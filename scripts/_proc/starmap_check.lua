-- 天赋星图布局验证:直接调 TalentStarMap.draw 渲染一张,看节点是五角星还是矩形网格
local StarMap = require "ui.church.talent.TalentStarMap"

local W, H = 1400, 1000
local nvg = nil
local fontId = nil

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[starmap] ERROR: nvgCreate failed")
        return
    end
    fontId = nvgCreateFont(nvg, "cn", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    StarMap.init(nvg)
    StarMap.setZoom(1.0)  -- 最小缩放：全貌
    print("[starmap] ready, font=" .. tostring(fontId))
    SubscribeToEvent(nvg, "NanoVGRender", "OnRender")
end

function OnRender()
    nvgBeginFrame(nvg, W, H, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, W, H)
    nvgFillColor(nvg, nvgRGBA(24, 20, 32, 255))
    nvgFill(nvg)
    StarMap.draw(nvg, 0, 0, W, H)
    nvgEndFrame(nvg)
end
