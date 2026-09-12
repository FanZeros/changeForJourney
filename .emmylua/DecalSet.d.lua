---@meta

--- Auto-generated from Graphics/DecalSet

---@class DecalSet : Drawable
---@field material Material
---@field numDecals integer
---@field numVertices integer
---@field numIndices integer
---@field maxVertices integer
---@field maxIndices integer
---@field optimizeBufferSize boolean
DecalSet = {}

---@param material Material
---@return nil
function DecalSet:SetMaterial(material) end

---@param num integer
---@return nil
function DecalSet:SetMaxVertices(num) end

---@param num integer
---@return nil
function DecalSet:SetMaxIndices(num) end

---@param enable boolean
---@return nil
function DecalSet:SetOptimizeBufferSize(enable) end

---@param target Drawable
---@param worldPosition Vector3
---@param worldRotation Quaternion
---@param size number
---@param aspectRatio number
---@param depth number
---@param topLeftUV Vector2
---@param bottomRightUV Vector2
---@param timeToLive? number
---@param normalCutoff? number
---@param subGeometry? integer
---@return boolean
function DecalSet:AddDecal(target, worldPosition, worldRotation, size, aspectRatio, depth, topLeftUV, bottomRightUV, timeToLive, normalCutoff, subGeometry) end

---@param num integer
---@return nil
function DecalSet:RemoveDecals(num) end

---@return nil
function DecalSet:RemoveAllDecals() end

---@return Material
function DecalSet:GetMaterial() end

---@return integer
function DecalSet:GetNumDecals() end

---@return integer
function DecalSet:GetNumVertices() end

---@return integer
function DecalSet:GetNumIndices() end

---@return integer
function DecalSet:GetMaxVertices() end

---@return integer
function DecalSet:GetMaxIndices() end

---@return boolean
function DecalSet:GetOptimizeBufferSize() end

