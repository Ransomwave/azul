local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local stripProps = require(Util.stripProps)

local Border = require(Components.Border)
local Container = require(Components.Container)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"BackgroundColor",
	"BorderColor",
	"BackgroundTransparency",
	"BorderTransparency",
}

type Props = {
	BackgroundColor: Fusion.UsedAs<Color3>?,
	BorderColor: Fusion.UsedAs<Color3>?,
	BackgroundTransparency: Fusion.UsedAs<number>?,
	BorderTransparency: Fusion.UsedAs<number>?,
	[any]: any,
}

return function(outerScope: Scope, props: Props): Instance
	local scope = outerScope:innerScope {
		Border = Border,
		Container = Container,
	}

	return scope:Hydrate(scope:Container {
		Size = UDim2.fromOffset(120, Theme.CompSizeY.Large),
		BackgroundColor3 = props.BackgroundColor or Theme.Colors.Background,
		BackgroundTransparency = props.BackgroundTransparency or 0,
		[Children] = scope:Border {
			Color = props.BorderColor,
			Transparency = props.BorderTransparency,
		},
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
