---@meta

--- Auto-generated from Network/NetworkPriority

---@class NetworkPriority : Component
---@field basePriority number
---@field distanceFactor number
---@field minPriority number
---@field alwaysUpdateOwner boolean
NetworkPriority = {}

---@param priority number
---@return nil
function NetworkPriority:SetBasePriority(priority) end

---@param factor number
---@return nil
function NetworkPriority:SetDistanceFactor(factor) end

---@param priority number
---@return nil
function NetworkPriority:SetMinPriority(priority) end

---@param enable boolean
---@return nil
function NetworkPriority:SetAlwaysUpdateOwner(enable) end

---@return number
function NetworkPriority:GetBasePriority() end

---@return number
function NetworkPriority:GetDistanceFactor() end

---@return number
function NetworkPriority:GetMinPriority() end

---@return boolean
function NetworkPriority:GetAlwaysUpdateOwner() end

---@param distance number
---@param accumulator number
---@return boolean
function NetworkPriority:CheckUpdate(distance, accumulator) end

