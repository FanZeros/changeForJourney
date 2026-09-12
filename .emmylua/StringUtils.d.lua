---@meta

--- Auto-generated from Core/StringUtils

-- Global functions
---@param source string
---@return boolean
function ToBool(source) end

---@param source string
---@return number
function ToFloat(source) end

---@param source string
---@param base? integer
---@return integer
function ToInt(source, base) end

---@param source string
---@param base? integer
---@return integer
function ToUInt(source, base) end

---@param source string
---@param base? integer
---@return integer
function ToInt64(source, base) end

---@param source string
---@param base? integer
---@return integer
function ToUInt64(source, base) end

---@param source string
---@return Color
function ToColor(source) end

---@param source string
---@return IntRect
function ToIntRect(source) end

---@param source string
---@return IntVector2
function ToIntVector2(source) end

---@param source string
---@return IntVector3
function ToIntVector3(source) end

---@param source string
---@return Quaternion
function ToQuaternion(source) end

---@param source string
---@return Rect
function ToRect(source) end

---@param source string
---@return Vector2
function ToVector2(source) end

---@param source string
---@return Vector3
function ToVector3(source) end

---@param source string
---@param allowMissingCoords? boolean
---@return Vector4
function ToVector4(source, allowMissingCoords) end

---@param source string
---@return Matrix3
function ToMatrix3(source) end

---@param source string
---@return Matrix3x4
function ToMatrix3x4(source) end

---@param source string
---@return Matrix4
function ToMatrix4(source) end

---@param value function|string -- function or function name
---@return string
function ToString(value) end

---@param value integer
---@return string
function ToStringHex(value) end

---@param ch integer
---@return boolean
function IsAlpha(ch) end

---@param ch integer
---@return boolean
function IsDigit(ch) end

---@param ch integer
---@return integer
function ToUpper(ch) end

---@param ch integer
---@return integer
function ToLower(ch) end
