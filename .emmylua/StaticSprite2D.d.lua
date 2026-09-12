---@meta

--- Auto-generated from Urho2D/StaticSprite2D

---@class StaticSprite2D : Drawable2D
---@field sprite Sprite2D
---@field blendMode BlendMode
---@field flipX boolean
---@field flipY boolean
---@field swapXY boolean
---@field color Color
---@field alpha number
---@field useHotSpot boolean
---@field hotSpot Vector2
---@field customMaterial Material
---@field drawRect Rect
---@field useDrawRect boolean
---@field textureRect Rect
---@field useTextureRect boolean
StaticSprite2D = {}

---@param sprite Sprite2D
---@return nil
function StaticSprite2D:SetSprite(sprite) end

---@param mode BlendMode
---@return nil
function StaticSprite2D:SetBlendMode(mode) end

---@param flipX boolean
---@param flipY boolean
---@param swapXY? boolean
---@return nil
function StaticSprite2D:SetFlip(flipX, flipY, swapXY) end

---@param flipX boolean
---@return nil
function StaticSprite2D:SetFlipX(flipX) end

---@param flipY boolean
---@return nil
function StaticSprite2D:SetFlipY(flipY) end

---@param swapXY boolean
---@return nil
function StaticSprite2D:SetSwapXY(swapXY) end

---@param color Color
---@return nil
function StaticSprite2D:SetColor(color) end

---@param alpha number
---@return nil
function StaticSprite2D:SetAlpha(alpha) end

---@param useHotSpot boolean
---@return nil
function StaticSprite2D:SetUseHotSpot(useHotSpot) end

---@param hotspot Vector2
---@return nil
function StaticSprite2D:SetHotSpot(hotspot) end

---@param useDrawRect boolean
---@return nil
function StaticSprite2D:SetUseDrawRect(useDrawRect) end

---@param rect Rect
---@return nil
function StaticSprite2D:SetDrawRect(rect) end

---@param useTextureRect boolean
---@return nil
function StaticSprite2D:SetUseTextureRect(useTextureRect) end

---@param rect Rect
---@return nil
function StaticSprite2D:SetTextureRect(rect) end

---@param customMaterial Material
---@return nil
function StaticSprite2D:SetCustomMaterial(customMaterial) end

---@return Sprite2D
function StaticSprite2D:GetSprite() end

---@return BlendMode
function StaticSprite2D:GetBlendMode() end

---@return boolean
function StaticSprite2D:GetFlipX() end

---@return boolean
function StaticSprite2D:GetFlipY() end

---@return boolean
function StaticSprite2D:GetSwapXY() end

---@return Color
function StaticSprite2D:GetColor() end

---@return number
function StaticSprite2D:GetAlpha() end

---@return boolean
function StaticSprite2D:GetUseHotSpot() end

---@return Vector2
function StaticSprite2D:GetHotSpot() end

---@return boolean
function StaticSprite2D:GetUseDrawRect() end

---@return Rect
function StaticSprite2D:GetDrawRect() end

---@return boolean
function StaticSprite2D:GetUseTextureRect() end

---@return Rect
function StaticSprite2D:GetTextureRect() end

---@return Material
function StaticSprite2D:GetCustomMaterial() end

