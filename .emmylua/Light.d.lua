---@meta

--- Auto-generated from Graphics/Light

---@alias LightType
---| integer # LightType enum values

---@type LightType
LIGHT_DIRECTIONAL = 0
---@type LightType
LIGHT_SPOT = 1
---@type LightType
LIGHT_POINT = 2
---@type LightType
LIGHT_RECT = 3

---@class BiasParameters
---@overload fun(constantBias: number, slopeScaledBias: number, normalOffset?: number): BiasParameters
---@overload fun(): BiasParameters
---@field constantBias number
---@field slopeScaledBias number
---@field normalOffset number
BiasParameters = {}

---@overload fun(self: BiasParameters, constantBias: number, slopeScaledBias: number, normalOffset?: number): BiasParameters
---@overload fun(constantBias: number, slopeScaledBias: number, normalOffset?: number): BiasParameters
---@return BiasParameters
function BiasParameters.new() end


---@class CascadeParameters
---@overload fun(split1: number, split2: number, split3: number, split4: number, fadeStart: number, biasAutoAdjust?: number): CascadeParameters
---@overload fun(): CascadeParameters
---@field fadeStart number
---@field biasAutoAdjust number
CascadeParameters = {}

---@overload fun(self: CascadeParameters, split1: number, split2: number, split3: number, split4: number, fadeStart: number, biasAutoAdjust?: number): CascadeParameters
---@overload fun(split1: number, split2: number, split3: number, split4: number, fadeStart: number, biasAutoAdjust?: number): CascadeParameters
---@return CascadeParameters
function CascadeParameters.new() end


---@class FocusParameters
---@overload fun(focus: boolean, nonUniform: boolean, autoSize: boolean, quantize: number, minView: number): FocusParameters
---@overload fun(): FocusParameters
---@field focus boolean
---@field nonUniform boolean
---@field autoSize boolean
---@field quantize number
---@field minView number
FocusParameters = {}

---@overload fun(self: FocusParameters, focus: boolean, nonUniform: boolean, autoSize: boolean, quantize: number, minView: number): FocusParameters
---@overload fun(focus: boolean, nonUniform: boolean, autoSize: boolean, quantize: number, minView: number): FocusParameters
---@return FocusParameters
function FocusParameters.new() end


---@class Light : Drawable
---@field lightType LightType
---@field perVertex boolean
---@field color Color
---@field temperature number
---@field useTemperature boolean
---@field radius number
---@field softRadius number
---@field length number
---@field sourceWidth number
---@field sourceHeight number
---@field barnDoorAngle number
---@field barnDoorLength number
---@field usePhysicalValues boolean
---@field specularIntensity number
---@field brightness number
---@field range number
---@field fov number
---@field aspectRatio number
---@field fadeDistance number
---@field shadowFadeDistance number
---@field shadowBias BiasParameters
---@field shadowCascade CascadeParameters
---@field shadowFocus FocusParameters
---@field shadowIntensity number
---@field shadowResolution number
---@field shadowNearFarRatio number
---@field shadowMaxExtrusion number
---@field rampTexture Texture
---@field shapeTexture Texture
---@field frustum Frustum
---@field numShadowSplits integer
---@field negative boolean
---@field effectiveColor Color
---@field effectiveSpecularIntensity number
---@field punctualLight boolean
---@field innerConeAngle number
---@field outerConeAngle number
Light = {}

---@param type LightType
---@return nil
function Light:SetLightType(type) end

---@param enable boolean
---@return nil
function Light:SetPerVertex(enable) end

---@param color Color
---@return nil
function Light:SetColor(color) end

---@param temperature number
---@return nil
function Light:SetTemperature(temperature) end

---@param enable boolean
---@return nil
function Light:SetUseTemperature(enable) end

---@param redius number
---@return nil
function Light:SetRadius(redius) end

---@param radius number
---@return nil
function Light:SetSoftRadius(radius) end

---@param length number
---@return nil
function Light:SetLength(length) end

---@param width number
---@return nil
function Light:SetSourceWidth(width) end

---@param height number
---@return nil
function Light:SetSourceHeight(height) end

---@param angle number
---@return nil
function Light:SetBarnDoorAngle(angle) end

---@param length number
---@return nil
function Light:SetBarnDoorLength(length) end

---@param enable boolean
---@return nil
function Light:SetUsePhysicalValues(enable) end

---@param intensity number
---@return nil
function Light:SetSpecularIntensity(intensity) end

---@param brightness number
---@return nil
function Light:SetBrightness(brightness) end

---@param range number
---@return nil
function Light:SetRange(range) end

---@param fov number
---@return nil
function Light:SetFov(fov) end

---@param aspectRatio number
---@return nil
function Light:SetAspectRatio(aspectRatio) end

---@param distance number
---@return nil
function Light:SetFadeDistance(distance) end

---@param distance number
---@return nil
function Light:SetShadowFadeDistance(distance) end

---@param parameters BiasParameters
---@return nil
function Light:SetShadowBias(parameters) end

---@param parameters CascadeParameters
---@return nil
function Light:SetShadowCascade(parameters) end

---@param parameters FocusParameters
---@return nil
function Light:SetShadowFocus(parameters) end

---@param intensity number
---@return nil
function Light:SetShadowIntensity(intensity) end

---@param resolution number
---@return nil
function Light:SetShadowResolution(resolution) end

---@param nearFarRatio number
---@return nil
function Light:SetShadowNearFarRatio(nearFarRatio) end

---@param extrusion number
---@return nil
function Light:SetShadowMaxExtrusion(extrusion) end

---@param texture Texture
---@return nil
function Light:SetRampTexture(texture) end

---@param texture Texture
---@return nil
function Light:SetShapeTexture(texture) end

---@return LightType
function Light:GetLightType() end

---@return boolean
function Light:GetPerVertex() end

---@return Color
function Light:GetColor() end

---@return number
function Light:GetTemperature() end

---@return boolean
function Light:GetUseTemperature() end

---@return number
function Light:GetRadius() end

---@return number
function Light:GetSoftRadius() end

---@return number
function Light:GetLength() end

---@return number
function Light:GetSourceWidth() end

---@return number
function Light:GetSourceHeight() end

---@return number
function Light:GetBarnDoorAngle() end

---@return number
function Light:GetBarnDoorLength() end

---@return boolean
function Light:GetUsePhysicalValues() end

---@return number
function Light:GetSpecularIntensity() end

---@return number
function Light:GetBrightness() end

---@return Color
function Light:GetEffectiveColor() end

---@return Color
function Light:GetColorFromTemperature() end

---@return number
function Light:GetEffectiveSpecularIntensity() end

---@return number
function Light:GetRange() end

---@return number
function Light:GetFov() end

---@return number
function Light:GetAspectRatio() end

---@return number
function Light:GetFadeDistance() end

---@return number
function Light:GetShadowFadeDistance() end

---@return BiasParameters
function Light:GetShadowBias() end

---@return CascadeParameters
function Light:GetShadowCascade() end

---@return FocusParameters
function Light:GetShadowFocus() end

---@return number
function Light:GetShadowIntensity() end

---@return number
function Light:GetShadowResolution() end

---@return number
function Light:GetShadowNearFarRatio() end

---@return number
function Light:GetShadowMaxExtrusion() end

---@return Texture
function Light:GetRampTexture() end

---@return Texture
function Light:GetShapeTexture() end

---@return Frustum
function Light:GetFrustum() end

---@return integer
function Light:GetNumShadowSplits() end

---@return boolean
function Light:IsNegative() end

---@param flag boolean
---@return nil
function Light:SetStatic(flag) end

---@param f boolean
---@return nil
function Light:SetPunctualLight(f) end

---@return boolean
function Light:GetPunctualLight() end

---@param angle number
---@return nil
function Light:SetInnerConeAngle(angle) end

---@param angle number
---@return nil
function Light:SetOuterConeAngle(angle) end

---@return number
function Light:GetInnerConeAngle() end

---@return number
function Light:GetOuterConeAngle() end

