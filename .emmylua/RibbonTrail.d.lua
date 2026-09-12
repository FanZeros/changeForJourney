---@meta

--- Auto-generated from Graphics/RibbonTrail

---@alias TrailType
---| integer # TrailType enum values

---@type TrailType
TT_FACE_CAMERA = 0
---@type TrailType
TT_BONE = 1

---@class RibbonTrail : Drawable
---@field material Material
---@field vertexDistance number
---@field width number
---@field startColor Color
---@field endColor Color
---@field startScale number
---@field endScale number
---@field trailType TrailType
---@field baseVelocity Vector3
---@field sorted boolean
---@field lifetime number
---@field tailColumn integer
---@field emitting boolean
---@field updateInvisible boolean
---@field animationLodBias number
RibbonTrail = {}

---@param material Material
---@return nil
function RibbonTrail:SetMaterial(material) end

---@param length number
---@return nil
function RibbonTrail:SetVertexDistance(length) end

---@param width number
---@return nil
function RibbonTrail:SetWidth(width) end

---@param c Color
---@return nil
function RibbonTrail:SetStartColor(c) end

---@param c Color
---@return nil
function RibbonTrail:SetEndColor(c) end

---@param startScale number
---@return nil
function RibbonTrail:SetStartScale(startScale) end

---@param endScale number
---@return nil
function RibbonTrail:SetEndScale(endScale) end

---@param type TrailType
---@return nil
function RibbonTrail:SetTrailType(type) end

---@param baseVelocity Vector3
---@return nil
function RibbonTrail:SetBaseVelocity(baseVelocity) end

---@param enable boolean
---@return nil
function RibbonTrail:SetSorted(enable) end

---@param time number
---@return nil
function RibbonTrail:SetLifetime(time) end

---@param emitting boolean
---@return nil
function RibbonTrail:SetEmitting(emitting) end

---@param updateInvisible boolean
---@return nil
function RibbonTrail:SetUpdateInvisible(updateInvisible) end

---@param tailColumn integer
---@return nil
function RibbonTrail:SetTailColumn(tailColumn) end

---@param bias number
---@return nil
function RibbonTrail:SetAnimationLodBias(bias) end

---@return nil
function RibbonTrail:Commit() end

---@return Material
function RibbonTrail:GetMaterial() end

---@return number
function RibbonTrail:GetVertexDistance() end

---@return number
function RibbonTrail:GetWidth() end

---@return Color
function RibbonTrail:GetStartColor() end

---@return Color
function RibbonTrail:GetEndColor() end

---@return number
function RibbonTrail:GetStartScale() end

---@return number
function RibbonTrail:GetEndScale() end

---@return TrailType
function RibbonTrail:GetTrailType() end

---@return Vector3
function RibbonTrail:GetBaseVelocity() end

---@return boolean
function RibbonTrail:IsSorted() end

---@return number
function RibbonTrail:GetLifetime() end

---@return integer
function RibbonTrail:GetTailColumn() end

---@return boolean
function RibbonTrail:IsEmitting() end

---@return boolean
function RibbonTrail:GetUpdateInvisible() end

---@return number
function RibbonTrail:GetAnimationLodBias() end

