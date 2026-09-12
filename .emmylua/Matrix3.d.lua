---@meta

--- Auto-generated from Math/Matrix3

---@class Matrix3
---@overload fun(matrix: Matrix3): Matrix3
---@overload fun(v00: number, v01: number, v02: number, v10: number, v11: number, v12: number, v20: number, v21: number, v22: number): Matrix3
---@overload fun(): Matrix3
---@field m00 number
---@field m01 number
---@field m02 number
---@field m10 number
---@field m11 number
---@field m12 number
---@field m20 number
---@field m21 number
---@field m22 number
---@field scale Vector3
---@field transpose Matrix3
---@field inverse Matrix3
---@field ZERO Matrix3
---@field IDENTITY Matrix3
---@operator eq(Matrix3): boolean
---@operator mul(Vector3): Vector3
---@operator add(Matrix3): Matrix3
---@operator sub(Matrix3): Matrix3
---@operator mul(number): Matrix3
---@operator mul(Matrix3): Matrix3
Matrix3 = {}

---@overload fun(self: Matrix3, matrix: Matrix3): Matrix3
---@overload fun(matrix: Matrix3): Matrix3
---@overload fun(self: Matrix3, v00: number, v01: number, v02: number, v10: number, v11: number, v12: number, v20: number, v21: number, v22: number): Matrix3
---@overload fun(v00: number, v01: number, v02: number, v10: number, v11: number, v12: number, v20: number, v21: number, v22: number): Matrix3
---@return Matrix3
function Matrix3.new() end

---@param scale Vector3
---@return nil
function Matrix3:SetScale(scale) end

---@param scale number
---@return nil
function Matrix3:SetScale(scale) end

---@return Vector3
function Matrix3:Scale() end

---@return Matrix3
function Matrix3:Transpose() end

---@param scale Vector3
---@return Matrix3
function Matrix3:Scaled(scale) end

---@param rhs Matrix3
---@return boolean
function Matrix3:Equals(rhs) end

---@return Matrix3
function Matrix3:Inverse() end

---@return string
function Matrix3:ToString() end

