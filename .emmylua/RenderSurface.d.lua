---@meta

--- Auto-generated from Graphics/RenderSurface

---@class RenderSurface
---@overload fun(parentTexture: Texture): RenderSurface
---@overload fun(): RenderSurface
---@field parentTexture Texture
---@field width integer
---@field height integer
---@field usage TextureUsage
---@field numViewports integer
---@field updateMode RenderSurfaceUpdateMode
---@field linkedRenderTarget RenderSurface
---@field linkedDepthStencil RenderSurface
---@field resolveDirty boolean
RenderSurface = {}

---@overload fun(self: RenderSurface, parentTexture: Texture): RenderSurface
---@overload fun(parentTexture: Texture): RenderSurface
---@return RenderSurface
function RenderSurface.new() end

---@param num integer
---@return nil
function RenderSurface:SetNumViewports(num) end

---@param index integer
---@param viewport Viewport
---@return nil
function RenderSurface:SetViewport(index, viewport) end

---@param mode RenderSurfaceUpdateMode
---@return nil
function RenderSurface:SetUpdateMode(mode) end

---@param renderTarget RenderSurface
---@return nil
function RenderSurface:SetLinkedRenderTarget(renderTarget) end

---@param depthStencil RenderSurface
---@return nil
function RenderSurface:SetLinkedDepthStencil(depthStencil) end

---@return nil
function RenderSurface:QueueUpdate() end

---@return nil
function RenderSurface:Release() end

---@return Texture
function RenderSurface:GetParentTexture() end

---@return integer
function RenderSurface:GetWidth() end

---@return integer
function RenderSurface:GetHeight() end

---@return TextureUsage
function RenderSurface:GetUsage() end

---@return integer
function RenderSurface:GetNumViewports() end

---@param index integer
---@return Viewport
function RenderSurface:GetViewport(index) end

---@return RenderSurfaceUpdateMode
function RenderSurface:GetUpdateMode() end

---@return RenderSurface
function RenderSurface:GetLinkedRenderTarget() end

---@return RenderSurface
function RenderSurface:GetLinkedDepthStencil() end

---@return boolean
function RenderSurface:IsResolveDirty() end

