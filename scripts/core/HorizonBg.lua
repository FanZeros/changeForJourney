-- ============================================================================
-- HorizonBg - 横屏三联共享大背景
-- 左右侧面板各显示同一张大背景的一半（虚拟 2160x2400 画布 cover-crop），
-- 中间战斗面板保持自己的独立背景。视觉上左右构成同一个连续世界。
-- 用法:
--   HorizonBg.init(vg)                 -- Start 时调用一次（经全局去重包装加载）
--   HorizonBg.draw(vg, half, alpha)    -- half: 0=画布左半(左面板) 1=画布右半(右面板)
-- ============================================================================

local HorizonBg = {}

local imgShared = -1
local IMG_PATH = "image/UI_CZ_BJ.png"  -- 城镇大背景（1080x2400）

function HorizonBg.init(vg)
    if imgShared < 0 then
        imgShared = nvgCreateImage(vg, IMG_PATH, 0)
    end
end

--- 绘制共享大背景的指定一半（须在面板设计空间内调用；首次调用自动加载）
---@param vg any
---@param half number 0=画布左半（左面板） 1=画布右半（右面板）
---@param alpha number 透明度 0-1
function HorizonBg.draw(vg, half, alpha)
    if imgShared < 0 then
        imgShared = nvgCreateImage(vg, IMG_PATH, 0)
    end
    local a = alpha or 1
    if a <= 0.01 then return end

    -- 虚拟连续画布 2160x2400，源图 cover-crop 填满（2x 放大，纵向取中段）
    local canvasW, canvasH = 2160, 2400
    local iw, ih = 1080, 2400
    local scale = math.max(canvasW / iw, canvasH / ih)
    local dw, dh = iw * scale, ih * scale
    local ox = (canvasW - dw) * 0.5 - half * 1080
    local oy = (canvasH - dh) * 0.5

    -- [P3-12a 回退] 城镇大背景用户已专门制作暗黑版，保持原样直绘
    local paint = nvgImagePattern(vg, ox, oy, dw, dh, 0, imgShared, math.floor(a * 255 + 0.5) / 255)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

return HorizonBg
