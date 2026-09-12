---@meta

--- Auto-generated from UI/Window

---@alias WindowDragMode
---| integer # WindowDragMode enum values

---@type WindowDragMode
DRAG_NONE = 0
---@type WindowDragMode
DRAG_MOVE = 1
---@type WindowDragMode
DRAG_RESIZE_TOPLEFT = 2
---@type WindowDragMode
DRAG_RESIZE_TOP = 3
---@type WindowDragMode
DRAG_RESIZE_TOPRIGHT = 4
---@type WindowDragMode
DRAG_RESIZE_RIGHT = 5
---@type WindowDragMode
DRAG_RESIZE_BOTTOMRIGHT = 6
---@type WindowDragMode
DRAG_RESIZE_BOTTOM = 7
---@type WindowDragMode
DRAG_RESIZE_BOTTOMLEFT = 8
---@type WindowDragMode
DRAG_RESIZE_LEFT = 9

---@class Window : BorderImage
---@overload fun(): Window
---@field movable boolean
---@field resizable boolean
---@field fixedWidthResizing boolean
---@field fixedHeightResizing boolean
---@field resizeBorder IntRect
---@field modal boolean
---@field modalShadeColor Color
---@field modalFrameColor Color
---@field modalFrameSize IntVector2
---@field modalAutoDismiss boolean
Window = {}

---@return Window
function Window.new() end

---@param enable boolean
---@return nil
function Window:SetMovable(enable) end

---@param enable boolean
---@return nil
function Window:SetResizable(enable) end

---@param enable boolean
---@return nil
function Window:SetFixedWidthResizing(enable) end

---@param enable boolean
---@return nil
function Window:SetFixedHeightResizing(enable) end

---@param rect IntRect
---@return nil
function Window:SetResizeBorder(rect) end

---@param modal boolean
---@return nil
function Window:SetModal(modal) end

---@param color Color
---@return nil
function Window:SetModalShadeColor(color) end

---@param color Color
---@return nil
function Window:SetModalFrameColor(color) end

---@param size IntVector2
---@return nil
function Window:SetModalFrameSize(size) end

---@param enable boolean
---@return nil
function Window:SetModalAutoDismiss(enable) end

---@return boolean
function Window:IsMovable() end

---@return boolean
function Window:IsResizable() end

---@return boolean
function Window:GetFixedWidthResizing() end

---@return boolean
function Window:GetFixedHeightResizing() end

---@return IntRect
function Window:GetResizeBorder() end

---@return boolean
function Window:IsModal() end

---@return Color
function Window:GetModalShadeColor() end

---@return Color
function Window:GetModalFrameColor() end

---@return IntVector2
function Window:GetModalFrameSize() end

---@return boolean
function Window:GetModalAutoDismiss() end

