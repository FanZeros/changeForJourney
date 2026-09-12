---@meta

--- Auto-generated from VoxelPhysics/VoxelModel

---@class VoxelModel : Resource
---@field dimensions IntVector3
---@field voxelCount integer
VoxelModel = {}

---@return IntVector3
function VoxelModel:GetDimensions() end

---@param x integer
---@param y integer
---@param z integer
---@return number
function VoxelModel:GetIndexAt(x, y, z) end

---@param index integer
---@return Color
function VoxelModel:GetPaletteColor(index) end

---@param index integer
---@return boolean
function VoxelModel:IsPaletteIndexUsed(index) end

---@return integer
function VoxelModel:GetVoxelCount() end

