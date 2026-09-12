---@meta

--- Auto-generated from Graphics/TextureCube

---@class TextureCube : Texture
---@overload fun(): TextureCube
TextureCube = {}

---@return TextureCube
function TextureCube.new() end

---@param size integer
---@param format integer
---@param usage? TextureUsage
---@param multiSample? integer
---@return boolean
function TextureCube:SetSize(size, format, usage, multiSample) end

---@param face CubeMapFace
---@param image Image
---@param useAlpha? boolean
---@return boolean
function TextureCube:SetData(face, image, useAlpha) end

---@param face CubeMapFace
---@return Image
function TextureCube:GetImage(face) end

---@param face CubeMapFace
---@return RenderSurface
function TextureCube:GetRenderSurface(face) end

