----------------------------------------
--
-- ColorPicker.lua
--
-- Creates a frame containing a color picker.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local CustomTextButton = require("./CustomTextButton")
local VerticallyScalingListFrame = require("./VerticallyScalingListFrame")

local kColorPickedLabelHeight = 20

local ColorPickerClass = {}
ColorPickerClass.__index = ColorPickerClass

--- ColorPickerClass constructor.
--- @param nameSuffix string -- Suffix to append to the color picker's name.
--- @return ColorPickerClass -- A new instance of the color picker class.
function ColorPickerClass.new(nameSuffix: string)
  local self = setmetatable({}, ColorPickerClass)

  self._cancelFunction = nil
  self._confirmFunction = nil
  self._valueChangedFunction = nil

  local frame = Instance.new("Frame")
  frame.Name = "ClPck " .. nameSuffix
  frame.BackgroundColor3 = Color3.fromRGB(53, 53, 53)
  frame.BorderSizePixel = 0
  frame.Size = UDim2.fromOffset(170, 186)
  GuiUtilities.syncGuiElementBackgroundColor(frame)

  local colorSpectrum = Instance.new("ImageButton")
  colorSpectrum.Name = "ColorSpectrum"
  colorSpectrum.AutoButtonColor = false
  colorSpectrum.BackgroundColor3 = Color3.new(1, 1, 1)
  colorSpectrum.Image = "rbxassetid://18967417547"
  colorSpectrum.Position = UDim2.new(0, 15, 0, 7)
  colorSpectrum.Size = UDim2.new(0, 111, 0, 111)
  colorSpectrum.BorderSizePixel = 1
  colorSpectrum.Parent = frame
  GuiUtilities.syncGuiElementBorderColor(colorSpectrum)

  local colorBrightness = Instance.new("ImageButton")
  colorBrightness.Name = "ColorBrightness"
  colorBrightness.AnchorPoint = Vector2.new(0.5, 0)
  colorBrightness.AutoButtonColor = false
  colorBrightness.BackgroundColor3 = Color3.new(1, 1, 1)
  colorBrightness.Image = ""
  colorBrightness.Position = UDim2.new(1, -20, 0, 7)
  colorBrightness.Size = UDim2.new(0, 16, 0, 107)
  colorBrightness.BorderSizePixel = 1
  colorBrightness.Parent = frame
  GuiUtilities.syncGuiElementBorderColor(colorBrightness)

  local colorBrightnessKnob = Instance.new("Frame")
  colorBrightnessKnob.Name = "Knob"
  colorBrightnessKnob.AnchorPoint = Vector2.new(0.5, 0)
  colorBrightnessKnob.BackgroundColor3 = Color3.new(1, 1, 1)
  colorBrightnessKnob.BorderColor3 = Color3.new()
  colorBrightnessKnob.BorderSizePixel = 0
  colorBrightnessKnob.Position = UDim2.fromScale(0.5, 0)
  colorBrightnessKnob.Size = UDim2.fromOffset(25, 10)
  colorBrightnessKnob.Parent = colorBrightness

  local uIGradient = Instance.new("UIGradient")
  uIGradient.Name = "UIGradient"
  uIGradient.Rotation = -90
  uIGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
    ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
  })
  uIGradient.Parent = colorBrightness

  local uiStroke = Instance.new("UIStroke")
  uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  uiStroke.Parent = colorBrightnessKnob

  local uiCorner = Instance.new("UICorner")
  uiCorner.CornerRadius = UDim.new(0, 4)
  uiCorner.Parent = colorBrightnessKnob

  local cross = Instance.new("ImageLabel")
  cross.Name = "CrossIcon"
  cross.AnchorPoint = Vector2.new(0.5, 0.5)
  cross.BackgroundTransparency = 1
  cross.Image = "rbxassetid://15929013661"
  cross.Position = UDim2.fromScale(0, 0)
  cross.Size = UDim2.fromOffset(20, 20)
  cross.Parent = colorSpectrum

  local buttonsContainer = Instance.new("Frame")
  buttonsContainer.Name = "ButtonsContainer"
  buttonsContainer.AnchorPoint = Vector2.new(0.5, 1)
  buttonsContainer.BackgroundColor3 = Color3.fromRGB(169, 255, 129)
  buttonsContainer.BackgroundTransparency = 1
  buttonsContainer.BorderSizePixel = 0
  buttonsContainer.Position = UDim2.fromScale(0.5, 1)
  buttonsContainer.Size = UDim2.fromOffset(170, 36)
  buttonsContainer.Parent = frame

  local outputContainer = Instance.new("Frame")
  outputContainer.Name = "OutputContainer"
  outputContainer.AnchorPoint = Vector2.new(0.5, 1)
  outputContainer.BackgroundTransparency = 1
  outputContainer.BackgroundColor3 = Color3.fromRGB(40, 132, 181)
  outputContainer.BorderSizePixel = 0
  outputContainer.Position = UDim2.fromScale(0.5, 0.8)
  outputContainer.Size = UDim2.fromOffset(170, 24)
  outputContainer.Parent = frame

  local colorPreviewBox = Instance.new("Frame")
  colorPreviewBox.Name = "ColorPreview"
  colorPreviewBox.AnchorPoint = Vector2.new(0, 0.5)
  colorPreviewBox.BackgroundColor3 = Color3.new(1, 1, 1)
  colorPreviewBox.Position = UDim2.new(0, 15, 0.5, 0)
  colorPreviewBox.Size = UDim2.new(0, 18, 0, 18)
  colorPreviewBox.Parent = outputContainer
  GuiUtilities.syncGuiElementBorderColor(colorPreviewBox)

  local colorRGBCode = Instance.new("TextBox")
  colorRGBCode.Name = "ColorRGBCode"
  colorRGBCode.AnchorPoint = Vector2.new(0, 0.5)
  colorRGBCode.BackgroundColor3 = Color3.fromRGB(61, 255, 232)
  colorRGBCode.BorderColor3 = Color3.fromRGB(34, 34, 34)
  colorRGBCode.BorderSizePixel = 1
  colorRGBCode.ClearTextOnFocus = false
  colorRGBCode.Font = Enum.Font.SourceSans
  colorRGBCode.Position = UDim2.new(0, 36, 0.5, 0)
  colorRGBCode.Size = UDim2.fromOffset(62, 20)
  colorRGBCode.Text = "255,255,255"
  colorRGBCode.TextColor3 = Color3.fromRGB(204, 204, 204)
  colorRGBCode.TextEditable = false
  colorRGBCode.TextSize = 15
  colorRGBCode.Parent = outputContainer
  GuiUtilities.syncGuiElementFontColor(colorRGBCode)
  GuiUtilities.syncGuiElementInputFieldColor(colorRGBCode)
  GuiUtilities.syncGuiElementBorderColor(colorRGBCode)

  local colorHexCode = Instance.new("TextBox")
  colorHexCode.Name = "ColorHexCode"
  colorHexCode.AnchorPoint = Vector2.new(0, 0.5)
  colorHexCode.BackgroundColor3 = Color3.fromRGB(61, 255, 232)
  colorHexCode.BorderColor3 = Color3.fromRGB(34, 34, 34)
  colorHexCode.BorderSizePixel = 1
  colorHexCode.ClearTextOnFocus = false
  colorHexCode.Font = Enum.Font.SourceSans
  colorHexCode.Position = UDim2.new(0, 101, 0.5, 0)
  colorHexCode.Size = UDim2.fromOffset(55, 20)
  colorHexCode.Text = "#FFFFFF"
  colorHexCode.TextColor3 = Color3.fromRGB(204, 204, 204)
  colorHexCode.TextEditable = false
  colorHexCode.TextSize = 15
  colorHexCode.Parent = outputContainer
  GuiUtilities.syncGuiElementFontColor(colorHexCode)
  GuiUtilities.syncGuiElementInputFieldColor(colorHexCode)
  GuiUtilities.syncGuiElementBorderColor(colorHexCode)

  colorSpectrum.InputBegan:Connect(function (inputObject: InputObject)
    if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    self._dragging = true
    self:_OnColorSpectrumClick(inputObject)
  end)

  colorSpectrum.InputChanged:Connect(function (inputObject: InputObject)
    if not self._dragging then return end
    self:_OnColorSpectrumClick(inputObject)
  end)

  colorSpectrum.InputEnded:Connect(function (inputObject: InputObject)
    if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    self._dragging = false
  end)

  colorBrightness.InputBegan:Connect(function (inputObject: InputObject)
    if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    self._draggingBrightness = true
    self:_OnBrightnessSliderClick(inputObject)
  end)

  colorBrightness.InputChanged:Connect(function (inputObject: InputObject)
    if not self._draggingBrightness then return end
    self:_OnBrightnessSliderClick(inputObject)
  end)

  colorBrightness.InputEnded:Connect(function (inputObject: InputObject)
    if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    self._draggingBrightness = false
  end)

  local verticallyScalingFrame = VerticallyScalingListFrame.new("suffix")
  verticallyScalingFrame:GetFrame().Parent = buttonsContainer
  verticallyScalingFrame:GetFrame().AnchorPoint = Vector2.new(0, 0.5)
  verticallyScalingFrame:GetFrame().Position = UDim2.fromScale(0, 0.5)
  verticallyScalingFrame:SetHorizontalAlignment(Enum.HorizontalAlignment.Center)
  verticallyScalingFrame:SetVerticalAlignment(Enum.VerticalAlignment.Center)
  verticallyScalingFrame:SetFillDirection(Enum.FillDirection.Horizontal)
  verticallyScalingFrame:SetLayoutPadding(UDim.new(0, 5))

  local buttonConfirm = CustomTextButton.new("confirm", "Confirm", true)
  local buttonCancel = CustomTextButton.new("cancel", "Cancel", true)

  verticallyScalingFrame:AddChild(buttonConfirm:GetFrame())
  verticallyScalingFrame:AddChild(buttonCancel:GetFrame())

  self._frame = frame
  self._colorSpectrum = colorSpectrum
  self._colorPreviewBox = colorPreviewBox
  self._colorCodeBoxRGB = colorRGBCode
  self._colorCodeBoxHex = colorHexCode
  self._colorBrightnessSlider = colorBrightness
  self._colorBrightnessKnob = colorBrightnessKnob
  self._colorCross = cross
  self._buttonCancel = buttonCancel
  self._buttonConfirm = buttonConfirm

  self._colorPicked = Color3.new(1,1,1) :: Color3
  self._colorPickedRGBCode = "255,255,255"
  self._colorPickedHexCode = "#FFFFFF"

  self._dragging = false
  self._draggingBrightness = false

  self._hsvHue = 1
  self._hsvSat = 1
  self._hsvVal = 1

  return self
end

function ColorPickerClass:_OnColorSpectrumClick(inputObject: InputObject)
  -- detect clicked color code based on the click position in the color spectrum image
  local relX: number, relY:number = GuiUtilities.GetClickOffsetFromObject(inputObject, self._colorSpectrum)
  if relX >= 0 and relX <= 1 and relY >= 0 and relY <= 1 then
    self._hsvHue = relX
    self._hsvSat = 1 - relY
    self:_CommitColorChange()
    self:_UpdateBrightnessSlider()
    self:_UpdateColorCross()
  end
end

function ColorPickerClass:_OnBrightnessSliderClick(inputObject: InputObject)
  local _, relY = GuiUtilities.GetClickOffsetFromObject(inputObject, self._colorBrightnessSlider)
  self._hsvVal = 1 - relY
  self:_UpdateBrightnessSlider()
  self:_CommitColorChange()
end

function ColorPickerClass:_CommitColorChange(color: Color3?)
  -- Applies and commits a new color to the picker.
  -- If a Color3 parameter is provided, updates internal HSV values accordingly. Used by manually setting the value.
  -- Otherwise, generates a color from current HSV state. Used by interacting with the picker.
  -- Also updates UI elements and triggers the value changed callback if set.
  if color then
    self._colorPicked = color
    local h, s, v = color:ToHSV()
    self._hsvHue = h
    self._hsvSat = s
    self._hsvVal = v
  else
    self._colorPicked = Color3.fromHSV(self._hsvHue, self._hsvSat, self._hsvVal)
  end

  self:_UpdateColorCodeLabel()
  self:_UpdateColorPreviewBox()
  if self._valueChangedFunction then -- fire value changed function
    self._valueChangedFunction(self._colorPicked)
  end
end

function ColorPickerClass:_UpdateColorCross()
  -- positions and paint the color cross
	self._colorCross.Position = UDim2.fromScale(self._hsvHue, 1 - self._hsvSat)
  self._colorCross.ImageColor3 = if 1 - self._hsvSat < 0.4 then Color3.new(1,1,1) else Color3.new(0,0,0)
end

function ColorPickerClass:_UpdateBrightnessSlider()
  self._colorBrightnessKnob.Position = UDim2.new(0.5, 0, 1 - self._hsvVal, 0)
  self._colorBrightnessSlider.UIGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
    ColorSequenceKeypoint.new(1, Color3.fromHSV(self._hsvHue, self._hsvSat, 1)),
  })
end

function ColorPickerClass:_UpdateColorCodeLabel()
  -- generate a color code string like this: R,G,B #HEX
  local R = math.clamp(math.round(self._colorPicked.R * 255), 0, 255)
  local G = math.clamp(math.round(self._colorPicked.G * 255), 0, 255)
  local B = math.clamp(math.round(self._colorPicked.B * 255), 0, 255)
  self._colorPickedHexCode = "#" .. string.upper(self._colorPicked:ToHex())
  self._colorPickedRGBCode = ("%d,%d,%d"):format(R, G, B)
  self._colorCodeBoxRGB.Text = self._colorPickedRGBCode
  self._colorCodeBoxHex.Text = self._colorPickedHexCode
end

function ColorPickerClass:_UpdateColorPreviewBox()
  self._colorPreviewBox.BackgroundColor3 = self._colorPicked
end

--- Sets the function to be called when the cancel button is clicked.
--- @param cf function -- A function to execute when cancel is pressed.
function ColorPickerClass:SetCancelFunction(cf: () -> ())
  self._buttonCancel:SetClickedFunction(cf)
end

--- Sets the function to be called when the confirm button is clicked.
--- Passes the currently selected color to the callback.
--- @param cf function -- A function that takes the selected Color3 as a parameter.
function ColorPickerClass:SetConfirmFunction(cf: (chosenColor: Color3) -> ())
  self._buttonConfirm:SetClickedFunction(function (...)
    cf(self._colorPicked)
  end)
end

--- Sets a callback function to be called when the color value changes.
--- Passing nil will remove the existing callback.
--- @param vcf (newValue: Color3) -> () | nil -- Function to call on color change, or nil to unbind.
function ColorPickerClass:SetValueChangedFunction(vcf: (newValue: Color3) -> () | nil)
  self._valueChangedFunction = vcf
end

--- Returns the main UI frame of the color picker.
--- @return Frame -- The root frame containing the color picker UI.
function ColorPickerClass:GetFrame(): Frame
  return self._frame
end

--- Gets the currently selected color in the color picker.
--- @return Color3 -- The current color selection.
function ColorPickerClass:GetValue(): Color3
  return self._colorPicked
end

--- Sets the currently selected color in the color picker.
--- @param newValue Color3 -- The color to set.
function ColorPickerClass:SetValue(newValue: Color3)
  self:_CommitColorChange(newValue)
  self:_UpdateColorCross()
  self:_UpdateBrightnessSlider()
end

--- Returns the currently picked color as a hex code string.
--- Example: "#FFFFFF" for white.
--- @return string -- The hex code representation of the picked color.
function ColorPickerClass:GetHexCode(): string
  return self._colorPickedHexCode
end


--- Returns the currently picked color as an RGB string.
--- Example: "255,255,255" for white.
--- @return string -- The RGB string representation of the picked color.
function ColorPickerClass:GetRGBCode(): string
  return self._colorPickedRGBCode
end

return ColorPickerClass