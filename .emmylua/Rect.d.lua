---@meta

--- Auto-generated from Math/Rect

---@class Rect
---@overload fun(rect: Rect): Rect
---@overload fun(min: Vector2, max: Vector2): Rect
---@overload fun(left: number, top: number, right: number, bottom: number): Rect
---@overload fun(vector: Vector4): Rect
---@overload fun(): Rect
---@field min Vector2
---@field max Vector2
---@field FULL Rect
---@field POSITIVE Rect
---@field ZERO Rect
---@field center Vector2
---@field size Vector2
---@field halfSize Vector2
---@operator eq(Rect): boolean
Rect = {}

---@overload fun(self: Rect, rect: Rect): Rect
---@overload fun(rect: Rect): Rect
---@overload fun(self: Rect, min: Vector2, max: Vector2): Rect
---@overload fun(min: Vector2, max: Vector2): Rect
---@overload fun(self: Rect, left: number, top: number, right: number, bottom: number): Rect
---@overload fun(left: number, top: number, right: number, bottom: number): Rect
---@overload fun(self: Rect, vector: Vector4): Rect
---@overload fun(vector: Vector4): Rect
---@return Rect
function Rect.new() end

---@param rect Rect
---@return nil
function Rect:Define(rect) end

---@param min Vector2
---@param max Vector2
---@return nil
function Rect:Define(min, max) end

---@param point Vector2
---@return nil
function Rect:Define(point) end

---@param point Vector2
---@return nil
function Rect:Merge(point) end

---@param rect Rect
---@return nil
function Rect:Merge(rect) end

---@return nil
function Rect:Clear() end

---@param rect Rect
---@return nil
function Rect:Clip(rect) end

---@return boolean
function Rect:Defined() end

---@return Vector2
function Rect:Center() end

---@return Vector2
function Rect:Size() end

---@return Vector2
function Rect:HalfSize() end

---@param rhs Rect
---@return boolean
function Rect:Equals(rhs) end

---@param point Vector2
---@return Intersection
function Rect:IsInside(point) end

---@param rect Rect
---@return Intersection
function Rect:IsInside(rect) end

---@return Vector4
function Rect:ToVector4() end

---@return string
function Rect:ToString() end


---@class IntRect
---@overload fun(left: integer, top: integer, right: integer, bottom: integer): IntRect
---@overload fun(min: IntVector2, max: IntVector2): IntRect
---@overload fun(): IntRect
---@field left integer
---@field top integer
---@field right integer
---@field bottom integer
---@field ZERO IntRect
---@field size IntVector2
---@field width integer
---@field height integer
---@operator eq(IntRect): boolean
IntRect = {}

---@overload fun(self: IntRect, left: integer, top: integer, right: integer, bottom: integer): IntRect
---@overload fun(left: integer, top: integer, right: integer, bottom: integer): IntRect
---@overload fun(self: IntRect, min: IntVector2, max: IntVector2): IntRect
---@overload fun(min: IntVector2, max: IntVector2): IntRect
---@return IntRect
function IntRect.new() end

---@return IntVector2
function IntRect:Size() end

---@return integer
function IntRect:Width() end

---@return integer
function IntRect:Height() end

---@param point IntVector2
---@return Intersection
function IntRect:IsInside(point) end

---@param rect IntRect
---@return nil
function IntRect:Clip(rect) end

---@param rect IntRect
---@return nil
function IntRect:Merge(rect) end

