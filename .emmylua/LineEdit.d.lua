---@meta

--- Auto-generated from UI/LineEdit

---@class LineEdit : BorderImage
---@overload fun(): LineEdit
---@field text string
---@field cursorPosition integer
---@field cursorBlinkRate number
---@field maxLength integer
---@field echoCharacter integer
---@field cursorMovable boolean
---@field textSelectable boolean
---@field textCopyable boolean
---@field textElement Text
---@field cursor BorderImage
LineEdit = {}

---@return LineEdit
function LineEdit.new() end

---@param text string
---@return nil
function LineEdit:SetText(text) end

---@param position integer
---@return nil
function LineEdit:SetCursorPosition(position) end

---@param rate number
---@return nil
function LineEdit:SetCursorBlinkRate(rate) end

---@param length integer
---@return nil
function LineEdit:SetMaxLength(length) end

---@param c integer
---@return nil
function LineEdit:SetEchoCharacter(c) end

---@param enable boolean
---@return nil
function LineEdit:SetCursorMovable(enable) end

---@param enable boolean
---@return nil
function LineEdit:SetTextSelectable(enable) end

---@param enable boolean
---@return nil
function LineEdit:SetTextCopyable(enable) end

---@return string
function LineEdit:GetText() end

---@return integer
function LineEdit:GetCursorPosition() end

---@return number
function LineEdit:GetCursorBlinkRate() end

---@return integer
function LineEdit:GetMaxLength() end

---@return integer
function LineEdit:GetEchoCharacter() end

---@return boolean
function LineEdit:IsCursorMovable() end

---@return boolean
function LineEdit:IsTextSelectable() end

---@return boolean
function LineEdit:IsTextCopyable() end

---@return Text
function LineEdit:GetTextElement() end

---@return BorderImage
function LineEdit:GetCursor() end

