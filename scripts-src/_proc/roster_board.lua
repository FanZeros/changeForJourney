-- 离线渲染:20 角色卡牌总览板(玩梗规划版) → 截图输出
-- 运行: UrhoXRuntime _proc/roster_board.lua -tapcode_dir=... -tool_mode -graphicssurfaceless -screenshot=...

-- 数据: id, 玩梗名, 品质, 职业, 原名, 称号, 有立绘文件
local HEROES = {
    { id = 1,  meme = "大狗嚼",       q = "R",   qc = {160,160,160}, job = "战士", orig = "卡琳",     title = "汪卫先锋", art = true  },
    { id = 2,  meme = "黄桃龙",       q = "R",   qc = {160,160,160}, job = "法师", orig = "麦琪",     title = "火球一本龙", art = true  },
    { id = 3,  meme = "叮咚鸡",       q = "R",   qc = {160,160,160}, job = "游侠", orig = "琳达",     title = "等通知哨兵", art = true  },
    { id = 4,  meme = "接化发掌门",   q = "SR",  qc = {162,160,255}, job = "骑士", orig = "塞西莉亚", title = "浑元形意宗师", art = false },
    { id = 5,  meme = "叠甲怪",       q = "SR",  qc = {162,160,255}, job = "战士", orig = "维多利亚", title = "叠甲战神",   art = true  },
    { id = 6,  meme = "阿姨压",   q = "SR",  qc = {162,160,255}, job = "法师", orig = "露娜",     title = "电音天后",   art = false },
    { id = 7,  meme = "信光机兵",     q = "SR",  qc = {162,160,255}, job = "游侠", orig = "星织",     title = "光之巨人", art = false },
    { id = 8,  meme = "愤怒的小雀",   q = "SR",  qc = {162,160,255}, job = "刺客", orig = "绫音",     title = "弹弓怒鸟",     art = false },
    { id = 9,  meme = "卡皮巴拉",     q = "SR",  qc = {162,160,255}, job = "牧师", orig = "芙罗拉",   title = "温泉教主", art = true  },
    { id = 10, meme = "铁憨憨",       q = "SSR", qc = {255,237,0},   job = "骑士", orig = "丽贝卡",   title = "扛门大将军", art = true  },
    { id = 11, meme = "熬夜冠军",     q = "SSR", qc = {255,237,0},   job = "战士", orig = "素华",     title = "熬夜修仙党",   art = true  },
    { id = 12, meme = "雪皇",         q = "SSR", qc = {255,237,0},   job = "法师", orig = "艾丝翠德", title = "甜蜜冰后", art = false },
    { id = 13, meme = "弹弹弹",       q = "SSR", qc = {255,237,0},   job = "游侠", orig = "罗莎琳",   title = "鱼尾纹克星", art = true  },
    { id = 14, meme = "内鬼",         q = "SSR", qc = {255,237,0},   job = "刺客", orig = "幽夜",     title = "藏得最深的人", art = false },
    { id = 15, meme = "复活吧爱人",   q = "SSR", qc = {255,237,0},   job = "牧师", orig = "伊丽莎白", title = "急救复活甲", art = false },
    { id = 16, meme = "万剑归宗",     q = "UR",  qc = {255,106,0},   job = "战士", orig = "洛星绘",   title = "御剑飞行家", art = false },
    { id = 20, meme = "摘星星星人",   q = "UR",  qc = {255,106,0},   job = "法师", orig = "梅丽莎",   title = "太空出差人",   art = true  },
    { id = 21, meme = "闪电卖鸡",     q = "SSR", qc = {255,237,0},   job = "战士", orig = "亚历克斯", title = "赛道之王", art = true  },
    { id = 22, meme = "小黑子",   q = "SSR", qc = {255,237,0},   job = "法师", orig = "赛拉",     title = "两年半练习生", art = false },
    { id = 23, meme = "真布诗人", q = "SSR", qc = {255,237,0},  job = "牧师", orig = "艾尔温",   title = "即兴说唱王", art = false },
}

-- 布局常量(画布 860x1560)
local W, H     = 940, 1700
local COLS     = 5
local CELL_W   = 184
local CARD_W   = 150
local CARD_H   = 332
local X0       = 30
local Y0       = 96
local CELL_H   = 394

local nvg      = nil
local fontId   = nil
local imgs     = {}

function Start()
    nvg = nvgCreate(1)
    if nvg == nil then
        print("[roster] ERROR: nvgCreate failed")
        return
    end
    fontId = nvgCreateFont(nvg, "cn", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    if fontId == -1 or fontId == nil then
        print("[roster] ERROR: font load failed")
        return
    end
    for _, h in ipairs(HEROES) do
        local path = string.format("image/角色卡牌/KP_YX_%d.png", h.id)
        local img = nvgCreateImage(nvg, path, 0)
        imgs[h.id] = img
        print("[roster] load " .. path .. " -> " .. tostring(img))
    end
    SubscribeToEvent(nvg, "NanoVGRender", "HandleRender")
    print("[roster] ready, waiting screenshot frame")
end

---@param eventType string
---@param eventData any
function HandleRender(eventType, eventData)
    local graphics = GetGraphics()
    if not graphics then return end
    local width = graphics:GetWidth()
    local height = graphics:GetHeight()

    nvgBeginFrame(nvg, width, height, 1.0)

    -- 背景
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, width, height)
    nvgFillColor(nvg, nvgRGBA(22, 22, 42, 255))
    nvgFill(nvg)

    -- 标题
    nvgFontFaceId(nvg, fontId)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 30)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg, W * 0.5, 38, "角色总览 · 玩梗卡面 v2(全量实装)", nil)
    nvgFontSize(nvg, 15)
    nvgFillColor(nvg, nvgRGBA(150, 150, 180, 255))
    nvgText(nvg, W * 0.5, 68, "20名英雄 · 脸部特写+品质晕+紫框 · 已全部实装为游戏卡面 KP_YX", nil)

    for i, h in ipairs(HEROES) do
        local row = math.floor((i - 1) / COLS)
        local col = (i - 1) % COLS
        local cellX = X0 + col * CELL_W
        local cellY = Y0 + row * CELL_H
        local cx = cellX + CELL_W * 0.5
        local img = imgs[h.id]

        -- 卡牌底框
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - CARD_W * 0.5 - 3, cellY - 3, CARD_W + 6, CARD_H + 6, 6)
        nvgFillColor(nvg, nvgRGBA(58, 58, 106, 255))
        nvgFill(nvg)

        -- 卡牌图
        if img and img >= 0 then
            local paint = nvgImagePattern(nvg, cx - CARD_W * 0.5, cellY, CARD_W, CARD_H, 0, img, 1.0)
            nvgBeginPath(nvg)
            nvgRect(nvg, cx - CARD_W * 0.5, cellY, CARD_W, CARD_H)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)
        else
            nvgBeginPath(nvg)
            nvgRect(nvg, cx - CARD_W * 0.5, cellY, CARD_W, CARD_H)
            nvgFillColor(nvg, nvgRGBA(60, 30, 30, 255))
            nvgFill(nvg)
        end

        local ty = cellY + CARD_H + 16
        -- 行1: #id 玩梗名 品质·职业
        nvgFontSize(nvg, 15)
        local line1 = string.format("#%d %s %s·%s", h.id, h.meme, h.q, h.job)
        local wq = nvgTextBounds(nvg, 0, 0, "#" .. h.id .. " ", nil)
        local wname = nvgTextBounds(nvg, 0, 0, h.meme .. " ", nil)
        local totalW = wq + wname + nvgTextBounds(nvg, 0, 0, h.q .. "·" .. h.job, nil)
        local sx = cx - totalW * 0.5
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(200, 200, 220, 255))
        nvgText(nvg, sx, ty, "#" .. h.id .. " ", nil)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgText(nvg, sx + wq, ty, h.meme .. " ", nil)
        nvgFillColor(nvg, nvgRGBA(h.qc[1], h.qc[2], h.qc[3], 255))
        nvgText(nvg, sx + wq + wname, ty, h.q .. "·" .. h.job, nil)
        -- 行2: 原名·称号
        ty = ty + 20
        nvgFontSize(nvg, 13)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(150, 150, 180, 255))
        nvgText(nvg, cx, ty, "原名" .. h.orig .. "·" .. h.title, nil)

    end

    nvgEndFrame(nvg)
end
