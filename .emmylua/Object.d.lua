---@meta

--- Auto-generated from Core/Object

---@class Object : RefCounted
---@field type StringHash|string
---@field typeName string
---@field category string
Object = {}

---@return StringHash|string
function Object:GetType() end

---@return string
function Object:GetTypeName() end

---@return string
function Object:GetCategory() end

---@param block boolean
---@return nil
function Object:SetBlockEvents(block) end

---@return boolean
function Object:GetBlockEvents() end

---@return nil
function Object:Dispose() end

---@param eventName string
---@param eventData? VariantMap
---@return nil
function Object:SendEvent(eventName, eventData) end

---@param eventName string
---@return boolean
function Object:HasSubscribedToEvent(eventName) end

---@param sender Object
---@param eventName string
---@return boolean
function Object:HasSubscribedToEvent(sender, eventName) end

