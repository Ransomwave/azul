----------------------------------------
--
-- LabeledMultiChoice.lua
--
-- Creates a frame containing a label and list of choices, of which exactly one 
-- is always selected.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")
LabeledRadioButton = require("./LabeledRadioButton")
LabeledCheckbox = require("./LabeledCheckbox")
VerticallyScalingListFrame = require("./VerticallyScalingListFrame")

local kRadioButtonsHPadding = GuiUtilities.kRadioButtonsHPadding

LabeledMultiChoiceClass = {}
LabeledMultiChoiceClass.__index = LabeledMultiChoiceClass


--- LabeledMultiChoiceClass constructor.
--- @param nameSuffix string -- Suffix to append to the name of the UI elements.
--- @param labelText string -- The label displayed next to the multi-choice selector.
--- @param choices {{Id: number | string, Text: string}} -- An array of choice entries. Each entry must include a .Id field and .Text field.
--- @param initChoiceIndex number? -- Optional index of the initially selected choice. Defaults to the first if not provided.
--- @return LabeledMultiChoiceClass -- A new instance of the labeled multi-choice selector.
function LabeledMultiChoiceClass.new(nameSuffix: string, labelText: string, choices: {{Id: number | string, Text: string}}, initChoiceIndex: number?)
  local self = {}
  setmetatable(self, LabeledMultiChoiceClass)

  self._buttonObjsByIndex = {}
  
  self._choices = choices

  if (not initChoiceIndex ) then 
    initChoiceIndex = 1
  end
  if (initChoiceIndex > #choices) then 
    initChoiceIndex = #choices
  end


  local vsl = VerticallyScalingListFrame.new("MCC_" .. nameSuffix)
  vsl:AddBottomPadding()

  local titleLabel = GuiUtilities.MakeFrameWithSubSectionLabel("Title", labelText)
  vsl:AddChild(titleLabel)

  -- Container for cells.
  local cellFrame = self:_MakeRadioButtons(choices)
  vsl:AddChild(cellFrame)

  self._vsl = vsl

  self:SetSelectedIndex(initChoiceIndex)

  return self
end

-- Small checkboxes are a different entity.
-- All the bits are smaller.
-- Fixed width instead of flood-fill.
-- Box comes first, then label.
function LabeledMultiChoiceClass:_MakeRadioButtons(choices)
  local frame = GuiUtilities.MakeFrame("RadioButtons")
  frame.BackgroundTransparency = 1

  local padding = Instance.new("UIPadding")
  padding.PaddingLeft = UDim.new(0, GuiUtilities.StandardLineLabelLeftMargin)
  padding.PaddingRight = UDim.new(0, GuiUtilities.StandardLineLabelLeftMargin)
  padding.Parent = frame
  
  -- Make a grid to put checkboxes in.
  local uiGridLayout = Instance.new("UIGridLayout")
  uiGridLayout.CellSize = LabeledCheckbox.kMinFrameSize
  uiGridLayout.CellPadding = UDim2.new(0, 
    kRadioButtonsHPadding,
    0,
    GuiUtilities.kStandardVMargin)
  uiGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
  uiGridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
  uiGridLayout.Parent = frame
  uiGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
  self._uiGridLayout = uiGridLayout

  for i, choiceData in ipairs(choices) do 
    self:_AddRadioButton(frame, i, choiceData)
  end

    -- Sync size with content size.
  GuiUtilities.AdjustHeightDynamicallyToLayout(frame, uiGridLayout)

  return frame
end

function LabeledMultiChoiceClass:_AddRadioButton(parentFrame, index, choiceData)
  local radioButtonObj = LabeledRadioButton.new(choiceData.Id, choiceData.Text)
  self._buttonObjsByIndex[index] = radioButtonObj

  radioButtonObj:SetValueChangedFunction(function(value)
    -- If we notice the button going from off to on, and it disagrees with 
    -- our current notion of selection, update selection.
    if (value and self._selectedIndex ~= index) then 
      self:SetSelectedIndex(index)
    end
  end)
  
  radioButtonObj:GetFrame().LayoutOrder = index
  radioButtonObj:GetFrame().Parent = parentFrame
end

--- Sets the selected index in the multi-choice UI and updates the button states accordingly.
--- @param selectedIndex number -- The index of the choice to be selected.
function LabeledMultiChoiceClass:SetSelectedIndex(selectedIndex) 
  self._selectedIndex = selectedIndex
  for i = 1, #self._buttonObjsByIndex do 
    self._buttonObjsByIndex[i]:SetValue(i == selectedIndex)
  end

  if (self._valueChangedFunction) then 
    self._valueChangedFunction(self._selectedIndex)
  end
end

--- Gets the currently selected index in the multi-choice UI.
--- @return number -- The index of the selected choice.
function LabeledMultiChoiceClass:GetSelectedIndex()
  return self._selectedIndex
end

--- Gets the ID value of the currently selected choice.
--- @return number | string -- The "Id" field of the selected choice.
function LabeledMultiChoiceClass:GetSelectedValue(): number | string
  return self._choices[self._selectedIndex].Id
end

--- Sets a callback function to be invoked whenever the selected value changes.
--- @param vcf (newValue: number | string) -> () -- A function that receives the new selected index as a parameter.
function LabeledMultiChoiceClass:SetValueChangedFunction(vcf: (newValue: number | string) -> ())
  self._valueChangedFunction = vcf
end

--- Retrieves the main frame containing the multi-choice UI elements.
--- @return Frame -- The UI frame of the multi-choice component.
function LabeledMultiChoiceClass:GetFrame(): Frame
  return self._vsl:GetFrame()
end

--- Sets the horizontal size of each cell (button) in the multi-choice grid layout.
--- @param cellSize number -- The desired horizontal size in pixels.
function LabeledMultiChoiceClass:SetCellHorizontalSize(cellSize: number)
  local size = self._uiGridLayout.CellSize :: UDim2
  self._uiGridLayout.CellSize = UDim2.new(size.X.Scale, cellSize, size.Y.Scale, size.Y.Offset)
end

--- Sets the vertical size of each cell (button) in the multi-choice grid layout.
--- @param cellSize number -- The desired vertical size in pixels.
function LabeledMultiChoiceClass:SetCellVerticalSize(cellSize: number)
  local size = self._uiGridLayout.CellSize :: UDim2
  self._uiGridLayout.CellSize = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale, cellSize)
end


return LabeledMultiChoiceClass