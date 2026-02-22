--!strict
--[[
	Azul UI Module
	Manages the companion plugin's dock widget and settings interface
]]

local UI = {}

local Config = require(script.Parent.Config)
local Enums = require(script.Parent.Enums)

UI.__index = UI

type CallbackFunctions = {
	onStartSync: () -> (),
	onStopSync: () -> (),
	onDebugModeChanged: (boolean) -> ()?,
	onSilentModeChanged: (boolean) -> ()?,
	onConfigChanged: (string, any) -> (),
	onSettingsScopeChanged: (number) -> (),
	onClearGuids: () -> (),
}

type SelfType = {
	plugin: Plugin,
	config: { any },
	callbacks: CallbackFunctions,
	LOGO: string,
	LOGO_SYNCED: string,
	settingsScope: string,
	debugPrint: (...string) -> (),
	infoPrint: (...string) -> (),
	saveSettings: () -> (),
	loadSettings: () -> (),
	rebuildServiceSet: () -> (),

	isSyncEnabled: boolean,

	azulWidget: DockWidgetPluginGui,
	connectButton: PluginToolbarButton,
	titleImageLabel: ImageLabel,
	syncButton: any,
	debugModeCheckbox: any,
	silentModeCheckbox: any,
	settingsScopeDropdown: any,
	websocketUrlLabel: any,
	heartbeatIntervalLabel: any,
	listTypeLabel: any,
	serviceListLabel: any,
	excludedParentsLabel: any,
	clearGuidsButton: any,

	GetSyncState: (SelfType) -> boolean,
	UpdateSyncState: (SelfType, boolean) -> (),
	UpdateConfig: (SelfType) -> (),
	SetSettingsScope: (SelfType, any) -> (),
}

UI.logo = "rbxassetid://134336592598474"
UI.syncedLogo = "rbxassetid://103599828888609"

local function createInfoLabel(text: string)
	local label = Instance.new("TextLabel")
	label.Name = "InfoLabel"
	label.RichText = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.Size = UDim2.new(1, 0, 0, 15)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(0.5, 0.5, 0.5)
	label.Font = Enum.Font.SourceSans
	label.TextSize = 15
	label.Text = `{text}<br/>`
	label.TextXAlignment = Enum.TextXAlignment.Left

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 30)
	padding.PaddingRight = UDim.new(0, 30)
	padding.Parent = label

	return label
end

--[=[
	Initialize the UI widget
	
	Parameters:
	- plugin: The plugin object from the Roblox plugin API
	- config: Reference to the CONFIG table
	- settingsScope: Reference to the settingsScope variable`
	- callbacks: Table with callbacks:
	  - onStartSync: Called when user clicks Connect
	  - onStopSync: Called when user clicks Disconnect
	  - onDebugModeChanged: Called when debug mode checkbox changes
	  - onSilentModeChanged: Called when silent mode checkbox changes
	  - onConfigChanged: Called when any config value changes (receives {key, value})
	  - onSettingsScopeChanged: Called when scope changes
	  - onClearGuids: Called when clear GUIDs button is clicked
	- helpers: Table with helper functions:
	  - debugPrint: Debug print function
	  - infoPrint: Info print function
	  - saveSettings: Save settings function
	  - loadSettings: Load settings function
	  - rebuildServiceSet: Rebuild service set function
	
	Returns: Table with methods:
	- updateSyncState(enabled: boolean): Update UI to reflect sync state
	- updateConfig(): Refresh UI with current CONFIG values
]=]
function UI.new(plugin, callbacks, settingsScope, helpers): SelfType
	local self = {} :: SelfType
	setmetatable(self, UI)

	-- Store references
	self.plugin = plugin
	self.callbacks = callbacks
	self.LOGO = UI.logo
	self.LOGO_SYNCED = UI.syncedLogo
	self.settingsScope = settingsScope
	self.debugPrint = helpers.debugPrint
	self.infoPrint = helpers.infoPrint
	self.saveSettings = helpers.saveSettings
	self.loadSettings = helpers.loadSettings
	self.rebuildServiceSet = helpers.rebuildServiceSet

	-- Track sync enabled state locally (PluginToolbarButton has SetActive but no GetActive)
	self.isSyncEnabled = false

	-- Import UI components
	local parentFolder = script.Parent
	local studioWidgets = parentFolder:FindFirstChild("StudioWidgets")
	local components = studioWidgets:FindFirstChild("Components")
	local VerticalScrollingFrame = require(components:FindFirstChild("VerticalScrollingFrame"))
	local CollapsibleTitledSection = require(components:FindFirstChild("CollapsibleTitledSection"))
	local CustomTextButton = require(components:FindFirstChild("CustomTextButton"))
	local LabeledCheckbox = require(components:FindFirstChild("LabeledCheckbox"))
	local LabeledMultiChoice = require(components:FindFirstChild("LabeledMultiChoice"))
	local LabeledTextInput = require(components:FindFirstChild("LabeledTextInput"))
	local DropdownMenu = require(components:FindFirstChild("DropdownMenu"))

	-- Create toolbar button
	local toolbar = plugin:CreateToolbar("Azul")
	self.connectButton = toolbar:CreateButton("Azul", "Connect/disconnect from sync daemon", self.LOGO)

	-- Create widget
	local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, true, 345, 640, 300, 300)

	local azulWidget = plugin:CreateDockWidgetPluginGuiAsync("azulWidget", widgetInfo)
	azulWidget.Name = "AzulCompanionPlugin"
	azulWidget.Title = "Azul"
	self.azulWidget = azulWidget

	-- Create main scroll frame
	local mainScrollFrame = VerticalScrollingFrame.new("main")
	mainScrollFrame:GetContentsFrame().Parent = azulWidget

	local mainSectionListLayout = Instance.new("UIListLayout")
	mainSectionListLayout.Parent = mainScrollFrame:GetSectionFrame()
	mainSectionListLayout.Padding = UDim.new(0, 0)
	mainSectionListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainSectionListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- Main section
	local mainSection = CollapsibleTitledSection.new("mainSection", "Azul Companion Plugin", true, false, false)
	mainSection:GetSectionFrame().LayoutOrder = 0
	mainSection:GetSectionFrame().Parent = mainScrollFrame:GetContentsFrame()

	-- Title image
	local titleImageLabel = Instance.new("ImageLabel")
	titleImageLabel.Size = UDim2.new(1, 0, 0, 50)
	titleImageLabel.BackgroundTransparency = 1
	titleImageLabel.Image = self.LOGO
	titleImageLabel.ScaleType = Enum.ScaleType.Fit
	mainSection:AddChild(titleImageLabel, 0)
	self.titleImageLabel = titleImageLabel

	-- Sync button
	local syncButton = CustomTextButton.new("toggleSync", "Connect", false)
	syncButton.Parent = mainScrollFrame:GetContentsFrame()
	syncButton:SetSize(UDim2.fromScale(1, 0.25))

	local syncButtonPadding = Instance.new("UIPadding")
	syncButtonPadding.PaddingLeft = UDim.new(0.1, 0)
	syncButtonPadding.PaddingRight = UDim.new(0.1, 0)
	syncButtonPadding.Parent = syncButton:GetFrame()

	syncButton:SetClickedFunction(function()
		if self.isSyncEnabled then
			syncButton:GetButton().Text = "Stopping..."
			self.callbacks.onStopSync()
		else
			syncButton:GetButton().Text = "Connecting..."
			self.callbacks.onStartSync()
		end
	end)
	mainSection:AddChild(syncButton:GetFrame())
	self.syncButton = syncButton

	-- Debug Mode checkbox
	local debugModeCheckbox = LabeledCheckbox.new("debugMode", "Debug Mode", Config.DEBUG_MODE, false)
	debugModeCheckbox:SetValue(Config.DEBUG_MODE)
	debugModeCheckbox:SetValueChangedFunction(function(newValue)
		Config.DEBUG_MODE = newValue
		helpers.debugPrint(`[🐛 AzulUI]: Debug mode set to: {newValue}`)
	end)
	mainSection:AddChild(debugModeCheckbox:GetFrame())
	mainSection:AddChild(createInfoLabel("Debug mode enables verbose logging to the output console."))
	self.debugModeCheckbox = debugModeCheckbox

	-- Silent Mode checkbox
	local silentModeCheckbox = LabeledCheckbox.new("silentMode", "Silent Mode", Config.SILENT_MODE, false)
	silentModeCheckbox:SetValue(Config.SILENT_MODE)
	silentModeCheckbox:SetValueChangedFunction(function(newValue)
		Config.SILENT_MODE = newValue
		helpers.infoPrint(`[🐛 AzulUI]: Silent mode set to: {newValue}`)
	end)
	mainSection:AddChild(silentModeCheckbox:GetFrame())
	mainSection:AddChild(createInfoLabel("Silent mode suppresses all console output except errors."))
	self.silentModeCheckbox = silentModeCheckbox

	-- Settings section
	local settingsSection = CollapsibleTitledSection.new("settings", "Plugin Settings", true, true, true)
	settingsSection:GetSectionFrame().LayoutOrder = 1
	settingsSection:GetSectionFrame().Parent = mainScrollFrame:GetContentsFrame()

	-- Settings scope dropdown
	local scopeChoices = {
		{ Id = 1, Text = "Global" },
		{ Id = 2, Text = "Project" },
	}
	local settingsScopeDropdown = DropdownMenu.new("settingsScope", "Scope", scopeChoices, "Select ...")
	settingsSection:AddChild(settingsScopeDropdown:GetSectionFrame())
	self.settingsScopeDropdown = settingsScopeDropdown

	-- WebSocket URL input
	local websocketUrlLabel = LabeledTextInput.new("websocketUrl", "WebSocket URL:", Config.WS_URL)
	websocketUrlLabel:SetValue(Config.WS_URL)
	websocketUrlLabel:SetValueChangedFunction(function(newValue)
		Config.WS_URL = newValue
		self.callbacks.onConfigChanged("WS_URL", newValue)
	end)
	settingsSection:AddChild(websocketUrlLabel:GetFrame())
	self.websocketUrlLabel = websocketUrlLabel

	-- Heartbeat Interval input
	local heartbeatIntervalLabel =
		LabeledTextInput.new("heartbeatInterval", "Heartbeat Interval (s):", tostring(Config.HEARTBEAT_INTERVAL))
	heartbeatIntervalLabel:SetValue(tostring(Config.HEARTBEAT_INTERVAL))
	heartbeatIntervalLabel:SetValueChangedFunction(function(newValue)
		local interval = tonumber(newValue)
		if interval and interval > 0 then
			Config.HEARTBEAT_INTERVAL = interval
			self.callbacks.onConfigChanged("HEARTBEAT_INTERVAL", interval)
		end
	end)
	settingsSection:AddChild(heartbeatIntervalLabel:GetFrame())
	settingsSection:AddChild(createInfoLabel("Interval in seconds between heartbeat pings to the daemon."))
	self.heartbeatIntervalLabel = heartbeatIntervalLabel

	-- List type dropdown
	local listTypeLabel = LabeledMultiChoice.new("listType", "Service List Type:", {
		{ Id = "WHITELIST", Text = "Whitelist" },
		{ Id = "BLACKLIST", Text = "Blacklist" },
	}, if Config.LIST_TYPE == Enums.listType.WHITELIST then 1 else 2)
	listTypeLabel:SetValueChangedFunction(function(newIndex)
		if newIndex == 1 then
			Config.LIST_TYPE = Enums.listType.WHITELIST
		else
			Config.LIST_TYPE = Enums.listType.BLACKLIST
		end
		self.callbacks.onConfigChanged("LIST_TYPE", Config.LIST_TYPE)
	end)
	settingsSection:AddChild(listTypeLabel:GetFrame())
	settingsSection:AddChild(
		createInfoLabel(
			"Whitelist: only services in the list are synced.<br />Blacklist: services in the list are excluded."
		)
	)
	self.listTypeLabel = listTypeLabel

	-- Service List input
	local serviceListLabel =
		LabeledTextInput.new("serviceList", "Service List:", table.concat(Config.SERVICE_LIST, ", "))
	serviceListLabel:SetMaxGraphemes(9999)
	serviceListLabel:SetValue(table.concat(Config.SERVICE_LIST, ", "))
	serviceListLabel:SetValueChangedFunction(function(newValue)
		local services = {}
		for serviceName in string.gmatch(newValue, "([^,%s]+)") do
			table.insert(services, serviceName)
		end
		Config.SERVICE_LIST = services
		self.rebuildServiceSet()
		self.callbacks.onConfigChanged("SERVICE_LIST", services)
	end)
	settingsSection:AddChild(serviceListLabel:GetFrame())
	settingsSection:AddChild(createInfoLabel("List of services to include/exclude based on the selected List Type."))
	self.serviceListLabel = serviceListLabel

	-- Excluded Parents input
	local excludedParentsLabel =
		LabeledTextInput.new("excludedParents", "Excluded Parents:", table.concat(Config.EXCLUDED_PARENTS, ", "))
	excludedParentsLabel:SetValue(table.concat(Config.EXCLUDED_PARENTS, ", "))
	excludedParentsLabel:SetValueChangedFunction(function(newValue)
		local excluded = {}
		for parentName in string.gmatch(newValue, "([^,%s]+)") do
			table.insert(excluded, parentName)
		end
		Config.EXCLUDED_PARENTS = excluded
		self.callbacks.onConfigChanged("EXCLUDED_PARENTS", excluded)
	end)
	settingsSection:AddChild(excludedParentsLabel:GetFrame())
	settingsSection:AddChild(createInfoLabel("List of parent paths to exclude from syncing, separated by commas."))
	self.excludedParentsLabel = excludedParentsLabel

	settingsScopeDropdown:SetValue(if self.settingsScope == Enums.scope.GLOBAL then 1 else 2)

	-- Settings scope callback
	settingsScopeDropdown:SetValueChangedFunction(function(newValue: number | string, newText: string)
		helpers.debugPrint("[🐛 AzulUI]: Settings scope changed to:", newText)

		local newScope
		if newValue == 1 then
			newScope = Enums.scope.GLOBAL
		elseif newValue == 2 then
			newScope = Enums.scope.PROJECT
		else
			return
		end

		self.callbacks.onSettingsScopeChanged(newScope)
	end)

	-- Clear legacy GUIDs button
	local clearGuidsButton = CustomTextButton.new("clearLegacyGUIDs", "Clear Legacy GUIDs", false)
	clearGuidsButton:SetClickedFunction(function()
		self.callbacks.onClearGuids()
	end)
	clearGuidsButton:SetSize(UDim2.fromScale(1, 0.1))

	local clearButtonPadding = Instance.new("UIPadding")
	clearButtonPadding.PaddingLeft = UDim.new(0.1, 0)
	clearButtonPadding.PaddingRight = UDim.new(0.1, 0)
	clearButtonPadding.Parent = clearGuidsButton:GetFrame()

	settingsSection:AddChild(clearGuidsButton:GetFrame())
	settingsSection:AddChild(
		createInfoLabel(
			"Removes all stored GUID attributes from instances in the DataModel. Use this to clean GUIDs left by old versions of Azul."
		)
	)
	self.clearGuidsButton = clearGuidsButton

	-- Connect button click handler
	self.connectButton.Click:Connect(function()
		azulWidget.Enabled = not azulWidget.Enabled
	end)

	return (self :: any) :: SelfType
end

function UI:GetSyncState()
	return self.isSyncEnabled
end

function UI:UpdateSyncState(enabled: boolean)
	self.isSyncEnabled = enabled
	self.connectButton:SetActive(enabled)
	if enabled then
		self.connectButton.Icon = self.LOGO_SYNCED
		self.syncButton:GetButton().Text = "Disconnect"
		self.titleImageLabel.Image = self.LOGO_SYNCED
	else
		self.connectButton.Icon = self.LOGO
		self.syncButton:GetButton().Text = "Connect"
		self.titleImageLabel.Image = self.LOGO
	end
end

function UI:SetSettingsScope(scope)
	self.settingsScope = scope
end

function UI:UpdateConfig()
	self = self :: SelfType

	self.debugModeCheckbox:SetValue(Config.DEBUG_MODE)
	self.silentModeCheckbox:SetValue(Config.SILENT_MODE)
	self.settingsScopeDropdown:SetValue(if self.settingsScope == Enums.scope.GLOBAL then 1 else 2)
	self.websocketUrlLabel:SetValue(Config.WS_URL)
	self.heartbeatIntervalLabel:SetValue(tostring(Config.HEARTBEAT_INTERVAL))
	self.listTypeLabel:SetSelectedIndex(if Config.LIST_TYPE == Enums.listType.WHITELIST then 1 else 2)
	self.serviceListLabel:SetValue(table.concat(Config.SERVICE_LIST, ", "))
	self.excludedParentsLabel:SetValue(table.concat(Config.EXCLUDED_PARENTS, ", "))
end

return UI
