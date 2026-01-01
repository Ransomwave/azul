----------------------------------------
--
-- HorizontalLineClass.lua
--
-- Creates a horizontal line of a fixed height and color
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local kDefaultColor = Color3.new(0.5, 0.5, 0.5)

local HorizontalLineClass = {}
HorizontalLineClass.__index = HorizontalLineClass

--- HorizontalLineClass constructor.
--- @param nameSuffix string -- Suffix to append to the line's name for uniqueness.
--- @param height number? -- Optional height of the horizontal line. Defaults to a predefined value if not specified.
--- @param color Color3? -- Optional color of the horizontal line. Defaults to a standard UI color if not specified.
--- @return HorizontalLineClass -- A new instance of the horizontal line class.
function HorizontalLineClass.new(nameSuffix: string, height: number?, color: Color3?)
  local self = setmetatable({}, HorizontalLineClass)
  
  local frame = Instance.new("Frame")
  frame.Name = "HLF " .. nameSuffix
  frame.BackgroundTransparency = 0
  frame.BorderSizePixel = 0
  frame.Size = UDim2.new(1, 0, 0, height or GuiUtilities.kStandardPropertyHeight)

  frame.BackgroundColor3 = if color then color else kDefaultColor
  if not color then GuiUtilities.syncGuiElementColorCustom(frame, "BackgroundColor3", Enum.StudioStyleGuideColor.Border) end
  
  self._frame = frame
  
  return self
end

--- Returns the main frame representing the horizontal line UI element.
--- @return Frame -- The UI frame containing the horizontal line.
function HorizontalLineClass:GetFrame()
  return self._frame
end 

return HorizontalLineClass