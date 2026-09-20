-- ============================================================================
-- render_awaken.lua — 离屏渲染觉醒面板，验证影画切片布局
-- 用法: UrhoXRuntime _proc/render_awaken.lua -tapcode_dir=<项目根> -tool_mode
--       -graphicssurfaceless -screenshot=<path> -screenshot-frame=120 -x 540 -y 1200
-- ============================================================================

local nvg = nil

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[awaken] ERROR: nvgCreate failed")
        return
    end
    nvgCreateFont(nvg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")

    local panel = require("ui.AwakeningPanel")
    panel.initImages(nvg)
    panel.setClassIcons({})
    -- 模拟：1 阶已嵌合，2 阶可嵌合（碎片足够），3 阶未解锁
    panel.setOwnedDataGetter(function(_heroId)
        return { shards = 130, awakening = { [1] = true, [2] = false, [3] = false } }
    end)
    panel.reset(1)

    SubscribeToEvent(nvg, "NanoVGRender", "HandleRender")
    print("[awaken] ready")
end

---@param eventType string
---@param eventData any
function HandleRender(eventType, eventData)
    local graphics = GetGraphics()
    if not graphics then return end
    local width = graphics:GetWidth()
    local height = graphics:GetHeight()

    nvgBeginFrame(nvg, width, height, 1.0)

    -- 设计空间 1080x2400 等比适配
    local scale = math.min(width / 1080, height / 2400)
    nvgSave(nvg)
    nvgScale(nvg, scale, scale)
    nvgTranslate(nvg, (width / scale - 1080) * 0.5, (height / scale - 2400) * 0.5)

    local ok, err = pcall(function()
        require("ui.AwakeningPanel").draw(nvg, 1)
    end)
    if not ok then
        print("[awaken] draw ERROR: " .. tostring(err))
    end

    nvgRestore(nvg)
    nvgEndFrame(nvg)
end
