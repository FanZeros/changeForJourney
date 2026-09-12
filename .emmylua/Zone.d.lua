---@meta

--- Auto-generated from Graphics/Zone

---@alias AmbientSource
---| integer # AmbientSource enum values

---@type AmbientSource
AMBIENT_PREBAKED = 0
---@type AmbientSource
AMBIENT_SKYBOX = 1
---@type AmbientSource
AMBIENT_COLOR = 2

---@alias BloomMode
---| integer # BloomMode enum values

---@type BloomMode
BLOOM_MODE_LEGACY = 0
---@type BloomMode
BLOOM_MODE_PLUS = 1
---@type BloomMode
BLOOM_MODE_UE = 2

---@alias TonemapMode
---| integer # TonemapMode enum values

---@type TonemapMode
TONEMAP_MODE_NONE = 0
---@type TonemapMode
TONEMAP_MODE_ACES = 1
---@type TonemapMode
TONEMAP_MODE_LUT = 2

---@class ToonShadingParams
---@overload fun(): ToonShadingParams
---@field midpoint number
---@field shadowHSV Vector3
---@field skinShadowTint Color
---@field mainLightMaxContribution Color
---@field mainLightMultiplier Color
---@field rimTint Color
---@field rimIntensity number
---@field depthEffectsSimpleOffset number
---@field rimDepthThreshold number
---@field rimDepthFadeRange number
---@field faceDepthEffectsSimpleOffsetMultiplier number
---@field depthShadowInfluence number
---@field depthShadowThreshold number
---@field depthShadowFadeRange number
ToonShadingParams = {}

---@return ToonShadingParams
function ToonShadingParams.new() end


---@class Zone : Drawable
---@field boundingBox BoundingBox
---@field inverseWorldTransform Matrix3x4
---@field ambientColor Color
---@field ambientStartColor Color
---@field ambientEndColor Color
---@field fogColor Color
---@field fogDensity number
---@field fogStart number
---@field fogEnd number
---@field fogHeight number
---@field fogHeightScale number
---@field priority integer
---@field heightFog boolean
---@field skyFogIntensity number
---@field override boolean
---@field ambientGradient boolean
---@field zoneTexture Texture
---@field ambientSource AmbientSource
---@field sourceTexture Texture
---@field ambientIntensity number
---@field autoExposureEnabled boolean
---@field ssrEnabled boolean
---@field ssrUsePrevFrameColor boolean
---@field ssgiEnabled boolean
---@field ssgiQuality integer
---@field ssgiIntensity number
---@field ssaoRadius number
---@field ssaoIntensity number
---@field motionBlurEnabled boolean
---@field motionBlurAmount number
---@field motionBlurMaxDistortion number
---@field tonemapLUTEnabled boolean
---@field tonemapMode TonemapMode
---@field toonShadingParams ToonShadingParams
---@field bloomPlusEnabled boolean
---@field bloomThreshold number
---@field bloomWeight number
---@field bloomPlusIntensity number
---@field bloomMode BloomMode
---@field bloomUEIntensity number
---@field bloomUEThreshold number
---@field bloomUESizeScale number
---@field volumetricFogEnabled boolean
---@field volumetricFogOverrideLightColors boolean
---@field volumetricFogDirectionalInscatteringColor Color
---@field skyLightVolumetricScatteringIntensity number
---@field fxaaEnabled boolean
---@field vignetteEnabled boolean
---@field vignetteIntensity number
---@field vignetteTexture Texture
Zone = {}

---@param box BoundingBox
---@return nil
function Zone:SetBoundingBox(box) end

---@param color Color
---@return nil
function Zone:SetAmbientColor(color) end

---@param color Color
---@return nil
function Zone:SetFogColor(color) end

---@param density number
---@return nil
function Zone:SetFogDensity(density) end

---@param start number
---@return nil
function Zone:SetFogStart(start) end

---@param end_ number
---@return nil
function Zone:SetFogEnd(end_) end

---@param height number
---@return nil
function Zone:SetFogHeight(height) end

---@param scale number
---@return nil
function Zone:SetFogHeightScale(scale) end

---@param priority integer
---@return nil
function Zone:SetPriority(priority) end

---@param enable boolean
---@return nil
function Zone:SetHeightFog(enable) end

---@param value number
---@return nil
function Zone:SetSkyFogIntensity(value) end

---@param enable boolean
---@return nil
function Zone:SetOverride(enable) end

---@param enable boolean
---@return nil
function Zone:SetAmbientGradient(enable) end

---@param texture Texture
---@return nil
function Zone:SetZoneTexture(texture) end

---@param source AmbientSource
---@return nil
function Zone:SetAmbientSource(source) end

---@param texture Texture
---@return nil
function Zone:SetSourceTexture(texture) end

---@param texture Texture
---@return nil
function Zone:SetSourceTextureFromBakeCache(texture) end

---@param intensity number
---@return nil
function Zone:SetAmbientIntensity(intensity) end

---@param value boolean
---@return nil
function Zone:SetAutoExposureEnabled(value) end

---@param enable boolean
---@return nil
function Zone:SetSSREnabled(enable) end

---@param enable boolean
---@return nil
function Zone:SetSSRUsePrevFrameColor(enable) end

---@param enable boolean
---@return nil
function Zone:SetSSGIEnabled(enable) end

---@param quality integer
---@return nil
function Zone:SetSSGIQuality(quality) end

---@param intensity number
---@return nil
function Zone:SetSSGIIntensity(intensity) end

---@param radius number
---@return nil
function Zone:SetSSAORadius(radius) end

---@param intensity number
---@return nil
function Zone:SetSSAOIntensity(intensity) end

---@param enable boolean
---@return nil
function Zone:SetMotionBlurEnabled(enable) end

---@param amount number
---@return nil
function Zone:SetMotionBlurAmount(amount) end

---@param percent number
---@return nil
function Zone:SetMotionBlurMaxDistortion(percent) end

---@param enable boolean
---@return nil
function Zone:SetTonemapLUTEnabled(enable) end

---@param mode TonemapMode
---@return nil
function Zone:SetTonemapMode(mode) end

---@param params ToonShadingParams
---@return nil
function Zone:SetToonShadingParams(params) end

---@param value boolean
---@return nil
function Zone:SetBloomPlusEnabled(value) end

---@param value number
---@return nil
function Zone:SetBloomThreshold(value) end

---@param value number
---@return nil
function Zone:SetBloomWeight(value) end

---@param value number
---@return nil
function Zone:SetBloomPlusIntensity(value) end

---@param mode BloomMode
---@return nil
function Zone:SetBloomMode(mode) end

---@param value number
---@return nil
function Zone:SetBloomUEIntensity(value) end

---@param value number
---@return nil
function Zone:SetBloomUEThreshold(value) end

---@param value number
---@return nil
function Zone:SetBloomUESizeScale(value) end

---@param stage integer
---@param size number
---@return nil
function Zone:SetBloomUESize(stage, size) end

---@param stage integer
---@param tint Color
---@return nil
function Zone:SetBloomUETint(stage, tint) end

---@param enable boolean
---@return nil
function Zone:SetVolumetricFogEnabled(enable) end

---@param enable boolean
---@return nil
function Zone:SetVolumetricFogOverrideLightColors(enable) end

---@param color Color
---@return nil
function Zone:SetVolumetricFogDirectionalInscatteringColor(color) end

---@param intensity number
---@return nil
function Zone:SetSkyLightVolumetricScatteringIntensity(intensity) end

---@param value boolean
---@return nil
function Zone:SetFXAAEnabled(value) end

---@param enable boolean
---@return nil
function Zone:SetVignetteEnabled(enable) end

---@param intensity number
---@return nil
function Zone:SetVignetteIntensity(intensity) end

---@param vignetteTexture Texture
---@return nil
function Zone:SetVignetteTexture(vignetteTexture) end

---@return Matrix3x4
function Zone:GetInverseWorldTransform() end

---@return Color
function Zone:GetAmbientColor() end

---@return Color
function Zone:GetAmbientStartColor() end

---@return Color
function Zone:GetAmbientEndColor() end

---@return Color
function Zone:GetFogColor() end

---@return number
function Zone:GetFogDensity() end

---@return number
function Zone:GetFogStart() end

---@return number
function Zone:GetFogEnd() end

---@return number
function Zone:GetFogHeight() end

---@return number
function Zone:GetFogHeightScale() end

---@return integer
function Zone:GetPriority() end

---@return boolean
function Zone:GetHeightFog() end

---@return number
function Zone:GetSkyFogIntensity() end

---@return boolean
function Zone:GetOverride() end

---@return boolean
function Zone:GetAmbientGradient() end

---@return Texture
function Zone:GetZoneTexture() end

---@return AmbientSource
function Zone:GetAmbientSource() end

---@return Texture
function Zone:GetSourceTexture() end

---@return number
function Zone:GetAmbientIntensity() end

---@return boolean
function Zone:GetAutoExposureEnabled() end

---@return boolean
function Zone:GetSSREnabled() end

---@return boolean
function Zone:GetSSRUsePrevFrameColor() end

---@return boolean
function Zone:GetSSGIEnabled() end

---@return integer
function Zone:GetSSGIQuality() end

---@return number
function Zone:GetSSGIIntensity() end

---@return number
function Zone:GetSSAORadius() end

---@return number
function Zone:GetSSAOIntensity() end

---@return boolean
function Zone:GetMotionBlurEnabled() end

---@return number
function Zone:GetMotionBlurAmount() end

---@return number
function Zone:GetMotionBlurMaxDistortion() end

---@return boolean
function Zone:GetTonemapLUTEnabled() end

---@return TonemapMode
function Zone:GetTonemapMode() end

---@return ToonShadingParams
function Zone:GetToonShadingParams() end

---@return boolean
function Zone:GetBloomPlusEnabled() end

---@return number
function Zone:GetBloomThreshold() end

---@return number
function Zone:GetBloomWeight() end

---@return number
function Zone:GetBloomPlusIntensity() end

---@return BloomMode
function Zone:GetBloomMode() end

---@return number
function Zone:GetBloomUEIntensity() end

---@return number
function Zone:GetBloomUEThreshold() end

---@return number
function Zone:GetBloomUESizeScale() end

---@param stage integer
---@return number
function Zone:GetBloomUESize(stage) end

---@param stage integer
---@return Color
function Zone:GetBloomUETint(stage) end

---@return boolean
function Zone:GetVolumetricFogEnabled() end

---@return boolean
function Zone:GetVolumetricFogOverrideLightColors() end

---@return Color
function Zone:GetVolumetricFogDirectionalInscatteringColor() end

---@return number
function Zone:GetSkyLightVolumetricScatteringIntensity() end

---@return boolean
function Zone:GetFXAAEnabled() end

---@return boolean
function Zone:GetVignetteEnabled() end

---@return number
function Zone:GetVignetteIntensity() end

---@return Texture
function Zone:GetVignetteTexture() end

---@param point Vector3
---@return boolean
function Zone:IsInside(point) end

