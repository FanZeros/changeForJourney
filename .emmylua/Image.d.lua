---@meta

--- Auto-generated from Resource/Image

---@alias CompressedFormat
---| integer # CompressedFormat enum values

---@type CompressedFormat
CF_NONE = 0
---@type CompressedFormat
CF_RGBA = 1
---@type CompressedFormat
CF_DXT1 = 2
---@type CompressedFormat
CF_DXT3 = 3
---@type CompressedFormat
CF_DXT5 = 4
---@type CompressedFormat
CF_ETC1 = 5
---@type CompressedFormat
CF_PVRTC_RGB_2BPP = 6
---@type CompressedFormat
CF_PVRTC_RGBA_2BPP = 7
---@type CompressedFormat
CF_PVRTC_RGB_4BPP = 8
---@type CompressedFormat
CF_PVRTC_RGBA_4BPP = 9

---@class Image : Resource
---@overload fun(): Image
---@field width integer
---@field height integer
---@field depth integer
---@field components integer
---@field compressed boolean
---@field compressedFormat CompressedFormat
---@field numCompressedLevels integer
---@field cubemap boolean
---@field array boolean
---@field sRGB boolean
Image = {}

---@return Image
function Image.new() end

---@param width integer
---@param height integer
---@param components integer
---@return boolean
function Image:SetSize(width, height, components) end

---@param width integer
---@param height integer
---@param depth integer
---@param components integer
---@return boolean
function Image:SetSize(width, height, depth, components) end

---@param x integer
---@param y integer
---@param color Color
---@return nil
function Image:SetPixel(x, y, color) end

---@param x integer
---@param y integer
---@param z integer
---@param color Color
---@return nil
function Image:SetPixel(x, y, z, color) end

---@param x integer
---@param y integer
---@param uintColor integer
---@return nil
function Image:SetPixelInt(x, y, uintColor) end

---@param x integer
---@param y integer
---@param z integer
---@param uintColor integer
---@return nil
function Image:SetPixelInt(x, y, z, uintColor) end

---@param source Deserializer
---@return boolean
function Image:LoadColorLUT(source) end

---@param fileName string
---@return boolean
function Image:LoadColorLUT(fileName) end

---@return boolean
function Image:FlipHorizontal() end

---@return boolean
function Image:FlipVertical() end

---@param width integer
---@param height integer
---@return boolean
function Image:Resize(width, height) end

---@param color Color
---@return nil
function Image:Clear(color) end

---@param uintColor integer
---@return nil
function Image:ClearInt(uintColor) end

---@param fileName string
---@return boolean
function Image:SaveBMP(fileName) end

---@param fileName string
---@return boolean
function Image:SavePNG(fileName) end

---@param fileName string
---@return boolean
function Image:SaveTGA(fileName) end

---@param fileName string
---@param quality integer
---@return boolean
function Image:SaveJPG(fileName, quality) end

---@param fileName string
---@return boolean
function Image:SaveDDS(fileName) end

---@param fileName string
---@param compression? number
---@return boolean
function Image:SaveWEBP(fileName, compression) end

---@param x integer
---@param y integer
---@return Color
function Image:GetPixel(x, y) end

---@param x integer
---@param y integer
---@param z integer
---@return Color
function Image:GetPixel(x, y, z) end

---@param x integer
---@param y integer
---@return integer
function Image:GetPixelInt(x, y) end

---@param x integer
---@param y integer
---@param z integer
---@return integer
function Image:GetPixelInt(x, y, z) end

---@param x number
---@param y number
---@return Color
function Image:GetPixelBilinear(x, y) end

---@param x number
---@param y number
---@param z number
---@return Color
function Image:GetPixelTrilinear(x, y, z) end

---@return integer
function Image:GetWidth() end

---@return integer
function Image:GetHeight() end

---@return integer
function Image:GetDepth() end

---@return integer
function Image:GetComponents() end

---@return boolean
function Image:IsCompressed() end

---@return CompressedFormat
function Image:GetCompressedFormat() end

---@return integer
function Image:GetNumCompressedLevels() end

---@param rect IntRect
---@return Image
function Image:GetSubimage(rect) end

---@param image Image
---@param rect IntRect
---@return boolean
function Image:SetSubimage(image, rect) end

---@return boolean
function Image:IsCubemap() end

---@return boolean
function Image:IsArray() end

---@return boolean
function Image:IsSRGB() end

---@return boolean
function Image:HasAlphaChannel() end

