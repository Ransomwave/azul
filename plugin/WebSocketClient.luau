--!strict
--[[
	WebSocket Client for Roblox Studio
	
	Uses Roblox Studio's native WebSocket support (WebStreamClient) for real-time
	bidirectional communication with the sync daemon.
]]

local HttpService = game:GetService("HttpService")

local WebSocketClient = {}
WebSocketClient.__index = WebSocketClient

type configType = {
	debugMode: boolean?,
	silentMode: boolean?,
}

-- self type
type WebSocketClient = {
	url: string,
	client: WebStreamClient,
	connected: boolean,
	messageHandlers: { [string]: (any) -> () },
	config: configType,

	new: (url: string?) -> WebSocketClient,
	on: (self: WebSocketClient, event: string, handler: (any) -> ()) -> (),
	connect: (self: WebSocketClient) -> boolean,
	handleMessage: (self: WebSocketClient, message: string) -> (),
	send: (self: WebSocketClient, message: string) -> boolean,
	disconnect: (self: WebSocketClient) -> (),
	debugPrint: (self: WebSocketClient, ...any) -> (),
	infoPrint: (self: WebSocketClient, ...any) -> (),
}

function WebSocketClient.new(url, config: configType?)
	local self = setmetatable({}, WebSocketClient)
	self.url = url or "ws://localhost:8080"
	self.client = nil
	self.connected = false
	self.messageHandlers = {}
	self.onClosed = Instance.new("BindableEvent")
	self.config = config or {
		debugMode = false,
		silentMode = true,
	}

	if self.config.debugMode then
		print("[🐛 WebSocket]: Debug mode is enabled!")
	end

	return (self :: any) :: WebSocketClient
end

function WebSocketClient:debugPrint(...)
	self = self :: WebSocketClient
	if self.config.silentMode or not self.config.debugMode then
		return
	end
	print(...)
end

function WebSocketClient:infoPrint(...)
	self = self :: WebSocketClient
	if self.config.silentMode then
		return
	end
	print(...)
end

function WebSocketClient:on(event, handler)
	self = self :: WebSocketClient
	self.messageHandlers[event] = handler
end

function WebSocketClient:connect()
	self = self :: WebSocketClient
	if self.connected then
		return true
	end

	-- Create WebSocket client using CreateWebStreamClient
	local success, result = pcall(function()
		return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
			Url = self.url,
		})
	end)

	if not success then
		warn("[WebSocket]: Connection failed:", result)
		if self.messageHandlers.error then
			self.messageHandlers.error(result)
		end
		return false
	end

	self.client = result
	self.connected = true

	-- Set up message handler (only MessageReceived is documented)
	self.client.MessageReceived:Connect(function(message)
		local parseSuccess, parseError = pcall(function()
			self:handleMessage(message)
		end)
		if not parseSuccess then
			warn("[WebSocket]: Error handling message:", parseError)
		end
	end)

	-- Notify connection established
	self:debugPrint("[🐛 WebSocket]: Connected to", self.url)
	if self.messageHandlers.connect then
		task.defer(function()
			self.messageHandlers.connect()
		end)
	end

	return true
end

function WebSocketClient:handleMessage(message)
	self = self :: WebSocketClient
	if not message or message == "" then
		return
	end

	self:debugPrint("[🐛 WebSocket]: Received message:", string.sub(message, 1, 100))

	local success, data = pcall(function()
		return HttpService:JSONDecode(message)
	end)

	if success and self.messageHandlers.message then
		self.messageHandlers.message(data)
	elseif not success then
		warn("[WebSocket]: Failed to parse message:", message)
	end
end

function WebSocketClient:send(message)
	self = self :: WebSocketClient
	if not self.connected or not self.client then
		warn("[WebSocket]: Cannot send: not connected")
		return false
	end

	self:debugPrint("[🐛 WebSocket]: Sending:", string.sub(message, 1, 100))

	local success, err = pcall(function()
		self.client:Send(message)
	end)

	if not success then
		warn("[WebSocket]: Send failed:", err)
		return false
	end

	return true
end

function WebSocketClient:disconnect()
	self = self :: WebSocketClient

	if not self.connected or not self.client then
		return
	end

	self.connected = false

	self.client:Close()
	-- self.client = nil

	if self.messageHandlers.disconnect then
		self.messageHandlers.disconnect()
	end
end

return WebSocketClient
