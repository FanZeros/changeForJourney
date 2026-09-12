---@meta

--- Auto-generated from UI/Cursor

---@alias CursorShape
---| integer # CursorShape enum values

---@type CursorShape
CS_NORMAL = 0
---@type CursorShape
CS_IBEAM = 1
---@type CursorShape
CS_CROSS = 2
---@type CursorShape
CS_RESIZEVERTICAL = 3
---@type CursorShape
CS_RESIZEDIAGONAL_TOPRIGHT = 4
---@type CursorShape
CS_RESIZEHORIZONTAL = 5
---@type CursorShape
CS_RESIZEDIAGONAL_TOPLEFT = 6
---@type CursorShape
CS_RESIZE_ALL = 7
---@type CursorShape
CS_ACCEPTDROP = 8
---@type CursorShape
CS_REJECTDROP = 9
---@type CursorShape
CS_BUSY = 10
---@type CursorShape
CS_BUSY_ARROW = 11
---@type CursorShape
CS_MAX_SHAPES = 12

---@class Cursor : BorderImage
---@overload fun(): Cursor
---@field shape string
---@field useSystemShapes boolean
Cursor = {}

---@return Cursor
function Cursor.new() end

---@param shape string
---@param image Image
---@param imageRect IntRect
---@param hotSpot IntVector2
---@return nil
function Cursor:DefineShape(shape, image, imageRect, hotSpot) end

---@param shape CursorShape
---@param image Image
---@param imageRect IntRect
---@param hotSpot IntVector2
---@return nil
function Cursor:DefineShape(shape, image, imageRect, hotSpot) end

---@param shape CursorShape
---@return nil
function Cursor:SetShape(shape) end

---@param shape string
---@return nil
function Cursor:SetShape(shape) end

---@param enable boolean
---@return nil
function Cursor:SetUseSystemShapes(enable) end

---@return string
function Cursor:GetShape() end

---@return boolean
function Cursor:GetUseSystemShapes() end

