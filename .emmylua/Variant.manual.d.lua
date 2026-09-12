---@meta

-- =============================================================================
-- Variant Type System (Manual Definitions)
-- =============================================================================
-- These types provide precise type checking for Variant fields in VariantMap.
-- Each VariantWith* type only exposes the Get method(s) that make sense for
-- that data type, preventing errors like calling GetVector3() on an integer field.

---@class VariantWithInt
---@field GetInt fun(self: VariantWithInt): integer
---@field GetUInt fun(self: VariantWithInt): integer

---@class VariantWithInt64
---@field GetInt64 fun(self: VariantWithInt64): integer
---@field GetUInt64 fun(self: VariantWithInt64): integer

---@class VariantWithBool
---@field GetBool fun(self: VariantWithBool): boolean

---@class VariantWithFloat
---@field GetFloat fun(self: VariantWithFloat): number
---@field GetDouble fun(self: VariantWithFloat): number

---@class VariantWithString
---@field GetString fun(self: VariantWithString): string

---@class VariantWithStringHash
---@field GetStringHash fun(self: VariantWithStringHash): StringHash|string

---@class VariantWithVector2
---@field GetVector2 fun(self: VariantWithVector2): Vector2

---@class VariantWithVector3
---@field GetVector3 fun(self: VariantWithVector3): Vector3

---@class VariantWithVector4
---@field GetVector4 fun(self: VariantWithVector4): Vector4

---@class VariantWithQuaternion
---@field GetQuaternion fun(self: VariantWithQuaternion): Quaternion

---@class VariantWithColor
---@field GetColor fun(self: VariantWithColor): Color

---@class VariantWithRect
---@field GetRect fun(self: VariantWithRect): Rect

---@class VariantWithIntRect
---@field GetIntRect fun(self: VariantWithIntRect): IntRect

---@class VariantWithIntVector2
---@field GetIntVector2 fun(self: VariantWithIntVector2): IntVector2

---@class VariantWithIntVector3
---@field GetIntVector3 fun(self: VariantWithIntVector3): IntVector3

---@class VariantWithMatrix3
---@field GetMatrix3 fun(self: VariantWithMatrix3): Matrix3

---@class VariantWithMatrix3x4
---@field GetMatrix3x4 fun(self: VariantWithMatrix3x4): Matrix3x4

---@class VariantWithMatrix4
---@field GetMatrix4 fun(self: VariantWithMatrix4): Matrix4

---@class VariantWithResourceRef
---@field GetResourceRef fun(self: VariantWithResourceRef): ResourceRef

---@class VariantWithResourceRefList
---@field GetResourceRefList fun(self: VariantWithResourceRefList): ResourceRefList

---@class VariantWithVariantVector
---@field GetVariantVector fun(self: VariantWithVariantVector): Variant[]

---@class VariantWithStringVector
---@field GetStringVector fun(self: VariantWithStringVector): string[]

---@class VariantWithVariantMap
---@field GetVariantMap fun(self: VariantWithVariantMap): VariantMap|nil

---@class VariantWithPtr
---@field GetPtr __union_func__type_str__ret_RefCountedT
---@field GetPtr fun(self: VariantWithPtr): RefCounted
---@field GetVoidPtr fun(self: VariantWithPtr, type: string): any

-- Fix Variant:GetPtr signature (accepts optional typeName for type casting)
---@class Variant
---@field GetPtr fun(self: Variant): RefCounted
-- Fix Variant:GetVariantMap signature: nil on type mismatch (guarded in
-- Variant.pkg to avoid exposing the shared static emptyVariantMap by
-- reference — see TOLUA_DISABLE_tolua_CoreLuaAPI_Variant_GetVariantMap00).
---@field GetVariantMap fun(self: Variant): VariantMap|nil

---@class VariantWithBuffer
---@field GetBuffer fun(self: VariantWithBuffer): VectorBuffer

-- Generic Variant for unknown or mixed-type fields
---@alias VariantGeneric Variant

-- =============================================================================
-- VariantMap with Helper Methods
-- =============================================================================

---@class VariantMap
---@field [string] Variant | Vector3 | Quaternion | Color | StringHash | IntRect | IntVector2 | IntVector3 | Matrix3 | Matrix3x4 | Matrix4 | VariantVector | VariantMap | StringVector | ResourceRef | ResourceRefList | RefCounted | VariantWithInt | VariantWithInt64 | VariantWithBool | VariantWithFloat | VariantWithString | VariantWithStringHash | VariantWithVector2 | VariantWithVector3 | VariantWithVector4 | VariantWithQuaternion | VariantWithColor | VariantWithRect | VariantWithIntRect | VariantWithIntVector2 | VariantWithIntVector3 | VariantWithMatrix3 | VariantWithMatrix3x4 | VariantWithMatrix4 | VariantWithResourceRef | VariantWithResourceRefList | VariantWithVariantVector | VariantWithStringVector | VariantWithVariantMap | VariantWithPtr | VariantWithBuffer
VariantMap = {}

--- Get an integer value from the VariantMap by key
---@param key string
---@return integer
function VariantMap:GetInt(key) end

--- Get a string value from the VariantMap by key
---@param key string
---@return string
function VariantMap:GetString(key) end

--- Get a boolean value from the VariantMap by key
---@param key string
---@return boolean
function VariantMap:GetBool(key) end

--- Get a float value from the VariantMap by key
---@param key string
---@return number
function VariantMap:GetFloat(key) end

--- Get a Vector2 value from the VariantMap by key
---@param key string
---@return Vector2
function VariantMap:GetVector2(key) end

--- Get a Vector3 value from the VariantMap by key
---@param key string
---@return Vector3
function VariantMap:GetVector3(key) end

--- Get a Quaternion value from the VariantMap by key
---@param key string
---@return Quaternion
function VariantMap:GetQuaternion(key) end

--- Get a Color value from the VariantMap by key
---@param key string
---@return Color
function VariantMap:GetColor(key) end

--- Get a StringHash value from the VariantMap by key
---@param key string
---@return StringHash
function VariantMap:GetStringHash(key) end

--- Get a pointer value from the VariantMap by key (returns various object types)
-- ---@param key string
-- ---@return any
-- function VariantMap:GetPtr(key) end

--- Get a buffer value from the VariantMap by key (returns a VectorBuffer copy)
---@param key string
---@return VectorBuffer
function VariantMap:GetBuffer(key) end

--- Get a variant vector value from the VariantMap by key (returns a Lua table)
---@param key string
---@return Variant[]
function VariantMap:GetVariantVector(key) end

--- Get a string vector value from the VariantMap by key (returns a Lua table)
---@param key string
---@return string[]
function VariantMap:GetStringVector(key) end

--- Get a nested variant map by key; nil when the value is not a VariantMap
---@param key string
---@return VariantMap|nil
function VariantMap:GetVariantMap(key) end

--- Get an IntRect value from the VariantMap by key
---@param key string
---@return IntRect
function VariantMap:GetIntRect(key) end

--- Get an IntVector2 value from the VariantMap by key
---@param key string
---@return IntVector2
function VariantMap:GetIntVector2(key) end

--- Get an IntVector3 value from the VariantMap by key
---@param key string
---@return IntVector3
function VariantMap:GetIntVector3(key) end

--- Get a Matrix3 value from the VariantMap by key
---@param key string
---@return Matrix3
function VariantMap:GetMatrix3(key) end

--- Get a Matrix3x4 value from the VariantMap by key
---@param key string
---@return Matrix3x4
function VariantMap:GetMatrix3x4(key) end

--- Get a Matrix4 value from the VariantMap by key
---@param key string
---@return Matrix4
function VariantMap:GetMatrix4(key) end

-- =============================================================================
-- Variant Parameter Type (for SetVar and similar functions)
-- =============================================================================
-- In Lua bindings, ToluaToVariant automatically converts Lua types to Variant
-- This alias allows passing common Lua types directly to Variant parameters

---@alias VariantInput boolean | number | integer | string | Vector2 | Vector3 | Vector4 | Quaternion | Color | IntRect | IntVector2 | IntVector3 | Matrix3 | Matrix3x4 | Matrix4 | Variant | table

-- Node:SetVar overloads to accept Lua types directly
---@class Node
---@field SetVar fun(self: Node, key: StringHash|string, value: VariantInput)

-- UIElement:SetVar overloads to accept Lua types directly
---@class UIElement
---@field SetVar fun(self: UIElement, key: StringHash|string, value: VariantInput)
