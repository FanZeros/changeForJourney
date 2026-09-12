---@meta

--- Auto-generated from Urho2D/Drawable2D


---@class Drawable2D : Drawable
---@field layer integer
---@field orderInLayer integer
Drawable2D = {}

---@param layer integer
---@return nil
function Drawable2D:SetLayer(layer) end

---@param orderInLayer integer
---@return nil
function Drawable2D:SetOrderInLayer(orderInLayer) end

---@return integer
function Drawable2D:GetLayer() end

---@return integer
function Drawable2D:GetOrderInLayer() end


-- Global variables
---@type number
PIXEL_SIZE = nil
