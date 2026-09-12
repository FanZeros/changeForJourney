---@meta

--- Auto-generated from VoxelPhysics/VoxelVehicle

---@class VoxelVehicle : Component
---@field maxDriveForce number
---@field maxSteerAngle number
---@field steerSpeedFalloff number
---@field maxSpeed number
---@field grip number
---@field rollingResistance number
---@field skidSteer boolean
---@field forwardSpeed number
---@field wheelCount integer
VoxelVehicle = {}

--- Add a suspension corner (chassis-local attach point). Wheels are usually authored
--- once at assembly; the array serializes with the component.
---@param attachLocal Vector3
---@param radius number
---@param restLength number
---@param stiffness number
---@param damping number
---@param steers boolean
---@param drives boolean
---@return nil
function VoxelVehicle:AddWheel(attachLocal, radius, restLength, stiffness, damping, steers, drives) end

--- Clear wheels.
---@return nil
function VoxelVehicle:ClearWheels() end

--- Return wheel count.
---@return integer
function VoxelVehicle:GetWheelCount() end

--- Driver intent for the coming steps: throttle and steer in [-1, 1], brake in [0, 1]. Call
--- once per rendered frame after adding the wheels at assembly time.
---@param throttle number
---@param steer number
---@param brake number
---@return nil
function VoxelVehicle:SetInput(throttle, steer, brake) end

--- Peak drive force per driven wheel (N) and max steering lock (degrees).
---@param force number
---@return nil
function VoxelVehicle:SetMaxDriveForce(force) end

--- Return max drive force.
---@return number
function VoxelVehicle:GetMaxDriveForce() end

--- Set maximum steering angle in degrees.
---@param degrees number
---@return nil
function VoxelVehicle:SetMaxSteerAngle(degrees) end

--- Return maximum steering angle in degrees.
---@return number
function VoxelVehicle:GetMaxSteerAngle() end

--- Speed-sensitive steering falloff (per m/s): the effective steer angle is
--- maxSteerAngle / (1 + |forwardSpeed| * falloff) — full lock when parking, less at
--- speed so a fast turn stays an arc instead of a slide. 0 disables, default 0.08.
---@param perMs number
---@return nil
function VoxelVehicle:SetSteerSpeedFalloff(perMs) end

--- Return steer speed falloff.
---@return number
function VoxelVehicle:GetSteerSpeedFalloff() end

--- Top speed (m/s): drive force fades linearly to zero as forward speed approaches it;
--- braking by opposite throttle keeps full authority. 0 = unlimited (default), but with
--- no aerodynamic drag a constant drive force pushes even a bulldozer to highway speed. A
--- deliberately low cap is part of a heavy machine's handling model.
---@param metersPerSecond number
---@return nil
function VoxelVehicle:SetMaxSpeed(metersPerSecond) end

--- Return max speed.
---@return number
function VoxelVehicle:GetMaxSpeed() end

--- Tyre grip: lateral slip is cancelled up to this fraction per step (0-1). Lower drifts.
---@param grip number
---@return nil
function VoxelVehicle:SetGrip(grip) end

--- Return grip.
---@return number
function VoxelVehicle:GetGrip() end

--- Rolling resistance on coasting wheels: this fraction of the roll speed is cancelled
--- per step (default 0.02 ≈ 1.2/s at 60 Hz — what stops an idle car). Aircraft landing
--- gear must set it much lower or the takeoff roll saturates at walking pace: 0.02
--- per step on free-rolling gear eats a fighter's entire thrust by ~6 m/s (measured).
---@param perStep number
---@return nil
function VoxelVehicle:SetRollingResistance(perStep) end

--- Return rolling resistance.
---@return number
function VoxelVehicle:GetRollingResistance() end

--- Ground speed along the chassis forward axis, m/s (telemetry).
---@return number
function VoxelVehicle:GetForwardSpeed() end

--- Per-wheel suspension state, refreshed every solver step. What wheel VISUALS need:
--- the wheel centre sits (restLength - compression) below the attach point.
---@param index integer
---@return number
function VoxelVehicle:GetWheelCompression(index) end

--- Return true if the wheel suspension ray is supported.
---@param index integer
---@return boolean
function VoxelVehicle:IsWheelGrounded(index) end

--- Tank-style differential steering for tracked vehicles. Steer input scales the drive
--- force per side instead of yawing wheels: full steer with zero throttle pivots in
--- place. Front-wheel yaw steering is hopeless on a six-wheel tracked layout — the four
--- straight wheels' lateral grip simply out-votes it.
---@param enable boolean
---@return nil
function VoxelVehicle:SetSkidSteer(enable) end

--- Return true if differential skid steering is enabled.
---@return boolean
function VoxelVehicle:IsSkidSteer() end

--- Per-wheel steering authority in [-1, 1]; negative counter-steers (forklift rear
--- axle). AddWheel's bool is shorthand for 1 or 0.
---@param index integer
---@param factor number
---@return nil
function VoxelVehicle:SetWheelSteerFactor(index, factor) end

--- Return wheel steer factor.
---@param index integer
---@return number
function VoxelVehicle:GetWheelSteerFactor(index) end

--- World-space ground contact of the wheel's ray (valid while grounded). Wheel visuals
--- that sit radius above this point kiss the ground at ANY body roll or pitch.
---@param index integer
---@return Vector3
function VoxelVehicle:GetWheelContactPoint(index) end

--- Last solver-step steer angle in degrees for this wheel (0 if skid-steering).
---@param index integer
---@return number
function VoxelVehicle:GetWheelSteerAngle(index) end

