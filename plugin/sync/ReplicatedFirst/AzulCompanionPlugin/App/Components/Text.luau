local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local stripProps = require(Util.stripProps)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Font",
	"Color",
	"Scaled",
}

type Props = {
	Font: Fusion.UsedAs<Font>?,
	Color: Fusion.UsedAs<Color3>?,
	Scaled: boolean?,
	[any]: any,
}

return function(scope: Scope, props: Props): Instance
	return scope:Hydrate(scope:New "TextLabel" {
		FontFace = props.Font or Theme.Fonts.Regular,
		TextColor3 = props.Color or Theme.Colors.Text,
		TextSize = Theme.TextSize.Large,
		AutomaticSize = props.Scaled and Enum.AutomaticSize.None or Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Left,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		TextScaled = props.Scaled,
		RichText = true,
		[Children] = props.Scaled and scope:New "UITextSizeConstraint" {
			MaxTextSize = props.TextSize or Theme.TextSize.Large,
		} or nil,
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
