---@meta

--- Auto-generated from VoxelPhysics/VoxelAssembly

---@class VoxelMemberStress
---@overload fun(): VoxelMemberStress
---@field force Vector3
---@field torque Vector3
---@field forceFactor number
---@field torqueFactor number
---@field breakFactor number
VoxelMemberStress = {}

---@return VoxelMemberStress
function VoxelMemberStress.new() end


---@class VoxelAssembly : Component
---@field volumeCount integer
---@field mass number
---@field rootVolume VoxelVolume
---@field linearVelocity Vector3
---@field angularVelocity Vector3
---@field linearDamping number
---@field angularDamping number
---@field gravityFactor number
---@field useGravity boolean
---@field ccdEnabled boolean
VoxelAssembly = {}

--- Add a finalized standalone dynamic volume. Repeated additions share one
--- compound rebuild at the next physics safe point.
---@param volume VoxelVolume
---@return boolean
function VoxelAssembly:AddVolume(volume) end

--- Detach a member as a standalone body. newRoot is required only when the caller wants to
--- override deterministic root selection after removing the current root.
---@param volume VoxelVolume
---@param newRoot? VoxelVolume
---@return boolean
function VoxelAssembly:RemoveVolume(volume, newRoot) end

--- Return true if the volume belongs to this assembly.
---@param volume VoxelVolume
---@return boolean
function VoxelAssembly:ContainsVolume(volume) end

--- Return volume count.
---@return integer
function VoxelAssembly:GetVolumeCount() end

--- Return volume.
---@param index integer
---@return VoxelVolume
function VoxelAssembly:GetVolume(index) end

--- Select the member Node that defines the stable gameplay transform of the assembly.
---@param volume VoxelVolume
---@return nil
function VoxelAssembly:SetRootVolume(volume) end

--- Return root volume.
---@return VoxelVolume
function VoxelAssembly:GetRootVolume() end

--- Replace the shared body with one standalone dynamic body per member.
---@return nil
function VoxelAssembly:Dissolve() end

--- Rigid-body façade. All values are world-space and operate on the shared body.
---@param force Vector3
---@return nil
function VoxelAssembly:ApplyForce(force) end

--- Apply force in newtons at the specified world-space position.
---@param force Vector3
---@param worldPosition Vector3
---@return nil
function VoxelAssembly:ApplyForce(force, worldPosition) end

--- Apply impulse in newton-seconds.
---@param impulse Vector3
---@return nil
function VoxelAssembly:ApplyImpulse(impulse) end

--- Apply impulse in newton-seconds.
---@param impulse Vector3
---@param worldPosition Vector3
---@return nil
function VoxelAssembly:ApplyImpulse(impulse, worldPosition) end

--- Apply torque in newton-metres.
---@param torque Vector3
---@return nil
function VoxelAssembly:ApplyTorque(torque) end

--- Apply angular impulse in newton-metre-seconds.
---@param impulse Vector3
---@return nil
function VoxelAssembly:ApplyTorqueImpulse(impulse) end

--- Clear accumulated force and torque without clearing velocity.
---@return nil
function VoxelAssembly:ResetForces() end

--- Return world-space velocity at the specified world-space point.
---@param worldPosition Vector3
---@return Vector3
function VoxelAssembly:GetVelocityAtPoint(worldPosition) end

--- Density-derived mass summed over all current members. There is intentionally no SetMass.
---@return number
function VoxelAssembly:GetMass() end

--- Return linear velocity in world space, in metres per second.
---@return Vector3
function VoxelAssembly:GetLinearVelocity() end

--- Set linear velocity in world space, in metres per second.
---@param velocity Vector3
---@return nil
function VoxelAssembly:SetLinearVelocity(velocity) end

--- Return angular velocity in world space, in radians per second.
---@return Vector3
function VoxelAssembly:GetAngularVelocity() end

--- Set angular velocity in world space, in radians per second.
---@param velocity Vector3
---@return nil
function VoxelAssembly:SetAngularVelocity(velocity) end

--- Set linear damping.
---@param damping number
---@return nil
function VoxelAssembly:SetLinearDamping(damping) end

--- Return linear damping.
---@return number
function VoxelAssembly:GetLinearDamping() end

--- Set angular damping.
---@param damping number
---@return nil
function VoxelAssembly:SetAngularDamping(damping) end

--- Return angular damping.
---@return number
function VoxelAssembly:GetAngularDamping() end

--- Set gravity factor.
---@param factor number
---@return nil
function VoxelAssembly:SetGravityFactor(factor) end

--- Return gravity factor.
---@return number
function VoxelAssembly:GetGravityFactor() end

--- Set use gravity.
---@param enable boolean
---@return nil
function VoxelAssembly:SetUseGravity(enable) end

--- Return true if gravity affects the shared body.
---@return boolean
function VoxelAssembly:GetUseGravity() end

--- Set ccd enabled.
---@param enable boolean
---@return nil
function VoxelAssembly:SetCcdEnabled(enable) end

--- Return true if continuous collision detection is enabled.
---@return boolean
function VoxelAssembly:IsCcdEnabled() end

--- Wake the solver body.
---@return nil
function VoxelAssembly:Activate() end

--- Return whether the assembly's shared rigid body is active (not sleeping).
---@return boolean
function VoxelAssembly:IsActive() end

--- Configure the intact reaction force and torque thresholds used by automatic member detachment.
--- Remaining voxel occupancy weakens these thresholds after damage. A positive finite
--- threshold enables that channel; non-positive values disable it.
---@param volume VoxelVolume
---@param breakForce number
---@param breakTorque number
---@return nil
function VoxelAssembly:SetMemberBreakThreshold(volume, breakForce, breakTorque) end

--- Make both break channels infinitely strong again.
---@param volume VoxelVolume
---@return nil
function VoxelAssembly:ClearMemberBreakThreshold(volume) end

--- Whether at least one finite positive force or torque threshold is configured.
---@param volume VoxelVolume
---@return boolean
function VoxelAssembly:IsMemberBreakable(volume) end

--- Return the latest post-step reaction estimate and normalized break factor.
---@param volume VoxelVolume
---@return VoxelMemberStress
function VoxelAssembly:GetMemberStress(volume) end

