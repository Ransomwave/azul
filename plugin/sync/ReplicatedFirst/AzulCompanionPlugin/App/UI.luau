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
local Notifications = require("./Components/Notifications")

-- Registered on the root scope, so they can be used as `scope:Name { ... }`
local Components = {
	Box = require("./Components/Box"),
	Checkbox = require("./Components/Checkbox"),
	Container = require("./Components/Container"),
	Image = require("./Components/Image"),
	Input = require("./Components/Input"),
	List = require("./Components/List"),
	Notifications = Notifications,
	OptionSelector = require("./Components/OptionSelector"),
	Padding = require("./Components/Padding"),
	ScrollingContainer = require("./Components/ScrollingContainer"),
	Slider = require("./Components/Slider"),
	Text = require("./Components/Text"),
	TextButton = require("./Components/TextButton"),
	Toolbar = require("./Components/Plugin/Toolbar"),
	ToolbarButton = require("./Components/Plugin/ToolbarButton"),
	Widget = require("./Components/Plugin/Widget"),
}

local Children = fusion.Children
local OnEvent = fusion.OnEvent
local peek = fusion.peek

type Scope = fusion.Scope<typeof(fusion) & typeof(Components)>

UI.__index = UI

export type HelperFunctions = {
	rebuildServiceSet: () -> (),
	openPlaceConfig: () -> (),
}

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
	-- Owns every state object and instance the UI creates; cleaned up on unload
	scope: Scope,
	config: { any },
	callbacks: CallbackFunctions,
	LOGO: string,
	LOGO_SYNCED: string,
	settingsScope: string,
	rebuildServiceSet: () -> (),

	isSyncEnabled: boolean,

	azulWidget: DockWidgetPluginGui,
	notify: Notifications.Notify,
	connectButton: PluginToolbarButton,

	icon: fusion.Value<string>,
	isOpen: fusion.Value<boolean>,
	syncEnabled: fusion.Value<boolean>,
	handshakeComplete: fusion.Value<boolean>,
	autoConnect: fusion.Value<boolean>,
	debugMode: fusion.Value<boolean>,
	silentMode: fusion.Value<boolean>,
	notifications: fusion.Value<boolean>,
	notificationSounds: fusion.Value<boolean>,
	autoOpenModal: fusion.Value<boolean>,
	syncReminders: fusion.Value<boolean>,
	streamSoloOutput: fusion.Value<boolean>,
	settingsScopeValue: fusion.Value<string>,
	listTypeValue: fusion.Value<string>,

	wsUrlRef: fusion.Value<TextBox?>,
	heartbeat: fusion.Value<number>,
	batchIdleRef: fusion.Value<TextBox?>,
	scriptDebounceRef: fusion.Value<TextBox?>,

	maxHandshakes: fusion.Value<number>,
	maxReconnections: fusion.Value<number>,
	reconnectionInterval: fusion.Value<number>,

	serviceListRef: fusion.Value<TextBox?>,
	excludedParentsRef: fusion.Value<TextBox?>,
	ignoredClassesRef: fusion.Value<TextBox?>,

	GetSyncState: (AzulUI) -> boolean,
	UpdateSyncState: (AzulUI, boolean) -> (),
	UpdateHandshakeState: (AzulUI, boolean) -> (),
	UpdateConfig: (AzulUI) -> (),
	SetSettingsScope: (AzulUI, any) -> (),
	Notify: (AzulUI, string, number?, { Notifications.Action }?) -> (),
}

UI.logo = "rbxassetid://134336592598474"
UI.syncedLogo = "rbxassetid://103599828888609"

local function debugPrint(...)
	if not Config.DEBUG_MODE then return end
	print(`[🐛 Azul::{script}]: `, ...)
end

--- Utility function to validate number input from TextBoxes. If the number is valid, it calls the provided callback with the number value.
local function validateNumberInput(newValue: string, callback: (number) -> ())
	local numberValue = tonumber(newValue)

	if not numberValue then
		warn(`[Azul::{script}]: Invalid number input: {newValue}`)
		return
	end

	if numberValue <= 0 then
		warn(`[Azul::{script}]: Number input must be greater than 0: {newValue}`)
		return
	end

	callback(numberValue)
end

local function section(scope: Scope, title: string, children: { Instance })
	return scope:Container {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			scope:List {
				Spacing = 6,
			},
			scope:Text {
				Text = title,
				FontFace = Theme.Fonts.Bold,
				TextSize = Theme.TextSize.Medium,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			},
			children,
		},
	}
end

local function infoText(scope: Scope, text: string)
	return scope:Text {
		Text = text,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextDimmed,
		RichText = true,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
end

local function labeledToggle(scope: Scope, label: string, value: fusion.Value<boolean>, changed: (boolean) -> ())
	return scope:Container {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			scope:List {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Spacing = 8,
			},
			scope:Checkbox {
				Value = value,
				Changed = changed,
			},
			scope:Text {
				Text = label,
				TextSize = Theme.TextSize.Medium,
				AutomaticSize = Enum.AutomaticSize.XY,
			},
		},
	}
end

local function labeledInput(scope: Scope, label: string, ref: fusion.Value<TextBox?>, props: { [string]: any })
	local input = scope:Input {
		Text = props.Text or "",
		PlaceholderText = props.Placeholder or "",
		TextWrapped = props.TextWrapped or false,
		MultiLine = props.MultiLine or false,
		ClearTextOnFocus = false,
		Size = UDim2.fromScale(1, 1),
		Changed = props.Changed,
		Finished = props.Finished,
	}
	ref:set(input)

	return scope:Container {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			scope:List {
				Spacing = 4,
			},
			scope:Text {
				Text = label,
				TextSize = Theme.TextSize.Small,
				Color = Theme.Colors.TextDimmed,
				AutomaticSize = Enum.AutomaticSize.XY,
			},
			scope:Box {
				Size = props.BoxSize or UDim2.new(1, 0, 0, Theme.CompSizeY.Medium),
				AutomaticSize = Enum.AutomaticSize.None,
				[Children] = {
					scope:Padding {
						Padding = 6,
						Vertical = false,
					},
					input,
				},
			},
		},
	}
end

local function labeledSlider(scope: Scope, label: string, props: { [string]: any })
	return scope:Container {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			scope:List {
				Spacing = 4,
			},
			scope:Text {
				Text = label,
				TextSize = Theme.TextSize.Small,
				Color = Theme.Colors.TextDimmed,
				AutomaticSize = Enum.AutomaticSize.XY,
			},
			scope:Slider(props),
		},
	}
end

--- The reconnection slider's minimum (0) stands for infinite attempts, stored in config as -1.
local function toReconnectionSlider(value: number): number return if value == -1 then 0 else value end

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

	local scope = fusion.scoped(fusion, Components)
	self.scope = scope
	plugin.Unloading:Once(function() fusion.doCleanup(scope) end)

	self.icon = scope:Value(self.LOGO)
	self.isOpen = scope:Value(Config.AUTO_OPEN_MODAL and true or false)
	self.syncEnabled = scope:Value(false)
	self.handshakeComplete = scope:Value(false)
	self.autoConnect = scope:Value(Config.AUTO_CONNECT)
	self.debugMode = scope:Value(Config.DEBUG_MODE)
	self.silentMode = scope:Value(Config.SILENT_MODE)
	self.notifications = scope:Value(Config.NOTIFICATIONS)
	self.notificationSounds = scope:Value(Config.NOTIFICATION_SOUNDS)
	self.autoOpenModal = scope:Value(Config.AUTO_OPEN_MODAL)
	self.syncReminders = scope:Value(Config.SYNC_REMINDERS)
	self.streamSoloOutput = scope:Value(Config.STREAM_SOLO_OUTPUT)
	self.settingsScopeValue = scope:Value(settingsScope == Enums.scope.GLOBAL and "Global" or "Project")
	self.listTypeValue = scope:Value(Config.LIST_TYPE == Enums.listType.WHITELIST and "Whitelist" or "Blacklist")

	self.wsUrlRef = scope:Value(nil)
	self.heartbeat = scope:Value(Config.HEARTBEAT_INTERVAL)
	self.batchIdleRef = scope:Value(nil)
	self.scriptDebounceRef = scope:Value(nil)

	self.maxHandshakes = scope:Value(Config.MAX_HANDSHAKES)
	self.maxReconnections = scope:Value(toReconnectionSlider(Config.MAX_RECONNECTIONS))
	self.reconnectionInterval = scope:Value(Config.RECONNECTION_INTERVAL)

	self.serviceListRef = scope:Value(nil)
	self.excludedParentsRef = scope:Value(nil)
	self.ignoredClassesRef = scope:Value(nil)

	self.connectButton = scope:ToolbarButton {
		Toolbar = scope:Toolbar {
			Name = "Azul",
		},
		Name = "Azul",
		ToolTip = "Open Azul",
		Image = self.icon,
		[OnEvent "Click"] = function() self.isOpen:set(not peek(self.isOpen)) end,
	}

	local widget = scope:Widget {
		Name = "Azul",
		Id = "Azul",
		MinimumSize = Vector2.new(300, 300),
		FloatingSize = Vector2.new(345, 640),
		InitialDockTo = Enum.InitialDockState.Float,
		InitialEnabled = Config.AUTO_OPEN_MODAL and true or false,
		Enabled = self.isOpen,
		[Children] = {
			scope:Container {
				Size = UDim2.fromScale(1, 1),
				AutomaticSize = Enum.AutomaticSize.None,
				BackgroundColor3 = Theme.Colors.Background,
				BackgroundTransparency = 0,
				[Children] = {
					scope:ScrollingContainer {
						ScrollBar = true,
						[Children] = {
							scope:Padding {
								Padding = Theme.WidgetPadding,
							},
							scope:List {
								Spacing = Theme.ListSpacing,
							},
							scope:Container {
								Size = UDim2.fromScale(1, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								[Children] = {
									scope:List {
										FillDirection = Enum.FillDirection.Horizontal,
										HorizontalAlignment = Enum.HorizontalAlignment.Center,
										VerticalAlignment = Enum.VerticalAlignment.Center,
										Spacing = 10,
									},
									scope:Image {
										Size = UDim2.fromOffset(36, 36),
										Image = self.icon,
									},
									scope:Text {
										Text = "Azul",
										FontFace = Theme.Fonts.Mono,
										TextSize = Theme.TextSize.Heading,

										AutomaticSize = Enum.AutomaticSize.XY,
									},
								},
							},
							scope:TextButton {
								Text = scope:Computed(function(use)
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
							},
							section(scope, "Behavior", {
								labeledToggle(scope, "Auto Connect", self.autoConnect, function(newValue)
									Config.AUTO_CONNECT = newValue
									if self.callbacks.onAutoConnectChanged then
										self.callbacks.onAutoConnectChanged(newValue)
									end
								end),
								infoText(scope, "Automatically attempts to connect to Daemon."),
								labeledToggle(scope, "Silent Mode", self.silentMode, function(newValue)
									Config.SILENT_MODE = newValue
									if self.callbacks.onSilentModeChanged then
										self.callbacks.onSilentModeChanged(newValue)
									end
								end),
								infoText(scope, "Suppresses all console output except errors."),
								labeledToggle(scope, "Debug Mode", self.debugMode, function(newValue)
									Config.DEBUG_MODE = newValue
									if self.callbacks.onDebugModeChanged then
										self.callbacks.onDebugModeChanged(newValue)
									end
								end),
								infoText(scope, "Enables verbose logging in the output console."),
								labeledToggle(scope, "Auto Open Modal", self.autoOpenModal, function(newValue)
									Config.AUTO_OPEN_MODAL = newValue
									self.callbacks.onConfigChanged("AUTO_OPEN_MODAL", newValue)
								end),
								infoText(scope, "Opens the plugin modal when Studio first launches."),
								labeledToggle(scope, "Stream Console Output", self.streamSoloOutput, function(newValue)
									Config.STREAM_SOLO_OUTPUT = newValue
									self.callbacks.onConfigChanged("STREAM_SOLO_OUTPUT", newValue)
								end),
								infoText(scope, "Streams playtest output to the Daemon terminal."),
								scope:Text {
									Text = "Settings Scope",
									TextSize = Theme.TextSize.Small,
									Color = Theme.Colors.TextDimmed,
									AutomaticSize = Enum.AutomaticSize.XY,
								},
								scope:OptionSelector {
									Options = { "Global", "Project" },
									Value = self.settingsScopeValue,
									Selected = function(option)
										local scope = option == "Global" and Enums.scope.GLOBAL or Enums.scope.PROJECT
										self.callbacks.onSettingsScopeChanged(scope)
									end,
								},
							}),
							section(scope, "Connection", {
								labeledInput(scope, "WebSocket URL", self.wsUrlRef, {
									Text = Config.WS_URL,
									Finished = function(text)
										if text == "" then return end
										self.callbacks.onConfigChanged("WS_URL", text)
									end,
								}),
								labeledSlider(scope, "Heartbeat Interval (seconds)", {
									Value = self.heartbeat,
									Min = 5,
									Max = 120,
									Step = 5,
									Changed = function(value)
										self.callbacks.onConfigChanged("HEARTBEAT_INTERVAL", value)
									end,
								}),
								labeledInput(scope, "Batch Idle Window (seconds)", self.batchIdleRef, {
									Text = tostring(Config.BATCH_IDLE_WINDOW),
									Finished = function(text)
										if text == "" then return end
										validateNumberInput(
											text,
											function(value) self.callbacks.onConfigChanged("BATCH_IDLE_WINDOW", value) end
										)
									end,
								}),
								labeledInput(scope, "Script Change Debounce (seconds)", self.scriptDebounceRef, {
									Text = tostring(Config.SCRIPT_CHANGE_DEBOUNCE),
									Finished = function(text)
										if text == "" then return end
										validateNumberInput(
											text,
											function(value)
												self.callbacks.onConfigChanged("SCRIPT_CHANGE_DEBOUNCE", value)
											end
										)
									end,
								}),
							}),
							section(scope, "Auto Connect", {
								labeledSlider(scope, "Maximum Handshake Attempts", {
									Value = self.maxHandshakes,
									Min = 1,
									Max = 10,
									Changed = function(value) self.callbacks.onConfigChanged("MAX_HANDSHAKES", value) end,
								}),
								labeledSlider(scope, "Maximum Reconnection Attempts", {
									Value = self.maxReconnections,
									Min = 0,
									Max = 10,
									Format = function(value) return if value == 0 then "∞" else tostring(value) end,
									Changed = function(value)
										self.callbacks.onConfigChanged(
											"MAX_RECONNECTIONS",
											if value == 0 then -1 else value
										)
									end,
								}),
								labeledSlider(scope, "Reconnection Interval (seconds)", {
									Value = self.reconnectionInterval,
									Min = 1,
									Max = 60,
									Changed = function(value)
										self.callbacks.onConfigChanged("RECONNECTION_INTERVAL", value)
									end,
								}),
							}),
							section(scope, "Filters", {
								scope:Text {
									Text = "List Type",
									TextSize = Theme.TextSize.Small,
									Color = Theme.Colors.TextDimmed,
									AutomaticSize = Enum.AutomaticSize.XY,
								},
								scope:OptionSelector {
									Options = { "Whitelist", "Blacklist" },
									Value = self.listTypeValue,
									Selected = function(option)
										self.callbacks.onConfigChanged(
											"LIST_TYPE",
											option == "Whitelist" and Enums.listType.WHITELIST
												or Enums.listType.BLACKLIST
										)
									end,
								},
								labeledInput(scope, "Service List (comma-separated)", self.serviceListRef, {
									Text = table.concat(Config.SERVICE_LIST, ", "),
									-- MultiLine = true,
									BoxSize = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium * 2),
									Finished = function(text)
										local items = AzulService.parseCommaSeparatedList(text)
										self.callbacks.onConfigChanged("SERVICE_LIST", items)
									end,
								}),
								labeledInput(scope, "Excluded Parents (comma-separated)", self.excludedParentsRef, {
									Text = table.concat(Config.EXCLUDED_PARENTS, ", "),
									-- MultiLine = true,
									BoxSize = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium * 2),
									Finished = function(text)
										local items = AzulService.parseCommaSeparatedList(text)
										self.callbacks.onConfigChanged("EXCLUDED_PARENTS", items)
									end,
								}),
								labeledInput(scope, "Ignored ClassNames (comma-separated)", self.ignoredClassesRef, {
									Text = table.concat(Config.IGNORED_CLASSES, ", "),
									BoxSize = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium * 2),
									Finished = function(text)
										local items = AzulService.parseCommaSeparatedList(text)
										self.callbacks.onConfigChanged("IGNORED_CLASSES", items)
									end,
								}),
							}),
							section(scope, "UI", {
								labeledToggle(scope, "Notifications", self.notifications, function(newValue)
									Config.NOTIFICATIONS = newValue
									self.callbacks.onConfigChanged("NOTIFICATIONS", newValue)
								end),
								infoText(scope, "Shows pop-up notifications for important events."),
								labeledToggle(scope, "Notification Sounds", self.notificationSounds, function(newValue)
									Config.NOTIFICATION_SOUNDS = newValue
									self.callbacks.onConfigChanged("NOTIFICATION_SOUNDS", newValue)
								end),
								infoText(scope, "Plays a sound when a notification appears."),
								labeledToggle(scope, "Sync Reminders", self.syncReminders, function(newValue)
									Config.SYNC_REMINDERS = newValue
									self.callbacks.onConfigChanged("SYNC_REMINDERS", newValue)
								end),
								infoText(scope, "Reminds you to sync when opening a previously synced Place."),
							}),
							section(scope, "Tools", {
								scope:TextButton {
									Text = "Reload Sourcemap",
									Size = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium),
									Activated = function() self.callbacks.onSourcemapReload() end,
								},
								scope:TextButton {
									Text = "Open Place Configuration",
									Size = UDim2.new(1, 0, 0, Theme.CompSizeY.Medium),
									Activated = function() helpers.openPlaceConfig() end,
								},
							}),
							scope:Text {
								Text = `Azul Plugin v{AzulService.VERSION}`,
								TextSize = Theme.TextSize.Small,
								Color = Theme.Colors.TextDimmed,
								AutomaticSize = Enum.AutomaticSize.XY,
							},
						},
					},
				},
			},
		},
	}

	self.azulWidget = widget

	self.notify = scope:Notifications {
		Logo = self.icon,
		SoundParent = widget,
	}

	scope:Observer(self.isOpen):onChange(function() self.connectButton:SetActive(peek(self.isOpen)) end)

	self.connectButton:SetActive(peek(self.isOpen))

	return self
end

function UI:GetSyncState() return self.isSyncEnabled end

function UI:UpdateSyncState(enabled: boolean)
	self.isSyncEnabled = enabled
	self.syncEnabled:set(enabled)
	self.icon:set(if enabled then self.LOGO_SYNCED else self.LOGO)
	if not enabled then self.handshakeComplete:set(false) end
end

function UI:UpdateHandshakeState(complete: boolean) self.handshakeComplete:set(complete) end

--[=[
	Shows a pop-up notification for `timeout` seconds with optional `actions` buttons, unless notifications are disabled.
]=]
function UI:Notify(text: string, timeout: number?, actions: { Notifications.Action }?)
	if not Config.NOTIFICATIONS then return end
	self.notify(text, timeout, Config.NOTIFICATION_SOUNDS, actions)
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
	self.notifications:set(Config.NOTIFICATIONS)
	self.notificationSounds:set(Config.NOTIFICATION_SOUNDS)
	self.autoOpenModal:set(Config.AUTO_OPEN_MODAL)
	self.syncReminders:set(Config.SYNC_REMINDERS)
	self.streamSoloOutput:set(Config.STREAM_SOLO_OUTPUT)
	self.settingsScopeValue:set(if self.settingsScope == Enums.scope.GLOBAL then "Global" else "Project")
	self.listTypeValue:set(if Config.LIST_TYPE == Enums.listType.WHITELIST then "Whitelist" else "Blacklist")

	local wsUrlInput = peek(self.wsUrlRef)
	if wsUrlInput then wsUrlInput.Text = Config.WS_URL end

	self.heartbeat:set(Config.HEARTBEAT_INTERVAL)

	local batchIdleInput = peek(self.batchIdleRef)
	if batchIdleInput then batchIdleInput.Text = tostring(Config.BATCH_IDLE_WINDOW) end

	local scriptDebounceInput = peek(self.scriptDebounceRef)
	if scriptDebounceInput then scriptDebounceInput.Text = tostring(Config.SCRIPT_CHANGE_DEBOUNCE) end

	self.maxHandshakes:set(Config.MAX_HANDSHAKES)
	self.maxReconnections:set(toReconnectionSlider(Config.MAX_RECONNECTIONS))
	self.reconnectionInterval:set(Config.RECONNECTION_INTERVAL)

	local serviceListInput = peek(self.serviceListRef)
	if serviceListInput then serviceListInput.Text = table.concat(Config.SERVICE_LIST, ", ") end

	local excludedParentsInput = peek(self.excludedParentsRef)
	if excludedParentsInput then excludedParentsInput.Text = table.concat(Config.EXCLUDED_PARENTS, ", ") end

	local ignoredClassesInput = peek(self.ignoredClassesRef)
	if ignoredClassesInput then ignoredClassesInput.Text = table.concat(Config.IGNORED_CLASSES, ", ") end
end

return UI
