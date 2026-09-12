---@meta

--- Auto-generated from UI/Button

---@class Button : BorderImage
---@overload fun(): Button
---@field pressedOffset IntVector2
---@field disabledOffset IntVector2
---@field pressedChildOffset IntVector2
---@field repeatDelay number
---@field repeatRate number
---@field pressed boolean
---@field text string
---@field showText boolean
---@field textElement Text
Button = {}

---@return Button
function Button.new() end

---@param offset IntVector2
---@return nil
function Button:SetPressedOffset(offset) end

---@param x integer
---@param y integer
---@return nil
function Button:SetPressedOffset(x, y) end

---@param offset IntVector2
---@return nil
function Button:SetDisabledOffset(offset) end

---@param x integer
---@param y integer
---@return nil
function Button:SetDisabledOffset(x, y) end

---@param offset IntVector2
---@return nil
function Button:SetPressedChildOffset(offset) end

---@param x integer
---@param y integer
---@return nil
function Button:SetPressedChildOffset(x, y) end

---@param delay number
---@param rate number
---@return nil
function Button:SetRepeat(delay, rate) end

---@param delay number
---@return nil
function Button:SetRepeatDelay(delay) end

---@param rate number
---@return nil
function Button:SetRepeatRate(rate) end

---@param text string
---@return nil
function Button:SetText(text) end

---@return string
function Button:GetText() end

---@return Text
function Button:GetTextElement() end

---@param enable boolean
---@return nil
function Button:SetShowText(enable) end

---@return boolean
function Button:GetShowText() end

---@return IntVector2
function Button:GetPressedOffset() end

---@return IntVector2
function Button:GetDisabledOffset() end

---@return IntVector2
function Button:GetPressedChildOffset() end

---@return number
function Button:GetRepeatDelay() end

---@return number
function Button:GetRepeatRate() end

---@return boolean
function Button:IsPressed() end

