-- ============================================================================
-- verify_offline_panel.lua — 离线收益弹窗验证（headless 截图）
-- 验证点：弹窗在设计稿内居中、无全屏黑遮罩、队员升级列表（进度条+经验数字）
-- 跑法:
--   LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe EGL_PLATFORM=surfaceless \
--   ./.cli/UrhoXRuntime _proc/verify_offline_panel.lua -tapcode_dir=/workspace -tool_mode \
--     -graphicssurfaceless -screenshot=/abs/xxx.png -screenshot-frame=150 -x 1080 -y 2400
-- ============================================================================

-- 窗口尺寸：与实机横屏三栏一致（1920x1080），弹窗走窗口居中 letterbox
local W, H = 1920, 1080
local DW, DH = 1080, 2400  -- 竖版设计稿

local nvg = nil
local panel = nil
local frames = 0

--- 世界背景：每 120px 一条亮色带，用来一眼看出弹窗外面没有被压暗
local function drawBackdrop(n)
    for i = 0, math.floor(H / 120) do
        local y = i * 120
        local c = (i % 2 == 0) and 200 or 120
        nvgBeginPath(n)
        nvgRect(n, 0, y, W, 120)
        nvgFillColor(n, nvgRGBA(c, math.floor(c * 0.8), math.floor(c * 0.6), 255))
        nvgFill(n)
    end
    nvgFontFace(n, "sans")
    nvgFontSize(n, 56)
    nvgTextAlign(n, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(n, nvgRGBA(20, 20, 20, 255))
    nvgText(n, W * 0.5, 40, "背景（不应变暗）", nil)
end

--- 用固定步长推进动画到指定秒数，便于截取确定的动画阶段
local simTime = 0
local function advanceTo(target)
    while simTime < target do
        panel.update(1 / 60)
        simTime = simTime + 1 / 60
    end
end

--- 由外部 -validate-test 或环境变量指定的目标动画秒数（默认 6s，已播完全部动画）
local TARGET = tonumber(os.getenv("VR_AT")) or 6.0

function onRender()
    frames = frames + 1
    advanceTo(TARGET)

    nvgBeginFrame(nvg, W, H, 1.0)
    drawBackdrop(nvg)
    -- 与 StandaloneHorizon 三行路径一致的窗口居中 letterbox
    local fit = math.min(W / DW, H / DH)
    nvgSave(nvg)
    nvgScissor(nvg, 0, 0, W, H)
    nvgTranslate(nvg, (W - DW * fit) * 0.5, (H - DH * fit) * 0.5)
    nvgScale(nvg, fit, fit)
    panel.draw(nvg)
    nvgRestore(nvg)
    nvgEndFrame(nvg)

    if frames == 1 or frames % 30 == 0 then
        print(string.format("[verify_offline] frame=%d elapsed=%.3f", frames, time.elapsedTime))
    end
end

function Start()
    print("[verify_offline] start")
    nvg = nvgCreate(1)
    if not nvg then
        print("[verify_offline] ERROR nvgCreate failed")
        return
    end
    nvgCreateFont(nvg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")

    local ImageCache = require("ui.widget.ImageCache")
    ImageCache.init(nvg)
    panel = require("ui.hud.popup.OfflineRewardPanel")
    panel.init(nvg)

    local mockRewards = {}
    local mockTemplates = { "W1", "W2", "W3", "O1", "A1", "A2", "X1", "X2" }
    for i = 1, 12 do
        mockRewards[i] = {
            type       = "equip",
            templateId = mockTemplates[((i - 1) % #mockTemplates) + 1],
            quality    = ((i - 1) % 5) + 1,
            level      = 10 + i,
            count      = (i <= 8) and 1 or (i * 2),
        }
    end
    mockRewards[#mockRewards + 1] = { type = "gold", amount = 61300 }
    mockRewards[#mockRewards + 1] = { type = "sweepTicket", amount = 2129 }

    -- 按 ExpTable 曲线生成，保证等级/经验/进度条自洽
    local ExpTable = require("config.ExpTable")
    local function mkPreview(heroId, name, quality, startLevel, startExp, expGain)
        local sim = ExpTable.simulateHeroExp(startLevel, startExp, expGain)
        return {
            heroId = heroId, name = name, quality = quality,
            startLevel = startLevel, startExp = startExp,
            level = sim.level, exp = sim.exp, maxExp = sim.maxExp,
            levelGain = sim.gain, expGain = expGain, capped = sim.capped,
        }
    end
    local mockHeroPreview = {
        mkPreview(1, "大狗嚼",     3, 1,  0, 900000),   -- 连升多级
        mkPreview(2, "黄桃龙",     3, 12, 40000, 260000),
        mkPreview(3, "叮咚鸡",     2, 20, 500, 30000),  -- 小幅升级
        mkPreview(4, "接化发掌门", 4, 30, 0, 5000),     -- 不够升级
    }

    panel.show({
        offlineSeconds = 8 * 3600 + 52 * 60 + 51,
        maxSeconds     = 24 * 3600,
        multiplier     = 1.0,
        adventureExp   = 85300,
        adventurerExp  = 170500,
        heroExpPreview = mockHeroPreview,
        rewards        = mockRewards,
        onClaim        = function() end,
    })
    print("[verify_offline] panel shown")

    SubscribeToEvent(nvg, "NanoVGRender", "onRender")
end
