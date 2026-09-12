---@meta

--- Auto-generated from Urho2D/CollisionEdge2D

---@class CollisionEdge2D : CollisionShape2D
---@field vertex1 Vector2
---@field vertex2 Vector2
CollisionEdge2D = {}

---@param vertex Vector2
---@return nil
function CollisionEdge2D:SetVertex1(vertex) end

---@param vertex Vector2
---@return nil
function CollisionEdge2D:SetVertex2(vertex) end

---@param vertex1 Vector2
---@param vertex2 Vector2
---@return nil
function CollisionEdge2D:SetVertices(vertex1, vertex2) end

---@return Vector2
function CollisionEdge2D:GetVertex1() end

---@return Vector2
function CollisionEdge2D:GetVertex2() end

