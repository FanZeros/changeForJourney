---@meta

--- Auto-generated from UI/Text

---@alias TextEffect
---| integer # TextEffect enum values

---@type TextEffect
TE_NONE = 0
---@type TextEffect
TE_SHADOW = 1
---@type TextEffect
TE_STROKE = 2

---@class Text : UISelectable
---@overload fun(): Text
---@field font Font
---@field fontSize number
---@field text string
---@field textAlignment HorizontalAlignment
---@field rowSpacing number
---@field wordwrap boolean
---@field autoLocalizable boolean
---@field selectionStart integer
---@field selectionLength integer
---@field textEffect TextEffect
---@field effectShadowOffset IntVector2
---@field effectStrokeThickness integer
---@field effectRoundStroke boolean
---@field effectColor Color
---@field rowHeight number
---@field numRows integer
---@field numChars integer
Text = {}

---@return Text
function Text.new() end

---@param fontName string
---@param size? number
---@return boolean
function Text:SetFont(fontName, size) end

---@param font Font
---@param size? number
---@return boolean
function Text:SetFont(font, size) end

---@param size number
---@return boolean
function Text:SetFontSize(size) end

---@param text string
---@return nil
function Text:SetText(text) end

---@param align HorizontalAlignment
---@return nil
function Text:SetTextAlignment(align) end

---@param spacing number
---@return nil
function Text:SetRowSpacing(spacing) end

---@param enable boolean
---@return nil
function Text:SetWordwrap(enable) end

---@param start integer
---@param length? integer
---@return nil
function Text:SetSelection(start, length) end

---@return nil
function Text:ClearSelection() end

---@param textEffect TextEffect
---@return nil
function Text:SetTextEffect(textEffect) end

---@param offset IntVector2
---@return nil
function Text:SetEffectShadowOffset(offset) end

---@param thickness integer
---@return nil
function Text:SetEffectStrokeThickness(thickness) end

---@param roundStroke boolean
---@return nil
function Text:SetEffectRoundStroke(roundStroke) end

---@param effectColor Color
---@return nil
function Text:SetEffectColor(effectColor) end

---@return boolean
function Text:GetAutoLocalizable() end

---@param enable boolean
---@return nil
function Text:SetAutoLocalizable(enable) end

---@return Font
function Text:GetFont() end

---@return number
function Text:GetFontSize() end

---@return string
function Text:GetText() end

---@return HorizontalAlignment
function Text:GetTextAlignment() end

---@return number
function Text:GetRowSpacing() end

---@return boolean
function Text:GetWordwrap() end

---@return integer
function Text:GetSelectionStart() end

---@return integer
function Text:GetSelectionLength() end

---@return TextEffect
function Text:GetTextEffect() end

---@return IntVector2
function Text:GetEffectShadowOffset() end

---@return integer
function Text:GetEffectStrokeThickness() end

---@return boolean
function Text:GetEffectRoundStroke() end

---@return Color
function Text:GetEffectColor() end

---@return number
function Text:GetRowHeight() end

---@return integer
function Text:GetNumRows() end

---@return integer
function Text:GetNumChars() end

---@param index integer
---@return number
function Text:GetRowWidth(index) end

---@param index integer
---@return Vector2
function Text:GetCharPosition(index) end

---@param index integer
---@return Vector2
function Text:GetCharSize(index) end

---@param bias number
---@return nil
function Text:SetEffectDepthBias(bias) end

---@return number
function Text:GetEffectDepthBias() end

