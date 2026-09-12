---@meta

--- Auto-generated from IO/VectorBuffer

---@class VectorBuffer
---@overload fun(source: Deserializer, size: integer): VectorBuffer
---@overload fun(): VectorBuffer
---@field name string
---@field checksum integer
---@field position integer
---@field size integer
---@field eof boolean
VectorBuffer = {}

---@overload fun(self: VectorBuffer, source: Deserializer, size: integer): VectorBuffer
---@overload fun(source: Deserializer, size: integer): VectorBuffer
---@return VectorBuffer
function VectorBuffer.new() end

---@param source Deserializer
---@param size integer
---@return nil
function VectorBuffer:SetData(source, size) end

---@return nil
function VectorBuffer:Clear() end

---@param size integer
---@return nil
function VectorBuffer:Resize(size) end

---@return any
function VectorBuffer:GetData() end

---@return any
function VectorBuffer:GetModifiableData() end

---@param size integer
---@return VectorBuffer
function VectorBuffer:Read(size) end

---@param position integer
---@return integer
function VectorBuffer:Seek(position) end

---@param delta integer
---@return integer
function VectorBuffer:SeekRelative(delta) end

---@return string
function VectorBuffer:GetName() end

---@return integer
function VectorBuffer:GetChecksum() end

---@return integer
function VectorBuffer:GetPosition() end

---@return integer
function VectorBuffer:Tell() end

---@return integer
function VectorBuffer:GetSize() end

---@return boolean
function VectorBuffer:IsEof() end

---@return integer
function VectorBuffer:ReadInt() end

---@return integer
function VectorBuffer:ReadInt64() end

---@return integer
function VectorBuffer:ReadShort() end

---@return integer
function VectorBuffer:ReadByte() end

---@return integer
function VectorBuffer:ReadUInt() end

---@return integer
function VectorBuffer:ReadUInt64() end

---@return integer
function VectorBuffer:ReadUShort() end

---@return number
function VectorBuffer:ReadUByte() end

---@return boolean
function VectorBuffer:ReadBool() end

---@return number
function VectorBuffer:ReadFloat() end

---@return number
function VectorBuffer:ReadDouble() end

---@return IntRect
function VectorBuffer:ReadIntRect() end

---@return IntVector2
function VectorBuffer:ReadIntVector2() end

---@return IntVector3
function VectorBuffer:ReadIntVector3() end

---@return Rect
function VectorBuffer:ReadRect() end

---@return Vector2
function VectorBuffer:ReadVector2() end

---@return Vector3
function VectorBuffer:ReadVector3() end

---@param maxAbsCoord number
---@return Vector3
function VectorBuffer:ReadPackedVector3(maxAbsCoord) end

---@return Vector4
function VectorBuffer:ReadVector4() end

---@return Quaternion
function VectorBuffer:ReadQuaternion() end

---@return Quaternion
function VectorBuffer:ReadPackedQuaternion() end

---@return Matrix3
function VectorBuffer:ReadMatrix3() end

---@return Matrix3x4
function VectorBuffer:ReadMatrix3x4() end

---@return Matrix4
function VectorBuffer:ReadMatrix4() end

---@return Color
function VectorBuffer:ReadColor() end

---@return BoundingBox
function VectorBuffer:ReadBoundingBox() end

---@return string
function VectorBuffer:ReadString() end

---@return string
function VectorBuffer:ReadFileID() end

---@return StringHash|string
function VectorBuffer:ReadStringHash() end

---@return VectorBuffer
function VectorBuffer:ReadBuffer() end

---@return ResourceRef
function VectorBuffer:ReadResourceRef() end

---@return ResourceRefList
function VectorBuffer:ReadResourceRefList() end

---@return Variant
function VectorBuffer:ReadVariant() end

---@param type VariantType
---@return Variant
function VectorBuffer:ReadVariant(type) end

---@return VariantVector
function VectorBuffer:ReadVariantVector() end

---@return VariantMap
function VectorBuffer:ReadVariantMap() end

---@return integer
function VectorBuffer:ReadVLE() end

---@return integer
function VectorBuffer:ReadNetID() end

---@return string
function VectorBuffer:ReadLine() end

---@param buffer VectorBuffer
---@return integer
function VectorBuffer:Write(buffer) end

---@param value integer
---@return boolean
function VectorBuffer:WriteInt(value) end

---@param value integer
---@return boolean
function VectorBuffer:WriteInt64(value) end

---@param value integer
---@return boolean
function VectorBuffer:WriteShort(value) end

---@param value integer
---@return boolean
function VectorBuffer:WriteByte(value) end

---@param value integer
---@return boolean
function VectorBuffer:WriteUInt(value) end

---@param value integer
---@return boolean
function VectorBuffer:WriteUInt64(value) end

---@param value integer -- unsigned short
---@return boolean
function VectorBuffer:WriteUShort(value) end

---@param value number -- unsigned char
---@return boolean
function VectorBuffer:WriteUByte(value) end

---@param value boolean
---@return boolean
function VectorBuffer:WriteBool(value) end

---@param value number
---@return boolean
function VectorBuffer:WriteFloat(value) end

---@param value number
---@return boolean
function VectorBuffer:WriteDouble(value) end

---@param value IntRect
---@return boolean
function VectorBuffer:WriteIntRect(value) end

---@param value IntVector2
---@return boolean
function VectorBuffer:WriteIntVector2(value) end

---@param value IntVector3
---@return boolean
function VectorBuffer:WriteIntVector3(value) end

---@param value Rect
---@return boolean
function VectorBuffer:WriteRect(value) end

---@param value Vector2
---@return boolean
function VectorBuffer:WriteVector2(value) end

---@param value Vector3
---@return boolean
function VectorBuffer:WriteVector3(value) end

---@param value Vector3
---@param maxAbsCoord number
---@return boolean
function VectorBuffer:WritePackedVector3(value, maxAbsCoord) end

---@param value Vector4
---@return boolean
function VectorBuffer:WriteVector4(value) end

---@param value Quaternion
---@return boolean
function VectorBuffer:WriteQuaternion(value) end

---@param value Quaternion
---@return boolean
function VectorBuffer:WritePackedQuaternion(value) end

---@param value Matrix3
---@return boolean
function VectorBuffer:WriteMatrix3(value) end

---@param value Matrix3x4
---@return boolean
function VectorBuffer:WriteMatrix3x4(value) end

---@param value Matrix4
---@return boolean
function VectorBuffer:WriteMatrix4(value) end

---@param value Color
---@return boolean
function VectorBuffer:WriteColor(value) end

---@param value BoundingBox
---@return boolean
function VectorBuffer:WriteBoundingBox(value) end

---@param value string
---@return boolean
function VectorBuffer:WriteString(value) end

---@param value string
---@return boolean
function VectorBuffer:WriteFileID(value) end

---@param value StringHash|string
---@return boolean
function VectorBuffer:WriteStringHash(value) end

---@param buffer VectorBuffer
---@return boolean
function VectorBuffer:WriteBuffer(buffer) end

---@param value ResourceRef
---@return boolean
function VectorBuffer:WriteResourceRef(value) end

---@param value ResourceRefList
---@return boolean
function VectorBuffer:WriteResourceRefList(value) end

---@param value Variant
---@return boolean
function VectorBuffer:WriteVariant(value) end

---@param value Variant
---@return boolean
function VectorBuffer:WriteVariantData(value) end

---@param value VariantVector
---@return boolean
function VectorBuffer:WriteVariantVector(value) end

---@param value VariantMap
---@return boolean
function VectorBuffer:WriteVariantMap(value) end

---@param value integer
---@return boolean
function VectorBuffer:WriteVLE(value) end

---@param value integer
---@return boolean
function VectorBuffer:WriteNetID(value) end

---@param value string
---@return boolean
function VectorBuffer:WriteLine(value) end

