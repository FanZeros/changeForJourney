---@meta

--- Auto-generated from Resource/Resource

---@class Resource : Object
---@field name string
---@field nameHash StringHash|string
---@field memoryUse integer
Resource = {}

---@param source Deserializer
---@return boolean
function Resource:Load(source) end

---@param fileName string
---@return boolean
function Resource:Load(fileName) end

---@param dest Serializer
---@return boolean
function Resource:Save(dest) end

---@param fileName string
---@return boolean
function Resource:Save(fileName) end

---@return string
function Resource:GetName() end

---@return StringHash|string
function Resource:GetNameHash() end

---@return integer
function Resource:GetMemoryUse() end


---@class ResourceWithMetadata : Resource
ResourceWithMetadata = {}

---@param name string
---@param value Variant
---@return nil
function ResourceWithMetadata:AddMetadata(name, value) end

---@param name string
---@return nil
function ResourceWithMetadata:RemoveMetadata(name) end

---@return nil
function ResourceWithMetadata:RemoveAllMetadata() end

---@param name string
---@return Variant
function ResourceWithMetadata:GetMetadata(name) end

---@return boolean
function ResourceWithMetadata:HasMetadata() end

