---@meta

--- Auto-generated from UI/NanoVGTypes

---@class NVGcolor
---@field r number Red component (0.0-1.0)
---@field g number Green component (0.0-1.0)
---@field b number Blue component (0.0-1.0)
---@field a number Alpha component (0.0-1.0)
NVGcolor = {}


---@class NVGpaint
---@field xform number[] Transform matrix (6 floats)
---@field extent number[] Extent (2 floats: width, height)
---@field radius number Radius
---@field feather number Feather
---@field innerColor NVGcolor Inner color (for image pattern: tints the image via multiply in shader)
---@field outerColor NVGcolor Outer color
---@field image integer Image handle
NVGpaint = {}


---@class NVGglyphPosition
---@field str string Character position in string
---@field x number X position of the glyph
---@field minx number Left bound of the glyph
---@field maxx number Right bound of the glyph
NVGglyphPosition = {}


---@class NVGtextRow
---@field start string Start of the row
---@field end string End of the row
---@field next string Next row start
---@field width number Logical width of the row
---@field minx number Actual left bound of the row
---@field maxx number Actual right bound of the row
NVGtextRow = {}


-- Global functions
--- Create color from RGB values (0-255). Alpha will be set to 255.
---@param r number -- unsigned char
---@param g number -- unsigned char
---@param b number -- unsigned char
---@return NVGcolor
function nvgRGB(r, g, b) end

--- Create color from RGB float values (0.0-1.0). Alpha will be set to 1.0.
---@param r number
---@param g number
---@param b number
---@return NVGcolor
function nvgRGBf(r, g, b) end

--- Create color from RGBA values (0-255).
---@param r number -- unsigned char
---@param g number -- unsigned char
---@param b number -- unsigned char
---@param a number -- unsigned char
---@return NVGcolor
function nvgRGBA(r, g, b, a) end

--- Create color from RGBA float values (0.0-1.0).
---@param r number
---@param g number
---@param b number
---@param a number
---@return NVGcolor
function nvgRGBAf(r, g, b, a) end

--- Linearly interpolate from color c0 to c1.
---@param c0 NVGcolor
---@param c1 NVGcolor
---@param u number
---@return NVGcolor
function nvgLerpRGBA(c0, c1, u) end

--- Set transparency of a color (0-255).
---@param c0 NVGcolor
---@param a number -- unsigned char
---@return NVGcolor
function nvgTransRGBA(c0, a) end

--- Set transparency of a color (0.0-1.0).
---@param c0 NVGcolor
---@param a number
---@return NVGcolor
function nvgTransRGBAf(c0, a) end

--- Create color from HSL (0.0-1.0). Alpha will be set to 255.
---@param h number
---@param s number
---@param l number
---@return NVGcolor
function nvgHSL(h, s, l) end

--- Create color from HSLA. HSL in range [0.0-1.0], alpha in range [0-255].
---@param h number
---@param s number
---@param l number
---@param a number -- unsigned char
---@return NVGcolor
function nvgHSLA(h, s, l, a) end
