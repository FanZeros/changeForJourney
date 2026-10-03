-- 设计坐标控件桥：复用宿主 NanoVG 帧，只渲染新 UI 组件子树。
-- 沿用 scaffold-2d 的 UI.Init → 构建树 → SetRoot；输入仍由既有模态宿主消费。
local UI = require("urhox-libs/UI")
local ImageCache = require("urhox-libs/UI/Core/ImageCache")

local Surface = {}
local initialized = false
---@type NVGContextWrapper?
local imageContext = nil

function Surface.init()
    if initialized then return end
    initialized = true
    UI.Init({
        theme = "default-dark",
        fonts = {
            { family = "sans", weights = { normal = "Fonts/NotoSansCJKkr-Bold.otf" } },
        },
        scale = UI.Scale.DEFAULT,
        autoEvents = false,
    })
    UI.SetRoot(UI.Panel { width = "100%", height = "100%", pointerEvents = "none" })
end

function Surface.shutdown()
    if not initialized then return end
    ImageCache.Clear()
    imageContext = nil
    UI.Shutdown()
    initialized = false
end

---@param root Widget
---@param vg NVGContextWrapper
---@param width number
---@param height number
function Surface.draw(root, vg, width, height)
    Surface.init()
    if not root or not vg or width <= 0 or height <= 0 then return end
    -- 图片句柄属于创建它的 NanoVG 上下文，不能用 UI 私有上下文的句柄在宿主绘制。
    if imageContext ~= vg then
        ImageCache.Clear()
        ImageCache.SetContext(vg)
        imageContext = vg
    end
    YGNodeCalculateLayout(root.node, width, height, YGDirectionLTR)
    UI.RenderWidgetSubtree(root, vg)
end

return Surface
