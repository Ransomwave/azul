local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)

type Scope = Fusion.Scope<typeof(Fusion)>

return function(
	scope: Scope,
	goal: Fusion.StateObject<Color3>,
	state: Fusion.StateObject<Enum.GuiState>,
	speed: Fusion.UsedAs<number>?,
	damping: Fusion.UsedAs<number>?
): Fusion.Spring<Color3>
	return scope:Spring(
		scope:Computed(function(use)
			local goal = use(goal)
			local state = use(state)

			local isDark = use(Theme.IsDark)
			local h, s, v = goal:ToHSV()

			if state == Enum.GuiState.Hover then
				return Color3.fromHSV(h, s, v * (isDark and 1.3 or 0.9))
			elseif state == Enum.GuiState.Press then
				return Color3.fromHSV(h, s, v * (isDark and 1.5 or 0.8))
			else
				return goal
			end
		end),
		speed or Theme.SpringSpeed,
		damping or Theme.SpringDamping
	)
end
