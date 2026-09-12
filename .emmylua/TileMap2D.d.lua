---@meta

--- Auto-generated from Urho2D/TileMap2D

---@class TileMap2D : Component
---@field tmxFile TmxFile2D
---@field info TileMapInfo2D
---@field numLayers integer
TileMap2D = {}

---@param tmxFile TmxFile2D
---@return nil
function TileMap2D:SetTmxFile(tmxFile) end

---@return TmxFile2D
function TileMap2D:GetTmxFile() end

---@return TileMapInfo2D
function TileMap2D:GetInfo() end

---@return integer
function TileMap2D:GetNumLayers() end

---@param index integer
---@return TileMapLayer2D
function TileMap2D:GetLayer(index) end

---@param x integer
---@param y integer
---@return Vector2
function TileMap2D:TileIndexToPosition(x, y) end

---@param position Vector2
---@param x? integer
---@param y? integer
---@return boolean
function TileMap2D:PositionToTileIndex(position, x, y) end

