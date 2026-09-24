-- 渲染 LetterIntro 信件预览(MODE: early=显墨中 / sealed=火漆印落定)
local LetterIntro = require("ui.story.LetterIntro")
local MODE = "sealed"
local nvg = nil
local frame = 0

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[letterprev] ERROR: nvgCreate failed")
        return
    end
    nvgCreateFont(nvg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    LetterIntro.init(nvg)
    LetterIntro.start(nil)
    SubscribeToEvent(nvg, "NanoVGRender", "HandleRender")
    print("[letterprev] mode=" .. MODE)
end

---@param eventType string
---@param eventData any
function HandleRender(eventType, eventData)
    local g = GetGraphics()
    if not g then return end
    frame = frame + 1
    nvgBeginFrame(nvg, 1920, 1080, 1.0)
    if MODE == "sealed" and frame <= 14 then
        LetterIntro.handleTap()   -- 快进:显完并翻段,14 次后进入 sealed
    end
    LetterIntro.update(1 / 30)
    ---@diagnostic disable-next-line: missing-parameter
    LetterIntro.draw(nvg, 1920, 1080)
    nvgEndFrame(nvg)
end
