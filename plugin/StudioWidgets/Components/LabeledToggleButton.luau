----------------------------------------
--
-- LabeledToggleButtonClass.lua
--
-- Creates a frame containing a label and a toggle button.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")
LabeledCheckbox = require("./LabeledCheckbox")

local kToggleOffDark = "rbxasset://textures/RoactStudioWidgets/toggle_off_dark.png"
local kToggleOnDark = "rbxasset://textures/RoactStudioWidgets/toggle_on_dark.png"

local kToggleOffLight = "rbxasset://textures/RoactStudioWidgets/toggle_off_light.png"
local kToggleOnLight = "rbxasset://textures/RoactStudioWidgets/toggle_on_light.png"

local kToggleOffDisabledDark = "rbxasset://textures/RoactStudioWidgets/toggle_disable_dark.png"
local kToggleOnDisabledDark = "rbxasset://textures/RoactStudioWidgets/toggle_on_disable_dark.png"

local kToggleOffDisabledLight = "rbxasset://textures/RoactStudioWidgets/toggle_disable_light.png"
local kToggleOnDisabledLight = "rbxasset://textures/RoactStudioWidgets/toggle_on_disable_light.png"

local kFrameSizeX = 28
local kFrameSizeY = 16

LabeledToggleButtonClass = {}
LabeledToggleButtonClass.__index = LabeledToggleButtonClass
setmetatable(LabeledToggleButtonClass, LabeledCheckbox)

--- LabeledToggleButtonClass constructor.
--- @param nameSuffix string -- Suffix to append to the name of the UI elements.
--- @param labelText string -- The label displayed next to the toggle button.
--- @return LabeledToggleButtonClass -- A new instance of the labeled toggle button class.
function LabeledToggleButtonClass.new(nameSuffix: string, labelText: string)
  local newButton = LabeledCheckbox.new(nameSuffix, labelText, false)
  setmetatable(newButton, LabeledToggleButtonClass)

  newButton:GetFrame().Name = "TBF" .. nameSuffix
  newButton._button.Size = UDim2.new(0, kFrameSizeX, 0, kFrameSizeY)
  newButton._button.Image = ""
  newButton._button.ImageColor3 = Color3.new(1,1,1)
  newButton._button.BackgroundTransparency = 1
  newButton._checkImage.ImageColor3 = Color3.new(1,1,1)

  newButton:_UpdateAppearance()

  return newButton
end

function LabeledToggleButtonClass:_MaybeToggleState()
  if (not self._disabled) then 
    self:SetValue(not self._value)
  end
end

function LabeledToggleButtonClass:_UpdateAppearance()
  local themeName = GuiUtilities:GetThemeName()
  if self:GetValue() then
    if self:GetDisabled() then
      self._checkImage.Image = if themeName == "Light" then kToggleOnDisabledLight else kToggleOnDisabledDark
    else
      self._checkImage.Image = if themeName == "Light" then kToggleOnLight else kToggleOnDark
    end
  else
    if self:GetDisabled() then
      self._checkImage.Image = if themeName == "Light" then kToggleOffDisabledLight else kToggleOffDisabledDark
    else
      self._checkImage.Image = if themeName == "Light" then kToggleOffLight else kToggleOffDark
    end
  end
end

return LabeledToggleButtonClass