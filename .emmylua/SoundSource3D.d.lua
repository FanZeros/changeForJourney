---@meta

--- Auto-generated from Audio/SoundSource3D

---@class SoundSource3D : SoundSource
---@field nearDistance number
---@field farDistance number
---@field innerAngle number
---@field outerAngle number
---@field rolloffFactor number
SoundSource3D = {}

---@param nearDistance number
---@param farDistance number
---@param rolloffFactor number
---@return nil
function SoundSource3D:SetDistanceAttenuation(nearDistance, farDistance, rolloffFactor) end

---@param innerAngle number
---@param outerAngle number
---@return nil
function SoundSource3D:SetAngleAttenuation(innerAngle, outerAngle) end

---@param distance number
---@return nil
function SoundSource3D:SetNearDistance(distance) end

---@param distance number
---@return nil
function SoundSource3D:SetFarDistance(distance) end

---@param angle number
---@return nil
function SoundSource3D:SetInnerAngle(angle) end

---@param angle number
---@return nil
function SoundSource3D:SetOuterAngle(angle) end

---@param factor number
---@return nil
function SoundSource3D:SetRolloffFactor(factor) end

---@return nil
function SoundSource3D:CalculateAttenuation() end

---@return number
function SoundSource3D:GetNearDistance() end

---@return number
function SoundSource3D:GetFarDistance() end

---@return number
function SoundSource3D:GetInnerAngle() end

---@return number
function SoundSource3D:GetOuterAngle() end

---@return number
function SoundSource3D:RollAngleoffFactor() end

