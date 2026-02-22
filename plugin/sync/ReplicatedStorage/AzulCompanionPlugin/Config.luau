local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(script.Parent.Enums)

configTable = {
	WS_URL = "ws://localhost:8080",
	HEARTBEAT_INTERVAL = 30,
	LIST_TYPE = Enums.listType.WHITELIST, -- or BLACKLIST
	SERVICE_LIST = {
		"Workspace",
		"Lighting",
		"ReplicatedFirst",
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterGui",
		"StarterPack",
		"StarterPlayer",
		"SoundService",
	},

	EXCLUDED_PARENTS = {
		"ServerStorage.RecPlugins", -- Folder managed by "Eye" plugin. It updates the sourcemap thousands of times. We don't need to track this.
		"Workspace.Surface Converter Storage", -- Folder managed by "Surface Converter" plugin. We don't need to track it.
	},

	DEBUG_MODE = false,
	SILENT_MODE = false,
}

return configTable
