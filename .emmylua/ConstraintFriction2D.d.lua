---@meta

--- Auto-generated from Urho2D/ConstraintFriction2D

---@class ConstraintFriction2D : Constraint2D
---@field anchor Vector2
---@field maxForce number
---@field maxTorque number
ConstraintFriction2D = {}

---@param anchor Vector2
---@return nil
function ConstraintFriction2D:SetAnchor(anchor) end

---@param maxForce number
---@return nil
function ConstraintFriction2D:SetMaxForce(maxForce) end

---@param maxTorque number
---@return nil
function ConstraintFriction2D:SetMaxTorque(maxTorque) end

---@return Vector2
function ConstraintFriction2D:GetAnchor() end

---@return number
function ConstraintFriction2D:GetMaxForce() end

---@return number
function ConstraintFriction2D:GetMaxTorque() end

