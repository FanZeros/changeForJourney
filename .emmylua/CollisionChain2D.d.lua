---@meta

--- Auto-generated from Urho2D/CollisionChain2D

---@class CollisionChain2D : CollisionShape2D
---@field loop boolean
---@field vertexCount integer
CollisionChain2D = {}

---@param loop boolean
---@return nil
function CollisionChain2D:SetLoop(loop) end

---@param count integer
---@return nil
function CollisionChain2D:SetVertexCount(count) end

---@param index integer
---@param vertex Vector2
---@return nil
function CollisionChain2D:SetVertex(index, vertex) end

---@param vertices Vector2[]
---@return nil
function CollisionChain2D:SetVertices(vertices) end

---@return boolean
function CollisionChain2D:GetLoop() end

---@return integer
function CollisionChain2D:GetVertexCount() end

---@param index integer
---@return Vector2
function CollisionChain2D:GetVertex(index) end

