---@meta

--- Auto-generated from Graphics/Paintable

---@alias PaintBlendMode
---| integer # PaintBlendMode enum values

---@type PaintBlendMode
PAINT_BLEND_REPLACE = 0
---@type PaintBlendMode
PAINT_BLEND_ADD = 1
---@type PaintBlendMode
PAINT_BLEND_ERASE = 2

---@class PaintBrush
---@overload fun(): PaintBrush
---@field radiusUV number
---@field radiusWorld number
---@field strength number
---@field paintColor Color
---@field colorOpacity number
---@field metallic number
---@field roughness number
---@field metallicOpacity number
---@field roughnessOpacity number
---@field blendMode PaintBlendMode
PaintBrush = {}

---@return PaintBrush
function PaintBrush.new() end


---@class PaintRaycastHit
---@overload fun(): PaintRaycastHit
---@field hit boolean
---@field position Vector3
---@field normal Vector3
---@field uv Vector2
---@field barycentric Vector3
---@field distance number
---@field geometryIndex integer
---@field primitiveIndex integer
---@field paintSurfaceIndex integer
PaintRaycastHit = {}

---@return PaintRaycastHit
function PaintRaycastHit.new() end


---@class Paintable : Component
---@field paintResolution integer
---@field targetDrawable Drawable
Paintable = {}

---@param resolution integer
---@return nil
function Paintable:SetPaintResolution(resolution) end

---@return integer
function Paintable:GetPaintResolution() end

---@return Drawable
function Paintable:GetTargetDrawable() end

---@param paintSurfaceIndex? integer
---@return Texture2DArray
function Paintable:GetPaintMap(paintSurfaceIndex) end

---@param worldRay Ray
---@param maxDistance? number
---@return PaintRaycastHit
function Paintable:RaycastUV(worldRay, maxDistance) end

---@param paintSurfaceIndex integer
---@param uv Vector2
---@param brush PaintBrush
---@return boolean
function Paintable:PaintAtUV(paintSurfaceIndex, uv, brush) end

---@param worldRay Ray
---@param brush PaintBrush
---@param maxDistance? number
---@return boolean
function Paintable:PaintAtRay(worldRay, brush, maxDistance) end

---@param paintSurfaceIndex? integer
---@return boolean
function Paintable:ClearPaint(paintSurfaceIndex) end

---@return boolean
function Paintable:CommitDirtyPaintMaps() end

