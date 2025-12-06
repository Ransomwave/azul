--[[
	Super Studio Sync - Roblox Studio Plugin
	
	This plugin keeps Studio scripts synchronized with a local filesystem
	via WebSocket connection to the desktop daemon.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- Configuration
local CONFIG = {
	WS_URL = "ws://localhost:8080",
	GUID_ATTRIBUTE = "StudioSyncGUID",
	RECONNECT_DELAY = 3,
	HEARTBEAT_INTERVAL = 30,
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
local wsConnection = nil
local trackedInstances = {}
local guidMap = {}
local lastHeartbeat = 0

-- WebSocket mock (Roblox doesn't have native WebSocket, using HttpService for polling)
-- In production, you'd use a WebSocket library or implement long-polling
local WebSocket = {}
WebSocket.__index = WebSocket

function WebSocket.new(url)
	local self = setmetatable({}, WebSocket)
	self.url = url
	self.connected = false
	self.messageQueue = {}
	return self
end

function WebSocket:connect()
	-- In a real implementation, establish WebSocket connection
	-- For now, we'll simulate with a connection flag
	self.connected = true
	print("[StudioSync] Connected to daemon")
	return true
end

function WebSocket:send(message)
	if not self.connected then
		warn("[StudioSync] Cannot send: not connected")
		return false
	end

	-- In production, send via actual WebSocket
	-- For now, we'll use HttpService POST
	local success, result = pcall(function()
		return HttpService:PostAsync("http://localhost:8080/message", message, Enum.HttpContentType.ApplicationJson)
	end)

	if not success then
		warn("[StudioSync] Send failed:", result)
		return false
	end

	return true
end

function WebSocket:receive()
	-- In production, receive from WebSocket
	-- For now, poll via HttpService GET
	if not self.connected then
		return nil
	end

	local success, result = pcall(function()
		return HttpService:GetAsync("http://localhost:8080/poll")
	end)

	if success and result and result ~= "" then
		return result
	end

	return nil
end

function WebSocket:close()
	self.connected = false
	print("[StudioSync] Disconnected from daemon")
end

-- Utility: Generate or retrieve GUID for instance
local function getOrCreateGUID(instance)
	local guid = instance:GetAttribute(CONFIG.GUID_ATTRIBUTE)

	if not guid then
		guid = HttpService:GenerateGUID(false):gsub("-", "")
		instance:SetAttribute(CONFIG.GUID_ATTRIBUTE, guid)
	end

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

-- Utility: Check if instance should be synced
local function shouldSync(instance)
	if not instance then
		return false
	end

	-- Only sync scripts
	if not isScript(instance) then
		return false
	end

	-- Don't sync plugins
	local current = instance
	while current do
		if current == game:GetService("CoreGui") or current == game:GetService("CorePackages") then
			return false
		end
		current = current.Parent
	end

	return true
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
	if not wsConnection or not wsConnection.connected then
		return false
	end

	local message = {
		type = messageType,
	}

	-- Merge data into message
	for k, v in pairs(data or {}) do
		message[k] = v
	end

	local json = HttpService:JSONEncode(message)
	return wsConnection:send(json)
end

-- Send full snapshot
local function sendFullSnapshot()
	print("[StudioSync] Sending full snapshot...")

	local instances = {}

	-- Collect all scripts from the DataModel
	local function collectScripts(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if shouldSync(child) then
				local data = instanceToData(child)
				table.insert(instances, data)

				-- Track this instance
				local guid = data.guid
				trackedInstances[child] = guid
				guidMap[guid] = child
			end

			-- Recurse into children
			collectScripts(child)
		end
	end

	-- Start from game
	for _, service in ipairs(game:GetChildren()) do
		collectScripts(service)
	end

	-- Send snapshot
	sendMessage("fullSnapshot", { data = instances })
	print("[StudioSync] Snapshot sent:", #instances, "scripts")
end

-- Handle script change
local function onScriptChanged(script)
	if not shouldSync(script) then
		return
	end

	local guid = getOrCreateGUID(script)
	local path = getInstancePath(script)

	sendMessage("scriptChanged", {
		guid = guid,
		path = path,
		className = script.ClassName,
		source = script.Source,
	})
end

-- Handle instance added
local function onInstanceAdded(instance)
	if not shouldSync(instance) then
		return
	end

	local data = instanceToData(instance)
	local guid = data.guid

	trackedInstances[instance] = guid
	guidMap[guid] = instance

	sendMessage("instanceUpdated", { data = data })

	-- Watch for source changes
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

	sendMessage("deleted", { guid = guid })
end

-- Process incoming daemon message
local function processMessage(json)
	local success, message = pcall(function()
		return HttpService:JSONDecode(json)
	end)

	if not success then
		warn("[StudioSync] Failed to parse message:", json)
		return
	end

	if message.type == "patchScript" then
		-- Update script source
		local instance = guidMap[message.guid]
		if instance and isScript(instance) then
			instance.Source = message.source
			print("[StudioSync] Updated script:", instance:GetFullName())
		end
	elseif message.type == "requestSnapshot" then
		-- Daemon is requesting a full snapshot
		sendFullSnapshot()
	elseif message.type == "error" then
		warn("[StudioSync] Daemon error:", message.message)
	end
end

-- Poll for messages from daemon
local function pollMessages()
	if not wsConnection or not wsConnection.connected then
		return
	end

	local message = wsConnection:receive()
	if message then
		processMessage(message)
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

	-- Connect to daemon
	wsConnection = WebSocket.new(CONFIG.WS_URL)
	local connected = wsConnection:connect()

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

	-- Send initial snapshot
	task.wait(0.5) -- Give daemon time to be ready
	sendFullSnapshot()

	-- Start message polling
	RunService.Heartbeat:Connect(function()
		if syncEnabled then
			pollMessages()

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

	if wsConnection then
		wsConnection:close()
		wsConnection = nil
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
