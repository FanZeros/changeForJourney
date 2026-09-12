---@meta

--- Auto-generated from UI/NanoVGEnums

---@alias NVGwinding
---| integer # NVGwinding enum values

---@type NVGwinding
NVG_CCW = 1
---@type NVGwinding
NVG_CW = 2

---@alias NVGsolidity
---| integer # NVGsolidity enum values

---@type NVGsolidity
NVG_SOLID = 1
---@type NVGsolidity
NVG_HOLE = 2

---@alias NVGlineCap
---| integer # NVGlineCap enum values

---@type NVGlineCap
NVG_BUTT = 0
---@type NVGlineCap
NVG_ROUND = 1
---@type NVGlineCap
NVG_SQUARE = 2
---@type NVGlineCap
NVG_BEVEL = 3
---@type NVGlineCap
NVG_MITER = 4

---@alias NVGalign
---| integer # NVGalign enum values

---@type NVGalign
NVG_ALIGN_LEFT = 1<<0
---@type NVGalign
NVG_ALIGN_CENTER = 1<<1
---@type NVGalign
NVG_ALIGN_RIGHT = 1<<2
---@type NVGalign
NVG_ALIGN_CENTER_VISUAL = 1<<7
---@type NVGalign
NVG_ALIGN_TOP = 1<<3
---@type NVGalign
NVG_ALIGN_MIDDLE = 1<<4
---@type NVGalign
NVG_ALIGN_BOTTOM = 1<<5
---@type NVGalign
NVG_ALIGN_BASELINE = 1<<6

---@alias NVGblendFactor
---| integer # NVGblendFactor enum values

---@type NVGblendFactor
NVG_ZERO = 1<<0
---@type NVGblendFactor
NVG_ONE = 1<<1
---@type NVGblendFactor
NVG_SRC_COLOR = 1<<2
---@type NVGblendFactor
NVG_ONE_MINUS_SRC_COLOR = 1<<3
---@type NVGblendFactor
NVG_DST_COLOR = 1<<4
---@type NVGblendFactor
NVG_ONE_MINUS_DST_COLOR = 1<<5
---@type NVGblendFactor
NVG_SRC_ALPHA = 1<<6
---@type NVGblendFactor
NVG_ONE_MINUS_SRC_ALPHA = 1<<7
---@type NVGblendFactor
NVG_DST_ALPHA = 1<<8
---@type NVGblendFactor
NVG_ONE_MINUS_DST_ALPHA = 1<<9
---@type NVGblendFactor
NVG_SRC_ALPHA_SATURATE = 1<<10

---@alias NVGcompositeOperation
---| integer # NVGcompositeOperation enum values

---@type NVGcompositeOperation
NVG_SOURCE_OVER = 0
---@type NVGcompositeOperation
NVG_SOURCE_IN = 1
---@type NVGcompositeOperation
NVG_SOURCE_OUT = 2
---@type NVGcompositeOperation
NVG_ATOP = 3
---@type NVGcompositeOperation
NVG_DESTINATION_OVER = 4
---@type NVGcompositeOperation
NVG_DESTINATION_IN = 5
---@type NVGcompositeOperation
NVG_DESTINATION_OUT = 6
---@type NVGcompositeOperation
NVG_DESTINATION_ATOP = 7
---@type NVGcompositeOperation
NVG_LIGHTER = 8
---@type NVGcompositeOperation
NVG_COPY = 9
---@type NVGcompositeOperation
NVG_XOR = 10

---@alias NVGimageFlags
---| integer # NVGimageFlags enum values

---@type NVGimageFlags
NVG_IMAGE_GENERATE_MIPMAPS = 1<<0
---@type NVGimageFlags
NVG_IMAGE_REPEATX = 1<<1
---@type NVGimageFlags
NVG_IMAGE_REPEATY = 1<<2
---@type NVGimageFlags
NVG_IMAGE_FLIPY = 1<<3
---@type NVGimageFlags
NVG_IMAGE_PREMULTIPLIED = 1<<4
---@type NVGimageFlags
NVG_IMAGE_NEAREST = 1<<5

---@alias NVGColorSpace
---| integer # NVGColorSpace enum values

---@type NVGColorSpace
NVG_COLOR_GAMMA = 0
---@type NVGColorSpace
NVG_COLOR_LINEAR = 1
