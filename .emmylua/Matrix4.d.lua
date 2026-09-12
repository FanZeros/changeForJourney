---@meta

--- Auto-generated from Math/Matrix4

---@class Matrix4
---@overload fun(matrix: Matrix4): Matrix4
---@overload fun(matrix: Matrix3): Matrix4
---@overload fun(v00: number, v01: number, v02: number, v03: number, v10: number, v11: number, v12: number, v13: number, v20: number, v21: number, v22: number, v23: number, v30: number, v31: number, v32: number, v33: number): Matrix4
---@overload fun(): Matrix4
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
---@field m30 number
---@field m31 number
---@field m32 number
---@field m33 number
---@field rotationMatrix Matrix3
---@field translation Vector3
---@field rotation Quaternion
---@field scale Vector3
---@field transpose Matrix4
---@field inverse Matrix4
---@field ZERO Matrix4
---@field IDENTITY Matrix4
---@operator eq(Matrix4): boolean
---@operator mul(Vector3): Vector3
---@operator mul(Vector4): Vector4
---@operator add(Matrix4): Matrix4
---@operator sub(Matrix4): Matrix4
---@operator mul(number): Matrix4
---@operator mul(Matrix4): Matrix4
---@operator mul(Matrix3x4): Matrix4
Matrix4 = {}

---@overload fun(self: Matrix4, matrix: Matrix4): Matrix4
---@overload fun(matrix: Matrix4): Matrix4
---@overload fun(self: Matrix4, matrix: Matrix3): Matrix4
---@overload fun(matrix: Matrix3): Matrix4
---@overload fun(self: Matrix4, v00: number, v01: number, v02: number, v03: number, v10: number, v11: number, v12: number, v13: number, v20: number, v21: number, v22: number, v23: number, v30: number, v31: number, v32: number, v33: number): Matrix4
---@overload fun(v00: number, v01: number, v02: number, v03: number, v10: number, v11: number, v12: number, v13: number, v20: number, v21: number, v22: number, v23: number, v30: number, v31: number, v32: number, v33: number): Matrix4
---@return Matrix4
function Matrix4.new() end

---@param translation Vector3
---@return nil
function Matrix4:SetTranslation(translation) end

---@param rotation Matrix3
---@return nil
function Matrix4:SetRotation(rotation) end

---@param scale Vector3
---@return nil
function Matrix4:SetScale(scale) end

---@param scale number
---@return nil
function Matrix4:SetScale(scale) end

---@return Matrix3
function Matrix4:ToMatrix3() end

---@return Matrix3
function Matrix4:RotationMatrix() end

---@return Vector3
function Matrix4:Translation() end

---@return Quaternion
function Matrix4:Rotation() end

---@return Vector3
function Matrix4:Scale() end

---@return Matrix4
function Matrix4:Transpose() end

---@param rhs Matrix4
---@return boolean
function Matrix4:Equals(rhs) end

---@param translation Vector3
---@param rotation Quaternion
---@param scale Vector3
---@return nil
function Matrix4:Decompose(translation, rotation, scale) end

---@return Matrix4
function Matrix4:Inverse() end

---@return string
function Matrix4:ToString() end

