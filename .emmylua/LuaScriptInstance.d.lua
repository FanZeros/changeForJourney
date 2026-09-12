---@meta

--- Auto-generated from LuaScript/LuaScriptInstance

---@class LuaScriptInstance : Component
---@field scriptFile LuaFile
---@field scriptObjectType string
LuaScriptInstance = {}

---@param scriptObjectType string
---@return boolean
function LuaScriptInstance:CreateObject(scriptObjectType) end

---@param scriptFile LuaFile
---@param scriptObjectType string
---@return boolean
function LuaScriptInstance:CreateObject(scriptFile, scriptObjectType) end

---@param scriptFile LuaFile
---@return nil
function LuaScriptInstance:SetScriptFile(scriptFile) end

---@param scriptObjectType string
---@return nil
function LuaScriptInstance:SetScriptObjectType(scriptObjectType) end

-- Method SubscribeToEvent is not supported (uses void* pointer)

-- Method SubscribeToEvent is not supported (uses void* pointer)

---@param eventName string
---@return nil
function LuaScriptInstance:UnsubscribeFromEvent(eventName) end

---@param sender Object
---@param eventName string
---@return nil
function LuaScriptInstance:UnsubscribeFromEvent(sender, eventName) end

---@param sender Object
---@return nil
function LuaScriptInstance:UnsubscribeFromEvents(sender) end

---@return nil
function LuaScriptInstance:UnsubscribeFromAllEvents() end

---@param exceptionNames string[]
---@return nil
function LuaScriptInstance:UnsubscribeFromAllEventsExcept(exceptionNames) end

---@param eventName string
---@return boolean
function LuaScriptInstance:HasSubscribedToEvent(eventName) end

---@param sender Object
---@param eventName string
---@return boolean
function LuaScriptInstance:HasSubscribedToEvent(sender, eventName) end

---@return LuaFile
function LuaScriptInstance:GetScriptFile() end

---@return string
function LuaScriptInstance:GetScriptObjectType() end

