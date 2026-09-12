---@meta

--- Auto-generated from Math/Matrix2

---@class Matrix2
---@overload fun(matrix: Matrix2): Matrix2
---@overload fun(v00: number, v01: number, v02: number, v10: number, v11: number, v12: number, v20: number, v21: number, v22: number): Matrix2
---@overload fun(): Matrix2
---@field m00 number
---@field m01 number
---@field m10 number
---@field m11 number
---@field ZERO Matrix2
---@field IDENTITY Matrix2
---@operator eq(Matrix2): boolean
---@operator mul(Vector2): Vector2
---@operator add(Matrix2): Matrix2
---@operator sub(Matrix2): Matrix2
---@operator mul(number): Matrix2
---@operator mul(Matrix2): Matrix2
Matrix2 = {}

---@overload fun(self: Matrix2, matrix: Matrix2): Matrix2
---@overload fun(matrix: Matrix2): Matrix2
---@overload fun(self: Matrix2, v00: number, v01: number, v02: number, v10: number, v11: number, v12: number, v20: number, v21: number, v22: number): Matrix2
---@overload fun(v00: number, v01: number, v02: number, v10: number, v11: number, v12: number, v20: number, v21: number, v22: number): Matrix2
---@return Matrix2
function Matrix2.new() end

---@param scale Vector2
---@return nil
function Matrix2:SetScale(scale) end

---@param scale number
---@return nil
function Matrix2:SetScale(scale) end

---@return Vector2
function Matrix2:Scale() end

---@return Matrix2
function Matrix2:Transpose() end

---@param scale Vector2
---@return Matrix2
function Matrix2:Scaled(scale) end

---@param rhs Matrix2
---@return boolean
function Matrix2:Equals(rhs) end

---@return Matrix2
function Matrix2:Inverse() end

---@return string
function Matrix2:ToString() end

