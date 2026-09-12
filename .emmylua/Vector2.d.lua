---@meta

--- Auto-generated from Math/Vector2

---@class Vector2
---@overload fun(vector: Vector2): Vector2
---@overload fun(x: number, y: number): Vector2
---@overload fun(): Vector2
---@field x number
---@field y number
---@field length number
---@field lengthSquared number
---@field normalized Vector2
---@field abs Vector2
---@field ZERO Vector2
---@field LEFT Vector2
---@field RIGHT Vector2
---@field UP Vector2
---@field DOWN Vector2
---@field ONE Vector2
---@operator eq(Vector2): boolean
---@operator add(number): Vector2
---@operator add(Vector2): Vector2
---@operator unm: Vector2
---@operator sub(Vector2): Vector2
---@operator mul(number): Vector2
---@operator mul(Vector2): Vector2
---@operator div(number): Vector2
---@operator div(Vector2): Vector2
Vector2 = {}

---@overload fun(self: Vector2, vector: Vector2): Vector2
---@overload fun(vector: Vector2): Vector2
---@overload fun(self: Vector2, x: number, y: number): Vector2
---@overload fun(x: number, y: number): Vector2
---@return Vector2
function Vector2.new() end

---@return number
function Vector2:Length() end

---@return number
function Vector2:LengthSquared() end

---@param rhs Vector2
---@return number
function Vector2:DotProduct(rhs) end

---@param rhs Vector2
---@return number
function Vector2:AbsDotProduct(rhs) end

---@param axis Vector2
---@return number
function Vector2:ProjectOntoAxis(axis) end

---@param rhs Vector2
---@return number
function Vector2:Angle(rhs) end

---@return Vector2
function Vector2:Abs() end

---@param rhs Vector2
---@param t number
---@return Vector2
function Vector2:Lerp(rhs, t) end

---@param rhs Vector2
---@return boolean
function Vector2:Equals(rhs) end

---@return boolean
function Vector2:IsNaN() end

---@return Vector2
function Vector2:Normalized() end

---@return string
function Vector2:ToString() end


---@class IntVector2
---@overload fun(x: integer, y: integer): IntVector2
---@overload fun(rhs: IntVector2): IntVector2
---@overload fun(): IntVector2
---@field x integer
---@field y integer
---@field ZERO IntVector2
---@field LEFT IntVector2
---@field RIGHT IntVector2
---@field UP IntVector2
---@field DOWN IntVector2
---@field ONE IntVector2
---@operator eq(IntVector2): boolean
---@operator add(IntVector2): IntVector2
---@operator unm: IntVector2
---@operator sub(IntVector2): IntVector2
---@operator mul(integer): IntVector2
---@operator mul(IntVector2): IntVector2
---@operator div(integer): IntVector2
---@operator div(IntVector2): IntVector2
IntVector2 = {}

---@overload fun(self: IntVector2, x: integer, y: integer): IntVector2
---@overload fun(x: integer, y: integer): IntVector2
---@overload fun(self: IntVector2, rhs: IntVector2): IntVector2
---@overload fun(rhs: IntVector2): IntVector2
---@return IntVector2
function IntVector2.new() end

---@return string
function IntVector2:ToString() end

---@return integer
function IntVector2:ToHash() end

---@return number
function IntVector2:Length() end


-- Global functions
---@param lhs Vector2
---@param rhs Vector2
---@param t Vector2
---@return Vector2
function VectorLerp(lhs, rhs, t) end

---@param lhs Vector2
---@param rhs Vector2
---@return Vector2
function VectorMin(lhs, rhs) end

---@param lhs Vector2
---@param rhs Vector2
---@return Vector2
function VectorMax(lhs, rhs) end

---@param vec Vector2
---@return Vector2
function VectorFloor(vec) end

---@param vec Vector2
---@return Vector2
function VectorRound(vec) end

---@param vec Vector2
---@return Vector2
function VectorCeil(vec) end

---@param vec Vector2
---@return IntVector2
function VectorFloorToInt(vec) end

---@param vec Vector2
---@return IntVector2
function VectorRoundToInt(vec) end

---@param vec Vector2
---@return IntVector2
function VectorCeilToInt(vec) end

---@param lhs IntVector2
---@param rhs IntVector2
---@return IntVector2
function VectorMin(lhs, rhs) end

---@param lhs IntVector2
---@param rhs IntVector2
---@return IntVector2
function VectorMax(lhs, rhs) end

---@param seed Vector2
---@return number
function StableRandom(seed) end

---@param seed number
---@return number
function StableRandom(seed) end
