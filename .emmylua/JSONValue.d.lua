---@meta

--- Auto-generated from Resource/JSONValue

---@alias JSONValueType
---| integer # JSONValueType enum values

---@type JSONValueType
JSON_NULL = 0
---@type JSONValueType
JSON_BOOL = 1
---@type JSONValueType
JSON_NUMBER = 2
---@type JSONValueType
JSON_STRING = 3
---@type JSONValueType
JSON_ARRAY = 4
---@type JSONValueType
JSON_OBJECT = 5

---@alias JSONNumberType
---| integer # JSONNumberType enum values

---@type JSONNumberType
JSONNT_NAN = 0
---@type JSONNumberType
JSONNT_INT = 1
---@type JSONNumberType
JSONNT_UINT = 2
---@type JSONNumberType
JSONNT_FLOAT_DOUBLE = 3

---@class JSONObject
JSONObject = {}


---@class JSONArray
JSONArray = {}


---@class JSONValue
---@overload fun(value: boolean): JSONValue
---@overload fun(value: string): JSONValue
---@overload fun(value: number): JSONValue
---@overload fun(value: JSONArray): JSONValue
---@overload fun(value: JSONObject): JSONValue
---@overload fun(value: JSONValue): JSONValue
---@overload fun(): JSONValue
---@field EMPTY JSONValue
---@field emptyArray JSONArray
---@field emptyObject JSONObject
---@field null boolean
---@field valueType JSONValueType
---@field numberType JSONNumberType
---@field valueTypeName string
---@field numberTypeName string
JSONValue = {}

---@overload fun(self: JSONValue, value: boolean): JSONValue
---@overload fun(value: boolean): JSONValue
---@overload fun(self: JSONValue, value: string): JSONValue
---@overload fun(value: string): JSONValue
---@overload fun(self: JSONValue, value: number): JSONValue
---@overload fun(value: number): JSONValue
---@overload fun(self: JSONValue, value: JSONArray): JSONValue
---@overload fun(value: JSONArray): JSONValue
---@overload fun(self: JSONValue, value: JSONObject): JSONValue
---@overload fun(value: JSONObject): JSONValue
---@overload fun(self: JSONValue, value: JSONValue): JSONValue
---@overload fun(value: JSONValue): JSONValue
---@return JSONValue
function JSONValue.new() end

---@param value boolean
---@return nil
function JSONValue:SetBool(value) end

---@param value integer
---@return nil
function JSONValue:SetInt(value) end

---@param value integer
---@return nil
function JSONValue:SetUint(value) end

---@param value number
---@return nil
function JSONValue:SetFloat(value) end

---@param value number
---@return nil
function JSONValue:SetDouble(value) end

---@param value string
---@return nil
function JSONValue:SetString(value) end

---@param value JSONArray
---@return nil
function JSONValue:SetArray(value) end

---@param value JSONObject
---@return nil
function JSONValue:SetObject(value) end

---@param value Variant
---@return nil
function JSONValue:SetVariant(value) end

---@param value VariantMap
---@return nil
function JSONValue:SetVariantMap(value) end

---@return JSONValueType
function JSONValue:GetValueType() end

---@return JSONNumberType
function JSONValue:GetNumberType() end

---@return string
function JSONValue:GetValueTypeName() end

---@return string
function JSONValue:GetNumberTypeName() end

---@return boolean
function JSONValue:IsNull() end

---@return boolean
function JSONValue:IsBool() end

---@return boolean
function JSONValue:IsNumber() end

---@return boolean
function JSONValue:IsString() end

---@return boolean
function JSONValue:IsArray() end

---@return boolean
function JSONValue:IsObject() end

---@return boolean
function JSONValue:GetBool() end

---@return integer
function JSONValue:GetInt() end

---@return integer
function JSONValue:GetUInt() end

---@return number
function JSONValue:GetFloat() end

---@return number
function JSONValue:GetDouble() end

---@return string
function JSONValue:GetString() end

---@return JSONArray
function JSONValue:GetArray() end

---@return JSONObject
function JSONValue:GetObject() end

---@return Variant
function JSONValue:GetVariant() end

---@return VariantMap
function JSONValue:GetVariantMap() end

---@param value JSONValue
---@return nil
function JSONValue:Push(value) end

---@return nil
function JSONValue:Pop() end

---@param pos integer
---@param value JSONValue
---@return nil
function JSONValue:Insert(pos, value) end

---@param pos integer
---@param length? integer
---@return nil
function JSONValue:Erase(pos, length) end

---@param key string
---@return boolean
function JSONValue:Erase(key) end

---@param newSize integer
---@return nil
function JSONValue:Resize(newSize) end

---@return integer
function JSONValue:Size() end

---@param key string
---@param value JSONValue
---@return nil
function JSONValue:Set(key, value) end

---@param key string
---@return JSONValue
function JSONValue:Get(key) end

---@param key string
---@return boolean
function JSONValue:Contains(key) end

---@return nil
function JSONValue:Clear() end

