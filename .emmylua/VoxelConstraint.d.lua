---@meta

--- Auto-generated from VoxelPhysics/VoxelConstraint

---@alias VoxelConstraintType
---| integer # VoxelConstraintType enum values

---@type VoxelConstraintType
--- One rotational degree of freedom around the local constraint axis.
VOXEL_CONSTRAINT_HINGE = 0
---@type VoxelConstraintType
--- Lock all relative translation and rotation.
VOXEL_CONSTRAINT_FIXED = 1
---@type VoxelConstraintType
--- One translational degree of freedom along the local constraint axis.
VOXEL_CONSTRAINT_SLIDER = 2
---@type VoxelConstraintType
--- Three-degree-of-freedom point joint for hitches and shackles.
VOXEL_CONSTRAINT_BALL = 3

---@class VoxelConstraint : Component
---@field constraintType VoxelConstraintType
---@field otherVolume VoxelVolume
---@field ownVolume VoxelVolume
---@field position Vector3
---@field rotation Quaternion
---@field otherPosition Vector3
---@field otherRotation Quaternion
---@field worldPosition Vector3
---@field disableCollision boolean
---@field maxFrictionForce number
---@field maxFrictionTorque number
---@field axisAngularDamping number
---@field axisAngularDampingMaxTorque number
---@field solverVelocitySteps integer
---@field solverPositionSteps integer
---@field angularLimitMin number
---@field angularLimitMax number
---@field linearLimitMin number
---@field linearLimitMax number
---@field linearSpring boolean
---@field linearSpringRestPosition number
---@field linearSpringStiffness number
---@field linearSpringDamping number
---@field built boolean
---@field suspended boolean
---@field reactionForce Vector3
---@field reactionTorque Vector3
---@field hingeAngle number
---@field sliderPosition number
VoxelConstraint = {}

--- Set constraint type.
---@param type VoxelConstraintType
---@return nil
function VoxelConstraint:SetConstraintType(type) end

--- Return constraint type.
---@return VoxelConstraintType
function VoxelConstraint:GetConstraintType() end

--- Set endpoint B. Endpoint A is the VoxelVolume on this component's Node.
---@param volume VoxelVolume
---@return nil
function VoxelConstraint:SetOtherVolume(volume) end

--- Return own volume.
---@return VoxelVolume
function VoxelConstraint:GetOwnVolume() end

--- Return other volume.
---@return VoxelVolume
function VoxelConstraint:GetOtherVolume() end

--- Endpoint A frame in volume-local space. Hinge uses local Z; slider uses local X as its axis.
---@param position Vector3
---@return nil
function VoxelConstraint:SetPosition(position) end

--- Return the constraint anchor in the owning volume's local space.
---@return Vector3
function VoxelConstraint:GetPosition() end

--- Set rotation.
---@param rotation Quaternion
---@return nil
function VoxelConstraint:SetRotation(rotation) end

--- Return the constraint frame rotation in the owning volume's local space.
---@return Quaternion
function VoxelConstraint:GetRotation() end

--- Endpoint B frame in the other volume's local space.
---@param position Vector3
---@return nil
function VoxelConstraint:SetOtherPosition(position) end

--- Return the constraint anchor in the other volume's local space.
---@return Vector3
function VoxelConstraint:GetOtherPosition() end

--- Set other rotation.
---@param rotation Quaternion
---@return nil
function VoxelConstraint:SetOtherRotation(rotation) end

--- Return the constraint frame rotation in the other volume's local space.
---@return Quaternion
function VoxelConstraint:GetOtherRotation() end

--- Move both local frame origins to the same world-space point without changing their axes.
---@param position Vector3
---@return nil
function VoxelConstraint:SetWorldPosition(position) end

--- Return the constraint anchor in world space.
---@return Vector3
function VoxelConstraint:GetWorldPosition() end

--- Disable contacts between the two endpoint members while this constraint exists.
---@param disable boolean
---@return nil
function VoxelConstraint:SetDisableCollision(disable) end

--- Return true if contacts between the endpoint volumes are disabled.
---@return boolean
function VoxelConstraint:GetDisableCollision() end

--- Drive a hinge at degrees per second. maxTorque <= 0 disables the motor.
---@param targetDegreesPerSecond number
---@param maxTorque number
---@return nil
function VoxelConstraint:SetAngularMotorVelocity(targetDegreesPerSecond, maxTorque) end

--- Drive a slider at metres per second. maxForce <= 0 disables the motor.
---@param targetMetersPerSecond number
---@param maxForce number
---@return nil
function VoxelConstraint:SetLinearMotorVelocity(targetMetersPerSecond, maxForce) end

--- Drive a hinge toward a periodic angle in degrees, normalized before applying limits.
--- maxTorque <= 0 disables the servo; maxSpeedDegreesPerSecond <= 0 removes the explicit speed limit.
---@param targetAngleDegrees number
---@param maxTorque number
---@param maxSpeedDegreesPerSecond number
---@return nil
function VoxelConstraint:SetServo(targetAngleDegrees, maxTorque, maxSpeedDegreesPerSecond) end

--- Disable the explicit motor. An enabled slider spring remains active.
---@return nil
function VoxelConstraint:DisableMotor() end

--- Set max friction force.
---@param force number
---@return nil
function VoxelConstraint:SetMaxFrictionForce(force) end

--- Return max friction force.
---@return number
function VoxelConstraint:GetMaxFrictionForce() end

--- Set max friction torque.
---@param torque number
---@return nil
function VoxelConstraint:SetMaxFrictionTorque(torque) end

--- Return max friction torque.
---@return number
function VoxelConstraint:GetMaxFrictionTorque() end

--- Set hinge stops in degrees. minimum >= maximum removes the limits.
---@param minimumDegrees number
---@param maximumDegrees number
---@return nil
function VoxelConstraint:SetAngularLimits(minimumDegrees, maximumDegrees) end

--- Set slider stops in metres. minimum >= maximum removes the limits.
---@param minimumMeters number
---@param maximumMeters number
---@return nil
function VoxelConstraint:SetLinearLimits(minimumMeters, maximumMeters) end

--- Configure a slider spring in physical units. This setting is retained but inactive for non-slider constraints.
---@param restPositionMeters number
---@param stiffnessNewtonsPerMeter number
---@param dampingNewtonSecondsPerMeter number
---@return nil
function VoxelConstraint:SetLinearSpring(restPositionMeters, stiffnessNewtonsPerMeter, dampingNewtonSecondsPerMeter) end

--- Disable the slider spring without changing the authored spring values.
---@return nil
function VoxelConstraint:ClearLinearSpring() end

--- Return true if the slider spring is enabled.
---@return boolean
function VoxelConstraint:HasLinearSpring() end

--- Return the slider spring rest position in metres.
---@return number
function VoxelConstraint:GetLinearSpringRestPosition() end

--- Return the slider spring stiffness in newtons per metre.
---@return number
function VoxelConstraint:GetLinearSpringStiffness() end

--- Return the slider spring damping in newton-seconds per metre.
---@return number
function VoxelConstraint:GetLinearSpringDamping() end

--- Apply damping around the constraint axis without damping the other angular axes.
---@param damping number
---@param maxTorque? number
---@return nil
function VoxelConstraint:SetAxisAngularDamping(damping, maxTorque) end

--- Return axis angular damping.
---@return number
function VoxelConstraint:GetAxisAngularDamping() end

--- Return axis angular damping max torque.
---@return number
function VoxelConstraint:GetAxisAngularDampingMaxTorque() end

--- Override solver velocity steps for this constraint's physics island. Values are clamped to 0..255;
--- zero uses the world default.
---@param steps integer
---@return nil
function VoxelConstraint:SetSolverVelocitySteps(steps) end

--- Return the solver velocity-step override. Zero uses the world default.
---@return integer
function VoxelConstraint:GetSolverVelocitySteps() end

--- Override solver position steps for this constraint's physics island. Values are clamped to 0..255;
--- zero uses the world default.
---@param steps integer
---@return nil
function VoxelConstraint:SetSolverPositionSteps(steps) end

--- Return the solver position-step override. Zero uses the world default.
---@return integer
function VoxelConstraint:GetSolverPositionSteps() end

--- Return angular limit min.
---@return number
function VoxelConstraint:GetAngularLimitMin() end

--- Return angular limit max.
---@return number
function VoxelConstraint:GetAngularLimitMax() end

--- Return linear limit min.
---@return number
function VoxelConstraint:GetLinearLimitMin() end

--- Return linear limit max.
---@return number
function VoxelConstraint:GetLinearLimitMax() end

--- (Re)create the solver joint from current settings. Returns false when either volume
--- has no body yet — ApplyAttributes then queues a retry on the world.
---@return boolean
function VoxelConstraint:Rebuild() end

--- Return true if the runtime constraint has been created.
---@return boolean
function VoxelConstraint:IsBuilt() end

--- True while both endpoints resolve to the same assembly body. The persisted
--- settings are kept and rebuilt automatically after either endpoint detaches.
---@return boolean
function VoxelConstraint:IsSuspended() end

--- Live joint state for gameplay (arm angle readouts).
---@return number
function VoxelConstraint:GetHingeAngle() end

--- Return slider position.
---@return number
function VoxelConstraint:GetSliderPosition() end

--- Return the average world-space force applied to endpoint A during the last solver step, in newtons.
--- Return zero when the runtime constraint was not active in that step.
---@return Vector3
function VoxelConstraint:GetReactionForce() end

--- Return the average pure world-space torque applied to endpoint A during the last solver step, in newton-metres.
--- The value excludes torque induced by the constraint force's offset from the body centre of mass.
---@return Vector3
function VoxelConstraint:GetReactionTorque() end

