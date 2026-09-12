---@meta

--- Auto-generated from VoxelPhysics/VoxelRollingContact

---@class VoxelRollingContact : Component
---@field volume VoxelVolume
---@field active boolean
---@field sidewallFriction number
---@field nonSupportFriction number
---@field rollingResistance number
---@field supportContactCount integer
---@field nonSupportContactCount integer
---@field sidewallContactCount integer
---@field normalLoad number
---@field longitudinalSlipRatio number
---@field lateralSlipAngle number
---@field longitudinalForce number
---@field lateralForce number
---@field combinedGripUsage number
---@field supportNormalDot number
VoxelRollingContact = {}

--- Return the sibling volume whose contacts are decorated.
---@return VoxelVolume
function VoxelRollingContact:GetVolume() end

--- Return true while an enabled component has a live cylindrical volume body.
---@return boolean
function VoxelRollingContact:IsActive() end

--- Set longitudinal grip: static/peak capacity through peak slip, then high-slip plateau.
---@param peakSlipRatio number
---@param peakFriction number
---@param slideSlipRatio number
---@param slideFriction number
---@return nil
function VoxelRollingContact:SetLongitudinalGrip(peakSlipRatio, peakFriction, slideSlipRatio, slideFriction) end

---@return number
function VoxelRollingContact:GetLongitudinalPeakSlipRatio() end

---@return number
function VoxelRollingContact:GetLongitudinalPeakFriction() end

---@return number
function VoxelRollingContact:GetLongitudinalSlideSlipRatio() end

---@return number
function VoxelRollingContact:GetLongitudinalSlideFriction() end

--- Set lateral grip in degrees: static/peak capacity through peak angle, then slide plateau.
---@param peakSlipAngleDegrees number
---@param peakFriction number
---@param slideSlipAngleDegrees number
---@param slideFriction number
---@return nil
function VoxelRollingContact:SetLateralGrip(peakSlipAngleDegrees, peakFriction, slideSlipAngleDegrees, slideFriction) end

---@return number
function VoxelRollingContact:GetLateralPeakSlipAngle() end

---@return number
function VoxelRollingContact:GetLateralPeakFriction() end

---@return number
function VoxelRollingContact:GetLateralSlideSlipAngle() end

---@return number
function VoxelRollingContact:GetLateralSlideFriction() end

--- Override sidewall friction, or reset it to inherit ordinary volume friction.
---@param friction number
---@return nil
function VoxelRollingContact:SetSidewallFriction(friction) end

---@return nil
function VoxelRollingContact:ResetSidewallFriction() end

---@return number
function VoxelRollingContact:GetSidewallFriction() end

--- Override non-support friction, or reset it to inherit ordinary volume friction.
---@param friction number
---@return nil
function VoxelRollingContact:SetNonSupportFriction(friction) end

---@return nil
function VoxelRollingContact:ResetNonSupportFriction() end

---@return number
function VoxelRollingContact:GetNonSupportFriction() end

--- Set support-normal blend range as dot products against gravity-up.
---@param noGripDot number
---@param fullGripDot number
---@return nil
function VoxelRollingContact:SetSupportRange(noGripDot, fullGripDot) end

---@return number
function VoxelRollingContact:GetNoGripDot() end

---@return number
function VoxelRollingContact:GetFullGripDot() end

--- Set dimensionless rolling-resistance coefficient.
---@param coefficient number
---@return nil
function VoxelRollingContact:SetRollingResistance(coefficient) end

---@return number
function VoxelRollingContact:GetRollingResistance() end

--- Previous completed physics-step telemetry.
---@return boolean
function VoxelRollingContact:HasSupport() end

---@return integer
function VoxelRollingContact:GetSupportContactCount() end

---@return integer
function VoxelRollingContact:GetNonSupportContactCount() end

---@return integer
function VoxelRollingContact:GetSidewallContactCount() end

---@return number
function VoxelRollingContact:GetNormalLoad() end

---@return number
function VoxelRollingContact:GetLongitudinalSlipRatio() end

---@return number
function VoxelRollingContact:GetLateralSlipAngle() end

---@return number
function VoxelRollingContact:GetLongitudinalForce() end

---@return number
function VoxelRollingContact:GetLateralForce() end

---@return number
function VoxelRollingContact:GetCombinedGripUsage() end

---@return number
function VoxelRollingContact:GetSupportNormalDot() end

