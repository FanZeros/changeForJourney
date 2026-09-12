---@meta

--- Auto-generated from Math/Quaternion

---@class Quaternion
---@overload fun(quat: Quaternion): Quaternion
---@overload fun(w: number, x: number, y: number, z: number): Quaternion
---@overload fun(angle: number, axis: Vector3): Quaternion
---@overload fun(angle: number): Quaternion
---@overload fun(x: number, y: number, z: number): Quaternion
---@overload fun(start: Vector3, end: Vector3): Quaternion
---@overload fun(xAxis: Vector3, yAxis: Vector3, zAxis: Vector3): Quaternion
---@overload fun(matrix: Matrix3): Quaternion
---@overload fun(): Quaternion
---@field w number
---@field x number
---@field y number
---@field z number
---@field lengthSquared number
---@field normalized Quaternion
---@field conjugate Quaternion
---@field eulerAngles Vector3
---@field yawAngle number
---@field pitchAngle number
---@field rollAngle number
---@field axis Vector3
---@field angle number
---@field rotationMatrix Matrix3
---@field IDENTITY Quaternion
---@operator eq(Quaternion): boolean
---@operator add(Quaternion): Quaternion
---@operator unm: Quaternion
---@operator sub(Quaternion): Quaternion
---@operator mul(number): Quaternion
---@operator mul(Quaternion): Quaternion
---@operator mul(Vector3): Vector3
Quaternion = {}

---@overload fun(self: Quaternion, quat: Quaternion): Quaternion
---@overload fun(quat: Quaternion): Quaternion
---@overload fun(self: Quaternion, w: number, x: number, y: number, z: number): Quaternion
---@overload fun(w: number, x: number, y: number, z: number): Quaternion
---@overload fun(self: Quaternion, angle: number, axis: Vector3): Quaternion
---@overload fun(angle: number, axis: Vector3): Quaternion
---@overload fun(self: Quaternion, angle: number): Quaternion
---@overload fun(angle: number): Quaternion
---@overload fun(self: Quaternion, x: number, y: number, z: number): Quaternion
---@overload fun(x: number, y: number, z: number): Quaternion
---@overload fun(self: Quaternion, start: Vector3, end: Vector3): Quaternion
---@overload fun(start: Vector3, end: Vector3): Quaternion
---@overload fun(self: Quaternion, xAxis: Vector3, yAxis: Vector3, zAxis: Vector3): Quaternion
---@overload fun(xAxis: Vector3, yAxis: Vector3, zAxis: Vector3): Quaternion
---@overload fun(self: Quaternion, matrix: Matrix3): Quaternion
---@overload fun(matrix: Matrix3): Quaternion
---@return Quaternion
function Quaternion.new() end

---@param angle number
---@param axis Vector3
---@return nil
function Quaternion:FromAngleAxis(angle, axis) end

---@param x number
---@param y number
---@param z number
---@return nil
function Quaternion:FromEulerAngles(x, y, z) end

---@param start Vector3
---@param end_ Vector3
---@return nil
function Quaternion:FromRotationTo(start, end_) end

---@param xAxis Vector3
---@param yAxis Vector3
---@param zAxis Vector3
---@return nil
function Quaternion:FromAxes(xAxis, yAxis, zAxis) end

---@param matrix Matrix3
---@return nil
function Quaternion:FromRotationMatrix(matrix) end

---@param direction Vector3
---@param up? Vector3
---@return boolean
function Quaternion:FromLookRotation(direction, up) end

---@return nil
function Quaternion:Normalize() end

---@return Quaternion
function Quaternion:Normalized() end

---@return Quaternion
function Quaternion:Inverse() end

---@return number
function Quaternion:LengthSquared() end

---@param rhs Quaternion
---@return number
function Quaternion:DotProduct(rhs) end

---@param rhs Quaternion
---@return boolean
function Quaternion:Equals(rhs) end

---@return boolean
function Quaternion:IsNaN() end

---@return Quaternion
function Quaternion:Conjugate() end

---@return Vector3
function Quaternion:EulerAngles() end

---@return number
function Quaternion:YawAngle() end

---@return number
function Quaternion:PitchAngle() end

---@return number
function Quaternion:RollAngle() end

---@return Vector3
function Quaternion:Axis() end

---@return number
function Quaternion:Angle() end

---@return Matrix3
function Quaternion:RotationMatrix() end

---@param rhs Quaternion
---@param t number
---@return Quaternion
function Quaternion:Slerp(rhs, t) end

---@param rhs Quaternion
---@param t number
---@param shortestPath boolean
---@return Quaternion
function Quaternion:Nlerp(rhs, t, shortestPath) end

---@return string
function Quaternion:ToString() end

