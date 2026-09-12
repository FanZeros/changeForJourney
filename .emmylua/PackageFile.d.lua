---@meta

--- Auto-generated from IO/PackageFile

---@alias PackageIOMode
---| integer # PackageIOMode enum values

---@type PackageIOMode
PACKAGE_AUTO_CLOSE = 0
---@type PackageIOMode
PACKAGE_HOLDING = 1
---@type PackageIOMode
MAX_PACKAGE_IOMODE = 2

---@class PackageEntry
---@field offset integer
---@field size integer
---@field checksum integer
PackageEntry = {}


---@class PackageFile : Object
---@overload fun(fileName: string, mode?: PackageIOMode, startOffset?: integer): PackageFile
---@overload fun(): PackageFile
---@field name string
---@field nameHash StringHash|string
---@field numFiles integer
---@field totalSize integer
---@field totalDataSize integer
---@field checksum integer
---@field compressed boolean
PackageFile = {}

---@overload fun(self: PackageFile, fileName: string, mode?: PackageIOMode, startOffset?: integer): PackageFile
---@overload fun(fileName: string, mode?: PackageIOMode, startOffset?: integer): PackageFile
---@return PackageFile
function PackageFile.new() end

---@param fileName string
---@param mode? PackageIOMode
---@param startOffset? integer
---@return boolean
function PackageFile:Open(fileName, mode, startOffset) end

---@param fileName string
---@return boolean
function PackageFile:Exists(fileName) end

---@param fileName string
---@return PackageEntry
function PackageFile:GetEntry(fileName) end

---@return string
function PackageFile:GetName() end

---@return StringHash|string
function PackageFile:GetNameHash() end

---@return integer
function PackageFile:GetNumFiles() end

---@return integer
function PackageFile:GetTotalSize() end

---@return integer
function PackageFile:GetTotalDataSize() end

---@return integer
function PackageFile:GetChecksum() end

---@return boolean
function PackageFile:IsCompressed() end

