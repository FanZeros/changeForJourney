---@meta

--- Auto-generated from Navigation/DynamicNavigationMesh

---@class DynamicNavigationMesh : NavigationMesh
---@field drawObstacles boolean
---@field maxObstacles integer
---@field maxLayers integer
DynamicNavigationMesh = {}

---@param enable boolean
---@return nil
function DynamicNavigationMesh:SetDrawObstacles(enable) end

---@param maxLayers integer
---@return nil
function DynamicNavigationMesh:SetMaxLayers(maxLayers) end

---@param maxObstacles integer
---@return nil
function DynamicNavigationMesh:SetMaxObstacles(maxObstacles) end

---@return boolean
function DynamicNavigationMesh:GetDrawObstacles() end

---@return integer
function DynamicNavigationMesh:GetMaxLayers() end

---@return integer
function DynamicNavigationMesh:GetMaxObstacles() end

