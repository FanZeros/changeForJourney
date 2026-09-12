---@meta

--- Auto-generated from Urho2D/TileMapLayer2D

---@class TileMapLayer2D : Component
---@field drawOrder integer
---@field visible boolean
---@field layerType TileMapLayerType2D
---@field width integer
---@field height integer
---@field numObjects integer
---@field imageNode Node
TileMapLayer2D = {}

---@param drawOrder integer
---@return nil
function TileMapLayer2D:SetDrawOrder(drawOrder) end

---@param visible boolean
---@return nil
function TileMapLayer2D:SetVisible(visible) end

---@return integer
function TileMapLayer2D:GetDrawOrder() end

---@return boolean
function TileMapLayer2D:IsVisible() end

---@param name string
---@return boolean
function TileMapLayer2D:HasProperty(name) end

---@param name string
---@return string
function TileMapLayer2D:GetProperty(name) end

---@return TileMapLayerType2D
function TileMapLayer2D:GetLayerType() end

---@return integer
function TileMapLayer2D:GetWidth() end

---@return integer
function TileMapLayer2D:GetHeight() end

---@param x integer
---@param y integer
---@return Node
function TileMapLayer2D:GetTileNode(x, y) end

---@param x integer
---@param y integer
---@return Tile2D
function TileMapLayer2D:GetTile(x, y) end

---@return integer
function TileMapLayer2D:GetNumObjects() end

---@param index integer
---@return TileMapObject2D
function TileMapLayer2D:GetObject(index) end

---@param index integer
---@return Node
function TileMapLayer2D:GetObjectNode(index) end

---@return Node
function TileMapLayer2D:GetImageNode() end

