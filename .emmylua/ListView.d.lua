---@meta

--- Auto-generated from UI/ListView

---@alias HighlightMode
---| integer # HighlightMode enum values

---@type HighlightMode
HM_NEVER = 0
---@type HighlightMode
HM_FOCUS = 1
---@type HighlightMode
HM_ALWAYS = 2

---@class HierarchyContainer : UIElement
HierarchyContainer = {}


---@class ListView : ScrollView
---@overload fun(): ListView
---@field numItems integer
---@field selection integer
---@field selectedItem UIElement
---@field highlightMode HighlightMode
---@field multiselect boolean
---@field clearSelectionOnDefocus boolean
---@field selectOnClickEnd boolean
---@field hierarchyMode boolean
---@field baseIndent integer
ListView = {}

---@return ListView
function ListView.new() end

---@return nil
function ListView:UpdateInternalLayout() end

---@return nil
function ListView:DisableInternalLayoutUpdate() end

---@return nil
function ListView:EnableInternalLayoutUpdate() end

---@param item UIElement
---@return nil
function ListView:AddItem(item) end

---@param index integer
---@param item UIElement
---@param parentItem? UIElement
---@return nil
function ListView:InsertItem(index, item, parentItem) end

---@param item UIElement
---@param index? integer
---@return nil
function ListView:RemoveItem(item, index) end

---@param index integer
---@return nil
function ListView:RemoveItem(index) end

---@return nil
function ListView:RemoveAllItems() end

---@param index integer
---@return nil
function ListView:SetSelection(index) end

---@param indices integer[]
---@return nil
function ListView:SetSelections(indices) end

---@param index integer
---@return nil
function ListView:AddSelection(index) end

---@param index integer
---@return nil
function ListView:RemoveSelection(index) end

---@param index integer
---@return nil
function ListView:ToggleSelection(index) end

---@param delta integer
---@param additive? boolean
---@return nil
function ListView:ChangeSelection(delta, additive) end

---@return nil
function ListView:ClearSelection() end

---@param mode HighlightMode
---@return nil
function ListView:SetHighlightMode(mode) end

---@param enable boolean
---@return nil
function ListView:SetMultiselect(enable) end

---@param enable boolean
---@return nil
function ListView:SetHierarchyMode(enable) end

---@param baseIndent integer
---@return nil
function ListView:SetBaseIndent(baseIndent) end

---@param enable boolean
---@return nil
function ListView:SetClearSelectionOnDefocus(enable) end

---@param enable boolean
---@return nil
function ListView:SetSelectOnClickEnd(enable) end

---@param index integer
---@param enable boolean
---@param recursive? boolean
---@return nil
function ListView:Expand(index, enable, recursive) end

---@param index integer
---@param recursive? boolean
---@return nil
function ListView:ToggleExpand(index, recursive) end

---@return integer
function ListView:GetNumItems() end

---@param index integer
---@return UIElement
function ListView:GetItem(index) end

---@return UIElement[]
function ListView:GetItems() end

---@param item UIElement
---@return integer
function ListView:FindItem(item) end

---@return integer
function ListView:GetSelection() end

---@return integer[]
function ListView:GetSelections() end

---@return nil
function ListView:CopySelectedItemsToClipboard() end

---@return UIElement
function ListView:GetSelectedItem() end

---@return UIElement[]
function ListView:GetSelectedItems() end

---@param index integer
---@return boolean
function ListView:IsSelected(index) end

---@param index integer
---@return boolean
function ListView:IsExpanded(index) end

---@return HighlightMode
function ListView:GetHighlightMode() end

---@return boolean
function ListView:GetMultiselect() end

---@return boolean
function ListView:GetClearSelectionOnDefocus() end

---@return boolean
function ListView:GetSelectOnClickEnd() end

---@return boolean
function ListView:GetHierarchyMode() end

---@return integer
function ListView:GetBaseIndent() end

