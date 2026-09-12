---@meta

--- Auto-generated from Graphics/Model

---@class Model : ResourceWithMetadata
---@overload fun(): Model
---@field boundingBox BoundingBox
---@field skeleton Skeleton
---@field numGeometries integer
---@field numMorphs integer
Model = {}

---@return Model
function Model.new() end

---@param cloneName? string
---@return Model
function Model:Clone(cloneName) end

---@param box BoundingBox
---@return nil
function Model:SetBoundingBox(box) end

---@param buffers VertexBuffer[]
---@param morphRangeStarts integer[]
---@param morphRangeCounts integer[]
---@return boolean
function Model:SetVertexBuffers(buffers, morphRangeStarts, morphRangeCounts) end

---@param buffers IndexBuffer[]
---@return boolean
function Model:SetIndexBuffers(buffers) end

---@param num integer
---@return nil
function Model:SetNumGeometries(num) end

---@param index integer
---@param num integer
---@return boolean
function Model:SetNumGeometryLodLevels(index, num) end

---@param index integer
---@param lodLevel integer
---@param geometry Geometry
---@return boolean
function Model:SetGeometry(index, lodLevel, geometry) end

---@param index integer
---@param center Vector3
---@return boolean
function Model:SetGeometryCenter(index, center) end

---@return BoundingBox
function Model:GetBoundingBox() end

---@return Skeleton
function Model:GetSkeleton() end

---@return integer
function Model:GetNumGeometries() end

---@param index integer
---@return integer
function Model:GetNumGeometryLodLevels(index) end

---@param index integer
---@param lodLevel integer
---@return Geometry
function Model:GetGeometry(index, lodLevel) end

---@param index integer
---@return Vector3
function Model:GetGeometryCenter(index) end

---@return integer
function Model:GetNumMorphs() end

---@param name string
---@return ModelMorph
function Model:GetMorph(name) end

---@param nameHash StringHash|string
---@return ModelMorph
function Model:GetMorph(nameHash) end

---@param index integer
---@return ModelMorph
function Model:GetMorph(index) end

---@param bufferIndex integer
---@return integer
function Model:GetMorphRangeStart(bufferIndex) end

---@param bufferIndex integer
---@return integer
function Model:GetMorphRangeCount(bufferIndex) end

