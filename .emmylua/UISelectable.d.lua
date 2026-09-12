---@meta

--- Auto-generated from UI/UISelectable

---@class UISelectable : UIElement
---@overload fun(): UISelectable
---@field selectionColor Color
---@field hoverColor Color
UISelectable = {}

---@return UISelectable
function UISelectable.new() end

---@param color Color
---@return nil
function UISelectable:SetSelectionColor(color) end

---@param color Color
---@return nil
function UISelectable:SetHoverColor(color) end

---@return Color
function UISelectable:GetSelectionColor() end

---@return Color
function UISelectable:GetHoverColor() end

