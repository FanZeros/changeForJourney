---@meta

--- Auto-generated from Urho2D/ConstraintRevolute2D

---@class ConstraintRevolute2D : Constraint2D
---@field anchor Vector2
---@field enableLimit boolean
---@field lowerAngle number
---@field upperAngle number
---@field enableMotor boolean
---@field motorSpeed number
---@field maxMotorTorque number
ConstraintRevolute2D = {}

---@param anchor Vector2
---@return nil
function ConstraintRevolute2D:SetAnchor(anchor) end

---@param enableLimit boolean
---@return nil
function ConstraintRevolute2D:SetEnableLimit(enableLimit) end

---@param lowerAngle number
---@return nil
function ConstraintRevolute2D:SetLowerAngle(lowerAngle) end

---@param upperAngle number
---@return nil
function ConstraintRevolute2D:SetUpperAngle(upperAngle) end

---@param enableMotor boolean
---@return nil
function ConstraintRevolute2D:SetEnableMotor(enableMotor) end

---@param motorSpeed number
---@return nil
function ConstraintRevolute2D:SetMotorSpeed(motorSpeed) end

---@param maxMotorTorque number
---@return nil
function ConstraintRevolute2D:SetMaxMotorTorque(maxMotorTorque) end

---@return Vector2
function ConstraintRevolute2D:GetAnchor() end

---@return boolean
function ConstraintRevolute2D:GetEnableLimit() end

---@return number
function ConstraintRevolute2D:GetLowerAngle() end

---@return number
function ConstraintRevolute2D:GetUpperAngle() end

---@return boolean
function ConstraintRevolute2D:GetEnableMotor() end

---@return number
function ConstraintRevolute2D:GetMotorSpeed() end

---@return number
function ConstraintRevolute2D:GetMaxMotorTorque() end

