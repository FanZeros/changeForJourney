---@meta

--- Auto-generated from UI/UIComponent

---@class UIComponent : Component
---@overload fun(): UIComponent
---@field root UIElement
---@field material Material
---@field texture Texture2D
UIComponent = {}

---@return UIComponent
function UIComponent.new() end

---@return UIElement
function UIComponent:GetRoot() end

---@return Material
function UIComponent:GetMaterial() end

---@return Texture2D
function UIComponent:GetTexture() end

