-- 实装验收:直接读取实装后的游戏资产路径,模拟卡牌与对话立绘两种游戏内显示
local IDS = { 9, 11, 21 }
local NAMES = { [9] = "卡皮巴拉", [11] = "熬夜冠军", [21] = "闪电卖鸡" }

local W, H = 1400, 1100
local nvg = nil
local fontId = nil
local cardImgs, portImgs = {}, {}

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[implcheck] ERROR: nvgCreate failed")
        return
    end
    fontId = nvgCreateFont(nvg, "cn", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    if fontId == -1 or fontId == nil then
        print("[implcheck] ERROR: font load failed")
        return
    end
    for _, id in ipairs(IDS) do
        local cp = string.format("image/角色卡牌/KP_YX_%d.png", id)
        local pp = string.format("image/角色立绘/UI_DLH_%d.png", id)
        cardImgs[id] = nvgCreateImage(nvg, cp, 0)
        portImgs[id] = nvgCreateImage(nvg, pp, 0)
        print(string.format("[implcheck] %d card=%s portrait=%s", id,
            tostring(cardImgs[id]), tostring(portImgs[id])))
    end
    SubscribeToEvent(nvg, "NanoVGRender", "HandleRender")
    print("[implcheck] ready")
end

-- 把图片按 contain 缩放绘制在 (cx 中心, cy 顶) 区域内
local function drawContain(img, x, y, w, h)
    local iw, ih = nvgImageSize(nvg, img)
    if not iw or iw <= 0 then return end
    local s = math.min(w / iw, h / ih)
    local dw, dh = iw * s, ih * s
    local ox = x + (w - dw) * 0.5
    local oy = y + (h - dh) * 0.5
    local paint = nvgImagePattern(nvg, ox, oy, dw, dh, 0, img, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, ox, oy, dw, dh)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

-- 立绘按 cover 裁切绘制(模拟对话立绘的显示方式,底部对齐)
local function drawCoverBottom(img, x, y, w, h)
    local iw, ih = nvgImageSize(nvg, img)
    if not iw or iw <= 0 then return end
    local s = math.max(w / iw, h / ih)
    local dw, dh = iw * s, ih * s
    local ox = x + (w - dw) * 0.5
    local oy = y + h - dh
    local paint = nvgImagePattern(nvg, ox, oy, dw, dh, 0, img, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, w, h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

---@param eventType string
---@param eventData any
function HandleRender(eventType, eventData)
    local graphics = GetGraphics()
    if not graphics then return end
    local width = graphics:GetWidth()
    local height = graphics:GetHeight()

    nvgBeginFrame(nvg, width, height, 1.0)

    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, width, height)
    nvgFillColor(nvg, nvgRGBA(24, 24, 44, 255))
    nvgFill(nvg)

    nvgFontFaceId(nvg, fontId)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 38)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, W * 0.5, 60, "实装验收 · 已替换 KP_YX 卡面 + UI_DLH 立绘", nil)
    nvgFontSize(nvg, 20)
    nvgFillColor(nvg, nvgRGBA(160, 160, 190, 255))
    nvgText(nvg, W * 0.5, 105, "左:游戏卡牌显示场景(KP_YX) · 右:剧情对话立绘显示场景(UI_DLH)", nil)

    local slotW = 400
    local x0 = (W - 3 * slotW) * 0.5 + 20

    for i, id in ipairs(IDS) do
        local bx = x0 + (i - 1) * slotW
        -- 卡牌场景
        if cardImgs[id] and cardImgs[id] >= 0 then
            drawContain(cardImgs[id], bx, 150, 180, 400)
        end
        -- 对话立绘场景(右半身,底部对齐,底部对话框)
        local px = bx + 190
        nvgBeginPath(nvg)
        nvgRect(nvg, px, 150, 200, 400)
        nvgFillColor(nvg, nvgRGBA(34, 34, 58, 255))
        nvgFill(nvg)
        if portImgs[id] and portImgs[id] >= 0 then
            nvgBeginPath(nvg)
            nvgRect(nvg, px, 150, 200, 400)
            nvgFillColor(nvg, nvgRGBA(34, 34, 58, 255))
            nvgFill(nvg)
            drawCoverBottom(portImgs[id], px, 150, 200, 400)
        end
        -- 对话框
        nvgBeginPath(nvg)
        nvgRect(nvg, px, 470, 200, 80)
        nvgFillColor(nvg, nvgRGBA(12, 12, 24, 230))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, px, 470)
        nvgLineTo(nvg, px + 200, 470)
        nvgStrokeColor(nvg, nvgRGBA(120, 120, 200, 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
        nvgFontSize(nvg, 24)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 237, 0, 255))
        nvgText(nvg, px + 14, 500, NAMES[id], nil)
        nvgFontSize(nvg, 16)
        nvgFillColor(nvg, nvgRGBA(200, 200, 220, 255))
        nvgText(nvg, px + 14, 530, "叮咚!新立绘实装成功~", nil)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 角色名标签
        nvgFontSize(nvg, 22)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgText(nvg, bx + 90, 600, "#" .. id .. " " .. NAMES[id], nil)
    end

    nvgEndFrame(nvg)
end
