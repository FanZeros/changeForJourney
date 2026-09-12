---@meta

--- Auto-generated from Urho2D/ConstraintWeld2D

---@class ConstraintWeld2D : Constraint2D
---@field anchor Vector2
---@field frequencyHz number
---@field dampingRatio number
ConstraintWeld2D = {}

---@param anchor Vector2
---@return nil
function ConstraintWeld2D:SetAnchor(anchor) end

---@param frequencyHz number
---@return nil
function ConstraintWeld2D:SetFrequencyHz(frequencyHz) end

---@param dampingRatio number
---@return nil
function ConstraintWeld2D:SetDampingRatio(dampingRatio) end

---@return Vector2
function ConstraintWeld2D:GetAnchor() end

---@return number
function ConstraintWeld2D:GetFrequencyHz() end

---@return number
function ConstraintWeld2D:GetDampingRatio() end

