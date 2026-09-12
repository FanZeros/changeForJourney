---@meta

--- Auto-generated from Graphics/Terrain

---@class Terrain : Component
---@field patchSize integer
---@field spacing Vector3
---@field numVertices IntVector2
---@field numPatches IntVector2
---@field maxLodLevels integer
---@field occlusionLodLevel integer
---@field smoothing boolean
---@field heightMap Image
---@field material Material
---@field northNeighbor Terrain
---@field southNeighbor Terrain
---@field westNeighbor Terrain
---@field eastNeighbor Terrain
---@field drawDistance number
---@field shadowDistance number
---@field lodBias number
---@field viewMask integer
---@field lightMask integer
---@field shadowMask integer
---@field zoneMask integer
---@field maxLights integer
---@field visible boolean
---@field castShadows boolean
---@field occluder boolean
---@field occludee boolean
Terrain = {}

---@param size integer
---@return nil
function Terrain:SetPatchSize(size) end

---@param spacing Vector3
---@return nil
function Terrain:SetSpacing(spacing) end

---@param levels integer
---@return nil
function Terrain:SetMaxLodLevels(levels) end

---@param level integer
---@return nil
function Terrain:SetOcclusionLodLevel(level) end

---@param enable boolean
---@return nil
function Terrain:SetSmoothing(enable) end

---@param image Image
---@return boolean
function Terrain:SetHeightMap(image) end

---@param material Material
---@return nil
function Terrain:SetMaterial(material) end

---@param north Terrain
---@return nil
function Terrain:SetNorthNeighbor(north) end

---@param south Terrain
---@return nil
function Terrain:SetSouthNeighbor(south) end

---@param west Terrain
---@return nil
function Terrain:SetWestNeighbor(west) end

---@param east Terrain
---@return nil
function Terrain:SetEastNeighbor(east) end

---@param north Terrain
---@param south Terrain
---@param west Terrain
---@param east Terrain
---@return nil
function Terrain:SetNeighbors(north, south, west, east) end

---@param distance number
---@return nil
function Terrain:SetDrawDistance(distance) end

---@param distance number
---@return nil
function Terrain:SetShadowDistance(distance) end

---@param bias number
---@return nil
function Terrain:SetLodBias(bias) end

---@param mask integer
---@return nil
function Terrain:SetViewMask(mask) end

---@param mask integer
---@return nil
function Terrain:SetLightMask(mask) end

---@param mask integer
---@return nil
function Terrain:SetShadowMask(mask) end

---@param mask integer
---@return nil
function Terrain:SetZoneMask(mask) end

---@param num integer
---@return nil
function Terrain:SetMaxLights(num) end

---@param enable boolean
---@return nil
function Terrain:SetCastShadows(enable) end

---@param enable boolean
---@return nil
function Terrain:SetOccluder(enable) end

---@param enable boolean
---@return nil
function Terrain:SetOccludee(enable) end

---@return nil
function Terrain:ApplyHeightMap() end

---@return integer
function Terrain:GetPatchSize() end

---@return Vector3
function Terrain:GetSpacing() end

---@return IntVector2
function Terrain:GetNumVertices() end

---@return IntVector2
function Terrain:GetNumPatches() end

---@return integer
function Terrain:GetMaxLodLevels() end

---@return integer
function Terrain:GetOcclusionLodLevel() end

---@return boolean
function Terrain:GetSmoothing() end

---@return Image
function Terrain:GetHeightMap() end

---@return Material
function Terrain:GetMaterial() end

---@return Terrain
function Terrain:GetNorthNeighbor() end

---@return Terrain
function Terrain:GetSouthNeighbor() end

---@return Terrain
function Terrain:GetWestNeighbor() end

---@return Terrain
function Terrain:GetEastNeighbor() end

---@param index integer
---@return TerrainPatch
function Terrain:GetPatch(index) end

---@param x integer
---@param z integer
---@return TerrainPatch
function Terrain:GetPatch(x, z) end

---@param x integer
---@param z integer
---@return TerrainPatch
function Terrain:GetNeighborPatch(x, z) end

---@param worldPosition Vector3
---@return number
function Terrain:GetHeight(worldPosition) end

---@param worldPosition Vector3
---@return Vector3
function Terrain:GetNormal(worldPosition) end

---@param worldPosition Vector3
---@return IntVector2
function Terrain:WorldToHeightMap(worldPosition) end

---@param pixelPosition IntVector2
---@return Vector3
function Terrain:HeightMapToWorld(pixelPosition) end

---@return number[]
function Terrain:GetHeightData() end

---@return number
function Terrain:GetDrawDistance() end

---@return number
function Terrain:GetShadowDistance() end

---@return number
function Terrain:GetLodBias() end

---@return integer
function Terrain:GetViewMask() end

---@return integer
function Terrain:GetLightMask() end

---@return integer
function Terrain:GetShadowMask() end

---@return integer
function Terrain:GetZoneMask() end

---@return integer
function Terrain:GetMaxLights() end

---@return boolean
function Terrain:IsVisible() end

---@return boolean
function Terrain:GetCastShadows() end

---@return boolean
function Terrain:IsOccluder() end

---@return boolean
function Terrain:IsOccludee() end

