---@meta

--- Auto-generated from Graphics/AnimationState

---@alias AnimationBlendMode
---| integer # AnimationBlendMode enum values

---@type AnimationBlendMode
ABM_LERP = 0
---@type AnimationBlendMode
ABM_ADDITIVE = 1

---@class AnimationState
---@overload fun(model: AnimatedModel, animation: Animation): AnimationState
---@overload fun(node: Node, animation: Animation): AnimationState
---@overload fun(): AnimationState
---@field animation Animation
---@field startBone Bone
---@field enabled boolean
---@field looped boolean
---@field weight number
---@field time number
---@field length number
---@field layer number -- unsigned char
---@field blendMode AnimationBlendMode
AnimationState = {}

---@overload fun(self: AnimationState, model: AnimatedModel, animation: Animation): AnimationState
---@overload fun(model: AnimatedModel, animation: Animation): AnimationState
---@overload fun(self: AnimationState, node: Node, animation: Animation): AnimationState
---@overload fun(node: Node, animation: Animation): AnimationState
---@return AnimationState
function AnimationState.new() end

---@param bone Bone
---@return nil
function AnimationState:SetStartBone(bone) end

---@param looped boolean
---@return nil
function AnimationState:SetLooped(looped) end

---@param weight number
---@return nil
function AnimationState:SetWeight(weight) end

---@param time number
---@return nil
function AnimationState:SetTime(time) end

---@param name string
---@param weight number
---@param recursive? boolean
---@return nil
function AnimationState:SetBoneWeight(name, weight, recursive) end

---@param nameHash StringHash|string
---@param weight number
---@param recursive? boolean
---@return nil
function AnimationState:SetBoneWeight(nameHash, weight, recursive) end

---@param index integer
---@param weight number
---@param recursive? boolean
---@return nil
function AnimationState:SetBoneWeight(index, weight, recursive) end

---@param delta number
---@return nil
function AnimationState:AddWeight(delta) end

---@param delta number
---@return nil
function AnimationState:AddTime(delta) end

---@param layer number -- unsigned char
---@return nil
function AnimationState:SetLayer(layer) end

---@param mode AnimationBlendMode
---@return nil
function AnimationState:SetBlendMode(mode) end

---@return Animation
function AnimationState:GetAnimation() end

---@return Bone
function AnimationState:GetStartBone() end

---@param name string
---@return number
function AnimationState:GetBoneWeight(name) end

---@param nameHash StringHash|string
---@return number
function AnimationState:GetBoneWeight(nameHash) end

---@param index integer
---@return number
function AnimationState:GetBoneWeight(index) end

---@param name string
---@return integer
function AnimationState:GetTrackIndex(name) end

---@param nameHash StringHash|string
---@return integer
function AnimationState:GetTrackIndex(nameHash) end

---@return boolean
function AnimationState:IsEnabled() end

---@return boolean
function AnimationState:IsLooped() end

---@return number
function AnimationState:GetWeight() end

---@return number
function AnimationState:GetTime() end

---@return number
function AnimationState:GetLength() end

---@return number
function AnimationState:GetLayer() end

---@return AnimationBlendMode
function AnimationState:GetBlendMode() end

