---@meta

--- Auto-generated from UI/UI

---@alias FontHintLevel
---| integer # FontHintLevel enum values

---@type FontHintLevel
FONT_HINT_LEVEL_NONE = 0
---@type FontHintLevel
FONT_HINT_LEVEL_LIGHT = 1
---@type FontHintLevel
FONT_HINT_LEVEL_NORMAL = 2

---@class UI : Object
---@field root UIElement
---@field rootModalElement UIElement
---@field cursor Cursor
---@field cursorPosition IntVector2
---@field focusElement UIElement
---@field frontElement UIElement
---@field clipboardText string
---@field doubleClickInterval number
---@field dragBeginInterval number
---@field dragBeginDistance integer
---@field defaultToolTipDelay number
---@field maxFontTextureSize integer
---@field nonFocusedMouseWheel boolean
---@field useSystemClipboard boolean
---@field useScreenKeyboard boolean
---@field useMutableGlyphs boolean
---@field forceAutoHint boolean
---@field fontHintLevel FontHintLevel
---@field fontSubpixelThreshold number
---@field fontOversampling integer
---@field modalElement boolean
---@field scale Vector2
---@field customSize IntVector2
UI = {}

---@param cursor Cursor
---@return nil
function UI:SetCursor(cursor) end

---@param element UIElement
---@param byKey? boolean
---@return nil
function UI:SetFocusElement(element, byKey) end

---@param modalElement UIElement
---@param enable boolean
---@return boolean
function UI:SetModalElement(modalElement, enable) end

---@return nil
function UI:Clear() end

---@param element UIElement
---@return nil
function UI:DebugDraw(element) end

---@param source File
---@param styleFile? XMLFile
---@return UIElement
function UI:LoadLayout(source, styleFile) end

---@param fileName string
---@param styleFile? XMLFile
---@return UIElement
function UI:LoadLayout(fileName, styleFile) end

---@param file XMLFile
---@param styleFile? XMLFile
---@return UIElement
function UI:LoadLayout(file, styleFile) end

---@param dest Serializer
---@param element UIElement
---@return boolean
function UI:SaveLayout(dest, element) end

---@param text string
---@return nil
function UI:SetClipboardText(text) end

---@param interval number
---@return nil
function UI:SetDoubleClickInterval(interval) end

---@param pixels number
---@return nil
function UI:SetMaxDoubleClickDistance(pixels) end

---@param interval number
---@return nil
function UI:SetDragBeginInterval(interval) end

---@param pixels integer
---@return nil
function UI:SetDragBeginDistance(pixels) end

---@param delay number
---@return nil
function UI:SetDefaultToolTipDelay(delay) end

---@param size integer
---@return nil
function UI:SetMaxFontTextureSize(size) end

---@param nonFocusedMouseWheel boolean
---@return nil
function UI:SetNonFocusedMouseWheel(nonFocusedMouseWheel) end

---@param enable boolean
---@return nil
function UI:SetUseSystemClipboard(enable) end

---@param enable boolean
---@return nil
function UI:SetUseScreenKeyboard(enable) end

---@param enable boolean
---@return nil
function UI:SetUseMutableGlyphs(enable) end

---@param enable boolean
---@return nil
function UI:SetForceAutoHint(enable) end

---@param level FontHintLevel
---@return nil
function UI:SetFontHintLevel(level) end

---@param threshold number
---@return nil
function UI:SetFontSubpixelThreshold(threshold) end

---@param limit integer
---@return nil
function UI:SetFontOversampling(limit) end

---@param scale Vector2
---@return nil
function UI:SetScale(scale) end

---@param width number
---@return nil
function UI:SetWidth(width) end

---@param height number
---@return nil
function UI:SetHeight(height) end

---@param size IntVector2
---@return nil
function UI:SetCustomSize(size) end

---@param width integer
---@param height integer
---@return nil
function UI:SetCustomSize(width, height) end

---@return UIElement
function UI:GetRoot() end

---@return UIElement
function UI:GetRootModalElement() end

---@return Cursor
function UI:GetCursor() end

---@return IntVector2
function UI:GetCursorPosition() end

---@param position IntVector2
---@param enabledOnly? boolean
---@return UIElement
function UI:GetElementAt(position, enabledOnly) end

---@param x integer
---@param y integer
---@param enabledOnly? boolean
---@return UIElement
function UI:GetElementAt(x, y, enabledOnly) end

---@return UIElement
function UI:GetFocusElement() end

---@return UIElement
function UI:GetFrontElement() end

---@param index integer
---@return UIElement
function UI:GetDragElement(index) end

---@return string
function UI:GetClipboardText() end

---@return number
function UI:GetDoubleClickInterval() end

---@return number
function UI:GetMaxDoubleClickDistance() end

---@return number
function UI:GetDragBeginInterval() end

---@return integer
function UI:GetDragBeginDistance() end

---@return number
function UI:GetDefaultToolTipDelay() end

---@return integer
function UI:GetMaxFontTextureSize() end

---@return boolean
function UI:IsNonFocusedMouseWheel() end

---@return boolean
function UI:GetUseSystemClipboard() end

---@return boolean
function UI:GetUseScreenKeyboard() end

---@return boolean
function UI:GetUseMutableGlyphs() end

---@return boolean
function UI:GetForceAutoHint() end

---@return FontHintLevel
function UI:GetFontHintLevel() end

---@return number
function UI:GetFontSubpixelThreshold() end

---@return integer
function UI:GetFontOversampling() end

---@return boolean
function UI:HasModalElement() end

---@return boolean
function UI:IsDragging() end

---@return Vector2
function UI:GetScale() end

---@return IntVector2
function UI:GetCustomSize() end


-- Global functions
---@return UI
function GetUI() end

-- Global variables
---@type UI
ui = nil
