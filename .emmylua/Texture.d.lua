---@meta

--- Auto-generated from Graphics/Texture

---@class Texture : ResourceWithMetadata
---@field format integer
---@field compressed boolean
---@field levels integer
---@field width integer
---@field height integer
---@field components integer
---@field filterMode TextureFilterMode
---@field anisotropy integer
---@field borderColor Color
---@field sRGB boolean
---@field multiSample integer
---@field autoResolve boolean
---@field resolveDirty boolean
---@field levelsDirty boolean
---@field backupTexture Texture
---@field usage TextureUsage
Texture = {}

---@param levels integer
---@return nil
function Texture:SetNumLevels(levels) end

---@param filter TextureFilterMode
---@return nil
function Texture:SetFilterMode(filter) end

---@param coord TextureCoordinate
---@param address TextureAddressMode
---@return nil
function Texture:SetAddressMode(coord, address) end

---@param level integer
---@return nil
function Texture:SetAnisotropy(level) end

---@param color Color
---@return nil
function Texture:SetBorderColor(color) end

---@param enable boolean
---@return nil
function Texture:SetSRGB(enable) end

---@param texture Texture
---@return nil
function Texture:SetBackupTexture(texture) end

---@param quality MaterialQuality
---@param toSkip integer
---@return nil
function Texture:SetMipsToSkip(quality, toSkip) end

---@return integer
function Texture:GetFormat() end

---@return boolean
function Texture:IsCompressed() end

---@return integer
function Texture:GetLevels() end

---@return integer
function Texture:GetWidth() end

---@return integer
function Texture:GetHeight() end

---@return TextureFilterMode
function Texture:GetFilterMode() end

---@param coord TextureCoordinate
---@return TextureAddressMode
function Texture:GetAddressMode(coord) end

---@return integer
function Texture:GetAnisotropy() end

---@return Color
function Texture:GetBorderColor() end

---@return boolean
function Texture:GetSRGB() end

---@return integer
function Texture:GetMultiSample() end

---@return boolean
function Texture:GetAutoResolve() end

---@return boolean
function Texture:IsResolveDirty() end

---@return boolean
function Texture:GetLevelsDirty() end

---@return Texture
function Texture:GetBackupTexture() end

---@param quality MaterialQuality
---@return integer
function Texture:GetMipsToSkip(quality) end

---@param level integer
---@return integer
function Texture:GetLevelWidth(level) end

---@param level integer
---@return integer
function Texture:GetLevelHeight(level) end

---@return TextureUsage
function Texture:GetUsage() end

---@param width integer
---@param height integer
---@return integer
function Texture:GetDataSize(width, height) end

---@param width integer
---@return integer
function Texture:GetRowDataSize(width) end

---@return integer
function Texture:GetComponents() end

