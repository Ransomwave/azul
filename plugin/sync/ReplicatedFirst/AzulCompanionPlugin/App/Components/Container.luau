local Azul = script:FindFirstAncestor("AzulCompanionPlugin")

local Fusion = require(Azul.Packages.fusion)

type Scope = Fusion.Scope<typeof(Fusion)>

type Props = {
	[any]: any,
}

return function(scope: Scope, props: Props): Instance
	return scope:Hydrate(scope:New "Frame" {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
	})(props)
end
