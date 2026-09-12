---@meta

--- Auto-generated from IO/File

---@alias FileMode
---| integer # FileMode enum values

---@type FileMode
FILE_READ = 0
---@type FileMode
FILE_WRITE = 1
---@type FileMode
FILE_READWRITE = 2

---@class File : Object
---@overload fun(fileName: string, mode?: FileMode): File
---@overload fun(package: PackageFile, fileName: string): File
---@overload fun(): File
---@field mode FileMode
---@field open boolean
---@field packaged boolean
---@field name string
---@field checksum integer
---@field position integer
---@field size integer
---@field eof boolean
File = {}

---@overload fun(self: File, fileName: string, mode?: FileMode): File
---@overload fun(fileName: string, mode?: FileMode): File
---@overload fun(self: File, package: PackageFile, fileName: string): File
---@overload fun(package: PackageFile, fileName: string): File
---@return File
function File.new() end

---@param fileName string
---@param mode? FileMode
---@return boolean
function File:Open(fileName, mode) end

---@param package PackageFile
---@param fileName string
---@return boolean
function File:Open(package, fileName) end

---@return nil
function File:Close() end

--- 关闭文件句柄并释放 Lua 端引用 (相当于 Close() + 清空 userdata 一步到位)。
--- Dispose 后此 File 对象在 Lua 端不可再访问。
---@return nil
function File:Dispose() end

---@return nil
function File:Flush() end

---@param name string
---@return nil
function File:SetName(name) end

---@return FileMode
function File:GetMode() end

---@return boolean
function File:IsOpen() end

---@return any
function File:GetHandle() end

---@return boolean
function File:IsPackaged() end

---@param size integer
---@return VectorBuffer
function File:Read(size) end

---@param position integer
---@return integer
function File:Seek(position) end

---@param delta integer
---@return integer
function File:SeekRelative(delta) end

---@return string
function File:GetName() end

---@return integer
function File:GetChecksum() end

---@return integer
function File:GetPosition() end

---@return integer
function File:Tell() end

---@return integer
function File:GetSize() end

---@return boolean
function File:IsEof() end

---@return integer
function File:ReadInt() end

---@return integer
function File:ReadInt64() end

---@return integer
function File:ReadShort() end

---@return integer
function File:ReadByte() end

---@return integer
function File:ReadUInt() end

---@return integer
function File:ReadUInt64() end

---@return integer
function File:ReadUShort() end

---@return number
function File:ReadUByte() end

---@return boolean
function File:ReadBool() end

---@return number
function File:ReadFloat() end

---@return number
function File:ReadDouble() end

---@return IntRect
function File:ReadIntRect() end

---@return IntVector2
function File:ReadIntVector2() end

---@return IntVector3
function File:ReadIntVector3() end

---@return Rect
function File:ReadRect() end

---@return Vector2
function File:ReadVector2() end

---@return Vector3
function File:ReadVector3() end

---@param maxAbsCoord number
---@return Vector3
function File:ReadPackedVector3(maxAbsCoord) end

---@return Vector4
function File:ReadVector4() end

---@return Quaternion
function File:ReadQuaternion() end

---@return Quaternion
function File:ReadPackedQuaternion() end

---@return Matrix3
function File:ReadMatrix3() end

---@return Matrix3x4
function File:ReadMatrix3x4() end

---@return Matrix4
function File:ReadMatrix4() end

---@return Color
function File:ReadColor() end

---@return BoundingBox
function File:ReadBoundingBox() end

---@return string
function File:ReadString() end

---@return string
function File:ReadFileID() end

---@return StringHash|string
function File:ReadStringHash() end

---@return VectorBuffer
function File:ReadBuffer() end

---@return ResourceRef
function File:ReadResourceRef() end

---@return ResourceRefList
function File:ReadResourceRefList() end

---@return Variant
function File:ReadVariant() end

---@param type VariantType
---@return Variant
function File:ReadVariant(type) end

---@return VariantVector
function File:ReadVariantVector() end

---@return VariantMap
function File:ReadVariantMap() end

---@return integer
function File:ReadVLE() end

---@return integer
function File:ReadNetID() end

---@return string
function File:ReadLine() end

---@param buffer VectorBuffer
---@return integer
function File:Write(buffer) end

---@param value integer
---@return boolean
function File:WriteInt(value) end

---@param value integer
---@return boolean
function File:WriteInt64(value) end

---@param value integer
---@return boolean
function File:WriteShort(value) end

---@param value integer
---@return boolean
function File:WriteByte(value) end

---@param value integer
---@return boolean
function File:WriteUInt(value) end

---@param value integer
---@return boolean
function File:WriteUInt64(value) end

---@param value integer -- unsigned short
---@return boolean
function File:WriteUShort(value) end

---@param value number -- unsigned char
---@return boolean
function File:WriteUByte(value) end

---@param value boolean
---@return boolean
function File:WriteBool(value) end

---@param value number
---@return boolean
function File:WriteFloat(value) end

---@param value number
---@return boolean
function File:WriteDouble(value) end

---@param value IntRect
---@return boolean
function File:WriteIntRect(value) end

---@param value IntVector2
---@return boolean
function File:WriteIntVector2(value) end

---@param value IntVector3
---@return boolean
function File:WriteIntVector3(value) end

---@param value Rect
---@return boolean
function File:WriteRect(value) end

---@param value Vector2
---@return boolean
function File:WriteVector2(value) end

---@param value Vector3
---@return boolean
function File:WriteVector3(value) end

---@param value Vector3
---@param maxAbsCoord number
---@return boolean
function File:WritePackedVector3(value, maxAbsCoord) end

---@param value Vector4
---@return boolean
function File:WriteVector4(value) end

---@param value Quaternion
---@return boolean
function File:WriteQuaternion(value) end

---@param value Quaternion
---@return boolean
function File:WritePackedQuaternion(value) end

---@param value Matrix3
---@return boolean
function File:WriteMatrix3(value) end

---@param value Matrix3x4
---@return boolean
function File:WriteMatrix3x4(value) end

---@param value Matrix4
---@return boolean
function File:WriteMatrix4(value) end

---@param value Color
---@return boolean
function File:WriteColor(value) end

---@param value BoundingBox
---@return boolean
function File:WriteBoundingBox(value) end

---@param value string
---@return boolean
function File:WriteString(value) end

---@param value string
---@return boolean
function File:WriteFileID(value) end

---@param value StringHash|string
---@return boolean
function File:WriteStringHash(value) end

---@param buffer VectorBuffer
---@return boolean
function File:WriteBuffer(buffer) end

---@param value ResourceRef
---@return boolean
function File:WriteResourceRef(value) end

---@param value ResourceRefList
---@return boolean
function File:WriteResourceRefList(value) end

---@param value Variant
---@return boolean
function File:WriteVariant(value) end

---@param value Variant
---@return boolean
function File:WriteVariantData(value) end

---@param value VariantVector
---@return boolean
function File:WriteVariantVector(value) end

---@param value VariantMap
---@return boolean
function File:WriteVariantMap(value) end

---@param value integer
---@return boolean
function File:WriteVLE(value) end

---@param value integer
---@return boolean
function File:WriteNetID(value) end

---@param value string
---@return boolean
function File:WriteLine(value) end

