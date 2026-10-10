--!strict
--[[
	Azul - Roblox Studio Plugin.
	Companion plugin for Azul to sync scripts between Roblox Studio and external editors.

	Ransomwave 2025
]]

const RunService = game:GetService("RunService")

const pluginParent = script.Parent
if not pluginParent then return end

-- Modules
const Config = require("@self/Config")
const Enums = require("@self/Enums")
const SettingsStore = require("@self/SettingsStore")

-- State Management
local settingsStore = SettingsStore.new(plugin, Config, Enums.scope, {
	defaultScope = Enums.scope.GLOBAL,
})

-- Playtest DataModels only relay output; syncing stays in the edit DataModel
if RunService:IsRunning() then
	const OutputRelay = require("@self/OutputRelay")
	if Config.STREAM_SOLO_OUTPUT then OutputRelay.start(Config.WS_URL) end
	return
end

const SyncSession = require("@self/SyncSession")

-- UI Apps
const azulApp = require("@self/App/UI")

const session = SyncSession.new(plugin, settingsStore, Config)

--[=[
    UI Callback Handlers
]=]
const uiCallbacks: azulApp.CallbackFunctions = {
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
		end
	end,

	onConfigChanged = function(key, value)
		session:debugPrint(
			`Config {key} updated to: {if type(value) == "table" then table.concat(value, ", ") else tostring(value)}`
		)
		Config[key] = value
		settingsStore:saveSettings() -- Playtest DataModels read settings when they start
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

local uiHelpers: azulApp.HelperFunctions = {
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
-- This configuration is sent to the Daemon on sync. It can be used to specify settings for this Place, such as push mappings.

-- More info:
-- https://azul.ransomwave.games/advanced/place-daemon-config/

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
const newAzulUI = azulApp.new(plugin, uiCallbacks, settingsStore:getScope(), uiHelpers)
session:setUI(newAzulUI)

-- Plugin Lifecycle
plugin.Unloading:Connect(function()
	session:stopAutoConnect()
	settingsStore:saveSettings()
	settingsStore:saveSelectedScope()
	session:stopSync()
end)

--- Formats a duration in seconds as e.g. "3 days".
local function formatDuration(seconds: number): string
	const units: { { seconds: number, name: string } } = {
		{ seconds = 86400, name = "day" },
		{ seconds = 3600, name = "hour" },
		{ seconds = 60, name = "minute" },
	}
	for _, unit in units do
		local count = seconds // unit.seconds
		if count >= 1 then return `{count} {unit.name}{if count == 1 then "" else "s"}` end
	end
	return "less than a minute"
end

if Config.AUTO_CONNECT then
	session:startAutoConnect()
else
	session:infoPrint("Plugin loaded. Click on the 'Azul' button to connect.")

	-- Remind to sync Places that were synced before
	local lastSynced = settingsStore:getLastSynced()
	if lastSynced and Config.SYNC_REMINDERS then
		newAzulUI:Notify(
			`You synced this Place with Azul {formatDuration(os.time() - lastSynced)} ago. Connect again?`,
			15,
			{
				{ Text = "Connect", Activated = uiCallbacks.onStartSync },
				{ Text = "Forget", Activated = function() settingsStore:forgetPlace() end },
			}
		)
	end
end

session:debugPrint("Debug mode is enabled!")
session:debugPrint(`Service list type is set to: "{Config.LIST_TYPE}"`)
