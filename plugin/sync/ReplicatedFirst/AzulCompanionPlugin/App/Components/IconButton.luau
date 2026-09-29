local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local animate = require(Util.animate)
local stripProps = require(Util.stripProps)
local getState = require(Util.getState)
local default = require(Util.default)

local Border = require(Components.Border)
local Image = require(Components.Image)

local OnEvent = Fusion.OnEvent
local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Activated",
	"Solid",
	"Icon",
	"BackgroundActive",
	"Blending",
}

type Props = {
	Activated: (() -> ())?,
	Solid: Fusion.UsedAs<boolean>?,
	Icon: Fusion.UsedAs<string>?,
	BackgroundActive: Fusion.Computed<boolean>?,
	Blending: boolean?,
	[any]: any,
}

return function(outerScope: Scope, props: Props): Instance
	local scope = outerScope:innerScope {
		Border = Border,
		Image = Image,
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
			function(use)
				return if use(props.Solid)
					then use(Theme.Colors.Brand)
					else use(props.BackgroundActive) and use(Theme.Colors.ActiveBackground) or use(
						Theme.Colors.Background
					)
			end
		),
		state
	)

	return scope:Hydrate(scope:New "TextButton" {
		Size = UDim2.fromOffset(Theme.CompSizeY.Large, Theme.CompSizeY.Large),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		[OnEvent "InputBegan"] = function(inputObject)
			if inputObject.UserInputType == Enum.UserInputType.MouseMovement then
				isHovered:set(true)
			elseif inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
				isPressed:set(true)
			end
		end,
		[OnEvent "InputEnded"] = function(inputObject)
			if inputObject.UserInputType == Enum.UserInputType.MouseMovement then
				isHovered:set(false)
			elseif inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
				isPressed:set(false)
			end
		end,
		[OnEvent "Activated"] = function()
			if props.Activated then props.Activated() end
		end,
		[Children] = {
			scope:Border {},
			scope:Image {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.55, 0.55),
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				ImageTransparency = default(props.Blending, true) and scope:Computed(
					function(use) return use(Theme.IsDark) and 0.1 or 0.2 end
				) or 0,
				ImageColor3 = scope:Computed(
					function(use) return use(props.Solid) and use(Theme.Colors.TextBranded) or use(Theme.Colors.Text) end
				),
				Image = props.Icon,
			},
		},
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
