--!strict
--[[
	Azul - Roblox Studio Plugin.
	Companion plugin for Azul to sync scripts between Roblox Studio and external editors.

	Ransomwave 2025
]]

-- Services
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- Prevent from running if the game is being Playtested
if RunService:IsRunning() then return end

local pluginParent = script.Parent
if not pluginParent then return end
local azulPluginFolder = pluginParent.Parent
if not azulPluginFolder then return end

-- Modules
local WebSocketClient = require(azulPluginFolder.WebSocketClient)
local UI = require(azulPluginFolder.UI)
local CONFIG = require(azulPluginFolder.Config)
local Enums = require(azulPluginFolder.Enums)
local AzulService = require(azulPluginFolder.AzulService)

-- Settings
local PUSH_CONFIG_PATH = {
	"ServerStorage",
	"Azul",
	"Config",
}

local SETTINGS_SCOPE = Enums.scope.GLOBAL -- or "project"
local SETTINGS_KEY = "AZUL_SETTINGS"

-- Logging helpers
local function debugPrint(...)
	if CONFIG.SILENT_MODE or not CONFIG.DEBUG_MODE then return end
	print(`[🐛 Azul]:`, ...)
end

local function infoPrint(...)
	if CONFIG.SILENT_MODE then return end
	print(`[Azul]:	`, ...)
end

local function getScopeKey(scope)
	local placeId = tostring(game.PlaceId or "0")
	if scope == Enums.scope.PROJECT then return `project_{placeId}` end
	return "global"
end

local _storedSettings = {}

-- Save settings
local function saveSettings()
	local all = plugin:GetSetting(SETTINGS_KEY)
	if type(all) ~= "table" then all = {} end

	local scopeKey = getScopeKey(SETTINGS_SCOPE)
	local scopedCopy = {}
	for key, value in pairs(CONFIG) do
		scopedCopy[key] = value
	end

	-- Always persist debug/silent at the global level
	local globalScoped = all["global"]
	if type(globalScoped) ~= "table" then globalScoped = {} end
	globalScoped.DEBUG_MODE = CONFIG.DEBUG_MODE
	globalScoped.SILENT_MODE = CONFIG.SILENT_MODE
	all["global"] = globalScoped

	all[scopeKey] = scopedCopy
	_storedSettings = all
	plugin:SetSetting(SETTINGS_KEY, all)
end

local function loadSettings()
	local all = plugin:GetSetting(SETTINGS_KEY)
	if type(all) ~= "table" then
		all = {}
		-- Legacy flat settings fallback
		for key, _ in pairs(CONFIG) do
			local legacyValue = plugin:GetSetting(key)
			if legacyValue ~= nil then CONFIG[key] = legacyValue end
		end
		_storedSettings = all
		return
	end

	_storedSettings = all
	local scopeKey = getScopeKey(SETTINGS_SCOPE)
	local scoped = all[scopeKey]
	local globalScoped = all["global"]

	if type(scoped) ~= "table" then scoped = {} end
	if type(globalScoped) ~= "table" then globalScoped = {} end

	for key, _ in pairs(CONFIG) do
		local value = scoped[key]
		if value == nil and scopeKey ~= "global" then value = globalScoped[key] end
		if value ~= nil then CONFIG[key] = value end
	end

	-- DEBUG_MODE and SILENT_MODE always come from global
	if globalScoped.DEBUG_MODE ~= nil then CONFIG.DEBUG_MODE = globalScoped.DEBUG_MODE end
	if globalScoped.SILENT_MODE ~= nil then CONFIG.SILENT_MODE = globalScoped.SILENT_MODE end
end

loadSettings()

-- Sync state
local syncEnabled = false
local wsClient = nil
local trackedInstances = {}
local guidMap = {}
local usedGuids = {}
local lastHeartbeat = 0
local applyingPatch = false
local lastPatchTime = {} -- Track last patch time per GUID to prevent loops
local recentPatches = {} -- Track which scripts were recently patched from daemon
local lastInstanceUpdate = {} -- Deduplicate identical rapid instanceUpdated payloads per GUID
local connections = {}
local suppressOutbound = false -- Prevent emitting events while applying inbound patches

local pendingInstanceUpdates = {}
local pendingScriptChanges = {}
local pendingDeletes = {}

local batchingEnabled = false
local batchFlushToken = 0 -- Incremented to invalidate pending flush timers
local batchAccumulator = 0

local BATCH_INTERVAL = 0.2 -- Seconds between outbound batch flushes
local BATCH_IDLE_WINDOW = 0.1 -- Seconds of inactivity before sending batch

-- Utility: Check if instance is a script
local function isScript(instance)
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

local serviceSet = {}

AzulService.rebuildServiceSet(serviceSet)

-- Utility: Check if instance should be included in snapshot (all instances)
local function shouldIncludeInSnapshot(instance)
	if not instance then return false end

	return not AzulService.isExcluded(instance, serviceSet)
end

-- Send message to daemon
local function sendMessage(messageTypeOrPayload, data)
	if not wsClient or not wsClient.connected then return false end

	local message
	if type(messageTypeOrPayload) == "table" then
		message = {}
		for key, value in pairs(messageTypeOrPayload) do
			message[key] = value
		end
	else
		message = {
			type = messageTypeOrPayload,
		}
		for key, value in pairs(data or {}) do
			message[key] = value
		end
	end

	debugPrint(`Sending message: {message.type}`)

	local json = HttpService:JSONEncode(message)
	return wsClient:send(json)
end

-- Toggle outbound emission (used while applying inbound patches)
local function setOutboundSuppressed(suppressed: boolean)
	suppressOutbound = suppressed
	if suppressed then
		-- Drop any pending outbound changes to avoid echoing daemon writes
		table.clear(pendingInstanceUpdates)
		table.clear(pendingScriptChanges)
		table.clear(pendingDeletes)
	end
end

-- Send full snapshot
local function sendFullSnapshot()
	infoPrint("Sending full snapshot...")

	-- Reset tracking to ensure fresh GUID deduping
	trackedInstances = {}
	guidMap = {}
	usedGuids = {}

	local instances = {}
	local scriptCount = 0
	local batchSize = 400 -- Yield periodically to avoid plugin thread timeouts

	-- Build a queue to iterate without deep recursion
	local queue = {}
	for _, service in ipairs(game:GetChildren()) do
		if shouldIncludeInSnapshot(service) then table.insert(queue, service) end
	end

	local index = 1
	while index <= #queue do
		if not syncEnabled then
			infoPrint("Snapshot aborted - sync disabled")
			return
		end

		local instance = queue[index]

		if shouldIncludeInSnapshot(instance) then
			local data = AzulService.instanceToData(instance, trackedInstances, guidMap, usedGuids)
			if data then
				table.insert(instances, data)

				trackedInstances[instance] = data.guid
				guidMap[data.guid] = instance

				if isScript(instance) then
					scriptCount += 1
				end
			end

			-- Enqueue children that are eligible for snapshot
			for _, child in ipairs(instance:GetChildren()) do
				if shouldIncludeInSnapshot(child) then table.insert(queue, child) end
			end
		end

		-- Yield periodically to avoid hitting Studio's execution time limit
		if index % batchSize == 0 then task.wait() end

		index += 1
	end

	-- Send snapshot
	sendMessage("fullSnapshot", { data = instances })
	infoPrint("Snapshot sent:", #instances, "instances (", scriptCount, "scripts )")

	if syncEnabled then
		batchingEnabled = true
		batchFlushToken += 1 -- Invalidate any pre-snapshot timers
		batchAccumulator = 0
	end
end

-- Queue and batch outbound messages to reduce chatter
local function flushOutboundQueues()
	local messages: { [number]: { type: string, data: any } } = {}

	for _, data in pairs(pendingInstanceUpdates) do
		table.insert(messages, {
			type = "instanceUpdated",
			data = data,
		})
	end

	for _, payload in pairs(pendingScriptChanges) do
		table.insert(messages, {
			type = "scriptChanged",
			data = {
				guid = payload.guid,
				path = payload.path,
				className = payload.className,
				source = payload.source,
			},
		})
	end

	for guid, shouldSend in pairs(pendingDeletes) do
		if shouldSend then table.insert(messages, {
			type = "deleted",
			data = {
				guid = guid,
			},
		}) end
	end

	table.clear(pendingInstanceUpdates)
	table.clear(pendingScriptChanges)
	table.clear(pendingDeletes)

	if #messages == 0 then return end

	if batchingEnabled and #messages > 1 then
		if #messages > 200 then
			debugPrint(`Too many messages ({#messages}) in batch, sending full snapshot instead.`)
			sendFullSnapshot()
		else
			sendMessage("batch", { messages = messages })
		end
	else
		for _, message in ipairs(messages) do
			sendMessage(message)
		end
	end
end

-- Schedule a batch flush after a quiet window
local function scheduleBatchFlush()
	if not batchingEnabled then return end

	batchFlushToken += 1
	local token = batchFlushToken

	task.delay(BATCH_IDLE_WINDOW, function()
		if token ~= batchFlushToken then return end
		flushOutboundQueues()
	end)
end

local function queueInstanceUpdate(data)
	if suppressOutbound or not syncEnabled then return end
	if not data or not data.guid then return end

	pendingInstanceUpdates[data.guid] = data
	scheduleBatchFlush()
end

local function queueScriptChange(payload)
	if suppressOutbound or not syncEnabled then return end
	if not payload or not payload.guid then return end

	pendingScriptChanges[payload.guid] = payload
	scheduleBatchFlush()
end

local function queueDeletion(guid: string)
	if suppressOutbound or not syncEnabled then return end
	if not guid or guid == "" then return end

	pendingDeletes[guid] = true
	scheduleBatchFlush()
end

-- Deduped instance update sender (used for adds, renames, reparent)
local function sendInstanceUpdateDedup(instance)
	if suppressOutbound or not syncEnabled then return end

	local data = AzulService.instanceToDataDedup(instance, trackedInstances, guidMap, usedGuids, lastInstanceUpdate)
	if not data then return end

	local guid = data.guid
	trackedInstances[instance] = guid
	guidMap[guid] = instance

	queueInstanceUpdate(data)
end

-- Utility: Check if instance should be synced (scripts only)
local function shouldSync(instance)
	if not instance then return false end

	-- Only sync scripts
	if not isScript(instance) then return false end

	return not AzulService.isExcluded(instance, serviceSet)
end

-- Handle script change
local function onScriptChanged(changedScript: Script | LocalScript | ModuleScript)
	if suppressOutbound or not shouldSync(changedScript) then return end

	local guid = AzulService.getOrCreateGUID(changedScript, trackedInstances, guidMap, usedGuids)

	-- Don't send changes if this was just patched from daemon
	if recentPatches[guid] then
		debugPrint("Ignoring change (was just patched from daemon):", `{changedScript.Parent}.{changedScript.Name}`)
		recentPatches[guid] = nil
		return
	end

	-- Don't send changes if we're applying a patch from daemon
	if applyingPatch then return end

	-- Don't send changes within 1 second of receiving a patch (debounce)
	local lastPatch = lastPatchTime[guid] or 0
	local now = tick()
	if now - lastPatch < 1 then
		debugPrint("Ignoring change (too soon after patch):", `{changedScript.Parent}.{changedScript.Name}`)
		return
	end

	local path = AzulService.getInstancePath(changedScript)
	if not path then return end

	queueScriptChange({
		guid = guid,
		path = path,
		className = changedScript.ClassName,
		source = changedScript.Source,
	})
end

-- Utility: register change listeners on an instance for name/parent/source updates
local function attachListeners(instance)
	if not shouldIncludeInSnapshot(instance) then return end

	-- Name changes should propagate to daemon (renames / path changes)
	local nameConnnection = instance:GetPropertyChangedSignal("Name"):Connect(function()
		sendInstanceUpdateDedup(instance)
	end)

	table.insert(connections, nameConnnection)

	-- Parent changes (reparent/move) also change path
	local parentConnection = instance:GetPropertyChangedSignal("Parent"):Connect(function()
		-- If parent is nil (destroy in progress), rely on DescendantRemoving -> deleted
		if instance.Parent == nil then return end
		sendInstanceUpdateDedup(instance)
	end)

	table.insert(connections, parentConnection)

	-- Source changes (scripts only)
	if isScript(instance) then
		local sourceConnection = (instance :: Script):GetPropertyChangedSignal("Source"):Connect(function()
			if syncEnabled then onScriptChanged(instance :: Script) end
		end)
		table.insert(connections, sourceConnection)
	end
end

local function wipeChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if AzulService.isProtectedRobloxContainer(child) then continue end
		child:Destroy()
	end
end

-- Locate the ModuleScript that carries push settings for this place

local function sendDaemonConfig(warnOnFail: boolean?)
	local configPayload, err = AzulService.readPushConfig(PUSH_CONFIG_PATH)
	if not configPayload then
		if warnOnFail then
			warn(`[Azul]: daemon config unavailable: {err}`)
		else
			debugPrint(`daemon config unavailable: {err}`)
		end
		return false
	end

	return sendMessage("pushConfig", {
		config = configPayload,
	})
end

-- Handle instance added
local function onInstanceAdded(instance: Instance)
	if suppressOutbound then return end
	-- Include all non-excluded instances (scripts + containers) so sourcemap stays accurate
	if not shouldIncludeInSnapshot(instance) then return end

	local data = AzulService.instanceToData(instance, trackedInstances, guidMap, usedGuids)
	if not data then return end
	-- local guid = data.guid
	sendInstanceUpdateDedup(instance)

	-- Track subsequent changes (rename/reparent/source)
	attachListeners(instance)

	-- Watch for source changes (scripts only)
	-- (handled inside attachListeners)
end

-- Handle instance removed
local function onInstanceRemoved(instance)
	if suppressOutbound then return end

	if not trackedInstances[instance] then
		-- debugPrint(`Instance is excluded: {instance.Parent}.{instance.Name}`)
		return
	end

	local guid = trackedInstances[instance]

	-- Fallback: if we never tracked this instance (edge cases), use debug id directly
	if not guid then guid = instance:GetDebugId(0) end

	if not guid then return end

	trackedInstances[instance] = nil
	guidMap[guid] = nil
	usedGuids[guid] = nil

	queueDeletion(guid)
end

-- Process incoming daemon message
local function processMessage(message)
	debugPrint("Processing message type:", message.type)

	if message.type == "patchScript" then
		debugPrint("Patch requested for GUID:", message.guid)
		-- Update script source
		local instance = guidMap[message.guid]
		if instance and isScript(instance) then
			setOutboundSuppressed(true)
			-- Mark this script as recently patched from daemon
			recentPatches[message.guid] = true

			-- Record patch time BEFORE applying to prevent echo
			lastPatchTime[message.guid] = tick()

			-- Update source (large scripts via ScriptEditorService)
			applyingPatch = true
			AzulService.setScriptSource(instance :: Script, message.source) -- We already checked isScript above, we can assert this cast

			-- Keep flag set longer to cover any async events
			task.delay(0.2, function()
				applyingPatch = false
				setOutboundSuppressed(false)
			end)

			infoPrint("Updated script:", `{instance.Parent}.{instance.Name}`)

			-- Clear the patch marker after editor refresh completes
			task.delay(0.2, function()
				task.wait(0.2)
				recentPatches[message.guid] = nil
			end)
		else
			warn("[Azul]: Cannot apply patch - instance not found for GUID:", message.guid)
			local count = 0
			for _ in pairs(guidMap) do
				count = count + 1
			end
			warn("[Azul]: Total tracked instances:", count)
		end
	elseif message.type == "requestSnapshot" then
		-- Daemon is requesting a full snapshot
		infoPrint("Snapshot requested by daemon")
		sendFullSnapshot()
	elseif message.type == "buildSnapshot" then
		-- One-time push from filesystem into Studio
		infoPrint("Applying build snapshot from daemon")
		setOutboundSuppressed(true)
		local ok, err = pcall(function()
			local created = AzulService.applySnapshotInstances(message.data)
			-- Update tracking with new instances
			for _, item in ipairs(message.data or {}) do
				local instance = guidMap[item.guid]
				if instance then
					trackedInstances[instance] = item.guid
					attachListeners(instance)
				end
			end
			infoPrint(`Build snapshot applied ({created} created/updated)`)
		end)

		setOutboundSuppressed(false)
		if not ok then warn("[Azul]: Error applying build snapshot", err) end

		-- Disconnect after build completes (daemon will exit)
		task.delay(0.5, function()
			stopSync()
		end)
	elseif message.type == "pushSnapshot" then
		infoPrint("Applying push snapshot from daemon")
		setOutboundSuppressed(true)

		local ok, err = pcall(function()
			for _, mapping in ipairs(message.mappings or {}) do
				local destination = mapping.destination or {}
				if #destination == 0 then
					warn("[Azul]: Push mapping missing destination; skipping")
					continue
				end

				local targetContainer = AzulService.getOrCreatePath(destination)
				if mapping.destructive then wipeChildren(targetContainer) end

				local created = AzulService.applySnapshotInstances(mapping.instances or {})
				-- Update tracking with new instances
				for _, item in ipairs(mapping.instances or {}) do
					local instance = guidMap[item.guid]
					if instance then
						trackedInstances[instance] = item.guid
						attachListeners(instance)
					end
				end
				infoPrint(`Push applied to {table.concat(destination, "/")} ({created} created/updated)`)
			end
		end)

		setOutboundSuppressed(false)
		if not ok then warn("[Azul]: Error applying push snapshot", err) end

		-- Disconnect after push completes (daemon will exit)
		task.delay(0.5, function()
			stopSync()
		end)
	elseif message.type == "requestPushConfig" then
		sendDaemonConfig(true)
	elseif message.type == "error" then
		warn("[Azul]: Daemon error:", message.message)
	elseif message.type == "pong" then
		-- Heartbeat response
		debugPrint("Received pong")
	else
		warn("[Azul]: Unknown message type:", message.type)
	end
end

-- Declare azulUI before using it
local azulUI

-- Start sync
local function startSync()
	if syncEnabled then return end

	infoPrint("Starting sync...")
	syncEnabled = true
	batchingEnabled = false
	batchFlushToken += 1

	if azulUI then azulUI:UpdateSyncState(true) end

	-- Create and connect WebSocket client
	wsClient = WebSocketClient.new(CONFIG.WS_URL, {
		debugMode = CONFIG.DEBUG_MODE,
		silentMode = CONFIG.SILENT_MODE,
	})

	-- Set up message handler
	wsClient:on("message", function(message)
		processMessage(message)
	end)

	-- Set up connection handler
	wsClient:on("connect", function()
		infoPrint("Connected to daemon")
		-- Send initial snapshot after connection
		sendDaemonConfig()
	end)

	-- Set up disconnect handler
	wsClient:on("disconnect", function()
		infoPrint("Disconnected from daemon")
		stopSync()
	end)

	-- Set up error handler
	wsClient:on("error", function(error)
		warn("[Azul]: Connection error:", error)
	end)

	-- Connect to daemon
	local connected = wsClient:connect()

	if not connected then
		warn("[Azul]: Failed to connect to daemon")
		stopSync()
		return
	end

	-- Defer listener setup to avoid blocking
	task.defer(function()
		-- Setup listeners for existing instances
		local function setupListeners(parent)
			for _, child in ipairs(parent:GetChildren()) do
				attachListeners(child)
				setupListeners(child)
			end
		end

		for _, service in ipairs(game:GetChildren()) do
			setupListeners(service)
			task.wait() -- Yield between services
		end
	end)

	-- Listen for new instances
	local descendantAddedConnection = game.DescendantAdded:Connect(function(instance)
		if syncEnabled then onInstanceAdded(instance) end
	end)
	table.insert(connections, descendantAddedConnection)

	-- Listen for removed instances
	local descendantRemovingConnection = game.DescendantRemoving:Connect(function(instance)
		if syncEnabled then onInstanceRemoved(instance) end
	end)
	table.insert(connections, descendantRemovingConnection)

	-- Start heartbeat
	local heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if syncEnabled then
			-- Send heartbeat periodically
			local now = os.time()
			if now - lastHeartbeat > CONFIG.HEARTBEAT_INTERVAL then
				sendMessage("ping", {})
				lastHeartbeat = now
			end

			if batchingEnabled then
				-- Batch flush uses an idle timer; heartbeat just keeps the client alive
			else
				-- Legacy fast path before initial snapshot: flush at a fixed interval
				batchAccumulator += dt
				if batchAccumulator >= BATCH_INTERVAL then
					batchAccumulator -= BATCH_INTERVAL
					flushOutboundQueues()
				end
			end
		end
	end)
	table.insert(connections, heartbeatConnection)

	infoPrint("Sync enabled")
end

-- Stop sync
function stopSync()
	if not syncEnabled then return end

	sendMessage("clientDisconnect", {})

	infoPrint("Stopping sync...")
	syncEnabled = false

	if azulUI then azulUI:UpdateSyncState(false) end

	-- Close WebSocket connection
	if wsClient then wsClient:disconnect() end
	wsClient = nil :: any

	-- Clear GUID attributes if configured
	if CONFIG.CLEAR_GUIDS_ON_EXIT then
		AzulService.clearAllGUIDAttributes()
		infoPrint("Cleared all GUID attributes")
	end

	trackedInstances = {}
	guidMap = {}
	batchAccumulator = 0
	table.clear(pendingInstanceUpdates)
	table.clear(pendingScriptChanges)
	table.clear(pendingDeletes)

	batchingEnabled = false
	batchFlushToken += 1

	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	connections = {}

	infoPrint("Sync stopped")
end

-- Cleanup on plugin unload
plugin.Unloading:Connect(function()
	saveSettings()
	stopSync()
end)

infoPrint("Plugin loaded. Click on the 'Azul' button to connect.")
debugPrint("Debug mode is enabled!")
debugPrint(`Service list type is set to: "{CONFIG.LIST_TYPE}"`)

-- Initialize UI
local uiCallbacks = {
	onStartSync = startSync,
	onStopSync = stopSync,
	onConfigChanged = function(key, value)
		debugPrint(`Config {key} updated to: {value}`)
	end,
	onSettingsScopeChanged = function(newScope)
		local newScopeIsGlobal = newScope == Enums.scope.GLOBAL
		if newScopeIsGlobal == (SETTINGS_SCOPE == Enums.scope.GLOBAL) then return end

		-- Persist the current scope before switching
		saveSettings()
		SETTINGS_SCOPE = newScope
		azulUI:SetSettingsScope(SETTINGS_SCOPE)
		loadSettings()
		AzulService.rebuildServiceSet(serviceSet)
		azulUI:UpdateConfig()

		local scopeLabel = if SETTINGS_SCOPE == Enums.scope.GLOBAL then "Global" else "Project"
		infoPrint(`Settings scope set to {scopeLabel}`)
	end,
	onClearGuids = AzulService.clearAllGUIDAttributes,
}

local uiHelpers = {
	debugPrint = debugPrint,
	infoPrint = infoPrint,
	saveSettings = saveSettings,
	loadSettings = loadSettings,
	rebuildServiceSet = function()
		AzulService.rebuildServiceSet(serviceSet)
	end,
}

azulUI = UI.new(plugin, uiCallbacks, SETTINGS_SCOPE, uiHelpers)

-- applyConfigToUI = function()
-- 	if azulUI then azulUI:UpdateConfig() end
-- end
