----------------------------------------
--
-- DropdownMenuClass.lua
--
-- Creates dropdown-style selection menu.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local kArrowDown = "rbxasset://textures/WindControl/ArrowDown.png"
local kDropdownButtonHeight = 23

DropdownMenuClass = {}
DropdownMenuClass.__index = DropdownMenuClass

DropdownMenuClass._defaultLength = 189

--- DropdownMenuClass constructor.
--- @param nameSuffix string -- Suffix to append to the dropdown's name.
--- @param labelText string -- Label text to display alongside the dropdown.
--- @param selectionTable {{Id: string | number, Text: string}} -- Table of selection options to populate the dropdown.
--- @param placeholderText string? -- Optional text to display when no option is selected.
--- @return DropdownMenuClass -- A new instance of the dropdown menu.
function DropdownMenuClass.new(nameSuffix: string, labelText: string, selectionTable: {{Id: number | string, Text: string}}, placeholderText: string?)
  local self = {}
  setmetatable(self, DropdownMenuClass)
  self._dropdownButtonHeight = kDropdownButtonHeight
  self._expandedSize = 0
  self._placeholderText = placeholderText or "Select option"

  local section = GuiUtilities.MakeStandardFixedHeightFrame('DMSection' .. nameSuffix)
  self._sectionFrame = section

  local label = GuiUtilities.MakeStandardPropertyLabel(labelText)
  label.Parent = section

  local button = Instance.new("TextButton")
  button.AutoButtonColor = false
  button.Text = ""
  button.Size = UDim2.new(0, 100, 0.6, 0)
  button.AnchorPoint = Vector2.new(0,0.5)
  button.Position = UDim2.new(0, GuiUtilities.StandardLineElementLeftMargin, 0.5, 0)
  button.Parent = section
  GuiUtilities.syncGuiElementBackgroundColor(button)
  GuiUtilities.syncGuiElementBorderColor(button)
  GuiUtilities.syncGuiElementInputFieldColor(button)

  local buttonLabel = Instance.new("TextLabel")
  buttonLabel.Name = "ButtonLabel"
  buttonLabel.BackgroundTransparency = 1
  buttonLabel.Text = self._placeholderText
  buttonLabel.Size = UDim2.new(0, 85, 1, 0)
  buttonLabel.AnchorPoint = Vector2.new(0,0.5)
  buttonLabel.Position = UDim2.new(0, 0, 0.5, 0)
  buttonLabel.Parent = button
  GuiUtilities.syncGuiElementFontColor(buttonLabel)

  local invisFrame = Instance.new("Frame")
  invisFrame.Size = UDim2.new(1,0,0,0)
  invisFrame.AnchorPoint = Vector2.new(0.5,0)
  invisFrame.Position = UDim2.new(0.5,0,1,0)
  invisFrame.BackgroundTransparency = 1
  invisFrame.ClipsDescendants = true
  invisFrame.Parent = button

  local contentsFrame = Instance.new("ScrollingFrame")
  contentsFrame.CanvasSize = UDim2.new(1,0,0,0)
  contentsFrame.ScrollBarThickness = 0
  contentsFrame.Size = UDim2.new(1,-2,0,self._expandedSize)
  contentsFrame.AnchorPoint = Vector2.new(0.5,0)
  contentsFrame.Position = UDim2.new(0.5,0,0,0)
  contentsFrame.BorderSizePixel = 1
  contentsFrame.ZIndex = 9
  contentsFrame.Parent = invisFrame
  GuiUtilities.syncGuiElementInputFieldColor(contentsFrame)
  GuiUtilities.syncGuiElementBorderColor(contentsFrame)

  local listLayout = Instance.new("UIListLayout")
  listLayout.FillDirection = Enum.FillDirection.Vertical
  listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
  listLayout.SortOrder = Enum.SortOrder.LayoutOrder
  listLayout.Parent = contentsFrame

  local arrow = Instance.new("ImageLabel")
  arrow.Name = "Arrow"
  arrow.AnchorPoint = Vector2.new(1, 0)
  arrow.Position = UDim2.new(1, 0)
  arrow.Size = UDim2.new(0, 15, 1, 0)
  arrow.BackgroundTransparency = 1
  arrow.Image = kArrowDown
  arrow.Parent = button

  self._titleLabel = label
  self._dropButton = button
  self._buttonLabel = buttonLabel
  self._contentsFrame = contentsFrame
  self._invisFrame = invisFrame
  self._listLayout = listLayout
  self._arrow = arrow
  self._buttonArray = {}
  self._selected = ""
  self._expanded = false
  self._rightClickResetEnabled = true

  self:_SetButtonHoverEvents(button, Enum.StudioStyleGuideColor.InputFieldBackground)
  
  self._dropButton.MouseButton1Click:Connect(function()
    self:_ToggleExpand()
  end)

  self._dropButton.MouseButton2Click:Connect(function()
    if not self._rightClickResetEnabled then return end
    self:_Retract()
    self:ResetValue()
  end)

  if selectionTable then -- if the user provided a table of selections
    self:AddSelectionsFromTable(selectionTable)
  end

  GuiUtilities.BindThemeChanged(function () self:_UpdateColors() end)
  self:_UpdateColors()

  return self
end

function DropdownMenuClass:_ToggleExpand()
  -- get the widget
  local widget = self._invisFrame:FindFirstAncestorOfClass("DockWidgetPluginGui")
  if widget then
    -- now test if the bottom of the frame is below the absolute size of the widget
    local absSizeY = self._contentsFrame.AbsoluteSize.Y
    local absPosY = self._contentsFrame.AbsolutePosition.Y
    local absAdded
    if self._expanded and self._contentsFrame.AnchorPoint == Vector2.new(0.5,1) then
      absAdded = absSizeY+absPosY+absSizeY
    elseif self._contentsFrame.AnchorPoint == Vector2.new(0.5,1) then
      absAdded = absSizeY+absPosY+absSizeY
    else
      absAdded = absSizeY+absPosY
    end

    if not self._expanded then
      if absAdded >= widget.AbsoluteSize.Y then
        self._contentsFrame.AnchorPoint = Vector2.new(0.5,1)
        self._contentsFrame.Position = UDim2.new(0.5,0,1,0)
        self._invisFrame.AnchorPoint = Vector2.new(0.5,1)
        self._invisFrame.Position = UDim2.new(0.5,0,0,0)
      else
        self._contentsFrame.AnchorPoint = Vector2.new(0.5,0)
        self._contentsFrame.Position = UDim2.new(0.5,0,0,0)
        self._invisFrame.AnchorPoint = Vector2.new(0.5,0)
        self._invisFrame.Position = UDim2.new(0.5,0,1,0)
      end
    end
  end

  if self._expanded then
    self:_Retract()
    self._expanded = false
  else
    self:_Expand()
    self._expanded = true
  end
end

function DropdownMenuClass:_Retract()
  self._invisFrame:TweenSize(UDim2.new(1,2,0,0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
  self._expanded = false
end

function DropdownMenuClass:_Expand()
  self._invisFrame:TweenSize(UDim2.new(1,2,0,self._expandedSize+2), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.15, true)
  self._expanded = true
end

function DropdownMenuClass:_UpdateSize()
  local count = 0
  for _,v in pairs(self._buttonArray) do
    count += 1
  end
  if count >= 7 then
    self._canvasSize = count*self._dropdownButtonHeight
    self._expandedSize = DropdownMenuClass._defaultLength
    self._contentsFrame.CanvasSize = UDim2.new(1,-2,0,self._canvasSize)
    self._contentsFrame.Size = UDim2.new(1,-2,0,self._expandedSize)
    if self._expanded then
      self._invisFrame:TweenSize(UDim2.new(1,2,0,self._expandedSize), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.15, true)
    end
  else
    self._canvasSize = count*self._dropdownButtonHeight
    self._expandedSize = count*self._dropdownButtonHeight

    self._contentsFrame.CanvasSize = UDim2.new(1,-2,0,self._canvasSize)
    self._contentsFrame.Size = UDim2.new(1,-2,0,self._expandedSize)
    if self._expanded then
      self._invisFrame:TweenSize(UDim2.new(1,2,0,self._expandedSize), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.15, true)
    end
  end

end

function DropdownMenuClass:_UpdateColors()
  local themeName = GuiUtilities.GetThemeName()
  self._arrow.ImageColor3 = if themeName == "Light" then GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Border) else GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.TitlebarText)
end

function DropdownMenuClass:_SetButtonHoverEvents(button: GuiButton, defaultStyle: Enum.StudioStyleGuideColor)
  button.InputBegan:Connect(function(inputObject: InputObject)
    if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Hover)
  end)

  button.InputEnded:Connect(function (inputObject: InputObject)
    if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    button.BackgroundColor3 = GuiUtilities.GetThemeColor(defaultStyle)
  end)

  button.MouseButton1Down:Connect(function()
    button.BackgroundColor3 = GuiUtilities.GetThemeColor(Enum.StudioStyleGuideColor.Button, Enum.StudioStyleGuideModifier.Pressed)
  end)

  button.MouseButton1Up:Connect(function()
    button.BackgroundColor3 = GuiUtilities.GetThemeColor(defaultStyle)
  end)
end

--- Adds a single selection item to the dropdown menu.
--- @param selectionTable {Id: string | number, Text: string} -- Table containing selection data with `Text` (string) and `Id` (string or number).
function DropdownMenuClass:AddSelectionItem(selectionTable: {Id: number | string, Text: string})
  assert(type(selectionTable.Text) == "string", "Expected String for Text, got "..type(selectionTable.Text))
  assert(type(selectionTable.Id) == "string" or type(selectionTable.Id) == "number", "Expected String or Number for Id, got " .. type(selectionTable.Id))

  if self._buttonArray[selectionTable.Id] then -- if the selection already exists
    return warn("There is already a selection with identifier: "..selectionTable.Id)
  end

  local button = Instance.new("TextButton")
  button.Name = selectionTable.Text
  button.Text = selectionTable.Text
  button.BorderMode = Enum.BorderMode.Inset
  button.Size = UDim2.new(1,0,0,self._dropdownButtonHeight)
  button.BackgroundTransparency = 0
  button.AutoButtonColor = false
  button.ZIndex = 10
  button.Parent = self._contentsFrame
  GuiUtilities.syncGuiElementFontColor(button)
  GuiUtilities.syncGuiElementBorderColor(button)
  GuiUtilities.syncGuiElementBackgroundColor(button)

  local connection = button.MouseButton1Click:Connect(function()
    self:SetValue(selectionTable.Id)
    self:_Retract()
  end)

  self._buttonArray[selectionTable.Id] = {
    Id = selectionTable.Id,
    Text = selectionTable.Text,
    button = button,
    connection = connection
  }

  self:_SetButtonHoverEvents(button, Enum.StudioStyleGuideColor.MainBackground)

  -- change contentsFrame size. Remember to do this at the end next time.
  self:_UpdateSize()
  return
end

--- Removes a selection item from the dropdown menu by its identifier.
--- @param identifier string | number -- Identifier of the selection to remove.
function DropdownMenuClass:RemoveSelection(identifier)
  if self._buttonArray[identifier] then
    self._buttonArray[identifier].connection:Disconnect()
    self._buttonArray[identifier].button:Destroy()
    self._buttonArray[identifier] = nil
    self:_UpdateSize() -- resize frame
  end
end

--- Adds multiple selection items to the dropdown from a table of selection tables.
--- @param selectionTable table -- Table of selection tables to add.
function DropdownMenuClass:AddSelectionsFromTable(selectionTable)
  assert(type(selectionTable) == "table", "Expected table. Got "..type(selectionTable))

  for i,v in pairs(selectionTable) do
    if type(v) == "table" then
      self:AddSelectionItem(v)
    end
  end
end

--- Resets the dropdown selection to none and restores placeholder text.
function DropdownMenuClass:ResetValue()
  self._selected = ""
  self._buttonLabel.Text = self._placeholderText
end

--- Sets the current value of the dropdown to the option with the given identifier.
--- Triggers the value changed callback if defined.
--- @param newValue number | string -- The identifier of the option to select.
function DropdownMenuClass:SetValue(newValue: number | string)
  assert(self._buttonArray[newValue] ~= nil, "Could not find an option with the id: " .. newValue)
  self._selected = newValue
  self._buttonLabel.Text = self._buttonArray[newValue].Text
  if (self._valueChangedFunction) then 
    self._valueChangedFunction(newValue, self._buttonArray[newValue].Text)
  end
end

--- Returns the value (Id) of the selected option, or nil if nothing is selected.
--- @return number | string | nil -- Id of selected option, or nil.
function DropdownMenuClass:GetValue(): number | string | nil
  if self._selected == "" then return nil end
  return self._buttonArray[self._selected].Id
end

--- Returns the text (Text) of the selected option, or nil if nothing is selected.
--- @return string | nil -- Text of selected option, or nil.
function DropdownMenuClass:GetText(): string | nil
  if self._selected == "" then return nil end
  return self._buttonArray[self._selected].Text
end

--- Returns the frame containing the full dropdown section (title + contents).
--- @return Frame -- The section frame.
function DropdownMenuClass:GetSectionFrame()
  return self._sectionFrame
end

--- Returns the frame containing the dropdown's content (selection options).
--- @return Frame -- The contents frame.
function DropdownMenuClass:GetContentsFrame()
  return self._contentsFrame
end

--- Changes the label text displayed above the dropdown menu.
--- @param labelText string -- New label text to display.
function DropdownMenuClass:SetLabelText(labelText: string)
  assert(type(labelText) == "string", "Expected string. Got "..type(labelText))
  self._titleLabel.Text = labelText
end

--- Sets the function to call when the selected value changes.
--- @param vcFunction (newValue: number | string) -> () -- A function that takes the new value (number or string) as an argument.
function DropdownMenuClass:SetValueChangedFunction(vcFunction: (newValue: number | string, newText: string) -> ()) 
  self._valueChangedFunction = vcFunction
end

--- Sets the sort order of the dropdown menu items within a UI layout.
--- Defaults to `LayoutOrder` if not explicitly set.
--- @param layoutOrder Enum.SortOrder -- The sort order to apply (e.g., Name, LayoutOrder).
function DropdownMenuClass:SetSortOrder(layoutOrder: Enum.SortOrder)
  self._listLayout.SortOrder = layoutOrder
end

--- Enables or disables the ability to reset the dropdown selection via right-click.
--- @param state boolean -- Whether right-click reset is enabled.
function DropdownMenuClass:SetRightClickResetEnabled(state: boolean)
  self._rightClickResetEnabled = state
end

return DropdownMenuClass