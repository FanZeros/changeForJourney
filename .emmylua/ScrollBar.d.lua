---@meta

--- Auto-generated from UI/ScrollBar

---@class ScrollBar : BorderImage
---@overload fun(): ScrollBar
---@field orientation Orientation
---@field range number
---@field value number
---@field scrollStep number
---@field stepFactor number
---@field effectiveScrollStep number
---@field backButton Button
---@field forwardButton Button
---@field slider Slider
ScrollBar = {}

---@return ScrollBar
function ScrollBar.new() end

---@param orientation Orientation
---@return nil
function ScrollBar:SetOrientation(orientation) end

---@param range number
---@return nil
function ScrollBar:SetRange(range) end

---@param value number
---@return nil
function ScrollBar:SetValue(value) end

---@param delta number
---@return nil
function ScrollBar:ChangeValue(delta) end

---@param step number
---@return nil
function ScrollBar:SetScrollStep(step) end

---@param factor number
---@return nil
function ScrollBar:SetStepFactor(factor) end

---@return nil
function ScrollBar:StepBack() end

---@return nil
function ScrollBar:StepForward() end

---@return Orientation
function ScrollBar:GetOrientation() end

---@return number
function ScrollBar:GetRange() end

---@return number
function ScrollBar:GetValue() end

---@return number
function ScrollBar:GetScrollStep() end

---@return number
function ScrollBar:GetStepFactor() end

---@return number
function ScrollBar:GetEffectiveScrollStep() end

---@return Button
function ScrollBar:GetBackButton() end

---@return Button
function ScrollBar:GetForwardButton() end

---@return Slider
function ScrollBar:GetSlider() end

