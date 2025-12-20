local module = {}

module.kTitleBarHeight = 27
module.kInlineTitleBarHeight = 24

module.kStandardContentAreaWidth = 180

module.kStandardPropertyHeight = 30
module.kSubSectionLabelHeight = 30

module.kStandardVMargin = 7
module.kStandardHMargin = 16

module.kCheckboxMinLabelWidth = 52
module.kCheckboxMinMargin = 12
module.kCheckboxWidth = 12

module.kRadioButtonsHPadding = 24

module.StandardLineLabelLeftMargin = module.kTitleBarHeight
module.StandardLineElementLeftMargin = (
	module.StandardLineLabelLeftMargin
	+ module.kCheckboxMinLabelWidth
	+ module.kCheckboxMinMargin
	+ module.kCheckboxWidth
	+ module.kRadioButtonsHPadding
) + 20
module.StandardLineLabelWidth = (module.StandardLineElementLeftMargin - module.StandardLineLabelLeftMargin - 10)

module.kDropDownHeight = 55

module.kBottomButtonsFrameHeight = 50
module.kBottomButtonsHeight = 28

module.kShapeButtonSize = 32
module.kTextVerticalFudge = -3
module.kButtonVerticalFudge = -5

module.kBottomButtonsWidth = 100

module.kDisabledTextColor = Color3.new(0.4, 0.4, 0.4) --todo: input spec disabled text color
module.kStandardButtonTextColor = Color3.new(0, 0, 0) --todo: input spec disabled text color
module.kPressedButtonTextColor = Color3.new(1, 1, 1) --todo: input spec disabled text color

module.kButtonStandardBackgroundColor = Color3.new(1, 1, 1) --todo: sync with spec
module.kButtonStandardBorderColor = Color3.new(0.4, 0.4, 0.4) --todo: sync with spec
module.kButtonDisabledBackgroundColor = Color3.new(0.7, 0.7, 0.7) --todo: sync with spec
module.kButtonDisabledBorderColor = Color3.new(0.6, 0.6, 0.6) --todo: sync with spec

module.kButtonBackgroundTransparency = 0.5
module.kButtonBackgroundIntenseTransparency = 0.4

module.kMainFrame = nil

--- Determines if icons should use a lighter style based on the studio theme's background brightness.
--- @return boolean Returns true if the average RGB value of the main background is below 0.5 (darker theme).
function module.ShouldUseIconsForDarkerBackgrounds()
	local mainColor = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
	return (mainColor.R + mainColor.G + mainColor.B) / 3 < 0.5
end

--- Calculates the average brightness of a given Color3.
--- @param color Color3 -- The color to evaluate.
--- @return number -- The average brightness (0 to 1).
function module.GetColorOverallBrightness(color: Color3): number
	return (color.R + color.G + color.B) / 3
end

--- Stores a reference to the given frame to be used as the main UI container.
--- @param frame Frame -- The Frame to be set as the main UI reference.
function module.SetMainFrame(frame: Frame)
	module.kMainFrame = frame
end

--- Synchronizes the GUI element's background color with the theme's title bar color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- The GUI element to sync.
function module.syncGuiElementTitleColor(guiElement: GuiObject)
	local function setColors()
		guiElement.BackgroundColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.Titlebar)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the GUI element's background color with the theme's input field background color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- The GUI element to sync.
function module.syncGuiElementInputFieldColor(guiElement: GuiObject)
	local function setColors()
		guiElement.BackgroundColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.InputFieldBackground)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the GUI element's background color with the theme's main background color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- The GUI element to sync.
function module.syncGuiElementBackgroundColor(guiElement: GuiObject)
	local function setColors()
		guiElement.BackgroundColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Alternates the GUI element's background color based on its LayoutOrder to create a striped effect.
--- Uses MainBackground for even rows and CategoryItem for odd rows.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- The GUI element to sync.
function module.syncGuiElementStripeColor(guiElement: GuiObject)
	local function setColors()
		if (guiElement.LayoutOrder + 1) % 2 == 0 then
			guiElement.BackgroundColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
		else
			guiElement.BackgroundColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.CategoryItem)
		end
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the GUI element's border color with the theme's border color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- The GUI element to sync.
function module.syncGuiElementBorderColor(guiElement: GuiObject)
	local function setColors()
		guiElement.BorderColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.Border)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the GUI element's font color with the theme's main text color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- A GUI element that has a TextColor3 property.
function module.syncGuiElementFontColor(guiElement: { TextColor3: Color3 })
	local function setColors()
		guiElement.TextColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainText)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the GUI element's scrollbar image color with the theme's scrollbar color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- A GUI element that has a ScrollBarImageColor3 property.
function module.syncGuiElementScrollColor(guiElement: { ScrollBarImageColor3: Color3 })
	local function setColors()
		guiElement.ScrollBarImageColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.ScrollBar)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the GUI element's image color with the theme's main background color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- A GUI element that has an ImageColor3 property.
function module.syncGuiElementImageColor(guiElement: { ImageColor3: Color3 })
	local function setColors()
		guiElement.ImageColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the GUI element's background color with the theme's default button color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- The GUI element to sync.
function module.syncGuiElementButtonColor(guiElement: GuiObject)
	local function setColors()
		guiElement.BackgroundColor3 =
			settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Default)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the GUI element's image color with the theme's default button color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement GuiObject -- A GUI element that has an ImageColor3 property.
function module.syncGuiElementButtonImageColor(guiElement: { ImageColor3: Color3 })
	local function setColors()
		guiElement.ImageColor3 =
			settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Default)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Synchronizes the UIStroke's color with the theme's border color.
--- Updates automatically when the Studio theme changes.
--- @param guiElement UIStroke -- The UIStroke to sync.
function module.syncGuiElementUIStrokeColor(guiElement: UIStroke)
	local function setColors()
		guiElement.Color = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.Border)
	end
	settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
end

--- Syncs the the gui specific property to the specific style and modifier color of the Studio Theme.
--- This also returns the connection so you have more flexibility to disconnect it when you need.
--- @param guiElement GuiObject -- Any Gui Object
--- @param property string -- The property to sync the color like BackgroundColor3, ImageColor3, TextColor3, etc.
--- @param style Enum.StudioStyleGuideColor -- The style guide color.
--- @param modifier Enum.StudioStyleGuideModifier? -- The optional style guide modifier.
--- @return RBXScriptConnection -- The connection of the event. Can be disconnected by doing conn:Disconnect().
function module.syncGuiElementColorCustom(
	guiElement: GuiObject,
	property: string,
	style: Enum.StudioStyleGuideColor,
	modifier: Enum.StudioStyleGuideModifier?
): RBXScriptConnection
	local function setColors()
		guiElement[property] = settings().Studio.Theme:GetColor(style, modifier)
	end
	local connection = settings().Studio.ThemeChanged:Connect(setColors)
	setColors()
	return connection
end

--- Gets the specific color of the currently selected Studio Theme.
--- @param style Enum.StudioStyleGuideColor -- The style guide color.
--- @param modifier Enum.StudioStyleGuideModifier? -- The optional style guide modifier.
--- @return Color3 -- The color if found.
function module.GetThemeColor(style: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	return settings().Studio.Theme:GetColor(style, modifier)
end

--- Gets current Roblox Studio Theme name.
--- @return string -- The color name.
function module.GetThemeName(): string
	return settings().Studio.Theme.Name
end

--- Binds a callback to the theme changed event
--- @param callback () -> () -- The callback function to Connect
--- @return RBXScriptConnection -- The connection of the event. Can be disconnected by doing conn:Disconnect().
function module.BindThemeChanged(callback: () -> ()): RBXScriptConnection
	local connection = settings().Studio.ThemeChanged:Connect(callback)
	return connection
end

--- Calculates the relative position of a click within a GUI element.
--- Returns the normalized (0 to 1) X and Y offsets based on the input object's position
--- relative to the specified GUI element's absolute position.
--- ```luau
---   frame.InputBegan:Connect(function (inputObject: InputObject)
---       local relX, relY = GuiUtilities.GetClickOffsetFromObject(inputObject, frame)
---   end)
--- ```
--- @param inputObject InputObject -- The object containing the input data.
--- @param guiObject GuiObject -- The GUI element to get the relative position within.
--- @return number, number -- Two numbers representing the relative X and Y position.
function module.GetClickOffsetFromObject(inputObject: InputObject, guiElement: GuiObject): (number, number)
	local clickPos = inputObject.Position
	local relX = (clickPos.X - guiElement.AbsolutePosition.X) / guiElement.AbsoluteSize.X
	local relY = (clickPos.Y - guiElement.AbsolutePosition.Y) / guiElement.AbsoluteSize.Y
	return relX, relY
end

--- Creates and returns a Frame with default background and border settings.
--- Automatically synchronizes its background color with the Studio theme's main background.
--- @param name string -- The name to assign to the created Frame.
--- @return Frame -- The styled Frame instance.
function module.MakeFrame(name: string)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0

	module.syncGuiElementBackgroundColor(frame)

	return frame
end

--- Creates and returns a Frame that spans the full horizontal width and has a fixed vertical height.
--- Useful for creating rows or lines containing widgets of arbitrary size.
--- @param name string -- The name to assign to the created Frame.
--- @param height number -- The fixed height in pixels for the Frame.
--- @return Frame -- The fixed-height Frame instance.
function module.MakeFixedHeightFrame(name: string, height: number)
	local frame = module.MakeFrame(name)
	frame.Size = UDim2.new(1, 0, 0, height)

	return frame
end

--- Creates and returns a Frame with a standard fixed height used for typical UI elements
--- like labels, input fields, dropdowns, and checkboxes.
--- Uses `module.kStandardPropertyHeight` as the standard height value.
--- @param name string -- The name to assign to the created Frame.
--- @return Frame -- The standard-height Frame instance.
function module.MakeStandardFixedHeightFrame(name: string)
	return module.MakeFixedHeightFrame(name, module.kStandardPropertyHeight)
end

--- Dynamically adjusts the height of a frame to match the total height of its children,
--- based on a UIListLayout's AbsoluteContentSize. Optional padding can be added.
--- Automatically updates the frame's height when the layout's size changes.
---
--- @param frame GuiObject -- The frame whose height will be dynamically adjusted.
--- @param uiLayout UIListLayout -- The layout used to determine the total content height.
--- @param optPadding number? -- Optional additional padding added to the total height.
function module.AdjustHeightDynamicallyToLayout(frame: GuiObject, uiLayout: UIListLayout, optPadding: number?)
	local function updateSizes()
		frame.Size = UDim2.new(1, 0, 0, uiLayout.AbsoluteContentSize.Y + (optPadding or 0))
	end
	uiLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSizes)
	updateSizes()
end

--- Adds a list of frames as children to a given frame that uses a UIListLayout with `LayoutOrder`-based sorting.
--- Each child frame is assigned an increasing `LayoutOrder` to maintain order.
--- Also applies striped background colors and border colors to each frame for visual clarity.
---
--- @param listFrame GuiObject -- The parent frame that contains a UIListLayout.
--- @param frames {GuiObject} -- A list of frames to add as children, in order.
function module.AddStripedChildrenToListFrame(listFrame: GuiObject, frames: { GuiObject })
	for index, frame in ipairs(frames) do
		frame.Parent = listFrame
		frame.LayoutOrder = index
		frame.BackgroundTransparency = 0
		frame.BorderSizePixel = 1
		module.syncGuiElementStripeColor(frame)
		module.syncGuiElementBorderColor(frame)
	end
end

--- Creates a section frame inside a given parent GUI element, optionally including a title bar and fixed content height.
--- If a title is provided, a title bar is created and positioned at the top.
--- The frame's total height is adjusted to include the title bar and the optional content height.
---
--- @param parentGui GuiObject -- The GUI object that will serve as the parent for the new section frame.
--- @param name string -- The name assigned to the new frame.
--- @param title string? -- Optional title text; if provided, a title bar will be added.
--- @param contentHeight number? -- Optional fixed height for the content area of the section.
--- @return Frame -- The constructed section frame.
local function MakeSectionInternal(parentGui: GuiObject, name: string, title: string?, contentHeight: number?)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Parent = parentGui
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	-- If title is "nil', no title bar.
	local contentYOffset = 0
	if title then
		local titleBarFrame = Instance.new("Frame")
		titleBarFrame.Name = "TitleBarFrame"
		titleBarFrame.Parent = frame
		titleBarFrame.Position = UDim2.new(0, 0, 0, 0)
		titleBarFrame.LayoutOrder = 0

		local titleBar = Instance.new("TextLabel")
		titleBar.Name = "TitleBarLabel"
		titleBar.Text = title
		titleBar.Parent = titleBarFrame
		titleBar.BackgroundTransparency = 1
		titleBar.Position = UDim2.new(0, module.kStandardHMargin, 0, 0)

		module.syncGuiElementFontColor(titleBar)

		contentYOffset = contentYOffset + module.kTitleBarHeight
	end

	frame.Size = UDim2.new(1, 0, 0, contentYOffset + (contentHeight or 0))

	return frame
end

--- Creates a standard property label `TextLabel` with left alignment and predefined styling for use in property UIs.
--- Optionally syncs the label's font color with the current Studio theme unless `opt_ignoreThemeUpdates` is true.
---
--- @param text string -- The text to display in the label.
--- @param opt_ignoreThemeUpdates boolean? -- If true, skips syncing the font color with the Studio theme.
--- @return TextLabel -- The constructed label instance.
function module.MakeStandardPropertyLabel(text: string, opt_ignoreThemeUpdates: boolean?)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans --todo: input spec font
	label.TextSize = 15 --todo: input spec font size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, module.StandardLineLabelLeftMargin, 0.5, module.kTextVerticalFudge)
	label.Size = UDim2.new(0, module.StandardLineLabelWidth, 1, 0)

	if not opt_ignoreThemeUpdates then
		module.syncGuiElementFontColor(label)
	end

	return label
end

--- Creates a frame with a subsection label. The frame has a fixed height and transparent background,
--- and contains a left-aligned label styled for subsection headers.
---
--- @param name string -- The name to assign to the frame.
--- @param text string -- The text to display in the label.
--- @return Frame -- The constructed frame containing the subsection label.
function module.MakeFrameWithSubSectionLabel(name: string, text: string)
	local row = module.MakeFixedHeightFrame(name, module.kSubSectionLabelHeight)
	row.BackgroundTransparency = 1

	local label = module.MakeStandardPropertyLabel(text)
	label.BackgroundTransparency = 1
	label.Parent = row

	return row
end

--- Adds a `UIListLayout` to the given frame and sets up dynamic height adjustment so that the frame
--- automatically resizes based on its children’s total height.
---
--- @param frame GuiObject -- The frame to attach the auto-scaling list layout to.
function module.MakeFrameAutoScalingList(frame: GuiObject)
	local uiListLayout = Instance.new("UIListLayout")
	uiListLayout.Parent = frame
	uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder

	module.AdjustHeightDynamicallyToLayout(frame, uiListLayout)
end

return module
