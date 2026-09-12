---@meta

--- Auto-generated from Core/Variant

---@alias VariantType
---| integer # VariantType enum values

---@type VariantType
VAR_NONE = 0
---@type VariantType
VAR_INT = 1
---@type VariantType
VAR_BOOL = 2
---@type VariantType
VAR_FLOAT = 3
---@type VariantType
VAR_VECTOR2 = 4
---@type VariantType
VAR_VECTOR3 = 5
---@type VariantType
VAR_VECTOR4 = 6
---@type VariantType
VAR_QUATERNION = 7
---@type VariantType
VAR_COLOR = 8
---@type VariantType
VAR_STRING = 9
---@type VariantType
VAR_BUFFER = 10
---@type VariantType
VAR_VOIDPTR = 11
---@type VariantType
VAR_RESOURCEREF = 12
---@type VariantType
VAR_RESOURCEREFLIST = 13
---@type VariantType
VAR_VARIANTVECTOR = 14
---@type VariantType
VAR_VARIANTMAP = 15
---@type VariantType
VAR_INTRECT = 16
---@type VariantType
VAR_INTVECTOR2 = 17
---@type VariantType
VAR_PTR = 18
---@type VariantType
VAR_MATRIX3 = 19
---@type VariantType
VAR_MATRIX3X4 = 20
---@type VariantType
VAR_MATRIX4 = 21
---@type VariantType
VAR_DOUBLE = 22
---@type VariantType
VAR_STRINGVECTOR = 23
---@type VariantType
VAR_RECT = 24
---@type VariantType
VAR_INTVECTOR3 = 25
---@type VariantType
VAR_INT64 = 26
---@type VariantType
MAX_VAR_TYPES = 27

---@class ResourceRef
---@overload fun(type: StringHash|string): ResourceRef
---@overload fun(type: StringHash|string, name: string): ResourceRef
---@overload fun(type: string, name: string): ResourceRef
---@overload fun(rhs: ResourceRef): ResourceRef
---@overload fun(): ResourceRef
---@field type StringHash|string
---@field name string
---@operator eq(ResourceRef): boolean
ResourceRef = {}

---@overload fun(self: ResourceRef, type: StringHash|string): ResourceRef
---@overload fun(type: StringHash|string): ResourceRef
---@overload fun(self: ResourceRef, type: StringHash|string, name: string): ResourceRef
---@overload fun(type: StringHash|string, name: string): ResourceRef
---@overload fun(self: ResourceRef, type: string, name: string): ResourceRef
---@overload fun(type: string, name: string): ResourceRef
---@overload fun(self: ResourceRef, rhs: ResourceRef): ResourceRef
---@overload fun(rhs: ResourceRef): ResourceRef
---@return ResourceRef
function ResourceRef.new() end


---@class ResourceRefList
---@overload fun(type: StringHash|string): ResourceRefList
---@overload fun(): ResourceRefList
---@field type StringHash|string
---@operator eq(ResourceRefList): boolean
ResourceRefList = {}

---@overload fun(self: ResourceRefList, type: StringHash|string): ResourceRefList
---@overload fun(type: StringHash|string): ResourceRefList
---@return ResourceRefList
function ResourceRefList.new() end


---@class Variant
---@overload fun(value: boolean): Variant
---@overload fun(value: number): Variant
---@overload fun(value: string): Variant
---@overload fun(value: Vector2): Variant
---@overload fun(value: Vector3): Variant
---@overload fun(value: Vector4): Variant
---@overload fun(value: Quaternion): Variant
---@overload fun(value: Color): Variant
---@overload fun(value: IntRect): Variant
---@overload fun(value: IntVector2): Variant
---@overload fun(value: IntVector3): Variant
---@overload fun(value: any): Variant
---@overload fun(value: Variant): Variant
---@overload fun(type: string, value: string): Variant
---@overload fun(type: VariantType, value: string): Variant
---@overload fun(): Variant
---@field type VariantType
---@field typeName string
---@field zero boolean
---@field empty boolean
---@operator eq(Variant): boolean
---@field GetPtr __union_func__type_str__ret_RefCountedT
Variant = {}

---@overload fun(value: boolean): Variant
---@overload fun(value: number): Variant
---@overload fun(value: string): Variant
---@overload fun(value: Vector2): Variant
---@overload fun(value: Vector3): Variant
---@overload fun(value: Vector4): Variant
---@overload fun(value: Quaternion): Variant
---@overload fun(value: Color): Variant
---@overload fun(value: IntRect): Variant
---@overload fun(value: IntVector2): Variant
---@overload fun(value: IntVector3): Variant
---@overload fun(value: any): Variant
---@overload fun(self: Variant, value: Variant): Variant
---@overload fun(value: Variant): Variant
---@overload fun(self: Variant, type: string, value: string): Variant
---@overload fun(type: string, value: string): Variant
---@overload fun(self: Variant, type: VariantType, value: string): Variant
---@overload fun(type: VariantType, value: string): Variant
---@return Variant
function Variant.new() end

---@param type string
---@return nil
function Variant:_Setup(type) end

---@return nil
function Variant:Clear() end

---@param rhs Variant
---@return nil
function Variant:Set(rhs) end

---@param type? string
---@return any
function Variant:Get(type) end

---@return integer
function Variant:GetInt() end

---@return integer
function Variant:GetUInt() end

---@return integer
function Variant:GetInt64() end

---@return integer
function Variant:GetUInt64() end

---@return StringHash|string
function Variant:GetStringHash() end

---@return boolean
function Variant:GetBool() end

---@return number
function Variant:GetFloat() end

---@return number
function Variant:GetDouble() end

---@return Vector2
function Variant:GetVector2() end

---@return Vector3
function Variant:GetVector3() end

---@return Vector4
function Variant:GetVector4() end

---@return Quaternion
function Variant:GetQuaternion() end

---@return Color
function Variant:GetColor() end

---@return string
function Variant:GetString() end

---@return number[]
function Variant:GetRawBuffer() end

---@return VectorBuffer
function Variant:GetBuffer() end

---@param type string
---@return any
function Variant:GetVoidPtr(type) end

---@return ResourceRef
function Variant:GetResourceRef() end

---@return ResourceRefList
function Variant:GetResourceRefList() end

---@return Variant[]
function Variant:GetVariantVector() end

---@return VariantMap
function Variant:GetVariantMap() end

---@return string[]
function Variant:GetStringVector() end

---@return Rect
function Variant:GetRect() end

---@return IntRect
function Variant:GetIntRect() end

---@return IntVector2
function Variant:GetIntVector2() end

---@return IntVector3
function Variant:GetIntVector3() end

---@return Matrix3
function Variant:GetMatrix3() end

---@return Matrix3x4
function Variant:GetMatrix3x4() end

---@return Matrix4
function Variant:GetMatrix4() end

---@return VariantType
function Variant:GetType() end

---@return string
function Variant:GetTypeName() end

---@return string
function Variant:ToString() end

---@return boolean
function Variant:IsZero() end

---@return boolean
function Variant:IsEmpty() end


---@class VariantMap
---@overload fun(): VariantMap
VariantMap = {}

---@return VariantMap
function VariantMap.new() end

---@param type string
---@return nil
function VariantMap:_Setup(type) end

