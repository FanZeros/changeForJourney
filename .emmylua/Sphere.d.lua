---@meta

--- Auto-generated from Math/Sphere

---@class Sphere
---@overload fun(sphere: Sphere): Sphere
---@overload fun(center: Vector3, radius: number): Sphere
---@overload fun(box: BoundingBox): Sphere
---@overload fun(frustum: Frustum): Sphere
---@overload fun(poly: Polyhedron): Sphere
---@overload fun(): Sphere
---@field center Vector3
---@field radius number
---@operator eq(Sphere): boolean
Sphere = {}

---@overload fun(self: Sphere, sphere: Sphere): Sphere
---@overload fun(sphere: Sphere): Sphere
---@overload fun(self: Sphere, center: Vector3, radius: number): Sphere
---@overload fun(center: Vector3, radius: number): Sphere
---@overload fun(self: Sphere, box: BoundingBox): Sphere
---@overload fun(box: BoundingBox): Sphere
---@overload fun(self: Sphere, frustum: Frustum): Sphere
---@overload fun(frustum: Frustum): Sphere
---@overload fun(self: Sphere, poly: Polyhedron): Sphere
---@overload fun(poly: Polyhedron): Sphere
---@return Sphere
function Sphere.new() end

---@param sphere Sphere
---@return nil
function Sphere:Define(sphere) end

---@param center Vector3
---@param radius number
---@return nil
function Sphere:Define(center, radius) end

---@param box BoundingBox
---@return nil
function Sphere:Define(box) end

---@param frustum Frustum
---@return nil
function Sphere:Define(frustum) end

---@param poly Polyhedron
---@return nil
function Sphere:Define(poly) end

---@param point Vector3
---@return nil
function Sphere:Merge(point) end

---@param box BoundingBox
---@return nil
function Sphere:Merge(box) end

---@param frustum Frustum
---@return nil
function Sphere:Merge(frustum) end

---@param poly Polyhedron
---@return nil
function Sphere:Merge(poly) end

---@param sphere Sphere
---@return nil
function Sphere:Merge(sphere) end

---@return nil
function Sphere:Clear() end

---@return boolean
function Sphere:Defined() end

---@param point Vector3
---@return Intersection
function Sphere:IsInside(point) end

---@param sphere Sphere
---@return Intersection
function Sphere:IsInside(sphere) end

---@param box BoundingBox
---@return Intersection
function Sphere:IsInside(box) end

---@param sphere Sphere
---@return Intersection
function Sphere:IsInsideFast(sphere) end

---@param box BoundingBox
---@return Intersection
function Sphere:IsInsideFast(box) end

---@param point Vector3
---@return number
function Sphere:Distance(point) end

---@param theta number
---@param phi number
---@return Vector3
function Sphere:GetLocalPoint(theta, phi) end

---@param theta number
---@param phi number
---@return Vector3
function Sphere:GetPoint(theta, phi) end

