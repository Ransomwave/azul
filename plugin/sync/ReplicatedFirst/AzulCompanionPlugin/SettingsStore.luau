--!strict
--[[
	Settings storage helper for Azul plugin config.
	Handles global/project scope selection and persisted config values.
]]

local SettingsStore = {}
SettingsStore.__index = SettingsStore

type ScopeEnum = {
	GLOBAL: string,
	PROJECT: string,
}

type SettingsStoreOptions = {
	settingsKey: string?,
	settingsScopeKey: string?,
	defaultScope: string?,
}

export type SettingsStore = {
	plugin: Plugin,
	config: { [string]: any },
	scopeEnum: ScopeEnum,
	settingsKey: string,
	settingsScopeKey: string,
	scope: string,
	storedSettings: { [string]: any },

	getScopeKey: (self: SettingsStore, scope: string) -> string,
	getPlaceScopeSelectionKey: (self: SettingsStore) -> string,
	saveSelectedScope: (self: SettingsStore) -> (),
	loadSelectedScope: (self: SettingsStore) -> (),
	saveSettings: (self: SettingsStore) -> (),
	loadSettings: (self: SettingsStore) -> (),
	getScope: (self: SettingsStore) -> string,
	setScope: (self: SettingsStore, newScope: string) -> (),
}

function SettingsStore.new(
	plugin: Plugin,
	config: { [string]: any },
	scopeEnum: ScopeEnum,
	options: SettingsStoreOptions?
): SettingsStore
	local self = setmetatable({}, SettingsStore)
	self.plugin = plugin
	self.config = config
	self.scopeEnum = scopeEnum
	self.settingsKey = if options and options.settingsKey then options.settingsKey else "AZUL_SETTINGS"
	self.settingsScopeKey = if options and options.settingsScopeKey
		then options.settingsScopeKey
		else "AZUL_SETTINGS_SCOPE_BY_PLACE"
	self.scope = if options and options.defaultScope then options.defaultScope else scopeEnum.GLOBAL
	self.storedSettings = {}

	self:loadSelectedScope()
	self:loadSettings()

	return (self :: any) :: SettingsStore
end

function SettingsStore:getScopeKey(scope: string): string
	local placeId = tostring(game.PlaceId or "0")
	if scope == self.scopeEnum.PROJECT then return `project_{placeId}` end
	return self.scopeEnum.GLOBAL
end

function SettingsStore:getPlaceScopeSelectionKey(): string
	return tostring(game.PlaceId or "0")
end

function SettingsStore:saveSelectedScope()
	local selectedScopes = self.plugin:GetSetting(self.settingsScopeKey)
	if type(selectedScopes) ~= "table" then selectedScopes = {} end

	selectedScopes[self:getPlaceScopeSelectionKey()] = self.scope
	self.plugin:SetSetting(self.settingsScopeKey, selectedScopes)
end

function SettingsStore:loadSelectedScope()
	local selectedScopes = self.plugin:GetSetting(self.settingsScopeKey)
	if type(selectedScopes) ~= "table" then return end

	local selectedScope = selectedScopes[self:getPlaceScopeSelectionKey()]
	if selectedScope == self.scopeEnum.GLOBAL or selectedScope == self.scopeEnum.PROJECT then
		self.scope = selectedScope
	end
end

function SettingsStore:saveSettings()
	local allSettings = self.plugin:GetSetting(self.settingsKey)
	if type(allSettings) ~= "table" then allSettings = {} end

	local scopeKey = self:getScopeKey(self.scope)
	local scopedCopy = {}
	for key, value in pairs(self.config) do
		scopedCopy[key] = value
	end

	-- Always persist debug/silent at the global level.
	local globalScoped = allSettings[self.scopeEnum.GLOBAL]
	if type(globalScoped) ~= "table" then globalScoped = {} end
	globalScoped.DEBUG_MODE = self.config.DEBUG_MODE
	globalScoped.SILENT_MODE = self.config.SILENT_MODE
	allSettings[self.scopeEnum.GLOBAL] = globalScoped

	allSettings[scopeKey] = scopedCopy
	self.storedSettings = allSettings
	self.plugin:SetSetting(self.settingsKey, allSettings)
end

function SettingsStore:loadSettings()
	local allSettings = self.plugin:GetSetting(self.settingsKey)
	if type(allSettings) ~= "table" then
		allSettings = {}

		-- Legacy flat settings fallback.
		for key, _ in pairs(self.config) do
			local legacyValue = self.plugin:GetSetting(key)
			if legacyValue ~= nil then self.config[key] = legacyValue end
		end

		self.storedSettings = allSettings
		return
	end

	self.storedSettings = allSettings

	local scopeKey = self:getScopeKey(self.scope)
	local scoped = allSettings[scopeKey]
	local globalScoped = allSettings[self.scopeEnum.GLOBAL]

	if type(scoped) ~= "table" then scoped = {} end
	if type(globalScoped) ~= "table" then globalScoped = {} end

	for key, _ in pairs(self.config) do
		local value = scoped[key]
		if value == nil and scopeKey ~= self.scopeEnum.GLOBAL then value = globalScoped[key] end
		if value ~= nil then self.config[key] = value end
	end

	-- DEBUG_MODE and SILENT_MODE always come from global.
	if globalScoped.DEBUG_MODE ~= nil then self.config.DEBUG_MODE = globalScoped.DEBUG_MODE end
	if globalScoped.SILENT_MODE ~= nil then self.config.SILENT_MODE = globalScoped.SILENT_MODE end
end

function SettingsStore:getScope(): string
	return self.scope
end

function SettingsStore:setScope(newScope: string)
	if newScope ~= self.scopeEnum.GLOBAL and newScope ~= self.scopeEnum.PROJECT then return end
	if newScope == self.scope then return end

	self:saveSettings()
	self.scope = newScope
	self:saveSelectedScope()
	self:loadSettings()
end

return SettingsStore
