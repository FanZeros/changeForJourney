---@meta

--- Auto-generated from Math/Matrix3x4

---@class Matrix3x4
---@overload fun(matrix: Matrix3x4): Matrix3x4
---@overload fun(matrix: Matrix3): Matrix3x4
---@overload fun(matrix: Matrix4): Matrix3x4
---@overload fun(v00: number, v01: number, v02: number, v03: number, v10: number, v11: number, v12: number, v13: number, v20: number, v21: number, v22: number, v23: number): Matrix3x4
---@overload fun(translation: Vector3, rotation: Quaternion, scale: number): Matrix3x4
---@overload fun(translation: Vector3, rotation: Quaternion, scale: Vector3): Matrix3x4
---@overload fun(): Matrix3x4
---@field m00 number
---@field m01 number
---@field m02 number
---@field m03 number
---@field m10 number
---@field m11 number
---@field m12 number
---@field m13 number
---@field m20 number
---@field m21 number
---@field m22 number
---@field m23 number
---@field rotationMatrix Matrix3
---@field translation Vector3
---@field rotation Quaternion
---@field scale Vector3
---@field ZERO Matrix3x4
---@field IDENTITY Matrix3x4
---@operator eq(Matrix3x4): boolean
---@operator mul(Vector3): Vector3
---@operator mul(Vector4): Vector3
---@operator add(number): Matrix3x4
---@operator add(Matrix3x4): Matrix3x4
---@operator sub(Matrix3x4): Matrix3x4
---@operator mul(number): Matrix3x4
---@operator mul(Matrix3x4): Matrix3x4
---@operator div(number): Matrix3x4
---@operator mul(Matrix4): Matrix4
Matrix3x4 = {}

---@overload fun(self: Matrix3x4, matrix: Matrix3x4): Matrix3x4
---@overload fun(matrix: Matrix3x4): Matrix3x4
---@overload fun(self: Matrix3x4, matrix: Matrix3): Matrix3x4
---@overload fun(matrix: Matrix3): Matrix3x4
---@overload fun(self: Matrix3x4, matrix: Matrix4): Matrix3x4
---@overload fun(matrix: Matrix4): Matrix3x4
---@overload fun(self: Matrix3x4, v00: number, v01: number, v02: number, v03: number, v10: number, v11: number, v12: number, v13: number, v20: number, v21: number, v22: number, v23: number): Matrix3x4
---@overload fun(v00: number, v01: number, v02: number, v03: number, v10: number, v11: number, v12: number, v13: number, v20: number, v21: number, v22: number, v23: number): Matrix3x4
---@overload fun(self: Matrix3x4, translation: Vector3, rotation: Quaternion, scale: number): Matrix3x4
---@overload fun(translation: Vector3, rotation: Quaternion, scale: number): Matrix3x4
---@overload fun(self: Matrix3x4, translation: Vector3, rotation: Quaternion, scale: Vector3): Matrix3x4
---@overload fun(translation: Vector3, rotation: Quaternion, scale: Vector3): Matrix3x4
---@return Matrix3x4
function Matrix3x4.new() end

---@param translation Vector3
---@return nil
function Matrix3x4:SetTranslation(translation) end

---@param rotation Matrix3
---@return nil
function Matrix3x4:SetRotation(rotation) end

---@param scale Vector3
---@return nil
function Matrix3x4:SetScale(scale) end

---@param scale number
---@return nil
function Matrix3x4:SetScale(scale) end

---@return Matrix3
function Matrix3x4:ToMatrix3() end

---@return Matrix4
function Matrix3x4:ToMatrix4() end

---@return Matrix3
function Matrix3x4:RotationMatrix() end

---@return Vector3
function Matrix3x4:Translation() end

---@return Quaternion
function Matrix3x4:Rotation() end

---@return Vector3
function Matrix3x4:Scale() end

---@param rhs Matrix3x4
---@return boolean
function Matrix3x4:Equals(rhs) end

---@param translation Vector3
---@param rotation Quaternion
---@param scale Vector3
---@return nil
function Matrix3x4:Decompose(translation, rotation, scale) end

---@return Matrix3x4
function Matrix3x4:Inverse() end

---@return string
function Matrix3x4:ToString() end

