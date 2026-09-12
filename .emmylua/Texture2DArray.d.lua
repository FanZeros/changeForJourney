---@meta

--- Auto-generated from Graphics/Texture2DArray


---@class Texture2DArray : Texture
---@overload fun(): Texture2DArray
---@field layers integer
---@field renderSurface RenderSurface
Texture2DArray = {}

---@return Texture2DArray
function Texture2DArray.new() end

---@param layers integer
---@return nil
function Texture2DArray:SetLayers(layers) end

---@param layers integer
---@param width integer
---@param height integer
---@param format integer
---@param usage? TextureUsage
---@return boolean
function Texture2DArray:SetSize(layers, width, height, format, usage) end

---@param layer integer
---@param image Image
---@param useAlpha? boolean
---@return boolean
function Texture2DArray:SetData(layer, image, useAlpha) end

---@return integer
function Texture2DArray:GetLayers() end

---@return RenderSurface
function Texture2DArray:GetRenderSurface() end

