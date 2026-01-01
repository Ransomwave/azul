----------------------------------------
--
-- LabeledTextInput.lua
--
-- Creates a frame containing a label and a text input control.
--
----------------------------------------
GuiUtilities = require("../GuiUtilities")

local kTextInputWidth = 100
local kTextBoxInternalPadding = 4
local kReadOnlyTransparency = 0.55

LabeledTextInputClass = {}
LabeledTextInputClass.__index = LabeledTextInputClass

--- LabeledTextInputClass constructor.
--- @param nameSuffix string -- The name suffix of the text input.
--- @param labelText string -- The text of the label.
--- @param defaultValue string? -- The default value of the text input.
--- @param readonly boolean? -- Whether or not it is read only.
--- @return LabeledTextInputClass The text input class object.
function LabeledTextInputClass.new(nameSuffix: string, labelText: string, defaultValue: string?, readonly: boolean?)
	local self = {}
	setmetatable(self, LabeledTextInputClass)

	-- Note: we are using "graphemes" instead of characters.
	-- In modern text-manipulation-fu, what with internationalization,
	-- emojis, etc, it's not enough to count characters, particularly when
	-- concerned with "how many <things> am I rendering?".
	-- We are using the
	self._MaxGraphemes = 50

	self._valueChangedFunction = nil

	defaultValue = defaultValue or ""

	local frame = GuiUtilities.MakeStandardFixedHeightFrame("TextInput " .. nameSuffix)
	self._frame = frame

	local label = GuiUtilities.MakeStandardPropertyLabel(labelText)
	label.Parent = frame
	self._label = label

	self._value = defaultValue

	-- Dumb hack to add padding to text box,
	local textBoxWrapperFrame = Instance.new("Frame")
	textBoxWrapperFrame.Name = "Wrapper"
	textBoxWrapperFrame.Size = UDim2.new(0, kTextInputWidth, 0.6, 0)
	textBoxWrapperFrame.Position = UDim2.new(0, GuiUtilities.StandardLineElementLeftMargin, 0.5, 0)
	textBoxWrapperFrame.AnchorPoint = Vector2.new(0, 0.5)
	textBoxWrapperFrame.Parent = frame
	GuiUtilities.syncGuiElementInputFieldColor(textBoxWrapperFrame)
	GuiUtilities.syncGuiElementBorderColor(textBoxWrapperFrame)

	local textBox = Instance.new("TextBox")
	textBox.Parent = textBoxWrapperFrame
	textBox.Name = "TextBox"
	textBox.Text = defaultValue
	textBox.PlaceholderText = defaultValue
	textBox.Font = Enum.Font.SourceSans
	textBox.TextSize = 15
	textBox.BorderSizePixel = 0
	textBox.BackgroundTransparency = 1
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.Size = UDim2.new(1, -kTextBoxInternalPadding, 1, GuiUtilities.kTextVerticalFudge)
	textBox.Position = UDim2.new(0, kTextBoxInternalPadding, 0, 0)
	textBox.ClipsDescendants = true
	-- textBox.ClearTextOnFocus = true
	textBox.ClearTextOnFocus = false -- Changed to false to prevent accidental data loss.
	textBox.TextEditable = true

	GuiUtilities.syncGuiElementBackgroundColor(textBox)

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		-- Never let the text be too long.
		-- Careful here: we want to measure number of graphemes, not characters,
		-- in the text, and we want to clamp on graphemes as well.
		if utf8.len(self._textBox.Text) > self._MaxGraphemes then
			local count = 0
			for start, stop in utf8.graphemes(self._textBox.Text) do
				count = count + 1
				if count > self._MaxGraphemes then
					-- We have gone one too far.
					-- clamp just before the beginning of this grapheme.
					self._textBox.Text = string.sub(self._textBox.Text, 1, start - 1)
					break
				end
			end
			-- Don't continue with rest of function: the resetting of "Text" field
			-- above will trigger re-entry.  We don't need to trigger value
			-- changed function twice.
			return
		end

		self._value = self._textBox.Text
		if self._valueChangedFunction then
			self._valueChangedFunction(self._value)
		end
	end)

	self._textBox = textBox
	self._textBoxThemeConnection = nil :: RBXScriptConnection?
	self._textBoxThemeFontConnection = nil :: RBXScriptConnection?
	self:SetReadOnly(readonly)

	return self
end

--- Sets the function to be called when the value changes.
--- @param vcf () -> () -- The function to call when the value changes.
function LabeledTextInputClass:SetValueChangedFunction(vcf: (newValue: string) -> ())
	self._valueChangedFunction = vcf
end

--- Returns the UI frame associated with this input.
--- @return Frame -- The frame object.
function LabeledTextInputClass:GetFrame(): Frame
	return self._frame
end

--- Gets the text box itself.
--- @return TextBox -- The text box.
function LabeledTextInputClass:GetTextBox(): TextBox
	return self._textBox
end

--- Returns the maximum number of graphemes allowed.
--- @return number -- The maximum grapheme count.
function LabeledTextInputClass:GetMaxGraphemes(): number
	return self._MaxGraphemes
end

--- Sets the maximum number of graphemes allowed.
--- @param newValue number -- The new maximum grapheme count.
function LabeledTextInputClass:SetMaxGraphemes(newValue)
	self._MaxGraphemes = newValue
end

--- Returns the current value of the input.
--- @return string -- The current value.
function LabeledTextInputClass:GetValue(): string
	return self._value
end

--- Sets this input text value.
--- @param newValue string -- The value to set.
function LabeledTextInputClass:SetValue(newValue: string)
	if self._value ~= newValue then
		self._textBox.Text = newValue
	end
end

--- Gets this input text editable state.
--- @return boolean -- This input text editable state.
function LabeledTextInputClass:GetTextEditable(state: boolean)
	return self._textBox.TextEditable
end

--- Sets this input text editable state.
---
--- If not editable the user can't edit the contents of this input text.
--- @param state boolean -- Whether or not to set it as editable.
function LabeledTextInputClass:SetTextEditable(state: boolean)
	self._textBox.TextEditable = state
end

--- Sets this input text clear text on focus state.
---
--- If true the text inside this input text are cleared once the user focus it.
--- @param state boolean -- Whether or not to set it to clear text on focus.
function LabeledTextInputClass:SetClearTextOnFocusEnabled(state: boolean)
	self._textBox.ClearTextOnFocus = state
end

--- Sets the function that runs when focus is lost.
--- @param funct (enterPressed: boolean, inputThatCausedFocusLoss: InputObject) -> () -- The function to run.
function LabeledTextInputClass:SetFocusLostFunction(funct: (
	enterPressed: boolean,
	inputThatCausedFocusLoss: InputObject
	) -> ())
	self._textBox.FocusLost:Connect(funct)
end

--- Gets this input text read-only state.
--- @return boolean -- This input text read-only state.
function LabeledTextInputClass:GetReadOnly(): boolean
	return self._readOnly
end

--- Sets this input text read-only state.
---
--- Read-only text inputs are not editable and have a greyed out appearance.
--- @param state boolean -- Whether or not to set it as read-only.
function LabeledTextInputClass:SetReadOnly(state: boolean)
	self._readOnly = state
	if self._textBoxThemeConnection then
		self._textBoxThemeConnection:Disconnect()
	end
	if self._textBoxThemeFontConnection then
		self._textBoxThemeFontConnection:Disconnect()
	end
	if self._readOnly then
		self._textBox.BackgroundTransparency = kReadOnlyTransparency
		self._textBox.TextEditable = false
		self._textBox.ClearTextOnFocus = false
		self._textBoxThemeConnection = GuiUtilities.syncGuiElementColorCustom(
			self._textBox,
			"TextColor3",
			Enum.StudioStyleGuideColor.MainText,
			Enum.StudioStyleGuideModifier.Disabled
		)
		self._textBoxThemeFontConnection = GuiUtilities.syncGuiElementColorCustom(
			self._label,
			"TextColor3",
			Enum.StudioStyleGuideColor.MainText,
			Enum.StudioStyleGuideModifier.Disabled
		)
	else
		self._textBox.BackgroundTransparency = 1
		self._textBox.TextEditable = true
		self._textBoxThemeConnection =
			GuiUtilities.syncGuiElementColorCustom(self._textBox, "TextColor3", Enum.StudioStyleGuideColor.MainText)
		self._textBoxThemeFontConnection =
			GuiUtilities.syncGuiElementColorCustom(self._label, "TextColor3", Enum.StudioStyleGuideColor.MainText)
	end
end

return LabeledTextInputClass