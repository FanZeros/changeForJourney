---@meta

--- Auto-generated from Graphics/Geometry

---@class Geometry : Object
---@overload fun(): Geometry
---@field numVertexBuffers integer
---@field indexBuffer IndexBuffer
---@field primitiveType PrimitiveType
---@field indexStart integer
---@field indexCount integer
---@field vertexStart integer
---@field vertexCount integer
---@field lodDistance number
---@field empty boolean
Geometry = {}

---@return Geometry
function Geometry.new() end

---@param num integer
---@return boolean
function Geometry:SetNumVertexBuffers(num) end

---@param index integer
---@param buffer VertexBuffer
---@return boolean
function Geometry:SetVertexBuffer(index, buffer) end

---@param buffer IndexBuffer
---@return nil
function Geometry:SetIndexBuffer(buffer) end

---@param type PrimitiveType
---@param indexStart integer
---@param indexCount integer
---@param getUsedVertexRange? boolean
---@return boolean
function Geometry:SetDrawRange(type, indexStart, indexCount, getUsedVertexRange) end

---@param type PrimitiveType
---@param indexStart integer
---@param indexCount integer
---@param vertexStart integer
---@param vertexCount integer
---@param checkIllegal? boolean
---@return boolean
function Geometry:SetDrawRange(type, indexStart, indexCount, vertexStart, vertexCount, checkIllegal) end

---@param distance number
---@return nil
function Geometry:SetLodDistance(distance) end

---@return integer
function Geometry:GetNumVertexBuffers() end

---@param index integer
---@return VertexBuffer
function Geometry:GetVertexBuffer(index) end

---@return IndexBuffer
function Geometry:GetIndexBuffer() end

---@return PrimitiveType
function Geometry:GetPrimitiveType() end

---@return integer
function Geometry:GetIndexStart() end

---@return integer
function Geometry:GetIndexCount() end

---@return integer
function Geometry:GetVertexStart() end

---@return integer
function Geometry:GetVertexCount() end

---@return number
function Geometry:GetLodDistance() end

---@return boolean
function Geometry:IsEmpty() end

