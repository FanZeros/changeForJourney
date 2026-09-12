---@meta

--- Auto-generated from UI/Text3D


---@class Text3D : Drawable
---@overload fun(): Text3D
---@field font Font
---@field material Material
---@field fontSize number
---@field text string
---@field textAlignment HorizontalAlignment
---@field horizontalAlignment HorizontalAlignment
---@field verticalAlignment VerticalAlignment
---@field rowSpacing number
---@field wordwrap boolean
---@field textEffect TextEffect
---@field effectShadowOffset IntVector2
---@field effectStrokeThickness integer
---@field effectRoundStroke boolean
---@field effectColor Color
---@field effectDepthBias number
---@field width integer
---@field color Color
---@field height integer
---@field rowHeight number
---@field numRows integer
---@field numChars integer
---@field opacity number
---@field fixedScreenSize boolean
---@field faceCameraMode FaceCameraMode
Text3D = {}

---@return Text3D
function Text3D.new() end

---@param fontName string
---@param size? number
---@return boolean
function Text3D:SetFont(fontName, size) end

---@param font Font
---@param size? number
---@return boolean
function Text3D:SetFont(font, size) end

---@param size number
---@return boolean
function Text3D:SetFontSize(size) end

---@param material Material
---@return nil
function Text3D:SetMaterial(material) end

---@param text string
---@return nil
function Text3D:SetText(text) end

---@param hAlign HorizontalAlignment
---@param vAlign VerticalAlignment
---@return nil
function Text3D:SetAlignment(hAlign, vAlign) end

---@param align HorizontalAlignment
---@return nil
function Text3D:SetHorizontalAlignment(align) end

---@param align VerticalAlignment
---@return nil
function Text3D:SetVerticalAlignment(align) end

---@param align HorizontalAlignment
---@return nil
function Text3D:SetTextAlignment(align) end

---@param spacing number
---@return nil
function Text3D:SetRowSpacing(spacing) end

---@param enable boolean
---@return nil
function Text3D:SetWordwrap(enable) end

---@param textEffect TextEffect
---@return nil
function Text3D:SetTextEffect(textEffect) end

---@param offset IntVector2
---@return nil
function Text3D:SetEffectShadowOffset(offset) end

---@param thickness integer
---@return nil
function Text3D:SetEffectStrokeThickness(thickness) end

---@param roundStroke boolean
---@return nil
function Text3D:SetEffectRoundStroke(roundStroke) end

---@param effectColor Color
---@return nil
function Text3D:SetEffectColor(effectColor) end

---@param bias number
---@return nil
function Text3D:SetEffectDepthBias(bias) end

---@param width integer
---@return nil
function Text3D:SetWidth(width) end

---@param color Color
---@return nil
function Text3D:SetColor(color) end

---@param corner Corner
---@param color Color
---@return nil
function Text3D:SetColor(corner, color) end

---@param opacity number
---@return nil
function Text3D:SetOpacity(opacity) end

---@param enable boolean
---@return nil
function Text3D:SetFixedScreenSize(enable) end

---@param mode FaceCameraMode
---@return nil
function Text3D:SetFaceCameraMode(mode) end

---@return Font
function Text3D:GetFont() end

---@return Material
function Text3D:GetMaterial() end

---@return number
function Text3D:GetFontSize() end

---@return string
function Text3D:GetText() end

---@return HorizontalAlignment
function Text3D:GetTextAlignment() end

---@return HorizontalAlignment
function Text3D:GetHorizontalAlignment() end

---@return VerticalAlignment
function Text3D:GetVerticalAlignment() end

---@return number
function Text3D:GetRowSpacing() end

---@return boolean
function Text3D:GetWordwrap() end

---@return TextEffect
function Text3D:GetTextEffect() end

---@return IntVector2
function Text3D:GetEffectShadowOffset() end

---@return integer
function Text3D:GetEffectStrokeThickness() end

---@return boolean
function Text3D:GetEffectRoundStroke() end

---@return Color
function Text3D:GetEffectColor() end

---@return number
function Text3D:GetEffectDepthBias() end

---@return integer
function Text3D:GetWidth() end

---@return integer
function Text3D:GetHeight() end

---@return number
function Text3D:GetRowHeight() end

---@return integer
function Text3D:GetNumRows() end

---@return integer
function Text3D:GetNumChars() end

---@param index integer
---@return number
function Text3D:GetRowWidth(index) end

---@param index integer
---@return Vector2
function Text3D:GetCharPosition(index) end

---@param index integer
---@return Vector2
function Text3D:GetCharSize(index) end

---@param corner Corner
---@return Color
function Text3D:GetColor(corner) end

---@return number
function Text3D:GetOpacity() end

---@return boolean
function Text3D:IsFixedScreenSize() end

---@return FaceCameraMode
function Text3D:GetFaceCameraMode() end

