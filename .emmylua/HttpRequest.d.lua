---@meta

--- Auto-generated from Network/HttpRequest

---@alias HttpRequestState
---| integer # HttpRequestState enum values

---@type HttpRequestState
HTTP_INITIALIZING = 0
---@type HttpRequestState
HTTP_ERROR = 1
---@type HttpRequestState
HTTP_OPEN = 2
---@type HttpRequestState
HTTP_CLOSED = 3

---@class HttpRequest : RefCounted
---@field URL string
---@field verb string
---@field error string
---@field state HttpRequestState
---@field availableSize integer
---@field open boolean
HttpRequest = {}

---@return string
function HttpRequest:GetURL() end

---@return string
function HttpRequest:GetVerb() end

---@return string
function HttpRequest:GetError() end

---@return HttpRequestState
function HttpRequest:GetState() end

---@return integer
function HttpRequest:GetAvailableSize() end

---@return boolean
function HttpRequest:IsOpen() end

---@param size integer
---@return VectorBuffer
function HttpRequest:Read(size) end

---@return boolean
function HttpRequest:IsEof() end

---@return integer
function HttpRequest:ReadInt() end

---@return integer
function HttpRequest:ReadShort() end

---@return integer
function HttpRequest:ReadByte() end

---@return integer
function HttpRequest:ReadUInt() end

---@return integer
function HttpRequest:ReadUShort() end

---@return number
function HttpRequest:ReadUByte() end

---@return boolean
function HttpRequest:ReadBool() end

---@return number
function HttpRequest:ReadFloat() end

---@return number
function HttpRequest:ReadDouble() end

---@return IntRect
function HttpRequest:ReadIntRect() end

---@return IntVector2
function HttpRequest:ReadIntVector2() end

---@return IntVector3
function HttpRequest:ReadIntVector3() end

---@return Rect
function HttpRequest:ReadRect() end

---@return Vector2
function HttpRequest:ReadVector2() end

---@return Vector3
function HttpRequest:ReadVector3() end

---@param maxAbsCoord number
---@return Vector3
function HttpRequest:ReadPackedVector3(maxAbsCoord) end

---@return Vector4
function HttpRequest:ReadVector4() end

---@return Quaternion
function HttpRequest:ReadQuaternion() end

---@return Quaternion
function HttpRequest:ReadPackedQuaternion() end

---@return Matrix3
function HttpRequest:ReadMatrix3() end

---@return Matrix3x4
function HttpRequest:ReadMatrix3x4() end

---@return Matrix4
function HttpRequest:ReadMatrix4() end

---@return Color
function HttpRequest:ReadColor() end

---@return BoundingBox
function HttpRequest:ReadBoundingBox() end

---@return string
function HttpRequest:ReadString() end

---@return string
function HttpRequest:ReadFileID() end

---@return StringHash|string
function HttpRequest:ReadStringHash() end

---@return VectorBuffer
function HttpRequest:ReadBuffer() end

---@return ResourceRef
function HttpRequest:ReadResourceRef() end

---@return ResourceRefList
function HttpRequest:ReadResourceRefList() end

---@return Variant
function HttpRequest:ReadVariant() end

---@param type VariantType
---@return Variant
function HttpRequest:ReadVariant(type) end

---@return VariantVector
function HttpRequest:ReadVariantVector() end

---@return VariantMap
function HttpRequest:ReadVariantMap() end

---@return integer
function HttpRequest:ReadVLE() end

---@return integer
function HttpRequest:ReadNetID() end

---@return string
function HttpRequest:ReadLine() end

