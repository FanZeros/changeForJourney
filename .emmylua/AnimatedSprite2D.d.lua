---@meta

--- Auto-generated from Urho2D/AnimatedSprite2D

---@alias LoopMode2D
---| integer # LoopMode2D enum values

---@type LoopMode2D
LM_DEFAULT = 0
---@type LoopMode2D
LM_FORCE_LOOPED = 1
---@type LoopMode2D
LM_FORCE_CLAMPED = 2

---@class AnimatedSprite2D : StaticSprite2D
---@field speed number
---@field entity string
---@field animation string
---@field animationSet AnimationSet2D
---@field loopMode LoopMode2D
AnimatedSprite2D = {}

---@param animationSet AnimationSet2D
---@return nil
function AnimatedSprite2D:SetAnimationSet(animationSet) end

---@param entity string
---@return nil
function AnimatedSprite2D:SetEntity(entity) end

---@param name string
---@param loopMode? LoopMode2D
---@return nil
function AnimatedSprite2D:SetAnimation(name, loopMode) end

---@param loopMode LoopMode2D
---@return nil
function AnimatedSprite2D:SetLoopMode(loopMode) end

---@param speed number
---@return nil
function AnimatedSprite2D:SetSpeed(speed) end

---@return AnimationSet2D
function AnimatedSprite2D:GetAnimationSet() end

---@return string
function AnimatedSprite2D:GetEntity() end

---@return string
function AnimatedSprite2D:GetAnimation() end

---@return LoopMode2D
function AnimatedSprite2D:GetLoopMode() end

---@return number
function AnimatedSprite2D:GetSpeed() end

