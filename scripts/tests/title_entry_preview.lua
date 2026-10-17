-- scaffold-2d 生命周期的受控开场验收：只绘制真实标题，不启动玩家档或游戏服务。
-- -entry-time=1.35 固定入场时间；-entry-exit=0.275 固定点击后的过渡时间。
local Title = require("ui.story.gate.DarkTitleScreenGate")
---@type NVGContextWrapper?
local vg = nil
local elapsed, exitElapsed = 1.35, -1
local frames = 0

function Start()
    for _, arg in ipairs(GetArguments()) do
        local value = arg:match("^%-entry%-time=(.+)$")
        if value then elapsed = math.max(0, tonumber(value) or 0) end
        value = arg:match("^%-entry%-exit=(.+)$")
        if value then exitElapsed = math.max(0, tonumber(value) or 0) end
    end
    vg = assert(nvgCreate(1))
    assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0)
    Title.init(vg)
    Title.open()
    Title.setReady(true)
    Title.update(elapsed)
    if exitElapsed >= 0 then
        Title.handleTap()
        Title.update(exitElapsed)
    end
    SubscribeToEvent(vg, "NanoVGRender", "HandleEntryPreview")
    print("[entry-preview] initialized time=" .. elapsed .. " exit=" .. exitElapsed)
end

function HandleEntryPreview()
    local ctx = vg
    if not ctx then return end
    local dpr = graphics:GetDPR()
    local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(ctx, w, h, dpr)
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(14, 17, 22, 255))
    nvgFill(ctx)
    Title.draw(ctx, w, h)
    nvgEndFrame(ctx)
    frames = frames + 1
    if frames == 120 then print("[entry-preview] CONTROLLED FRAME READY") end
end

function Stop()
    if vg then nvgDelete(vg); vg = nil end
end
