---@meta

--- Auto-generated from Graphics/VertexBuffer

---@class VertexBuffer : Object
---@overload fun(): VertexBuffer
---@field shadowed boolean
---@field dynamic boolean
---@field vertexCount integer
---@field vertexSize integer
---@field elementMask integer
VertexBuffer = {}

---@return VertexBuffer
function VertexBuffer.new() end

---@param enable boolean
---@return nil
function VertexBuffer:SetShadowed(enable) end

---@param vertexCount integer
---@param elements VertexElement[]
---@param dynamic? boolean
---@return boolean
function VertexBuffer:SetSize(vertexCount, elements, dynamic) end

---@param vertexCount integer
---@param elementMask integer
---@param dynamic? boolean
---@return boolean
function VertexBuffer:SetSize(vertexCount, elementMask, dynamic) end

---@param data VectorBuffer
---@return boolean
function VertexBuffer:SetData(data) end

---@param data VectorBuffer
---@param start integer
---@param count integer
---@param discard? boolean
---@return boolean
function VertexBuffer:SetDataRange(data, start, count, discard) end

---@return VectorBuffer
function VertexBuffer:GetData() end

---@return boolean
function VertexBuffer:IsShadowed() end

---@return boolean
function VertexBuffer:IsDynamic() end

---@return integer
function VertexBuffer:GetVertexCount() end

---@return integer
function VertexBuffer:GetVertexSize() end

---@return VertexElement[]
function VertexBuffer:GetElements() end

---@param semantic VertexElementSemantic
---@param index? number -- unsigned char
---@return boolean
function VertexBuffer:HasElement(semantic, index) end

---@param type VertexElementType
---@param semantic VertexElementSemantic
---@param index? number -- unsigned char
---@return boolean
function VertexBuffer:HasElement(type, semantic, index) end

---@param semantic VertexElementSemantic
---@param index? number -- unsigned char
---@return integer
function VertexBuffer:GetElementOffset(semantic, index) end

---@param type VertexElementType
---@param semantic VertexElementSemantic
---@param index? number -- unsigned char
---@return integer
function VertexBuffer:GetElementOffset(type, semantic, index) end

---@return integer
function VertexBuffer:GetElementMask() end

