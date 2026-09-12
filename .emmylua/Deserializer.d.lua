---@meta

--- Auto-generated from IO/Deserializer

---@class Deserializer
---@field name string
---@field checksum integer
---@field position integer
---@field size integer
---@field eof boolean
Deserializer = {}

---@param size integer
---@return VectorBuffer
function Deserializer:Read(size) end

---@param position integer
---@return integer
function Deserializer:Seek(position) end

---@param delta integer
---@return integer
function Deserializer:SeekRelative(delta) end

---@return string
function Deserializer:GetName() end

---@return integer
function Deserializer:GetChecksum() end

---@return integer
function Deserializer:GetPosition() end

---@return integer
function Deserializer:Tell() end

---@return integer
function Deserializer:GetSize() end

---@return boolean
function Deserializer:IsEof() end

---@return integer
function Deserializer:ReadInt() end

---@return integer
function Deserializer:ReadInt64() end

---@return integer
function Deserializer:ReadShort() end

---@return integer
function Deserializer:ReadByte() end

---@return integer
function Deserializer:ReadUInt() end

---@return integer
function Deserializer:ReadUInt64() end

---@return integer
function Deserializer:ReadUShort() end

---@return number
function Deserializer:ReadUByte() end

---@return boolean
function Deserializer:ReadBool() end

---@return number
function Deserializer:ReadFloat() end

---@return number
function Deserializer:ReadDouble() end

---@return IntRect
function Deserializer:ReadIntRect() end

---@return IntVector2
function Deserializer:ReadIntVector2() end

---@return IntVector3
function Deserializer:ReadIntVector3() end

---@return Rect
function Deserializer:ReadRect() end

---@return Vector2
function Deserializer:ReadVector2() end

---@return Vector3
function Deserializer:ReadVector3() end

---@param maxAbsCoord number
---@return Vector3
function Deserializer:ReadPackedVector3(maxAbsCoord) end

---@return Vector4
function Deserializer:ReadVector4() end

---@return Quaternion
function Deserializer:ReadQuaternion() end

---@return Quaternion
function Deserializer:ReadPackedQuaternion() end

---@return Matrix3
function Deserializer:ReadMatrix3() end

---@return Matrix3x4
function Deserializer:ReadMatrix3x4() end

---@return Matrix4
function Deserializer:ReadMatrix4() end

---@return Color
function Deserializer:ReadColor() end

---@return BoundingBox
function Deserializer:ReadBoundingBox() end

---@return string
function Deserializer:ReadString() end

---@return string
function Deserializer:ReadFileID() end

---@return StringHash|string
function Deserializer:ReadStringHash() end

---@return VectorBuffer
function Deserializer:ReadBuffer() end

---@return ResourceRef
function Deserializer:ReadResourceRef() end

---@return ResourceRefList
function Deserializer:ReadResourceRefList() end

---@return Variant
function Deserializer:ReadVariant() end

---@param type VariantType
---@return Variant
function Deserializer:ReadVariant(type) end

---@return VariantVector
function Deserializer:ReadVariantVector() end

---@return VariantMap
function Deserializer:ReadVariantMap() end

---@return integer
function Deserializer:ReadVLE() end

---@return integer
function Deserializer:ReadNetID() end

---@return string
function Deserializer:ReadLine() end

