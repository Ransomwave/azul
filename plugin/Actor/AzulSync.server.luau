--[[
	Azul - Roblox Studio Plugin.
	Companion plugin for Azul to sync scripts between Roblox Studio and external editors.

	Ransomwave 2025
]]

-- Services
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")

-- Prevent from running if the game is being Playtested
if RunService:IsRunning() then return end

local pluginParent = script.Parent
if not pluginParent then return end
local azulPluginFolder = pluginParent.Parent
if not azulPluginFolder then return end

-- Modules
local WebSocketClient = require(azulPluginFolder.WebSocketClient)
local UI = require(azulPluginFolder.UI)

local enum = {
	listType = {
		WHITELIST = "WHITELIST",
		BLACKLIST = "BLACKLIST",
	},

	scope = {
		GLOBAL = "global",
		PROJECT = "project",
	},
}

-- Configuration
local CONFIG = {
	WS_URL = "ws://localhost:8080",
	HEARTBEAT_INTERVAL = 30,
	LIST_TYPE = enum.listType.WHITELIST, -- or BLACKLIST
	SERVICE_LIST = {
		"Workspace",
		"Lighting",
		"ReplicatedFirst",
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterGui",
		"StarterPack",
		"StarterPlayer",
		"SoundService",
	},

	EXCLUDED_PARENTS = {
		"ServerStorage.RecPlugins", -- Folder managed by "Eye" plugin. It updates the sourcemap thousands of times. We don't need to track this.
		"Workspace.Surface Converter Storage", -- Folder managed by "Surface Converter" plugin. We don't need to track it.
	},

	DEBUG_MODE = false,
	SILENT_MODE = false,
}

local PUSH_CONFIG_PATH = {
	"ServerStorage",
	"Azul",
	"Config",
}

local SETTINGS_SCOPE = enum.scope.GLOBAL -- or "project"
local SETTINGS_KEY = "AZUL_SETTINGS"

-- Logging helpers
local function debugPrint(...)
	if CONFIG.SILENT_MODE or not CONFIG.DEBUG_MODE then return end
	print(...)
end

local function infoPrint(...)
	if CONFIG.SILENT_MODE then return end
	print(...)
end

local function getScopeKey(scope)
	local placeId = tostring(game.PlaceId or "0")
	if scope == enum.scope.PROJECT then return `project_{placeId}` end
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

local LOGO = "rbxassetid://134336592598474" -- Azul logo asset ID
local LOGO_SYNCED = "rbxassetid://103599828888609" -- Sync icon asset ID

-- Plugin state
-- local plugin = plugin
-- local toolbar = plugin:CreateToolbar("Azul")
-- local connectButton = toolbar:CreateButton("Azul", "Connect/disconnect from sync daemon", LOGO)

-- Sync state
local syncEnabled = false
local wsClient = nil
local trackedInstances = {}
local guidMap = {}
local usedGuids = {}
local lastHeartbeat = 0
local batchAccumulator = 0
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

local BATCH_INTERVAL = 0.2 -- Seconds between outbound batch flushes
local BATCH_IDLE_WINDOW = 0.1 -- Seconds of inactivity before sending batch

-- Utility: Clear all GUID attributes
-- This is for legacy support; we now use :GetDebugId() for stable GUIDs
local function clearAllGUIDAttributes()
	local guidAttributeName = plugin:GetSetting("GUID_ATTRIBUTE") or "AzulSyncGUID"

	for _, instance in game:GetDescendants() do
		if instance:GetAttribute(guidAttributeName) then instance:SetAttribute(guidAttributeName, nil) end
	end
	infoPrint("[Azul]: Cleared all legacy GUID attributes from instances.")
end

-- Utility: Check if instance is a script
local function isScript(instance)
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

local serviceSet = {}
-- Utility: Rebuild service set from config
local function rebuildServiceSet()
	table.clear(serviceSet)
	for _, name in ipairs(CONFIG.SERVICE_LIST) do
		serviceSet[name] = true
	end
end

rebuildServiceSet()

-- Utility: Check if instance should be excluded from sync
local function isExcluded(instance: Instance)
	if not instance then return true end

	local fullName = instance:GetFullName()
	for _, ancestorName in CONFIG.EXCLUDED_PARENTS do
		if fullName:find(ancestorName) then return true end
	end

	-- Walk up to the service
	local current = instance
	while current do
		if current.Parent == game then
			local inList = serviceSet[current.Name] ~= nil

			if CONFIG.LIST_TYPE == enum.listType.WHITELIST then
				-- Whitelist: only allow services in the list
				-- debugPrint(`[🐛 Azul]: Included {instance} in whitelist`)
				return not inList
			else
				-- Blacklist: exclude services in the list
				-- debugPrint(`[🐛 Azul]: Excluded {instance} in blacklist`)
				return inList
			end
		end
		current = current.Parent
	end

	-- Not under DataModel
	return true
end

local function getOrCreatePath(pathSegments: { string }): Instance
	local current: Instance = game
	for index, segment in ipairs(pathSegments) do
		local nextNode = current:FindFirstChild(segment)

		if not nextNode then
			if index == 1 then
				local ok, service = pcall(function()
					return game:GetService(segment)
				end)
				if ok and service then nextNode = service end
			end

			if not nextNode then
				nextNode = Instance.new("Folder")
				nextNode.Name = segment
				nextNode.Parent = current
			end
		end

		current = nextNode
	end

	return current
end

local function isProtectedRobloxContainer(instance: Instance?): boolean
	if not instance then return false end

	-- Top-level services cannot be destroyed or reparented
	local okService = pcall(function()
		return game:GetService(instance.Name)
	end)
	if instance.Parent == game and okService then return true end

	-- Certain StarterPlayer children are locked (StarterPlayerScripts, StarterCharacterScripts, StarterGear)
	local parent = instance.Parent
	if parent and parent.ClassName == "StarterPlayer" then
		local name = instance.Name
		if name == "StarterPlayerScripts" or name == "StarterCharacterScripts" or name == "StarterGear" then
			return true
		end
	end

	return false
end

-- Utility: Check if instance should be included in snapshot (all instances)
local function shouldIncludeInSnapshot(instance)
	if not instance then return false end

	return not isExcluded(instance)
end

-- Utility: Generate or retrieve GUID for instance (use Roblox debug IDs to avoid attribute churn)
local function getOrCreateGUID(instance)
	local cached = trackedInstances[instance]
	if cached then return cached end

	local guid = instance:GetDebugId(0)
	trackedInstances[instance] = guid
	guidMap[guid] = instance
	usedGuids[guid] = true
	return guid
end

-- Utility: Get instance path
local function getInstancePath(instance)
	local path = {}
	local current = instance

	while current and current ~= game do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	-- If current became nil, the instance is no longer under DataModel
	if current ~= game then return nil end

	return path
end

-- Convert instance to data format
local function instanceToData(instance)
	local guid = getOrCreateGUID(instance)
	local path = getInstancePath(instance)
	if not path then return nil end

	local parentGuid: string? = nil
	local parent = instance.Parent
	if parent then
		if parent == game then
			parentGuid = "root"
		else
			parentGuid = getOrCreateGUID(parent)
		end
	end

	local data = {
		guid = guid,
		className = instance.ClassName,
		name = instance.Name,
		path = path,
		parentGuid = parentGuid,
	}

	if isScript(instance) then data.source = instance.Source end

	return data
end

-- Utility: set script source safely (handles large sources via ScriptEditorService)
local function setScriptSource(scriptInstance: Script | LocalScript | ModuleScript, source: string)
	local ok, err = pcall(function()
		if ScriptEditorService and ScriptEditorService.UpdateSourceAsync then
			ScriptEditorService:UpdateSourceAsync(scriptInstance, function(...)
				return source
			end)
		else
			(scriptInstance :: Script).Source = source
		end
	end)

	if not ok then warn("[Azul]: Failed to set script source", err) end

	return ok
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

	debugPrint(`[🐛 Azul]: Sending message: {message.type}`)

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

-- Queue and batch outbound messages to reduce chatter
local function flushOutboundQueues()
	local messages = {}

	for _, data in pairs(pendingInstanceUpdates) do
		table.insert(messages, {
			type = "instanceUpdated",
			data = data,
		})
	end

	for _, payload in pairs(pendingScriptChanges) do
		table.insert(messages, {
			type = "scriptChanged",
			guid = payload.guid,
			path = payload.path,
			className = payload.className,
			source = payload.source,
		})
	end

	for guid, shouldSend in pairs(pendingDeletes) do
		if shouldSend then table.insert(messages, {
			type = "deleted",
			guid = guid,
		}) end
	end

	table.clear(pendingInstanceUpdates)
	table.clear(pendingScriptChanges)
	table.clear(pendingDeletes)

	if #messages == 0 then return end

	if batchingEnabled and #messages > 1 then
		sendMessage("batch", { messages = messages })
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

	local data = instanceToData(instance)
	if not data then return end

	local guid = data.guid
	local parentKey = data.parentGuid or ""
	local key = table.concat(data.path, "/") .. "|" .. data.className .. "|" .. data.name .. "|" .. parentKey
	local now = tick()
	local last = lastInstanceUpdate[guid]
	if last and last.key == key and now - last.t < 0.05 then
		-- Ignore duplicate bursts from multiple property signals firing at once
		return
	end
	lastInstanceUpdate[guid] = { key = key, t = now }

	trackedInstances[instance] = guid
	guidMap[guid] = instance

	queueInstanceUpdate(data)
end

-- Utility: Check if instance should be synced (scripts only)
local function shouldSync(instance)
	if not instance then return false end

	-- Only sync scripts
	if not isScript(instance) then return false end

	return not isExcluded(instance)
end

-- Handle script change
local function onScriptChanged(changedScript: Script | LocalScript | ModuleScript)
	if suppressOutbound or not shouldSync(changedScript) then return end

	local guid = getOrCreateGUID(changedScript)

	-- Don't send changes if this was just patched from daemon
	if recentPatches[guid] then
		debugPrint(
			"[🐛 Azul]: Ignoring change (was just patched from daemon):",
			`{changedScript.Parent}.{changedScript.Name}`
		)
		recentPatches[guid] = nil
		return
	end

	-- Don't send changes if we're applying a patch from daemon
	if applyingPatch then return end

	-- Don't send changes within 1 second of receiving a patch (debounce)
	local lastPatch = lastPatchTime[guid] or 0
	local now = tick()
	if now - lastPatch < 1 then
		debugPrint(
			"[🐛 Azul]: Ignoring change (too soon after patch):",
			`{changedScript.Parent}.{changedScript.Name}`
		)
		return
	end

	local path = getInstancePath(changedScript)
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
		local sourceConnection = instance:GetPropertyChangedSignal("Source"):Connect(function()
			if syncEnabled then onScriptChanged(instance) end
		end)
		table.insert(connections, sourceConnection)
	end
end

local function wipeChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if isProtectedRobloxContainer(child) then continue end
		child:Destroy()
	end
end

local function applySnapshotInstances(instances: { any }): number
	table.sort(instances, function(a, b)
		return #a.path < #b.path
	end)

	local lockedContainerParents = {
		StarterPlayerScripts = "StarterPlayer",
		StarterCharacterScripts = "StarterPlayer",
		StarterGear = "StarterPlayer",
	}

	local created = 0
	for _, item in ipairs(instances) do
		local adjustedPath = {}
		for i, segment in ipairs(item.path) do
			adjustedPath[i] = segment
		end

		local protectedContainerName: string? = nil
		local first = adjustedPath[1]
		local maybeParent = lockedContainerParents[first]
		if maybeParent and maybeParent ~= first then
			table.insert(adjustedPath, 1, maybeParent)
			protectedContainerName = adjustedPath[2]
		end

		if not protectedContainerName and #adjustedPath >= 2 then
			local second = adjustedPath[2]
			if lockedContainerParents[second] == adjustedPath[1] then protectedContainerName = second end
		end

		local serviceCandidate: Instance? = nil
		if #adjustedPath == 1 then
			local okService, service = pcall(function()
				return game:GetService(adjustedPath[1])
			end)
			if okService then serviceCandidate = service end
		end

		local parentPath = {}
		for i = 1, #adjustedPath - 1 do
			parentPath[i] = adjustedPath[i]
		end

		local parent = getOrCreatePath(parentPath)
		local existing = if serviceCandidate
			then serviceCandidate
			else parent:FindFirstChild(adjustedPath[#adjustedPath])
		local instance = existing

		local function isScriptClass(className: string)
			return className == "Script" or className == "LocalScript" or className == "ModuleScript"
		end

		if existing and existing.ClassName ~= item.className then
			local targetIsScript = isScriptClass(item.className)
			if targetIsScript then
				if isProtectedRobloxContainer(existing) then
					instance = existing
				else
					existing:Destroy()
					instance = nil
				end
			else
				instance = existing
			end
		end

		if not instance and protectedContainerName then
			local protectedParentName = lockedContainerParents[protectedContainerName]
			if protectedParentName then
				local okParent, protectedParent = pcall(function()
					return game:GetService(protectedParentName)
				end)
				if okParent and protectedParent then
					local protectedExisting = protectedParent:FindFirstChild(protectedContainerName)
					if protectedExisting then instance = protectedExisting end
				end
			end
		end

		if not instance then
			local newInstance
			local okNew, createdInstance = pcall(function()
				return Instance.new(item.className)
			end)
			if okNew and createdInstance then
				newInstance = createdInstance
			else
				newInstance = Instance.new("Folder")
			end
			newInstance.Name = adjustedPath[#adjustedPath]
			newInstance.Parent = parent
			instance = newInstance
			created += 1
		else
			if not serviceCandidate and not isProtectedRobloxContainer(instance) then
				instance.Name = adjustedPath[#adjustedPath]
			end
		end

		trackedInstances[instance] = item.guid
		guidMap[item.guid] = instance
		usedGuids[item.guid] = true

		if isScriptClass(item.className) and item.source then setScriptSource(instance :: Script, item.source) end

		attachListeners(instance)
	end

	return created
end

-- Locate the ModuleScript that carries push settings for this place
local function findPushConfigModule(): ModuleScript?
	local current: Instance = game
	for index, segment in ipairs(PUSH_CONFIG_PATH) do
		if index == 1 then
			local ok, service = pcall(function()
				return game:GetService(segment)
			end)
			if not ok or not service then return nil end
			current = service
		else
			local nextNode = current:FindFirstChild(segment)
			if not nextNode then return nil end
			current = nextNode
		end
	end

	if current and current:IsA("ModuleScript") then return current :: ModuleScript end

	return nil
end

-- Read and validate push config from ModuleScript
local function readPushConfig()
	local module = findPushConfigModule()
	if not module then return nil, "Push config ModuleScript not found" end

	-- Clone module to force require to refresh data
	local moduleClone = module:Clone()
	moduleClone.Parent = module.Parent
	module:Destroy()
	module = moduleClone
	--

	local ok, data = pcall(require, module)
	if not ok then return nil, `Failed to require push config: {data}` end

	if type(data) ~= "table" then return nil, "Push config is not a table" end

	debugPrint(`[🐛 Azul]: Push config loaded from {module}: {HttpService:JSONEncode(data)}`)

	local mappings = {}
	if type(data.pushMappings) == "table" then
		for _, entry in ipairs(data.pushMappings) do
			if type(entry) == "table" and type(entry.source) == "string" and type(entry.destination) == "table" then
				local dest = {}
				for _, seg in ipairs(entry.destination) do
					if type(seg) == "string" and seg ~= "" then table.insert(dest, seg) end
				end

				if #dest > 0 then
					table.insert(mappings, {
						source = entry.source,
						destination = dest,
						destructive = entry.destructive == true,
						rojoMode = entry.rojoMode == true,
					})
				end
			end
		end
	end

	local configPayload = {
		mappings = mappings,
		port = data.port,
		debugMode = data.debugMode,
		deleteOrphansOnConnect = data.deleteOrphansOnConnect,
	}

	return configPayload, nil
end

local function sendDaemonConfig(warnOnFail: boolean?)
	local configPayload, err = readPushConfig()
	if not configPayload then
		if warnOnFail then
			warn(`[Azul]: daemon config unavailable: {err}`)
		else
			debugPrint(`[🐛 Azul]: daemon config unavailable: {err}`)
		end
		return false
	end

	return sendMessage("pushConfig", {
		config = configPayload,
	})
end

-- Send full snapshot
local function sendFullSnapshot()
	infoPrint("[Azul]: Sending full snapshot...")

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
			infoPrint("[Azul]: Snapshot aborted - sync disabled")
			return
		end

		local instance = queue[index]

		if shouldIncludeInSnapshot(instance) then
			local data = instanceToData(instance)
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
	infoPrint("[Azul]: Snapshot sent:", #instances, "instances (", scriptCount, "scripts )")

	if syncEnabled then
		batchingEnabled = true
		batchFlushToken += 1 -- Invalidate any pre-snapshot timers
		batchAccumulator = 0
	end
end

-- Handle instance added
local function onInstanceAdded(instance: Instance)
	if suppressOutbound then return end
	-- Include all non-excluded instances (scripts + containers) so sourcemap stays accurate
	if not shouldIncludeInSnapshot(instance) then return end

	local data = instanceToData(instance)
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
		-- debugPrint(`[🐛 Azul]: Instance is excluded: {instance.Parent}.{instance.Name}`)
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
	debugPrint("[🐛 Azul]: Processing message type:", message.type)

	if message.type == "patchScript" then
		debugPrint("[🐛 Azul]: Patch requested for GUID:", message.guid)
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
			setScriptSource(instance, message.source)

			-- Keep flag set longer to cover any async events
			task.delay(0.2, function()
				applyingPatch = false
				setOutboundSuppressed(false)
			end)

			infoPrint("[Azul]: Updated script:", `{instance.Parent}.{instance.Name}`)

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
		infoPrint("[Azul]: Snapshot requested by daemon")
		sendFullSnapshot()
	elseif message.type == "buildSnapshot" then
		-- One-time push from filesystem into Studio
		infoPrint("[Azul]: Applying build snapshot from daemon")
		setOutboundSuppressed(true)
		local ok, err = pcall(function()
			local created = applySnapshotInstances(message.data)
			infoPrint(`[Azul]: Build snapshot applied ({created} created/updated)`)
		end)

		setOutboundSuppressed(false)
		if not ok then warn("[Azul]: Error applying build snapshot", err) end

		-- Disconnect after build completes (daemon will exit)
		task.delay(0.5, function()
			stopSync()
		end)
	elseif message.type == "pushSnapshot" then
		infoPrint("[Azul]: Applying push snapshot from daemon")
		setOutboundSuppressed(true)

		local ok, err = pcall(function()
			for _, mapping in ipairs(message.mappings or {}) do
				local destination = mapping.destination or {}
				if #destination == 0 then
					warn("[Azul]: Push mapping missing destination; skipping")
					continue
				end

				local targetContainer = getOrCreatePath(destination)
				if mapping.destructive then wipeChildren(targetContainer) end

				local created = applySnapshotInstances(mapping.instances or {})
				infoPrint(`[Azul]: Push applied to {table.concat(destination, "/")} ({created} created/updated)`)
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
		debugPrint("[🐛 Azul]: Received pong")
	else
		warn("[Azul]: Unknown message type:", message.type)
	end
end

-- Declare azulUI before using it
local azulUI

-- Start sync
local function startSync()
	if syncEnabled then return end

	infoPrint("[Azul]: Starting sync...")
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
		infoPrint("[Azul]: Connected to daemon")
		-- Send initial snapshot after connection
		sendDaemonConfig()
	end)

	-- Set up disconnect handler
	wsClient:on("disconnect", function()
		infoPrint("[Azul]: Disconnected from daemon")
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

	infoPrint("[Azul]: Sync enabled")
end

-- Stop sync
function stopSync()
	if not syncEnabled then return end

	sendMessage("clientDisconnect", {})

	infoPrint("[Azul]: Stopping sync...")
	syncEnabled = false

	if azulUI then azulUI:UpdateSyncState(false) end

	-- Close WebSocket connection
	if wsClient then
		wsClient:disconnect()
		wsClient = nil
	end

	-- Clear GUID attributes if configured
	if CONFIG.CLEAR_GUIDS_ON_EXIT then
		clearAllGUIDAttributes()
		infoPrint("[Azul]: Cleared all GUID attributes")
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

	infoPrint("[Azul]: Sync stopped")
end

-- Cleanup on plugin unload
plugin.Unloading:Connect(function()
	saveSettings()
	stopSync()
end)

infoPrint("[Azul]: Plugin loaded. Click on the 'Azul' button to connect.")
debugPrint("[🐛 Azul]: Debug mode is enabled!")
debugPrint(`[🐛 Azul]: Service list type is set to: "{CONFIG.LIST_TYPE}"`)

-- Initialize UI
local uiCallbacks = {
	onStartSync = startSync,
	onStopSync = stopSync,
	onConfigChanged = function(key, value)
		debugPrint(`[🐛 Azul]: Config {key} updated to: {value}`)
	end,
	onSettingsScopeChanged = function(newScope)
		local newScopeIsGlobal = newScope == enum.scope.GLOBAL
		if newScopeIsGlobal == (SETTINGS_SCOPE == enum.scope.GLOBAL) then return end

		-- Persist the current scope before switching
		saveSettings()
		SETTINGS_SCOPE = newScope
		azulUI:SetSettingsScope(SETTINGS_SCOPE)
		loadSettings()
		rebuildServiceSet()
		azulUI:UpdateConfig()

		local scopeLabel = if SETTINGS_SCOPE == enum.scope.GLOBAL then "Global" else "Project"
		infoPrint(`[Azul]: Settings scope set to {scopeLabel}`)
	end,
	onClearGuids = clearAllGUIDAttributes,
}

local uiConstants = {
	LOGO = LOGO,
	LOGO_SYNCED = LOGO_SYNCED,
	SETTINGS_SCOPE = SETTINGS_SCOPE,
}

local uiHelpers = {
	debugPrint = debugPrint,
	infoPrint = infoPrint,
	saveSettings = saveSettings,
	loadSettings = loadSettings,
	rebuildServiceSet = rebuildServiceSet,
}

azulUI = UI.new(plugin, CONFIG, enum, uiCallbacks, uiConstants, uiHelpers)

applyConfigToUI = function()
	if azulUI then azulUI:UpdateConfig() end
end
