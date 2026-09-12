---@meta

--- Auto-generated from Urho2D/Sprite2D

---@class Sprite2D : Resource
---@field texture Texture2D
---@field rectangle IntRect
---@field hotSpot Vector2
---@field offset IntVector2
---@field textureEdgeOffset number
---@field spriteSheet SpriteSheet2D
Sprite2D = {}

---@param texture Texture2D
---@return nil
function Sprite2D:SetTexture(texture) end

---@param rectangle IntRect
---@return nil
function Sprite2D:SetRectangle(rectangle) end

---@param hotSpot Vector2
---@return nil
function Sprite2D:SetHotSpot(hotSpot) end

---@param offset IntVector2
---@return nil
function Sprite2D:SetOffset(offset) end

---@param offset number
---@return nil
function Sprite2D:SetTextureEdgeOffset(offset) end

---@param spriteSheet SpriteSheet2D
---@return nil
function Sprite2D:SetSpriteSheet(spriteSheet) end

---@return Texture2D
function Sprite2D:GetTexture() end

---@return IntRect
function Sprite2D:GetRectangle() end

---@return Vector2
function Sprite2D:GetHotSpot() end

---@return IntVector2
function Sprite2D:GetOffset() end

---@return number
function Sprite2D:GetTextureEdgeOffset() end

---@return SpriteSheet2D
function Sprite2D:GetSpriteSheet() end

