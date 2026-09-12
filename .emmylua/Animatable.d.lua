---@meta

--- Auto-generated from Scene/Animatable


---@class Animatable : Serializable
---@field animationEnabled boolean
---@field objectAnimation ObjectAnimation
Animatable = {}

---@param enable boolean
---@return nil
function Animatable:SetAnimationEnabled(enable) end

---@param time number
---@return nil
function Animatable:SetAnimationTime(time) end

---@param objectAnimation ObjectAnimation
---@return nil
function Animatable:SetObjectAnimation(objectAnimation) end

---@param name string
---@param attributeAnimation ValueAnimation
---@param wrapMode? WrapMode
---@param speed? number
---@return nil
function Animatable:SetAttributeAnimation(name, attributeAnimation, wrapMode, speed) end

---@param name string
---@param wrapMode WrapMode
---@return nil
function Animatable:SetAttributeAnimationWrapMode(name, wrapMode) end

---@param name string
---@param speed number
---@return nil
function Animatable:SetAttributeAnimationSpeed(name, speed) end

---@param name string
---@param time number
---@return nil
function Animatable:SetAttributeAnimationTime(name, time) end

---@return nil
function Animatable:RemoveObjectAnimation() end

---@param name string
---@return nil
function Animatable:RemoveAttributeAnimation(name) end

---@return boolean
function Animatable:GetAnimationEnabled() end

---@return ObjectAnimation
function Animatable:GetObjectAnimation() end

---@param name string
---@return ValueAnimation
function Animatable:GetAttributeAnimation(name) end

---@param name string
---@return WrapMode
function Animatable:GetAttributeAnimationWrapMode(name) end

---@param name string
---@return number
function Animatable:GetAttributeAnimationSpeed(name) end

---@param name string
---@return number
function Animatable:GetAttributeAnimationTime(name) end

