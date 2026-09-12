---@meta

--- Auto-generated from Graphics/Graphics

---@class Graphics : Object
---@field initialized boolean
---@field windowTitle string
---@field apiName string
---@field windowPosition IntVector2
---@field width integer
---@field height integer
---@field multiSample integer
---@field size IntVector2
---@field fullscreen boolean
---@field resizable boolean
---@field borderless boolean
---@field vSync boolean
---@field refreshRate integer
---@field monitor integer
---@field tripleBuffer boolean
---@field sRGB boolean
---@field dither boolean
---@field flushGPU boolean
---@field orientations string
---@field deviceLost boolean
---@field numPrimitives integer
---@field numBatches integer
---@field dummyColorFormat integer
---@field shadowMapFormat integer
---@field hiresShadowMapFormat integer
---@field instancingSupport boolean
---@field deferredSupport boolean
---@field hardwareShadowSupport boolean
---@field readableDepthSupport boolean
---@field sRGBSupport boolean
---@field sRGBWriteSupport boolean
---@field monitorCount integer
---@field shaderCacheDir string
---@field transparent boolean
---@field clickThrough boolean
---@field topmost boolean
---@field compositionBacked boolean
Graphics = {}

---@param windowTitle string
---@return nil
function Graphics:SetWindowTitle(windowTitle) end

---@param windowIcon Image
---@return nil
function Graphics:SetWindowIcon(windowIcon) end

---@param position IntVector2
---@return nil
function Graphics:SetWindowPosition(position) end

---@param x integer
---@param y integer
---@return nil
function Graphics:SetWindowPosition(x, y) end

---@param width integer
---@param height integer
---@param fullscreen boolean
---@param borderless boolean
---@param resizable boolean
---@param highDPI boolean
---@param vsync boolean
---@param tripleBuffer boolean
---@param multiSample integer
---@param monitor integer
---@param refreshRate integer
---@return boolean
function Graphics:SetMode(width, height, fullscreen, borderless, resizable, highDPI, vsync, tripleBuffer, multiSample, monitor, refreshRate) end

---@param width integer
---@param height integer
---@return boolean
function Graphics:SetMode(width, height) end

---@param enable boolean
---@return nil
function Graphics:SetTransparent(enable) end

---@param enable boolean
---@return nil
function Graphics:SetClickThrough(enable) end

---@param enable boolean
---@return nil
function Graphics:SetTopmost(enable) end

---@param enable boolean
---@return nil
function Graphics:SetSRGB(enable) end

---@param enable boolean
---@return nil
function Graphics:SetDither(enable) end

---@param enable boolean
---@return nil
function Graphics:SetFlushGPU(enable) end

---@param orientations string
---@return nil
function Graphics:SetOrientations(orientations) end

---@return boolean
function Graphics:ToggleFullscreen() end

---@return nil
function Graphics:Maximize() end

---@return nil
function Graphics:Minimize() end

---@return nil
function Graphics:Raise() end

---@return nil
function Graphics:Raise() end

---@return nil
function Graphics:Close() end

---@param destImage Image
---@return boolean
function Graphics:TakeScreenShot(destImage) end

---@param fileName string
---@return nil
function Graphics:BeginDumpShaders(fileName) end

---@return nil
function Graphics:EndDumpShaders() end

---@param source Deserializer
---@return nil
function Graphics:PrecacheShaders(source) end

---@param fileName string
---@return nil
function Graphics:PrecacheShaders(fileName) end

---@param path string
---@return nil
function Graphics:SetShaderCacheDir(path) end

---@return boolean
function Graphics:IsInitialized() end

---@return any
function Graphics:GetExternalWindow() end

---@return string
function Graphics:GetWindowTitle() end

---@return string
function Graphics:GetApiName() end

---@return IntVector2
function Graphics:GetWindowPosition() end

---@return integer
function Graphics:GetWidth() end

---@return integer
function Graphics:GetHeight() end

---@return number
function Graphics:GetDPR() end

---@return integer
function Graphics:GetMultiSample() end

---@return IntVector2
function Graphics:GetSize() end

---@return boolean
function Graphics:GetFullscreen() end

---@return boolean
function Graphics:GetResizable() end

---@return boolean
function Graphics:GetBorderless() end

---@return boolean
function Graphics:IsTransparent() end

---@return boolean
function Graphics:IsClickThrough() end

---@return boolean
function Graphics:IsTopmost() end

---@return boolean
function Graphics:IsCompositionBacked() end

---@param enable boolean
---@return nil
function Graphics:SetVSync(enable) end

---@return boolean
function Graphics:GetVSync() end

---@return integer
function Graphics:GetMonitor() end

---@return integer
function Graphics:GetRefreshRate() end

---@return boolean
function Graphics:GetTripleBuffer() end

---@return boolean
function Graphics:GetSRGB() end

---@return boolean
function Graphics:GetDither() end

---@return boolean
function Graphics:GetFlushGPU() end

---@return string
function Graphics:GetOrientations() end

---@return boolean
function Graphics:IsDeviceLost() end

---@return integer
function Graphics:GetNumPrimitives() end

---@return integer
function Graphics:GetNumBatches() end

---@return integer
function Graphics:GetDummyColorFormat() end

---@return integer
function Graphics:GetShadowMapFormat() end

---@return integer
function Graphics:GetHiresShadowMapFormat() end

---@return boolean
function Graphics:GetInstancingSupport() end

---@return boolean
function Graphics:GetDeferredSupport() end

---@return boolean
function Graphics:GetHardwareShadowSupport() end

---@return boolean
function Graphics:GetReadableDepthSupport() end

---@return boolean
function Graphics:GetSRGBSupport() end

---@return boolean
function Graphics:GetSRGBWriteSupport() end

---@return string
function Graphics:GetGpuTimingStatsString() end

---@param monitor integer
---@return IntVector2
function Graphics:GetDesktopResolution(monitor) end

---@return integer
function Graphics:GetMonitorCount() end

---@return string
function Graphics:GetShaderCacheDir() end

---@return integer
function Graphics:GetCurrentMonitor() end

---@return boolean
function Graphics:GetMaximized() end

---@param monitor? integer
---@return Vector3
function Graphics:GetDisplayDPI(monitor) end

---@return integer
function Graphics:GetAlphaFormat() end

---@return integer
function Graphics:GetLuminanceFormat() end

---@return integer
function Graphics:GetLuminanceAlphaFormat() end

---@return integer
function Graphics:GetRGBFormat() end

---@return integer
function Graphics:GetRGBAFormat() end

---@return integer
function Graphics:GetRGBA16Format() end

---@return integer
function Graphics:GetRGBAFloat16Format() end

---@return integer
function Graphics:GetRGBAFloat32Format() end

---@return integer
function Graphics:GetRG16Format() end

---@return integer
function Graphics:GetRGFloat16Format() end

---@return integer
function Graphics:GetRGFloat32Format() end

---@return integer
function Graphics:GetFloat16Format() end

---@return integer
function Graphics:GetFloat32Format() end

---@return integer
function Graphics:GetLinearDepthFormat() end

---@return integer
function Graphics:GetDepthStencilFormat() end

---@return integer
function Graphics:GetReadableDepthFormat() end

---@param formatName string
---@return integer
function Graphics:GetFormat(formatName) end

---@return integer
function Graphics:GetMaxBones() end


-- Global functions
---@return Graphics
function GetGraphics() end

-- Global variables
---@type Graphics
graphics = nil
