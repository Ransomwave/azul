----------------------------------------
--
-- LabeledNumberInput.lua
--
-- Creates a frame containing a label and a number input control.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local kNumberInputWidth = 89
local kArrowButtonWidth = 10
local kTextBoxInternalPadding = 4
local kReadOnlyTransparency = 0.55

LabeledNumberInputClass = {}
LabeledNumberInputClass.__index = LabeledNumberInputClass

--- LabeledNumberInputClass constructor.
--- @param nameSuffix string -- The name suffix of the number input.
--- @param labelText string -- The text of the label.
--- @param stepIncrement number? -- The increment value when pressing the arrow up or down.
--- @param defaultValue number? -- The default value of the number input.
--- @param readonly boolean? -- Whether or not it is read only.
--- @return LabeledNumberInputClass The number input class object.
function LabeledNumberInputClass.new(nameSuffix: string, labelText: string, stepIncrement: number?, defaultValue: number?, readonly: boolean?)
  local self = {}
  setmetatable(self, LabeledNumberInputClass)

  -- Note: we are using "graphemes" instead of characters.
  -- In modern text-manipulation-fu, what with internationalization, 
  -- emojis, etc, it's not enough to count characters, particularly when 
  -- concerned with "how many <things> am I rendering?".
  -- We are using the 
  self._MaxGraphemes = 10
  
  self._valueChangedFunction = nil

  defaultValue = defaultValue or 0
  stepIncrement = stepIncrement or 1

  local frame = GuiUtilities.MakeStandardFixedHeightFrame('NumberInput ' .. nameSuffix)
  self._frame = frame

  local label = GuiUtilities.MakeStandardPropertyLabel(labelText)
  label.Parent = frame
  self._label = label

  self._value = defaultValue

  -- Dumb hack to add padding to text box,
  local textBoxWrapperFrame = Instance.new("Frame")
  textBoxWrapperFrame.Name = "Wrapper"
  textBoxWrapperFrame.Size = UDim2.new(0, kNumberInputWidth, 0.6, 0)
  textBoxWrapperFrame.Position = UDim2.new(0, GuiUtilities.StandardLineElementLeftMargin, .5, 0)
  textBoxWrapperFrame.AnchorPoint = Vector2.new(0, .5)
  textBoxWrapperFrame.Parent = frame
  GuiUtilities.syncGuiElementInputFieldColor(textBoxWrapperFrame)
  GuiUtilities.syncGuiElementBorderColor(textBoxWrapperFrame)

  local textBox = Instance.new("TextBox")
  textBox.Parent = textBoxWrapperFrame
  textBox.Name = "TextBox"
  textBox.Text = defaultValue
  textBox.Font = Enum.Font.SourceSans
  textBox.TextSize = 15
  textBox.BorderSizePixel = 0
  textBox.BackgroundTransparency = 1
  textBox.TextXAlignment = Enum.TextXAlignment.Left
  textBox.Size = UDim2.new(1, -kTextBoxInternalPadding, 1, GuiUtilities.kTextVerticalFudge)
  textBox.Position = UDim2.new(0, kTextBoxInternalPadding, 0, 0)
  textBox.ClipsDescendants = true
  textBox.ClearTextOnFocus = false
  textBox.TextEditable = true
  GuiUtilities.syncGuiElementBackgroundColor(textBox)
  
  local buttonUp = Instance.new("ImageButton")
  buttonUp.Name = "ArrowUp"
  buttonUp.Parent = textBoxWrapperFrame
  buttonUp.AutoButtonColor = false
  buttonUp.BorderSizePixel = 0
  buttonUp.Image = "rbxasset:///textures/WindControl/ArrowUp.png"
  buttonUp.Position = UDim2.new(1, 1, 0, 0)
  buttonUp.Size = UDim2.new(0, kArrowButtonWidth, 0.5, 0)
  GuiUtilities.syncGuiElementInputFieldColor(buttonUp)
  
  local buttonDown = Instance.new("ImageButton")
  buttonDown.Name = "ArrowDown"
  buttonDown.Parent = textBoxWrapperFrame
  buttonDown.AnchorPoint = Vector2.new(0, 1)
  buttonDown.AutoButtonColor = false
  buttonDown.BorderSizePixel = 0
  buttonDown.Image = "rbxasset:///textures/WindControl/ArrowDown.png"
  buttonDown.Position = UDim2.new(1, 1, 1, 0)
  buttonDown.Size = UDim2.new(0, kArrowButtonWidth, 0.5, 0)
  GuiUtilities.syncGuiElementInputFieldColor(buttonDown)
  
  buttonUp.MouseEnter:Connect(function ()
    if self._readOnly then return end
    buttonUp.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Hover)
  end)
  
  buttonUp.MouseLeave:Connect(function ()
    if self._readOnly then return end
    buttonUp.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.InputFieldBackground)
  end)
  
  buttonDown.MouseEnter:Connect(function ()
    if self._readOnly then return end
    buttonDown.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Hover)
  end)

  buttonDown.MouseLeave:Connect(function ()
    if self._readOnly then return end
    buttonDown.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.InputFieldBackground)
  end)
  
  buttonUp.Activated:Connect(function ()
    if self._readOnly then return end
    local number = tonumber(self._textBox.Text)
    number += stepIncrement
    self._textBox.Text = tostring(self:_RoundToStep(number))
  end)
  
  buttonDown.Activated:Connect(function ()
    if self._readOnly then return end
    local number = tonumber(self._textBox.Text)
    number -= stepIncrement
    self._textBox.Text = tostring(self:_RoundToStep(number))
  end)

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

    -- filter the input text below to ensure it's a valid integer or float
    local lastChar = string.sub(self._textBox.Text, -1, -1)

    if lastChar:match("%d") then
      -- do nothing
    elseif lastChar:match("%a") then
      -- In a number input letters are not accepted, only numbers!
      self._textBox.Text = string.sub(self._textBox.Text, 1, #self._textBox.Text - 1)
    elseif lastChar == "-" then
      -- Only accept '-' if it's at the very start and hasn't been used before
      if #self._textBox.Text > 1 or self._textBox.Text:find("-", 2, true) then
        self._textBox.Text = string.sub(self._textBox.Text, 1, #self._textBox.Text - 1)
      end
    elseif lastChar ~= "." then
      -- We don't accept any symbols except dot
      self._textBox.Text = string.sub(self._textBox.Text, 1, #self._textBox.Text - 1)
    end

    if self._textBox.Text:match("%..*%.") then
      -- We don't accept multiple dots
      self._textBox.Text = string.sub(self._textBox.Text, 1, #self._textBox.Text - 1)
    end

    if self._textBox.Text:match("%.(%d%d%d%d+)") then
      -- We don't accept more than 3 decimals
      self._textBox.Text = string.sub(self._textBox.Text, 1, #self._textBox.Text - 1)
    end

    self._value = tonumber(self._textBox.Text)
    if (self._valueChangedFunction) then 
      self._valueChangedFunction(self._value)
    end
  end)
  
  self._textBoxWrapperFrame = textBoxWrapperFrame
  self._textBox = textBox
  self._textBoxThemeConnection = nil :: RBXScriptConnection?
  self._textBoxThemeFontConnection = nil :: RBXScriptConnection?
  self._stepIncrement = stepIncrement
  self._stepDecimalPlaces = self:_CountDecimalPlaces(stepIncrement)
  self._buttonArrowUp = buttonUp
  self._buttonArrowDown = buttonDown
  self:SetReadOnly(readonly)

  return self
end

function LabeledNumberInputClass:_RoundToDecimals(num: number, decimals: number)
  -- rounds the decimals of a number to a maximum of decimals specified by the parameter
  return tonumber(string.format("%." .. decimals .. "f", num))
end

function LabeledNumberInputClass:_RoundToStep(value: number)
  -- rounds the value to the nearest step based on the stepIncrement variable
  -- tries to avoid floating point imprecision (like 0.1 + 0.1 = 1.999)
  local rounded = tonumber(string.format("%." .. self._stepDecimalPlaces .. "f", value))
  return rounded
end

function LabeledNumberInputClass:_CountDecimalPlaces(num: number): number
  -- counts the decimal places of a number
  local _, decimal = tostring(num):match("^(%-?%d*)%.?(%d*)$")
  return #decimal
end

--- Sets the function to be called when the value changes.
--- @param vcf () -> () -- The function to call when the value changes.
function LabeledNumberInputClass:SetValueChangedFunction(vcf: (newValue: number) -> ())
  self._valueChangedFunction = vcf
end

--- Returns the UI frame associated with this input.
--- @return Frame -- The frame object.
function LabeledNumberInputClass:GetFrame(): Frame
  return self._frame
end

--- Gets the text box itself.
--- @return TextBox -- The text box.
function LabeledNumberInputClass:GetTextBox(): TextBox
  return self._textBox
end

--- Returns the maximum number of graphemes allowed.
--- @return number -- The maximum grapheme count.
function LabeledNumberInputClass:GetMaxGraphemes(): number
  return self._MaxGraphemes
end

--- Sets the maximum number of graphemes allowed.
--- @param newValue number -- The new maximum grapheme count.
function LabeledNumberInputClass:SetMaxGraphemes(newValue)
  self._MaxGraphemes = newValue
end

--- Returns the current value of the input.
--- @return number -- The current value.
function LabeledNumberInputClass:GetValue(): number
  return self._value
end

--- Sets this input number value.
--- @param newValue number -- The value to set.
function LabeledNumberInputClass:SetValue(newValue: number)
  if self._value ~= newValue then
    self._value = self:_RoundToDecimals(newValue, 3)
    self._textBox.Text = self._value
  end
end

--- Sets the function that runs when focus is lost.
--- @param funct (enterPressed: boolean, inputThatCausedFocusLoss: InputObject) -> () -- The function to run.
function LabeledNumberInputClass:SetFocusLostFunction(funct: (enterPressed: boolean, inputThatCausedFocusLoss: InputObject) -> ())
  self._textBox.FocusLost:Connect(funct)
end

--- Gets this input text read-only state.
--- @return boolean -- This input text read-only state.
function LabeledNumberInputClass:GetReadOnly(): boolean
  return self._readOnly
end

--- Sets this input read-only state.
---
--- Read-only inputs are not editable and have a greyed out appearance.
--- @param state boolean -- Whether or not to set it as read-only.
function LabeledNumberInputClass:SetReadOnly(state: boolean)
  self._readOnly = state
  if self._textBoxThemeConnection then self._textBoxThemeConnection:Disconnect() end
  if self._textBoxThemeFontConnection then self._textBoxThemeFontConnection:Disconnect() end
  if self._readOnly then
    self._buttonArrowUp.BackgroundTransparency = kReadOnlyTransparency
    self._buttonArrowDown.BackgroundTransparency = kReadOnlyTransparency
    self._textBoxWrapperFrame.BackgroundTransparency = kReadOnlyTransparency
    self._textBox.TextEditable = false
    self._textBoxThemeConnection = GuiUtilities.syncGuiElementColorCustom(self._textBox, "TextColor3", Enum.StudioStyleGuideColor.MainText, Enum.StudioStyleGuideModifier.Disabled)
    self._textBoxThemeFontConnection = GuiUtilities.syncGuiElementColorCustom(self._label, "TextColor3", Enum.StudioStyleGuideColor.MainText, Enum.StudioStyleGuideModifier.Disabled)
  else
    self._buttonArrowUp.BackgroundTransparency = 0
    self._buttonArrowDown.BackgroundTransparency = 0
    self._textBoxWrapperFrame.BackgroundTransparency = 0
    self._textBox.TextEditable = true
    self._textBoxThemeConnection = GuiUtilities.syncGuiElementColorCustom(self._textBox, "TextColor3", Enum.StudioStyleGuideColor.MainText)
    self._textBoxThemeFontConnection = GuiUtilities.syncGuiElementColorCustom(self._label, "TextColor3", Enum.StudioStyleGuideColor.MainText)
  end
end

--- Gets the currently set step increment.
--- @return number -- This input step increment.
function LabeledNumberInputClass:GetStepIncrement(): number
  return self._stepIncrement
end

--- Sets the currently set step increment.
--- @param stepIncrement number -- The step increment.
function LabeledNumberInputClass:SetStepIncrement(stepIncrement: number)
  self._stepIncrement = stepIncrement
  self._stepDecimalPlaces = self:_CountDecimalPlaces(self._stepIncrement)
end

return LabeledNumberInputClass