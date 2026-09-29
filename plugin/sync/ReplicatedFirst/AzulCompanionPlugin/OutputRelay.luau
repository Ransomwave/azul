--!strict
--[[
	Relays playtest output to the Daemon's `/studio-output` endpoint.
	Runs inside the Solo playtest server and client DataModels.
]]

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local WebSocketClient = require("./WebSocketClient")

local MAX_PENDING_MESSAGES = 500 -- Messages buffered while the socket is opening

local OutputRelay = {}

--[=[
	Opens a WebSocket to the Daemon and forwards every LogService message to it.
	Relaying stops for good once the socket closes or errors.

	@param wsUrl The Daemon WebSocket URL from Config (scheme optional).
]=]
function OutputRelay.start(wsUrl: string)
	local url = WebSocketClient.normalizeUrl(wsUrl):gsub("/+$", "") .. "/studio-output"
	local ok, result = pcall(
		function()
			return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
				Url = url,
			})
		end
	)
	if not ok then
		warn(`[Azul]: Playtest output relay could not connect to {url}: {result}`)
		return
	end

	local client = result :: WebStreamClient
	local source = if RunService:IsServer() then "server" else "client"
	local pending: { string } = {}
	local isOpen = false
	local messageConnection: RBXScriptConnection

	local function stop()
		isOpen = false
		messageConnection:Disconnect()
		table.clear(pending)
	end

	-- Sends are pcall'd: an uncaught send error would be logged, relayed, and fail again.
	local function send(encoded: string)
		if not pcall(client.Send, client, encoded) then stop() end
	end

	local function flush()
		if isOpen then return end
		isOpen = true
		for _, encoded in pending do
			send(encoded)
		end
		table.clear(pending)
	end

	local function relay(message: string, messageType: Enum.MessageType, timestamp: number)
		local encoded = HttpService:JSONEncode({
			type = "studioOutput",
			message = message,
			messageType = messageType.Name,
			source = source,
			timestamp = timestamp, -- Taken when logged so buffered messages keep their real time
		})

		if isOpen then
			send(encoded)
		else
			-- Keep the most recent output: remove the oldest once the buffer is full
			if #pending >= MAX_PENDING_MESSAGES then table.remove(pending, 1) end
			table.insert(pending, encoded)
		end
	end

	-- Previous messages are removed when a playtest is started, so getting the log history is fine
	for _, entry in LogService:GetLogHistory() do
		relay(entry.message, entry.messageType, entry.timestamp * 1000)
	end

	messageConnection = LogService.MessageOut:Connect(
		function(message, messageType) relay(message, messageType, DateTime.now().UnixTimestampMillis) end
	)

	client.Opened:Connect(flush)
	client.Closed:Connect(stop)
	client.Error:Connect(function(statusCode: number, errorMessage: string)
		if not messageConnection.Connected then return end
		stop() -- Disconnects the log listener first so this warning isn't relayed
		warn(`[Azul]: Playtest output relay stopped ({statusCode}): {errorMessage}`)
	end)
	if client.ConnectionState == Enum.WebStreamClientState.Open then flush() end
end

return OutputRelay
