---@meta

--- Auto-generated from Graphics/Texture2D


---@class Texture2D : Texture
---@overload fun(): Texture2D
---@field renderSurface RenderSurface
Texture2D = {}

---@return Texture2D
function Texture2D.new() end

---@param width integer
---@param height integer
---@param format integer
---@param usage? TextureUsage
---@param multiSample? integer
---@param autoResolve? boolean
---@return boolean
function Texture2D:SetSize(width, height, format, usage, multiSample, autoResolve) end

---@param image Image
---@param useAlpha? boolean
---@return boolean
function Texture2D:SetData(image, useAlpha) end

---@return Image
function Texture2D:GetImage() end

---@return RenderSurface
function Texture2D:GetRenderSurface() end

