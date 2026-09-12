---@meta

--- Auto-generated from Urho2D/RigidBody2D

---@alias BodyType2D
---| integer # BodyType2D enum values

---@type BodyType2D
BT_STATIC = BT_STATIC  -- Original C++ value: b2_staticBody
---@type BodyType2D
BT_KINEMATIC = BT_KINEMATIC  -- Original C++ value: b2_kinematicBody
---@type BodyType2D
BT_DYNAMIC = BT_DYNAMIC  -- Original C++ value: b2_dynamicBody

---@class RigidBody2D : Component
---@field bodyType BodyType2D
---@field mass number
---@field inertia number
---@field massCenter Vector2
---@field useFixtureMass boolean
---@field linearDamping number
---@field angularDamping number
---@field allowSleep boolean
---@field fixedRotation boolean
---@field bullet boolean
---@field gravityScale number
---@field awake boolean
---@field linearVelocity Vector2
---@field angularVelocity number
RigidBody2D = {}

---@param bodyType BodyType2D
---@return nil
function RigidBody2D:SetBodyType(bodyType) end

---@param mass number
---@return nil
function RigidBody2D:SetMass(mass) end

---@param inertia number
---@return nil
function RigidBody2D:SetInertia(inertia) end

---@param center Vector2
---@return nil
function RigidBody2D:SetMassCenter(center) end

---@param useFixtureMass boolean
---@return nil
function RigidBody2D:SetUseFixtureMass(useFixtureMass) end

---@param linearDamping number
---@return nil
function RigidBody2D:SetLinearDamping(linearDamping) end

---@param angularDamping number
---@return nil
function RigidBody2D:SetAngularDamping(angularDamping) end

---@param allowSleep boolean
---@return nil
function RigidBody2D:SetAllowSleep(allowSleep) end

---@param fixedRotation boolean
---@return nil
function RigidBody2D:SetFixedRotation(fixedRotation) end

---@param bullet boolean
---@return nil
function RigidBody2D:SetBullet(bullet) end

---@param gravityScale number
---@return nil
function RigidBody2D:SetGravityScale(gravityScale) end

---@param awake boolean
---@return nil
function RigidBody2D:SetAwake(awake) end

---@param linearVelocity Vector2
---@return nil
function RigidBody2D:SetLinearVelocity(linearVelocity) end

---@param angularVelocity number
---@return nil
function RigidBody2D:SetAngularVelocity(angularVelocity) end

---@param force Vector2
---@param point Vector2
---@param wake boolean
---@return nil
function RigidBody2D:ApplyForce(force, point, wake) end

---@param force Vector2
---@param wake boolean
---@return nil
function RigidBody2D:ApplyForceToCenter(force, wake) end

---@param torque number
---@param wake boolean
---@return nil
function RigidBody2D:ApplyTorque(torque, wake) end

---@param impulse Vector2
---@param point Vector2
---@param wake boolean
---@return nil
function RigidBody2D:ApplyLinearImpulse(impulse, point, wake) end

---@param impulse Vector2
---@param wake boolean
---@return nil
function RigidBody2D:ApplyLinearImpulseToCenter(impulse, wake) end

---@param impulse number
---@param wake boolean
---@return nil
function RigidBody2D:ApplyAngularImpulse(impulse, wake) end

---@return BodyType2D
function RigidBody2D:GetBodyType() end

---@return number
function RigidBody2D:GetMass() end

---@return number
function RigidBody2D:GetInertia() end

---@return Vector2
function RigidBody2D:GetMassCenter() end

---@return boolean
function RigidBody2D:GetUseFixtureMass() end

---@return number
function RigidBody2D:GetLinearDamping() end

---@return number
function RigidBody2D:GetAngularDamping() end

---@return boolean
function RigidBody2D:IsAllowSleep() end

---@return boolean
function RigidBody2D:IsFixedRotation() end

---@return boolean
function RigidBody2D:IsBullet() end

---@return number
function RigidBody2D:GetGravityScale() end

---@return boolean
function RigidBody2D:IsAwake() end

---@return Vector2
function RigidBody2D:GetLinearVelocity() end

---@return number
function RigidBody2D:GetAngularVelocity() end

