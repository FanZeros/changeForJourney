---@meta

--- Auto-generated from UI/BorderImage


---@class BorderImage : UIElement
---@overload fun(): BorderImage
---@field texture Texture
---@field imageRect IntRect
---@field border IntRect
---@field imageBorder IntRect
---@field hoverOffset IntVector2
---@field blendMode BlendMode
---@field tiled boolean
BorderImage = {}

---@return BorderImage
function BorderImage.new() end

---@param texture Texture
---@return nil
function BorderImage:SetTexture(texture) end

---@param rect IntRect
---@return nil
function BorderImage:SetImageRect(rect) end

---@return nil
function BorderImage:SetFullImageRect() end

---@param rect IntRect
---@return nil
function BorderImage:SetBorder(rect) end

---@param rect IntRect
---@return nil
function BorderImage:SetImageBorder(rect) end

---@param offset IntVector2
---@return nil
function BorderImage:SetHoverOffset(offset) end

---@param x integer
---@param y integer
---@return nil
function BorderImage:SetHoverOffset(x, y) end

---@param mode BlendMode
---@return nil
function BorderImage:SetBlendMode(mode) end

---@param enable boolean
---@return nil
function BorderImage:SetTiled(enable) end

---@return Texture
function BorderImage:GetTexture() end

---@return IntRect
function BorderImage:GetImageRect() end

---@return IntRect
function BorderImage:GetBorder() end

---@return IntRect
function BorderImage:GetImageBorder() end

---@return IntVector2
function BorderImage:GetHoverOffset() end

---@return BlendMode
function BorderImage:GetBlendMode() end

---@return boolean
function BorderImage:IsTiled() end

