---@meta

--- Auto-generated from Resource/XMLElement

---@class XMLElement
---@field EMPTY XMLElement
---@field null boolean
---@field name string
---@field parent XMLElement
---@field value string
---@field numAttributes integer
---@field file XMLFile
XMLElement = {}

---@param element XMLElement
---@param asCopy boolean
---@return boolean
function XMLElement:AppendChild(element, asCopy) end

---@param name string
---@return XMLElement
function XMLElement:CreateChild(name) end

---@param name string
---@return XMLElement
function XMLElement:GetOrCreateChild(name) end

---@param element XMLElement
---@return boolean
function XMLElement:RemoveChild(element) end

---@param name string
---@return boolean
function XMLElement:RemoveChild(name) end

---@param name? string
---@return boolean
function XMLElement:RemoveChildren(name) end

---@param name? string
---@return boolean
function XMLElement:RemoveAttribute(name) end

---@return boolean
function XMLElement:Remove() end

---@param value string
---@return boolean
function XMLElement:SetValue(value) end

---@param name string
---@param value string
---@return boolean
function XMLElement:SetAttribute(name, value) end

---@param value string
---@return boolean
function XMLElement:SetAttribute(value) end

---@param name string
---@param value boolean
---@return boolean
function XMLElement:SetBool(name, value) end

---@param value BoundingBox
---@return boolean
function XMLElement:SetBoundingBox(value) end

---@param name string
---@param value Color
---@return boolean
function XMLElement:SetColor(name, value) end

---@param name string
---@param value number
---@return boolean
function XMLElement:SetFloat(name, value) end

---@param name string
---@param value number
---@return boolean
function XMLElement:SetDouble(name, value) end

---@param name string
---@param value integer
---@return boolean
function XMLElement:SetUInt(name, value) end

---@param name string
---@param value integer
---@return boolean
function XMLElement:SetInt(name, value) end

---@param name string
---@param value integer
---@return boolean
function XMLElement:SetUInt64(name, value) end

---@param name string
---@param value integer
---@return boolean
function XMLElement:SetInt64(name, value) end

---@param name string
---@param value IntRect
---@return boolean
function XMLElement:SetIntRect(name, value) end

---@param name string
---@param value IntVector2
---@return boolean
function XMLElement:SetIntVector2(name, value) end

---@param name string
---@param value IntVector3
---@return boolean
function XMLElement:SetIntVector3(name, value) end

---@param name string
---@param value Rect
---@return boolean
function XMLElement:SetRect(name, value) end

---@param name string
---@param value Quaternion
---@return boolean
function XMLElement:SetQuaternion(name, value) end

---@param name string
---@param value string
---@return boolean
function XMLElement:SetString(name, value) end

---@param value Variant
---@return boolean
function XMLElement:SetVariant(value) end

---@param value Variant
---@return boolean
function XMLElement:SetVariantValue(value) end

---@param value ResourceRef
---@return boolean
function XMLElement:SetResourceRef(value) end

---@param value ResourceRefList
---@return boolean
function XMLElement:SetResourceRefList(value) end

---@param name string
---@param value Vector2
---@return boolean
function XMLElement:SetVector2(name, value) end

---@param name string
---@param value Vector3
---@return boolean
function XMLElement:SetVector3(name, value) end

---@param name string
---@param value Vector4
---@return boolean
function XMLElement:SetVector4(name, value) end

---@param name string
---@param value Variant
---@return boolean
function XMLElement:SetVectorVariant(name, value) end

---@param name string
---@param value Matrix3
---@return boolean
function XMLElement:SetMatrix3(name, value) end

---@param name string
---@param value Matrix3x4
---@return boolean
function XMLElement:SetMatrix3x4(name, value) end

---@param name string
---@param value Matrix4
---@return boolean
function XMLElement:SetMatrix4(name, value) end

---@return boolean
function XMLElement:IsNull() end

---@return boolean
function XMLElement:NotNull() end

---@return string
function XMLElement:GetName() end

---@param name string
---@return boolean
function XMLElement:HasChild(name) end

---@param name? string
---@return XMLElement
function XMLElement:GetChild(name) end

---@param name? string
---@return XMLElement
function XMLElement:GetNext(name) end

---@return XMLElement
function XMLElement:GetParent() end

---@return integer
function XMLElement:GetNumAttributes() end

---@param name string
---@return boolean
function XMLElement:HasAttribute(name) end

---@return string
function XMLElement:GetValue() end

---@param name? string
---@return string
function XMLElement:GetAttribute(name) end

---@param name string
---@return string
function XMLElement:GetAttributeLower(name) end

---@param name string
---@return string
function XMLElement:GetAttributeUpper(name) end

---@return string[]
function XMLElement:GetAttributeNames() end

---@param name string
---@return boolean
function XMLElement:GetBool(name) end

---@return BoundingBox
function XMLElement:GetBoundingBox() end

---@param name string
---@return Color
function XMLElement:GetColor(name) end

---@param name string
---@return number
function XMLElement:GetFloat(name) end

---@param name string
---@return number
function XMLElement:GetDouble(name) end

---@param name string
---@return integer
function XMLElement:GetUInt(name) end

---@param name string
---@return integer
function XMLElement:GetInt(name) end

---@param name string
---@return integer
function XMLElement:GetUInt64(name) end

---@param name string
---@return integer
function XMLElement:GetInt64(name) end

---@param name string
---@return IntRect
function XMLElement:GetIntRect(name) end

---@param name string
---@return IntVector2
function XMLElement:GetIntVector2(name) end

---@param name string
---@return IntVector3
function XMLElement:GetIntVector3(name) end

---@param name string
---@return Rect
function XMLElement:GetRect(name) end

---@param name string
---@return Quaternion
function XMLElement:GetQuaternion(name) end

---@return Variant
function XMLElement:GetVariant() end

---@param type VariantType
---@return Variant
function XMLElement:GetVariantValue(type) end

---@return ResourceRef
function XMLElement:GetResourceRef() end

---@return ResourceRefList
function XMLElement:GetResourceRefList() end

---@return VariantMap
function XMLElement:GetVariantMap() end

---@param name string
---@return Vector2
function XMLElement:GetVector2(name) end

---@param name string
---@return Vector3
function XMLElement:GetVector3(name) end

---@param name string
---@return Vector4
function XMLElement:GetVector4(name) end

---@param name string
---@return Vector4
function XMLElement:GetVector(name) end

---@param name string
---@return Matrix3
function XMLElement:GetMatrix3(name) end

---@param name string
---@return Matrix3x4
function XMLElement:GetMatrix3x4(name) end

---@param name string
---@return Matrix4
function XMLElement:GetMatrix4(name) end

---@return XMLFile
function XMLElement:GetFile() end

