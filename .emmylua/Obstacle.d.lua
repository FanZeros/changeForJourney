---@meta

--- Auto-generated from Navigation/Obstacle

---@class Obstacle : Component
---@field radius number
---@field height number
Obstacle = {}

---@param depthTest boolean
---@return nil
function Obstacle:DrawDebugGeometry(depthTest) end

---@param radius number
---@return nil
function Obstacle:SetRadius(radius) end

---@param height number
---@return nil
function Obstacle:SetHeight(height) end

---@return number
function Obstacle:GetRadius() end

---@return number
function Obstacle:GetHeight() end

