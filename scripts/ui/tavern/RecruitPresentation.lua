-- 招募专用分层图片与控件字幕；复用宿主NanoVG帧及1080×2400设计空间。
-- 不创建第二个绘图帧，不推进业务时间，不触发随机数或玩家数据更新。
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local Timeline = require("ui.tavern.RecruitTimeline")
local M = {}
local PATHS = {
    gate = "image/招募特效/gate_leaf.png",
    seal = "image/招募特效/seal.png",
    ring = "image/招募特效/rune_ring.png",
    back = "image/招募特效/card_back.png",
    rift = "image/招募特效/rift.png",
    halo = "image/招募特效/halo.png",
    spark = "image/招募特效/spark.png",
    shard = "image/招募特效/shard.png",
}
---@type table<any, table<string, number>>
local contexts = {}
---@type Widget?
local root = nil
---@type Label?
local title = nil
---@type Label?
local hint = nil
local phaseText = ""

local function rect(vg, x, y, w, h, color)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgFill(vg)
end

local function picture(vg, key, cx, cy, w, h, alpha, color, angle)
    if alpha <= 0.001 or w <= 0 or h <= 0 then return false end
    local context = contexts[vg]
    local handle = context and context[key] or -1
    if handle < 0 then return false end
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    if angle then nvgRotate(vg, angle) end
    local paint
    if color then
        paint = nvgImagePatternTinted(vg, -w/2, -h/2, w, h, 0, handle,
            nvgRGBA(color[1], color[2], color[3], math.floor(alpha * 255)))
    else
        paint = nvgImagePattern(vg, -w/2, -h/2, w, h, 0, handle, alpha)
    end
    nvgBeginPath(vg)
    nvgRect(vg, -w/2, -h/2, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
    return true
end

function M.init(vg)
    if not contexts[vg] then
        local images = {}
        contexts[vg] = images
        local loaded = 0
        for key, path in pairs(PATHS) do
            images[key] = -1
            local ok, handle = pcall(nvgCreateImage, vg, path, 0)
            if ok and type(handle) == "number" and handle >= 0 then
                images[key] = handle
                loaded = loaded + 1
            else
                print("[RecruitPresentation] 缺图使用几何兜底：" .. path)
            end
        end
        print("[RecruitPresentation] 图片预热=" .. loaded .. "/8")
    end
    if root then return end
    Surface.init()
    title = UI.Label { text = "", fontFamily = "sans", fontWeight = "normal",
        fontSize = 42, fontColor = { 236, 221, 188, 255 }, textAlign = "center",
        position = "absolute", top = 175, left = 60, width = 960, height = 75,
        pointerEvents = "none", flexShrink = 1 }
    hint = UI.Label { text = "", fontFamily = "sans", fontWeight = "normal",
        fontSize = 30, fontColor = { 205, 194, 174, 230 }, textAlign = "center",
        position = "absolute", bottom = 108, left = 40, width = 1000, height = 60,
        pointerEvents = "none", flexShrink = 1 }
    root = UI.Panel { width = 1080, height = 2400, pointerEvents = "none",
        children = { title, hint } }
end

-- 仅销毁本模块资源；普通关闭保留预热缓存，Stop才在VG销毁前释放。
function M.destroy()
    for vg, images in pairs(contexts) do
        for _, handle in pairs(images) do
            if handle >= 0 then pcall(nvgDeleteImage, vg, handle) end
        end
    end
    contexts = {}
    if root then root:Destroy() end
    root, title, hint = nil, nil, nil
    phaseText = ""
end

function M.drawIntro(vg, elapsed, quality)
    local pose = Timeline.intro(elapsed)
    local color = Timeline.color(quality)
    local cx, cy = 540, 1030
    nvgSave(vg)
    nvgGlobalAlpha(vg, pose.alpha)
    picture(vg, "halo", cx, cy, 940, 1180, pose.light * 0.70, color)
    picture(vg, "ring", cx, cy, 830, 830, 0.4 + pose.charge * 0.45, nil, pose.ringAngle)
    picture(vg, "rift", cx, cy, 30 + 430 * pose.opening, 1100, pose.light)
    local gateW, gateH = 285 * (1 - pose.opening * 0.38), 900
    local offset = 142 + pose.opening * 300
    local left = picture(vg, "gate", cx - offset, cy, gateW, gateH, 1)
    -- 同一门扇镜像复用；设计坐标变换由宿主处理，此处不重复DPR缩放。
    nvgSave(vg)
    nvgTranslate(vg, cx * 2, 0)
    nvgScale(vg, -1, 1)
    local right = picture(vg, "gate", cx - offset, cy, gateW, gateH, 1)
    nvgRestore(vg)
    if not left or not right then
        rect(vg, cx - offset - gateW/2, cy - gateH/2, gateW, gateH, { 37, 30, 28 })
        rect(vg, cx + offset - gateW/2, cy - gateH/2, gateW, gateH, { 37, 30, 28 })
        rect(vg, cx - 4, cy - gateH/2, 8, gateH, { 225, 184, 110, 200 })
    end
    local sealSize = 260 * pose.sealScale
    if not picture(vg, "seal", cx, cy, sealSize, sealSize, pose.sealAlpha) then
        nvgBeginPath(vg); nvgCircle(vg, cx, cy, sealSize * 0.35)
        nvgFillColor(vg, nvgRGBA(151, 54, 40, math.floor(pose.sealAlpha * 255)))
        nvgFill(vg)
    end
    -- 固定解析轨迹，绝不消费抽奖或战斗共享RNG。
    for i = 1, 16 do
        local angle = i * 2.399963 + elapsed * 0.22
        local radius = 320 * (1 - pose.charge * 0.68) + pose.opening * 200
        local x, y = cx + math.cos(angle) * radius, cy + math.sin(angle) * radius * 1.15
        picture(vg, "spark", x, y, 13 + i % 3 * 4, 30, pose.light * 0.8, color, angle)
    end
    for i = 1, 6 do
        local angle = i * math.pi / 3
        local radius = 90 + pose.opening * 230
        picture(vg, "shard", cx + math.cos(angle) * radius, cy + math.sin(angle) * radius,
            25, 40, pose.opening * (1 - pose.opening), nil, angle + elapsed)
    end
    nvgRestore(vg)
end

function M.drawBack(vg, cx, cy, width, height, alpha)
    if picture(vg, "back", cx, cy, width, height, alpha) then return end
    rect(vg, cx - width/2, cy - height/2, width, height, { 36, 31, 28, math.floor(alpha * 255) })
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - width/2 + 4, cy - height/2 + 4, width - 8, height - 8, 8)
    nvgStrokeColor(vg, nvgRGBA(174, 130, 72, math.floor(alpha * 255)))
    nvgStrokeWidth(vg, 3); nvgStroke(vg)
end

function M.drawCardGlow(vg, cx, cy, width, height, quality, glow)
    if glow <= 0.001 then return end
    local color = Timeline.color(quality)
    picture(vg, "halo", cx, cy, width * 1.7, height * 1.35, glow * 0.6, color)
    picture(vg, "ring", cx, cy, width * 1.4, width * 1.4, glow * 0.5, color, glow * 0.25)
end

function M.drawLabels(vg, phase, ready, poolId, alpha)
    if not root or not title or not hint then return end
    local key = phase .. tostring(ready) .. tostring(poolId)
    if key ~= phaseText then
        phaseText = key
        title:SetText(phase == "intro" and (poolId == "stellar" and "星辰之门" or "契约之门") or "契约已现")
        hint:SetText(phase == "intro" and "点击跳过开门动画" or (ready and "点击空白处返回酒馆" or "点击立即揭晓全部"))
    end
    root:SetStyle({ opacity = alpha })
    Surface.draw(root, vg, 1080, 2400)
end

return M
