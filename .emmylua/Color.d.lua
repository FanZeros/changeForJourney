---@meta

--- Auto-generated from Math/Color

---@class Color
---@overload fun(color: Color): Color
---@overload fun(color: Color, a: number): Color
---@overload fun(r: number, g: number, b: number): Color
---@overload fun(r: number, g: number, b: number, a: number): Color
---@overload fun(): Color
---@field r number
---@field g number
---@field b number
---@field a number
---@field sumRGB number
---@field average number
---@field luma number
---@field chroma number
---@field hue number
---@field saturationHSL number
---@field saturationHSV number
---@field value number
---@field lightness number
---@field maxRGB number
---@field minRGB number
---@field range number
---@field abs Color
---@field WHITE Color
---@field GRAY Color
---@field BLACK Color
---@field RED Color
---@field GREEN Color
---@field BLUE Color
---@field CYAN Color
---@field MAGENTA Color
---@field YELLOW Color
---@field TRANSPARENT_BLACK Color
---@operator eq(Color): boolean
---@operator mul(number): Color
---@operator add(Color): Color
---@operator unm: Color
---@operator sub(Color): Color
Color = {}

---@overload fun(self: Color, color: Color): Color
---@overload fun(color: Color): Color
---@overload fun(self: Color, color: Color, a: number): Color
---@overload fun(color: Color, a: number): Color
---@overload fun(self: Color, r: number, g: number, b: number): Color
---@overload fun(r: number, g: number, b: number): Color
---@overload fun(self: Color, r: number, g: number, b: number, a: number): Color
---@overload fun(r: number, g: number, b: number, a: number): Color
---@return Color
function Color.new() end

---@return integer
function Color:ToUInt() end

---@return Vector3
function Color:ToHSL() end

---@return Vector3
function Color:ToHSV() end

---@param color integer
---@return nil
function Color:FromUInt(color) end

---@param h number
---@param s number
---@param l number
---@param a number
---@return nil
function Color:FromHSL(h, s, l, a) end

---@param h number
---@param s number
---@param v number
---@param a number
---@return nil
function Color:FromHSV(h, s, v, a) end

---@return Vector3
function Color:ToVector3() end

---@return Vector4
function Color:ToVector4() end

---@return number
function Color:SumRGB() end

---@return number
function Color:Average() end

---@return number
function Color:Luma() end

---@return number
function Color:Chroma() end

---@return number
function Color:Hue() end

---@return number
function Color:SaturationHSL() end

---@return number
function Color:SaturationHSV() end

---@return number
function Color:Value() end

---@return number
function Color:Lightness() end

---@return number
function Color:MaxRGB() end

---@return number
function Color:MinRGB() end

---@return number
function Color:Range() end

---@param clipAlpha? boolean
---@return nil
function Color:Clip(clipAlpha) end

---@param invertAlpha? boolean
---@return nil
function Color:Invert(invertAlpha) end

---@param rhs Color
---@param t number
---@return Color
function Color:Lerp(rhs, t) end

---@return Color
function Color:Abs() end

---@param rhs Color
---@return boolean
function Color:Equals(rhs) end

---@return string
function Color:ToString() end

