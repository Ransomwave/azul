--!strict
--[[
	Azul - Roblox Studio Plugin.
	Companion plugin for Azul to sync scripts between Roblox Studio and external editors.

	Ransomwave 2025
]]

local RunService = game:GetService("RunService")

-- Prevent from running if the game is being Playtested
if RunService:IsRunning() then return end

local pluginParent = script.Parent
if not pluginParent then return end
local azulPluginFolder = pluginParent.Parent
if not azulPluginFolder then return end

local UI = require("../UI")
local Config = require("../Config")
local Enums = require("../Enums")
local SettingsStore = require("../SettingsStore")
local SyncSession = require("./SyncSession")

local settingsStore = SettingsStore.new(plugin, Config, Enums.scope, {
	defaultScope = Enums.scope.GLOBAL,
})
settingsStore:loadSettings()

local session = SyncSession.new(plugin, settingsStore, Config)

local uiCallbacks: UI.CallbackFunctions = {
	onStartSync = function()
		session:startSync()
	end,
	onStopSync = function()
		session:stopSync()
	end,
	onConfigChanged = function(key, value)
		session:debugPrint(`Config {key} updated to: {value}`)
	end,
	onSettingsScopeChanged = function(newScope)
		session:onSettingsScopeChanged(newScope)
	end,
	onSourcemapReload = function()
		session:infoPrint("Reloading sourcemap...")
		session:reloadSourcemap()
	end,
}

local uiHelpers = {
	debugPrint = function(...)
		session:debugPrint(...)
	end,
	infoPrint = function(...)
		session:infoPrint(...)
	end,
	rebuildServiceSet = function()
		session:rebuildServiceSet()
	end,
}

local azulUI = UI.new(plugin, uiCallbacks, settingsStore:getScope(), uiHelpers)
session:setUI(azulUI)

plugin.Unloading:Connect(function()
	settingsStore:saveSettings()
	settingsStore:saveSelectedScope()
	session:stopSync()
end)

session:infoPrint("Plugin loaded. Click on the 'Azul' button to connect.")
session:debugPrint("Debug mode is enabled!")
session:debugPrint(`Service list type is set to: "{Config.LIST_TYPE}"`)
