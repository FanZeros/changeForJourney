---@meta

--- Auto-generated from Scene/WorldPartitionCell

---@class WorldPartitionCell : Component
---@field pendingCount integer
---@field ready boolean
WorldPartitionCell = {}

---@return nil
function WorldPartitionCell:IncrementPending() end

---@return nil
function WorldPartitionCell:DecrementPending() end

---@return integer
function WorldPartitionCell:GetPendingCount() end

---@return boolean
function WorldPartitionCell:IsReady() end

---@param node Node
---@return WorldPartitionCell
function WorldPartitionCell:FindInParents(node) end

