---@meta

--- Auto-generated from Math/BoundingBox

---@class BoundingBox
---@overload fun(box: BoundingBox): BoundingBox
---@overload fun(rect: Rect): BoundingBox
---@overload fun(min: Vector3, max: Vector3): BoundingBox
---@overload fun(min: number, max: number): BoundingBox
---@overload fun(frustum: Frustum): BoundingBox
---@overload fun(poly: Polyhedron): BoundingBox
---@overload fun(sphere: Sphere): BoundingBox
---@overload fun(): BoundingBox
---@field min Vector3
---@field max Vector3
---@field center Vector3
---@field size Vector3
---@field halfSize Vector3
---@operator eq(BoundingBox): boolean
BoundingBox = {}

---@overload fun(self: BoundingBox, box: BoundingBox): BoundingBox
---@overload fun(box: BoundingBox): BoundingBox
---@overload fun(self: BoundingBox, rect: Rect): BoundingBox
---@overload fun(rect: Rect): BoundingBox
---@overload fun(self: BoundingBox, min: Vector3, max: Vector3): BoundingBox
---@overload fun(min: Vector3, max: Vector3): BoundingBox
---@overload fun(self: BoundingBox, min: number, max: number): BoundingBox
---@overload fun(min: number, max: number): BoundingBox
---@overload fun(self: BoundingBox, frustum: Frustum): BoundingBox
---@overload fun(frustum: Frustum): BoundingBox
---@overload fun(self: BoundingBox, poly: Polyhedron): BoundingBox
---@overload fun(poly: Polyhedron): BoundingBox
---@overload fun(self: BoundingBox, sphere: Sphere): BoundingBox
---@overload fun(sphere: Sphere): BoundingBox
---@return BoundingBox
function BoundingBox.new() end

---@param box BoundingBox
---@return nil
function BoundingBox:Define(box) end

---@param rect Rect
---@return nil
function BoundingBox:Define(rect) end

---@param min Vector3
---@param max Vector3
---@return nil
function BoundingBox:Define(min, max) end

---@param min number
---@param max number
---@return nil
function BoundingBox:Define(min, max) end

---@param point Vector3
---@return nil
function BoundingBox:Define(point) end

---@param frustum Frustum
---@return nil
function BoundingBox:Define(frustum) end

---@param poly Polyhedron
---@return nil
function BoundingBox:Define(poly) end

---@param sphere Sphere
---@return nil
function BoundingBox:Define(sphere) end

---@param point Vector3
---@return nil
function BoundingBox:Merge(point) end

---@param box BoundingBox
---@return nil
function BoundingBox:Merge(box) end

---@param frustum Frustum
---@return nil
function BoundingBox:Merge(frustum) end

---@param poly Polyhedron
---@return nil
function BoundingBox:Merge(poly) end

---@param sphere Sphere
---@return nil
function BoundingBox:Merge(sphere) end

---@param box BoundingBox
---@return nil
function BoundingBox:Clip(box) end

---@param transform Matrix3
---@return nil
function BoundingBox:Transform(transform) end

---@param transform Matrix3x4
---@return nil
function BoundingBox:Transform(transform) end

---@return nil
function BoundingBox:Clear() end

---@return boolean
function BoundingBox:Defined() end

---@return Vector3
function BoundingBox:Center() end

---@return Vector3
function BoundingBox:Size() end

---@return Vector3
function BoundingBox:HalfSize() end

---@param transform Matrix3
---@return BoundingBox
function BoundingBox:Transformed(transform) end

---@param transform Matrix3x4
---@return BoundingBox
function BoundingBox:Transformed(transform) end

---@param projection Matrix4
---@return Rect
function BoundingBox:Projected(projection) end

---@param point Vector3
---@return number
function BoundingBox:DistanceToPoint(point) end

---@param point Vector3
---@return Intersection
function BoundingBox:IsInside(point) end

---@param box BoundingBox
---@return Intersection
function BoundingBox:IsInside(box) end

---@param sphere Sphere
---@return Intersection
function BoundingBox:IsInside(sphere) end

---@param box BoundingBox
---@return Intersection
function BoundingBox:IsInsideFast(box) end

---@param sphere Sphere
---@return Intersection
function BoundingBox:IsInsideFast(sphere) end

---@return string
function BoundingBox:ToString() end

