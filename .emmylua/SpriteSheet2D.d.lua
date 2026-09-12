---@meta

--- Auto-generated from Urho2D/SpriteSheet2D

---@class SpriteSheet2D : Resource
---@field texture Texture2D
SpriteSheet2D = {}

---@param texture Texture2D
---@return nil
function SpriteSheet2D:SetTexture(texture) end

---@return Texture2D
function SpriteSheet2D:GetTexture() end

---@param name string
---@return Sprite2D
function SpriteSheet2D:GetSprite(name) end

---@param name string
---@param rectangle IntRect
---@param hotSpot? Vector2
---@return nil
function SpriteSheet2D:DefineSprite(name, rectangle, hotSpot) end

