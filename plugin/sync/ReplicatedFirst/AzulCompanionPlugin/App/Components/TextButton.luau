local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local animate = require(Util.animate)
local stripProps = require(Util.stripProps)
local getTextSize = require(Util.getTextSize)
local getState = require(Util.getState)

local Border = require(Components.Border)

local OnEvent = Fusion.OnEvent
local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Activated",
	"Solid",
}

type Props = {
	Activated: (() -> ())?,
	Solid: Fusion.UsedAs<boolean>?,
	[any]: any,
}

return function(outerScope: Scope, props: Props): Instance
	local scope = outerScope:innerScope {
		Border = Border,
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
			function(use) return use(props.Solid) and use(Theme.Colors.Brand) or use(Theme.Colors.Background) end
		),
		state
	)

	local size = props.Size
		or scope:Computed(function(use)
			local text = use(props.Text)
			local size = getTextSize(text)

			return UDim2.fromOffset(size.X + 22, Theme.CompSizeY.Large)
		end)

	return scope:Hydrate(scope:New "TextButton" {
		Text = "Button",
		FontFace = Theme.Fonts.Regular,
		AutoButtonColor = false,
		TextSize = Theme.TextSize.Large,
		Size = size,
		BackgroundColor3 = color,
		TextColor3 = scope:Computed(
			function(use) return use(props.Solid) and use(Theme.Colors.TextBranded) or use(Theme.Colors.Text) end
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
		[Children] = {
			scope:Border {},
		},
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
