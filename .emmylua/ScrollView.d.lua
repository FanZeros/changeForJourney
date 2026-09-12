---@meta

--- Auto-generated from UI/ScrollView

---@class ScrollView : UIElement
---@overload fun(): ScrollView
---@field viewPosition IntVector2
---@field contentElement UIElement
---@field horizontalScrollBar ScrollBar
---@field verticalScrollBar ScrollBar
---@field scrollPanel BorderImage
---@field scrollBarsAutoVisible boolean
---@field horizontalScrollBarVisible boolean
---@field verticalScrollBarVisible boolean
---@field scrollStep number
---@field pageStep number
---@field scrollDeceleration number
---@field scrollSnapEpsilon number
ScrollView = {}

---@return ScrollView
function ScrollView.new() end

---@param element UIElement
---@return nil
function ScrollView:SetContentElement(element) end

---@param position IntVector2
---@return nil
function ScrollView:SetViewPosition(position) end

---@param x integer
---@param y integer
---@return nil
function ScrollView:SetViewPosition(x, y) end

---@param horizontal boolean
---@param vertical boolean
---@return nil
function ScrollView:SetScrollBarsVisible(horizontal, vertical) end

---@param enable boolean
---@return nil
function ScrollView:SetScrollBarsAutoVisible(enable) end

---@param step number
---@return nil
function ScrollView:SetScrollStep(step) end

---@param step number
---@return nil
function ScrollView:SetPageStep(step) end

---@param deceleration number
---@return nil
function ScrollView:SetScrollDeceleration(deceleration) end

---@param snap number
---@return nil
function ScrollView:SetScrollSnapEpsilon(snap) end

---@param disable boolean
---@return nil
function ScrollView:SetAutoDisableChildren(disable) end

---@param amount number
---@return nil
function ScrollView:SetAutoDisableThreshold(amount) end

---@return IntVector2
function ScrollView:GetViewPosition() end

---@return UIElement
function ScrollView:GetContentElement() end

---@return ScrollBar
function ScrollView:GetHorizontalScrollBar() end

---@return ScrollBar
function ScrollView:GetVerticalScrollBar() end

---@return BorderImage
function ScrollView:GetScrollPanel() end

---@return boolean
function ScrollView:GetScrollBarsAutoVisible() end

---@return number
function ScrollView:GetScrollStep() end

---@return number
function ScrollView:GetPageStep() end

---@return number
function ScrollView:GetScrollDeceleration() end

---@return number
function ScrollView:GetScrollSnapEpsilon() end

---@return boolean
function ScrollView:GetAutoDisableChildren() end

---@return number
function ScrollView:GetAutoDisableThreshold() end

