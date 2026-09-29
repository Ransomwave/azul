local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local stripProps = require(Util.stripProps)

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"ScrollBar",
}

type Props = {
	ScrollBar: boolean?,
	[any]: any,
}

return function(scope: Scope, props: Props): Instance
	return scope:Hydrate(scope:New "ScrollingFrame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = props.ScrollBar and 5 or 0,
		ScrollBarImageColor3 = Theme.Colors.TextDimmed,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromScale(0, 0),
		BorderSizePixel = 0,
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
