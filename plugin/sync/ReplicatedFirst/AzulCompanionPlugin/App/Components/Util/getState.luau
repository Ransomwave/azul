local Azul = script:FindFirstAncestor("AzulCompanionPlugin")

local Fusion = require(Azul.Packages.fusion)

type Scope = Fusion.Scope<typeof(Fusion)>

type Input = {
	Pressed: Fusion.StateObject<boolean>?,
	Hovered: Fusion.StateObject<boolean>?,
}

return function(scope: Scope, input: Input): Fusion.Computed<Enum.GuiState>
	local isPressed = input.Pressed
	local isHovered = input.Hovered

	return scope:Computed(function(use)
		if use(isPressed) then
			return Enum.GuiState.Press
		elseif use(isHovered) then
			return Enum.GuiState.Hover
		else
			return Enum.GuiState.Idle
		end
	end)
end
