---@meta

--- Auto-generated from Physics/Constraint

---@alias ConstraintType
---| integer # ConstraintType enum values

---@type ConstraintType
CONSTRAINT_POINT = 0
---@type ConstraintType
CONSTRAINT_HINGE = 1
---@type ConstraintType
CONSTRAINT_SLIDER = 2
---@type ConstraintType
CONSTRAINT_CONETWIST = 3

---@class Constraint : Component
---@overload fun(): Constraint
---@field physicsWorld PhysicsWorld
---@field constraintType ConstraintType
---@field ownBody RigidBody
---@field otherBody RigidBody
---@field position Vector3
---@field rotation Quaternion
---@field axis Vector3
---@field otherPosition Vector3
---@field otherRotation Quaternion
---@field otherAxis Vector3
---@field worldPosition Vector3
---@field highLimit Vector2
---@field lowLimit Vector2
---@field ERP number
---@field CFM number
---@field disableCollision boolean
Constraint = {}

---@return Constraint
function Constraint.new() end

---@param type ConstraintType
---@return nil
function Constraint:SetConstraintType(type) end

---@param body RigidBody
---@return nil
function Constraint:SetOtherBody(body) end

---@param position Vector3
---@return nil
function Constraint:SetPosition(position) end

---@param rotation Quaternion
---@return nil
function Constraint:SetRotation(rotation) end

---@param axis Vector3
---@return nil
function Constraint:SetAxis(axis) end

---@param position Vector3
---@return nil
function Constraint:SetOtherPosition(position) end

---@param rotation Quaternion
---@return nil
function Constraint:SetOtherRotation(rotation) end

---@param axis Vector3
---@return nil
function Constraint:SetOtherAxis(axis) end

---@param position Vector3
---@return nil
function Constraint:SetWorldPosition(position) end

---@param limit Vector2
---@return nil
function Constraint:SetHighLimit(limit) end

---@param limit Vector2
---@return nil
function Constraint:SetLowLimit(limit) end

---@param erp number
---@return nil
function Constraint:SetERP(erp) end

---@param cfm number
---@return nil
function Constraint:SetCFM(cfm) end

---@param disable boolean
---@return nil
function Constraint:SetDisableCollision(disable) end

---@return PhysicsWorld
function Constraint:GetPhysicsWorld() end

---@return ConstraintType
function Constraint:GetConstraintType() end

---@return RigidBody
function Constraint:GetOwnBody() end

---@return RigidBody
function Constraint:GetOtherBody() end

---@return Vector3
function Constraint:GetPosition() end

---@return Quaternion
function Constraint:GetRotation() end

---@return Vector3
function Constraint:GetOtherPosition() end

---@return Quaternion
function Constraint:GetOtherRotation() end

---@return Vector3
function Constraint:GetWorldPosition() end

---@return Vector2
function Constraint:GetHighLimit() end

---@return Vector2
function Constraint:GetLowLimit() end

---@return number
function Constraint:GetERP() end

---@return number
function Constraint:GetCFM() end

---@return boolean
function Constraint:GetDisableCollision() end

