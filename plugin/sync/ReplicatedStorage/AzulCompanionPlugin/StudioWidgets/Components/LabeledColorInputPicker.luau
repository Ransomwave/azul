----------------------------------------
--
-- LabeledColorInput.lua
--
-- Creates a frame containing a label and a text input control.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local ColorPicker = require("./ColorPicker")

local kTextInputWidth = 100
local kTextBoxInternalPadding = 4

LabeledColorInputPickerClass = {}
LabeledColorInputPickerClass.__index = LabeledColorInputPickerClass

function round(x)
  return x + 0.5 - (x + 0.5) % 1
end

--- LabeledColorInputPickerClass constructor.
--- @param nameSuffix string -- Suffix to append to the element's name for uniqueness.
--- @param labelText string -- Text label displayed alongside the color input.
--- @param defaultValue Color3 -- The default color value to initialize the input with.
--- @return LabeledColorInputPickerClass -- A new instance of the labeled color input class.
function LabeledColorInputPickerClass.new(nameSuffix: string, labelText: string, defaultValue: Color3)
  local self = {}
  setmetatable(self, LabeledColorInputPickerClass)

  -- Note: we are using "graphemes" instead of characters.
  -- In modern text-manipulation-fu, what with internationalization, 
  -- emojis, etc, it's not enough to count characters, particularly when 
  -- concerned with "how many <things> am I rendering?".
  -- We are using the 
  self._MaxGraphemes = 20

  self._valueChangedFunction = nil
  self._focusLostFunction = nil

  defaultValue = defaultValue or Color3.new(1,1,1)

  local frame = Instance.new("Frame")
  frame.Name = "CTIF" .. nameSuffix
  frame.Position = UDim2.new(0, 0, 1, 0)
  frame.Size = UDim2.new(1, 0, 0, 0)
  frame.BorderSizePixel = 0
  frame.AutomaticSize = Enum.AutomaticSize.Y
  GuiUtilities.syncGuiElementBackgroundColor(frame)

  local inputFrame = GuiUtilities.MakeStandardFixedHeightFrame("InputFrame")
  inputFrame.Parent = frame

  local label = GuiUtilities.MakeStandardPropertyLabel(labelText)
  label.Parent = inputFrame
  self._label = label

  -- Dumb hack to add padding to text box,
  local colorFrame = Instance.new("ImageButton")
  colorFrame.Name = "Color"
  colorFrame.AutoButtonColor = true
  colorFrame.Size = UDim2.new(0, 12, 0, 12)
  colorFrame.Position = UDim2.new(0, GuiUtilities.StandardLineElementLeftMargin, .5, 0)
  colorFrame.AnchorPoint = Vector2.new(0, .5)
  colorFrame.Parent = inputFrame
  colorFrame.BackgroundColor3 = defaultValue
  colorFrame.Image = ""
  GuiUtilities.syncGuiElementBorderColor(colorFrame)

  local textBoxWrapperFrame = Instance.new("Frame")
  textBoxWrapperFrame.Name = "Wrapper"
  textBoxWrapperFrame.Size = UDim2.new(0, kTextInputWidth - 20, 0.6, 0)
  textBoxWrapperFrame.Position = UDim2.new(0, GuiUtilities.StandardLineElementLeftMargin + 20, .5, 0)
  textBoxWrapperFrame.AnchorPoint = Vector2.new(0, .5)
  textBoxWrapperFrame.Parent = inputFrame
  GuiUtilities.syncGuiElementInputFieldColor(textBoxWrapperFrame)
  GuiUtilities.syncGuiElementBorderColor(textBoxWrapperFrame)

  local textBox = Instance.new("TextBox")
  textBox.Parent = textBoxWrapperFrame
  textBox.Name = "TextBox"
  textBox.Text = string.format("[%s, %s, %s]", tostring(round(defaultValue.R * 255)), tostring(round(defaultValue.G * 255)), tostring(round(defaultValue.B * 255)))
  textBox.Font = Enum.Font.SourceSans
  textBox.TextSize = 15
  textBox.BackgroundTransparency = 1
  textBox.TextXAlignment = Enum.TextXAlignment.Left
  textBox.Size = UDim2.new(1, -kTextBoxInternalPadding, 1, GuiUtilities.kTextVerticalFudge)
  textBox.Position = UDim2.new(0, kTextBoxInternalPadding, 0, 0)
  textBox.ClipsDescendants = true
  textBox.ClearTextOnFocus = false
  GuiUtilities.syncGuiElementFontColor(textBox)

  textBox:GetPropertyChangedSignal("Text"):Connect(function()
    -- Never let the text be too long.
    -- Careful here: we want to measure number of graphemes, not characters, 
    -- in the text, and we want to clamp on graphemes as well.
    if (utf8.len(self._textBox.Text) > self._MaxGraphemes) then 
      local count = 0
      for start, stop in utf8.graphemes(self._textBox.Text) do
        count = count + 1
        if (count > self._MaxGraphemes) then 
          -- We have gone one too far.
          -- clamp just before the beginning of this grapheme.
          self._textBox.Text = string.sub(self._textBox.Text, 1, start-1)
          break
        end
      end
      -- Don't continue with rest of function: the resetting of "Text" field
      -- above will trigger re-entry.  We don't need to trigger value
      -- changed function twice.
      return
    end

    self._value = self._textBox.Text
    if (self._valueChangedFunction) then 
      self._valueChangedFunction(self._value)
    end
  end)

  textBox.FocusLost:Connect(function (enterPressed: boolean)
    self:_GuessColorFromInputValue()
    if self._focusLostFunction then
      self._focusLostFunction(enterPressed)
    end
  end)

  local colorPickerComponent = ColorPicker.new("Picker")
  colorPickerComponent:SetValue(defaultValue)
  colorPickerComponent:GetFrame().Parent = frame
  colorPickerComponent:GetFrame().Position = UDim2.new(0, 43, 0, 30)
  colorPickerComponent:GetFrame().Visible = false
  colorPickerComponent._buttonConfirm:GetFrame().Visible = false
  colorPickerComponent._buttonCancel:GetButton().Text = "Close"
  colorPickerComponent._colorPreviewBox.Visible = false
  colorPickerComponent._colorCodeBoxRGB.Position = UDim2.new(0, 26, 0.5, 0)
  colorPickerComponent._colorCodeBoxHex.Position = UDim2.new(0, 92, 0.5, 0)

  colorPickerComponent:SetCancelFunction(function ()
    colorPickerComponent:GetFrame().Visible = false
  end)

  colorPickerComponent:SetValueChangedFunction(function (newValue: Color3)
    self._colorValue = newValue
    self:_UpdateColorFrame()
    self:_UpdateInputValue()
  end)

  colorFrame.MouseButton1Click:Connect(function ()
    if not self._colorPickerEnabled then return end
    colorPickerComponent:GetFrame().Visible = not colorPickerComponent:GetFrame().Visible
  end)

  self._frame = frame
  self._textBox = textBox
  self._colorFrame = colorFrame
  self._value = self._textBox.Text
  self._colorValue = defaultValue
  self._colorPickerComponent = colorPickerComponent
  self._colorPickerFrame = colorPickerComponent:GetFrame()
  self._colorPickerEnabled = true

  return self
end

function LabeledColorInputPickerClass:_UpdateColorFrame()
  self._colorFrame.BackgroundColor3 = self._colorValue
end

function LabeledColorInputPickerClass:_UpdateInputValue()
  self._value = if self._colorPickerEnabled then
    `[{self._colorPickerComponent:GetRGBCode()}]`
  else
    string.format(
      "[%s, %s, %s]",
      tostring(round(self._colorValue.R * 255)),
      tostring(round(self._colorValue.G * 255)),
      tostring(round(self._colorValue.B * 255))
    )
  self._textBox.Text = self._value
end

function LabeledColorInputPickerClass:_GuessColorFromInputValue()
  --- Attempts to parse a color value from the text input.
  --- Supports two formats: `R, G, B` (e.g., "255, 128, 0") and hex code (e.g., "#FFA500").
  --- If a valid color is found, it updates the current color value accordingly.
  local text = self._textBox.Text

  -- Try matching RGB format first
  local R, G, B = string.match(text, "(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  R = tonumber(R)
  G = tonumber(G)
  B = tonumber(B)
  if R and G and B then
    self:SetColorValue(Color3.fromRGB(
      math.clamp(R, 0, 255),
      math.clamp(G, 0, 255),
      math.clamp(B, 0, 255)
    ))
    return
  end

  -- Try matching HEX format like #2e2e2e or #ABCDEF
  local hex = string.match(text, "#(%x%x%x%x%x%x)")
  if hex then
    local r = tonumber(string.sub(hex, 1, 2), 16)
    local g = tonumber(string.sub(hex, 3, 4), 16)
    local b = tonumber(string.sub(hex, 5, 6), 16)
    if r and g and b then
      self:SetColorValue(Color3.fromRGB(r, g, b))
    end
  end
end

--- Sets the function to be called when the input value changes.
--- @param vcf function -- The function to call when the value changes.
function LabeledColorInputPickerClass:SetValueChangedFunction(vcf)
  self._valueChangedFunction = vcf
end

--- Sets the function to be called when the input loses focus.
--- @param flf function -- A function with signature (enterPressed: boolean) -> ().
function LabeledColorInputPickerClass:SetFocusLostFunction(flf: (enterPressed: boolean) -> ())
  self._focusLostFunction = flf
end

--- Returns the main frame of the labeled color input component.
--- @return Frame -- The UI frame for the component.
function LabeledColorInputPickerClass:GetFrame()
  return self._frame
end

--- Returns the current text value from the input field.
--- @return string -- The string entered in the input box.
function LabeledColorInputPickerClass:GetValue(): string
  return self._textBox.Text
end

--- Returns the current color value.
--- @return Color3 -- The selected color value.
function LabeledColorInputPickerClass:GetColorValue(): Color3
  return self._value
end

--- Returns the maximum number of graphemes allowed in the input field.
--- @return number -- The maximum graphemes setting.
function LabeledColorInputPickerClass:GetMaxGraphemes()
  return self._MaxGraphemes
end

--- Sets the maximum number of graphemes allowed in the input field.
--- @param newValue number -- The maximum number of graphemes.
function LabeledColorInputPickerClass:SetMaxGraphemes(newValue)
  self._MaxGraphemes = newValue
end

--- Sets the text value of the input field.
--- @param newValue string -- The new value to assign to the input.
function LabeledColorInputPickerClass:SetValue(newValue)
  if self._value ~= newValue then
    self._textBox.Text = newValue
  end
end

--- Sets the color value for the color input and updates the display.
--- @param newValue Color3 -- The new color to assign.
function LabeledColorInputPickerClass:SetColorValue(newValue: Color3)
  assert(typeof(newValue) == "Color3", "First parameter must be a Color3. Received " .. typeof(newValue))
  self._colorValue = newValue
  self:_UpdateColorFrame()
  self:_UpdateInputValue()
  if self._colorPickerEnabled then
    self._colorPickerComponent:SetValue(newValue)
  end
end

--- Enables or disables the color picker UI.
--- If disabled, the user can only manually input a RGB or a Hex color value.
---
--- If enabled, the user can also open a color picker UI to choose a color.
--- @param state boolean -- Whether to enable (true) or disable (false) the color picker.
function LabeledColorInputPickerClass:SetPickerEnabled(state: boolean)
  self._colorPickerEnabled = state
  if not state then
    self._colorPickerFrame.Visible = false
  end
end

--- Returns whether the color picker is currently enabled.
--- @return boolean -- True if the color picker is enabled, false otherwise.
function LabeledColorInputPickerClass:GetPickerEnabled(state: boolean)
  return self._colorPickerEnabled
end

return LabeledColorInputPickerClass