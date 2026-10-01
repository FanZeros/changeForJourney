-- ============================================================================
-- verify_reward_popup.lua — 关卡奖励（首通）逐件弹出动画回归
-- 验证 RewardPopup 改用共用 RewardCascade 后行为不变
-- 跑法:
--   VR_AT=0.9 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe EGL_PLATFORM=surfaceless \
--   ./.cli/UrhoXRuntime _proc/verify_reward_popup.lua -tapcode_dir=/workspace -tool_mode \
--     -graphicssurfaceless -screenshot=/abs/x.png -screenshot-frame=8 -x 1920 -y 1080
-- ============================================================================

local W, H = 1920, 1080
local DW, DH = 1080, 2400

local nvg = nil
local popup = nil
local frames = 0
local simTime = 0

local function drawBackdrop(n)
    for i = 0, math.floor(H / 120) do
        local y = i * 120
        local c = (i % 2 == 0) and 200 or 120
        nvgBeginPath(n)
        nvgRect(n, 0, y, W, 120)
        nvgFillColor(n, nvgRGBA(c, math.floor(c * 0.8), math.floor(c * 0.6), 255))
        nvgFill(n)
    end
end

local TARGET = tonumber(os.getenv("VR_AT")) or 4.0

function onRender()
    frames = frames + 1
    while simTime < TARGET do
        popup.update(1 / 60)
        simTime = simTime + 1 / 60
    end

    nvgBeginFrame(nvg, W, H, 1.0)
    drawBackdrop(nvg)
    local fit = math.min(W / DW, H / DH)
    nvgSave(nvg)
    nvgScissor(nvg, 0, 0, W, H)
    nvgTranslate(nvg, (W - DW * fit) * 0.5, (H - DH * fit) * 0.5)
    nvgScale(nvg, fit, fit)
    popup.draw(nvg)
    nvgRestore(nvg)
    nvgEndFrame(nvg)

    if frames == 1 then
        print(string.format("[verify_reward] frame=1 elapsed=%.3f", time.elapsedTime))
    end
end

function Start()
    print("[verify_reward] start")
    nvg = nvgCreate(1)
    if not nvg then
        print("[verify_reward] ERROR nvgCreate failed")
        return
    end
    nvgCreateFont(nvg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")

    local ImageCache = require("ui.widget.ImageCache")
    ImageCache.init(nvg)
    popup = require("ui.hud.popup.RewardPopup")
    popup.init(nvg)

    local templates = { "W1", "W2", "W3", "O1", "A1", "A2", "X1", "X2" }
    local rewards = {}
    for i = 1, 12 do
        rewards[i] = {
            type       = "equip",
            templateId = templates[((i - 1) % #templates) + 1],
            quality    = ((i - 1) % 5) + 1,
            level      = 10 + i,
            count      = (i <= 8) and 1 or (i * 2),
        }
    end
    rewards[#rewards + 1] = { type = "gold", amount = 61300 }
    rewards[#rewards + 1] = { type = "sweepTicket", amount = 2129 }

    popup.show("首通奖励", rewards, {})
    print("[verify_reward] popup shown")

    SubscribeToEvent(nvg, "NanoVGRender", "onRender")
end
