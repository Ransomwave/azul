----------------------------------------
--
-- VerticallyScalingListFrame
--
-- Creates a frame that organizes children into a list layout.
-- Will scale dynamically as children grow.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

VerticallyScalingListFrameClass = {}
VerticallyScalingListFrameClass.__index = VerticallyScalingListFrameClass

local kBottomPadding = 10

--- VerticallyScalingListFrameClass constructor.
--- @param nameSuffix string -- Suffix to append to the name of the scroll frame components.
--- @return VerticallyScalingListFrameClass -- A new instance of the vertically scaling list frame class.
function VerticallyScalingListFrameClass.new(nameSuffix: string)
  local self = {}
  setmetatable(self, VerticallyScalingListFrameClass)

  self._resizeCallback = nil
  
  local frame = Instance.new('Frame')
  frame.Name = 'VSLFrame' .. nameSuffix
  frame.Size = UDim2.new(1, 0, 0, 0)
  frame.BackgroundTransparency = 0
  frame.BorderSizePixel = 0
  GuiUtilities.syncGuiElementBackgroundColor(frame)

  self._frame = frame
  
  local uiListLayout = Instance.new('UIListLayout')
  uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
  uiListLayout.Parent = frame
  self._uiListLayout = uiListLayout

  local function updateSizes()
    self._frame.Size = UDim2.new(1, 0, 0, uiListLayout.AbsoluteContentSize.Y)
    if (self._resizeCallback) then 
      self._resizeCallback()
    end
  end
  self._uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSizes)
  updateSizes()

  self._childCount = 0

  return self
end

--- Adds a transparent bottom padding frame to the list.
function VerticallyScalingListFrameClass:AddBottomPadding()
  local frame = Instance.new("Frame")
  frame.Name = "BottomPadding"
  frame.BackgroundTransparency = 1
  frame.Size = UDim2.new(1, 0, 0, kBottomPadding)
  frame.LayoutOrder = 1000
  frame.Parent = self._frame
end

--- Returns the internal UI frame containing all children.
--- @return Frame -- The internal frame used for layout.
function VerticallyScalingListFrameClass:GetFrame()
  return self._frame
end

--- Adds a child frame to the list with automatic layout order.
--- @param childFrame GuiObject -- The child frame to add to the list.
function VerticallyScalingListFrameClass:AddChild(childFrame: GuiObject)
  childFrame.LayoutOrder = self._childCount
  self._childCount = self._childCount + 1
  childFrame.Parent = self._frame
end

--- Sets a callback function to be called when the frame is resized.
--- @param callback function -- The function to call on resize.
function VerticallyScalingListFrameClass:SetCallbackOnResize(callback: () -> ())
  self._resizeCallback = callback
end

--- Sets the horizontal alignment of elements in the UI list layout.
--- @param alignment Enum.HorizontalAlignment -- The desired horizontal alignment.
function VerticallyScalingListFrameClass:SetHorizontalAlignment(alignment: Enum.HorizontalAlignment)
  self._uiListLayout.HorizontalAlignment = alignment
end

--- Sets the vertical alignment of elements in the UI list layout.
--- @param alignment Enum.VerticalAlignment -- The desired vertical alignment.
function VerticallyScalingListFrameClass:SetVerticalAlignment(alignment: Enum.VerticalAlignment)
  self._uiListLayout.VerticalAlignment = alignment
end

--- Sets the fill direction of the UIListLayout inside the frame.
--- @param fillDirection Enum.FillDirection -- The direction in which UI elements will be laid out (Vertical or Horizontal).
function VerticallyScalingListFrameClass:SetFillDirection(fillDirection: Enum.FillDirection)
  self._uiListLayout.FillDirection = fillDirection
end

--- Sets the padding between UI elements in the list layout.
--- @param padding UDim -- The space to apply between child elements.
function VerticallyScalingListFrameClass:SetLayoutPadding(padding: UDim)
  self._uiListLayout.Padding = padding
end

return VerticallyScalingListFrameClass