local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local stripProps = require(Util.stripProps)

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Spacing",
}

type Props = {
	Spacing: number?,
	[any]: any,
}

return function(scope: Scope, props: Props): Instance
	return scope:Hydrate(scope:New "UIListLayout" {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, props.Spacing or Theme.ListSpacing),
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
