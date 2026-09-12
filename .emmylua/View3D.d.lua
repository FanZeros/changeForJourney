---@meta

--- Auto-generated from UI/View3D

---@class View3D : Window
---@overload fun(): View3D
---@field format integer
---@field autoUpdate boolean
View3D = {}

---@return View3D
function View3D.new() end

---@param scene Scene
---@param camera Camera
---@param ownScene? boolean
---@return nil
function View3D:SetView(scene, camera, ownScene) end

---@param format integer
---@return nil
function View3D:SetFormat(format) end

---@param enable boolean
---@return nil
function View3D:SetAutoUpdate(enable) end

---@return nil
function View3D:QueueUpdate() end

---@return integer
function View3D:GetFormat() end

---@return boolean
function View3D:GetAutoUpdate() end

---@return Scene
function View3D:GetScene() end

---@return Node
function View3D:GetCameraNode() end

---@return Texture2D
function View3D:GetRenderTexture() end

---@return Texture2D
function View3D:GetDepthTexture() end

---@return Viewport
function View3D:GetViewport() end

