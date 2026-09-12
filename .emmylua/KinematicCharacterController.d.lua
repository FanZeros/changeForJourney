---@meta

--- Auto-generated from Physics/KinematicCharacterController

---@class KinematicCharacterController : Component
---@overload fun(): KinematicCharacterController
---@field collisionLayer integer
---@field collisionMask integer
---@field gravityFactor number
---@field stepHeight number
---@field maxJumpHeight number
---@field jumpSpeed number
---@field fallSpeed number
---@field maxSlope number
---@field linearDamping number
---@field angularDamping number
---@field gravity Vector3
---@field physicsWorld PhysicsWorld
KinematicCharacterController = {}

---@return KinematicCharacterController
function KinematicCharacterController.new() end

---@param layer integer
---@return nil
function KinematicCharacterController:SetCollisionLayer(layer) end

---@param mask integer
---@return nil
function KinematicCharacterController:SetCollisionMask(mask) end

---@param layer integer
---@param mask integer
---@return nil
function KinematicCharacterController:SetCollisionLayerAndMask(layer, mask) end

---@param gravity Vector3
---@return nil
function KinematicCharacterController:SetGravity(gravity) end

---@param factor number
---@return nil
function KinematicCharacterController:SetGravityFactor(factor) end

---@return number
function KinematicCharacterController:GetGravityFactor() end

---@param damping number
---@return nil
function KinematicCharacterController:SetLinearDamping(damping) end

---@return number
function KinematicCharacterController:GetLinearDamping() end

---@param angularDamping number
---@return nil
function KinematicCharacterController:SetAngularDamping(angularDamping) end

---@return number
function KinematicCharacterController:GetAngularDamping() end

---@param stepHeight number
---@return nil
function KinematicCharacterController:SetStepHeight(stepHeight) end

---@return number
function KinematicCharacterController:GetStepHeight() end

---@param maxJumpHeight number
---@return nil
function KinematicCharacterController:SetMaxJumpHeight(maxJumpHeight) end

---@return number
function KinematicCharacterController:GetMaxJumpHeight() end

---@param fallSpeed number
---@return nil
function KinematicCharacterController:SetFallSpeed(fallSpeed) end

---@return number
function KinematicCharacterController:GetFallSpeed() end

---@param jumpSpeed number
---@return nil
function KinematicCharacterController:SetJumpSpeed(jumpSpeed) end

---@return number
function KinematicCharacterController:GetJumpSpeed() end

---@param maxSlope number
---@return nil
function KinematicCharacterController:SetMaxSlope(maxSlope) end

---@return number
function KinematicCharacterController:GetMaxSlope() end

---@param walkDir Vector3
---@return nil
function KinematicCharacterController:SetWalkDirection(walkDir) end

---@return boolean
function KinematicCharacterController:OnGround() end

---@param jump? Vector3
---@return nil
function KinematicCharacterController:Jump(jump) end

---@param impulse Vector3
---@return nil
function KinematicCharacterController:ApplyImpulse(impulse) end

---@return boolean
function KinematicCharacterController:CanJump() end

---@param velocity Vector3
---@return nil
function KinematicCharacterController:SetAngularVelocity(velocity) end

---@return Vector3
function KinematicCharacterController:GetAngularVelocity() end

---@param velocity Vector3
---@return nil
function KinematicCharacterController:SetLinearVelocity(velocity) end

---@return Vector3
function KinematicCharacterController:GetLinearVelocity() end

---@param position Vector3
---@return nil
function KinematicCharacterController:Warp(position) end

