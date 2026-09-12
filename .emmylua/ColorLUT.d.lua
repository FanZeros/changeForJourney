---@meta

--- Auto-generated from Resource/ColorLUT

---@alias ColorLUTFormat
---| integer # ColorLUTFormat enum values

---@type ColorLUTFormat
COLORLUT_TEXTURE3D = 0
---@type ColorLUTFormat
COLORLUT_TEXTURE2DSTRIP = 1

---@class ColorLUT : Resource
---@field texture3D Texture3D
---@field texture2DStrip Texture2D
---@field size integer
---@field format ColorLUTFormat
---@field title string
ColorLUT = {}

---@return Texture3D
function ColorLUT:GetTexture3D() end

---@return Texture2D
function ColorLUT:GetTexture2DStrip() end

---@return integer
function ColorLUT:GetSize() end

---@return ColorLUTFormat
function ColorLUT:GetFormat() end

---@return string
function ColorLUT:GetTitle() end

---@param input Color
---@return Color
function ColorLUT:SampleCPU(input) end

