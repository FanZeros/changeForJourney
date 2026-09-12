---@meta

--- Auto-generated from UI/CheckBox

---@class CheckBox : BorderImage
---@overload fun(): CheckBox
---@field checked boolean
---@field checkedOffset IntVector2
CheckBox = {}

---@return CheckBox
function CheckBox.new() end

---@param enable boolean
---@return nil
function CheckBox:SetChecked(enable) end

---@param rect IntVector2
---@return nil
function CheckBox:SetCheckedOffset(rect) end

---@param x integer
---@param y integer
---@return nil
function CheckBox:SetCheckedOffset(x, y) end

---@return boolean
function CheckBox:IsChecked() end

---@return IntVector2
function CheckBox:GetCheckedOffset() end

