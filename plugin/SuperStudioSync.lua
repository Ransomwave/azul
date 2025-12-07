--[[
	Super Studio Sync - Roblox Studio Plugin
	
	This plugin keeps Studio scripts synchronized with a local filesystem
	via WebSocket connection to the desktop daemon.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")

-- Import WebSocket client
local WebSocketClient = require(script.Parent.WebSocketClient)

-- Configuration
local CONFIG = {
	WS_URL = "ws://localhost:8080",
	GUID_ATTRIBUTE = "StudioSyncGUID",
	HEARTBEAT_INTERVAL = 30,
	EXCLUDED_SERVICES = {
		"CoreGui",
		"CorePackages",
		"Players",
		"Chat",
		"LocalizationService",
		"TestService",
		"StudioService",
		"RobloxReplicatedStorage",
		"PluginGuiService",
		"Stats",
		"MemStorageService",
		"StylingService",
		"VisualizationModeService",
	},

	EXCLUDED_PARENTS = {
		"ServerStorage.RecPlugins", -- Folder managed by "Eye" plugin. It updates the sourcemap thousands of times. We don't need to track this.
	},
}

-- Plugin state
local plugin = plugin
local toolbar = plugin:CreateToolbar("Super Studio Sync")
local connectButton = toolbar:CreateButton(
	"Toggle Sync",
	"Connect/disconnect from sync daemon",
	"rbxasset://textures/ui/GuiImagePlaceholder.png"
)

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

-- Utility: Generate or retrieve GUID for instance
local function getOrCreateGUID(instance)
	local guid = instance:GetAttribute(CONFIG.GUID_ATTRIBUTE)

	-- If GUID is missing or collides with another instance, generate a fresh one
	if not guid or (usedGuids[guid] and guidMap[guid] and guidMap[guid] ~= instance) then
		repeat
			guid = HttpService:GenerateGUID(false):gsub("-", "")
		until not usedGuids[guid]
		instance:SetAttribute(CONFIG.GUID_ATTRIBUTE, guid)
	end

	-- Track usage to prevent future collisions
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

	return path
end

-- Utility: Check if instance is a script
local function isScript(instance)
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

-- Utility: Check if instance should be excluded from sync
local function isExcluded(instance)
	if not instance then
		return true
	end

	-- Check if instance is in an excluded service
	local current = instance
	while current do
		if current.Parent == game then
			-- This is a service, check if it's excluded
			for _, excludedService in ipairs(CONFIG.EXCLUDED_SERVICES) do
				if current.Name == excludedService then
					return true
				end
			end
		end
		current = current.Parent
	end

	return false
end

-- Utility: Check if instance should be synced (scripts only)
local function shouldSync(instance)
	if not instance then
		return false
	end

	-- Only sync scripts
	if not isScript(instance) then
		return false
	end

	return not isExcluded(instance)
end

-- Utility: Check if instance should be included in snapshot (all instances)
local function shouldIncludeInSnapshot(instance)
	if not instance then
		return false
	end

	return not isExcluded(instance)
end

-- Convert instance to data format
local function instanceToData(instance)
	local guid = getOrCreateGUID(instance)
	local path = getInstancePath(instance)

	local data = {
		guid = guid,
		className = instance.ClassName,
		name = instance.Name,
		path = path,
	}

	if isScript(instance) then
		data.source = instance.Source
	end

	return data
end

-- Send message to daemon
local function sendMessage(messageType, data)
	if not wsClient or not wsClient.connected then
		return false
	end

	local message = {
		type = messageType,
	}

	-- Merge data into message
	for k, v in pairs(data or {}) do
		message[k] = v
	end

	print(`[StudioSync] Sending message: {messageType}`)

	local json = HttpService:JSONEncode(message)
	return wsClient:send(json)
end

-- Send full snapshot
local function sendFullSnapshot()
	print("[StudioSync] Sending full snapshot...")

	-- Reset tracking to ensure fresh GUID deduping
	trackedInstances = {}
	guidMap = {}
	usedGuids = {}

	local instances = {}
	local scriptCount = 0

	-- Collect all instances from the DataModel (for sourcemap)
	local function collectInstances(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if shouldIncludeInSnapshot(child) then
				local data = instanceToData(child)
				table.insert(instances, data)

				-- Track all instances for GUID ownership and removal handling
				local guid = data.guid
				trackedInstances[child] = guid
				guidMap[guid] = child

				if isScript(child) then
					scriptCount = scriptCount + 1
				end
			end

			-- Recurse into children
			collectInstances(child)
		end
	end

	-- Start from game - include services first, then their children
	for _, service in ipairs(game:GetChildren()) do
		if shouldIncludeInSnapshot(service) then
			-- Add the service itself first
			local serviceData = instanceToData(service)
			table.insert(instances, serviceData)
			trackedInstances[service] = serviceData.guid
			guidMap[serviceData.guid] = service

			-- Then add all its children
			collectInstances(service)
		end
	end

	-- Send snapshot
	sendMessage("fullSnapshot", { data = instances })
	print("[StudioSync] Snapshot sent:", #instances, "instances (", scriptCount, "scripts )")
end

-- Handle script change
local function onScriptChanged(script)
	if not shouldSync(script) then
		return
	end

	local guid = getOrCreateGUID(script)

	-- Don't send changes if this was just patched from daemon
	if recentPatches[guid] then
		print("[StudioSync] Ignoring change (was just patched from daemon):", script:GetFullName())
		recentPatches[guid] = nil
		return
	end

	-- Don't send changes if we're applying a patch from daemon
	if applyingPatch then
		return
	end

	-- Don't send changes within 1 second of receiving a patch (debounce)
	local lastPatch = lastPatchTime[guid] or 0
	local now = tick()
	if now - lastPatch < 1 then
		print("[StudioSync] Ignoring change (too soon after patch):", script:GetFullName())
		return
	end

	local path = getInstancePath(script)

	sendMessage("scriptChanged", {
		guid = guid,
		path = path,
		className = script.ClassName,
		source = script.Source,
	})
end

-- Handle instance added
local function onInstanceAdded(instance: Instance)
	-- Include all non-excluded instances (scripts + containers) so sourcemap stays accurate
	if not shouldIncludeInSnapshot(instance) then
		return
	end

	local fullName = instance:GetFullName()
	for _, ancestorName in CONFIG.EXCLUDED_PARENTS do
		if fullName:find(ancestorName) then
			return
		end
	end

	local data = instanceToData(instance)
	local guid = data.guid

	trackedInstances[instance] = guid
	guidMap[guid] = instance

	sendMessage("instanceUpdated", { data = data })

	-- Watch for source changes (scripts only)
	if isScript(instance) then
		instance:GetPropertyChangedSignal("Source"):Connect(function()
			onScriptChanged(instance)
		end)
	end
end

-- Handle instance removed
local function onInstanceRemoved(instance)
	local guid = trackedInstances[instance]
	if not guid then
		return
	end

	trackedInstances[instance] = nil
	guidMap[guid] = nil
	usedGuids[guid] = nil

	sendMessage("deleted", { guid = guid })
end

-- Process incoming daemon message
local function processMessage(message)
	print("[StudioSync] Processing message type:", message.type)

	if message.type == "patchScript" then
		print("[StudioSync] Patch requested for GUID:", message.guid)
		-- Update script source
		local instance = guidMap[message.guid]
		if instance and isScript(instance) then
			-- Mark this script as recently patched from daemon
			recentPatches[message.guid] = true

			-- Record patch time BEFORE applying to prevent echo
			lastPatchTime[message.guid] = tick()

			-- Update source
			applyingPatch = true
			instance.Source = message.source

			-- Keep flag set longer to cover any async events
			task.delay(0.2, function()
				applyingPatch = false
			end)

			print("[StudioSync] Updated script:", instance:GetFullName())

			-- Refresh the script editor if the script is currently open
			-- This ensures VSCode changes are visible immediately
			local success, scriptDocument = pcall(function()
				return ScriptEditorService:FindScriptDocument(instance)
			end)

			if success and scriptDocument then
				-- Close and reopen the document to refresh the editor
				task.spawn(function()
					pcall(function()
						scriptDocument:CloseAsync()
					end)
					task.wait(0.1)
					pcall(function()
						ScriptEditorService:OpenScriptDocumentAsync(instance)
					end)
					-- Clear the patch marker after editor refresh completes
					task.wait(0.2)
					recentPatches[message.guid] = nil
				end)
			end
		else
			warn("[StudioSync] Cannot apply patch - instance not found for GUID:", message.guid)
			local count = 0
			for _ in pairs(guidMap) do
				count = count + 1
			end
			warn("[StudioSync] Total tracked instances:", count)
		end
	elseif message.type == "requestSnapshot" then
		-- Daemon is requesting a full snapshot
		print("[StudioSync] Snapshot requested by daemon")
		sendFullSnapshot()
	elseif message.type == "error" then
		warn("[StudioSync] Daemon error:", message.message)
	elseif message.type == "pong" then
		-- Heartbeat response
		print("[StudioSync] Received pong")
	else
		warn("[StudioSync] Unknown message type:", message.type)
	end
end

-- Start sync
local function startSync()
	if syncEnabled then
		return
	end

	print("[StudioSync] Starting sync...")
	syncEnabled = true
	connectButton:SetActive(true)

	-- Create and connect WebSocket client
	wsClient = WebSocketClient.new(CONFIG.WS_URL)

	-- Set up message handler
	wsClient:on("message", function(message)
		processMessage(message)
	end)

	-- Set up connection handler
	wsClient:on("connect", function()
		print("[StudioSync] Connected to daemon")
		-- Send initial snapshot after connection
		task.wait(0.5)
		sendFullSnapshot()
	end)

	-- Set up disconnect handler
	wsClient:on("disconnect", function()
		print("[StudioSync] Disconnected from daemon")
	end)

	-- Set up error handler
	wsClient:on("error", function(error)
		warn("[StudioSync] Connection error:", error)
	end)

	-- Connect to daemon
	local connected = wsClient:connect()

	if not connected then
		warn("[StudioSync] Failed to connect to daemon")
		stopSync()
		return
	end

	-- Set up listeners for all existing instances
	local function setupListeners(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if isScript(child) then
				child:GetPropertyChangedSignal("Source"):Connect(function()
					if syncEnabled then
						onScriptChanged(child)
					end
				end)
			end
			setupListeners(child)
		end
	end

	for _, service in ipairs(game:GetChildren()) do
		setupListeners(service)
	end

	-- Listen for new instances
	game.DescendantAdded:Connect(function(instance)
		if syncEnabled then
			onInstanceAdded(instance)
		end
	end)

	-- Listen for removed instances
	game.DescendantRemoving:Connect(function(instance)
		if syncEnabled then
			onInstanceRemoved(instance)
		end
	end)

	-- Start heartbeat
	RunService.Heartbeat:Connect(function()
		if syncEnabled then
			-- Send heartbeat periodically
			local now = os.time()
			if now - lastHeartbeat > CONFIG.HEARTBEAT_INTERVAL then
				sendMessage("ping", {})
				lastHeartbeat = now
			end
		end
	end)

	print("[StudioSync] Sync enabled")
end

-- Stop sync
function stopSync()
	if not syncEnabled then
		return
	end

	print("[StudioSync] Stopping sync...")
	syncEnabled = false
	connectButton:SetActive(false)

	if wsClient then
		wsClient:disconnect()
		wsClient = nil
	end

	trackedInstances = {}
	guidMap = {}

	print("[StudioSync] Sync disabled")
end

-- Toggle button handler
connectButton.Click:Connect(function()
	if syncEnabled then
		stopSync()
	else
		startSync()
	end
end)

-- Cleanup on plugin unload
plugin.Unloading:Connect(function()
	stopSync()
end)

print("[StudioSync] Plugin loaded. Click 'Toggle Sync' to connect.")
