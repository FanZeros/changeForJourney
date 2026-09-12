---@meta

--- Auto-generated from UI/Slider

---@class Slider : BorderImage
---@overload fun(): Slider
---@field orientation Orientation
---@field range number
---@field value number
---@field knob BorderImage
---@field repeatRate number
Slider = {}

---@return Slider
function Slider.new() end

---@param orientation Orientation
---@return nil
function Slider:SetOrientation(orientation) end

---@param range number
---@return nil
function Slider:SetRange(range) end

---@param value number
---@return nil
function Slider:SetValue(value) end

---@param delta number
---@return nil
function Slider:ChangeValue(delta) end

---@param rate number
---@return nil
function Slider:SetRepeatRate(rate) end

---@return Orientation
function Slider:GetOrientation() end

---@return number
function Slider:GetRange() end

---@return number
function Slider:GetValue() end

---@return BorderImage
function Slider:GetKnob() end

---@return number
function Slider:GetRepeatRate() end

