local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)

local Corner = require(Components.Corner)

type Scope = Fusion.Scope<typeof(Fusion)>

type Props = {
	Color: Fusion.UsedAs<Color3>?,
	Transparency: Fusion.UsedAs<number>?,
	Thickness: Fusion.UsedAs<number>?,
	CornerRadius: Fusion.UsedAs<UDim>?,
}

return function(outerScope: Scope, props: Props): Fusion.Child
	local scope = outerScope:innerScope {
		Corner = Corner,
	}

	return {
		scope:Corner {},
		scope:New "UIStroke" {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = props.Color or Theme.Colors.Border,
			Thickness = props.Thickness or Theme.BorderThickness,
			Transparency = props.Transparency or 0,
		},
	}
end
