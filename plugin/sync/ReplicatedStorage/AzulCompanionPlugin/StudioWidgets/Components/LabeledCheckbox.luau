----------------------------------------
--
-- LabeledCheckbox.lua
--
-- Creates a frame containing a label and a checkbox.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local kCheckboxWidth = GuiUtilities.kCheckboxWidth

local kMinTextSize = 14
local kMinHeight = 24
local kMinLabelWidth = GuiUtilities.kCheckboxMinLabelWidth
local kMinMargin = GuiUtilities.kCheckboxMinMargin
local kMinButtonWidth = kCheckboxWidth

local kMinLabelSize = UDim2.new(0, kMinLabelWidth, 0, kMinHeight)
local kMinLabelPos = UDim2.new(0, kMinButtonWidth + kMinMargin, 0, kMinHeight / 2)

local kMinButtonSize = UDim2.new(0, kMinButtonWidth, 0, kMinButtonWidth)
local kMinButtonPos = UDim2.new(0, 0, 0, kMinHeight / 2)

local kCheckImageWidth = 8
local kMinCheckImageWidth = kCheckImageWidth

local kCheckImageSize = UDim2.new(0, kCheckImageWidth, 0, kCheckImageWidth)
local kMinCheckImageSize = UDim2.new(0, kMinCheckImageWidth, 0, kMinCheckImageWidth)

local kDisabledCheckImage = "rbxasset://textures/DeveloperFramework/checkbox_unchecked_dark.png"
local kEnabledCheckImageLight = "rbxasset://textures/PluginManagement/checked_light.png"
local kEnabledCheckImageDark = "rbxasset://textures/PluginManagement/checked_dark.png"
local kCheckboxFrameImage = kDisabledCheckImage

LabeledCheckboxClass = {}
LabeledCheckboxClass.__index = LabeledCheckboxClass

LabeledCheckboxClass.kMinFrameSize = UDim2.new(0, kMinLabelWidth + kMinMargin + kMinButtonWidth, 0, kMinHeight)

--- LabeledCheckboxClass constructor.
--- @param nameSuffix string -- Suffix to append to the checkbox's name for uniqueness.
--- @param labelText string -- Text to display next to the checkbox.
--- @param initValue boolean -- Initial checked state of the checkbox.
--- @param initDisabled boolean -- Whether the checkbox should be initially disabled.
--- @return LabeledCheckboxClass -- A new instance of the labeled checkbox class.
function LabeledCheckboxClass.new(nameSuffix: string, labelText: string, initValue: boolean, initDisabled: boolean)
	local self = {}
	setmetatable(self, LabeledCheckboxClass)

	initValue = not not initValue
	initDisabled = not not initDisabled

	local frame = GuiUtilities.MakeStandardFixedHeightFrame("CBF" .. nameSuffix)

	local fullBackgroundButton = Instance.new("TextButton")
	fullBackgroundButton.Name = "FullBackground"
	fullBackgroundButton.Parent = frame
	fullBackgroundButton.BackgroundTransparency = 1
	fullBackgroundButton.Size = UDim2.new(1, 0, 1, 0)
	fullBackgroundButton.Position = UDim2.new(0, 0, 0, 0)
	fullBackgroundButton.Text = ""

	local label = GuiUtilities.MakeStandardPropertyLabel(labelText, true)
	label.Parent = fullBackgroundButton

	local button = Instance.new("ImageButton")
	button.Name = "Button"
	button.Size = UDim2.new(0, kCheckboxWidth, 0, kCheckboxWidth)
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.BackgroundTransparency = 1
	button.Position = UDim2.new(0, GuiUtilities.StandardLineElementLeftMargin, 0.5, 0)
	button.Parent = fullBackgroundButton
	button.Image = kCheckboxFrameImage
	button.BorderSizePixel = 0
	button.AutoButtonColor = false

	local checkImage = Instance.new("ImageLabel")
	checkImage.Name = "CheckImage"
	checkImage.Parent = button
	checkImage.Image = kEnabledCheckImageLight
	checkImage.Visible = false
	checkImage.Size = UDim2.new(1, 3, 1, 3)
	checkImage.AnchorPoint = Vector2.new(0.5, 0.5)
	checkImage.Position = UDim2.new(0.5, 0, 0.5, 0)
	checkImage.BackgroundTransparency = 1
	checkImage.BorderSizePixel = 0

	self._frame = frame
	self._button = button
	self._label = label
	self._checkImage = checkImage
	self._fullBackgroundButton = fullBackgroundButton
	self._useDisabledOverride = false
	self._disabledOverride = false
	self:SetDisabled(initDisabled)

	self._value = not initValue
	self:SetValue(initValue)

	self:_SetupMouseClickHandling()

	GuiUtilities.BindThemeChanged(function()
		self:_UpdateFontColors()
	end)
	GuiUtilities.BindThemeChanged(function()
		self:_UpdateAppearance()
	end)
	self:_UpdateAppearance()
	self:_UpdateFontColors()

	return self
end

function LabeledCheckboxClass:_MaybeToggleState()
	if not self._disabled then
		self:SetValue(not self._value)
	end
end

function LabeledCheckboxClass:_SetupMouseClickHandling()
	self._button.MouseButton1Down:Connect(function()
		self:_MaybeToggleState()
	end)

	self._fullBackgroundButton.MouseButton1Down:Connect(function()
		self:_MaybeToggleState()
	end)
end

function LabeledCheckboxClass:_HandleUpdatedValue()
	--self._checkImage.Visible = self:GetValue()

	if not self._checkImage.Visible then
		self._checkImage.Visible = true
	end

	self:_UpdateAppearance()

	if self._valueChangedFunction then
		self._valueChangedFunction(self:GetValue())
	end
end

function LabeledCheckboxClass:_UpdateFontColors()
	if self._disabled then
		self._label.TextColor3 =
			GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.MainText, Enum.StudioStyleGuideModifier.Disabled)
	else
		self._label.TextColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.MainText)
	end
end

function LabeledCheckboxClass:_UpdateAppearance()
	if self:GetValue() then
		self._checkImage.Image = if GuiUtilities.GetThemeName() == "Light"
			then kEnabledCheckImageLight
			else kEnabledCheckImageDark
		self._checkImage.ImageColor3 = if GuiUtilities.GetThemeName() == "Light"
			then Color3.fromRGB(219, 219, 219)
			else Color3.new(1, 1, 1)
	else
		self._checkImage.Image = kDisabledCheckImage
		self._checkImage.ImageColor3 = GuiUtilities.GetThemeColor(
			Enum.StudioStyleGuideColor.CheckedFieldBackground,
			Enum.StudioStyleGuideModifier.Default
		)
	end
	self._button.Image = kCheckboxFrameImage
end

--- Enables the small size variant for the checkbox UI.
--- This adjusts the checkbox to use smaller dimensions, fixed width layout,
--- and places the checkbox box before the label.
--- Fixed width instead of flood-fill.
function LabeledCheckboxClass:UseSmallSize()
	self._label.TextSize = kMinTextSize
	self._label.Size = kMinLabelSize
	self._label.Position = kMinLabelPos
	self._label.TextXAlignment = Enum.TextXAlignment.Left

	self._button.Size = kMinButtonSize
	self._button.Position = kMinButtonPos

	self._checkImage.Size = kMinCheckImageSize

	self._frame.Size = LabeledCheckboxClass.kMinFrameSize
	self._frame.BackgroundTransparency = 1
end

--- Returns the UI frame of the labeled checkbox.
--- @return Frame -- The main frame containing the checkbox and label.
function LabeledCheckboxClass:GetFrame(): Frame
	return self._frame
end

--- Returns the current value of the checkbox.
--- If disabled and an override is active, returns the override value instead.
--- @return boolean -- The current effective value of the checkbox.
function LabeledCheckboxClass:GetValue(): boolean
	-- If button is disabled, and we should be using a disabled override,
	-- use the disabled override.
	if self._disabled and self._useDisabledOverride then
		return self._disabledOverride
	else
		return self._value
	end
end

--- Returns the label UI element associated with the checkbox.
--- @return TextLabel -- The label component of the checkbox.
function LabeledCheckboxClass:GetLabel(): TextLabel
	return self._label
end

--- Returns the button UI element that represents the checkbox.
--- @return TextButton -- The button used to toggle the checkbox state.
function LabeledCheckboxClass:GetButton(): TextButton
	return self._button
end

--- Sets a callback function to be called when the checkbox value changes.
--- @param vcFunction (newValue: boolean) -> () -- The function to call on value change.
function LabeledCheckboxClass:SetValueChangedFunction(vcFunction: (newValue: boolean) -> ())
	self._valueChangedFunction = vcFunction
end

--- Sets the disabled state of the checkbox.
--- Updates visuals and optionally triggers a value update if the state change affects the value.
--- @param newDisabled boolean -- Whether the checkbox should be disabled.
function LabeledCheckboxClass:SetDisabled(newDisabled: boolean)
	local originalValue = self:GetValue()

	if newDisabled ~= self._disabled then
		self._disabled = newDisabled

		-- if we are no longer disabled, then we don't need or want
		-- the override any more.  Forget it.
		if not self._disabled then
			self._useDisabledOverride = false
		end

		if newDisabled then
			self._checkImage.Image = kDisabledCheckImage
		else
			self._checkImage.Image = kEnabledCheckImageLight
		end

		self:_UpdateFontColors()
		self:_UpdateAppearance()
		self._button.BackgroundColor3 = self._disabled and GuiUtilities.kButtonDisabledBackgroundColor
			or GuiUtilities.kButtonStandardBackgroundColor
		self._button.BorderColor3 = self._disabled and GuiUtilities.kButtonDisabledBorderColor
			or GuiUtilities.kButtonStandardBorderColor
		if self._disabledChangedFunction then
			self._disabledChangedFunction(self._disabled)
		end
	end

	local newValue = self:GetValue()
	if newValue ~= originalValue then
		self:_HandleUpdatedValue()
	end
end

--- Returns whether the checkbox is currently disabled.
--- @return boolean -- True if the checkbox is disabled; otherwise false.
function LabeledCheckboxClass:GetDisabled(): boolean
	return self._disabled
end

--- Disables the checkbox and forces it to use an override value while disabled.
--- This is useful for displaying a locked state while maintaining UI logic.
--- @param overrideValue boolean -- The forced value to use while disabled.
function LabeledCheckboxClass:DisableWithOverrideValue(overrideValue: boolean)
	-- Disable this checkbox.  While disabled, force value to override
	-- value.
	local oldValue = self:GetValue()
	self._useDisabledOverride = true
	self._disabledOverride = overrideValue
	self:SetDisabled(true)
	local newValue = self:GetValue()
	if oldValue ~= newValue then
		self:_HandleUpdatedValue()
	end
end

--- Sets the value of the checkbox manually.
--- Triggers any relevant updates if the value has changed.
--- @param newValue boolean -- The new value to assign to the checkbox.
function LabeledCheckboxClass:SetValue(newValue: boolean)
	if newValue ~= self._value then
		self._value = newValue

		self:_HandleUpdatedValue()
	end
end

return LabeledCheckboxClass