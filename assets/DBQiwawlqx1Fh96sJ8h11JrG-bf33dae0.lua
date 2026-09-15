-- 角色卡实装预览:模拟游戏内卡牌样式展示 3 张双参考版玩梗立绘
-- 同时验证引擎对真 PNG 资源的直接读取
local CARDS = {
    { id = 9,  name = "卡皮巴拉",   orig = "芙罗拉",   title = "温泉教主", q = "SSR", qc = {255, 237, 0},
      img = "image/卡皮巴拉_立绘_双参考版_20260912113427.png" },
    { id = 11, name = "熬夜冠军",   orig = "素华",     title = "熬夜修仙党",   q = "SSR", qc = {255, 237, 0},
      img = "image/熬夜冠军_立绘_双参考版_20260912113554.png" },
    { id = 21, name = "闪电卖鸡",   orig = "亚历克斯", title = "赛道之王", q = "SSR", qc = {255, 237, 0},
      img = "image/闪电卖鸡_立绘_双参考版_20260912113646.png" },
}

local W, H = 1200, 1600
local CARD_W = 340
local IMG_H  = 620
local NAME_H = 150
local CARD_H = IMG_H + NAME_H
local GAP    = 60
local X0     = (W - 3 * CARD_W - 2 * GAP) * 0.5
local Y0     = 180

local nvg = nil
local fontId = nil
local imgs = {}

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[cardprev] ERROR: nvgCreate failed")
        return
    end
    fontId = nvgCreateFont(nvg, "cn", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    if fontId == -1 or fontId == nil then
        print("[cardprev] ERROR: font load failed")
        return
    end
    for i, c in ipairs(CARDS) do
        local h = nvgCreateImage(nvg, c.img, 0)
        imgs[i] = h
        print(string.format("[cardprev] %s -> %s", c.img, tostring(h)))
    end
    SubscribeToEvent(nvg, "NanoVGRender", "HandleRender")
    print("[cardprev] ready")
end

---@param eventType string
---@param eventData any
function HandleRender(eventType, eventData)
    local graphics = GetGraphics()
    if not graphics then return end
    local width = graphics:GetWidth()
    local height = graphics:GetHeight()

    nvgBeginFrame(nvg, width, height, 1.0)

    -- 深色游戏背景
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, width, height)
    nvgFillColor(nvg, nvgRGBA(24, 24, 44, 255))
    nvgFill(nvg)

    nvgFontFaceId(nvg, fontId)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 标题
    nvgFontSize(nvg, 40)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, W * 0.5, 80, "角色卡实装预览 · 玩梗立绘", nil)
    nvgFontSize(nvg, 22)
    nvgFillColor(nvg, nvgRGBA(160, 160, 190, 255))
    nvgText(nvg, W * 0.5, 128, "双参考版(卡面锁角色 + 基准图锁构图)", nil)

    for i, c in ipairs(CARDS) do
        local x = X0 + (i - 1) * (CARD_W + GAP)
        local y = Y0
        local img = imgs[i]

        -- 品质色外框
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - 5, y - 5, CARD_W + 10, CARD_H + 10, 14)
        nvgFillColor(nvg, nvgRGBA(c.qc[1], c.qc[2], c.qc[3], 255))
        nvgFill(nvg)

        -- 卡体底色
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, CARD_W, CARD_H, 10)
        nvgFillColor(nvg, nvgRGBA(40, 40, 66, 255))
        nvgFill(nvg)

        -- 立绘区(按高缩放填满,水平居中裁切;ImagePattern+圆角矩形填充自带裁切)
        if img and img >= 0 then
            local iw, ih = nvgImageSize(nvg, img)
            if iw and iw > 0 then
                local s = math.max(CARD_W / iw, IMG_H / ih)
                local dw, dh = iw * s, ih * s
                local ox = x + (CARD_W - dw) * 0.5
                local oy = y
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, x, y, CARD_W, IMG_H, 10)
                nvgFillColor(nvg, nvgRGBA(24, 24, 40, 255))
                nvgFill(nvg)
                local paint = nvgImagePattern(nvg, ox, oy, dw, dh, 0, img, 1.0)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, x, y, CARD_W, IMG_H, 10)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)
            end
        end

        -- 名牌区
        local ny = y + IMG_H
        nvgBeginPath(nvg)
        nvgRect(nvg, x + 1, ny, CARD_W - 2, NAME_H)
        nvgFillColor(nvg, nvgRGBA(28, 28, 50, 255))
        nvgFill(nvg)

        -- 品质角标
        nvgFontSize(nvg, 24)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(c.qc[1], c.qc[2], c.qc[3], 255))
        nvgText(nvg, x + 18, ny + 30, c.q, nil)

        -- 玩梗名
        nvgFontSize(nvg, 34)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgText(nvg, x + 75, ny + 30, c.name, nil)

        -- 原名·称号
        nvgFontSize(nvg, 20)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(160, 160, 190, 255))
        nvgText(nvg, x + CARD_W * 0.5, ny + 80, "原名" .. c.orig .. " · " .. c.title, nil)
        nvgFontSize(nvg, 18)
        nvgFillColor(nvg, nvgRGBA(120, 200, 120, 255))
        nvgText(nvg, x + CARD_W * 0.5, ny + 115, "玩梗立绘 · 双参考版", nil)
    end

    nvgEndFrame(nvg)
end
