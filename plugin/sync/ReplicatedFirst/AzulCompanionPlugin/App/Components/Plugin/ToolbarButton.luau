local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local stripProps = require(Util.stripProps)
local isState = require(Util.isState)

local peek = Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Toolbar",
	"Name",
	"ToolTip",
	"Image",
}

type ToolbarButtonProps = {
	Toolbar: PluginToolbar,
	Name: string,
	ToolTip: string,
	Image: Fusion.UsedAs<string>,
	[any]: any,
}

return function(scope: Scope, props: ToolbarButtonProps): PluginToolbarButton
	local button = props.Toolbar:CreateButton(props.Name, props.ToolTip, peek(props.Image))
	button.ClickableWhenViewportHidden = true

	if isState(props.Image) then
		scope:Observer(props.Image):onChange(function() button.Icon = peek(props.Image) end)
	end

	scope:Hydrate(button)(stripProps(props, COMPONENT_ONLY_PROPS))
	return button
end
