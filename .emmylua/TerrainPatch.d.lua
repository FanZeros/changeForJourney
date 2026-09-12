---@meta

--- Auto-generated from Graphics/TerrainPatch

---@class TerrainPatch : Drawable
---@field geometry Geometry
---@field maxLodGeometry Geometry
---@field occlusionGeometry Geometry
---@field vertexBuffer VertexBuffer
---@field owner Terrain
---@field northPatch TerrainPatch
---@field southPatch TerrainPatch
---@field westPatch TerrainPatch
---@field eastPatch TerrainPatch
---@field boundingBox BoundingBox
---@field coordinates IntVector2
---@field lodLevel integer
TerrainPatch = {}

---@param terrain Terrain
---@return nil
function TerrainPatch:SetOwner(terrain) end

---@param north TerrainPatch
---@param south TerrainPatch
---@param west TerrainPatch
---@param east TerrainPatch
---@return nil
function TerrainPatch:SetNeighbors(north, south, west, east) end

---@param material Material
---@return nil
function TerrainPatch:SetMaterial(material) end

---@param box BoundingBox
---@return nil
function TerrainPatch:SetBoundingBox(box) end

---@param coordinates IntVector2
---@return nil
function TerrainPatch:SetCoordinates(coordinates) end

---@return nil
function TerrainPatch:ResetLod() end

---@return Geometry
function TerrainPatch:GetGeometry() end

---@return Geometry
function TerrainPatch:GetMaxLodGeometry() end

---@return Geometry
function TerrainPatch:GetOcclusionGeometry() end

---@return VertexBuffer
function TerrainPatch:GetVertexBuffer() end

---@return Terrain
function TerrainPatch:GetOwner() end

---@return TerrainPatch
function TerrainPatch:GetNorthPatch() end

---@return TerrainPatch
function TerrainPatch:GetSouthPatch() end

---@return TerrainPatch
function TerrainPatch:GetWestPatch() end

---@return TerrainPatch
function TerrainPatch:GetEastPatch() end

---@return IntVector2
function TerrainPatch:GetCoordinates() end

---@return integer
function TerrainPatch:GetLodLevel() end

