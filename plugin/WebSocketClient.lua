--[[
	WebSocket Client for Roblox Studio
	
	Since Roblox doesn't support native WebSockets, this implements
	a polling-based client using HttpService.
	
	The daemon should expose HTTP endpoints for:
	- POST /connect - Establish connection
	- POST /send - Send message
	- GET /poll?clientId=xxx - Poll for messages
	- POST /disconnect - Close connection
]]

local HttpService = game:GetService("HttpService")

local WebSocketClient = {}
WebSocketClient.__index = WebSocketClient

function WebSocketClient.new(baseUrl)
	local self = setmetatable({}, WebSocketClient)
	self.baseUrl = baseUrl or "http://localhost:8080"
	self.clientId = nil
	self.connected = false
	self.messageHandlers = {}
	self.polling = false
	return self
end

function WebSocketClient:on(event, handler)
	self.messageHandlers[event] = handler
end

function WebSocketClient:connect()
	if self.connected then
		return true
	end

	-- Try to establish connection
	local success, response = pcall(function()
		return HttpService:PostAsync(self.baseUrl .. "/connect", "{}", Enum.HttpContentType.ApplicationJson)
	end)

	if not success then
		warn("[WebSocket] Connection failed:", response)
		if self.messageHandlers.error then
			self.messageHandlers.error(response)
		end
		return false
	end

	-- Parse client ID from response
	local data = HttpService:JSONDecode(response)
	self.clientId = data.clientId or HttpService:GenerateGUID(false)
	self.connected = true

	if self.messageHandlers.connect then
		self.messageHandlers.connect()
	end

	-- Start polling
	self:startPolling()

	return true
end

function WebSocketClient:send(message)
	if not self.connected then
		warn("[WebSocket] Cannot send: not connected")
		return false
	end

	local payload = {
		clientId = self.clientId,
		message = message,
	}

	local success, response = pcall(function()
		return HttpService:PostAsync(
			self.baseUrl .. "/send",
			HttpService:JSONEncode(payload),
			Enum.HttpContentType.ApplicationJson
		)
	end)

	if not success then
		warn("[WebSocket] Send failed:", response)
		return false
	end

	return true
end

function WebSocketClient:startPolling()
	if self.polling then
		return
	end

	self.polling = true

	task.spawn(function()
		while self.connected and self.polling do
			self:poll()
			task.wait(0.1) -- Poll every 100ms
		end
	end)
end

function WebSocketClient:poll()
	if not self.connected then
		return
	end

	local success, response = pcall(function()
		return HttpService:GetAsync(self.baseUrl .. "/poll?clientId=" .. self.clientId, false)
	end)

	if not success then
		-- Silently fail polling errors to avoid spam
		return
	end

	if response and response ~= "" and response ~= "null" then
		-- Parse and handle messages
		local messages = HttpService:JSONDecode(response)

		if type(messages) == "table" then
			for _, msg in ipairs(messages) do
				if self.messageHandlers.message then
					self.messageHandlers.message(msg)
				end
			end
		end
	end
end

function WebSocketClient:disconnect()
	if not self.connected then
		return
	end

	self.polling = false
	self.connected = false

	pcall(function()
		HttpService:PostAsync(
			self.baseUrl .. "/disconnect",
			HttpService:JSONEncode({ clientId = self.clientId }),
			Enum.HttpContentType.ApplicationJson
		)
	end)

	self.clientId = nil

	if self.messageHandlers.disconnect then
		self.messageHandlers.disconnect()
	end
end

return WebSocketClient
