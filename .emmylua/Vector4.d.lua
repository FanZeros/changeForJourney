---@meta

--- Auto-generated from Math/Vector4

---@class Vector4
---@overload fun(vector: Vector4): Vector4
---@overload fun(vector: Vector3, w: number): Vector4
---@overload fun(x: number, y: number, z: number, w: number): Vector4
---@overload fun(): Vector4
---@field x number
---@field y number
---@field z number
---@field w number
---@field abs Vector4
---@field ZERO Vector4
---@field ONE Vector4
---@operator eq(Vector4): boolean
---@operator add(Vector4): Vector4
---@operator unm: Vector4
---@operator sub(Vector4): Vector4
---@operator mul(number): Vector4
---@operator mul(Vector4): Vector4
---@operator div(number): Vector4
---@operator div(Vector4): Vector4
---@operator div(Vector4): Vector4
Vector4 = {}

---@overload fun(self: Vector4, vector: Vector4): Vector4
---@overload fun(vector: Vector4): Vector4
---@overload fun(self: Vector4, vector: Vector3, w: number): Vector4
---@overload fun(vector: Vector3, w: number): Vector4
---@overload fun(self: Vector4, x: number, y: number, z: number, w: number): Vector4
---@overload fun(x: number, y: number, z: number, w: number): Vector4
---@return Vector4
function Vector4.new() end

---@param rhs Vector4
---@return number
function Vector4:DotProduct(rhs) end

---@param rhs Vector4
---@return number
function Vector4:AbsDotProduct(rhs) end

---@param axis Vector3
---@return number
function Vector4:ProjectOntoAxis(axis) end

---@return Vector4
function Vector4:Abs() end

---@param rhs Vector4
---@param t number
---@return Vector4
function Vector4:Lerp(rhs, t) end

---@param rhs Vector4
---@return boolean
function Vector4:Equals(rhs) end

---@return boolean
function Vector4:IsNaN() end

---@return string
function Vector4:ToString() end


-- Global functions
---@param lhs Vector4
---@param rhs Vector4
---@param t Vector4
---@return Vector4
function VectorLerp(lhs, rhs, t) end

---@param lhs Vector4
---@param rhs Vector4
---@return Vector4
function VectorMin(lhs, rhs) end

---@param lhs Vector4
---@param rhs Vector4
---@return Vector4
function VectorMax(lhs, rhs) end

---@param vec Vector4
---@return Vector4
function VectorFloor(vec) end

---@param vec Vector4
---@return Vector4
function VectorRound(vec) end

---@param vec Vector4
---@return Vector4
function VectorCeil(vec) end
