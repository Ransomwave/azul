----------------------------------------
--
-- CollapsibleTitledSectionClass
--
-- Creates a section with a title label:
--
-- "SectionXXX"
--     "TitleBarVisual"
--     "Contents"
--
-- Requires "parent" and "sectionName" parameters and returns the section and its contentsFrame
-- The entire frame will resize dynamically as contents frame changes size.
--
-- "autoScalingList" is a boolean that defines wheter or not the content frame automatically resizes when children are added.
-- This is important for cases when you want minimize button to push or contract what is below it.
--
-- Both "minimizeable" and "minimizedByDefault" are false by default
-- These parameters define if the section will have an arrow button infront of the title label,
-- which the user may use to hide the section's contents
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local kArrowSpriteSheet = "rbxasset://textures/StudioSharedUI/arrowSpritesheet.png"
local kRightButtonRectSize = Vector2.new(12, 12)
local kRightButtonRectOffset = Vector2.new(12, 0)
local kDownButtonRectSize = Vector2.new(12, 12)
local kDownButtonRectOffset = Vector2.new(24, 0)

local kArrowSize = 9
local kDoubleClickTimeSec = 0.5

CollapsibleTitledSectionClass = {}
CollapsibleTitledSectionClass.__index = CollapsibleTitledSectionClass

--- CollapsibleTitledSectionClass constructor.
--- @param nameSuffix string -- The name suffix of the text input.
--- @param titleText string -- The title text.
--- @param autoScalingList boolean? -- Should it automatically update its size based on the content? Defaults to true.
--- @param minimizable boolean? -- Should it be minimizable? Defaults to true.
--- @param minimizedByDefault boolean? -- Should it start minimized? Defaults to true.
--- @return CollapsibleTitledSectionClass -- The CollapsibleTitledSection class object.
function CollapsibleTitledSectionClass.new(
	nameSuffix: string,
	titleText: string,
	autoScalingList: boolean?,
	minimizable: boolean?,
	minimizedByDefault: boolean?
)
	local self = {}
	setmetatable(self, CollapsibleTitledSectionClass)

	self._minimized = minimizedByDefault == true
	self._minimizable = minimizable == true

	self._titleBarHeight = GuiUtilities.kTitleBarHeight

	local frame = Instance.new("Frame")
	frame.Name = "CTSection" .. nameSuffix
	frame.BackgroundTransparency = 1
	self._frame = frame

	local uiListLayout = Instance.new("UIListLayout")
	uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	uiListLayout.Parent = frame
	self._uiListLayout = uiListLayout

	local contentsFrame = Instance.new("Frame")
	contentsFrame.Name = "Contents"
	contentsFrame.BackgroundTransparency = 1
	contentsFrame.Size = UDim2.new(1, 0, 0, 1)
	contentsFrame.Position = UDim2.new(0, 0, 0, 0)
	contentsFrame.Parent = frame
	contentsFrame.LayoutOrder = 2
	GuiUtilities.syncGuiElementBackgroundColor(contentsFrame)

	self._contentsFrame = contentsFrame

	uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_UpdateSize()
	end)
	self:_UpdateSize()

	self:_CreateTitleBar(titleText)
	self:SetCollapsedState(self._minimized)

	self._autoScalingList = autoScalingList == true
	if self._autoScalingList then
		GuiUtilities.MakeFrameAutoScalingList(self:GetContentsFrame())
	end

	return self
end

--- Gets the frame of this Collapsible Section itself.
--- @return Frame This Collapsible Section frame.
function CollapsibleTitledSectionClass:GetSectionFrame(): Frame
	return self._frame
end

--- Gets the frame that contains everything that is inside this Collapsible Section.
--- @return Frame The frame that contains everything inside this Collapsible Section.
function CollapsibleTitledSectionClass:GetContentsFrame(): Frame
	return self._contentsFrame
end

function CollapsibleTitledSectionClass:_UpdateSize()
	local totalSize = self._uiListLayout.AbsoluteContentSize.Y
	self._frame.Size = UDim2.new(1, 0, 0, totalSize)
end

function CollapsibleTitledSectionClass:_UpdateMinimizeButton()
	-- We can't rotate it because rotated images don't get clipped by parents.
	-- This is all in a scroll widget.
	-- :(
	if self._minimized then
		self._minimizeButton.Image = kArrowSpriteSheet
		self._minimizeButton.ImageRectSize = kRightButtonRectSize
		self._minimizeButton.ImageRectOffset = kRightButtonRectOffset
	else
		self._minimizeButton.Image = kArrowSpriteSheet
		self._minimizeButton.ImageRectSize = kDownButtonRectSize
		self._minimizeButton.ImageRectOffset = kDownButtonRectOffset
	end
end

--- Sets the collapsed state. Whether or not its open and showing its contents.
--- @param state boolean -- A boolean representing the state to set.
function CollapsibleTitledSectionClass:SetCollapsedState(state: boolean)
	if not self._minimizable then
		return
	end
	self._minimized = state
	self._contentsFrame.Visible = not state
	self:_UpdateMinimizeButton()
	self:_UpdateSize()
end

function CollapsibleTitledSectionClass:_ToggleCollapsedState()
	if not self._minimizable then
		return
	end
	self:SetCollapsedState(not self._minimized)
end

function CollapsibleTitledSectionClass:_CreateTitleBar(titleText)
	local titleTextOffset = self._titleBarHeight

	local titleBar = Instance.new("ImageButton")
	titleBar.AutoButtonColor = false
	titleBar.Name = "TitleBarVisual"
	titleBar.BorderSizePixel = 0
	titleBar.Position = UDim2.new(0, 0, 0, 0)
	titleBar.Size = UDim2.new(1, 0, 0, self._titleBarHeight)
	titleBar.Parent = self._frame
	titleBar.LayoutOrder = 1
	titleBar.BorderMode = Enum.BorderMode.Middle
	titleBar.BorderSizePixel = 1
	GuiUtilities.syncGuiElementTitleColor(titleBar)
	GuiUtilities.syncGuiElementBorderColor(titleBar)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.SourceSansBold --todo: input spec font
	titleLabel.TextSize = 15 --todo: input spec font size
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = titleText
	titleLabel.Position = UDim2.new(0, titleTextOffset, 0, 0)
	titleLabel.Size = UDim2.new(1, -titleTextOffset, 1, GuiUtilities.kTextVerticalFudge)
	titleLabel.Parent = titleBar
	GuiUtilities.syncGuiElementFontColor(titleLabel)

	self._minimizeButton = Instance.new("ImageButton")
	self._minimizeButton.Name = "MinimizeSectionButton"
	self._minimizeButton.Image = kArrowSpriteSheet
	self._minimizeButton.ImageRectSize = kRightButtonRectSize
	self._minimizeButton.ImageRectOffset = kRightButtonRectOffset
	self._minimizeButton.Size = UDim2.new(0, kArrowSize, 0, kArrowSize)
	self._minimizeButton.AnchorPoint = Vector2.new(0.5, 0.5)
	self._minimizeButton.Position = UDim2.new(0, self._titleBarHeight * 0.5, 0, self._titleBarHeight * 0.5)
	self._minimizeButton.BackgroundTransparency = 1
	self._minimizeButton.Visible = self._minimizable -- only show when minimizable
	GuiUtilities.syncGuiElementColorCustom(
		self._minimizeButton,
		"ImageColor3",
		Enum.StudioStyleGuideColor.ScriptText,
		Enum.StudioStyleGuideModifier.Default
	)

	self._minimizeButton.MouseButton1Down:Connect(function()
		self:_ToggleCollapsedState()
	end)
	self:_UpdateMinimizeButton()
	self._minimizeButton.Parent = titleBar

	self._latestClickTime = 0
	titleBar.MouseButton1Down:Connect(function()
		local now = tick()
		if now - self._latestClickTime < kDoubleClickTimeSec then
			self:_ToggleCollapsedState()
			self._latestClickTime = 0
		else
			self._latestClickTime = now
		end
	end)
end

--- Adds a child frame to the contents section of the collapsible titled section.
--- @param childFrame GuiObject -- The GUI object to add to the contents frame.
--- @param layoutOrder number? -- Optional layout order to assign to the child frame.
function CollapsibleTitledSectionClass:AddChild(childFrame: GuiObject, layoutOrder: number?)
	if layoutOrder then
		childFrame.LayoutOrder = layoutOrder
	end
	childFrame.Parent = self._contentsFrame
end

return CollapsibleTitledSectionClass
