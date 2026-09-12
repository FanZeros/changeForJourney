---@meta

--- Auto-generated from Animation/AimOffset

---@class AimOffset : Component
---@field numBones integer
---@field targetPitch number
---@field targetYaw number
---@field maxPitch number
---@field maxYaw number
---@field smoothSpeed number
---@field yawCompensation number
---@field stabilize boolean
---@field stabilizeParentCount integer
---@field enabled boolean
AimOffset = {}

---@param boneName string
---@param pitchWeight number
---@param yawWeight number
---@return nil
function AimOffset:AddBone(boneName, pitchWeight, yawWeight) end

---@param boneName string
---@param weight number
---@return nil
function AimOffset:AddBone(boneName, weight) end

---@param boneName string
---@return nil
function AimOffset:RemoveBone(boneName) end

---@return nil
function AimOffset:ClearBones() end

---@return integer
function AimOffset:GetNumBones() end

---@param pitch number
---@return nil
function AimOffset:SetTargetPitch(pitch) end

---@param yaw number
---@return nil
function AimOffset:SetTargetYaw(yaw) end

---@param pitch number
---@param yaw number
---@return nil
function AimOffset:SetTargetAngles(pitch, yaw) end

---@return number
function AimOffset:GetTargetPitch() end

---@return number
function AimOffset:GetTargetYaw() end

---@param maxPitch number
---@return nil
function AimOffset:SetMaxPitch(maxPitch) end

---@param maxYaw number
---@return nil
function AimOffset:SetMaxYaw(maxYaw) end

---@return number
function AimOffset:GetMaxPitch() end

---@return number
function AimOffset:GetMaxYaw() end

---@param speed number
---@return nil
function AimOffset:SetSmoothSpeed(speed) end

---@return number
function AimOffset:GetSmoothSpeed() end

---@param compensation number
---@return nil
function AimOffset:SetYawCompensation(compensation) end

---@return number
function AimOffset:GetYawCompensation() end

---@param stabilize boolean
---@return nil
function AimOffset:SetStabilize(stabilize) end

---@return boolean
function AimOffset:IsStabilize() end

---@param count integer
---@return nil
function AimOffset:SetStabilizeParentCount(count) end

---@return integer
function AimOffset:GetStabilizeParentCount() end

---@param enabled boolean
---@return nil
function AimOffset:SetEnabled(enabled) end

---@return boolean
function AimOffset:IsEnabled() end

---@return nil
function AimOffset:DebugPrintBones() end

