local plugin = script:FindFirstAncestorWhichIsA("Plugin")

local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local stripProps = require(Util.stripProps)

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Name",
}

type Props = {
	Name: string,
	[any]: any,
}

return function(scope: Scope, props: Props): PluginToolbar
	local toolbar = plugin:CreateToolbar(props.Name)
	scope:Hydrate(toolbar)(stripProps(props, COMPONENT_ONLY_PROPS))
	return toolbar
end
