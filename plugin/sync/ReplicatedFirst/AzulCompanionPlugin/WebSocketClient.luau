--!strict
--[[
	WebSocket Client for Roblox Studio
	
	Uses Roblox Studio's native WebSocket support (WebStreamClient) for real-time
	bidirectional communication with the sync daemon.

	Ransomwave 2025
]]

local HttpService = game:GetService("HttpService")

local WebSocketClient = {}
WebSocketClient.__index = WebSocketClient

type WebSocketConfig = {
	debugMode: boolean?,
	silentMode: boolean?,
}

type PrivateWebSocketClient = {
	url: string,
	client: WebStreamClient?,
	connected: boolean,
	messageHandlers: { [string]: (any) -> () },
	config: WebSocketConfig,
	onClosed: BindableEvent,
}

export type WebSocketClient = typeof(setmetatable({} :: PrivateWebSocketClient, WebSocketClient))

function WebSocketClient.new(url: string, config: WebSocketConfig?)
	local self = setmetatable({} :: PrivateWebSocketClient, WebSocketClient)
	self.url = if url:find("://", 1, true) then url else `ws://{url}` -- Default to ws:// if no scheme is provided
	self.client = nil
	self.connected = false
	self.messageHandlers = {}
	self.onClosed = Instance.new("BindableEvent")
	self.config = config or {
		debugMode = false,
		silentMode = true,
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
	self.connected = true

	-- Set up message handler (only MessageReceived is documented)
	client.MessageReceived:Connect(function(message)
		local parseSuccess, parseResult = pcall(function() self:handleMessage(message) end)
		if not parseSuccess then
			warn("[WebSocket]: Error handling message:", parseResult)
			warn("[WebSocket]: Raw message was:", message)
		end
	end)

	-- Notify connection established
	self:debugPrint("Connected to", self.url)
	if self.messageHandlers.connect then task.defer(function() self.messageHandlers.connect() end) end

	return true
end

function WebSocketClient:reconnect()
	self = self :: WebSocketClient

	self:debugPrint(`Reconnect requested to WebSocket at: {self.url}`)

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

function WebSocketClient:disconnect()
	self = self :: WebSocketClient

	if not self.connected or not self.client then return end

	self.connected = false

	self.client:Close()
	-- self.client = nil

	if self.messageHandlers.disconnect then self.messageHandlers.disconnect() end
end

return WebSocketClient
