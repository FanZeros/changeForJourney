---@meta

--- Auto-generated from Urho2D/ConstraintGear2D

---@class ConstraintGear2D : Constraint2D
---@field ownerConstraint Constraint2D
---@field otherConstraint Constraint2D
---@field ratio number
ConstraintGear2D = {}

---@param constraint Constraint2D
---@return nil
function ConstraintGear2D:SetOwnerConstraint(constraint) end

---@param constraint Constraint2D
---@return nil
function ConstraintGear2D:SetOtherConstraint(constraint) end

---@param ratio number
---@return nil
function ConstraintGear2D:SetRatio(ratio) end

---@return Constraint2D
function ConstraintGear2D:GetOwnerConstraint() end

---@return Constraint2D
function ConstraintGear2D:GetOtherConstraint() end

---@return number
function ConstraintGear2D:GetRatio() end

