--[[
	WebSocket Client for Roblox Studio
	
	Uses Roblox Studio's native WebSocket support (WebStreamClient) for real-time
	bidirectional communication with the sync daemon.
]]

local HttpService = game:GetService("HttpService")

local WebSocketClient = {}
WebSocketClient.__index = WebSocketClient

function WebSocketClient.new(url)
	local self = setmetatable({}, WebSocketClient)
	self.url = url or "ws://localhost:8080"
	self.client = nil
	self.connected = false
	self.messageHandlers = {}
	return self
end

function WebSocketClient:on(event, handler)
	self.messageHandlers[event] = handler
end

function WebSocketClient:connect()
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
		warn("[WebSocket] Connection failed:", result)
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
			warn("[WebSocket] Error handling message:", parseError)
		end
	end)

	-- Notify connection established
	print("[WebSocket] Connected to", self.url)
	if self.messageHandlers.connect then
		task.defer(function()
			self.messageHandlers.connect()
		end)
	end

	return true
end

function WebSocketClient:handleMessage(message)
	if not message or message == "" then
		return
	end

	print("[WebSocket] Received message:", string.sub(message, 1, 100))

	local success, data = pcall(function()
		return HttpService:JSONDecode(message)
	end)

	if success and self.messageHandlers.message then
		self.messageHandlers.message(data)
	elseif not success then
		warn("[WebSocket] Failed to parse message:", message)
	end
end

function WebSocketClient:send(message)
	if not self.connected or not self.client then
		warn("[WebSocket] Cannot send: not connected")
		return false
	end

	print("[WebSocket] Sending:", string.sub(message, 1, 100))

	local success, err = pcall(function()
		self.client:Send(message)
	end)

	if not success then
		warn("[WebSocket] Send failed:", err)
		return false
	end

	return true
end

function WebSocketClient:disconnect()
	if not self.connected or not self.client then
		return
	end

	self.connected = false

	-- WebStreamClient may not have an explicit close method
	-- Connection will be cleaned up when client is destroyed
	self.client = nil

	if self.messageHandlers.disconnect then
		self.messageHandlers.disconnect()
	end
end

return WebSocketClient
