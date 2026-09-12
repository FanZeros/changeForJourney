---@meta

--- Auto-generated from Math/Frustum

---@alias FrustumPlane
---| integer # FrustumPlane enum values

---@type FrustumPlane
PLANE_NEAR = 0
---@type FrustumPlane
PLANE_LEFT = 1
---@type FrustumPlane
PLANE_RIGHT = 2
---@type FrustumPlane
PLANE_UP = 3
---@type FrustumPlane
PLANE_DOWN = 4
---@type FrustumPlane
PLANE_FAR = 5

---@class Frustum
---@overload fun(frustum: Frustum): Frustum
---@overload fun(): Frustum
Frustum = {}

---@overload fun(self: Frustum, frustum: Frustum): Frustum
---@overload fun(frustum: Frustum): Frustum
---@return Frustum
function Frustum.new() end

---@param fov number
---@param aspectRatio number
---@param zoom number
---@param nearZ number
---@param farZ number
---@param transform? Matrix3x4
---@return nil
function Frustum:Define(fov, aspectRatio, zoom, nearZ, farZ, transform) end

---@param near Vector3
---@param far Vector3
---@param transform? Matrix3x4
---@return nil
function Frustum:Define(near, far, transform) end

---@param box BoundingBox
---@param transform? Matrix3x4
---@return nil
function Frustum:Define(box, transform) end

---@param projection Matrix4
---@return nil
function Frustum:Define(projection) end

---@param orthoSize number
---@param aspectRatio number
---@param zoom number
---@param nearZ number
---@param farZ number
---@param transform? Matrix3x4
---@return nil
function Frustum:DefineOrtho(orthoSize, aspectRatio, zoom, nearZ, farZ, transform) end

---@param projection Matrix4
---@param near number
---@param far number
---@return nil
function Frustum:DefineSplit(projection, near, far) end

---@param transform Matrix3
---@return nil
function Frustum:Transform(transform) end

---@param transform Matrix3x4
---@return nil
function Frustum:Transform(transform) end

---@param point Vector3
---@return Intersection
function Frustum:IsInside(point) end

---@param sphere Sphere
---@return Intersection
function Frustum:IsInside(sphere) end

---@param box BoundingBox
---@return Intersection
function Frustum:IsInside(box) end

---@param sphere Sphere
---@return Intersection
function Frustum:IsInsideFast(sphere) end

---@param box BoundingBox
---@return Intersection
function Frustum:IsInsideFast(box) end

---@param point Vector3
---@return number
function Frustum:Distance(point) end

---@param transform Matrix3
---@return Frustum
function Frustum:Transformed(transform) end

---@param transform Matrix3x4
---@return Frustum
function Frustum:Transformed(transform) end

---@param transform Matrix4
---@return Rect
function Frustum:Projected(transform) end

---@return nil
function Frustum:UpdatePlanes() end


-- Global variables
---@type integer
NUM_FRUSTUM_PLANES = nil
---@type integer
NUM_FRUSTUM_VERTICES = nil
