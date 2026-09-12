---@meta

--- Auto-generated from Math/Vector3

---@class Vector3
---@overload fun(vector: Vector3): Vector3
---@overload fun(vector: Vector2, z: number): Vector3
---@overload fun(vector: Vector2): Vector3
---@overload fun(x: number, y: number, z: number): Vector3
---@overload fun(x: number, y: number): Vector3
---@overload fun(): Vector3
---@field x number
---@field y number
---@field z number
---@field length number
---@field lengthSquared number
---@field normalized Vector3
---@field abs Vector3
---@field ZERO Vector3
---@field LEFT Vector3
---@field RIGHT Vector3
---@field UP Vector3
---@field DOWN Vector3
---@field FORWARD Vector3
---@field BACK Vector3
---@field ONE Vector3
---@operator eq(Vector3): boolean
---@operator add(number): Vector3
---@operator add(Vector3): Vector3
---@operator unm: Vector3
---@operator sub(Vector3): Vector3
---@operator mul(number): Vector3
---@operator mul(Vector3): Vector3
---@operator div(number): Vector3
---@operator div(Vector3): Vector3
Vector3 = {}

---@overload fun(self: Vector3, vector: Vector3): Vector3
---@overload fun(vector: Vector3): Vector3
---@overload fun(self: Vector3, vector: Vector2, z: number): Vector3
---@overload fun(vector: Vector2, z: number): Vector3
---@overload fun(self: Vector3, vector: Vector2): Vector3
---@overload fun(vector: Vector2): Vector3
---@overload fun(self: Vector3, x: number, y: number, z: number): Vector3
---@overload fun(x: number, y: number, z: number): Vector3
---@overload fun(self: Vector3, x: number, y: number): Vector3
---@overload fun(x: number, y: number): Vector3
---@return Vector3
function Vector3.new() end

---@return number
function Vector3:Length() end

---@return number
function Vector3:LengthSquared() end

---@param rhs Vector3
---@return number
function Vector3:DotProduct(rhs) end

---@param rhs Vector3
---@return number
function Vector3:AbsDotProduct(rhs) end

---@param axis Vector3
---@return number
function Vector3:ProjectOntoAxis(axis) end

---@param origin Vector3
---@param normal Vector3
---@return Vector3
function Vector3:ProjectOntoPlane(origin, normal) end

---@param from Vector3
---@param to Vector3
---@param clamped? boolean
---@return Vector3
function Vector3:ProjectOntoLine(from, to, clamped) end

---@param point Vector3
---@return number
function Vector3:DistanceToPoint(point) end

---@param origin Vector3
---@param normal Vector3
---@return number
function Vector3:DistanceToPlane(origin, normal) end

---@param axis Vector3
---@return Vector3
function Vector3:Orthogonalize(axis) end

---@param rhs Vector3
---@return Vector3
function Vector3:CrossProduct(rhs) end

---@return Vector3
function Vector3:Abs() end

---@param rhs Vector3
---@param t number
---@return Vector3
function Vector3:Lerp(rhs, t) end

---@param rhs Vector3
---@return boolean
function Vector3:Equals(rhs) end

---@return boolean
function Vector3:IsNaN() end

---@param rhs Vector3
---@return number
function Vector3:Angle(rhs) end

---@return Vector3
function Vector3:Normalized() end

---@return string
function Vector3:ToString() end


---@class IntVector3
---@overload fun(x: integer, y: integer, z: integer): IntVector3
---@overload fun(rhs: IntVector3): IntVector3
---@overload fun(): IntVector3
---@field x integer
---@field y integer
---@field z integer
---@field ZERO IntVector3
---@field LEFT IntVector3
---@field RIGHT IntVector3
---@field UP IntVector3
---@field DOWN IntVector3
---@field FORWARD IntVector3
---@field BACK IntVector3
---@field ONE IntVector3
---@operator eq(IntVector3): boolean
---@operator add(IntVector3): IntVector3
---@operator unm: IntVector3
---@operator sub(IntVector3): IntVector3
---@operator mul(integer): IntVector3
---@operator mul(IntVector3): IntVector3
---@operator div(integer): IntVector3
---@operator div(IntVector3): IntVector3
IntVector3 = {}

---@overload fun(self: IntVector3, x: integer, y: integer, z: integer): IntVector3
---@overload fun(x: integer, y: integer, z: integer): IntVector3
---@overload fun(self: IntVector3, rhs: IntVector3): IntVector3
---@overload fun(rhs: IntVector3): IntVector3
---@return IntVector3
function IntVector3.new() end

---@return string
function IntVector3:ToString() end

---@return integer
function IntVector3:ToHash() end

---@return number
function IntVector3:Length() end


-- Global functions
---@param lhs Vector3
---@param rhs Vector3
---@param t Vector3
---@return Vector3
function VectorLerp(lhs, rhs, t) end

---@param lhs Vector3
---@param rhs Vector3
---@return Vector3
function VectorMin(lhs, rhs) end

---@param lhs Vector3
---@param rhs Vector3
---@return Vector3
function VectorMax(lhs, rhs) end

---@param vec Vector3
---@return Vector3
function VectorFloor(vec) end

---@param vec Vector3
---@return Vector3
function VectorRound(vec) end

---@param vec Vector3
---@return Vector3
function VectorCeil(vec) end

---@param vec Vector3
---@return IntVector3
function VectorFloorToInt(vec) end

---@param vec Vector3
---@return IntVector3
function VectorRoundToInt(vec) end

---@param vec Vector3
---@return IntVector3
function VectorCeilToInt(vec) end

---@param lhs IntVector3
---@param rhs IntVector3
---@return IntVector3
function VectorMin(lhs, rhs) end

---@param lhs IntVector3
---@param rhs IntVector3
---@return IntVector3
function VectorMax(lhs, rhs) end

---@param seed Vector3
---@return number
function StableRandom(seed) end
