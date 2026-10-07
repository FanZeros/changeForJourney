-- 招募动画视觉验收：基于scaffold-2d生命周期与模式A设计缩放。
-- 只渲染固定展示回执，不加载main，不抽奖、不扣费、不读取玩家存档。
-- UrhoXRuntime _proc/verify_recruit_animation.lua -tapcode_dir=<项目> -tool_mode
-- -graphicssurfaceless -recruit-sample=0.9 -recruit-ten -screenshot=<绝对路径> -screenshot-frame=120
local RecruitAnim = require("ui.tavern.RecruitAnim")
---@type NVGContextWrapper?
local vg = nil
local sample, ten, stellar = 0.9, false, false
local frozenClock = { elapsedTime = 100 }
local previousTime = time

function Start()
    for _, arg in ipairs(GetArguments()) do
        local value = arg:match("^%-recruit%-sample=(.+)$")
        if value then sample = assert(tonumber(value), "sample必须为数值") end
        if arg == "-recruit-ten" then ten = true end
        if arg == "-recruit-stellar" then stellar = true end
    end
    assert(sample >= 0 and sample <= 20, "sample越界")
    vg = nvgCreate(1)
    assert(vg, "NanoVG创建失败")
    assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "字体加载失败")
    time = frozenClock
    RecruitAnim.init(vg)
    local results = { { type = "hero", heroId = 1, quality = 3 } }
    if ten then
        results = {
            { type = "hero", heroId = 1, quality = 3 },
            { type = "dupe_to_shard", heroId = 2, quality = 2, shardGain = 10 },
            { type = "hero", heroId = 3, quality = 2 },
            { type = "hero", heroId = 4, quality = 1 },
            { type = "hero", heroId = 5, quality = 1 },
            { type = "shard", heroId = 6, quality = 2, amount = 5 },
            { type = "shard", heroId = 7, quality = 1, amount = 2 },
            { type = "hero", heroId = 8, quality = 1 },
            { type = "hero", heroId = 9, quality = 2 },
            { type = "decompose", heroId = 10, quality = 1, tavernCoin = 10 },
        }
    end
    RecruitAnim.start(results, nil, ten and 10 or 1, stellar and "stellar" or "standard")
    frozenClock.elapsedTime = 100 + sample
    RecruitAnim.update(0)
    SubscribeToEvent("NanoVGRender", "HandleRecruitPreviewRender")
    print("[招募视觉] 固定展示 sample=" .. sample .. " ten=" .. tostring(ten))
end

function HandleRecruitPreviewRender()
    if not vg then return end
    local dpr = graphics:GetDPR()
    local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local fit = math.min(w / 1080, h / 2400)
    nvgBeginFrame(vg, w, h, dpr)
    nvgTranslate(vg, (w - 1080 * fit) / 2, (h - 2400 * fit) / 2)
    nvgScale(vg, fit, fit)
    RecruitAnim.draw(vg)
    nvgEndFrame(vg)
end

function Stop()
    RecruitAnim.destroy()
    require("ui.widget.DesignWidgetSurface").shutdown()
    time = previousTime
    if vg then nvgDelete(vg); vg = nil end
end
