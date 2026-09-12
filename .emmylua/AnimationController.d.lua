---@meta

--- Auto-generated from Graphics/AnimationController

---@class AnimationControl
---@overload fun(): AnimationControl
---@field name string
---@field hash StringHash|string
---@field speed number
---@field targetWeight number
---@field fadeTime number
---@field autoFadeTime number
---@field removeOnCompletion boolean
AnimationControl = {}

---@return AnimationControl
function AnimationControl.new() end


---@class AnimationController : Component
AnimationController = {}

---@param name string
---@param layer number -- unsigned char
---@param looped boolean
---@param fadeInTime? number
---@return boolean
function AnimationController:Play(name, layer, looped, fadeInTime) end

---@param name string
---@param layer number -- unsigned char
---@param looped boolean
---@param fadeTime? number
---@return boolean
function AnimationController:PlayExclusive(name, layer, looped, fadeTime) end

---@param name string
---@param fadeOutTime? number
---@return boolean
function AnimationController:Stop(name, fadeOutTime) end

---@param layer number -- unsigned char
---@param fadeOutTime? number
---@return nil
function AnimationController:StopLayer(layer, fadeOutTime) end

---@param fadeTime? number
---@return nil
function AnimationController:StopAll(fadeTime) end

---@param name string
---@param targetWeight number
---@param fadeTime number
---@return boolean
function AnimationController:Fade(name, targetWeight, fadeTime) end

---@param name string
---@param targetWeight number
---@param fadeTime number
---@return boolean
function AnimationController:FadeOthers(name, targetWeight, fadeTime) end

---@param name string
---@param layer number -- unsigned char
---@return boolean
function AnimationController:SetLayer(name, layer) end

---@param name string
---@param startBoneName string
---@return boolean
function AnimationController:SetStartBone(name, startBoneName) end

---@param name string
---@param time number
---@return boolean
function AnimationController:SetTime(name, time) end

---@param name string
---@param weight number
---@return boolean
function AnimationController:SetWeight(name, weight) end

---@param name string
---@param enable boolean
---@return boolean
function AnimationController:SetLooped(name, enable) end

---@param name string
---@param mode AnimationBlendMode
---@return boolean
function AnimationController:SetBlendMode(name, mode) end

---@param name string
---@param speed number
---@return boolean
function AnimationController:SetSpeed(name, speed) end

---@param name string
---@param fadeOutTime number
---@return boolean
function AnimationController:SetAutoFade(name, fadeOutTime) end

---@param name string
---@param removeOnCompletion boolean
---@return boolean
function AnimationController:SetRemoveOnCompletion(name, removeOnCompletion) end

---@param name string
---@return boolean
function AnimationController:IsPlaying(name) end

---@param layer number -- unsigned char
---@return boolean
function AnimationController:IsPlaying(layer) end

---@param name string
---@return boolean
function AnimationController:IsFadingIn(name) end

---@param name string
---@return boolean
function AnimationController:IsFadingOut(name) end

---@param name string
---@return boolean
function AnimationController:IsAtEnd(name) end

---@param name string
---@return number
function AnimationController:GetLayer(name) end

---@param name string
---@return Bone
function AnimationController:GetStartBone(name) end

---@param name string
---@return string
function AnimationController:GetStartBoneName(name) end

---@param name string
---@return number
function AnimationController:GetTime(name) end

---@param name string
---@return number
function AnimationController:GetWeight(name) end

---@param name string
---@return boolean
function AnimationController:IsLooped(name) end

---@param name string
---@return AnimationBlendMode
function AnimationController:GetBlendMode(name) end

---@param name string
---@return number
function AnimationController:GetLength(name) end

---@param name string
---@return number
function AnimationController:GetSpeed(name) end

---@param name string
---@return number
function AnimationController:GetFadeTarget(name) end

---@param name string
---@return number
function AnimationController:GetFadeTime(name) end

---@param name string
---@return number
function AnimationController:GetAutoFade(name) end

---@param name string
---@return boolean
function AnimationController:GetRemoveOnCompletion(name) end

---@param name string
---@return AnimationState
function AnimationController:GetAnimationState(name) end

---@param nameHash StringHash|string
---@return AnimationState
function AnimationController:GetAnimationState(nameHash) end

---@param index integer
---@return AnimationControl
function AnimationController:GetAnimation(index) end

---@return integer
function AnimationController:GetNumAnimations() end

