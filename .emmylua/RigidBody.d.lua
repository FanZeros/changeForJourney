---@meta

--- Auto-generated from Physics/RigidBody

---@alias CollisionEventMode
---| integer # CollisionEventMode enum values

---@type CollisionEventMode
COLLISION_NEVER = 0
---@type CollisionEventMode
COLLISION_ACTIVE = 1
---@type CollisionEventMode
COLLISION_ALWAYS = 2

---@class RigidBody : Component
---@overload fun(): RigidBody
---@field physicsWorld PhysicsWorld
---@field mass number
---@field position Vector3
---@field rotation Quaternion
---@field linearVelocity Vector3
---@field linearFactor Vector3
---@field linearRestThreshold number
---@field linearDamping number
---@field angularVelocity Vector3
---@field angularFactor Vector3
---@field angularRestThreshold number
---@field angularDamping number
---@field friction number
---@field anisotropicFriction Vector3
---@field rollingFriction number
---@field restitution number
---@field contactProcessingThreshold number
---@field ccdRadius number
---@field ccdMotionThreshold number
---@field useGravity boolean
---@field gravityOverride Vector3
---@field centerOfMass Vector3
---@field kinematic boolean
---@field trigger boolean
---@field active boolean
---@field collisionLayer integer
---@field collisionMask integer
---@field collisionEventMode CollisionEventMode
RigidBody = {}

---@return RigidBody
function RigidBody.new() end

---@param mass number
---@return nil
function RigidBody:SetMass(mass) end

---@param position Vector3
---@return nil
function RigidBody:SetPosition(position) end

---@param rotation Quaternion
---@return nil
function RigidBody:SetRotation(rotation) end

---@param position Vector3
---@param rotation Quaternion
---@return nil
function RigidBody:SetTransform(position, rotation) end

---@param velocity Vector3
---@return nil
function RigidBody:SetLinearVelocity(velocity) end

---@param factor Vector3
---@return nil
function RigidBody:SetLinearFactor(factor) end

---@param threshold number
---@return nil
function RigidBody:SetLinearRestThreshold(threshold) end

---@param damping number
---@return nil
function RigidBody:SetLinearDamping(damping) end

---@param angularVelocity Vector3
---@return nil
function RigidBody:SetAngularVelocity(angularVelocity) end

---@param factor Vector3
---@return nil
function RigidBody:SetAngularFactor(factor) end

---@param threshold number
---@return nil
function RigidBody:SetAngularRestThreshold(threshold) end

---@param factor number
---@return nil
function RigidBody:SetAngularDamping(factor) end

---@param friction number
---@return nil
function RigidBody:SetFriction(friction) end

---@param friction Vector3
---@return nil
function RigidBody:SetAnisotropicFriction(friction) end

---@param friction number
---@return nil
function RigidBody:SetRollingFriction(friction) end

---@param restitution number
---@return nil
function RigidBody:SetRestitution(restitution) end

---@param threshold number
---@return nil
function RigidBody:SetContactProcessingThreshold(threshold) end

---@param radius number
---@return nil
function RigidBody:SetCcdRadius(radius) end

---@param threshold number
---@return nil
function RigidBody:SetCcdMotionThreshold(threshold) end

---@param enable boolean
---@return nil
function RigidBody:SetUseGravity(enable) end

---@param gravity Vector3
---@return nil
function RigidBody:SetGravityOverride(gravity) end

---@param enable boolean
---@return nil
function RigidBody:SetKinematic(enable) end

---@param enable boolean
---@return nil
function RigidBody:SetTrigger(enable) end

---@param layer integer
---@return nil
function RigidBody:SetCollisionLayer(layer) end

---@param mask integer
---@return nil
function RigidBody:SetCollisionMask(mask) end

---@param layer integer
---@param mask integer
---@return nil
function RigidBody:SetCollisionLayerAndMask(layer, mask) end

---@param mode CollisionEventMode
---@return nil
function RigidBody:SetCollisionEventMode(mode) end

---@return nil
function RigidBody:DisableMassUpdate() end

---@return nil
function RigidBody:EnableMassUpdate() end

---@param force Vector3
---@return nil
function RigidBody:ApplyForce(force) end

---@param force Vector3
---@param position Vector3
---@return nil
function RigidBody:ApplyForce(force, position) end

---@param torque Vector3
---@return nil
function RigidBody:ApplyTorque(torque) end

---@param impulse Vector3
---@return nil
function RigidBody:ApplyImpulse(impulse) end

---@param impulse Vector3
---@param position Vector3
---@return nil
function RigidBody:ApplyImpulse(impulse, position) end

---@param torque Vector3
---@return nil
function RigidBody:ApplyTorqueImpulse(torque) end

---@return nil
function RigidBody:ResetForces() end

---@return nil
function RigidBody:Activate() end

---@return nil
function RigidBody:ReAddBodyToWorld() end

---@return PhysicsWorld
function RigidBody:GetPhysicsWorld() end

---@return number
function RigidBody:GetMass() end

---@return Vector3
function RigidBody:GetPosition() end

---@return Quaternion
function RigidBody:GetRotation() end

---@return Vector3
function RigidBody:GetLinearVelocity() end

---@return Vector3
function RigidBody:GetLinearFactor() end

---@param position Vector3
---@return Vector3
function RigidBody:GetVelocityAtPoint(position) end

---@return number
function RigidBody:GetLinearRestThreshold() end

---@return number
function RigidBody:GetLinearDamping() end

---@return Vector3
function RigidBody:GetAngularVelocity() end

---@return Vector3
function RigidBody:GetAngularFactor() end

---@return number
function RigidBody:GetAngularRestThreshold() end

---@return number
function RigidBody:GetAngularDamping() end

---@return number
function RigidBody:GetFriction() end

---@return Vector3
function RigidBody:GetAnisotropicFriction() end

---@return number
function RigidBody:GetRollingFriction() end

---@return number
function RigidBody:GetRestitution() end

---@return number
function RigidBody:GetContactProcessingThreshold() end

---@return number
function RigidBody:GetCcdRadius() end

---@return number
function RigidBody:GetCcdMotionThreshold() end

---@return boolean
function RigidBody:GetUseGravity() end

---@return Vector3
function RigidBody:GetGravityOverride() end

---@return Vector3
function RigidBody:GetCenterOfMass() end

---@return boolean
function RigidBody:IsKinematic() end

---@return boolean
function RigidBody:IsTrigger() end

---@return boolean
function RigidBody:IsActive() end

---@return integer
function RigidBody:GetCollisionLayer() end

---@return integer
function RigidBody:GetCollisionMask() end

---@return CollisionEventMode
function RigidBody:GetCollisionEventMode() end

