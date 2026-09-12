---@meta

--- Auto-generated from Core/Spline

---@alias InterpolationMode
---| integer # InterpolationMode enum values

---@type InterpolationMode
BEZIER_CURVE = 0
---@type InterpolationMode
CATMULL_ROM_CURVE = 1
---@type InterpolationMode
LINEAR_CURVE = 2
---@type InterpolationMode
CATMULL_ROM_FULL_CURVE = 3

---@class Spline
---@overload fun(mode: InterpolationMode): Spline
---@overload fun(rhs: Spline): Spline
---@overload fun(): Spline
---@field interpolationMode InterpolationMode
---@operator eq(Spline): boolean
Spline = {}

---@overload fun(self: Spline, mode: InterpolationMode): Spline
---@overload fun(mode: InterpolationMode): Spline
---@overload fun(self: Spline, rhs: Spline): Spline
---@overload fun(rhs: Spline): Spline
---@return Spline
function Spline.new() end

---@param f number
---@return Variant
function Spline:GetPoint(f) end

---@param index integer
---@return Variant
function Spline:GetKnot(index) end

---@param knot Variant
---@param param1 integer
---@return nil
function Spline:SetKnot(knot, param1) end

---@param knot Variant
---@return nil
function Spline:AddKnot(knot) end

---@param knot Variant
---@param index integer
---@return nil
function Spline:AddKnot(knot, index) end

---@return nil
function Spline:RemoveKnot() end

---@param index integer
---@return nil
function Spline:RemoveKnot(index) end

---@return nil
function Spline:Clear() end

