---@meta

--- Auto-generated from IO/NamedPipe

---@class NamedPipe : Object
---@overload fun(pipeName: string, isServer: boolean): NamedPipe
---@overload fun(): NamedPipe
---@field name string
---@field eof boolean
---@field open boolean
NamedPipe = {}

---@overload fun(self: NamedPipe, pipeName: string, isServer: boolean): NamedPipe
---@overload fun(pipeName: string, isServer: boolean): NamedPipe
---@return NamedPipe
function NamedPipe.new() end

---@param pipeName string
---@param isServer boolean
---@return boolean
function NamedPipe:Open(pipeName, isServer) end

---@return nil
function NamedPipe:Close() end

---@return boolean
function NamedPipe:IsOpen() end

---@param size integer
---@return VectorBuffer
function NamedPipe:Read(size) end

---@return string
function NamedPipe:GetName() end

---@return boolean
function NamedPipe:IsEof() end

---@return integer
function NamedPipe:ReadInt() end

---@return integer
function NamedPipe:ReadShort() end

---@return integer
function NamedPipe:ReadByte() end

---@return integer
function NamedPipe:ReadUInt() end

---@return integer
function NamedPipe:ReadUShort() end

---@return number
function NamedPipe:ReadUByte() end

---@return boolean
function NamedPipe:ReadBool() end

---@return number
function NamedPipe:ReadFloat() end

---@return number
function NamedPipe:ReadDouble() end

---@return IntRect
function NamedPipe:ReadIntRect() end

---@return IntVector2
function NamedPipe:ReadIntVector2() end

---@return IntVector3
function NamedPipe:ReadIntVector3() end

---@return Rect
function NamedPipe:ReadRect() end

---@return Vector2
function NamedPipe:ReadVector2() end

---@return Vector3
function NamedPipe:ReadVector3() end

---@param maxAbsCoord number
---@return Vector3
function NamedPipe:ReadPackedVector3(maxAbsCoord) end

---@return Vector4
function NamedPipe:ReadVector4() end

---@return Quaternion
function NamedPipe:ReadQuaternion() end

---@return Quaternion
function NamedPipe:ReadPackedQuaternion() end

---@return Matrix3
function NamedPipe:ReadMatrix3() end

---@return Matrix3x4
function NamedPipe:ReadMatrix3x4() end

---@return Matrix4
function NamedPipe:ReadMatrix4() end

---@return Color
function NamedPipe:ReadColor() end

---@return BoundingBox
function NamedPipe:ReadBoundingBox() end

---@return string
function NamedPipe:ReadString() end

---@return string
function NamedPipe:ReadFileID() end

---@return StringHash|string
function NamedPipe:ReadStringHash() end

---@return VectorBuffer
function NamedPipe:ReadBuffer() end

---@return ResourceRef
function NamedPipe:ReadResourceRef() end

---@return ResourceRefList
function NamedPipe:ReadResourceRefList() end

---@return Variant
function NamedPipe:ReadVariant() end

---@param type VariantType
---@return Variant
function NamedPipe:ReadVariant(type) end

---@return VariantVector
function NamedPipe:ReadVariantVector() end

---@return VariantMap
function NamedPipe:ReadVariantMap() end

---@return integer
function NamedPipe:ReadVLE() end

---@return integer
function NamedPipe:ReadNetID() end

---@return string
function NamedPipe:ReadLine() end

---@param buffer VectorBuffer
---@return integer
function NamedPipe:Write(buffer) end

---@param value integer
---@return boolean
function NamedPipe:WriteInt(value) end

---@param value integer
---@return boolean
function NamedPipe:WriteShort(value) end

---@param value integer
---@return boolean
function NamedPipe:WriteByte(value) end

---@param value integer
---@return boolean
function NamedPipe:WriteUInt(value) end

---@param value integer -- unsigned short
---@return boolean
function NamedPipe:WriteUShort(value) end

---@param value number -- unsigned char
---@return boolean
function NamedPipe:WriteUByte(value) end

---@param value boolean
---@return boolean
function NamedPipe:WriteBool(value) end

---@param value number
---@return boolean
function NamedPipe:WriteFloat(value) end

---@param value number
---@return boolean
function NamedPipe:WriteDouble(value) end

---@param value IntRect
---@return boolean
function NamedPipe:WriteIntRect(value) end

---@param value IntVector2
---@return boolean
function NamedPipe:WriteIntVector2(value) end

---@param value IntVector3
---@return boolean
function NamedPipe:WriteIntVector3(value) end

---@param value Rect
---@return boolean
function NamedPipe:WriteRect(value) end

---@param value Vector2
---@return boolean
function NamedPipe:WriteVector2(value) end

---@param value Vector3
---@return boolean
function NamedPipe:WriteVector3(value) end

---@param value Vector3
---@param maxAbsCoord number
---@return boolean
function NamedPipe:WritePackedVector3(value, maxAbsCoord) end

---@param value Vector4
---@return boolean
function NamedPipe:WriteVector4(value) end

---@param value Quaternion
---@return boolean
function NamedPipe:WriteQuaternion(value) end

---@param value Quaternion
---@return boolean
function NamedPipe:WritePackedQuaternion(value) end

---@param value Matrix3
---@return boolean
function NamedPipe:WriteMatrix3(value) end

---@param value Matrix3x4
---@return boolean
function NamedPipe:WriteMatrix3x4(value) end

---@param value Matrix4
---@return boolean
function NamedPipe:WriteMatrix4(value) end

---@param value Color
---@return boolean
function NamedPipe:WriteColor(value) end

---@param value BoundingBox
---@return boolean
function NamedPipe:WriteBoundingBox(value) end

---@param value string
---@return boolean
function NamedPipe:WriteString(value) end

---@param value string
---@return boolean
function NamedPipe:WriteFileID(value) end

---@param value StringHash|string
---@return boolean
function NamedPipe:WriteStringHash(value) end

---@param buffer VectorBuffer
---@return boolean
function NamedPipe:WriteBuffer(buffer) end

---@param value ResourceRef
---@return boolean
function NamedPipe:WriteResourceRef(value) end

---@param value ResourceRefList
---@return boolean
function NamedPipe:WriteResourceRefList(value) end

---@param value Variant
---@return boolean
function NamedPipe:WriteVariant(value) end

---@param value Variant
---@return boolean
function NamedPipe:WriteVariantData(value) end

---@param value VariantVector
---@return boolean
function NamedPipe:WriteVariantVector(value) end

---@param value VariantMap
---@return boolean
function NamedPipe:WriteVariantMap(value) end

---@param value integer
---@return boolean
function NamedPipe:WriteVLE(value) end

---@param value integer
---@return boolean
function NamedPipe:WriteNetID(value) end

---@param value string
---@return boolean
function NamedPipe:WriteLine(value) end

