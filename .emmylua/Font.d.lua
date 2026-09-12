---@meta

--- Auto-generated from UI/Font

---@alias FontType
---| integer # FontType enum values

---@type FontType
FONT_NONE = 0
---@type FontType
FONT_FREETYPE = 1
---@type FontType
FONT_BITMAP = 2
---@type FontType
MAX_FONT_TYPES = 3

---@class Font : Resource
---@field absoluteGlyphOffset IntVector2
---@field scaledGlyphOffset Vector2
---@field fontType FontType
Font = {}

---@param offset IntVector2
---@return nil
function Font:SetAbsoluteGlyphOffset(offset) end

---@param offset Vector2
---@return nil
function Font:SetScaledGlyphOffset(offset) end

---@return IntVector2
function Font:GetAbsoluteGlyphOffset() end

---@return Vector2
function Font:GetScaledGlyphOffset() end

---@param pointSize number
---@return IntVector2
function Font:GetTotalGlyphOffset(pointSize) end

---@return FontType
function Font:GetFontType() end

---@return boolean
function Font:IsSDFFont() end


---@class FontManager : Object
FontManager = {}

