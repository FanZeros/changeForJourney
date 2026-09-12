---@meta

--- Auto-generated from Graphics/DepthOfField

---@alias DOFQuality
---| integer # DOFQuality enum values

---@type DOFQuality
DOF_QUALITY_LOW = 0
---@type DOFQuality
DOF_QUALITY_MEDIUM = 1
---@type DOFQuality
DOF_QUALITY_HIGH = 2

---@class DepthOfField : Component
---@field enabled boolean
---@field focalDistance number
---@field focalRange number
---@field maxBlur number
---@field quality integer
---@field nearBlurScale number
---@field farBlurScale number
---@field bokehBrightness number
DepthOfField = {}

---@param enabled boolean
---@return nil
function DepthOfField:SetEnabled(enabled) end

---@return boolean
function DepthOfField:IsEnabled() end

---@param distance number
---@return nil
function DepthOfField:SetFocalDistance(distance) end

---@return number
function DepthOfField:GetFocalDistance() end

---@param range number
---@return nil
function DepthOfField:SetFocalRange(range) end

---@return number
function DepthOfField:GetFocalRange() end

---@param worldPos Vector3
---@return nil
function DepthOfField:FocusOnPosition(worldPos) end

---@param node Node
---@return nil
function DepthOfField:FocusOnNode(node) end

---@param blur number
---@return nil
function DepthOfField:SetMaxBlur(blur) end

---@return number
function DepthOfField:GetMaxBlur() end

---@param quality integer
---@return nil
function DepthOfField:SetQuality(quality) end

---@return integer
function DepthOfField:GetQuality() end

---@param scale number
---@return nil
function DepthOfField:SetNearBlurScale(scale) end

---@return number
function DepthOfField:GetNearBlurScale() end

---@param scale number
---@return nil
function DepthOfField:SetFarBlurScale(scale) end

---@return number
function DepthOfField:GetFarBlurScale() end

---@param brightness number
---@return nil
function DepthOfField:SetBokehBrightness(brightness) end

---@return number
function DepthOfField:GetBokehBrightness() end

---@param targetDistance number
---@param duration number
---@return nil
function DepthOfField:TransitionFocalDistance(targetDistance, duration) end

---@return nil
function DepthOfField:ResetToDefaults() end

