---@meta

--- Auto-generated from Graphics/Viewport

---@class Viewport
---@overload fun(scene: Scene, camera: Camera, renderPath?: RenderPath): Viewport
---@overload fun(scene: Scene, camera: Camera, rect: IntRect, renderPath?: RenderPath): Viewport
---@overload fun(): Viewport
---@field scene Scene
---@field camera Camera
---@field cullCamera Camera
---@field rect IntRect
---@field renderPath RenderPath
---@field drawDebug boolean
Viewport = {}

---@overload fun(self: Viewport, scene: Scene, camera: Camera, renderPath?: RenderPath): Viewport
---@overload fun(scene: Scene, camera: Camera, renderPath?: RenderPath): Viewport
---@overload fun(self: Viewport, scene: Scene, camera: Camera, rect: IntRect, renderPath?: RenderPath): Viewport
---@overload fun(scene: Scene, camera: Camera, rect: IntRect, renderPath?: RenderPath): Viewport
---@return Viewport
function Viewport.new() end

---@param scene Scene
---@return nil
function Viewport:SetScene(scene) end

---@param camera Camera
---@return nil
function Viewport:SetCamera(camera) end

---@param camera Camera
---@return nil
function Viewport:SetCullCamera(camera) end

---@param rect IntRect
---@return nil
function Viewport:SetRect(rect) end

---@param path RenderPath
---@return nil
function Viewport:SetRenderPath(path) end

---@param file XMLFile
---@return nil
function Viewport:SetRenderPath(file) end

---@param enable boolean
---@return nil
function Viewport:SetDrawDebug(enable) end

---@param enable boolean
---@return nil
function Viewport:SetViewClusterEnabled(enable) end

---@return boolean
function Viewport:IsViewClusterEnabled() end

---@return Scene
function Viewport:GetScene() end

---@return Camera
function Viewport:GetCamera() end

---@return Camera
function Viewport:GetCullCamera() end

---@return IntRect
function Viewport:GetRect() end

---@return RenderPath
function Viewport:GetRenderPath() end

---@return boolean
function Viewport:GetDrawDebug() end

---@param x integer
---@param y integer
---@return Ray
function Viewport:GetScreenRay(x, y) end

---@param worldPos Vector3
---@return IntVector2
function Viewport:WorldToScreenPoint(worldPos) end

---@param x integer
---@param y integer
---@param depth number
---@return Vector3
function Viewport:ScreenToWorldPoint(x, y, depth) end

---@param targetName string
---@param callback fun(success: boolean, image: Image):nil Data-ready callback; image is valid only during callback, nil on failure
---@return nil
function Viewport:CaptureRenderTarget(targetName, callback) end

