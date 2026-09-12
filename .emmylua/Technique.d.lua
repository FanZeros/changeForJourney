---@meta

--- Auto-generated from Graphics/Technique

---@alias PassLightingMode
---| integer # PassLightingMode enum values

---@type PassLightingMode
LIGHTING_UNLIT = 0
---@type PassLightingMode
LIGHTING_PERVERTEX = 1
---@type PassLightingMode
LIGHTING_PERPIXEL = 2

---@class Pass : RefCounted
---@field name string
---@field index integer
---@field blendMode BlendMode
---@field cullMode CullMode
---@field depthTestMode CompareMode
---@field lightingMode PassLightingMode
---@field depthWrite boolean
---@field alphaToCoverage boolean
---@field desktop boolean
---@field vertexShader string
---@field pixelShader string
---@field vertexShaderDefines string
---@field pixelShaderDefines string
---@field vertexShaderDefineExcludes string
---@field pixelShaderDefineExcludes string
Pass = {}

---@param mode BlendMode
---@return nil
function Pass:SetBlendMode(mode) end

---@param mode CullMode
---@return nil
function Pass:SetCullMode(mode) end

---@param mode CompareMode
---@return nil
function Pass:SetDepthTestMode(mode) end

---@param mode PassLightingMode
---@return nil
function Pass:SetLightingMode(mode) end

---@param enable boolean
---@return nil
function Pass:SetDepthWrite(enable) end

---@param enable boolean
---@return nil
function Pass:SetAlphaToCoverage(enable) end

---@param enable boolean
---@return nil
function Pass:SetIsDesktop(enable) end

---@param name string
---@return nil
function Pass:SetVertexShader(name) end

---@param name string
---@return nil
function Pass:SetPixelShader(name) end

---@param defines string
---@return nil
function Pass:SetVertexShaderDefines(defines) end

---@param defines string
---@return nil
function Pass:SetPixelShaderDefines(defines) end

---@param excludes string
---@return nil
function Pass:SetVertexShaderDefineExcludes(excludes) end

---@param excludes string
---@return nil
function Pass:SetPixelShaderDefineExcludes(excludes) end

---@return nil
function Pass:ReleaseShaders() end

---@return string
function Pass:GetName() end

---@return integer
function Pass:GetIndex() end

---@return CullMode
function Pass:GetCullMode() end

---@return BlendMode
function Pass:GetBlendMode() end

---@return CompareMode
function Pass:GetDepthTestMode() end

---@return PassLightingMode
function Pass:GetLightingMode() end

---@return boolean
function Pass:GetDepthWrite() end

---@return boolean
function Pass:GetAlphaToCoverage() end

---@return boolean
function Pass:IsDesktop() end

---@return string
function Pass:GetVertexShader() end

---@return string
function Pass:GetPixelShader() end

---@return string
function Pass:GetVertexShaderDefines() end

---@return string
function Pass:GetPixelShaderDefines() end

---@return string
function Pass:GetVertexShaderDefineExcludes() end

---@return string
function Pass:GetPixelShaderDefineExcludes() end


---@class Technique : Resource
---@field supported boolean
---@field desktop boolean
---@field numPasses integer
Technique = {}

---@param enable boolean
---@return nil
function Technique:SetIsDesktop(enable) end

---@param passName string
---@return Pass
function Technique:CreatePass(passName) end

---@param passName string
---@return nil
function Technique:RemovePass(passName) end

---@return nil
function Technique:ReleaseShaders() end

---@param cloneName? string
---@return Technique
function Technique:Clone(cloneName) end

---@param type string
---@return boolean
function Technique:HasPass(type) end

---@param type string
---@return Pass
function Technique:GetPass(type) end

---@param type string
---@return Pass
function Technique:GetSupportedPass(type) end

---@return boolean
function Technique:IsSupported() end

---@return boolean
function Technique:IsDesktop() end

---@return integer
function Technique:GetNumPasses() end

---@return string[]
function Technique:GetPassTypes() end

---@return Pass[]
function Technique:GetPasses() end

