---@meta

--- Auto-generated from Urho2D/ParticleEmitter2D

---@class ParticleEmitter2D : Drawable2D
---@field effect ParticleEffect2D
---@field sprite Sprite2D
---@field blendMode BlendMode
---@field emitting boolean
ParticleEmitter2D = {}

---@param effect ParticleEffect2D
---@return nil
function ParticleEmitter2D:SetEffect(effect) end

---@param sprite Sprite2D
---@return nil
function ParticleEmitter2D:SetSprite(sprite) end

---@param blendMode BlendMode
---@return nil
function ParticleEmitter2D:SetBlendMode(blendMode) end

---@param emitting boolean
---@return nil
function ParticleEmitter2D:SetEmitting(emitting) end

---@return ParticleEffect2D
function ParticleEmitter2D:GetEffect() end

---@return Sprite2D
function ParticleEmitter2D:GetSprite() end

---@return BlendMode
function ParticleEmitter2D:GetBlendMode() end

---@return boolean
function ParticleEmitter2D:IsEmitting() end

