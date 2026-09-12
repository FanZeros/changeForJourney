---@meta

--- Auto-generated from Core/Context

---@class Context
Context = {}

---@return Object
function Context:GetEventSender() end

---@return EventHandler
function Context:GetEventHandler() end

---@param objectType StringHash|string
---@return string
function Context:GetTypeName(objectType) end


-- Global functions
---@return Context
function GetContext() end

---@return Object
function GetEventSender() end

-- Global variables
---@type Context
context = nil
---@type EventSender
eventSender = nil
---@type EventHandler
eventHandler = nil
