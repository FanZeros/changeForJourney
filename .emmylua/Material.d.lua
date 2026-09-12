---@meta

--- Auto-generated from Graphics/Material



---@class Material : Resource
---@overload fun(): Material
---@field vertexShaderDefines string
---@field pixelShaderDefines string
---@field cullMode CullMode
---@field shadowCullMode CullMode
---@field fillMode FillMode
---@field depthBias BiasParameters
---@field alphaToCoverage boolean
---@field lineAntiAlias boolean
---@field renderOrder number -- unsigned char
---@field occlusion boolean
---@field specular boolean
---@field scene Scene
Material = {}

---@return Material
function Material.new() end

---@param num integer
---@return nil
function Material:SetNumTechniques(num) end

---@param index integer
---@param tech Technique
---@param qualityLevel? MaterialQuality
---@param lodDistance? number
---@return nil
function Material:SetTechnique(index, tech, qualityLevel, lodDistance) end

---@param shader SurfaceShader
---@return boolean
function Material:SetSurfaceShader(shader) end

---@param resourceName string
---@return boolean
function Material:SetSurfaceShader(resourceName) end

---@param defines string
---@return nil
function Material:SetVertexShaderDefines(defines) end

---@param defines string
---@return nil
function Material:SetPixelShaderDefines(defines) end

---@param name string
---@param value Variant
---@return nil
function Material:SetShaderParameter(name, value) end

---@param name string
---@param animation ValueAnimation
---@param wrapMode? WrapMode
---@param speed? number
---@return nil
function Material:SetShaderParameterAnimation(name, animation, wrapMode, speed) end

---@param name string
---@param wrapMode WrapMode
---@return nil
function Material:SetShaderParameterAnimationWrapMode(name, wrapMode) end

---@param name string
---@param speed number
---@return nil
function Material:SetShaderParameterAnimationSpeed(name, speed) end

---@param unit TextureUnit
---@param texture Texture
---@return nil
function Material:SetTexture(unit, texture) end

---@param sourceName string
---@param texture Texture
---@return boolean
function Material:SetSurfaceTexture(sourceName, texture) end

---@param offset Vector2
---@param rotation number
---@param repeat_ Vector2
---@return nil
function Material:SetUVTransform(offset, rotation, repeat_) end

---@param offset Vector2
---@param rotation number
---@param repeat_ number
---@return nil
function Material:SetUVTransform(offset, rotation, repeat_) end

---@param tiling Vector2
---@return nil
function Material:SetUVTiling(tiling) end

---@param offset Vector2
---@return nil
function Material:SetUVOffset(offset) end

---@param speed Vector2
---@return nil
function Material:SetUVSpeed(speed) end

---@param rotate number
---@return nil
function Material:SetTexRotation(rotate) end

---@return Vector2
function Material:GetUVTiling() end

---@return Vector2
function Material:GetUVOffset() end

---@return Vector2
function Material:GetUVSpeed() end

---@return number
function Material:GetTexRotation() end

---@param mode CullMode
---@return nil
function Material:SetCullMode(mode) end

---@param mode CullMode
---@return nil
function Material:SetShadowCullMode(mode) end

---@param mode FillMode
---@return nil
function Material:SetFillMode(mode) end

---@param parameters BiasParameters
---@return nil
function Material:SetDepthBias(parameters) end

---@param enable boolean
---@return nil
function Material:SetAlphaToCoverage(enable) end

---@param enable boolean
---@return nil
function Material:SetLineAntiAlias(enable) end

---@param renderOrder number -- unsigned char
---@return nil
function Material:SetRenderOrder(renderOrder) end

---@param enable boolean
---@return nil
function Material:SetOcclusion(enable) end

---@param scene Scene
---@return nil
function Material:SetScene(scene) end

---@param name string
---@return nil
function Material:RemoveShaderParameter(name) end

---@return nil
function Material:ReleaseShaders() end

---@param cloneName? string
---@return Material
function Material:Clone(cloneName) end

---@return nil
function Material:SortTechniques() end

---@param frameNumber integer
---@return nil
function Material:MarkForAuxView(frameNumber) end

---@return integer
function Material:GetNumTechniques() end

---@param index integer
---@return Technique
function Material:GetTechnique(index) end

---@return SurfaceShader
function Material:GetSurfaceShader() end

---@param index integer
---@param passName string
---@return Pass
function Material:GetPass(index, passName) end

---@param unit TextureUnit
---@return Texture
function Material:GetTexture(unit) end

---@param sourceName string
---@return Texture
function Material:GetSurfaceTexture(sourceName) end

---@return string
function Material:GetVertexShaderDefines() end

---@return string
function Material:GetPixelShaderDefines() end

---@param name string
---@return ValueAnimation
function Material:GetShaderParameterAnimation(name) end

---@param name string
---@return WrapMode
function Material:GetShaderParameterAnimationWrapMode(name) end

---@param name string
---@return number
function Material:GetShaderParameterAnimationSpeed(name) end

---@return CullMode
function Material:GetCullMode() end

---@return CullMode
function Material:GetShadowCullMode() end

---@return FillMode
function Material:GetFillMode() end

---@return BiasParameters
function Material:GetDepthBias() end

---@return boolean
function Material:GetAlphaToCoverage() end

---@return boolean
function Material:GetLineAntiAlias() end

---@return number
function Material:GetRenderOrder() end

---@return boolean
function Material:GetOcclusion() end

---@return boolean
function Material:GetSpecular() end

---@return Scene
function Material:GetScene() end

