--!strict
--[[
	Rojo-style toast notifications, stacked in the bottom-right corner of the Studio viewport.
]]

local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components

local Fusion = require(Azul.Packages.fusion)

local Assets = require(App.Assets)
local Theme = require(App.Theme)

local Box = require(Components.Box)
local Container = require(Components.Container)
local Corner = require(Components.Corner)
local Image = require(Components.Image)
local List = require(Components.List)
local Padding = require(Components.Padding)
local Text = require(Components.Text)
local TextButton = require(Components.TextButton)

local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

type Scope = Fusion.Scope<typeof(Fusion)>

local WIDTH = 320
local LOGO_SIZE = 32
local DEFAULT_TIMEOUT = 5
local FADE_TIME = 0.4
local BAR_HEIGHT = 3

type Props = {
	Logo: Fusion.UsedAs<string>,
	-- Sounds only play in Edit mode when parented to a plugin widget
	SoundParent: Instance,
}

--- A button under the notification text. Clicking it dismisses the notification, then runs `Activated`.
export type Action = {
	Text: string,
	Activated: () -> (),
}

export type Notify = (text: string, timeout: number?, playSound: boolean?, actions: { Action }?) -> ()

--- Builds one button per action, the first one solid. Buttons fade with the toast.
local function actionButtons(
	scope: Scope,
	actions: { Action },
	transparency: Fusion.UsedAs<number>,
	dismiss: () -> boolean
): { Instance }
	local buttons: { Instance } = {}
	for i, action in actions do
		buttons[i] = TextButton(scope, {
			Text = action.Text,
			TextSize = Theme.TextSize.Medium,
			Solid = i == 1,
			LayoutOrder = i,
			BackgroundTransparency = transparency,
			TextTransparency = transparency,
			Activated = function()
				if dismiss() then action.Activated() end
			end,
		})
	end
	return buttons
end

--[=[
	Creates the notifications ScreenGui in CoreGui, owned by `scope`.
	Returns a function that shows a notification for `timeout` seconds, playing a sound if `playSound` is true
	and showing a button for each of `actions`.
]=]
return function(outerScope: Scope, props: Props): Notify
	local scope = outerScope:innerScope {
		Box = Box,
		Container = Container,
		Corner = Corner,
		Image = Image,
		List = List,
		Padding = Padding,
		Text = Text,
	}

	local holder = scope:New "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[Children] = {
			scope:List {
				Spacing = 6,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
			},
			scope:Padding { Padding = 10 },
		},
	}

	scope:New "ScreenGui" {
		Name = "AzulNotifications",
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ResetOnSpawn = false,
		DisplayOrder = 100,
		Parent = CoreGui,
		[Children] = holder,
	}

	local count = 0

	local function notify(text: string, timeout: number?, playSound: boolean?, actions: { Action }?)
		count += 1
		local duration = timeout or DEFAULT_TIMEOUT

		-- Owns everything this toast creates; cleaned up once it has faded out
		local toastScope = scope:innerScope()

		local visibility = toastScope:Value(0)
		local alpha = toastScope:Spring(visibility, 15, 1)
		local transparency = toastScope:Computed(function(use) return 1 - use(alpha) end)

		-- Fraction of the lifetime left; drains while the toast isn't hovered
		local remaining = toastScope:Value(1)
		local timeLeft = duration
		local hovered = false

		-- Starts the fade-out; returns true only on the first call
		local dismissed = false
		local function dismiss(): boolean
			if dismissed then return false end
			dismissed = true
			visibility:set(0)
			task.delay(FADE_TIME, Fusion.doCleanup, toastScope)
			return true
		end

		table.insert(
			toastScope,
			RunService.Heartbeat:Connect(function(dt)
				if hovered then return end
				timeLeft -= dt
				remaining:set(math.max(timeLeft / duration, 0))
				if timeLeft <= 0 then dismiss() end
			end)
		)

		toastScope:New "TextButton" {
			Size = UDim2.fromOffset(WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = count,
			Parent = holder,
			[OnEvent "Activated"] = dismiss,
			[OnEvent "MouseEnter"] = function() hovered = true end,
			[OnEvent "MouseLeave"] = function() hovered = false end,
			[Children] = toastScope:Box {
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = transparency,
				BorderTransparency = transparency,
				[Children] = {
					toastScope:List { Spacing = 0 },
					toastScope:Container {
						Size = UDim2.fromScale(1, 0),
						LayoutOrder = 1,
						[Children] = {
							toastScope:Padding { Padding = 10 },
							toastScope:List {
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Spacing = 10,
							},
							toastScope:Image {
								Size = UDim2.fromOffset(LOGO_SIZE, LOGO_SIZE),
								Image = props.Logo,
								ImageTransparency = transparency,
							},
							toastScope:Text {
								Text = text,
								TextSize = Theme.TextSize.Medium,
								TextWrapped = true,
								TextTransparency = transparency,
								Size = UDim2.new(1, -(LOGO_SIZE + 10), 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
							},
						},
					},
					if actions
						then toastScope:Container {
							Size = UDim2.fromScale(1, 0),
							LayoutOrder = 2,
							[Children] = {
								toastScope:Padding { Padding = 10, Top = 0 },
								toastScope:List {
									FillDirection = Enum.FillDirection.Horizontal,
									HorizontalAlignment = Enum.HorizontalAlignment.Right,
									Spacing = 6,
								},
								actionButtons(toastScope, actions, transparency, dismiss),
							},
						}
						else nil,
					-- Time-left bar, spanning the bottom edge
					toastScope:Container {
						Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
						AutomaticSize = Enum.AutomaticSize.None,
						LayoutOrder = 3,
						BackgroundColor3 = Theme.Colors.Border,
						BackgroundTransparency = transparency,
						[Children] = {
							toastScope:Corner { Radius = BAR_HEIGHT },
							toastScope:Container {
								Size = toastScope:Computed(function(use) return UDim2.fromScale(use(remaining), 1) end),
								AutomaticSize = Enum.AutomaticSize.None,
								BackgroundColor3 = Theme.Colors.Brand,
								BackgroundTransparency = transparency,
								[Children] = toastScope:Corner { Radius = BAR_HEIGHT },
							},
						},
					},
				},
			},
		}

		visibility:set(1)

		if not playSound then return end

		local sound = Instance.new("Sound")
		sound.SoundId = Assets.Sounds.Notification
		sound.Parent = props.SoundParent
		sound.Ended:Once(function() sound:Destroy() end)
		sound:Play()
	end

	return notify
end
