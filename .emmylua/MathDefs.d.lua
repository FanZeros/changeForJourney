---@meta

--- Auto-generated from Math/MathDefs

---@alias Intersection
---| integer # Intersection enum values

---@type Intersection
OUTSIDE = 0
---@type Intersection
INTERSECTS = 1
---@type Intersection
INSIDE = 2

-- Global functions
---@param lhs number
---@param rhs number
---@return boolean
function Equals(lhs, rhs) end

---@param value number
---@return boolean
function IsNaN(value) end

---@param lhs number
---@param rhs number
---@param t number
---@return number
function Lerp(lhs, rhs, t) end

---@param lhs number
---@param rhs number
---@param x number
---@return number
function InverseLerp(lhs, rhs, x) end

---@param lhs number
---@param rhs number
---@return number
function Min(lhs, rhs) end

---@param lhs number
---@param rhs number
---@return number
function Max(lhs, rhs) end

---@param value number
---@return number
function Abs(value) end

---@param value number
---@return number
function Sign(value) end

---@param value number
---@param min number
---@param max number
---@return number
function Clamp(value, min, max) end

---@param lhs number
---@param rhs number
---@param t number
---@return number
function SmoothStep(lhs, rhs, t) end

---@param angle number
---@return number
function Sin(angle) end

---@param angle number
---@return number
function Cos(angle) end

---@param angle number
---@return number
function Tan(angle) end

---@param x number
---@return number
function Asin(x) end

---@param x number
---@return number
function Acos(x) end

---@param x number
---@return number
function Atan(x) end

---@param y number
---@param x number
---@return number
function Atan2(y, x) end

---@param x number
---@return number
function Sqrt(x) end

---@param x number
---@param y number
---@return number
function Pow(x, y) end

---@param x number
---@return number
function Ln(x) end

---@param x number
---@param y number
---@return number
function Mod(x, y) end

---@param x number
---@return number
function Fract(x) end

---@param x number
---@return number
function Floor(x) end

---@param x number
---@return number
function Round(x) end

---@param x number
---@return number
function Ceil(x) end

---@param x number
---@return integer
function FloorToInt(x) end

---@param x number
---@return integer
function RoundToInt(x) end

---@param x number
---@return integer
function CeilToInt(x) end

---@param lhs integer
---@param rhs integer
---@return integer
function MinInt(lhs, rhs) end

---@param lhs integer
---@param rhs integer
---@return integer
function MaxInt(lhs, rhs) end

---@param value integer
---@return integer
function AbsInt(value) end

---@param value integer
---@param min integer
---@param max integer
---@return integer
function ClampInt(value, min, max) end

---@param value integer
---@return boolean
function IsPowerOfTwo(value) end

---@param value integer
---@return integer
function NextPowerOfTwo(value) end

---@param value integer
---@return integer
function CountSetBits(value) end

---@param value integer
---@return integer
function LogBaseTwo(value) end

---@param hash integer
---@param c number -- unsigned char
---@return integer
function SDBMHash(hash, c) end

---@return number
function Random() end

---@param range number
---@return number
function Random(range) end

---@param min number
---@param max number
---@return number
function Random(min, max) end

---@param range integer
---@return integer
function RandomInt(range) end

---@param min integer
---@param max integer
---@return integer
function RandomInt(min, max) end

---@param meanValue number
---@param variance number
---@return number
function RandomNormal(meanValue, variance) end

-- Global variables
---@type number
M_PI = nil
---@type number
M_HALF_PI = nil
---@type integer
M_MIN_INT = nil
---@type integer
M_MAX_INT = nil
---@type integer
M_MIN_UNSIGNED = nil
---@type integer
M_MAX_UNSIGNED = nil
---@type number
M_EPSILON = nil
---@type number
M_LARGE_EPSILON = nil
---@type number
M_MIN_NEARCLIP = nil
---@type number
M_MAX_FOV = nil
---@type number
M_LARGE_VALUE = nil
---@type number
M_INFINITY = nil
---@type number
M_DEGTORAD = nil
---@type number
M_DEGTORAD_2 = nil
---@type number
M_RADTODEG = nil
