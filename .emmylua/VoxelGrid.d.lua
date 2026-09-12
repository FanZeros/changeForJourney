---@meta

--- Auto-generated from VoxelPhysics/VoxelGrid

---@class VoxelGrid
---@field dimensions IntVector3
---@field solidCount integer
VoxelGrid = {}

---@param x integer
---@param y integer
---@param z integer
---@return boolean
function VoxelGrid:IsSolid(x, y, z) end

---@param x integer
---@param y integer
---@param z integer
---@param solid boolean
---@return nil
function VoxelGrid:SetSolid(x, y, z, solid) end

---@param x integer
---@param y integer
---@param z integer
---@return number
function VoxelGrid:GetVoxelMaterial(x, y, z) end

---@param x integer
---@param y integer
---@param z integer
---@param material number -- unsigned char
---@return nil
function VoxelGrid:SetVoxelMaterial(x, y, z, material) end

---@param x0 integer
---@param y0 integer
---@param z0 integer
---@param x1 integer
---@param y1 integer
---@param z1 integer
---@param material number -- unsigned char
---@return nil
function VoxelGrid:PaintBox(x0, y0, z0, x1, y1, z1, material) end

---@param x0 integer
---@param y0 integer
---@param z0 integer
---@param x1 integer
---@param y1 integer
---@param z1 integer
---@param solid boolean
---@return nil
function VoxelGrid:FillBox(x0, y0, z0, x1, y1, z1, solid) end

---@return nil
function VoxelGrid:Clear() end

---@param x integer
---@param y integer
---@param z integer
---@param face integer
---@return boolean
function VoxelGrid:IsFaceExposed(x, y, z, face) end

---@return IntVector3
function VoxelGrid:GetDimensions() end

---@return integer
function VoxelGrid:GetSolidCount() end

