local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Assets = require(App.Assets)
local Theme = require(App.Theme)
local stripProps = require(Util.stripProps)
local isState = require(Util.isState)

local IconButton = require(Components.IconButton)

local peek = Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

local COMPONENT_ONLY_PROPS = {
	"Changed",
	"Value",
	"Placeholder",
}

type Props = {
	Changed: ((value: boolean) -> ())?,
	Value: Fusion.UsedAs<boolean>?,
	Placeholder: Fusion.UsedAs<boolean>?,
	[any]: any,
}

return function(outerScope: Scope, props: Props): Instance
	local scope = outerScope:innerScope {
		IconButton = IconButton,
	}

	local value = isState(props.Value) and props.Value or scope:Value(props.Value or false)
	local placeholder = isState(props.Placeholder) and props.Placeholder or scope:Value(props.Placeholder or false)

	return scope:Hydrate(scope:IconButton {
		Size = UDim2.fromOffset(Theme.CompSizeY.Medium, Theme.CompSizeY.Medium),
		Solid = value,
		Blending = false,
		Icon = scope:Computed(
			function(use)
				return if use(value) and use(placeholder) or use(placeholder) then Assets.Icons.Checkmark else ""
			end
		),
		Activated = function()
			value:set(not peek(value))

			if props.Changed then props.Changed(peek(value)) end
		end,
	})(stripProps(props, COMPONENT_ONLY_PROPS))
end
