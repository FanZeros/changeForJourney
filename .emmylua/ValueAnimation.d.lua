---@meta

--- Auto-generated from Scene/ValueAnimation

---@alias InterpMethod
---| integer # InterpMethod enum values

---@type InterpMethod
IM_NONE = 0
---@type InterpMethod
IM_LINEAR = 1
---@type InterpMethod
IM_SPLINE = 2

---@class ValueAnimation : Resource
---@overload fun(): ValueAnimation
---@field interpolationMethod InterpMethod
---@field splineTension number
---@field valueType VariantType
ValueAnimation = {}

---@return ValueAnimation
function ValueAnimation.new() end

---@param method InterpMethod
---@return nil
function ValueAnimation:SetInterpolationMethod(method) end

---@param tension number
---@return nil
function ValueAnimation:SetSplineTension(tension) end

---@param valueType VariantType
---@return nil
function ValueAnimation:SetValueType(valueType) end

---@param time number
---@param value Variant
---@return boolean
function ValueAnimation:SetKeyFrame(time, value) end

---@param time number
---@param eventType StringHash|string
---@param eventData? VariantMap
---@return nil
function ValueAnimation:SetEventFrame(time, eventType, eventData) end

---@return InterpMethod
function ValueAnimation:GetInterpolationMethod() end

---@return number
function ValueAnimation:GetSplineTension() end

---@return VariantType
function ValueAnimation:GetValueType() end

