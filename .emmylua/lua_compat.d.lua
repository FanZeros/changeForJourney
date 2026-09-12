---@meta

-- Lua version API compatibility.

---@param x number
---@param y number
---@return number
function math.pow(x, y) end

---@param y number
---@param x? number
---@return number
function math.atan2(y, x) end

---@param x number
---@return number
function math.cosh(x) end

---@param x number
---@return number
function math.sinh(x) end

---@param x number
---@return number
function math.tanh(x) end

---@param x number
---@return number, integer
function math.frexp(x) end

---@param x number
---@param e integer
---@return number
function math.ldexp(x, e) end

---@param x number
---@return number
function math.log10(x) end
