---@meta

--- Auto-generated from Graphics/OctreeQuery

---@alias RayQueryLevel
---| integer # RayQueryLevel enum values

---@type RayQueryLevel
RAY_AABB = 0
---@type RayQueryLevel
RAY_OBB = 1
---@type RayQueryLevel
RAY_TRIANGLE = 2
---@type RayQueryLevel
RAY_TRIANGLE_UV = 3
---@type RayQueryLevel
RAY_CONVEXHULL = 4

---@class OctreeQueryResult
---@overload fun(): OctreeQueryResult
---@field drawable Drawable
---@field node Node
OctreeQueryResult = {}

---@return OctreeQueryResult
function OctreeQueryResult.new() end


---@class RayQueryResult
---@overload fun(): RayQueryResult
---@field position Vector3
---@field normal Vector3
---@field textureUV Vector2
---@field distance number
---@field drawable Drawable
---@field node Node
---@field subObject integer
RayQueryResult = {}

---@return RayQueryResult
function RayQueryResult.new() end

