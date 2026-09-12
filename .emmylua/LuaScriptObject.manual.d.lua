---@meta

-- =============================================================================
-- LuaScriptObject - Base class for Lua script objects
-- =============================================================================

--- Base class for Lua script objects created via ScriptObject()
--- Script objects can be attached to nodes via Node:CreateScriptObject()
---@class LuaScriptObject
---@field node Node # The scene node this script is attached to
---@field instance LuaScriptInstance # The LuaScriptInstance component
---@field [string] any # Custom fields
LuaScriptObject = {}

-- =============================================================================
-- Lifecycle Methods (implement these in your script object)
-- =============================================================================

--- Called when the script object is created
---@type fun(self: LuaScriptObject)?
LuaScriptObject.Start = nil

--- Called when the script object is destroyed
---@type fun(self: LuaScriptObject)?
LuaScriptObject.Stop = nil

--- Called before the first Update (only once)
---@type fun(self: LuaScriptObject)?
LuaScriptObject.DelayedStart = nil

--- Called every frame during scene update
---@type fun(self: LuaScriptObject, timeStep: number)?
LuaScriptObject.Update = nil

--- Called every frame after scene update
---@type fun(self: LuaScriptObject, timeStep: number)?
LuaScriptObject.PostUpdate = nil

--- Called at fixed physics update intervals
---@type fun(self: LuaScriptObject, timeStep: number)?
LuaScriptObject.FixedUpdate = nil

--- Called after physics update
---@type fun(self: LuaScriptObject, timeStep: number)?
LuaScriptObject.FixedPostUpdate = nil

--- Called when loading from file/network
---@type fun(self: LuaScriptObject, deserializer: Deserializer)?
LuaScriptObject.Load = nil

--- Called when saving to file/network
---@type fun(self: LuaScriptObject, serializer: Serializer)?
LuaScriptObject.Save = nil

--- Called when receiving network update
---@type fun(self: LuaScriptObject, deserializer: Deserializer)?
LuaScriptObject.ReadNetworkUpdate = nil

--- Called when sending network update
---@type fun(self: LuaScriptObject, serializer: Serializer)?
LuaScriptObject.WriteNetworkUpdate = nil

--- Called after attributes are applied
---@type fun(self: LuaScriptObject)?
LuaScriptObject.ApplyAttributes = nil

--- Called when the node's transform changes
---@type fun(self: LuaScriptObject)?
LuaScriptObject.TransformChanged = nil

-- =============================================================================
-- Instance Methods
-- =============================================================================

--- Get the scene node this script is attached to
---@return Node
function LuaScriptObject:GetNode() end

-- =============================================================================
-- Event Subscription Methods
-- =============================================================================

-- Subscribe to a global event
--- When using self:SubscribeToEvent(), the callback receives (self, eventType, eventData)
---@see SubscribeToEvent
---@param eventType StringHash|string # Event type
---@param callback fun(self: LuaScriptObject, eventType: StringHash, eventData: VariantMap)|string # Handler function or method name
function LuaScriptObject:SubscribeToEvent(eventType, callback) end

--- Subscribe to an event from a specific sender
--- When using self:SubscribeToEvent(), the callback receives (self, eventType, eventData)
---@param sender Object # Event sender
---@param eventType StringHash|string # Event type
---@param callback fun(self: LuaScriptObject, eventType: StringHash, eventData: VariantMap)|string # Handler function or method name
function LuaScriptObject:SubscribeToEvent(sender, eventType, callback) end

--- Unsubscribe from a global event
---@param eventType StringHash|string # Event type
function LuaScriptObject:UnsubscribeFromEvent(eventType) end

--- Unsubscribe from an event from a specific sender
---@param sender Object # Event sender
---@param eventType StringHash|string # Event type
function LuaScriptObject:UnsubscribeFromEvent(sender, eventType) end

--- Unsubscribe from all events from a sender
---@param sender Object # Event sender
function LuaScriptObject:UnsubscribeFromEvents(sender) end

--- Unsubscribe from all events
function LuaScriptObject:UnsubscribeFromAllEvents() end

--- Unsubscribe from all events except specified ones
---@param exceptions string[] # Event names to keep
function LuaScriptObject:UnsubscribeFromAllEventsExcept(exceptions) end

--- Check if subscribed to a global event
---@param eventType StringHash|string # Event type
---@return boolean
function LuaScriptObject:HasSubscribedToEvent(eventType) end

--- Check if subscribed to an event from a specific sender
---@param sender Object # Event sender
---@param eventType StringHash|string # Event type
---@return boolean
function LuaScriptObject:HasSubscribedToEvent(sender, eventType) end

-- =============================================================================
-- ScriptObject Factory Function
-- =============================================================================

--- Create a new script object class that inherits from LuaScriptObject
--- Usage:
---   MyClass = ScriptObject()
---   function MyClass:Start() ... end
---   function MyClass:Update(timeStep) ... end
---@return LuaScriptObject # A new script object class
function ScriptObject() end
