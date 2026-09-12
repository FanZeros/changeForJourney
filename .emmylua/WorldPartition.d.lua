---@meta

--- Auto-generated from Scene/WorldPartition

---@class WorldPartitionComponent : Component
---@field numGridLevels integer
---@field debugDrawEnabled boolean
---@field maxLoadingCells integer
---@field activationBudgetUsec integer
---@field initialLoadComplete boolean
---@field loadingProgress number
---@field totalCellsInRange integer
---@field activatedCellsInRange integer
WorldPartitionComponent = {}

---@param level integer
---@param cellSize number
---@param loadingRange number
---@param unloadMargin? number
---@return nil
function WorldPartitionComponent:AddGridLevel(level, cellSize, loadingRange, unloadMargin) end

---@param worldPartitionJsonPath string
---@return boolean
function WorldPartitionComponent:LoadWorldData(worldPartitionJsonPath) end

---@return integer
function WorldPartitionComponent:GetNumGridLevels() end

---@param enabled boolean
---@return nil
function WorldPartitionComponent:SetDebugDrawEnabled(enabled) end

---@return boolean
function WorldPartitionComponent:GetDebugDrawEnabled() end

---@param maxCells integer
---@return nil
function WorldPartitionComponent:SetMaxLoadingCells(maxCells) end

---@return integer
function WorldPartitionComponent:GetMaxLoadingCells() end

---@param usec integer
---@return nil
function WorldPartitionComponent:SetActivationBudgetUsec(usec) end

---@return integer
function WorldPartitionComponent:GetActivationBudgetUsec() end

---@return boolean
function WorldPartitionComponent:IsInitialLoadComplete() end

---@return number
function WorldPartitionComponent:GetLoadingProgress() end

---@return integer
function WorldPartitionComponent:GetTotalCellsInRange() end

---@return integer
function WorldPartitionComponent:GetActivatedCellsInRange() end

