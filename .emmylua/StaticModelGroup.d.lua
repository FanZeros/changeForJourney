---@meta

--- Auto-generated from Graphics/StaticModelGroup

---@class StaticModelGroup : StaticModel
---@field numInstanceNodes integer
StaticModelGroup = {}

---@param node Node
---@return nil
function StaticModelGroup:AddInstanceNode(node) end

---@param node Node
---@return nil
function StaticModelGroup:RemoveInstanceNode(node) end

---@return nil
function StaticModelGroup:RemoveAllInstanceNodes() end

---@return integer
function StaticModelGroup:GetNumInstanceNodes() end

---@param index integer
---@return Node
function StaticModelGroup:GetInstanceNode(index) end

