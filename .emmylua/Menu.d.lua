---@meta

--- Auto-generated from UI/Menu

---@class Menu : Button
---@overload fun(): Menu
---@field popup UIElement
---@field popupOffset IntVector2
---@field showPopup boolean
---@field acceleratorKey integer
---@field acceleratorQualifiers integer
Menu = {}

---@return Menu
function Menu.new() end

---@param element UIElement
---@return nil
function Menu:SetPopup(element) end

---@param offset IntVector2
---@return nil
function Menu:SetPopupOffset(offset) end

---@param x integer
---@param y integer
---@return nil
function Menu:SetPopupOffset(x, y) end

---@param enable boolean
---@return nil
function Menu:ShowPopup(enable) end

---@param key integer
---@param qualifiers integer
---@return nil
function Menu:SetAccelerator(key, qualifiers) end

---@return UIElement
function Menu:GetPopup() end

---@return IntVector2
function Menu:GetPopupOffset() end

---@return boolean
function Menu:GetShowPopup() end

---@return integer
function Menu:GetAcceleratorKey() end

---@return integer
function Menu:GetAcceleratorQualifiers() end

