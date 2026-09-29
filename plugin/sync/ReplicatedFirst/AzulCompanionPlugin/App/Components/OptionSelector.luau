local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local animate = require(Util.animate)
local stripProps = require(Util.stripProps)
local getState = require(Util.getState)
local isState = require(Util.isState)

local Corner = require(Components.Corner)
local List = require(Components.List)
local Box = require(Components.Box)

local OnEvent = Fusion.OnEvent
local Children = Fusion.Children
local peek = Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

local BUTTON_COMPONENT_ONLY_PROPS = {
	"Activated",
	"IsSelected",
	"IsFirst",
	"IsLast",
}

type ButtonProps = {
	Activated: () -> (),
	IsSelected: Fusion.UsedAs<boolean>,
	IsFirst: boolean,
	IsLast: boolean,
	[any]: any,
}

local function Button(outerScope: Scope, props: ButtonProps): Instance
	local scope = outerScope:innerScope {
		Corner = Corner,
	}

	local isHovered = scope:Value(false)
	local isPressed = scope:Value(false)

	local state = getState(scope, {
		Hovered = isHovered,
		Pressed = isPressed,
	})

	local color = animate(
		scope,
		scope:Computed(
			function(use) return use(props.IsSelected) and use(Theme.Colors.Brand) or use(Theme.Colors.Background) end
		),
		state
	)

	local children = if props.IsFirst
		then {
			scope:Corner {},
			scope:New "Frame" {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0.1, 1),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			},
		}
		elseif props.IsLast then {
			scope:Corner {},
			scope:New "Frame" {
				Size = UDim2.fromScale(0.1, 1),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			},
		}
		else {}

	if not props.IsFirst then
		table.insert(
			children,
			scope:New "Frame" {
				Size = UDim2.new(0, Theme.BorderThickness, 1, 0),
				BackgroundColor3 = Theme.Colors.Border,
				BorderSizePixel = 0,
			}
		)
	end

	return scope:Hydrate(scope:New "TextButton" {
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.Fonts.Regular,
		AutoButtonColor = false,
		TextSize = Theme.TextSize.Large,
		BackgroundColor3 = color,
		TextColor3 = scope:Computed(
			function(use) return use(props.IsSelected) and use(Theme.Colors.TextBranded) or use(Theme.Colors.Text) end
		),
		[OnEvent "InputBegan"] = function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				isHovered:set(true)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				isPressed:set(true)
			end
		end,
		[OnEvent "InputEnded"] = function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				isHovered:set(false)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				isPressed:set(false)
			end
		end,
		[OnEvent "Activated"] = function()
			if props.Activated then props.Activated() end
		end,
		[Children] = children,
	})(stripProps(props, BUTTON_COMPONENT_ONLY_PROPS))
end

local COMPONENT_ONLY_PROPS = {
	"Selected",
	"Options",
	"Value",
}

type Props = {
	Selected: ((option: string) -> ())?,
	Options: { string },
	Value: Fusion.UsedAs<string>?,
	[any]: any,
}

return function(outerScope: Scope, props: Props): Instance
	local scope = outerScope:innerScope {
		Box = Box,
		Button = Button,
		List = List,
	}

	local value = isState(props.Value) and props.Value or scope:Value(props.Value or props.Options[1])

	return scope:Hydrate(scope:Box {
		Size = UDim2.new(1, 0, 0, Theme.CompSizeY.Small),
		AutomaticSize = Enum.AutomaticSize.None,
		[Children] = {
			scope:List {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalFlex = Enum.UIFlexAlignment.Fill,
				Spacing = 0,
			},
			scope:ForValues(props.Options, function(_, innerScope, option)
				return innerScope:Button {
					Text = option,
					IsSelected = innerScope:Computed(function(use) return use(value) == option end),
					Activated = function()
						if option == peek(value) then return end

						value:set(option)

						if props.Selected then props.Selected(option) end
					end,
					IsFirst = option == props.Options[1],
					IsLast = option == props.Options[#props.Options],
				}
			end),
		},
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
