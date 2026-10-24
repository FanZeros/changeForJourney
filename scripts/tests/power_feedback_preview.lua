-- scaffold-2d生命周期：真实EventBus/Power/UI/Surface/Spine受控采样，不运行main、不读写玩家档。
-- -power-sample=0.65 控制解遮挡后时间；-power-block=5.7 模拟升级弹窗；-power-lang=en选择语言。
local Surface = require("ui.widget.DesignWidgetSurface")
local UI = require("urhox-libs/UI")
local I18n = require("core.I18n")
local Events = require("config.GameEvents")
local sprites = require("ui.fx.DarkEffectSprites")
local nativeCache, nativeRequire = cache, require
---@type NVGContextWrapper?
local vg = nil
local power, bus = {}, {}
local sample, blockedTime, language = .65, 5.7, "zh_CN"
local clock = { elapsedTime = 100 }
local frames = 0
local headers = {}
---@type Panel?
local legend = nil
local function source(path)
    local file = assert(nativeCache:GetFile(path))
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
function Start()
    for _, arg in ipairs(GetArguments()) do
        local value = arg:match("^%-power%-sample=(.+)$")
        if value then sample = tonumber(value); assert(finite(sample) and sample >= 0 and sample <= 10) end
        value = arg:match("^%-power%-block=(.+)$")
        if value then blockedTime = tonumber(value); assert(finite(blockedTime) and blockedTime >= 0 and blockedTime <= 60) end
        value = arg:match("^%-power%-lang=(.+)$")
        if value then language = value end
    end
    assert(I18n.set(language) or I18n.get() == language)
    vg = assert(nvgCreate(1))
    assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0)
    Surface.init()
    local env = setmetatable({ time = clock }, { __index = _G })
    env._G = env
    bus = assert(load(source("core/EventBus.lua"), "@power-preview/EventBus", "t", env))()
    env.require = function(name)
        if name == "core.EventBus" then return bus end
        return nativeRequire(name)
    end
    power = assert(load(source("ui/fx/SpinePowerUpEffect.lua"), "@power-preview/Power", "t", env))()
    power.init()
    power.preload(vg)
    bus.emit(Events.TEAM_POWER_CHANGED, { powers = { 10000, 20000, 30000 }, ready = true })
    clock.elapsedTime = 103
    power.setPresentationBlocked(true)
    bus.emit(Events.TEAM_POWER_CHANGED, { powers = { 12345, 20890, 30000 }, cause = "equipment_equip", ready = true })
    clock.elapsedTime = clock.elapsedTime + blockedTime
    power.update(0)
    assert(power.isPlaying(), "被弹窗挡住时不能丢失合法装备增益")
    power.setPresentationBlocked(false)
    clock.elapsedTime = clock.elapsedTime + sample
    power.update(0)
    local rows = power.getDisplayRows()
    if sample < 3.2 then
        assert(#rows == 2 and rows[1].base == 10000 and rows[1].power == 12345 and rows[1].delta == 2345)
        assert(rows[2].base == 20000 and rows[2].power == 20890 and rows[2].delta == 890)
        if sample >= 1.4 then
            assert(rows[1].displayPower == 12345 and rows[2].displayPower == 20890)
        end
    end
    headers = { "真实换装战力反馈 · 被升级弹窗遮挡后继续播放", "actual equipment gain | blocker " .. blockedTime .. "s | sample " .. sample .. "s | " .. language }
    legend = UI.Panel { width = "100%", height = 84, padding = 14, pointerEvents = "none",
        alignItems = "center", children = {
            UI.Label { text = language == "zh_CN" and headers[1] or "Equipment power gain after blocked overlay", fontFamily = "sans", fontSize = 19,
                fontColor = { 218, 199, 150, 255 }, pointerEvents = "none" },
            UI.Label { text = headers[2], fontFamily = "sans", fontSize = 14,
                fontColor = { 166, 157, 136, 255 }, pointerEvents = "none" },
        } }
    SubscribeToEvent(vg, "NanoVGRender", "HandlePowerFeedbackPreview")
    print("[power-feedback-preview] 初始化完成：sample=" .. sample .. " blocker=" .. blockedTime)
end
function HandlePowerFeedbackPreview()
    local ctx = vg
    if not ctx then return end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(ctx, width, height, dpr)
    nvgBeginPath(ctx); nvgRect(ctx, 0, 0, width, height)
    nvgFillColor(ctx, nvgRGBA(14, 12, 10, 255)); nvgFill(ctx)
    power.draw(ctx, width, height)
    if legend then Surface.draw(legend, ctx, width, 84) end
    nvgEndFrame(ctx)
    frames = frames + 1
    if frames == 120 then
        print("[power-feedback-preview] ALL PASS rows=" .. #power.getDisplayRows()
            .. " sample=" .. sample .. " blocker=" .. blockedTime .. " drawing=" .. tostring(power.isPlaying()))
    end
end
function Stop()
    if power.destroy then power.destroy() end
    if legend then legend:Destroy(); legend = nil end
    sprites.destroy()
    Surface.shutdown()
    if vg then nvgDelete(vg); vg = nil end
end
