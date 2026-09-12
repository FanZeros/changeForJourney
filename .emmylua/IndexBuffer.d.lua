---@meta

--- Auto-generated from Graphics/IndexBuffer

---@class IndexBuffer : Object
---@overload fun(): IndexBuffer
---@field shadowed boolean
---@field dynamic boolean
---@field indexCount integer
---@field indexSize integer
IndexBuffer = {}

---@return IndexBuffer
function IndexBuffer.new() end

---@param enable boolean
---@return nil
function IndexBuffer:SetShadowed(enable) end

---@param indexCount integer
---@param largeIndices boolean
---@param dynamic? boolean
---@return boolean
function IndexBuffer:SetSize(indexCount, largeIndices, dynamic) end

---@param data VectorBuffer
---@return boolean
function IndexBuffer:SetData(data) end

---@param data VectorBuffer
---@param start integer
---@param count integer
---@param discard? boolean
---@return boolean
function IndexBuffer:SetDataRange(data, start, count, discard) end

---@return VectorBuffer
function IndexBuffer:GetData() end

---@return boolean
function IndexBuffer:IsShadowed() end

---@return boolean
function IndexBuffer:IsDynamic() end

---@return integer
function IndexBuffer:GetIndexCount() end

---@return integer
function IndexBuffer:GetIndexSize() end

