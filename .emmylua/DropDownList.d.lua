---@meta

--- Auto-generated from UI/DropDownList

---@class DropDownList : Menu
---@overload fun(): DropDownList
---@field numItems integer
---@field selection integer
---@field selectedItem UIElement
---@field listView ListView
---@field placeholder UIElement
---@field placeholderText string
---@field resizePopup boolean
DropDownList = {}

---@return DropDownList
function DropDownList.new() end

---@param item UIElement
---@return nil
function DropDownList:AddItem(item) end

---@param index integer
---@param item UIElement
---@return nil
function DropDownList:InsertItem(index, item) end

---@param item UIElement
---@return nil
function DropDownList:RemoveItem(item) end

---@param index integer
---@return nil
function DropDownList:RemoveItem(index) end

---@return nil
function DropDownList:RemoveAllItems() end

---@param index integer
---@return nil
function DropDownList:SetSelection(index) end

---@param text string
---@return nil
function DropDownList:SetPlaceholderText(text) end

---@param enable boolean
---@return nil
function DropDownList:SetResizePopup(enable) end

---@return integer
function DropDownList:GetNumItems() end

---@param index integer
---@return UIElement
function DropDownList:GetItem(index) end

---@return UIElement[]
function DropDownList:GetItems() end

---@return integer
function DropDownList:GetSelection() end

---@return UIElement
function DropDownList:GetSelectedItem() end

---@return ListView
function DropDownList:GetListView() end

---@return UIElement
function DropDownList:GetPlaceholder() end

---@return string
function DropDownList:GetPlaceholderText() end

---@return boolean
function DropDownList:GetResizePopup() end

