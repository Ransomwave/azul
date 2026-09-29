local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local Assets = require(App.Assets)
local animate = require(Util.animate)
local getState = require(Util.getState)
local stripProps = require(Util.stripProps)

local Container = require(Components.Container)
local Padding = require(Components.Padding)
local Corner = require(Components.Corner)
local Image = require(Components.Image)
local List = require(Components.List)
local Text = require(Components.Text)
local Box = require(Components.Box)

local OnEvent = Fusion.OnEvent
local Children = Fusion.Children
local OnChange = Fusion.OnChange
local peek = Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Title",
	"Color",
	"Expanded",
	"Elements",
}

type Props = {
	Title: string,
	Color: Fusion.UsedAs<Color3>?,
	Expanded: boolean?,
	Elements: { Instance },
}

return function(outerScope: Scope, props: Props): Instance
	local scope = outerScope:innerScope {
		Box = Box,
		Container = Container,
		Corner = Corner,
		Image = Image,
		List = List,
		Padding = Padding,
		Text = Text,
	}

	local isExpanded = scope:Value(props.Expanded or false)
	local absoluteSize = scope:Value(Vector2.zero)

	local isHovered = scope:Value(false)
	local isPressed = scope:Value(false)

	local state = getState(scope, {
		Hovered = isHovered,
		Pressed = isPressed,
	})

	local color = animate(
		scope,
		scope:Computed(
			function(use) return use(isExpanded) and use(Theme.Colors.ActiveBackground) or use(Theme.Colors.Background) end
		),
		state
	)

	return scope:Hydrate(scope:Box {
		ClipsDescendants = scope:Computed(function(use) return not use(isExpanded) end),
		AutomaticSize = Enum.AutomaticSize.None,
		Size = scope:Spring(
			scope:Computed(
				function(use)
					return UDim2.new(1, 0, 0, Theme.CompSizeY.Large + (use(isExpanded) and use(absoluteSize).Y or 0))
				end
			),
			30
		),
		[Children] = {
			scope:New "TextButton" {
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, Theme.CompSizeY.Large),
				BackgroundColor3 = color,
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
				[OnEvent "Activated"] = function() isExpanded:set(not peek(isExpanded)) end,
				[Children] = {
					scope:Corner {},
					scope:Container {
						Size = UDim2.fromScale(1, 1),
						[Children] = {
							scope:Padding {},
							scope:Text {
								Text = props.Title,
								FontFace = Theme.Fonts.Bold,
								TextSize = Theme.TextSize.Large,
								TextXAlignment = Enum.TextXAlignment.Left,
								Size = UDim2.fromScale(1, 1),
								Color = props.Color or Theme.Colors.Text,
							},
							scope:Image {
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.fromScale(1, 0.5),
								Size = UDim2.fromOffset(16, 16),
								Image = Assets.Icons.Expand,
								ImageColor3 = props.Color or Theme.Colors.Text,
								Rotation = scope:Spring(
									scope:Computed(function(use) return use(isExpanded) and 180 or 0 end),
									30
								),
							},
						},
					},
					scope:New "Frame" {
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.fromScale(0, 1),
						Size = UDim2.fromScale(1, 0.2),
						BackgroundColor3 = color,
						BorderSizePixel = 0,
						BackgroundTransparency = scope:Tween(
							scope:Computed(function(use) return use(isExpanded) and 0 or 1 end),
							TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
						),
					},
				},
			},
			scope:Container {
				Size = UDim2.fromScale(1, 0),
				Position = UDim2.fromOffset(0, Theme.CompSizeY.Large),
				[OnChange "AbsoluteSize"] = function(size) absoluteSize:set(size) end,
				[Children] = {
					scope:List {
						Spacing = 0,
					},
					props.Elements,
				},
			},
		},
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
