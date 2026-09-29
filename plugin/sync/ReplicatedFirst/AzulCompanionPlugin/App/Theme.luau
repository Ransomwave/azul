local plugin = script:FindFirstAncestorWhichIsA("Plugin")
local Studio = settings().Studio

local Azul = script:FindFirstAncestor("AzulCompanionPlugin")

local Fusion = require(Azul.Packages.fusion)

-- Lives for the whole plugin session; cleaned up on unload
local scope = Fusion.scoped(Fusion)

local function getColors(isDark: boolean): { [string]: { Color3 | { [string]: Color3 } } }
	local background = Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
	local border = Studio.Theme:GetColor(Enum.StudioStyleGuideColor.Shadow)

	if border == background then border = Studio.Theme:GetColor(Enum.StudioStyleGuideColor.ScrollBarBackground) end

	local h, s, v = border:ToHSV()
	border = Color3.fromHSV(h, s, v * (isDark and 1.2 or 0.85))

	return {
		-- Brand = Color3.fromRGB(90, 142, 233),
		Brand = Color3.fromHex("157eff"),

		Background = background,
		ActiveBackground = Studio.Theme:GetColor(Enum.StudioStyleGuideColor.Titlebar),
		Border = border,

		Text = Studio.Theme:GetColor(Enum.StudioStyleGuideColor.BrightText),
		TextDimmed = Studio.Theme:GetColor(Enum.StudioStyleGuideColor.SubText),
		TextBranded = isDark and Studio.Theme:GetColor(Enum.StudioStyleGuideColor.BrightText) or background,

		Diff = {
			Add = Color3.fromRGB(80, 220, 100),
			Update = Color3.fromRGB(100, 200, 230),
			Remove = Color3.fromRGB(230, 100, 100),
		},
	}
end

local function init(): Fusion.Value<Color3> return scope:Value(Color3.new()) end

local Theme = {
	-- For autocomplete
	Colors = {
		Brand = init(),

		Background = init(),
		ActiveBackground = init(),
		Border = init(),

		Text = init(),
		TextDimmed = init(),
		TextBranded = init(),

		Diff = {
			Add = init(),
			Update = init(),
			Remove = init(),
		},
	},

	Fonts = {
		Regular = Font.fromName("SourceSans"),
		Bold = Font.fromName("SourceSans", Enum.FontWeight.Bold),
		Italic = Font.fromName("SourceSans", Enum.FontWeight.Regular, Enum.FontStyle.Italic),
		Mono = Font.fromName("RobotoMono"),

		-- required for TextService:GetTextSize()
		Enums = {
			Regular = Enum.Font.SourceSans,
			Bold = Enum.Font.SourceSans,
			Italic = Enum.Font.SourceSans,
			Mono = Enum.Font.RobotoMono,
		},
	},

	BorderThickness = 1,
	CornerRadius = 4,
	ListSpacing = 12,
	WidgetPadding = 12,
	Padding = 8,

	TextSize = {
		Heading = 40,
		Large = 20,
		Medium = 18,
		Small = 15,
	},

	CompSizeY = {
		Large = 36,
		Medium = 30,
		Small = 28,
	},

	SpringSpeed = 30,
	SpringFastSpeed = 60,
	SpringDamping = 1.5,

	IsDark = scope:Value(true),
}

do
	local function updateTheme()
		local _, _, v = Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainBackground):ToHSV()
		local isDark = v <= 0.6

		Theme.IsDark:set(isDark)

		for key, color in getColors(isDark) do
			if type(color) ~= "table" then
				Theme.Colors[key]:set(color)
			else
				for subKey, subColor in color do
					Theme.Colors[key][subKey]:set(subColor)
				end
			end
		end
	end

	updateTheme()

	table.insert(scope, Studio.ThemeChanged:Connect(updateTheme))

	plugin.Unloading:Once(function() Fusion.doCleanup(scope) end)

	-- :P
	local now = DateTime.now():ToLocalTime()
	if now.Month == 4 and now.Day == 1 then
		Theme.Colors.Brand:set(Color3.fromHex("e13835"))
		Theme.CornerRadius = 0
	end
end

return Theme
