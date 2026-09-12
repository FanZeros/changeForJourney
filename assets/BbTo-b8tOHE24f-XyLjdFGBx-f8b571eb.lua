-- 离线渲染:20 角色卡牌总览板(玩梗规划版) → 截图输出
-- 运行: UrhoXRuntime _proc/roster_board.lua -tapcode_dir=... -tool_mode -graphicssurfaceless -screenshot=...

-- 数据: id, 玩梗名, 品质, 职业, 原名, 称号, 有立绘文件
local HEROES = {
    { id = 1,  meme = "大狗嚼",       q = "R",   qc = {160,160,160}, job = "战士", orig = "卡琳",     title = "初心之剑", art = true  },
    { id = 2,  meme = "奶龙龙",       q = "R",   qc = {160,160,160}, job = "法师", orig = "麦琪",     title = "魔法学徒", art = true  },
    { id = 3,  meme = "叮咚鸡",       q = "R",   qc = {160,160,160}, job = "游侠", orig = "琳达",     title = "林风哨卫", art = true  },
    { id = 4,  meme = "接化发掌门",   q = "SR",  qc = {162,160,255}, job = "骑士", orig = "塞西莉亚", title = "圣誓之锋", art = false },
    { id = 5,  meme = "叠甲怪",       q = "SR",  qc = {162,160,255}, job = "战士", orig = "维多利亚", title = "征服者",   art = true  },
    { id = 6,  meme = "阿姨压一压",   q = "SR",  qc = {162,160,255}, job = "法师", orig = "露娜",     title = "魔术师",   art = false },
    { id = 7,  meme = "信光机兵",     q = "SR",  qc = {162,160,255}, job = "游侠", orig = "星织",     title = "闪光机兵", art = false },
    { id = 8,  meme = "愤怒的小雀",   q = "SR",  qc = {162,160,255}, job = "刺客", orig = "绫音",     title = "蓝雀",     art = false },
    { id = 9,  meme = "卡皮巴拉",     q = "SR",  qc = {162,160,255}, job = "牧师", orig = "芙罗拉",   title = "自然之使", art = true  },
    { id = 10, meme = "铁憨憨",       q = "SSR", qc = {255,237,0},   job = "骑士", orig = "丽贝卡",   title = "帝国之枪", art = true  },
    { id = 11, meme = "熬夜冠军",     q = "SSR", qc = {255,237,0},   job = "战士", orig = "素华",     title = "斩夜姬",   art = true  },
    { id = 12, meme = "雪皇",         q = "SSR", qc = {255,237,0},   job = "法师", orig = "艾丝翠德", title = "冰晶使者", art = false },
    { id = 13, meme = "弹弹弹",       q = "SSR", qc = {255,237,0},   job = "游侠", orig = "罗莎琳",   title = "蔷薇之花", art = true  },
    { id = 14, meme = "内鬼",         q = "SSR", qc = {255,237,0},   job = "刺客", orig = "幽夜",     title = "影子忍者", art = false },
    { id = 15, meme = "复活吧爱人",   q = "SSR", qc = {255,237,0},   job = "牧师", orig = "伊丽莎白", title = "光之圣女", art = false },
    { id = 16, meme = "万剑归宗",     q = "UR",  qc = {255,106,0},   job = "战士", orig = "洛星绘",   title = "灵月剑仙", art = false },
    { id = 20, meme = "摘星星星人",   q = "UR",  qc = {255,106,0},   job = "法师", orig = "梅丽莎",   title = "摘星使",   art = true  },
    { id = 21, meme = "闪电卖鸡",     q = "SSR", qc = {255,237,0},   job = "战士", orig = "亚历克斯", title = "银色闪光", art = true  },
    { id = 22, meme = "小黑子鸡哥",   q = "SSR", qc = {255,237,0},   job = "法师", orig = "赛拉",     title = "精灵使徒", art = false },
    { id = 23, meme = "Freestyle诗人", q = "SSR", qc = {255,237,0},  job = "牧师", orig = "艾尔温",   title = "吟游诗人", art = false },
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
    nvgText(nvg, W * 0.5, 38, "角色总览图 · 玩梗规划 v1", nil)
    nvgFontSize(nvg, 15)
    nvgFillColor(nvg, nvgRGBA(150, 150, 180, 255))
    nvgText(nvg, W * 0.5, 68, "共20名英雄 · 绿=已有立绘文件 橙=缺立绘文件(卡面即立绘裁切)", nil)

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
        -- 行3: 立绘状态
        ty = ty + 18
        if h.art then
            nvgFillColor(nvg, nvgRGBA(120, 255, 120, 255))
            nvgText(nvg, cx, ty, "立绘: 有", nil)
        else
            nvgFillColor(nvg, nvgRGBA(255, 165, 0, 255))
            nvgText(nvg, cx, ty, "立绘: 缺(待补)", nil)
        end
    end

    nvgEndFrame(nvg)
end
