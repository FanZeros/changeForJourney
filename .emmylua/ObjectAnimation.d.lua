---@meta

--- Auto-generated from Scene/ObjectAnimation

---@alias WrapMode
---| integer # WrapMode enum values

---@type WrapMode
WM_LOOP = 0
---@type WrapMode
WM_ONCE = 1
---@type WrapMode
WM_CLAMP = 2

---@class ObjectAnimation : Resource
---@overload fun(): ObjectAnimation
ObjectAnimation = {}

---@return ObjectAnimation
function ObjectAnimation.new() end

---@param name string
---@param attributeAnimation ValueAnimation
---@param wrapMode? WrapMode
---@param speed? number
---@return nil
function ObjectAnimation:AddAttributeAnimation(name, attributeAnimation, wrapMode, speed) end

---@param name string
---@return nil
function ObjectAnimation:RemoveAttributeAnimation(name) end

---@param attributeAnimation ValueAnimation
---@return nil
function ObjectAnimation:RemoveAttributeAnimation(attributeAnimation) end

---@param name string
---@return ValueAnimation
function ObjectAnimation:GetAttributeAnimation(name) end

---@param name string
---@return WrapMode
function ObjectAnimation:GetAttributeAnimationWrapMode(name) end

---@param name string
---@return number
function ObjectAnimation:GetAttributeAnimationSpeed(name) end

