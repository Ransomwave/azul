local plugin = script:FindFirstAncestorWhichIsA("Plugin")

local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local stripProps = require(Util.stripProps)
local isState = require(Util.isState)
local default = require(Util.default)

local peek = Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Id",
	"InitialDockTo",
	"InitialEnabled",
	"OverrideEnabled",
	"FloatingSize",
	"MinimumSize",
	"Closed",
}

type WidgetProps = {
	Id: string?,
	InitialDockTo: Enum.InitialDockState?,
	InitialEnabled: boolean?,
	OverrideEnabled: boolean?,
	FloatingSize: Vector2?,
	MinimumSize: Vector2,
	Closed: (() -> ())?,
	[any]: any,
}

return function(scope: Scope, props: WidgetProps): DockWidgetPluginGui
	local floatingSize = props.FloatingSize or props.MinimumSize

	local widget = plugin:CreateDockWidgetPluginGui(
		props.Id or peek(props.Name),
		DockWidgetPluginGuiInfo.new(
			props.InitialDockTo or Enum.InitialDockState.Float,
			default(props.InitialEnabled, true),
			default(props.OverrideEnabled, false),
			floatingSize.X,
			floatingSize.Y,
			props.MinimumSize.X,
			props.MinimumSize.Y
		)
	)

	if isState(props.Enabled) then props.Enabled:set(widget.Enabled) end

	if props.Closed then widget:BindToClose(props.Closed) end

	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	props.Title = props.Name

	scope:Hydrate(widget)(stripProps(props, COMPONENT_ONLY_PROPS))
	return widget
end
