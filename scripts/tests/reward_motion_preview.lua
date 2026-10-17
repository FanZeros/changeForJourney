-- scaffold-2d式独立视觉验收入口：不加载main，不读写玩家档，不抽卡/发奖。
-- -motion-scene=reward|large|recruit -motion-time=受控秒数；120帧后截图由Runtime执行。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local clock = { elapsedTime = 100 }
local sceneName, sampleTime = "reward", 0.24
for _, argument in ipairs(GetArguments()) do
    sceneName = argument:match("^%-motion%-scene=(.+)$") or sceneName
    sampleTime = tonumber(argument:match("^%-motion%-time=(.+)$")) or sampleTime
end
---@type NVGContextWrapper?
local vg = nil
---@type table
local presenter = {}
local originalClock = time
local sourceReceipt = {}
local rngCalls, ioCalls = 0, 0

function Start()
    -- 时钟是独立预览内存，不触及玩家业务。
    rawset(_G, "time", clock)
    vg = nvgCreate(1)
    assert(vg, "preview VG creation failed")
    assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "preview font")
    Surface.init()
    if sceneName == "recruit" then
        presenter = require("ui.tavern.RecruitAnim")
        sourceReceipt = {
            { type = "hero", heroId = 1, quality = 1 },
            { type = "hero", heroId = 10, quality = 2 },
            { type = "hero", heroId = 7, quality = 3 },
            { type = "dupe_to_shard", heroId = 16, quality = 4, shardGain = 10 },
            { type = "resource", resType = "gold", quality = 1, amount = 12500 },
            { type = "hero", heroId = 3, quality = 1 },
            { type = "hero", heroId = 21, quality = 2 },
            { type = "hero", heroId = 9, quality = 3 },
            { type = "shard", heroId = 11, quality = 2, amount = 10 },
            { type = "resource", resType = "diamond", quality = 3, amount = 180 },
        }
        presenter.init(vg)
        presenter.start(sourceReceipt, nil, 10, "standard")
        clock.elapsedTime = 100 + sampleTime
        presenter.update(0)
    else
        presenter = require("ui.hud.popup.RewardPopup")
        presenter.init(vg)
        sourceReceipt = { { type = "gold", amount = 12500 }, { type = "diamond", amount = 180 },
            { type = "equip", templateId = "W1", quality = 3, level = 30 },
            { type = "hero", heroId = 10, quality = 2, amount = 1 },
            { type = "shard", heroId = 11, quality = 2, amount = 10 } }
        if sceneName == "large" then
            sourceReceipt = {}
            for i = 1, 42 do sourceReceipt[i] = { type = "gold", amount = 1000 + i * 137 } end
        end
        presenter.show("获得奖励", sourceReceipt, { subtitle = "暗铁契约 · 战利品", cascade = true })
        clock.elapsedTime = 100 + sampleTime
        presenter.update(0)
    end
    -- 仅断开独立预览的玩家IO与RNG；引擎native截图/日志仍由Runtime落盘。
    math.random = function() rngCalls = rngCalls + 1; error("preview unexpected RNG") end
    math.randomseed = math.random
    File = function() ioCalls = ioCalls + 1; error("preview unexpected player IO") end
    GetFileSystem = File
    print("[reward_motion_preview] ready scene=" .. sceneName .. " controlledTime=" .. sampleTime
        .. " receipt=" .. #sourceReceipt .. " RNG/PlayerIO=" .. rngCalls .. "/" .. ioCalls)
    SubscribeToEvent(vg, "NanoVGRender", "HandleRewardMotionPreviewRender")
end

function HandleRewardMotionPreviewRender()
    if not vg then return end
    local width, height, dpr = graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()
    local logicalW, logicalH = width / dpr, height / dpr
    nvgBeginFrame(vg, logicalW, logicalH, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logicalW, logicalH)
    nvgFillColor(vg, nvgRGBA(14, 13, 16, 255)); nvgFill(vg)
    nvgSave(vg)
    if sceneName == "large" then
        presenter.drawLarge(vg, logicalW, logicalH)
    else
        -- 既有1080×2400设计空间；图片/文字由真实模块及Surface绘制，不加新raw HUD。
        local fit = math.min(logicalW / 1080, logicalH / 2400)
        nvgTranslate(vg, (logicalW - 1080 * fit) * .5, (logicalH - 2400 * fit) * .5)
        nvgScale(vg, fit, fit)
        presenter.draw(vg)
    end
    nvgRestore(vg)
    nvgEndFrame(vg)
end

function Stop()
    if sceneName == "recruit" and presenter.destroy then presenter.destroy() end
    Surface.shutdown()
    if vg then nvgDelete(vg); vg = nil end
    rawset(_G, "time", originalClock)
    print("[reward_motion_preview] stopped RNG/PlayerIO=" .. rngCalls .. "/" .. ioCalls)
end
