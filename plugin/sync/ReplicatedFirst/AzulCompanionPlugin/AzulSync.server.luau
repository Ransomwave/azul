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

-- Modules
local UI = require("./UI")
local Config = require("./Config")
local Enums = require("./Enums")
local SettingsStore = require("./SettingsStore")
local SyncSession = require("./SyncSession")

-- UI Apps
local azulApp = require("./App/UI")
local azulLegacyUI = require("./UI")

-- State Management
local settingsStore = SettingsStore.new(plugin, Config, Enums.scope, {
	defaultScope = Enums.scope.GLOBAL,
})
settingsStore:loadSettings()

local session = SyncSession.new(plugin, settingsStore, Config)

--[=[
    UI Callback Handlers
]=]
local uiCallbacks: UI.CallbackFunctions = {
	onStartSync = function()
		-- If the auto-connect runner is active, stop it while user triggers manual start.
		session:stopAutoConnect()

		session:startSync()

		-- If Auto Connect still requested, restart the auto-connect runner to monitor
		if Config.AUTO_CONNECT then session:startAutoConnect() end
	end,

	onStopSync = function() session:stopSync() end,

	onAutoConnectChanged = function(newValue: boolean)
		Config.AUTO_CONNECT = newValue
		session:debugPrint(`Auto Connect changed: {newValue}`)
		if newValue then
			session:startAutoConnect()
		else
			session:stopAutoConnect()
			if session.syncEnabled and not session.handshakeComplete then session:stopSync() end
		end
	end,

	onConfigChanged = function(key, value)
		session:debugPrint(
			`Config {key} updated to: {if type(value) == "table" then table.concat(value, ", ") else tostring(value)}`
		)
		Config[key] = value
		if key == "SERVICE_LIST" then session:rebuildServiceSet() end
		if key == "AUTO_CONNECT" then
			if value then
				session:startAutoConnect()
			else
				session:stopAutoConnect()
				if session.syncEnabled and not session.handshakeComplete then session:stopSync() end
			end
		end
	end,

	onSettingsScopeChanged = function(newScope) session:onSettingsScopeChanged(newScope) end,

	onSourcemapReload = function()
		session:infoPrint("Reloading sourcemap...")
		session:reloadSourcemap()
	end,
}

local uiHelpers = {
	rebuildServiceSet = function() session:rebuildServiceSet() end,

	openPlaceConfig = function()
		local ScriptEditorService = game:GetService("ScriptEditorService")
		local ServerStorage = game:GetService("ServerStorage")
		local azulFolder = ServerStorage:FindFirstChild("Azul") :: Folder

		if not azulFolder then
			local newAzulFolder = Instance.new("Folder")
			newAzulFolder.Name = "Azul"
			newAzulFolder.Parent = ServerStorage
			azulFolder = newAzulFolder
		end

		local azulDaemonSettings = azulFolder:FindFirstChild("Config") :: ModuleScript
		if not azulDaemonSettings then
			local newConfigModule = Instance.new("ModuleScript")
			newConfigModule.Name = "Config"
			newConfigModule.Source = [[
-- Per-place Daemon configuration
-- This file is sent to the Daemon when it connects.
-- https://azul-docs.vercel.app/advanced-usage/#per-place-daemon-configuration

return {}
]]
			newConfigModule.Parent = azulFolder
			azulDaemonSettings = newConfigModule
		end

		ScriptEditorService:OpenScriptDocumentAsync(azulDaemonSettings)
	end,
}

--[=[
    Initialization
]=]
local USE_LEGACY_UI = false

if not USE_LEGACY_UI then
	local newAzulUI = azulApp.new(plugin, uiCallbacks, settingsStore:getScope(), uiHelpers)
	session:setUI(newAzulUI)
else
	warn(`[Azul::{script}]: Using legacy UI, this is not recommended!`)
	local azulUI = UI.new(plugin, uiCallbacks, settingsStore:getScope(), uiHelpers)
	session:setUI(azulUI)
end

-- Plugin Lifecycle
plugin.Unloading:Connect(function()
	session:stopAutoConnect()
	settingsStore:saveSettings()
	settingsStore:saveSelectedScope()
	session:stopSync()
end)

if Config.AUTO_CONNECT then
	session:startAutoConnect()
else
	session:infoPrint("Plugin loaded. Click on the 'Azul' button to connect.")
end

session:debugPrint("Debug mode is enabled!")
session:debugPrint(`Service list type is set to: "{Config.LIST_TYPE}"`)
