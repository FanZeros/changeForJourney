---@meta

--- Auto-generated from Graphics/Texture3D


---@class Texture3D : Texture
---@overload fun(): Texture3D
Texture3D = {}

---@return Texture3D
function Texture3D.new() end

---@param width integer
---@param height integer
---@param depth integer
---@param format integer
---@param usage? TextureUsage
---@return boolean
function Texture3D:SetSize(width, height, depth, format, usage) end

---@param image Image
---@param useAlpha? boolean
---@return boolean
function Texture3D:SetData(image, useAlpha) end

