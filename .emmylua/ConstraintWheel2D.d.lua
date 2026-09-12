---@meta

--- Auto-generated from Urho2D/ConstraintWheel2D

---@class ConstraintWheel2D : Constraint2D
---@field anchor Vector2
---@field axis Vector2
---@field enableMotor boolean
---@field maxMotorTorque number
---@field motorSpeed number
---@field frequencyHz number
---@field dampingRatio number
ConstraintWheel2D = {}

---@param anchor Vector2
---@return nil
function ConstraintWheel2D:SetAnchor(anchor) end

---@param axis Vector2
---@return nil
function ConstraintWheel2D:SetAxis(axis) end

---@param enableMotor boolean
---@return nil
function ConstraintWheel2D:SetEnableMotor(enableMotor) end

---@param maxMotorTorque number
---@return nil
function ConstraintWheel2D:SetMaxMotorTorque(maxMotorTorque) end

---@param motorSpeed number
---@return nil
function ConstraintWheel2D:SetMotorSpeed(motorSpeed) end

---@param frequencyHz number
---@return nil
function ConstraintWheel2D:SetFrequencyHz(frequencyHz) end

---@param dampingRatio number
---@return nil
function ConstraintWheel2D:SetDampingRatio(dampingRatio) end

---@return Vector2
function ConstraintWheel2D:GetAnchor() end

---@return Vector2
function ConstraintWheel2D:GetAxis() end

---@return boolean
function ConstraintWheel2D:GetEnableMotor() end

---@return number
function ConstraintWheel2D:GetMaxMotorTorque() end

---@return number
function ConstraintWheel2D:GetMotorSpeed() end

---@return number
function ConstraintWheel2D:GetFrequencyHz() end

---@return number
function ConstraintWheel2D:GetDampingRatio() end

