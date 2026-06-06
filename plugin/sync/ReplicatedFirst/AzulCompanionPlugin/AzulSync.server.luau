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
local connectionWatchdog: thread? = nil

--[=[
    Watchdog for Auto Connection
]=]
local function startWatchdog()
    if connectionWatchdog then
        task.cancel(connectionWatchdog)
        connectionWatchdog = nil
    end

    connectionWatchdog = task.spawn(function()
        local attempts = 0
        session:debugPrint("Watchdog started.")

        while true do
            -- 1. Exit if Auto-Connect is disabled
            if not Config.AUTO_CONNECT then 
                session:debugPrint("Watchdog terminating: AUTO_CONNECT is false.")
                break 
            end

            -- 2. If we aren't connected and haven't even started syncing yet
            if not session.syncEnabled and not session.handshakeComplete then
                session:debugPrint(`Watchdog: Attempting auto-connect... (Attempt {attempts + 1})`)
                session:startSync()
            end

            -- 3. Wait for the result of the attempt
            -- We poll until either handshake succeeds OR the session shuts down (failure)
            local timeout = 0
            while session.syncEnabled and not session.handshakeComplete and timeout < 10 do
                task.wait(1)
                timeout += 1
            end

            if session.handshakeComplete then
                attempts = 0
                session:debugPrint("Watchdog: Connection Succeeded.")
                
                -- Idle here as long as we are connected
                repeat task.wait(2) until not session.handshakeComplete or not Config.AUTO_CONNECT
            else
                -- Failed to handshake or session stopped
                attempts += 1
                session:debugPrint(`Watchdog: Attempt {attempts} failed.`)

                if Config.MAX_RECONNECTIONS ~= -1 and attempts >= Config.MAX_RECONNECTIONS then
                    session:infoPrint(`Auto-connect: Reached max attempts ({Config.MAX_RECONNECTIONS}). Stopping.`)
                    break
                end

                -- Interval wait
                task.wait(Config.RECONNECTION_INTERVAL or 5)
            end
            
            task.wait(.1)
        end
        
        connectionWatchdog = nil
    end)
end

--[=[
    UI Callback Handlers
]=]
local uiCallbacks: UI.CallbackFunctions = {
	onStartSync = function()

		-- Stop watchdog (if ever)
		if connectionWatchdog then
			task.cancel(connectionWatchdog)
			connectionWatchdog = nil
		end
		
		session:startSync()

		-- If Auto Connect is on, restart the watchdog to monitor the new connection
		if Config.AUTO_CONNECT then
			startWatchdog()
		end
	end,

	onStopSync = function()
		session:stopSync()
	end,

	onAutoConnectChanged = function(newValue: boolean)
		Config.AUTO_CONNECT = newValue
		session:debugPrint(`Auto Connect changed: {newValue}`)
		
		if newValue then
			startWatchdog()
		else 
			if connectionWatchdog then
				task.cancel(connectionWatchdog)
				connectionWatchdog = nil
			end
			if session.syncEnabled and not session.handshakeComplete then session:stopSync() end
		end
	end,

	onConfigChanged = function(key, value)
		session:debugPrint(
			`Config {key} updated to: {if type(value) == "table" then table.concat(value, ", ") else tostring(value)}`
		)
		Config[key] = value
		if key == "SERVICE_LIST" then session:rebuildServiceSet() end
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
	rebuildServiceSet = function()
		session:rebuildServiceSet()
	end,
	
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
	if connectionWatchdog then
		task.cancel(connectionWatchdog)
	end
	settingsStore:saveSettings()
	settingsStore:saveSelectedScope()
	session:stopSync()
end)

if Config.AUTO_CONNECT then
	startWatchdog()
else
	session:infoPrint("Plugin loaded. Click on the 'Azul' button to connect.")
end

session:debugPrint("Debug mode is enabled!")
session:debugPrint(`Service list type is set to: "{Config.LIST_TYPE}"`)