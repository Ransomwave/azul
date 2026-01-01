----------------------------------------
--
-- LabeledSlider.lua
--
-- Creates a frame containing a label and a slider control.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")
rbxGuiLibrary = require("../RbxGui")

local kSliderWidth = 100

local kSliderThumbImage = "rbxasset://textures/RoactStudioWidgets/button_radiobutton_chosen.png"

local kThumbSize = 13

LabeledSliderClass = {}
LabeledSliderClass.__index = LabeledSliderClass

--- LabeledSliderClass constructor.
--- @param nameSuffix string -- Suffix to append to the slider's name.
--- @param labelText string -- Text to display as the label for the slider.
--- @param minValue number? -- Optional minimum value of the slider (default is 1).
--- @param maxValue number? -- Optional maximum value of the slider.
--- @param defaultValue number? -- Optional default value of the slider.
--- @param width number? -- Optional width of the slider component.
--- @return LabeledSliderClass -- A new instance of the labeled slider class.
function LabeledSliderClass.new(nameSuffix: string, labelText: string, minValue: number?, maxValue: number?, defaultValue: number?, width: number?)
  local self = {}
  setmetatable(self, LabeledSliderClass)

  self._valueChangedFunction = nil

  minValue = minValue or 0
  maxValue = maxValue or 100
  defaultValue = defaultValue or 1
  width = width or kSliderWidth

  local frame = GuiUtilities.MakeStandardFixedHeightFrame("SLF" .. nameSuffix)
  self._frame = frame

  local label = GuiUtilities.MakeStandardPropertyLabel(labelText)
  label.Parent = frame
  self._label = label

  self._value = defaultValue

   --steps, width, position
  local slider, sliderValue = rbxGuiLibrary.CreateSliderNewest(minValue,maxValue, 
    width, 
    UDim2.new(0, 0, .5, -3))
  self._slider = slider
  self._sliderValue = sliderValue
  -- Some tweaks to make slider look nice.
  -- Hide the existing bar.
  slider.Bar.BackgroundTransparency = 1
  -- Replace slider thumb image.
  self._thumb = slider.Bar.Slider
  self._thumb.Image = kSliderThumbImage
  self._thumb.AnchorPoint = Vector2.new(0.5, 0.5)
  self._thumb.Size = UDim2.new(0, kThumbSize, 0, kThumbSize)
  
  -- Add images on bar.
  self._preThumbImage = Instance.new("ImageLabel")
  self._preThumbImage.Name = "PreThumb"
  self._preThumbImage.Parent = slider.Bar
  self._preThumbImage.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
  self._preThumbImage.Image = ""
  self._preThumbImage.Size = UDim2.new(1, 0, 1, 0)
  self._preThumbImage.Position = UDim2.new(0, 0, 0, 0)
  self._preThumbImage.BorderSizePixel = 0

  self._postThumbImage = Instance.new("Frame")
  self._postThumbImage.Name = "PostThumb"
  self._postThumbImage.Parent = slider.Bar
  self._postThumbImage.Size = UDim2.new(1, 0, 1, 0)
  self._postThumbImage.Position = UDim2.new(0, 0, 0, 0)
  self._postThumbImage.BorderSizePixel = 0

  sliderValue.Changed:Connect(function()
    self._value = sliderValue.Value
    
    -- Min value is minValue.
    -- Max value is maxValue.
    -- So scale is...
    local scale = (self._value - minValue) / (maxValue :: number - minValue :: number)

    self._preThumbImage.Size = UDim2.new(scale, 0, 1, 0)
    self._postThumbImage.Size = UDim2.new(1 - scale, 0, 1, 0)
    self._postThumbImage.Position = UDim2.new(scale, 0, 0, 0)
    
    self._thumb.Position = UDim2.new(scale, 0, 
      0.5, 0)
    
    if self._valueChangedFunction then 
      self._valueChangedFunction(self._value)
    end
  end)

  GuiUtilities.BindThemeChanged(function () self:_UpdateColors() end)
  self:_UpdateColors()
  
  if defaultValue == sliderValue.Value then self:SetValue(maxValue) end -- if both are the same the slider won't update its position
  self:SetValue(defaultValue)
  slider.AnchorPoint = Vector2.new(0, 0.5)
  slider.Size = UDim2.new(0, width, 1, 0)
  slider.Position = UDim2.new(0, GuiUtilities.StandardLineElementLeftMargin, 0, GuiUtilities.kStandardPropertyHeight/2)
  slider.Parent = frame
  
  return self
end

--- Sets the function to be called when the slider value changes.
--- @param vcf function -- The callback function to execute on value change.
function LabeledSliderClass:SetValueChangedFunction(vcf)
  self._valueChangedFunction = vcf
end

--- Returns the UI frame associated with this labeled slider.
--- @return Frame -- The slider's UI frame.
function LabeledSliderClass:GetFrame()
  return self._frame
end

--- Sets the slider's current value.
--- @param newValue number -- The value to set.
function LabeledSliderClass:SetValue(newValue: number)
  if self._sliderValue.Value ~= newValue then
    self._sliderValue.Value = newValue
  end
end

--- Gets the slider's current value.
--- @return number -- The current value of the slider.
function LabeledSliderClass:GetValue()
  return self._sliderValue.Value
end

--- Changes the label text displayed above the slider.
--- @param labelText string -- New label text to display.
function LabeledSliderClass:SetLabelText(labelText: string)
  assert(type(labelText) == "string", "Expected string. Got "..type(labelText))
  self._label.Text = labelText
end

function LabeledSliderClass:_UpdateColors()
  local guide = if GuiUtilities.GetThemeName() == "Light" then Enum.StudioStyleGuideColor.ScrollBarBackground else Enum.StudioStyleGuideColor.InputFieldBackground
  self._postThumbImage.BackgroundColor3 = GuiUtilities.GetThemeColor(guide)
end

return LabeledSliderClass