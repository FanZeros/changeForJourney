---@meta

--- Auto-generated from Graphics/ParticleEffect

---@alias EmitterType
---| integer # EmitterType enum values

---@type EmitterType
EMITTER_SPHERE = 0
---@type EmitterType
EMITTER_BOX = 1

---@class ColorFrame
---@overload fun(color: Color): ColorFrame
---@overload fun(color: Color, time: number): ColorFrame
---@overload fun(): ColorFrame
---@field color Color
---@field time number
ColorFrame = {}

---@overload fun(self: ColorFrame, color: Color): ColorFrame
---@overload fun(color: Color): ColorFrame
---@overload fun(self: ColorFrame, color: Color, time: number): ColorFrame
---@overload fun(color: Color, time: number): ColorFrame
---@return ColorFrame
function ColorFrame.new() end

---@param next ColorFrame
---@param time number
---@return Color
function ColorFrame:Interpolate(next, time) end


---@class TextureFrame
---@overload fun(): TextureFrame
---@field uv Rect
---@field time number
TextureFrame = {}

---@return TextureFrame
function TextureFrame.new() end


---@class ParticleEffect : Resource
---@overload fun(): ParticleEffect
---@field material Material
---@field numParticles integer
---@field updateInvisible boolean
---@field relative boolean
---@field scaled boolean
---@field sorted boolean
---@field fixedScreenSize boolean
---@field animationLodBias number
---@field emitterType EmitterType
---@field emitterSize Vector3
---@field minDirection Vector3
---@field maxDirection Vector3
---@field constantForce Vector3
---@field dampingForce number
---@field activeTime number
---@field inactiveTime number
---@field minEmissionRate number
---@field maxEmissionRate number
---@field minParticleSize Vector2
---@field maxParticleSize Vector2
---@field minTimeToLive number
---@field maxTimeToLive number
---@field minVelocity number
---@field maxVelocity number
---@field minRotation number
---@field maxRotation number
---@field minRotationSpeed number
---@field maxRotationSpeed number
---@field sizeAdd number
---@field sizeMul number
---@field numColorFrames integer
---@field numTextureFrames integer
ParticleEffect = {}

---@return ParticleEffect
function ParticleEffect.new() end

---@param material Material
---@return nil
function ParticleEffect:SetMaterial(material) end

---@param num integer
---@return nil
function ParticleEffect:SetNumParticles(num) end

---@param enable boolean
---@return nil
function ParticleEffect:SetUpdateInvisible(enable) end

---@param enable boolean
---@return nil
function ParticleEffect:SetRelative(enable) end

---@param enable boolean
---@return nil
function ParticleEffect:SetScaled(enable) end

---@param enable boolean
---@return nil
function ParticleEffect:SetSorted(enable) end

---@param enable boolean
---@return nil
function ParticleEffect:SetFixedScreenSize(enable) end

---@param lodBias number
---@return nil
function ParticleEffect:SetAnimationLodBias(lodBias) end

---@param type EmitterType
---@return nil
function ParticleEffect:SetEmitterType(type) end

---@param size Vector3
---@return nil
function ParticleEffect:SetEmitterSize(size) end

---@param direction Vector3
---@return nil
function ParticleEffect:SetMinDirection(direction) end

---@param direction Vector3
---@return nil
function ParticleEffect:SetMaxDirection(direction) end

---@param force Vector3
---@return nil
function ParticleEffect:SetConstantForce(force) end

---@param force number
---@return nil
function ParticleEffect:SetDampingForce(force) end

---@param time number
---@return nil
function ParticleEffect:SetActiveTime(time) end

---@param time number
---@return nil
function ParticleEffect:SetInactiveTime(time) end

---@param rate number
---@return nil
function ParticleEffect:SetMinEmissionRate(rate) end

---@param rate number
---@return nil
function ParticleEffect:SetMaxEmissionRate(rate) end

---@param size Vector2
---@return nil
function ParticleEffect:SetMinParticleSize(size) end

---@param size Vector2
---@return nil
function ParticleEffect:SetMaxParticleSize(size) end

---@param time number
---@return nil
function ParticleEffect:SetMinTimeToLive(time) end

---@param time number
---@return nil
function ParticleEffect:SetMaxTimeToLive(time) end

---@param velocity number
---@return nil
function ParticleEffect:SetMinVelocity(velocity) end

---@param velocity number
---@return nil
function ParticleEffect:SetMaxVelocity(velocity) end

---@param rotation number
---@return nil
function ParticleEffect:SetMinRotation(rotation) end

---@param rotation number
---@return nil
function ParticleEffect:SetMaxRotation(rotation) end

---@param speed number
---@return nil
function ParticleEffect:SetMinRotationSpeed(speed) end

---@param speed number
---@return nil
function ParticleEffect:SetMaxRotationSpeed(speed) end

---@param sizeAdd number
---@return nil
function ParticleEffect:SetSizeAdd(sizeAdd) end

---@param sizeMul number
---@return nil
function ParticleEffect:SetSizeMul(sizeMul) end

---@param color Color
---@param time number
---@return nil
function ParticleEffect:AddColorTime(color, time) end

---@param colorFrame ColorFrame
---@return nil
function ParticleEffect:AddColorFrame(colorFrame) end

---@param index integer
---@return nil
function ParticleEffect:RemoveColorFrame(index) end

---@param index integer
---@param colorFrame ColorFrame
---@return nil
function ParticleEffect:SetColorFrame(index, colorFrame) end

---@param number integer
---@return nil
function ParticleEffect:SetNumColorFrames(number) end

---@return nil
function ParticleEffect:SortColorFrames() end

---@param uv Rect
---@param time number
---@return nil
function ParticleEffect:AddTextureTime(uv, time) end

---@param textureFrame TextureFrame
---@return nil
function ParticleEffect:AddTextureFrame(textureFrame) end

---@param index integer
---@return nil
function ParticleEffect:RemoveTextureFrame(index) end

---@param index integer
---@param textureFrame TextureFrame
---@return nil
function ParticleEffect:SetTextureFrame(index, textureFrame) end

---@param number integer
---@return nil
function ParticleEffect:SetNumTextureFrames(number) end

---@return nil
function ParticleEffect:SortTextureFrames() end

---@param cloneName? string
---@return ParticleEffect
function ParticleEffect:Clone(cloneName) end

---@return Material
function ParticleEffect:GetMaterial() end

---@return integer
function ParticleEffect:GetNumParticles() end

---@return boolean
function ParticleEffect:GetUpdateInvisible() end

---@return boolean
function ParticleEffect:IsRelative() end

---@return boolean
function ParticleEffect:IsScaled() end

---@return boolean
function ParticleEffect:IsSorted() end

---@return boolean
function ParticleEffect:IsFixedScreenSize() end

---@return number
function ParticleEffect:GetAnimationLodBias() end

---@return EmitterType
function ParticleEffect:GetEmitterType() end

---@return Vector3
function ParticleEffect:GetEmitterSize() end

---@return Vector3
function ParticleEffect:GetMinDirection() end

---@return Vector3
function ParticleEffect:GetMaxDirection() end

---@return Vector3
function ParticleEffect:GetConstantForce() end

---@return number
function ParticleEffect:GetDampingForce() end

---@return number
function ParticleEffect:GetActiveTime() end

---@return number
function ParticleEffect:GetInactiveTime() end

---@return number
function ParticleEffect:GetMinEmissionRate() end

---@return number
function ParticleEffect:GetMaxEmissionRate() end

---@return Vector2
function ParticleEffect:GetMinParticleSize() end

---@return Vector2
function ParticleEffect:GetMaxParticleSize() end

---@return number
function ParticleEffect:GetMinTimeToLive() end

---@return number
function ParticleEffect:GetMaxTimeToLive() end

---@return number
function ParticleEffect:GetMinVelocity() end

---@return number
function ParticleEffect:GetMaxVelocity() end

---@return number
function ParticleEffect:GetMinRotation() end

---@return number
function ParticleEffect:GetMaxRotation() end

---@return number
function ParticleEffect:GetMinRotationSpeed() end

---@return number
function ParticleEffect:GetMaxRotationSpeed() end

---@return number
function ParticleEffect:GetSizeAdd() end

---@return number
function ParticleEffect:GetSizeMul() end

---@return integer
function ParticleEffect:GetNumColorFrames() end

---@param index integer
---@return ColorFrame
function ParticleEffect:GetColorFrame(index) end

---@return integer
function ParticleEffect:GetNumTextureFrames() end

---@param index integer
---@return TextureFrame
function ParticleEffect:GetTextureFrame(index) end

