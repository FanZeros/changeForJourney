---@meta

--- Auto-generated from Urho2D/TileMapDefs2D

---@alias Orientation2D
---| integer # Orientation2D enum values

---@type Orientation2D
O_ORTHOGONAL = 0
---@type Orientation2D
O_ISOMETRIC = 1
---@type Orientation2D
O_STAGGERED = 2
---@type Orientation2D
O_HEXAGONAL = 3

---@alias TileMapLayerType2D
---| integer # TileMapLayerType2D enum values

---@type TileMapLayerType2D
LT_TILE_LAYER = 0
---@type TileMapLayerType2D
LT_OBJECT_GROUP = 1
---@type TileMapLayerType2D
LT_IMAGE_LAYER = 2
---@type TileMapLayerType2D
LT_INVALID = 3

---@alias TileMapObjectType2D
---| integer # TileMapObjectType2D enum values

---@type TileMapObjectType2D
OT_RECTANGLE = 0
---@type TileMapObjectType2D
OT_ELLIPSE = 1
---@type TileMapObjectType2D
OT_POLYGON = 2
---@type TileMapObjectType2D
OT_POLYLINE = 3
---@type TileMapObjectType2D
OT_TILE = 4
---@type TileMapObjectType2D
OT_INVALID = 5

---@class TileMapInfo2D
---@field orientation Orientation2D
---@field width integer
---@field height integer
---@field tileWidth number
---@field tileHeight number
---@field mapWidth number
---@field mapHeight number
TileMapInfo2D = {}

---@return number
function TileMapInfo2D:GetMapWidth() end

---@return number
function TileMapInfo2D:GetMapHeight() end


---@class PropertySet2D
PropertySet2D = {}

---@param name string
---@return boolean
function PropertySet2D:HasProperty(name) end

---@param name string
---@return string
function PropertySet2D:GetProperty(name) end


---@class Tile2D
---@field gid integer
---@field sprite Sprite2D
Tile2D = {}

---@return integer
function Tile2D:GetGid() end

---@return boolean
function Tile2D:GetFlipX() end

---@return boolean
function Tile2D:GetFlipY() end

---@return boolean
function Tile2D:GetSwapXY() end

---@return Sprite2D
function Tile2D:GetSprite() end

---@param name string
---@return boolean
function Tile2D:HasProperty(name) end

---@param name string
---@return string
function Tile2D:GetProperty(name) end


---@class TileMapObject2D
---@field objectType TileMapObjectType2D
---@field name string
---@field type string
---@field position Vector2
---@field size Vector2
---@field numPoints integer
---@field tileGid integer
---@field tileSprite Sprite2D
TileMapObject2D = {}

---@return TileMapObjectType2D
function TileMapObject2D:GetObjectType() end

---@return string
function TileMapObject2D:GetName() end

---@return string
function TileMapObject2D:GetType() end

---@return Vector2
function TileMapObject2D:GetPosition() end

---@return Vector2
function TileMapObject2D:GetSize() end

---@return integer
function TileMapObject2D:GetNumPoints() end

---@param index integer
---@return Vector2
function TileMapObject2D:GetPoint(index) end

---@return integer
function TileMapObject2D:GetTileGid() end

---@return boolean
function TileMapObject2D:GetTileFlipX() end

---@return boolean
function TileMapObject2D:GetTileFlipY() end

---@return boolean
function TileMapObject2D:GetTileSwapXY() end

---@return Sprite2D
function TileMapObject2D:GetTileSprite() end

---@param name string
---@return boolean
function TileMapObject2D:HasProperty(name) end

---@param name string
---@return string
function TileMapObject2D:GetProperty(name) end


-- Global variables
---@type integer
FLIP_HORIZONTAL = nil
---@type integer
FLIP_VERTICAL = nil
---@type integer
FLIP_DIAGONAL = nil
---@type integer
FLIP_RESERVED = nil
---@type integer
FLIP_ALL = nil
