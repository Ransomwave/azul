-- Example Module: PlayerData
-- This would sync from Studio to sync/ReplicatedStorage/Modules/PlayerData/init.lua

local PlayerData = {}
PlayerData.__index = PlayerData

export type PlayerProfile = {
	userId: number,
	displayName: string,
	coins: number,
	level: number,
	inventory: { string },
}

local profiles: { [number]: PlayerProfile } = {}

function PlayerData.new(player: Player): PlayerProfile
	local profile: PlayerProfile = {
		userId = player.UserId,
		displayName = player.DisplayName,
		coins = 0,
		level = 1,
		inventory = {},
	}

	profiles[player.UserId] = profile
	return profile
end

function PlayerData.get(userId: number): PlayerProfile?
	return profiles[userId]
end

function PlayerData.addCoins(userId: number, amount: number): boolean
	local profile = profiles[userId]
	if not profile then
		return false
	end

	profile.coins += amount
	return true
end

function PlayerData.levelUp(userId: number): boolean
	local profile = profiles[userId]
	if not profile then
		return false
	end

	profile.level += 1
	return true
end

function PlayerData.addItem(userId: number, itemId: string): boolean
	local profile = profiles[userId]
	if not profile then
		return false
	end

	table.insert(profile.inventory, itemId)
	return true
end

return PlayerData
