---@meta

--- Additional Urho3D types that are not defined in pkg files but referenced in the API

---@alias ViewOverride integer

--- Crowd obstacle avoidance parameters (from Detour library)
---@class CrowdObstacleAvoidanceParams
---@field velBias number # Velocity bias
---@field weightDesVel number # Desired velocity weight
---@field weightCurVel number # Current velocity weight
---@field weightSide number # Side bias weight
---@field weightToi number # Time of impact weight
---@field horizTime number # Horizon time
---@field gridSize integer # Grid size
---@field adaptiveDivs integer # Adaptive divisions
---@field adaptiveRings integer # Adaptive rings
---@field adaptiveDepth integer # Adaptive depth
CrowdObstacleAvoidanceParams = {}

---@class RefCounted
RefCounted = {}

--- Manually delete the C++ object (tolua++ method)
--- This is needed for objects returned from functions that transfer ownership to Lua
function RefCounted:delete() end

--- Internal event handler class (not directly used in Lua scripting)
---@class EventHandler
EventHandler = {}

--- Event sender type alias
---@alias EventSender Object

---@class LogicComponent : Component
LogicComponent = {}

---@alias Algorithm integer

---@class JSONArray
JSONArray = {}

---@class JSONObject
JSONObject = {}

---@class LuaFile : Resource
LuaFile = {}

---@class SceneResolver
SceneResolver = {}

---@alias StringVector string[]

---@alias VariantVector Variant[]

---@alias SharedPtr<T> T

---@class ModelMorph
ModelMorph = {}

---@alias DragAndDropMode integer

--- tolua++ library global object
---@class tolua
tolua = {}

--- Cast an object to a specific type
---@param object any
---@param typeName string
---@return any
function tolua.cast(object, typeName) end

--- Get the type name of an object
---@param object any
---@return string
function tolua.type(object) end

-- =============================================================================
-- Coroutine Extensions (Urho3D)
-- =============================================================================
-- These are custom extensions to Lua's standard coroutine library provided by Urho3D

---@class coroutine : table
---@field start fun(func: function): boolean, any
---@field sleep fun(time: number): any
---@field update fun(steptime: number)
---@field waitevent fun(event: string): any
---@field sendevent fun(event: string)
coroutine = {}

--- Start a new coroutine immediately
---@param func function # The function to run in the coroutine
---@return boolean success, any ... # Returns the result of coroutine.resume()
function coroutine.start(func) end

--- Suspend the current coroutine for a specified time
---@param time number # Time to sleep in seconds
---@return any ... # Returns when the coroutine is resumed after the specified time
function coroutine.sleep(time) end

--- Update all sleeping coroutines (internal use, called by the engine)
---@param steptime number # Time step in seconds
function coroutine.update(steptime) end

--- Wait for a specific event in the current coroutine
---@param event string # The event name to wait for
---@return any ... # Returns when the event is sent via coroutine.sendevent()
function coroutine.waitevent(event) end

--- Send an event to wake up all coroutines waiting for it
---@param event string # The event name to send
function coroutine.sendevent(event) end

-- =============================================================================
-- Model Extensions (Missing from auto-generated definitions)
-- =============================================================================

---@class Model
---@field SetVertexBuffers fun(self: Model, buffers: VertexBuffer[], morphRangeStarts: integer[], morphRangeCounts: integer[]): boolean

--- Set vertex buffers with morph range data
---@param buffers VertexBuffer[] # Array of vertex buffers
---@param morphRangeStarts integer[] # Starting indices for morph ranges
---@param morphRangeCounts integer[] # Counts for morph ranges
---@return boolean # True if successful
function Model:SetVertexBuffers(buffers, morphRangeStarts, morphRangeCounts) end

-- =============================================================================
-- TileMap2D Extensions (Fix output parameter return values)
-- =============================================================================

---@class TileMap2D

--- Convert world position to tile index (returns 3 values: success, x, y)
--- Note: In Lua, output parameters (int*) become additional return values
---@param position Vector2 # World position
---@return boolean # True if position is within map bounds
---@return integer # Tile x index (0 if out of bounds)
---@return integer # Tile y index (0 if out of bounds)
function TileMap2D:PositionToTileIndex(position) end

-- =============================================================================
-- Internal Rendering Types (not exported to Lua but referenced in events)
-- =============================================================================

--- Internal rendering view class (not directly usable in Lua)
--- Referenced in graphics events: BeginViewUpdate, EndViewUpdate, etc.
---@class View
View = {}

--- SDL event structure (from SDL library, opaque in Lua)
--- Referenced in SDLRawInputEvent
---@class SDL_Event
SDL_Event = {}

-- =============================================================================
-- Common Module (Global utility functions for cloud services)
-- =============================================================================

---@class common Common utility module for cloud services
common = {}

--- Get the current map/game name
---@return string mapName The current map/game identifier
function common.get_map_name() end

--- Get the current user's ID
---@return integer userId The current player's user ID (int64)
function common.get_user_id() end

--- Get the opaque JSON payload supplied by the host runtime environment
---@return string extraJson The original JSON string, or an empty string when the host did not provide one
function common.get_env_extra() end

-- =============================================================================
-- Runtime Preview APIs
-- =============================================================================

---@alias UserNicknameId integer|string

---@class UserNicknameInfo
---@field userId integer
---@field nickname string

---@class GetUserNicknameOptions
---@field userIds UserNicknameId[] User IDs to query
---@field onSuccess? fun(nicknames: UserNicknameInfo[]) Called with results after a successful query
---@field onError? fun(errorCode: integer) Called when the query fails

--- Check whether the application is running in network mode.
---@return boolean
function IsNetworkMode() end

--- Query TapTap nicknames for one or more users.
---@param options GetUserNicknameOptions
---@return nil
function GetUserNickname(options) end

-- =============================================================================
-- cjson Module (JSON encode/decode, backed by RapidJSON)
-- =============================================================================

---@class cjson
---@field _NAME string # Module name ("cjson")
---@field _VERSION string # Module version ("1.1.0")
cjson = {}

--- Encode a Lua value to a JSON string.
--- Tables with consecutive integer keys (1..n) are encoded as JSON arrays;
--- tables with string keys are encoded as JSON objects.
--- Maximum nesting depth: 64.
---@param value any # The Lua value to encode (table, string, number, boolean, or nil)
---@return string # The JSON string
function cjson.encode(value) end

--- Decode a JSON string into a Lua value.
--- JSON objects become Lua tables with string keys;
--- JSON arrays become Lua tables with integer keys starting from 1.
---@param json string # The JSON string to decode
---@return any # The decoded Lua value
function cjson.decode(json) end

--- Return a JSON null sentinel value (currently returns nil).
---@return nil
function cjson.null() end
