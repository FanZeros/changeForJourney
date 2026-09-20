-- ============================================================================
-- verify_awakening.lua — 觉醒影画切片布局验证（headless 截图）
-- 状态: Ⅰ 已嵌合(原色) / Ⅱ 可嵌合(选中,灰度+青框) / Ⅲ 未解锁(灰度)
-- 跑法: ./.cli/UrhoXRuntime scripts/_proc/verify_awakening.lua -tool_mode \
--   -graphicssurfaceless -screenshot=/workspace/.tmp-headless/verify_awakening.png \
--   -screenshot-frame=40 -x 1080 -y 2400
-- ============================================================================

local AwakeningPanel = require("ui.AwakeningPanel")

local nvg = nil
local vgOk = false
local HERO_ID = 1

function onRender(evt, data)
    if not vgOk then return end
    local W, H = 1080, 2400
    nvgBeginFrame(nvg, W, H, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, W, H)
    nvgFillColor(nvg, nvgRGBA(12, 12, 18, 255))
    nvgFill(nvg)
    AwakeningPanel.draw(nvg, HERO_ID)
    nvgEndFrame(nvg)
end

function Start()
    print("[verify_awakening] start")
    nvg = nvgCreate(1)
    if not nvg then
        print("[verify_awakening] ERROR nvgCreate failed")
        return
    end
    nvgCreateFont(nvg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    AwakeningPanel.initImages(nvg)
    local icons = {}
    for i = 1, 6 do
        icons[i] = nvgCreateImage(nvg, "image/通用图标/ICON_ZY_" .. i .. ".png", 0)
    end
    AwakeningPanel.setClassIcons(icons)
    -- 模拟数据: Ⅰ已嵌合, 碎片 150（够 Ⅱ 的 90）
    AwakeningPanel.setOwnedDataGetter(function(hid)
        return { shards = 150, awakening = { [1] = true } }
    end)
    AwakeningPanel.reset(HERO_ID)
    vgOk = true
    print("[verify_awakening] nvg ready, panel reset hero=" .. HERO_ID)
    SubscribeToEvent(nvg, "NanoVGRender", "onRender")
end
