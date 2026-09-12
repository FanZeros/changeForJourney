---@meta

--- Auto-generated from Urho2D/ConstraintPrismatic2D

---@class ConstraintPrismatic2D : Constraint2D
---@field anchor Vector2
---@field axis Vector2
---@field enableLimit boolean
---@field lowerTranslation number
---@field upperTranslation number
---@field enableMotor boolean
---@field maxMotorForce number
---@field motorSpeed number
ConstraintPrismatic2D = {}

---@param anchor Vector2
---@return nil
function ConstraintPrismatic2D:SetAnchor(anchor) end

---@param axis Vector2
---@return nil
function ConstraintPrismatic2D:SetAxis(axis) end

---@param enableLimit boolean
---@return nil
function ConstraintPrismatic2D:SetEnableLimit(enableLimit) end

---@param lowerTranslation number
---@return nil
function ConstraintPrismatic2D:SetLowerTranslation(lowerTranslation) end

---@param upperTranslation number
---@return nil
function ConstraintPrismatic2D:SetUpperTranslation(upperTranslation) end

---@param enableMotor boolean
---@return nil
function ConstraintPrismatic2D:SetEnableMotor(enableMotor) end

---@param maxMotorForce number
---@return nil
function ConstraintPrismatic2D:SetMaxMotorForce(maxMotorForce) end

---@param motorSpeed number
---@return nil
function ConstraintPrismatic2D:SetMotorSpeed(motorSpeed) end

---@return Vector2
function ConstraintPrismatic2D:GetAnchor() end

---@return Vector2
function ConstraintPrismatic2D:GetAxis() end

---@return boolean
function ConstraintPrismatic2D:GetEnableLimit() end

---@return number
function ConstraintPrismatic2D:GetLowerTranslation() end

---@return number
function ConstraintPrismatic2D:GetUpperTranslation() end

---@return boolean
function ConstraintPrismatic2D:GetEnableMotor() end

---@return number
function ConstraintPrismatic2D:GetMaxMotorForce() end

---@return number
function ConstraintPrismatic2D:GetMotorSpeed() end

