local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local default = require(Util.default)
local stripProps = require(Util.stripProps)

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Padding",
	"Horizontal",
	"Vertical",
	"Left",
	"Right",
	"Top",
	"Bottom",
}

type Props = {
	-- Mode 1
	Padding: number?,
	Horizontal: boolean?,
	Vertical: boolean?,
	-- Mode 2
	Left: number?,
	Right: number?,
	Top: number?,
	Bottom: number?,
	[any]: any,
}

return function(scope: Scope, props: Props): Instance
	local left, right
	local top, bottom

	if props.Left or props.Right or props.Top or props.Bottom then
		local padding = props.Padding or 0

		left = UDim.new(0, props.Left or padding)
		right = UDim.new(0, props.Right or padding)
		top = UDim.new(0, props.Top or padding)
		bottom = UDim.new(0, props.Bottom or padding)
	else
		local padding = UDim.new(0, props.Padding or Theme.Padding)
		local horizontal = default(props.Horizontal, true)
		local vertical = default(props.Vertical, true)

		left = horizontal and padding or nil
		right = horizontal and padding or nil
		top = vertical and padding or nil
		bottom = vertical and padding or nil
	end

	return scope:Hydrate(scope:New "UIPadding" {
		PaddingLeft = left,
		PaddingRight = right,
		PaddingTop = top,
		PaddingBottom = bottom,
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
