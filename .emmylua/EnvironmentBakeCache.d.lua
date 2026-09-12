---@meta

--- Auto-generated from Graphics/EnvironmentBakeCache

---@class EnvironmentBakeCache
---@field gpuBakeEnabled boolean
EnvironmentBakeCache = {}

--- 启用/禁用 GPU 烘焙（默认启用，禁用后始终走 CPU；启用但硬件不支持时自动 fallback CPU）
---@param enabled boolean
---@return nil
function EnvironmentBakeCache:SetGPUBakeEnabled(enabled) end

---@return boolean
function EnvironmentBakeCache:GetGPUBakeEnabled() end

--- 清空缓存（下次 SetSourceTexture 会重新烘焙）
---@return nil
function EnvironmentBakeCache:ClearCache() end

--- 请求对源纹理(全景 Texture2D 或 TextureCube)做 IBL + SH 烘焙，结果存入缓存。
--- 返回是否已就绪(命中缓存)。
---@param sourceTexture Texture
---@return boolean
function EnvironmentBakeCache:RequestBake(sourceTexture) end


-- Global functions
---@return EnvironmentBakeCache
function GetEnvironmentBakeCache() end

-- Global variables
---@type EnvironmentBakeCache
environmentBakeCache = nil
