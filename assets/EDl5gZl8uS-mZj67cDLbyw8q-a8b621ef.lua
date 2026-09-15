-- ============================================================================
-- HeroRosterPanel - 角色配置表（全屏覆盖面板）
-- 展示全部英雄角色的属性配置，含品质、职业、天赋、六围、成长等
-- ============================================================================

local HC = require("config.HeroConfig")
local CC = require("config.ClassConfig")
local HeroAssetUtil = require("config.HeroAssetUtil")

local Panel = {}

-- ======================== 状态 ========================

local isOpen = false
local scrollY = 0
local maxScrollY = 0

-- ======================== 布局常量 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

local MARGIN     = 40
local TITLE_H    = 70
local CARD_H     = 140
local CARD_GAP   = 8
local CARD_PAD_X = 16
local CARD_PAD_Y = 12
local CLOSE_SIZE = 50

-- ======================== 颜色 ========================

local QUALITY_COLORS = {
    [1] = { 160, 160, 160 },   -- R: 灰
    [2] = { 162, 140, 255 },   -- SR: 紫蓝
    [3] = { 255, 220, 40 },    -- SSR: 金
}

local COLOR_BG        = { 15, 15, 25, 230 }
local COLOR_CARD_BG   = { 38, 38, 55, 240 }
local COLOR_TITLE     = { 255, 220, 80, 255 }

local imgHeroCards = {}  -- imgHeroCards[heroId] = nvg image handle
local COLOR_NAME      = { 255, 255, 255, 255 }
local COLOR_TALENT    = { 80, 210, 170, 255 }
local COLOR_ATK_INFO  = { 180, 170, 240, 255 }
local COLOR_STATS     = { 200, 200, 215, 255 }
local COLOR_GROWTH    = { 150, 150, 170, 255 }
local COLOR_CLOSE_BG  = { 180, 50, 50, 220 }

-- ======================== 预计算 ========================

local heroIds = {}  -- 缓存排序后的英雄 ID 列表

local function recalcScroll()
    local totalH = TITLE_H + 10 + #heroIds * (CARD_H + CARD_GAP) + MARGIN
    local viewH = DESIGN_H - MARGIN * 2
    maxScrollY = math.max(0, totalH - viewH)
    scrollY = math.max(0, math.min(scrollY, maxScrollY))
end

-- ======================== Public API ========================

function Panel.init(vg)
    isOpen = false
    scrollY = 0
    heroIds = HC.getAllIds()
    -- 加载英雄卡片背景 (1~15)
    HeroAssetUtil.preloadCards(vg, imgHeroCards)
end

function Panel.isVisible()
    return isOpen
end

function Panel.toggle()
    isOpen = not isOpen
    if isOpen then
        scrollY = 0
        heroIds = HC.getAllIds()
        recalcScroll()
    end
end

function Panel.show()
    isOpen = true
    scrollY = 0
    heroIds = HC.getAllIds()
    recalcScroll()
end

function Panel.hide()
    isOpen = false
end

-- ======================== 渲染 ========================

function Panel.draw(vg)
    if not isOpen then return end

    -- 全屏半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(COLOR_BG[1], COLOR_BG[2], COLOR_BG[3], COLOR_BG[4]))
    nvgFill(vg)

    -- ---- 标题 ----
    local titleY = MARGIN - scrollY
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 40)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(COLOR_TITLE[1], COLOR_TITLE[2], COLOR_TITLE[3], COLOR_TITLE[4]))
    nvgText(vg, DESIGN_W / 2, titleY + TITLE_H / 2, "角色配置表", nil)

    -- ---- 关闭按钮 ----
    local closeX = DESIGN_W - MARGIN - CLOSE_SIZE
    local closeY = MARGIN
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, CLOSE_SIZE, CLOSE_SIZE, 8)
    nvgFillColor(vg, nvgRGBA(COLOR_CLOSE_BG[1], COLOR_CLOSE_BG[2], COLOR_CLOSE_BG[3], COLOR_CLOSE_BG[4]))
    nvgFill(vg)
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, closeX + CLOSE_SIZE / 2, closeY + CLOSE_SIZE / 2, "X", nil)

    -- ---- 裁剪区域（标题下方到底部） ----
    local clipTop = MARGIN + TITLE_H
    local clipH   = DESIGN_H - clipTop - MARGIN
    nvgSave(vg)
    nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)

    -- ---- 英雄卡片列表 ----
    local cardW  = DESIGN_W - MARGIN * 2
    local startY = clipTop + 10 - scrollY

    for i, id in ipairs(heroIds) do
        local hero = HC.get(id)
        if not hero then goto continue end

        local cardY = startY + (i - 1) * (CARD_H + CARD_GAP)

        -- 可见性裁剪：完全不在视口内则跳过
        if cardY + CARD_H < clipTop or cardY > clipTop + clipH then
            goto continue
        end

        local qc = QUALITY_COLORS[hero.quality] or { 200, 200, 200 }

        -- 卡片背景（使用对应英雄卡片图片）
        local cardImg = imgHeroCards[id] or imgHeroCards[1]
        if cardImg and cardImg > 0 then
            local imgPaint = nvgImagePattern(vg, MARGIN, cardY, cardW, CARD_H, 0, cardImg, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, MARGIN, cardY, cardW, CARD_H, 10)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            nvgBeginPath(vg)
            nvgRoundedRect(vg, MARGIN, cardY, cardW, CARD_H, 10)
            nvgFillColor(vg, nvgRGBA(COLOR_CARD_BG[1], COLOR_CARD_BG[2], COLOR_CARD_BG[3], COLOR_CARD_BG[4]))
            nvgFill(vg)
        end

        -- 品质色边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, MARGIN, cardY, cardW, CARD_H, 10)
        nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 160))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 左侧品质色装饰条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, MARGIN, cardY, 5, CARD_H, 3)
        nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 200))
        nvgFill(vg)

        local textX = MARGIN + CARD_PAD_X + 6
        local textR = MARGIN + cardW - CARD_PAD_X
        local lineH = 23
        local cy = cardY + CARD_PAD_Y

        -- ---- 第1行：序号 [品质] 职业 | 名字 — 称谓 ----
        local qualityName = HC.QUALITY_INFO[hero.quality] and HC.QUALITY_INFO[hero.quality].name or "?"
        local classCfg = CC.get(hero.classId)
        local className = classCfg and classCfg.name or "?"

        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
        nvgText(vg, textX, cy, string.format("#%d [%s] %s", id, qualityName, className), nil)

        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(COLOR_NAME[1], COLOR_NAME[2], COLOR_NAME[3], COLOR_NAME[4]))
        nvgText(vg, textR, cy, hero.name .. " — " .. hero.title, nil)
        cy = cy + lineH + 3

        -- ---- 第2行：天赋 ----
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(COLOR_TALENT[1], COLOR_TALENT[2], COLOR_TALENT[3], COLOR_TALENT[4]))
        nvgText(vg, textX, cy, "天赋: " .. hero.talentName .. " — " .. hero.talentDesc, nil)
        cy = cy + lineH + 2

        -- ---- 第3行：伤害类型·次类型 | 间隔 | 目标 | 系数 | 波动 ----
        local mainType = hero.dmgMainType or "?"
        local subType  = hero.dmgSubType or "?"
        nvgFillColor(vg, nvgRGBA(COLOR_ATK_INFO[1], COLOR_ATK_INFO[2], COLOR_ATK_INFO[3], COLOR_ATK_INFO[4]))
        local atkLine = string.format("%s·%s | 间隔%.1fs | 目标%d | 系数%.2f | 波动%d%%",
            mainType, subType,
            hero.atkInterval, hero.atkTargets,
            hero.atkCoeff, math.floor(hero.dmgSpread * 100 + 0.5))
        nvgText(vg, textX, cy, atkLine, nil)
        cy = cy + lineH + 2

        -- ---- 第4行：初始六围 ----
        local bs = hero.baseStats
        nvgFillColor(vg, nvgRGBA(COLOR_STATS[1], COLOR_STATS[2], COLOR_STATS[3], COLOR_STATS[4]))
        nvgText(vg, textX, cy,
            string.format("初始: 力%.1f 敏%.1f 智%.1f 体%.1f 运%.1f 精%.1f",
                bs.str, bs.agi, bs.int, bs.vit, bs.luk, bs.spi), nil)
        cy = cy + lineH + 2

        -- ---- 第5行：成长六围（仅显示非零项） ----
        local gs = hero.growthStats
        local parts = {}
        if gs.str > 0 then parts[#parts + 1] = string.format("力%.2f", gs.str) end
        if gs.agi > 0 then parts[#parts + 1] = string.format("敏%.2f", gs.agi) end
        if gs.int > 0 then parts[#parts + 1] = string.format("智%.2f", gs.int) end
        if gs.vit > 0 then parts[#parts + 1] = string.format("体%.2f", gs.vit) end
        if gs.luk > 0 then parts[#parts + 1] = string.format("运%.2f", gs.luk) end
        if gs.spi > 0 then parts[#parts + 1] = string.format("精%.2f", gs.spi) end
        nvgFillColor(vg, nvgRGBA(COLOR_GROWTH[1], COLOR_GROWTH[2], COLOR_GROWTH[3], COLOR_GROWTH[4]))
        nvgText(vg, textX, cy, "成长: " .. table.concat(parts, " "), nil)

        ::continue::
    end

    nvgRestore(vg)

    -- ---- 滚动条指示器 ----
    if maxScrollY > 0 then
        local viewH = clipH
        local totalContentH = #heroIds * (CARD_H + CARD_GAP)
        local barH = math.max(40, viewH * viewH / totalContentH)
        local barY = clipTop + (scrollY / maxScrollY) * (viewH - barH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, DESIGN_W - 12, barY, 6, barH, 3)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 60))
        nvgFill(vg)
    end
end

-- ======================== 输入处理 ========================

--- 处理点击（设计空间坐标）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费了该事件
function Panel.handleInput(dx, dy)
    if not isOpen then return false end

    -- 关闭按钮（固定在顶部，不随滚动）
    local closeX = DESIGN_W - MARGIN - CLOSE_SIZE
    local closeY = MARGIN
    if dx >= closeX and dx <= closeX + CLOSE_SIZE
       and dy >= closeY and dy <= closeY + CLOSE_SIZE then
        isOpen = false
        return true
    end

    -- 面板打开时拦截所有点击，防止穿透
    return true
end

--- 处理滚动（鼠标滚轮或拖拽偏移量）
---@param delta number 正值向上滚，负值向下滚
---@return boolean 是否消费了该事件
function Panel.handleScroll(delta)
    if not isOpen then return false end
    scrollY = math.max(0, math.min(maxScrollY, scrollY - delta))
    return true
end

return Panel
