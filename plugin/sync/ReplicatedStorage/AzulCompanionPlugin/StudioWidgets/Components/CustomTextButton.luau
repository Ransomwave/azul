----------------------------------------
--
-- CustomTextButton.lua
--
-- Creates text button with custom look & feel, hover/click effects.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

CustomTextButtonClass = {}
CustomTextButtonClass.__index = CustomTextButtonClass

--- CustomTextButtonClass constructor.
--- @param nameSuffix string -- Suffix to append to the button's name.
--- @param labelText string -- Text to display on the button.
--- @param square boolean? -- Optional flag to render the button with square corners.
--- @return CustomTextButtonClass -- A new instance of the custom text button class.
function CustomTextButtonClass.new(nameSuffix: string, labelText: string, square: boolean?)
  local self = {}
  setmetatable(self, CustomTextButtonClass)

  self._clickedFunction = nil
  
  local frame = Instance.new("Frame")
  frame.Name = "ButtonFrame  " .. nameSuffix
  frame.BackgroundTransparency = 1
  frame.BorderSizePixel = 0
  frame.Size = UDim2.new(0, 70, 0, 25 - GuiUtilities.kButtonVerticalFudge)
  
  local button = Instance.new('TextButton')
  button.Name = nameSuffix
  button.AnchorPoint = Vector2.new(0, 0.5)
  button.BackgroundTransparency = 0
  button.AutoButtonColor = false
  button.Text = labelText
  button.Font = Enum.Font.SourceSans
  button.TextSize = 15
  button.Position = UDim2.new(0, 0, 0.5, 0)
  button.Size = UDim2.new(1, 0, 1, GuiUtilities.kButtonVerticalFudge)
  button.Parent = frame
  
  local uICorner = Instance.new("UICorner")
  uICorner.CornerRadius = UDim.new(0, 5)
  uICorner.Parent = button
  
  local uiStroke = Instance.new("UIStroke")
  uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  uiStroke.Parent = button
  
  if square then
    button.BorderSizePixel = 1
    uiStroke.Enabled = false
    uICorner.CornerRadius = UDim.new(0, 0)
    uICorner.Parent = frame
  end
  
  GuiUtilities.syncGuiElementButtonColor(button)
  GuiUtilities.syncGuiElementFontColor(button)
  GuiUtilities.syncGuiElementBorderColor(button)
  GuiUtilities.syncGuiElementUIStrokeColor(uiStroke)
  
  self._frame = frame
  self._button = button

  self._clicked = false
  self._hovered = false
  self._disabled = false

  button.InputBegan:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseMovement) then
      self._hovered = true
      self:_UpdateButtonVisual()
    end
  end)

  button.InputEnded:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseMovement) then
      self._hovered = false
      self._clicked = false
      self:_UpdateButtonVisual()
    end
  end)    

  button.MouseButton1Down:Connect(function()
    self._clicked = true
    self:_UpdateButtonVisual()
  end)

  button.MouseButton1Up:Connect(function()
    self._clicked = false
    self:_UpdateButtonVisual()
  end)

  GuiUtilities.BindThemeChanged(function ()
    if self._disabled then
      task.delay(0, function ()
        self:_UpdateButtonVisual()
      end)
    end
  end)

  button.Activated:Connect(function (inputObject, timesPressed)
    if self._clickedFunction then
      self._clickedFunction(inputObject, timesPressed)
    end
  end)

  self:_UpdateButtonVisual()

  return self
end

function CustomTextButtonClass:_UpdateButtonVisual()
  if self._disabled then -- background color
    self._button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Disabled)
  elseif (self._clicked) then
    self._button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Pressed)
  elseif (self._hovered) then
    self._button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Hover)
  else
    self._button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Default)
  end
  if self._disabled then -- button text color
    self._button.TextColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.ButtonText, Enum.StudioStyleGuideModifier.Disabled)
  else
    self._button.TextColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.ButtonText, Enum.StudioStyleGuideModifier.Default)
  end
end

-- Backwards compatibility (should be removed in the future)
CustomTextButtonClass.getButton = CustomTextButtonClass.GetButton

--- Returns the internal button instance.
--- @return TextButton -- The TextButton instance used in the custom button.
function CustomTextButtonClass:GetButton()
  return self._button
end

--- Returns the outer frame containing the button.
--- @return Frame -- The Frame instance wrapping the button.
function CustomTextButtonClass:GetFrame()
  return self._frame
end

--- Returns whether the button is currently disabled.
--- @return boolean -- True if the button is disabled, false otherwise.
function CustomTextButtonClass:GetDisabled()
  return self._disabled
end

--- Sets the disabled state of the button and updates its visual appearance.
--- @param state boolean -- True to disable the button, false to enable it.
function CustomTextButtonClass:SetDisabled(state: boolean)
  self._disabled = state
  self:_UpdateButtonVisual()
end

--- Sets the size of the button's outer frame.
--- @param size UDim2 -- The desired size for the frame.
function CustomTextButtonClass:SetSize(size: UDim2)
  self._frame.Size = size + UDim2.fromOffset(0, -GuiUtilities.kButtonVerticalFudge)
end

--- Sets the function to be called when the button is clicked.
--- @param cf (inputObject: InputObject, timesPressed: number) -> () -- A callback function or nil to remove the function.
function CustomTextButtonClass:SetClickedFunction(cf: (inputObject: InputObject, timesPressed: number) -> () | nil)
  self._clickedFunction = cf
end

return CustomTextButtonClass