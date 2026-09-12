---@meta

--- Auto-generated from Graphics/Renderer

---@class Renderer
---@field numViewports integer
---@field defaultRenderPath RenderPath
---@field defaultTechnique Technique
---@field hdrRendering boolean
---@field specularLighting boolean
---@field drawShadows boolean
---@field textureAnisotropy integer
---@field textureFilterMode TextureFilterMode
---@field textureQuality MaterialQuality
---@field materialQuality MaterialQuality
---@field shadowMapSize integer
---@field shadowQuality ShadowQuality
---@field shadowSoftness number
---@field vsmMultiSample integer
---@field reuseShadowMaps boolean
---@field maxShadowMaps integer
---@field dynamicInstancing boolean
---@field numExtraInstancingBufferElements integer
---@field minInstances integer
---@field maxSortedInstances integer
---@field maxOccluderTriangles integer
---@field occlusionBufferSize integer
---@field occluderSizeThreshold number
---@field threadedOcclusion boolean
---@field mobileShadowBiasMul number
---@field mobileShadowBiasAdd number
---@field mobileNormalOffsetMul number
---@field numViews integer
---@field numPrimitives integer
---@field numBatches integer
---@field defaultZone Zone
---@field defaultMaterial Material
---@field defaultLightRamp Texture2D
---@field defaultLightSpot Texture2D
Renderer = {}

---@param num integer
---@return nil
function Renderer:SetNumViewports(num) end

---@param index integer
---@param viewport Viewport
---@return nil
function Renderer:SetViewport(index, viewport) end

---@param renderPath RenderPath
---@return nil
function Renderer:SetDefaultRenderPath(renderPath) end

---@param file XMLFile
---@return nil
function Renderer:SetDefaultRenderPath(file) end

---@param technique Technique
---@return nil
function Renderer:SetDefaultTechnique(technique) end

---@param enable boolean
---@return nil
function Renderer:SetHDRRendering(enable) end

---@param enable boolean
---@return nil
function Renderer:SetSpecularLighting(enable) end

---@param level integer
---@return nil
function Renderer:SetTextureAnisotropy(level) end

---@param mode TextureFilterMode
---@return nil
function Renderer:SetTextureFilterMode(mode) end

---@param quality MaterialQuality
---@return nil
function Renderer:SetTextureQuality(quality) end

---@param quality MaterialQuality
---@return nil
function Renderer:SetMaterialQuality(quality) end

---@param enable boolean
---@return nil
function Renderer:SetDrawShadows(enable) end

---@param size integer
---@return nil
function Renderer:SetShadowMapSize(size) end

---@param quality ShadowQuality
---@return nil
function Renderer:SetShadowQuality(quality) end

---@param shadowSoftness number
---@return nil
function Renderer:SetShadowSoftness(shadowSoftness) end

---@param minVariance number
---@param lightBleedingReduction number
---@return nil
function Renderer:SetVSMShadowParameters(minVariance, lightBleedingReduction) end

---@param multiSample integer
---@return nil
function Renderer:SetVSMMultiSample(multiSample) end

---@param enable boolean
---@return nil
function Renderer:SetReuseShadowMaps(enable) end

---@param shadowMaps integer
---@return nil
function Renderer:SetMaxShadowMaps(shadowMaps) end

---@param enable boolean
---@return nil
function Renderer:SetDynamicInstancing(enable) end

---@param elements integer
---@return nil
function Renderer:SetNumExtraInstancingBufferElements(elements) end

---@param instances integer
---@return nil
function Renderer:SetMinInstances(instances) end

---@param instances integer
---@return nil
function Renderer:SetMaxSortedInstances(instances) end

---@param triangles integer
---@return nil
function Renderer:SetMaxOccluderTriangles(triangles) end

---@param size integer
---@return nil
function Renderer:SetOcclusionBufferSize(size) end

---@param screenSize number
---@return nil
function Renderer:SetOccluderSizeThreshold(screenSize) end

---@param enable boolean
---@return nil
function Renderer:SetThreadedOcclusion(enable) end

---@param mul number
---@return nil
function Renderer:SetMobileShadowBiasMul(mul) end

---@param add number
---@return nil
function Renderer:SetMobileShadowBiasAdd(add) end

---@param mul number
---@return nil
function Renderer:SetMobileNormalOffsetMul(mul) end

---@param enable boolean
---@return nil
function Renderer:SetVolumetricFogFroxelEnabled(enable) end

---@param enable boolean
---@return nil
function Renderer:SetVolumetricFogConservativeDepthEnabled(enable) end

---@param mode integer
---@return nil
function Renderer:SetVolumetricFogDebugMode(mode) end

---@param pixels integer
---@return nil
function Renderer:SetVolumetricFogGridPixelSize(pixels) end

---@param slices integer
---@return nil
function Renderer:SetVolumetricFogGridSizeZ(slices) end

---@param quality VolumetricFogQuality
---@return nil
function Renderer:SetVolumetricFogQuality(quality) end

---@param weight number
---@return nil
function Renderer:SetVolumetricFogHistoryWeight(weight) end

---@param value number
---@return nil
function Renderer:SetVolumetricFogLightSoftFading(value) end

---@return nil
function Renderer:ReloadShaders() end

---@return integer
function Renderer:GetNumViewports() end

---@param index integer
---@return Viewport
function Renderer:GetViewport(index) end

---@param scene Scene
---@param index integer
---@return Viewport
function Renderer:GetViewportForScene(scene, index) end

---@return RenderPath
function Renderer:GetDefaultRenderPath() end

---@return Technique
function Renderer:GetDefaultTechnique() end

---@return boolean
function Renderer:GetHDRRendering() end

---@return boolean
function Renderer:GetSpecularLighting() end

---@return boolean
function Renderer:GetDrawShadows() end

---@return integer
function Renderer:GetTextureAnisotropy() end

---@return TextureFilterMode
function Renderer:GetTextureFilterMode() end

---@return MaterialQuality
function Renderer:GetTextureQuality() end

---@return MaterialQuality
function Renderer:GetMaterialQuality() end

---@return integer
function Renderer:GetShadowMapSize() end

---@return ShadowQuality
function Renderer:GetShadowQuality() end

---@return boolean
function Renderer:GetVolumetricFogFroxelEnabled() end

---@return boolean
function Renderer:GetVolumetricFogConservativeDepthEnabled() end

---@return integer
function Renderer:GetVolumetricFogDebugMode() end

---@return integer
function Renderer:GetVolumetricFogGridPixelSize() end

---@return integer
function Renderer:GetVolumetricFogGridSizeZ() end

---@return VolumetricFogQuality
function Renderer:GetVolumetricFogQuality() end

---@return number
function Renderer:GetVolumetricFogHistoryWeight() end

---@return number
function Renderer:GetVolumetricFogLightSoftFading() end

---@return number
function Renderer:GetShadowSoftness() end

---@return Vector2
function Renderer:GetVSMShadowParameters() end

---@return integer
function Renderer:GetVSMMultiSample() end

---@return boolean
function Renderer:GetReuseShadowMaps() end

---@return integer
function Renderer:GetMaxShadowMaps() end

---@return boolean
function Renderer:GetDynamicInstancing() end

---@return integer
function Renderer:GetNumExtraInstancingBufferElements() end

---@return integer
function Renderer:GetMinInstances() end

---@return integer
function Renderer:GetMaxSortedInstances() end

---@return integer
function Renderer:GetMaxOccluderTriangles() end

---@return integer
function Renderer:GetOcclusionBufferSize() end

---@return number
function Renderer:GetOccluderSizeThreshold() end

---@return boolean
function Renderer:GetThreadedOcclusion() end

---@return number
function Renderer:GetMobileShadowBiasMul() end

---@return number
function Renderer:GetMobileShadowBiasAdd() end

---@return number
function Renderer:GetMobileNormalOffsetMul() end

---@return integer
function Renderer:GetNumViews() end

---@return integer
function Renderer:GetNumPrimitives() end

---@return integer
function Renderer:GetNumBatches() end

---@param allViews? boolean
---@return integer
function Renderer:GetNumGeometries(allViews) end

---@param allViews? boolean
---@return integer
function Renderer:GetNumLights(allViews) end

---@param allViews? boolean
---@return integer
function Renderer:GetNumShadowMaps(allViews) end

---@param allViews? boolean
---@return integer
function Renderer:GetNumOccluders(allViews) end

---@return Zone
function Renderer:GetDefaultZone() end

---@return Material
function Renderer:GetDefaultMaterial() end

---@return Texture2D
function Renderer:GetDefaultLightRamp() end

---@return Texture2D
function Renderer:GetDefaultLightSpot() end

---@param depthTest boolean
---@return nil
function Renderer:DrawDebugGeometry(depthTest) end


-- Global functions
---@return Renderer
function GetRenderer() end

-- Global variables
---@type Renderer
renderer = nil
