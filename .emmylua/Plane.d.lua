---@meta

--- Auto-generated from Math/Plane

---@class Plane
---@overload fun(plane: Plane): Plane
---@overload fun(v0: Vector3, v1: Vector3, v2: Vector3): Plane
---@overload fun(normal: Vector3, point: Vector3): Plane
---@overload fun(plane: Vector4): Plane
---@overload fun(): Plane
---@field normal Vector3
---@field absNormal Vector3
---@field d number
---@field reflectionMatrix Matrix3x4
---@field UP Plane
Plane = {}

---@overload fun(self: Plane, plane: Plane): Plane
---@overload fun(plane: Plane): Plane
---@overload fun(self: Plane, v0: Vector3, v1: Vector3, v2: Vector3): Plane
---@overload fun(v0: Vector3, v1: Vector3, v2: Vector3): Plane
---@overload fun(self: Plane, normal: Vector3, point: Vector3): Plane
---@overload fun(normal: Vector3, point: Vector3): Plane
---@overload fun(self: Plane, plane: Vector4): Plane
---@overload fun(plane: Vector4): Plane
---@return Plane
function Plane.new() end

---@param v0 Vector3
---@param v1 Vector3
---@param v2 Vector3
---@return nil
function Plane:Define(v0, v1, v2) end

---@param normal Vector3
---@param point Vector3
---@return nil
function Plane:Define(normal, point) end

---@param plane Vector4
---@return nil
function Plane:Define(plane) end

---@param transform Matrix3
---@return nil
function Plane:Transform(transform) end

---@param transform Matrix3x4
---@return nil
function Plane:Transform(transform) end

---@param transform Matrix4
---@return nil
function Plane:Transform(transform) end

---@param point Vector3
---@return Vector3
function Plane:Project(point) end

---@param point Vector3
---@return number
function Plane:Distance(point) end

---@param direction Vector3
---@return Vector3
function Plane:Reflect(direction) end

---@return Matrix3x4
function Plane:ReflectionMatrix() end

---@param transform Matrix3
---@return Plane
function Plane:Transformed(transform) end

---@param transform Matrix3x4
---@return Plane
function Plane:Transformed(transform) end

---@param transform Matrix4
---@return Plane
function Plane:Transformed(transform) end

---@return Vector4
function Plane:ToVector4() end

