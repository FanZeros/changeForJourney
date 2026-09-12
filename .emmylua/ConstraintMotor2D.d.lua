---@meta

--- Auto-generated from Urho2D/ConstraintMotor2D

---@class ConstraintMotor2D : Constraint2D
---@field linearOffset Vector2
---@field angularOffset number
---@field maxForce number
---@field maxTorque number
---@field correctionFactor number
ConstraintMotor2D = {}

---@param linearOffset Vector2
---@return nil
function ConstraintMotor2D:SetLinearOffset(linearOffset) end

---@param angularOffset number
---@return nil
function ConstraintMotor2D:SetAngularOffset(angularOffset) end

---@param maxForce number
---@return nil
function ConstraintMotor2D:SetMaxForce(maxForce) end

---@param maxTorque number
---@return nil
function ConstraintMotor2D:SetMaxTorque(maxTorque) end

---@param correctionFactor number
---@return nil
function ConstraintMotor2D:SetCorrectionFactor(correctionFactor) end

---@return Vector2
function ConstraintMotor2D:GetLinearOffset() end

---@return number
function ConstraintMotor2D:GetAngularOffset() end

---@return number
function ConstraintMotor2D:GetMaxForce() end

---@return number
function ConstraintMotor2D:GetMaxTorque() end

---@return number
function ConstraintMotor2D:GetCorrectionFactor() end

