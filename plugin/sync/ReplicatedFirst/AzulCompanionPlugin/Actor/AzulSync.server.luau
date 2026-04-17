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
local WebSocketClient = require("../WebSocketClient")
local UI = require("../UI")
local CONFIG = require("../Config")
local Enums = require("../Enums")
local AzulService = require("../AzulService")
local SettingsStore = require("../SettingsStore")

-- Settings
local PUSH_CONFIG_PATH = {
	"ServerStorage",
	"Azul",
	"Config",
}

-- Logging helpers
local function debugPrint(...)
	if CONFIG.SILENT_MODE or not CONFIG.DEBUG_MODE then return end
	print(`[🐛 Azul]:`, ...)
end

local function infoPrint(...)
	if CONFIG.SILENT_MODE then return end
	print(`[Azul]:	`, ...)
end

local settingsStore = SettingsStore.new(plugin, CONFIG, Enums.scope, {
	defaultScope = Enums.scope.GLOBAL,
})

--- Utility: Safely get a positive number from config, with fallback
local function safeGetNumber(value, default)
	if type(value) == "number" and value > 0 then return value end
	return default
end

settingsStore:loadSettings()

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
local pendingScriptChangeReady = {}
local scriptChangeDebounceTokenByGuid = {}
local pendingDeletes = {}

local batchingEnabled = false
local batchFlushToken = 0 -- Incremented to invalidate pending flush timers
local batchAccumulator = 0

-- Legacy! Does not get used after initial snapshot!
local BATCH_INTERVAL = 0.2 -- Seconds between outbound batch flushes

local serviceSet = {}

AzulService.rebuildServiceSet(serviceSet)

-- Utility: Check if instance should be included in snapshot (all instances)
local function shouldIncludeInSnapshot(instance)
	if not instance then return false end

	return not AzulService.isExcluded(instance, serviceSet)
end

-- Send message to daemon
local function sendMessage(messageTypeOrPayload, data: any?)
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
		table.clear(pendingScriptChangeReady)
		table.clear(scriptChangeDebounceTokenByGuid)
		table.clear(pendingDeletes)
	end
end

-- Send full snapshot
local function sendFullSnapshot(options: { includeProperties: boolean, scriptsAndDescendantsOnly: boolean }?)
	infoPrint("Sending full snapshot...")

	local includeProperties = options and options.includeProperties == true
	local scriptsAndDescendantsOnly = options and options.scriptsAndDescendantsOnly == true
	local includeAncestorsOfScripts: { [Instance]: boolean } = {}

	if scriptsAndDescendantsOnly then
		for _, descendant in ipairs(game:GetDescendants()) do
			if AzulService.isScript(descendant) and shouldIncludeInSnapshot(descendant) then
				local current: Instance? = descendant
				while current and current ~= game do
					if shouldIncludeInSnapshot(current) then includeAncestorsOfScripts[current] = true end
					current = current.Parent
				end
			end
		end
	end

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
		if shouldIncludeInSnapshot(service) then
			table.insert(queue, {
				instance = service,
				hasScriptAncestor = false,
			})
		end
	end

	local index = 1
	while index <= #queue do
		if not syncEnabled then
			infoPrint("Snapshot aborted - sync disabled")
			return
		end

		local queued = queue[index]
		local instance = queued.instance
		local hasScriptAncestor = queued.hasScriptAncestor == true

		local includeByMode = true
		if scriptsAndDescendantsOnly then
			includeByMode = AzulService.isScript(instance)
				or hasScriptAncestor
				or includeAncestorsOfScripts[instance] == true
		end

		if shouldIncludeInSnapshot(instance) and includeByMode then
			local data = AzulService.instanceToData(instance, trackedInstances, guidMap, usedGuids, {
				includeProperties = includeProperties,
			})
			if data then
				table.insert(instances, data)

				trackedInstances[instance] = data.guid
				guidMap[data.guid] = instance

				if AzulService.isScript(instance) then
					scriptCount += 1
				end
			end
		end

		-- Enqueue children that are eligible for traversal
		for _, child in ipairs(instance:GetChildren()) do
			if shouldIncludeInSnapshot(child) then
				table.insert(queue, {
					instance = child,
					hasScriptAncestor = hasScriptAncestor or AzulService.isScript(instance),
				})
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
		if includeProperties or scriptsAndDescendantsOnly then
			debugPrint(
				`Snapshot sent with options (includeProperties={tostring(includeProperties)}, scriptsAndDescendantsOnly={tostring(
					scriptsAndDescendantsOnly
				)}) - stopping sync since "pack" is one-shot.`
			)
			stopSync()
		end

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
		if pendingScriptChangeReady[payload.guid] == true then
			table.insert(messages, {
				type = "scriptChanged",
				data = {
					guid = payload.guid,
					path = payload.path,
					className = payload.className,
					source = payload.source,
				},
			})
			pendingScriptChanges[payload.guid] = nil
			pendingScriptChangeReady[payload.guid] = nil
			scriptChangeDebounceTokenByGuid[payload.guid] = nil
		end
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

	task.delay(safeGetNumber(CONFIG.BATCH_IDLE_WINDOW, 0.1), function()
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

	pendingScriptChangeReady[payload.guid] = false
	pendingScriptChanges[payload.guid] = payload

	local token = (scriptChangeDebounceTokenByGuid[payload.guid] or 0) + 1
	scriptChangeDebounceTokenByGuid[payload.guid] = token

	task.delay(safeGetNumber(CONFIG.SCRIPT_CHANGE_DEBOUNCE, 0.35), function()
		if not syncEnabled or suppressOutbound then return end
		if scriptChangeDebounceTokenByGuid[payload.guid] ~= token then return end
		if not pendingScriptChanges[payload.guid] then return end

		pendingScriptChangeReady[payload.guid] = true
		scheduleBatchFlush()
	end)
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
	if not AzulService.isScript(instance) then return false end

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
	if AzulService.isScript(instance) then
		local sourceConnection = (instance :: Script):GetPropertyChangedSignal("Source"):Connect(function()
			if syncEnabled then onScriptChanged(instance :: Script) end
		end)
		table.insert(connections, sourceConnection)
	end
end

local function wipeChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if AzulService.isProtectedRobloxContainer(child) then continue end
		local ok, err = pcall(function()
			child:Destroy()
		end)
		if not ok then warn(`[Azul]: Cannot destroy '{child.Name}': {err}`) end
	end
end

local function wipeBuildRoots(instances: { any })
	local rootsSeen = {}

	-- Collect root containers to wipe (optimize by avoiding redundant wipes on shared ancestors)
	for _, item in ipairs(instances) do
		local path = item.path
		if type(path) == "table" and #path >= 1 then
			local rootName = path[1]
			if type(rootName) == "string" and rootName ~= "" then rootsSeen[rootName] = true end
		end
	end

	for rootName in pairs(rootsSeen) do
		local rootInstance: Instance? = nil

		local okService, service = pcall(function()
			return game:GetService(rootName)
		end)
		if okService and service then
			rootInstance = service
		else
			rootInstance = game:FindFirstChild(rootName)
		end

		if rootInstance then
			local ok, err = pcall(function()
				wipeChildren(rootInstance)
			end)
			if not ok then warn(`[Azul]: Failed to wipe children for root container '{rootName}': {err}`) end
		else
			warn(`[Azul]: Destructive build could not find root container '{rootName}', skipping wipe`)
		end
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
		if instance and AzulService.isScript(instance) then
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
		sendFullSnapshot(message.options)
	elseif message.type == "buildSnapshot" then
		-- One-time push from filesystem into Studio
		infoPrint("Applying build snapshot from daemon")
		setOutboundSuppressed(true)

		local ok, err = pcall(function()
			if message.destructive == true then wipeBuildRoots(message.data or {}) end

			local created, updated, appliedGuidMap = AzulService.applySnapshotInstances(message.data)
			-- Update tracking with new instances
			for guid, instance in pairs(appliedGuidMap) do
				guidMap[guid] = instance
				trackedInstances[instance] = guid
				attachListeners(instance)
			end
			infoPrint(`Build snapshot applied ({created} created, {updated} updated)`)
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

				local created, updated, appliedGuidMap = AzulService.applySnapshotInstances(mapping.instances or {})
				-- Update tracking with new instances
				for guid, instance in pairs(appliedGuidMap) do
					guidMap[guid] = instance
					trackedInstances[instance] = guid
					attachListeners(instance)
				end
				infoPrint(`Push applied to {table.concat(destination, "/")} ({created} created, {updated} updated)`)
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
	elseif message.type == "daemonDisconnect" then
		infoPrint("Daemon is shutting down; disconnecting plugin")
		stopSync(true)
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
		local ok, err = pcall(function()
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
		if not ok then
			warn("[Azul]: Error during listener setup:", err)
			stopSync()
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
			if now - lastHeartbeat > safeGetNumber(CONFIG.HEARTBEAT_INTERVAL, 30) then
				if not sendMessage("ping", {}) then
					warn("[Azul]: Lost connection to daemon")
					stopSync()
					return
				end
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
function stopSync(dontRelayDisconnect: boolean?)
	if not syncEnabled then return end

	if not dontRelayDisconnect then sendMessage("clientDisconnect", {}) end

	infoPrint("Stopping sync...")
	syncEnabled = false

	if azulUI then azulUI:UpdateSyncState(false) end

	-- Close WebSocket connection
	if wsClient then wsClient:disconnect() end
	wsClient = nil :: any

	trackedInstances = {}
	guidMap = {}
	batchAccumulator = 0
	table.clear(pendingInstanceUpdates)
	table.clear(pendingScriptChanges)
	table.clear(pendingScriptChangeReady)
	table.clear(scriptChangeDebounceTokenByGuid)
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
	settingsStore:saveSettings()
	settingsStore:saveSelectedScope()
	stopSync()
end)

infoPrint("Plugin loaded. Click on the 'Azul' button to connect.")
debugPrint("Debug mode is enabled!")
debugPrint(`Service list type is set to: "{CONFIG.LIST_TYPE}"`)

-- Initialize UI
local uiCallbacks: UI.CallbackFunctions = {
	onStartSync = startSync,
	onStopSync = stopSync,
	onConfigChanged = function(key, value)
		debugPrint(`Config {key} updated to: {value}`)
	end,
	onSettingsScopeChanged = function(newScope)
		if newScope == settingsStore:getScope() then return end

		settingsStore:setScope(newScope)
		azulUI:SetSettingsScope(settingsStore:getScope())
		AzulService.rebuildServiceSet(serviceSet)
		azulUI:UpdateConfig()

		local scopeLabel = if settingsStore:getScope() == Enums.scope.GLOBAL then "Global" else "Project"
		infoPrint(`Settings scope set to {scopeLabel}`)
	end,

	onSourcemapReload = function()
		infoPrint("Reloading sourcemap...")
		sendFullSnapshot()
	end,
}

local uiHelpers = {
	debugPrint = debugPrint,
	infoPrint = infoPrint,
	rebuildServiceSet = function()
		AzulService.rebuildServiceSet(serviceSet)
	end,
}

azulUI = UI.new(plugin, uiCallbacks, settingsStore:getScope(), uiHelpers)

-- applyConfigToUI = function()
-- 	if azulUI then azulUI:UpdateConfig() end
-- end
