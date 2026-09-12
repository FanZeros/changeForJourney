---@meta

--- Auto-generated from Scene/Serializable

---@class Serializable : Object
---@field temporary boolean
Serializable = {}

---@param enable boolean
---@return nil
function Serializable:SetTemporary(enable) end

---@return boolean
function Serializable:IsTemporary() end

---@param attributeName string
---@param enable boolean
---@return nil
function Serializable:SetInterceptNetworkUpdate(attributeName, enable) end

---@param attributeName string
---@return boolean
function Serializable:GetInterceptNetworkUpdate(attributeName) end

---@return nil
function Serializable:ApplyAttributes() end

---@param index integer
---@return AttributeInfo
function Serializable:GetAttributeInfo(index) end

---@param index integer
---@param value Variant
---@return boolean
function Serializable:SetAttribute(index, value) end

---@param name string
---@param value Variant
---@return boolean
function Serializable:SetAttribute(name, value) end

---@param index integer
---@return Variant
function Serializable:GetAttribute(index) end

---@param name string
---@return Variant
function Serializable:GetAttribute(name) end

---@param index integer
---@return Variant
function Serializable:GetAttributeDefault(index) end

---@param name string
---@return Variant
function Serializable:GetAttributeDefault(name) end

---@return integer
function Serializable:GetNumAttributes() end

