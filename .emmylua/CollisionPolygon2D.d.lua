---@meta

--- Auto-generated from Urho2D/CollisionPolygon2D

---@class CollisionPolygon2D : CollisionShape2D
---@field vertexCount integer
CollisionPolygon2D = {}

---@param count integer
---@return nil
function CollisionPolygon2D:SetVertexCount(count) end

---@param index integer
---@param vertex Vector2
---@return nil
function CollisionPolygon2D:SetVertex(index, vertex) end

---@param vertices Vector2[]
---@return nil
function CollisionPolygon2D:SetVertices(vertices) end

---@return integer
function CollisionPolygon2D:GetVertexCount() end

---@param index integer
---@return Vector2
function CollisionPolygon2D:GetVertex(index) end

