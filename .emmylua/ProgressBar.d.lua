---@meta

--- Auto-generated from UI/ProgressBar

---@class ProgressBar : BorderImage
---@overload fun(): ProgressBar
---@field orientation Orientation
---@field range number
---@field value number
---@field knob BorderImage
---@field loadingPercentStyle string
---@field showPercentText boolean
ProgressBar = {}

---@return ProgressBar
function ProgressBar.new() end

---@param orientation Orientation
---@return nil
function ProgressBar:SetOrientation(orientation) end

---@param range number
---@return nil
function ProgressBar:SetRange(range) end

---@param value number
---@return nil
function ProgressBar:SetValue(value) end

---@param delta number
---@return nil
function ProgressBar:ChangeValue(delta) end

---@param style string
---@return nil
function ProgressBar:SetLoadingPercentStyle(style) end

---@param showPercentText boolean
---@return nil
function ProgressBar:SetShowPercentText(showPercentText) end

---@return Orientation
function ProgressBar:GetOrientation() end

---@return number
function ProgressBar:GetRange() end

---@return number
function ProgressBar:GetValue() end

---@return BorderImage
function ProgressBar:GetKnob() end

---@return string
function ProgressBar:GetLoadingPercentStyle() end

---@return boolean
function ProgressBar:GetShowPercentText() end

