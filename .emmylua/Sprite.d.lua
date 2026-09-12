---@meta

--- Auto-generated from UI/Sprite


---@class Sprite : UIElement
---@overload fun(): Sprite
---@field position Vector2
---@field hotSpot IntVector2
---@field scale Vector2
---@field rotation number
---@field texture Texture
---@field imageRect IntRect
---@field blendMode BlendMode
---@field transform Matrix3x4
Sprite = {}

---@return Sprite
function Sprite.new() end

---@param position Vector2
---@return nil
function Sprite:SetPosition(position) end

---@param x number
---@param y number
---@return nil
function Sprite:SetPosition(x, y) end

---@param hotSpot IntVector2
---@return nil
function Sprite:SetHotSpot(hotSpot) end

---@param x integer
---@param y integer
---@return nil
function Sprite:SetHotSpot(x, y) end

---@param scale Vector2
---@return nil
function Sprite:SetScale(scale) end

---@param x number
---@param y number
---@return nil
function Sprite:SetScale(x, y) end

---@param scale number
---@return nil
function Sprite:SetScale(scale) end

---@param angle number
---@return nil
function Sprite:SetRotation(angle) end

---@param texture Texture
---@return nil
function Sprite:SetTexture(texture) end

---@param rect IntRect
---@return nil
function Sprite:SetImageRect(rect) end

---@return nil
function Sprite:SetFullImageRect() end

---@param mode BlendMode
---@return nil
function Sprite:SetBlendMode(mode) end

---@return Vector2
function Sprite:GetPosition() end

---@return IntVector2
function Sprite:GetHotSpot() end

---@return Vector2
function Sprite:GetScale() end

---@return number
function Sprite:GetRotation() end

---@return Texture
function Sprite:GetTexture() end

---@return IntRect
function Sprite:GetImageRect() end

---@return BlendMode
function Sprite:GetBlendMode() end

---@return Matrix3x4
function Sprite:GetTransform() end

