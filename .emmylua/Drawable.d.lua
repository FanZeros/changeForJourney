---@meta

--- Auto-generated from Graphics/Drawable

---@class Drawable : Component
---@field worldBoundingBox BoundingBox
---@field drawableFlags number -- unsigned char
---@field drawDistance number
---@field shadowDistance number
---@field lodBias number
---@field viewMask integer
---@field lightMask integer
---@field shadowMask integer
---@field zoneMask integer
---@field maxLights integer
---@field castShadows boolean
---@field outlineEnabled boolean
---@field outlineColor Color
---@field outlineThickness number
---@field outlineZBias number
---@field occluder boolean
---@field occludee boolean
---@field inView boolean
---@field zone Zone
Drawable = {}

---@param distance number
---@return nil
function Drawable:SetDrawDistance(distance) end

---@param distance number
---@return nil
function Drawable:SetShadowDistance(distance) end

---@param bias number
---@return nil
function Drawable:SetLodBias(bias) end

---@param mask integer
---@return nil
function Drawable:SetViewMask(mask) end

---@param mask integer
---@return nil
function Drawable:SetLightMask(mask) end

---@param mask integer
---@return nil
function Drawable:SetShadowMask(mask) end

---@param mask integer
---@return nil
function Drawable:SetZoneMask(mask) end

---@param num integer
---@return nil
function Drawable:SetMaxLights(num) end

---@param enable boolean
---@return nil
function Drawable:SetCastShadows(enable) end

---@param enable boolean
---@return nil
function Drawable:SetOutlineEnabled(enable) end

---@return boolean
function Drawable:GetOutlineEnabled() end

---@param color Color
---@return nil
function Drawable:SetOutlineColor(color) end

---@return Color
function Drawable:GetOutlineColor() end

---@param thickness number
---@return nil
function Drawable:SetOutlineThickness(thickness) end

---@return number
function Drawable:GetOutlineThickness() end

---@param zBias number
---@return nil
function Drawable:SetOutlineZBias(zBias) end

---@return number
function Drawable:GetOutlineZBias() end

---@param enable boolean
---@return nil
function Drawable:SetOccluder(enable) end

---@param enable boolean
---@return nil
function Drawable:SetOccludee(enable) end

---@return nil
function Drawable:MarkForUpdate() end

---@return BoundingBox
function Drawable:GetBoundingBox() end

---@return BoundingBox
function Drawable:GetWorldBoundingBox() end

---@return number
function Drawable:GetDrawableFlags() end

---@return number
function Drawable:GetDrawDistance() end

---@return number
function Drawable:GetShadowDistance() end

---@return number
function Drawable:GetLodBias() end

---@return integer
function Drawable:GetViewMask() end

---@return integer
function Drawable:GetLightMask() end

---@return integer
function Drawable:GetShadowMask() end

---@return integer
function Drawable:GetZoneMask() end

---@return integer
function Drawable:GetMaxLights() end

---@return boolean
function Drawable:GetCastShadows() end

---@return boolean
function Drawable:IsOccluder() end

---@return boolean
function Drawable:IsOccludee() end

---@return boolean
function Drawable:IsInView() end

---@param param0 Camera
---@return boolean
function Drawable:IsInView(param0) end

---@return Zone
function Drawable:GetZone() end


-- Global variables
---@type integer
DRAWABLE_GEOMETRY = nil
---@type integer
DRAWABLE_STATICMESH = nil
---@type integer
DRAWABLE_SKELETONMESH = nil
---@type integer
DRAWABLE_TERRAIN = nil
---@type integer
DRAWABLE_PARTICLE = nil
---@type integer
DRAWABLE_LIGHT = nil
---@type integer
DRAWABLE_ZONE = nil
---@type integer
DRAWABLE_GEOMETRY2D = nil
---@type integer
DRAWABLE_ANY = nil
---@type integer
DEFAULT_VIEWMASK = nil
---@type integer
DEFAULT_LIGHTMASK = nil
---@type integer
DEFAULT_SHADOWMASK = nil
---@type integer
DEFAULT_ZONEMASK = nil
---@type integer
MAX_VERTEX_LIGHTS = nil
---@type number
ANIMATION_LOD_BASESCALE = nil
