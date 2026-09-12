---@meta

--- Auto-generated from IO/Serializer

---@class Serializer
Serializer = {}

---@param buffer VectorBuffer
---@return integer
function Serializer:Write(buffer) end

---@param value integer
---@return boolean
function Serializer:WriteInt(value) end

---@param value integer
---@return boolean
function Serializer:WriteInt64(value) end

---@param value integer
---@return boolean
function Serializer:WriteShort(value) end

---@param value integer
---@return boolean
function Serializer:WriteByte(value) end

---@param value integer
---@return boolean
function Serializer:WriteUInt(value) end

---@param value integer
---@return boolean
function Serializer:WriteUInt64(value) end

---@param value integer -- unsigned short
---@return boolean
function Serializer:WriteUShort(value) end

---@param value number -- unsigned char
---@return boolean
function Serializer:WriteUByte(value) end

---@param value boolean
---@return boolean
function Serializer:WriteBool(value) end

---@param value number
---@return boolean
function Serializer:WriteFloat(value) end

---@param value number
---@return boolean
function Serializer:WriteDouble(value) end

---@param value IntRect
---@return boolean
function Serializer:WriteIntRect(value) end

---@param value IntVector2
---@return boolean
function Serializer:WriteIntVector2(value) end

---@param value IntVector3
---@return boolean
function Serializer:WriteIntVector3(value) end

---@param value Rect
---@return boolean
function Serializer:WriteRect(value) end

---@param value Vector2
---@return boolean
function Serializer:WriteVector2(value) end

---@param value Vector3
---@return boolean
function Serializer:WriteVector3(value) end

---@param value Vector3
---@param maxAbsCoord number
---@return boolean
function Serializer:WritePackedVector3(value, maxAbsCoord) end

---@param value Vector4
---@return boolean
function Serializer:WriteVector4(value) end

---@param value Quaternion
---@return boolean
function Serializer:WriteQuaternion(value) end

---@param value Quaternion
---@return boolean
function Serializer:WritePackedQuaternion(value) end

---@param value Matrix3
---@return boolean
function Serializer:WriteMatrix3(value) end

---@param value Matrix3x4
---@return boolean
function Serializer:WriteMatrix3x4(value) end

---@param value Matrix4
---@return boolean
function Serializer:WriteMatrix4(value) end

---@param value Color
---@return boolean
function Serializer:WriteColor(value) end

---@param value BoundingBox
---@return boolean
function Serializer:WriteBoundingBox(value) end

---@param value string
---@return boolean
function Serializer:WriteString(value) end

---@param value string
---@return boolean
function Serializer:WriteFileID(value) end

---@param value StringHash|string
---@return boolean
function Serializer:WriteStringHash(value) end

---@param buffer VectorBuffer
---@return boolean
function Serializer:WriteBuffer(buffer) end

---@param value ResourceRef
---@return boolean
function Serializer:WriteResourceRef(value) end

---@param value ResourceRefList
---@return boolean
function Serializer:WriteResourceRefList(value) end

---@param value Variant
---@return boolean
function Serializer:WriteVariant(value) end

---@param value Variant
---@return boolean
function Serializer:WriteVariantData(value) end

---@param value VariantVector
---@return boolean
function Serializer:WriteVariantVector(value) end

---@param value VariantMap
---@return boolean
function Serializer:WriteVariantMap(value) end

---@param value integer
---@return boolean
function Serializer:WriteVLE(value) end

---@param value integer
---@return boolean
function Serializer:WriteNetID(value) end

---@param value string
---@return boolean
function Serializer:WriteLine(value) end

