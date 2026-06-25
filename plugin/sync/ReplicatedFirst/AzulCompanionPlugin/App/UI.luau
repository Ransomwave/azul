local ReplicatedFirst = game:GetService("ReplicatedFirst")

--[[
	Azul UI Module
	Component-based dock widget UI for the companion plugin
]]

local UI = {}

local AzulService = require("../AzulService")
local Config = require("../Config")
local Enums = require("../Enums")

local fusion = require("../Packages/fusion")
local Theme = require("./Theme")
local Toolbar = require("./Components/Plugin/Toolbar")
local ToolbarButton = require("./Components/Plugin/ToolbarButton")
local Widget = require("./Components/Plugin/Widget")
local Container = require("./Components/Container")
local List = require("./Components/List")
local Padding = require("./Components/Padding")
local Image = require("./Components/Image")
local Text = require("./Components/Text")
local TextButton = require("./Components/TextButton")
local Checkbox = require("./Components/Checkbox")
local OptionSelector = require("./Components/OptionSelector")
local Input = require("./Components/Input")
local ScrollingContainer = require("./Components/ScrollingContainer")
local Box = require("./Components/Box")

local Value = fusion.Value
local Computed = fusion.Computed
local Children = fusion.Children
local OnEvent = fusion.OnEvent
local Ref = fusion.Ref
local Observer = fusion.Observer
local peek = fusion.peek

UI.__index = UI

export type CallbackFunctions = {
	onStartSync: () -> (),
	onStopSync: () -> (),
	onAutoConnectChanged: (boolean) -> ()?,
	onDebugModeChanged: (boolean) -> ()?,
	onSilentModeChanged: (boolean) -> ()?,
	onConfigChanged: (string, any) -> (),
	onSettingsScopeChanged: (string) -> (),
	onSourcemapReload: () -> (),
}

type AzulUI = {
	plugin: Plugin,
	config: { any },
	callbacks: CallbackFunctions,
	LOGO: string,
	LOGO_SYNCED: string,
	settingsScope: string,
	rebuildServiceSet: () -> (),

	isSyncEnabled: boolean,

	azulWidget: DockWidgetPluginGui,
	connectButton: PluginToolbarButton,

	icon: fusion.Value<string>,
	isOpen: fusion.Value<boolean>,
	syncEnabled: fusion.Value<boolean>,
	handshakeComplete: fusion.Value<boolean>,
	autoConnect: fusion.Value<boolean>,
	debugMode: fusion.Value<boolean>,
	silentMode: fusion.Value<boolean>,
	settingsScopeValue: fusion.Value<string>,
	listTypeValue: fusion.Value<string>,

	wsUrlRef: fusion.Value<TextBox?>,
	heartbeatRef: fusion.Value<TextBox?>,
	batchIdleRef: fusion.Value<TextBox?>,
	scriptDebounceRef: fusion.Value<TextBox?>,

	maxConnectionsRef: fusion.Value<TextBox?>,
	maxReconnectionsRef: fusion.Value<TextBox?>,
	reconnectionIntervalRef: fusion.Value<TextBox?>,
	
	serviceListRef: fusion.Value<TextBox?>,
	excludedParentsRef: fusion.Value<TextBox?>,

	GetSyncState: (AzulUI) -> boolean,
	UpdateSyncState: (AzulUI, boolean) -> (),
	UpdateHandshakeState: (AzulUI, boolean) -> (),
	UpdateConfig: (AzulUI) -> (),
	SetSettingsScope: (AzulUI, any) -> (),
}

UI.logo = "rbxassetid://134336592598474"
UI.syncedLogo = "rbxassetid://103599828888609"

local function infoPrint(...)
	print(`[Azul]: `, ...)
end

local function debugPrint(...)
	if not Config.DEBUG_MODE then return end
	print(`[🐛 Azul::{script}]: `, ...)
end

--- Utility function to validate number input from TextBoxes. If the number is valid, it calls the provided callback with the number value.
local function validateNumberInput(newValue: string, callback: (number) -> (), allowNegative: boolean?)
	local numberValue = tonumber(newValue)

	if not numberValue then
		warn(`[Azul::{script}]: Invalid number input: {newValue}`)
		return
	end

	if not allowNegative and numberValue <= 0 then
		warn(`[Azul::{script}]: Number input must be greater than 0: {newValue}`)
		return
	elseif numberValue == 0 then
		warn(`[Azul::{script}]: Number input cannot be 0`)
		return
	end

	callback(numberValue)
end

local function section(title: string, children: { Instance })
	return Container({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			List({
				Spacing = 6,
			}),
			Text({
				Text = title,
				FontFace = Theme.Fonts.Bold,
				TextSize = Theme.TextSize.Medium,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			}),
			children,
		},
	})
end

local function infoText(text: string)
	return Text({
		Text = text,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextDimmed,
		RichText = true,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
end

local function labeledToggle(label: string, value: fusion.Value<boolean>, changed: (boolean) -> ())
	return Container({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			List({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Spacing = 8,
			}),
			Checkbox({
				Value = value,
				Changed = changed,
			}),
			Text({
				Text = label,
				TextSize = Theme.TextSize.Medium,
				AutomaticSize = Enum.AutomaticSize.XY,
			}),
		},
	})
end

local function labeledInput(label: string, ref: fusion.Value<TextBox?>, props: { [string]: any })
	return Container({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			List({
				Spacing = 4,
			}),
			Text({
				Text = label,
				TextSize = Theme.TextSize.Small,
				Color = Theme.Colors.TextDimmed,
				AutomaticSize = Enum.AutomaticSize.XY,
			}),
			Box({
				Size = props.BoxSize or UDim2.new(1, 0, 0, Theme.CompSizeY.Medium),
				AutomaticSize = Enum.AutomaticSize.None,
				[Children] = {
					Padding({
						Padding = 6,
						Vertical = false,
					}),
					Input {
						Text = props.Text or "",
						PlaceholderText = props.Placeholder or "",
						TextWrapped = props.TextWrapped or false,
						MultiLine = props.MultiLine or false,
						ClearTextOnFocus = false,
						Size = UDim2.fromScale(1, 1),
						[Ref] = ref,
						Changed = props.Changed,
						Finished = props.Finished,
					},
				},
			}),
		},
	})
end

--[=[
	Initializes the plugin UI, sets up callbacks, and manages sync state
]=]
function UI.new(plugin, callbacks, settingsScope, helpers): AzulUI
	local self = {} :: AzulUI
	setmetatable(self, UI)

	-- Store references
	self.plugin = plugin
	self.callbacks = callbacks
	self.LOGO = UI.logo
	self.LOGO_SYNCED = UI.syncedLogo
	self.settingsScope = settingsScope
	self.rebuildServiceSet = helpers.rebuildServiceSet

	-- Track sync enabled state locally
	self.isSyncEnabled = false

	self.icon = Value(self.LOGO)
	self.isOpen = Value(true)
	self.syncEnabled = Value(false)
	self.handshakeComplete = Value(false)
	self.autoConnect = Value(Config.AUTO_CONNECT)
	self.debugMode = Value(Config.DEBUG_MODE)
	self.silentMode = Value(Config.SILENT_MODE)
	self.settingsScopeValue = Value(settingsScope == Enums.scope.GLOBAL and "Global" or "Project")
	self.listTypeValue = Value(Config.LIST_TYPE == Enums.listType.WHITELIST and "Whitelist" or "Blacklist")

	self.wsUrlRef = Value(nil)
	self.heartbeatRef = Value(nil)
	self.batchIdleRef = Value(nil)
	self.scriptDebounceRef = Value(nil)

	self.maxHandshakesRef = Value(nil)
	self.maxReconnectionsRef = Value(nil)
	self.reconnectionIntervalRef = Value(nil)

	self.serviceListRef = Value(nil)
	self.excludedParentsRef = Value(nil)

	self.connectButton = ToolbarButton({
		Toolbar = Toolbar({
			Name = "Azul",
		}),
		Name = "Azul",
		ToolTip = "Open Azul",
		Image = self.icon,
		[OnEvent("Click")] = function()
			self.isOpen:set(not peek(self.isOpen))
		end,
	})

	local widget = Widget({
		Name = "Azul",
		Id = "Azul",
		MinimumSize = Vector2.new(300, 300),
		FloatingSize = Vector2.new(345, 640),
		InitialDockTo = Enum.InitialDockState.Float,
		InitialEnabled = true,
		Enabled = self.isOpen,
		[Children] = {
			Container({
				Size = UDim2.fromScale(1, 1),
				AutomaticSize = Enum.AutomaticSize.None,
				BackgroundColor3 = Theme.Colors.Background,
				BackgroundTransparency = 0,
				[Children] = {
					ScrollingContainer({
						ScrollBar = true,
						[Children] = {
							Padding {
								Padding = Theme.WidgetPadding,
							},
							List({
								Spacing = Theme.ListSpacing,
							}),
							Container({
								Size = UDim2.fromScale(1, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								[Children] = {
									List({
										FillDirection = Enum.FillDirection.Horizontal,
										HorizontalAlignment = Enum.HorizontalAlignment.Center,
										VerticalAlignment = Enum.VerticalAlignment.Center,
										Spacing = 10,
									}),
									Image({
										Size = UDim2.fromOffset(36, 36),
										Image = self.icon,
									}),
									Text({
										Text = "Azul",
										FontFace = Theme.Fonts.Mono,
										TextSize = Theme.TextSize.Heading,

										AutomaticSize = Enum.AutomaticSize.XY,
									}),
								},
							}),
							TextButton({
								Text = Computed(function(use)
									if not use(self.syncEnabled) then return "Connect" end
									if use(self.handshakeComplete) then return "Disconnect" end
									return "Awaiting Daemon..."
								end),
								Size = UDim2.new(1, 0, 0, Theme.CompSizeY.Large),
								Solid = true,
								Activated = function()
									if peek(self.syncEnabled) then
										self.callbacks.onStopSync()
									else
										self.callbacks.onStartSync()
									end
								end,
							}),
							section("Behavior", {
								labeledToggle("Auto Connect", self.autoConnect, function(newValue)
									Config.AUTO_CONNECT = newValue
									if self.callbacks.onAutoConnectChanged then
										self.callbacks.onAutoConnectChanged(newValue)
									end
								end),
								infoText("Automatically attempts to connect to Daemon."),
								labeledToggle("Silent Mode", self.silentMode, function(newValue)
									Config.SILENT_MODE = newValue
									if self.callbacks.onSilentModeChanged then
										self.callbacks.onSilentModeChanged(newValue)
									end
								end),
								infoText("Suppresses all console output except errors."),
								labeledToggle("Debug Mode", self.debugMode, function(newValue)
									Config.DEBUG_MODE = newValue
									if self.callbacks.onDebugModeChanged then
										self.callbacks.onDebugModeChanged(newValue)
									end
								end),
								infoText("Enables verbose logging in the output console."),
								Text({
									Text = "Settings Scope",
									TextSize = Theme.TextSize.Small,
									Color = Theme.Colors.TextDimmed,
									AutomaticSize = Enum.AutomaticSize.XY,
								}),
								OptionSelector({
									Options = { "Global", "Project" },
									Value = self.settingsScopeValue,
									Selected = function(option)
										local scope = option == "Global" and Enums.scope.GLOBAL or Enums.scope.PROJECT
										self.callbacks.onSettingsScopeChanged(scope)
									end,
								}),
							}),
							section("Connection", {
								labeledInput("WebSocket URL", self.wsUrlRef, {
									Text = "ws://localhost:8080",
									Finished = function(text)
										if text == "" then return end
										self.callbacks.onConfigChanged("WS_URL", text)
									end,
								}),
								labeledInput("Heartbeat Interval (seconds)", self.heartbeatRef, {
									Text = tostring(Config.HEARTBEAT_INTERVAL),
									Finished = function(text)
										if text == "" then return end
										validateNumberInput(text, function(value)
											self.callbacks.onConfigChanged("HEARTBEAT_INTERVAL", value)
										end)
									end,
								}),
								labeledInput("Batch Idle Window (seconds)", self.batchIdleRef, {
									Text = tostring(Config.BATCH_IDLE_WINDOW),
									Finished = function(text)
										if text == "" then return end
										validateNumberInput(text, function(value)
											self.callbacks.onConfigChanged("BATCH_IDLE_WINDOW", value)
										end)
									end,
								}),
								labeledInput("Script Change Debounce (seconds)", self.scriptDebounceRef, {
									Text = tostring(Config.SCRIPT_CHANGE_DEBOUNCE),
									Finished = function(text)
										if text == "" then return end
										validateNumberInput(text, function(value)
											self.callbacks.onConfigChanged("SCRIPT_CHANGE_DEBOUNCE", value)
										end)
									end,
								}),
							}),
							section("Auto Connect", {
								labeledInput("Maximum Handshake Attempts", self.maxHandshakesRef, {
									Text = tostring(Config.MAX_HANDSHAKES),
									Finished = function(text)
										if text == "" then return end
										validateNumberInput(text, function(value)
											self.callbacks.onConfigChanged("MAX_HANDSHAKES", value)
										end)
									end,
								}),
								labeledInput("Maximum Reconnection Attempts", self.maxReconnectionsRef, {
									Text = tostring(Config.MAX_RECONNECTIONS),
									Placeholder = "-1 for infinite attempts",
									Finished = function(text)
										if text == "" then return end
										validateNumberInput(text, function(value)
											self.callbacks.onConfigChanged("MAX_RECONNECTIONS", value)
										end, true)
									end,
								}),
								labeledInput("Reconnection Interval (seconds)", self.reconnectionIntervalRef, {
									Text = tostring(Config.RECONNECTION_INTERVAL),
									Finished = function(text)
										if text == "" then return end
										validateNumberInput(text, function(value)
											self.callbacks.onConfigChanged("RECONNECTION_INTERVAL", value)
										end)
									end,
								}),
							}),
							section("Filters", {
								Text({
									Text = "List Type",
									TextSize = Theme.TextSize.Small,
									Color = Theme.Colors.TextDimmed,
									AutomaticSize = Enum.AutomaticSize.XY,
								}),
								OptionSelector({
									Options = { "Whitelist", "Blacklist" },
									Value = self.listTypeValue,
									Selected = function(option)
										self.callbacks.onConfigChanged(
											"LIST_TYPE",
											option == "Whitelist" and Enums.listType.WHITELIST
												or Enums.listType.BLACKLIST
										)
									end,
								}),
								labeledInput("Service List (comma-separated)", self.serviceListRef, {
									Text = table.concat(Config.SERVICE_LIST, ", "),
									-- MultiLine = true,
									BoxSize = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium * 2),
									Finished = function(text)
										local items = AzulService.parseCommaSeparatedList(text)
										self.callbacks.onConfigChanged("SERVICE_LIST", items)
									end,
								}),
								labeledInput("Excluded Parents (comma-separated)", self.excludedParentsRef, {
									Text = table.concat(Config.EXCLUDED_PARENTS, ", "),
									-- MultiLine = true,
									BoxSize = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium * 2),
									Finished = function(text)
										local items = AzulService.parseCommaSeparatedList(text)
										self.callbacks.onConfigChanged("EXCLUDED_PARENTS", items)
									end,
								}),
							}),
							section("Tools", {
								TextButton {
									Text = "Reload Sourcemap",
									Size = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium),
									Activated = function()
										self.callbacks.onSourcemapReload()
									end,
								},
								TextButton {
									Text = "Open Place Configuration",
									Size = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium),
									Activated = function()
										helpers.openPlaceConfig()
									end,
								},
							}),
							Text {
								Text = `Azul Plugin v{AzulService.VERSION}`,
								TextSize = Theme.TextSize.Small,
								Color = Theme.Colors.TextDimmed,
								AutomaticSize = Enum.AutomaticSize.XY,
							},
						},
					}),
				},
			}),
		},
	})

	self.azulWidget = widget

	plugin.Unloading:Once(Observer(self.isOpen):onChange(function()
		self.connectButton:SetActive(peek(self.isOpen))
	end))

	self.connectButton:SetActive(peek(self.isOpen))

	return self
end

function UI:GetSyncState()
	return self.isSyncEnabled
end

function UI:UpdateSyncState(enabled: boolean)
	self.isSyncEnabled = enabled
	self.syncEnabled:set(enabled)
	self.icon:set(if enabled then self.LOGO_SYNCED else self.LOGO)
	if not enabled then self.handshakeComplete:set(false) end
end

function UI:UpdateHandshakeState(complete: boolean)
	self.handshakeComplete:set(complete)
end

function UI:SetSettingsScope(scope)
	self.settingsScope = scope
	self.settingsScopeValue:set(if scope == Enums.scope.GLOBAL then "Global" else "Project")
end

function UI:UpdateConfig()
	self = self :: AzulUI

	self.autoConnect:set(Config.AUTO_CONNECT)
	self.debugMode:set(Config.DEBUG_MODE)
	self.silentMode:set(Config.SILENT_MODE)
	self.settingsScopeValue:set(if self.settingsScope == Enums.scope.GLOBAL then "Global" else "Project")
	self.listTypeValue:set(if Config.LIST_TYPE == Enums.listType.WHITELIST then "Whitelist" else "Blacklist")

	local wsUrlInput = peek(self.wsUrlRef)
	if wsUrlInput then wsUrlInput.Text = Config.WS_URL end

	local heartbeatInput = peek(self.heartbeatRef)
	if heartbeatInput then heartbeatInput.Text = tostring(Config.HEARTBEAT_INTERVAL) end

	local batchIdleInput = peek(self.batchIdleRef)
	if batchIdleInput then batchIdleInput.Text = tostring(Config.BATCH_IDLE_WINDOW) end

	local scriptDebounceInput = peek(self.scriptDebounceRef)
	if scriptDebounceInput then scriptDebounceInput.Text = tostring(Config.SCRIPT_CHANGE_DEBOUNCE) end


	local maxConnectionsInput = peek(self.maxHandshakesRef)
	if maxConnectionsInput then maxConnectionsInput.Text = tostring(Config.MAX_HANDSHAKES) end

	local maxReconnectionsInput = peek(self.maxReconnectionsRef)
	if maxReconnectionsInput then maxReconnectionsInput.Text = tostring(Config.MAX_RECONNECTIONS) end

	local reconnectionIntervalInput = peek(self.reconnectionIntervalRef)
	if reconnectionIntervalInput then reconnectionIntervalInput.Text = tostring(Config.RECONNECTION_INTERVAL) end


	local serviceListInput = peek(self.serviceListRef)
	if serviceListInput then serviceListInput.Text = table.concat(Config.SERVICE_LIST, ", ") end

	local excludedParentsInput = peek(self.excludedParentsRef)
	if excludedParentsInput then excludedParentsInput.Text = table.concat(Config.EXCLUDED_PARENTS, ", ") end
end

return UI