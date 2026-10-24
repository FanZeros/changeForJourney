-- 神器动画视觉验收：复用 verify_recruit_animation 与 scaffold-2d 生命周期。
-- 只展示固定回执，不加载 main，不访问玩家存档，不执行抽奖/扣费/发奖。
-- 使用真实渲染时传 -graphicssurfaceless；CPU headless 不代表像素验收。
-- -artifact-sample=0.9 -artifact-ten -artifact-advanced -artifact-language=en
local Anim = require("ui.church.ArtifactDrawAnim")
local ImageCache = require("ui.widget.ImageCache")
local I18n = require("core.I18n")
---@type NVGContextWrapper?
local vg = nil
local sample, ten, advanced, language = 0.9, false, false, "zh_CN"
local frozenClock = { elapsedTime = 100 }
local previousTime = time

function Start()
    local ok, err = pcall(function()
        for _, arg in ipairs(GetArguments()) do
            local value = arg:match("^%-artifact%-sample=(.+)$")
            if value then sample = assert(tonumber(value), "sample必须为数值") end
            local lang = arg:match("^%-artifact%-language=(.+)$")
            if lang then language = lang end
            if arg == "-artifact-ten" then ten = true end
            if arg == "-artifact-advanced" then advanced = true end
        end
        assert(sample >= 0 and sample <= 20, "sample越界")
        assert(I18n.set(language), "不支持该语言")
        vg = nvgCreate(1)
        assert(vg, "NanoVG创建失败")
        assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "字体加载失败")
        time = frozenClock
        ImageCache.init(vg)
        assert(Anim.init(vg), "动画初始化失败")
        local results = {
            { type = "artifact", id = "preview-1", artifactId = 2, quality = 5,
                value = 72, valueRatio = 4800, threatClearValue = 58, threatClearRatio = 5300 },
        }
        if ten then
            results = {
                { type = "artifact", id = "preview-1", artifactId = 1, quality = 1, value = 125, valueRatio = 5000 },
                { type = "artifact", id = "preview-2", artifactId = 2, quality = 2, value = 17, valueRatio = 5000, threatClearValue = 19, threatClearRatio = 5000 },
                { type = "artifact", id = "preview-3", artifactId = 3, quality = 3, value = 130, valueRatio = 5000 },
                { type = "artifact", id = "preview-4", artifactId = 4, quality = 1, value = 75, valueRatio = 5000 },
                { type = "artifact", id = "preview-5", artifactId = 5, quality = 4, value = 105, valueRatio = 5000 },
                { type = "artifact", id = "preview-6", artifactId = 7, quality = 1, value = 10, valueRatio = 5000 },
                { type = "artifact", id = "preview-7", artifactId = 11, quality = 2, value = 40, valueRatio = 5000 },
                { type = "artifact", id = "preview-8", artifactId = 14, quality = 5, value = 7, valueRatio = 5000 },
                { type = "artifact", id = "preview-9", artifactId = 15, quality = 3, value = 180, valueRatio = 5000 },
                { type = "artifact", id = "preview-10", artifactId = 16, quality = 4, value = 150, valueRatio = 5000 },
            }
        end
        local opts = {
            getCost = function()
                return { parts = { { type = "golden_key", amount = ten and 3 or 1 },
                    { type = "diamond", amount = ten and 1050 or 600 } }, enough = true }
            end,
            onContinue = function() return false end, -- 固定展示绝不发出真实请求。
        }
        assert(Anim.start(results, nil, ten and 10 or 1, advanced and "advanced" or "normal", opts), "动画启动失败")
        frozenClock.elapsedTime = 100 + sample
        Anim.update(0)
        SubscribeToEvent("NanoVGRender", "HandleArtifactPreviewRender")
        print("[神器视觉] 固定展示 sample=" .. sample .. " ten=" .. tostring(ten) .. " language=" .. language)
    end)
    if not ok then
        log:Write(LOG_ERROR, "[神器视觉] " .. tostring(err))
        engine:Exit()
    end
end

function HandleArtifactPreviewRender()
    if not vg then return end
    local dpr = graphics:GetDPR()
    local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local fit = math.min(w / 1080, h / 2400)
    nvgBeginFrame(vg, w, h, dpr)
    nvgTranslate(vg, (w - 1080 * fit) / 2, (h - 2400 * fit) / 2)
    nvgScale(vg, fit, fit)
    Anim.draw(vg)
    nvgEndFrame(vg)
end

function Stop()
    Anim.destroy()
    require("ui.widget.DesignWidgetSurface").shutdown()
    time = previousTime
    if vg then nvgDelete(vg); vg = nil end
end
