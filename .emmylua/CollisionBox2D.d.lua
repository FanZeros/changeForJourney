---@meta

--- Auto-generated from Urho2D/CollisionBox2D

---@class CollisionBox2D : CollisionShape2D
---@field size Vector2
---@field center Vector2
---@field angle number
CollisionBox2D = {}

---@param size Vector2
---@return nil
function CollisionBox2D:SetSize(size) end

---@param width number
---@param height number
---@return nil
function CollisionBox2D:SetSize(width, height) end

---@param center Vector2
---@return nil
function CollisionBox2D:SetCenter(center) end

---@param x number
---@param y number
---@return nil
function CollisionBox2D:SetCenter(x, y) end

---@param angle number
---@return nil
function CollisionBox2D:SetAngle(angle) end

---@return Vector2
function CollisionBox2D:GetSize() end

---@return Vector2
function CollisionBox2D:GetCenter() end

---@return number
function CollisionBox2D:GetAngle() end

