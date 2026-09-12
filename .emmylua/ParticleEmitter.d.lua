---@meta

--- Auto-generated from Graphics/ParticleEmitter


---@class ParticleEmitter : BillboardSet
---@field effect ParticleEffect
---@field numParticles integer
---@field emitting boolean
---@field serializeParticles boolean
---@field autoRemoveMode AutoRemoveMode
ParticleEmitter = {}

---@param effect ParticleEffect
---@return nil
function ParticleEmitter:SetEffect(effect) end

---@param num integer
---@return nil
function ParticleEmitter:SetNumParticles(num) end

---@param enable boolean
---@return nil
function ParticleEmitter:SetEmitting(enable) end

---@param enable boolean
---@return nil
function ParticleEmitter:SetSerializeParticles(enable) end

---@param mode AutoRemoveMode
---@return nil
function ParticleEmitter:SetAutoRemoveMode(mode) end

---@return nil
function ParticleEmitter:ResetEmissionTimer() end

---@return nil
function ParticleEmitter:RemoveAllParticles() end

---@return nil
function ParticleEmitter:Reset() end

---@return nil
function ParticleEmitter:ApplyEffect() end

---@return ParticleEffect
function ParticleEmitter:GetEffect() end

---@return integer
function ParticleEmitter:GetNumParticles() end

---@return boolean
function ParticleEmitter:IsEmitting() end

---@return boolean
function ParticleEmitter:GetSerializeParticles() end

---@return AutoRemoveMode
function ParticleEmitter:GetAutoRemoveMode() end

