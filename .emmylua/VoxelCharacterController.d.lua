---@meta

--- Auto-generated from VoxelPhysics/VoxelCharacterController

---@alias VoxelCharacterGroundState
---| integer # VoxelCharacterGroundState enum values

---@type VoxelCharacterGroundState
--- Supported by a walkable surface.
VOXEL_CHARACTER_ON_GROUND = 0
---@type VoxelCharacterGroundState
--- Touching support that exceeds the configured maximum slope.
VOXEL_CHARACTER_ON_STEEP_GROUND = 1
---@type VoxelCharacterGroundState
--- Touching geometry without stable supporting contact.
VOXEL_CHARACTER_NOT_SUPPORTED = 2
---@type VoxelCharacterGroundState
--- No supporting contact.
VOXEL_CHARACTER_IN_AIR = 3

---@class VoxelCharacterController : Component
---@field height number
---@field radius number
---@field supportRadius number
---@field gravityFactor number
---@field mass number
---@field maxStrength number
---@field jumpSpeed number
---@field maxSlopeAngle number
---@field stepHeight number
---@field stickToFloorDistance number
---@field penetrationRecoverySpeed number
---@field enhancedInternalEdgeRemoval boolean
---@field maxNumHits integer
---@field desiredVelocity Vector3
---@field linearVelocity Vector3
---@field onGround boolean
---@field groundState VoxelCharacterGroundState
---@field groundNormal Vector3
---@field groundVelocity Vector3
---@field swimming boolean
---@field maxHitsExceeded boolean
---@field created boolean
VoxelCharacterController = {}

--- Queue a jump using the configured jump speed.
---@return nil
function VoxelCharacterController:Jump() end

--- Queue a jump for the next world update. Repeated requests keep the strongest one.
---@param speed number
---@return nil
function VoxelCharacterController:Jump(speed) end

--- Teleport both the virtual character and its Node. Position is at the feet.
---@param worldPosition Vector3
---@return nil
function VoxelCharacterController:Teleport(worldPosition) end

--- Set height.
---@param height number
---@return nil
function VoxelCharacterController:SetHeight(height) end

--- Return height.
---@return number
function VoxelCharacterController:GetHeight() end

--- Set radius.
---@param radius number
---@return nil
function VoxelCharacterController:SetRadius(radius) end

--- Return radius.
---@return number
function VoxelCharacterController:GetRadius() end

--- Horizontal radius of the lower capsule region that may count as support. Contacts outside
--- this radius remain valid collisions but do not make the character grounded; values are
--- clamped to [0, Radius].
---@param radius number
---@return nil
function VoxelCharacterController:SetSupportRadius(radius) end

--- Return support radius.
---@return number
function VoxelCharacterController:GetSupportRadius() end

--- Set gravity factor.
---@param factor number
---@return nil
function VoxelCharacterController:SetGravityFactor(factor) end

--- Return gravity factor.
---@return number
function VoxelCharacterController:GetGravityFactor() end

--- Set mass.
---@param mass number
---@return nil
function VoxelCharacterController:SetMass(mass) end

--- Return mass.
---@return number
function VoxelCharacterController:GetMass() end

--- Set max strength.
---@param strength number
---@return nil
function VoxelCharacterController:SetMaxStrength(strength) end

--- Return max strength.
---@return number
function VoxelCharacterController:GetMaxStrength() end

--- Set jump speed.
---@param speed number
---@return nil
function VoxelCharacterController:SetJumpSpeed(speed) end

--- Return jump speed.
---@return number
function VoxelCharacterController:GetJumpSpeed() end

--- Set maximum walkable slope angle in degrees.
---@param degrees number
---@return nil
function VoxelCharacterController:SetMaxSlopeAngle(degrees) end

--- Return maximum walkable slope angle in degrees.
---@return number
function VoxelCharacterController:GetMaxSlopeAngle() end

--- Set step height.
---@param height number
---@return nil
function VoxelCharacterController:SetStepHeight(height) end

--- Return step height.
---@return number
function VoxelCharacterController:GetStepHeight() end

--- Set stick to floor distance.
---@param distance number
---@return nil
function VoxelCharacterController:SetStickToFloorDistance(distance) end

--- Return stick to floor distance.
---@return number
function VoxelCharacterController:GetStickToFloorDistance() end

--- Set penetration recovery speed.
---@param speed number
---@return nil
function VoxelCharacterController:SetPenetrationRecoverySpeed(speed) end

--- Return penetration recovery speed.
---@return number
function VoxelCharacterController:GetPenetrationRecoverySpeed() end

--- Set enhanced internal edge removal.
---@param enable boolean
---@return nil
function VoxelCharacterController:SetEnhancedInternalEdgeRemoval(enable) end

--- Return true if enhanced internal edge removal is enabled.
---@return boolean
function VoxelCharacterController:GetEnhancedInternalEdgeRemoval() end

--- Set max num hits.
---@param maxHits integer
---@return nil
function VoxelCharacterController:SetMaxNumHits(maxHits) end

--- Return max num hits.
---@return integer
function VoxelCharacterController:GetMaxNumHits() end

--- Persistent movement intent consumed on every VoxelPhysicsWorld update.
---@param velocity Vector3
---@return nil
function VoxelCharacterController:SetDesiredVelocity(velocity) end

--- Return movement intent; remote replicas read the latest server value.
---@return Vector3
function VoxelCharacterController:GetDesiredVelocity() end

--- Return actual world-space velocity in m/s; remote replicas read the latest server value.
---@return Vector3
function VoxelCharacterController:GetLinearVelocity() end

--- Set linear velocity in world space, in metres per second.
---@param velocity Vector3
---@return nil
function VoxelCharacterController:SetLinearVelocity(velocity) end

--- Return walkable support state; remote replicas read the latest server ground state.
---@return boolean
function VoxelCharacterController:IsOnGround() end

--- Return ground state; remote replicas read the latest server value.
---@return VoxelCharacterGroundState
function VoxelCharacterController:GetGroundState() end

--- Return stable support normal; remote replicas read the latest server value.
---@return Vector3
function VoxelCharacterController:GetGroundNormal() end

--- Return stable support velocity; remote replicas read the latest server value.
---@return Vector3
function VoxelCharacterController:GetGroundVelocity() end

--- Return swimming state; remote replicas read the latest server value.
---@return boolean
function VoxelCharacterController:IsSwimming() end

--- Return contact-limit state; remote replicas read the latest server value.
---@return boolean
function VoxelCharacterController:GetMaxHitsExceeded() end

--- Return whether a local solver exists. Remote replicas remain false even when state is synchronized.
---@return boolean
function VoxelCharacterController:IsCreated() end

