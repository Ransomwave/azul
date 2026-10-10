--!strict
--[[
	WebSocket Client for Roblox Studio
	
	Uses Roblox Studio's native WebSocket support (WebStreamClient) for real-time
	bidirectional communication with the sync daemon.

	Ransomwave 2025
]]

const HttpService = game:GetService("HttpService")

const DEFAULT_CONNECT_TIMEOUT = 5

const WebSocketClient = {}
WebSocketClient.__index = WebSocketClient

type WebSocketConfig = {
	debugMode: boolean?,
	silentMode: boolean?,
	connectTimeout: number?,
}

type PrivateWebSocketClient = {
	url: string,
	client: WebStreamClient?,
	connected: boolean,
	messageHandlers: { [string]: (any) -> () },
	config: WebSocketConfig,
	clientConnections: { RBXScriptConnection },
}

export type WebSocketClient = typeof(setmetatable({} :: PrivateWebSocketClient, WebSocketClient))

--- Prefixes `ws://` when the URL has no scheme.
function WebSocketClient.normalizeUrl(url: string): string return if url:find("://", 1, true) then url else `ws://{url}` end

function WebSocketClient.new(url: string, config: WebSocketConfig?)
	local self = setmetatable({} :: PrivateWebSocketClient, WebSocketClient)
	self.url = WebSocketClient.normalizeUrl(url)
	self.client = nil
	self.connected = false
	self.messageHandlers = {}
	self.clientConnections = {}
	self.config = config or {
		debugMode = false,
		silentMode = true,
		connectTimeout = DEFAULT_CONNECT_TIMEOUT,
	}

	if self.config.debugMode then print("[🐛 WebSocket]: Debug mode is enabled!") end

	return (self :: any) :: WebSocketClient
end

function WebSocketClient:debugPrint(...)
	self = self :: WebSocketClient
	if self.config.silentMode or not self.config.debugMode then return end
	print(`[🐛 WebSocket]: `, ...)
end

function WebSocketClient:infoPrint(...)
	self = self :: WebSocketClient
	if self.config.silentMode then return end
	print(`[WebSocket]: `, ...)
end

function WebSocketClient:on(event, handler)
	self = self :: WebSocketClient
	self.messageHandlers[event] = handler
end

function WebSocketClient:once(event, handler)
	self = self :: WebSocketClient
	local function wrapper(...)
		handler(...)
		self.messageHandlers[event] = nil
	end
	self.messageHandlers[event] = wrapper
end

function WebSocketClient:connect()
	self = self :: WebSocketClient
	if self.connected then return true end

	-- Create WebSocket client using CreateWebStreamClient
	local success, result = pcall(
		function()
			return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
				Url = self.url,
			})
		end
	)

	if not success then
		warn("[WebSocket]: Connection failed:", result)
		if self.messageHandlers.error then self.messageHandlers.error(result) end
		return false
	end

	local client = result :: WebStreamClient
	self.client = client

	-- The socket opens asynchronously, wait for it to open or fail before reporting success
	local opened: boolean? = nil
	local openedConnection = client.Opened:Connect(function() opened = true end)
	table.insert(
		self.clientConnections,
		client.Error:Connect(function(statusCode, errorMessage)
			self:debugPrint("Error:", statusCode, errorMessage)
			if opened == nil then opened = false end
		end)
	)
	table.insert(
		self.clientConnections,
		client.Closed:Connect(function()
			if opened == nil then opened = false end
			self:disconnect()
		end)
	)

	local deadline = os.clock() + (self.config.connectTimeout or DEFAULT_CONNECT_TIMEOUT)
	while opened == nil and os.clock() < deadline do
		task.wait()
	end
	openedConnection:Disconnect()

	if not opened then
		self:closeClient()
		self:debugPrint("Could not open connection to", self.url)
		return false
	end

	self.connected = true

	table.insert(
		self.clientConnections,
		client.MessageReceived:Connect(function(message)
			local parseSuccess, parseResult = pcall(function() self:handleMessage(message) end)
			if not parseSuccess then
				warn("[WebSocket]: Error handling message:", parseResult)
				warn("[WebSocket]: Raw message was:", message)
			end
		end)
	)

	-- Notify connection established
	self:debugPrint("Connected to", self.url)
	task.defer(function()
		const onConnect = self.messageHandlers.connect
		if onConnect and self.connected then onConnect() end
	end)

	return true
end

function WebSocketClient:reconnect()
	self = self :: WebSocketClient

	self:disconnect()
	return self:connect()
end

function WebSocketClient:handleMessage(message)
	self = self :: WebSocketClient
	if not message or message == "" then return end

	self:debugPrint("Received message:", string.sub(message, 1, 100))

	local success, result = pcall(function() return HttpService:JSONDecode(message) end)

	if success then
		if self.messageHandlers.message then self.messageHandlers.message(result) end
		local messageType = result and result.type
		if type(messageType) == "string" and self.messageHandlers[messageType] then
			self.messageHandlers[messageType](result)
		end
	elseif not success then
		warn(`[WebSocket]: Failed to decode message as JSON: {result}`)
	end
end

function WebSocketClient:send(message)
	self = self :: WebSocketClient
	if not self.connected or not self.client then
		warn("[WebSocket]: Cannot send: not connected")
		return false
	end

	self:debugPrint("Sending:", string.sub(message, 1, 200))

	local success, result = pcall(function() self.client:Send(message) end)

	if not success then
		warn("[WebSocket]: Send failed:", result)
		return false
	end

	return true
end

--- Disconnects the socket's event connections and closes it.
function WebSocketClient:closeClient()
	self = self :: WebSocketClient

	for _, connection in self.clientConnections do
		connection:Disconnect()
	end
	table.clear(self.clientConnections)

	if self.client then pcall(self.client.Close, self.client) end
	self.client = nil
end

function WebSocketClient:disconnect()
	self = self :: WebSocketClient

	if not self.connected or not self.client then return end

	self.connected = false
	self:closeClient()

	if self.messageHandlers.disconnect then self.messageHandlers.disconnect() end
end

return WebSocketClient
