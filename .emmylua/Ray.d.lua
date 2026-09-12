---@meta

--- Auto-generated from Math/Ray

---@class Ray
---@overload fun(origin: Vector3, direction: Vector3): Ray
---@overload fun(ray: Ray): Ray
---@overload fun(): Ray
---@field origin Vector3
---@field direction Vector3
---@operator eq(Ray): boolean
Ray = {}

---@overload fun(self: Ray, origin: Vector3, direction: Vector3): Ray
---@overload fun(origin: Vector3, direction: Vector3): Ray
---@overload fun(self: Ray, ray: Ray): Ray
---@overload fun(ray: Ray): Ray
---@return Ray
function Ray.new() end

---@param origin Vector3
---@param direction Vector3
---@return nil
function Ray:Define(origin, direction) end

---@param point Vector3
---@return Vector3
function Ray:Project(point) end

---@param point Vector3
---@return number
function Ray:Distance(point) end

---@param ray Ray
---@return Vector3
function Ray:ClosestPoint(ray) end

---@param plane Plane
---@return number
function Ray:HitDistance(plane) end

---@param box BoundingBox
---@return number
function Ray:HitDistance(box) end

---@param frustum Frustum
---@param solidInside? boolean
---@return number
function Ray:HitDistance(frustum, solidInside) end

---@param sphere Sphere
---@return number
function Ray:HitDistance(sphere) end

---@param v0 Vector3
---@param v1 Vector3
---@param v2 Vector3
---@return number
function Ray:HitDistance(v0, v1, v2) end

---@param transform Matrix3x4
---@return Ray
function Ray:Transformed(transform) end

