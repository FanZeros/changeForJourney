---@meta

--- Auto-generated from Urho2D/ConstraintMouse2D

---@class ConstraintMouse2D : Constraint2D
---@field target Vector2
---@field maxForce number
---@field frequencyHz number
---@field dampingRatio number
ConstraintMouse2D = {}

---@param target Vector2
---@return nil
function ConstraintMouse2D:SetTarget(target) end

---@param maxForce number
---@return nil
function ConstraintMouse2D:SetMaxForce(maxForce) end

---@param frequencyHz number
---@return nil
function ConstraintMouse2D:SetFrequencyHz(frequencyHz) end

---@param dampingRatio number
---@return nil
function ConstraintMouse2D:SetDampingRatio(dampingRatio) end

---@return Vector2
function ConstraintMouse2D:GetTarget() end

---@return number
function ConstraintMouse2D:GetMaxForce() end

---@return number
function ConstraintMouse2D:GetFrequencyHz() end

---@return number
function ConstraintMouse2D:GetDampingRatio() end

