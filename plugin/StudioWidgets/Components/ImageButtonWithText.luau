----------------------------------------
--
-- ImageButtonWithText.lua
--
-- An image button with text underneath.  Standardized hover, clicked, and 
-- selected states.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

ImageButtonWithTextClass = {}
ImageButtonWithTextClass.__index = ImageButtonWithTextClass

local kSelectedBaseTransparency = 0.2
local kAdditionalTransparency = 0.1

--- ImageButtonWithTextClass constructor.
--- @param name string -- The name of the button instance.
--- @param layoutOrder number -- The layout order for the button in a UI layout.
--- @param icon string -- The asset ID or path for the image icon.
--- @param text string -- The text label to display on the button.
--- @param buttonSize UDim2 -- The size of the entire button.
--- @param imageSize UDim2 -- The size of the image icon inside the button.
--- @param imagePos UDim2 -- The position of the image icon within the button.
--- @param textSize UDim2 -- The size of the text label inside the button.
--- @param textPos UDim2 -- The position of the text label within the button.
--- @return ImageButtonWithTextClass -- A new instance of ImageButtonWithTextClass.
function ImageButtonWithTextClass.new(name: string, layoutOrder: number, icon: string, text: string, buttonSize: UDim2, imageSize: UDim2, imagePos: UDim2, textSize: UDim2, textPos: UDim2)
  local self = {}
  setmetatable(self, ImageButtonWithTextClass)

  self._clickedFunction = nil

  local button = Instance.new("ImageButton")
  button.Name = name
  button.AutoButtonColor = false
  button.Size = buttonSize
  button.BorderSizePixel = 1
  -- Image-with-text button has translucent background and "selected" background color.
  -- When selected we set transluency to not-zero so we see selected color.
  button.BackgroundTransparency = 1 

  button.LayoutOrder = layoutOrder

  local buttonIcon = Instance.new("ImageLabel")
  buttonIcon.BackgroundTransparency = 1
  buttonIcon.Image = icon or ""
  buttonIcon.Size = imageSize
  buttonIcon.Position = imagePos
  buttonIcon.Parent = button

  local textLabel = Instance.new("TextLabel")
  textLabel.BackgroundTransparency = 1
  textLabel.Text = text
  textLabel.Size = textSize
  textLabel.Position = textPos
  textLabel.TextScaled = true
  textLabel.Font = Enum.Font.SourceSans
  textLabel.Parent = button

  GuiUtilities.syncGuiElementFontColor(textLabel)

  local uiTextSizeConstraint = Instance.new("UITextSizeConstraint")
  -- Spec asks for fontsize of 12 pixels, but in Roblox the text font sizes look smaller than the mock
  --Note: For this font the Roblox text size is 25.7% larger than the design spec. 
  uiTextSizeConstraint.MaxTextSize = 15                                              
  uiTextSizeConstraint.Parent = textLabel

  self._button = button
  self._clicked = false
  self._hovered = false
  self._selected = false

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

  button.Activated:Connect(function (inputObject, timesPressed)
    if self._clickedFunction then
      self._clickedFunction(inputObject, timesPressed)
    end
  end)
  
  local function updateButtonVisual()
    self:_UpdateButtonVisual()
  end
  GuiUtilities.BindThemeChanged(updateButtonVisual)

  self:_UpdateButtonVisual()

  return self
end

function ImageButtonWithTextClass:_UpdateButtonVisual()
  -- Possibilties:
  if (self._clicked) then 
    -- This covers 'clicked and selected' or 'clicked'
    self._button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, 
      Enum.StudioStyleGuideModifier.Selected)
    self._button.BorderColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Border, 
      Enum.StudioStyleGuideModifier.Selected)
    if (self._selected) then 
      self._button.BackgroundTransparency = GuiUtilities.kButtonBackgroundIntenseTransparency
    else
      self._button.BackgroundTransparency = GuiUtilities.kButtonBackgroundTransparency
    end
  elseif (self._hovered) then 
    -- This covers 'hovered and selected' or 'hovered'
    self._button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, 
      Enum.StudioStyleGuideModifier.Hover)
    self._button.BorderColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Border, 
      Enum.StudioStyleGuideModifier.Hover)
    if (self._selected) then 
      self._button.BackgroundTransparency = GuiUtilities.kButtonBackgroundIntenseTransparency
    else
      self._button.BackgroundTransparency = GuiUtilities.kButtonBackgroundTransparency
    end
  elseif (self._selected) then 
    -- This covers 'selected'
    self._button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, 
      Enum.StudioStyleGuideModifier.Selected)
    self._button.BorderColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Border, 
      Enum.StudioStyleGuideModifier.Selected)
    self._button.BackgroundTransparency = GuiUtilities.kButtonBackgroundTransparency
  else
    -- This covers 'no special state'
    self._button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button)
    self._button.BorderColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Border)
    self._button.BackgroundTransparency = 1
  end
end

--- Returns the internal ImageButton instance.
--- @return ImageButton -- The ImageButton associated with this class instance.
function ImageButtonWithTextClass:GetButton()
  return self._button
end

--- Sets the selected state of the button and updates its visual appearance.
--- @param selected boolean -- Whether the button should be marked as selected.
function ImageButtonWithTextClass:SetSelected(selected)
  self._selected = selected
  self:_UpdateButtonVisual()
end

--- Returns whether the button is currently selected.
--- @return boolean -- True if the button is selected; false otherwise.
function ImageButtonWithTextClass:GetSelected()
  return self._selected
end

--- Sets the function to be called when the button is clicked.
--- @param cf (inputObject: InputObject, timesPressed: number) -> () -- A callback function or nil to remove the function.
function ImageButtonWithTextClass:SetClickedFunction(cf: (inputObject: InputObject, timesPressed: number) -> () | nil)
  self._clickedFunction = cf
end


return ImageButtonWithTextClass
