----------------------------------------
--
-- LabeledRadioButton.lua
--
-- Creates a frame containing a label and a radio button.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")
LabeledCheckbox = require("./LabeledCheckbox")

local kDefaultImage = "rbxasset://textures/RoactStudioWidgets/button_radiobutton_default.png"
local kEnabledImageLight = "rbxasset://textures/RoactStudioWidgets/button_radiobutton_chosen.png"
local kEnabledImageDark = kEnabledImageLight
local kRadioFrameImage = kDefaultImage

LabeledRadioButtonClass = {}
LabeledRadioButtonClass.__index = LabeledRadioButtonClass
setmetatable(LabeledRadioButtonClass, LabeledCheckbox)

--- LabeledRadioButtonClass constructor.
--- @param nameSuffix string -- Suffix to append to the name of the UI elements.
--- @param labelText string -- The label displayed next to the radio button.
--- @return LabeledRadioButtonClass -- A new instance of the labeled radio button class.
function LabeledRadioButtonClass.new(nameSuffix: string, labelText: string)
  local newButton = LabeledCheckbox.new(nameSuffix, labelText, false)
  setmetatable(newButton, LabeledRadioButtonClass)

  newButton:GetFrame().Name = "RBF" .. nameSuffix
  newButton:UseSmallSize()
  newButton._checkImage.Position = UDim2.new(0.5, 0, 0.5, 0)
  newButton._checkImage.Image = ""
  newButton._button.Image = kRadioFrameImage

  return newButton
end

function LabeledRadioButtonClass:_MaybeToggleState()
  -- A radio can never be toggled off. 
  -- Only turns off because another one turns on.
  if (not self._disabled and not self._value) then 
    self:SetValue(not self._value)
  end
end

function LabeledRadioButtonClass:_UpdateAppearance()
  if self:GetValue() then
    self._checkImage.Image = if GuiUtilities.GetThemeName() == "Light" then kEnabledImageLight else kEnabledImageDark
    self._checkImage.ImageColor3 = if GuiUtilities.GetThemeName() == "Light" then Color3.fromRGB(219, 219, 219) else Color3.new(1, 1, 1)
  else
    self._checkImage.Image = ""
    self._button.ImageColor3 = Color3.fromRGB(180, 180, 180)
  end
end

return LabeledRadioButtonClass