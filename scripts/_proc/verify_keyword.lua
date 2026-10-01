
-- ============================================================================
-- verify_keyword.lua — 关键词系统视觉验证（headless 截图）
-- 渲染：天赋描述富文本（关键词金色+下划线）+ 一个已打开的解释弹窗
-- 跑法: ./.cli/UrhoXRuntime scripts/_proc/verify_keyword.lua -tool_mode \
--   -graphicssurfaceless -screenshot=/workspace/.tmp-headless/verify_keyword.png \
--   -screenshot-frame=20 -x 1080 -y 700
-- ============================================================================

local KeywordText = require("ui.widget.KeywordText")

local nvg = nil
local vgOk = false
local kt = nil
local frame = 0

-- 回响客职业天赋（含「回响」x2 +「回响客」长词 +「仇恨」「封门人」）
local DESC = "普通攻击留下回响，1.2秒后造成原伤害45%的额外伤害（仅产生10%仇恨）；队伍中有封门人时，回响伤害+15%。"

function onRender(evt, data)
    if not vgOk then return end
    local W, H = 1080, 700
    nvgBeginFrame(nvg, W, H, 1.0)

    -- 深色背景
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, W, H)
    nvgFillColor(nvg, nvgRGBA(24, 19, 15, 255))
    nvgFill(nvg)

    -- 描述底板（模拟天赋区）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, 80, 80, 920, 180, 20)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 26))
    nvgFill(nvg)

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 40)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(0x66, 0xf8, 0x62, 255))
    nvgText(nvg, 113, 118, "回响：", nil)

    -- 关键词富文本
    kt:draw(nvg, DESC, 113, 150, 854, 34)

    -- 第 2 帧模拟点击第一个关键词，打开解释弹窗
    if frame == 2 then
        local spot = kt.hotspots[1]
        if spot then
            kt:handleInput((spot.x1 + spot.x2) * 0.5, (spot.y1 + spot.y2) * 0.5)
            print("[verify_keyword] opened popup for: " .. spot.name)
        end
    end
    kt:drawPopup(nvg)

    frame = frame + 1
    nvgEndFrame(nvg)

    -- Lua 主动截图（引擎 -screenshot 参数在本环境未生效）
    if frame == 4 then
        local img = Image()
        local okShot = graphics:TakeScreenShot(img)
        print("[verify_keyword] TakeScreenShot=" .. tostring(okShot)
            .. " size=" .. img.width .. "x" .. img.height)
        local paths = {
            "/workspace/.tmp-headless/verify_keyword.png",
            "verify_keyword.png",
        }
        for _, p in ipairs(paths) do
            local okSave = img:SavePNG(p)
            print("[verify_keyword] SavePNG(" .. p .. ")=" .. tostring(okSave))
            if okSave then break end
        end
    end
end

function Start()
    print("[verify_keyword] start")
    nvg = nvgCreate(1)
    if not nvg then
        print("[verify_keyword] ERROR nvgCreate failed")
        return
    end
    nvgCreateFont(nvg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    kt = KeywordText.new()
    vgOk = true
    print("[verify_keyword] nvg ready")
    SubscribeToEvent(nvg, "NanoVGRender", "onRender")
end
