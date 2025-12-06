-- Example Script: GameLoop
-- This would sync from Studio to sync/ServerScriptService/GameLoop.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- With Super Studio Sync + luau-lsp, this require gets full autocomplete!
local PlayerData = require(ReplicatedStorage.Modules.PlayerData)

-- Game state
local _roundActive = false
local roundNumber = 0

-- Initialize player data when they join
Players.PlayerAdded:Connect(function(player)
	print(`Player {player.Name} joined!`)

	-- Create player profile
	local profile = PlayerData.new(player)
	print(`Created profile for user {profile.userId}`)

	-- Give starting coins
	PlayerData.addCoins(player.UserId, 100)
	print(`Gave {player.Name} 100 starting coins`)
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	print(`Player {player.Name} left`)
	-- Save data here
end)

-- Game loop
local function startRound()
	_roundActive = true
	roundNumber += 1

	print(`\n=== Round {roundNumber} Started ===`)

	-- Award coins to all players
	for _, player in Players:GetPlayers() do
		PlayerData.addCoins(player.UserId, 10)
		print(`Awarded 10 coins to {player.Name}`)
	end

	-- Round lasts 30 seconds
	task.wait(30)

	_roundActive = false
	print(`=== Round {roundNumber} Ended ===\n`)
end

-- Main game loop
while true do
	-- Wait for players
	if #Players:GetPlayers() >= 1 then
		startRound()
	else
		print("Waiting for players...")
	end

	task.wait(5) -- Intermission
end
