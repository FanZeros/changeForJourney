---@meta

--- Auto-generated from Physics/RaycastVehicle

---@class RaycastVehicle : LogicComponent
---@overload fun(): RaycastVehicle
---@field RIGHT_UP_FORWARD IntVector3
---@field RIGHT_FORWARD_UP IntVector3
---@field UP_FORWARD_RIGHT IntVector3
---@field UP_RIGHT_FORWARD IntVector3
---@field FORWARD_RIGHT_UP IntVector3
---@field FORWARD_UP_RIGHT IntVector3
RaycastVehicle = {}

---@return RaycastVehicle
function RaycastVehicle.new() end

---@param context Context
---@return nil
function RaycastVehicle:RegisterObject(context) end

---@return nil
function RaycastVehicle:ApplyAttributes() end

---@param wheelNode Node
---@param wheelDirection Vector3
---@param wheelAxle Vector3
---@param restLength number
---@param wheelRadius number
---@param frontWheel boolean
---@return nil
function RaycastVehicle:AddWheel(wheelNode, wheelDirection, wheelAxle, restLength, wheelRadius, frontWheel) end

---@return nil
function RaycastVehicle:ResetSuspension() end

---@param wheel integer
---@param interpolated boolean
---@return nil
function RaycastVehicle:UpdateWheelTransform(wheel, interpolated) end

---@param wheel integer
---@param steeringValue number
---@return nil
function RaycastVehicle:SetSteeringValue(wheel, steeringValue) end

---@param wheel integer
---@param stiffness number
---@return nil
function RaycastVehicle:SetWheelSuspensionStiffness(wheel, stiffness) end

---@param wheel integer
---@param damping number
---@return nil
function RaycastVehicle:SetWheelDampingRelaxation(wheel, damping) end

---@param wheel integer
---@param compression number
---@return nil
function RaycastVehicle:SetWheelDampingCompression(wheel, compression) end

---@param wheel integer
---@param slip number
---@return nil
function RaycastVehicle:SetWheelFrictionSlip(wheel, slip) end

---@param wheel integer
---@param rollInfluence number
---@return nil
function RaycastVehicle:SetWheelRollInfluence(wheel, rollInfluence) end

---@param wheel integer
---@param force number
---@return nil
function RaycastVehicle:SetEngineForce(wheel, force) end

---@param wheel integer
---@param force number
---@return nil
function RaycastVehicle:SetBrake(wheel, force) end

---@param wheel integer
---@param wheelRadius number
---@return nil
function RaycastVehicle:SetWheelRadius(wheel, wheelRadius) end

---@return nil
function RaycastVehicle:ResetWheels() end

---@param wheel integer
---@param length number
---@return nil
function RaycastVehicle:SetWheelRestLength(wheel, length) end

---@param wheel integer
---@param factor number
---@return nil
function RaycastVehicle:SetWheelSkidInfo(wheel, factor) end

---@param wheel integer
---@return boolean
function RaycastVehicle:WheelIsGrounded(wheel) end

---@param wheel integer
---@param maxSuspensionTravel number
---@return nil
function RaycastVehicle:SetMaxSuspensionTravel(wheel, maxSuspensionTravel) end

---@param wheel integer
---@param direction Vector3
---@return nil
function RaycastVehicle:SetWheelDirection(wheel, direction) end

---@param wheel integer
---@param axle Vector3
---@return nil
function RaycastVehicle:SetWheelAxle(wheel, axle) end

---@param speed number
---@return nil
function RaycastVehicle:SetMaxSideSlipSpeed(speed) end

---@param wheel integer
---@param skid number
---@return nil
function RaycastVehicle:SetWheelSkidInfoCumulative(wheel, skid) end

---@param rpm number
---@return nil
function RaycastVehicle:SetInAirRPM(rpm) end

---@param coordinateSystem? IntVector3
---@return nil
function RaycastVehicle:SetCoordinateSystem(coordinateSystem) end

---@return nil
function RaycastVehicle:Init() end

---@param wheel integer
---@return Vector3
function RaycastVehicle:GetWheelPosition(wheel) end

---@param wheel integer
---@return Quaternion
function RaycastVehicle:GetWheelRotation(wheel) end

---@param wheel integer
---@return Vector3
function RaycastVehicle:GetWheelConnectionPoint(wheel) end

---@return integer
function RaycastVehicle:GetNumWheels() end

---@param wheel integer
---@return number
function RaycastVehicle:GetSteeringValue(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelSuspensionStiffness(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelDampingRelaxation(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelDampingCompression(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelFrictionSlip(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelRollInfluence(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetEngineForce(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetBrake(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelRadius(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelRestLength(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelSkidInfo(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetMaxSuspensionTravel(wheel) end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelSideSlipSpeed(wheel) end

---@return number
function RaycastVehicle:GetMaxSideSlipSpeed() end

---@param wheel integer
---@return number
function RaycastVehicle:GetWheelSkidInfoCumulative(wheel) end

---@param wheel integer
---@return Vector3
function RaycastVehicle:GetWheelDirection(wheel) end

---@param wheel integer
---@return boolean
function RaycastVehicle:IsFrontWheel(wheel) end

---@param wheel integer
---@return Vector3
function RaycastVehicle:GetWheelAxle(wheel) end

---@param wheel integer
---@return Vector3
function RaycastVehicle:GetContactPosition(wheel) end

---@param wheel integer
---@return Vector3
function RaycastVehicle:GetContactNormal(wheel) end

---@return number
function RaycastVehicle:GetInAirRPM() end

---@return IntVector3
function RaycastVehicle:GetCoordinateSystem() end

