---@meta

--- Auto-generated from Graphics/AnimatedModel

---@class AnimatedModel : StaticModel
---@field model Model
---@field skeleton Skeleton
---@field numAnimationStates integer
---@field animationLodBias number
---@field updateInvisible boolean
---@field numMorphs integer
---@field master boolean
AnimatedModel = {}

---@param model Model
---@return nil
function AnimatedModel:SetModel(model) end

---@param animation Animation
---@return AnimationState
function AnimatedModel:AddAnimationState(animation) end

---@param animation Animation
---@return nil
function AnimatedModel:RemoveAnimationState(animation) end

---@param animationName string
---@return nil
function AnimatedModel:RemoveAnimationState(animationName) end

---@param animationNameHash StringHash|string
---@return nil
function AnimatedModel:RemoveAnimationState(animationNameHash) end

---@param state AnimationState
---@return nil
function AnimatedModel:RemoveAnimationState(state) end

---@param index integer
---@return nil
function AnimatedModel:RemoveAnimationState(index) end

---@return nil
function AnimatedModel:RemoveAllAnimationStates() end

---@param bias number
---@return nil
function AnimatedModel:SetAnimationLodBias(bias) end

---@param enable boolean
---@return nil
function AnimatedModel:SetUpdateInvisible(enable) end

---@param name string
---@param weight number
---@return nil
function AnimatedModel:SetMorphWeight(name, weight) end

---@param nameHash StringHash|string
---@param weight number
---@return nil
function AnimatedModel:SetMorphWeight(nameHash, weight) end

---@param index integer
---@param weight number
---@return nil
function AnimatedModel:SetMorphWeight(index, weight) end

---@return nil
function AnimatedModel:ResetMorphWeights() end

---@return Skeleton
function AnimatedModel:GetSkeleton() end

---@return integer
function AnimatedModel:GetNumAnimationStates() end

---@param animation Animation
---@return AnimationState
function AnimatedModel:GetAnimationState(animation) end

---@param animationName string
---@return AnimationState
function AnimatedModel:GetAnimationState(animationName) end

---@param animationNameHash StringHash|string
---@return AnimationState
function AnimatedModel:GetAnimationState(animationNameHash) end

---@param index integer
---@return AnimationState
function AnimatedModel:GetAnimationState(index) end

---@return number
function AnimatedModel:GetAnimationLodBias() end

---@return boolean
function AnimatedModel:GetUpdateInvisible() end

---@return integer
function AnimatedModel:GetNumMorphs() end

---@param name string
---@return number
function AnimatedModel:GetMorphWeight(name) end

---@param nameHash StringHash|string
---@return number
function AnimatedModel:GetMorphWeight(nameHash) end

---@param index integer
---@return number
function AnimatedModel:GetMorphWeight(index) end

---@return boolean
function AnimatedModel:IsMaster() end

---@return nil
function AnimatedModel:UpdateBoneBoundingBox() end

