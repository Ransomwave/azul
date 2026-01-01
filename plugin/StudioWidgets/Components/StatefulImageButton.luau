----------------------------------------
--
-- StatefulImageButton.lua
--
-- Image button.
-- Has custom image for when "selected"
-- Uses shading to indicate hover and click states.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

StatefulImageButtonClass = {}
StatefulImageButtonClass.__index = StatefulImageButtonClass

--- StatefulImageButtonClass constructor.
--- @param buttonName string -- The name of the button instance.
--- @param imageAsset string -- The asset ID or path for the button's image.
--- @param buttonSize UDim2 -- The size of the button.
--- @return StatefulImageButtonClass -- A new instance of the StatefulImageButtonClass.
function StatefulImageButtonClass.new(buttonName: string, imageAsset: string, buttonSize: UDim2)
  local self = {}
  setmetatable(self, StatefulImageButtonClass)

  self._clickedFunction = nil

  local button = Instance.new("ImageButton")
  --button.Parent = parent
  button.Image = imageAsset
  button.BackgroundTransparency = 1
  button.BorderSizePixel = 0
  button.Size = buttonSize
  button.Name = buttonName

  self._button = button

  self._hovered = false
  self._clicked = false
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
  
  self:_UpdateButtonVisual()

  return self
end

-- Backwards compatibility (should be removed in the future)
StatefulImageButtonClass.setSelected = StatefulImageButtonClass.SetSelected
StatefulImageButtonClass.getSelected = StatefulImageButtonClass.GetSelected
StatefulImageButtonClass.getButton = StatefulImageButtonClass.GetButton

function StatefulImageButtonClass:_UpdateButtonVisual()
  if (self._selected) then 
    self._button.ImageTransparency = 0
    self._button.ImageColor3 = Color3.new(1,1,1) 
  else 
    self._button.ImageTransparency = 0.5
    self._button.ImageColor3 = Color3.new(.5,.5,.5)
  end

  if (self._clicked) then 
    self._button.BackgroundTransparency = 0.8
  elseif (self._hovered) then 
    self._button.BackgroundTransparency = 0.9
  else
    self._button.BackgroundTransparency = 1
  end
end

--- Sets the selection state of the button.
--- @param selected boolean -- Whether the button should appear selected.
function StatefulImageButtonClass:SetSelected(selected)
  self._selected = selected
  self:_updateButtonVisual()
end

--- Gets the current selection state of the button.
--- @return boolean -- True if the button is selected, false otherwise.
function StatefulImageButtonClass:GetSelected()
  return self._selected
end

--- Returns the underlying ImageButton instance.
--- @return ImageButton -- The ImageButton instance.
function StatefulImageButtonClass:GetButton()
  return self._button
end

--- Sets the function to be called when the button is clicked.
--- @param cf (inputObject: InputObject, timesPressed: number) -> () -- A callback function or nil to remove the function.
function StatefulImageButtonClass:SetClickedFunction(cf: (inputObject: InputObject, timesPressed: number) -> () | nil)
  self._clickedFunction = cf
end

return StatefulImageButtonClass