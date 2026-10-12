-- ============================================================================
-- HorizonBg - 横屏三联共享大背景
-- 左右侧面板各显示同一张大背景的一半（虚拟 2160x2400 画布 cover-crop），
-- 中间战斗面板保持自己的独立背景。视觉上左右构成同一个连续世界。
-- 用法:
--   HorizonBg.init(vg)                 -- Start 时调用一次（经全局去重包装加载）
--   HorizonBg.draw(vg, half, alpha)    -- half: 0=画布左半(左面板) 1=画布右半(右面板)
-- ============================================================================

local HorizonBg = {}

function HorizonBg.init(_vg)
end

--- 左右栏底色。可见画面由石框、关卡图和各页底板覆盖。
---@param vg any
---@param _half number 0=画布左半（左面板） 1=画布右半（右面板）
---@param alpha number 透明度 0-1
function HorizonBg.draw(vg, _half, alpha)
    local a = alpha or 1
    if a <= 0.01 then return end
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(14, 14, 22, math.floor(a * 255 + 0.5)))
    nvgFill(vg)
end

return HorizonBg
