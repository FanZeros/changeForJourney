---@meta

--- Auto-generated from Math/Polyhedron

---@class Polyhedron
---@overload fun(polyhedron: Polyhedron): Polyhedron
---@overload fun(box: BoundingBox): Polyhedron
---@overload fun(frustum: Frustum): Polyhedron
---@overload fun(): Polyhedron
---@field empty boolean
Polyhedron = {}

---@overload fun(self: Polyhedron, polyhedron: Polyhedron): Polyhedron
---@overload fun(polyhedron: Polyhedron): Polyhedron
---@overload fun(self: Polyhedron, box: BoundingBox): Polyhedron
---@overload fun(box: BoundingBox): Polyhedron
---@overload fun(self: Polyhedron, frustum: Frustum): Polyhedron
---@overload fun(frustum: Frustum): Polyhedron
---@return Polyhedron
function Polyhedron.new() end

---@param box BoundingBox
---@return nil
function Polyhedron:Define(box) end

---@param frustum Frustum
---@return nil
function Polyhedron:Define(frustum) end

---@param v0 Vector3
---@param v1 Vector3
---@param v2 Vector3
---@return nil
function Polyhedron:AddFace(v0, v1, v2) end

---@param v0 Vector3
---@param v1 Vector3
---@param v2 Vector3
---@param v3 Vector3
---@return nil
function Polyhedron:AddFace(v0, v1, v2, v3) end

---@param plane Plane
---@return nil
function Polyhedron:Clip(plane) end

---@param box BoundingBox
---@return nil
function Polyhedron:Clip(box) end

---@param box Frustum
---@return nil
function Polyhedron:Clip(box) end

---@return nil
function Polyhedron:Clear() end

---@param transform Matrix3
---@return nil
function Polyhedron:Transform(transform) end

---@param transform Matrix3x4
---@return nil
function Polyhedron:Transform(transform) end

---@param transform Matrix3
---@return Polyhedron
function Polyhedron:Transformed(transform) end

---@param transform Matrix3x4
---@return Polyhedron
function Polyhedron:Transformed(transform) end

---@return boolean
function Polyhedron:Empty() end

