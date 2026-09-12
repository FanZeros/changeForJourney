---@meta

--- Auto-generated from Graphics/Octree

---@class Octree : Component
---@field numLevels integer
Octree = {}

---@param box BoundingBox
---@param numLevels integer
---@return nil
function Octree:SetSize(box, numLevels) end

---@param drawable Drawable
---@return nil
function Octree:AddManualDrawable(drawable) end

---@param drawable Drawable
---@return nil
function Octree:RemoveManualDrawable(drawable) end

---@param point Vector3
---@param drawableFlags? number -- unsigned char
---@param viewMask? integer
---@return OctreeQueryResult[]
function Octree:GetDrawables(point, drawableFlags, viewMask) end

---@param box BoundingBox
---@param drawableFlags? number -- unsigned char
---@param viewMask? integer
---@return OctreeQueryResult[]
function Octree:GetDrawables(box, drawableFlags, viewMask) end

---@param frustum Frustum
---@param drawableFlags? number -- unsigned char
---@param viewMask? integer
---@return OctreeQueryResult[]
function Octree:GetDrawables(frustum, drawableFlags, viewMask) end

---@param sphere Sphere
---@param drawableFlags? number -- unsigned char
---@param viewMask? integer
---@return OctreeQueryResult[]
function Octree:GetDrawables(sphere, drawableFlags, viewMask) end

---@param drawableFlags? number -- unsigned char
---@param viewMask? integer
---@return OctreeQueryResult[]
function Octree:GetAllDrawables(drawableFlags, viewMask) end

---@param ray Ray
---@param level RayQueryLevel
---@param maxDistance number
---@param drawableFlags number -- unsigned char
---@param viewMask? integer
---@return RayQueryResult[]
function Octree:Raycast(ray, level, maxDistance, drawableFlags, viewMask) end

---@param ray Ray
---@param level RayQueryLevel
---@param maxDistance number
---@param drawableFlags number -- unsigned char
---@param viewMask? integer
---@return RayQueryResult
function Octree:RaycastSingle(ray, level, maxDistance, drawableFlags, viewMask) end

---@return integer
function Octree:GetNumLevels() end

---@param drawable Drawable
---@return nil
function Octree:QueueUpdate(drawable) end

---@param depthTest boolean
---@return nil
function Octree:DrawDebugGeometry(depthTest) end

