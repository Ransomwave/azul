----------------------------------------
--
-- VerticalSpacerClass.lua
--
-- Creates an empty space of a fixed height
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local VerticalSpacerClass = {}
VerticalSpacerClass.__index = VerticalSpacerClass

--- VerticalSpacerClass constructor.
--- @param nameSuffix string -- A unique suffix to append to the spacer's name.
--- @param height number? -- Optional height of the spacer in pixels. Defaults to a preset value if not provided.
--- @return VerticalSpacerClass -- A new instance of the vertical spacer component.
function VerticalSpacerClass.new(nameSuffix: string, height: number?)
  local self = setmetatable({}, VerticalSpacerClass)

  local frame = GuiUtilities.MakeStandardFixedHeightFrame("VSPF " .. nameSuffix)
  frame.BackgroundTransparency = 1
  if height then frame.Size = UDim2.new(1, 0, 0, height) end
  
  self._frame = frame
  
  return self
end

--- Returns the UI frame representing the vertical spacer.
--- @return Frame -- The frame instance used for layout spacing.
function VerticalSpacerClass:GetFrame(): Frame
  return self._frame
end

return VerticalSpacerClass