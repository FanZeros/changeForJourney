-- ============================================================================
-- DamageStatsPanel - 战斗伤害/治疗/承伤统计面板
-- 入口：战斗界面扫荡按钮左侧的「统计」按钮
-- 功能：实时展示本次战斗中每个己方英雄的输出 / 治疗 / 承受伤害排行
-- 数据：来自 systems.BattleStats（随每波战斗清零）
-- 范式：复用 SweepDialog 弹窗结构（遮罩 + 九宫格 + 弹性缩放 + 点击空白关闭）
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local DrawUtil          = require("core.DrawUtil")
local NumberUtil        = require("core.NumberUtil")
local BattleStats       = require("systems.BattleStats")
local BF                = require("systems.ButtonFeedback")

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice

local DamageStatsPanel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 入口按钮布局（扫荡按钮左侧） ========================
-- 扫荡按钮位于 (971, 2115)，宽 130；统计按钮放其左侧
local BTN_CX = 815
local BTN_CY = 2115
local BTN_W  = 130
local BTN_H  = 144

-- ======================== 弹窗布局常量 ========================

local D = {
    OVL_A   = 128,                       -- 遮罩 50%

    BG_CX   = 540,  BG_CY  = 1195,
    BG_W    = 950,  BG_H   = 1117,
    BG_IT   = 180,  BG_IR  = 40,  BG_IB = 50,  BG_IL = 40,

    -- 标题
    TT_Y    = 705,  TT_FONT = 60,  TT_SW = 6,
    TT_SR   = 0x46, TT_SG  = 0x2f, TT_SB = 0x20,

    -- 副标题（时长 / DPS）
    SUB_Y   = 800,  SUB_FONT = 34,
    SUB_R   = 0xb6, SUB_G  = 0xb0, SUB_B = 0x9d,

    -- Tab 行
    TAB_Y   = 888,  TAB_W  = 248, TAB_H = 78, TAB_R = 18,
    TAB_GAP = 12,

    -- 列表
    ROW_X     = 540,                     -- 行背景中心X
    ROW_W     = 820,
    ROW_H     = 104,
    ROW_FIRST_CY = 1010,                 -- 第一行中心Y
    ROW_STEP  = 116,
    ROW_R     = 16,
    ROW_BG_A  = 20,
    MAX_ROWS  = 5,

    -- 行内元素
    AVATAR_CX = 195, AVATAR_SZ = 80,
    NAME_X    = 262, NAME_FONT = 34,
    VAL_X     = 905, VAL_FONT  = 40,
    SUB2_FONT = 25,
    BAR_X0    = 262, BAR_X1 = 905,
    BAR_H     = 14,  BAR_R = 7,

    -- 空数据提示
    EMPTY_Y   = 1180, EMPTY_FONT = 40,
}

-- ======================== Tab 定义 ========================

local TABS = {
    { key = "damage", label = "输出", sortKey = "totalDamage", color = { 0xff, 0x7a, 0x3c } },
    { key = "heal",   label = "治疗", sortKey = "totalHeal",   color = { 0x36, 0xd6, 0x6e } },
    { key = "taken",  label = "承伤", sortKey = "takenDamage", color = { 0xb0, 0x78, 0xff } },
}

-- 伤害类型色（与战斗伤害飘字一致）
local COLOR_PHYS = { 255, 238, 96 }    -- 物理：黄
local COLOR_MAG  = { 113, 253, 255 }   -- 魔法：青

-- ======================== 图片句柄 ========================

local imgBtn = -1          -- UI_ICON_TJ.png（入口按钮图标）
local imgBg  = -1          -- UI_TY_EJQRK.png（弹窗九宫格背景）
local heroIconCache = {}   -- [heroId] = nvgImage handle
local cachedVg = nil

-- ======================== 状态 ========================

local state = {
    open     = false,
    openTime = 0,
    tab      = "damage",
}

local ANIM_OPEN_DUR = 0.18

-- ======================== 工具 ========================

local function hitTestRect(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

--- 懒加载英雄头像
local function getHeroIcon(heroId)
    if heroIconCache[heroId] == nil then
        if cachedVg then
            heroIconCache[heroId] = nvgCreateImage(cachedVg,
                "image/角色图标/UI_icon_hero_" .. heroId .. ".png", 0)
        else
            heroIconCache[heroId] = -1
        end
    end
    return heroIconCache[heroId]
end

--- 弹窗弹性缩放系数
local function getAnimScale()
    if not state.open then return 0 end
    local t = math.min((time.elapsedTime - state.openTime) / ANIM_OPEN_DUR, 1.0)
    return t * (1.0 + 0.08 * math.sin(t * math.pi))
end

--- 获取当前 Tab 定义
local function getCurrentTab()
    for _, tab in ipairs(TABS) do
        if tab.key == state.tab then return tab end
    end
    return TABS[1]
end

-- ======================== Public API ========================

--- 初始化（在 BattleScene.init 中调用）
---@param vg any NanoVG 上下文
function DamageStatsPanel.init(vg)
    cachedVg = vg
    imgBtn = nvgCreateImage(vg, "image/UI_ICON_TJ.png", 0)
    imgBg  = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    print("[DamageStatsPanel] init OK")
end

function DamageStatsPanel.open()
    if state.open then return end
    state.open     = true
    state.openTime = time.elapsedTime
end

function DamageStatsPanel.close()
    state.open = false
end

function DamageStatsPanel.isOpen()
    return state.open
end

-- ======================== 绘制入口按钮 ========================

--- 绘制战斗界面扫荡按钮左侧的统计入口按钮
---@param vg any
function DamageStatsPanel.drawButton(vg)
    if imgBtn < 0 then return end
    local _ds = BF.begin(vg, "dmgstat_btn", BTN_CX, BTN_CY, BTN_W, BTN_H)
    drawImageCentered(vg, imgBtn, BTN_CX, BTN_CY, BTN_W, BTN_H, 1.0)
    drawTextStroke(vg, BTN_CX, 2174, "统计", 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
    BF.finish(vg, _ds)
end

-- ======================== 绘制弹窗 ========================

--- 绘制单个 Tab 标签
local function drawTab(vg, tab, cx, selected)
    local x = cx - D.TAB_W * 0.5
    local y = D.TAB_Y - D.TAB_H * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, D.TAB_W, D.TAB_H, D.TAB_R)
    if selected then
        nvgFillColor(vg, nvgRGBA(tab.color[1], tab.color[2], tab.color[3], 235))
    else
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 36))
    end
    nvgFill(vg)
    if selected then
        drawTextStroke(vg, cx, D.TAB_Y, tab.label, 38,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4,
            { strokeColor = { 0, 0, 0 } })
    else
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, 255))
        nvgText(vg, cx, D.TAB_Y, tab.label, nil)
    end
end

--- 获取每个 Tab 的中心X坐标
local function getTabCX(index)
    local totalW = #TABS * D.TAB_W + (#TABS - 1) * D.TAB_GAP
    local startCX = D.BG_CX - totalW * 0.5 + D.TAB_W * 0.5
    return startCX + (index - 1) * (D.TAB_W + D.TAB_GAP)
end

--- 绘制单行英雄统计
---@param totalVal number 全队该指标总和（用于占比文本）
local function drawStatRow(vg, entry, cy, tab, mainVal, maxVal, totalVal)
    -- 行背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, D.ROW_X - D.ROW_W * 0.5, cy - D.ROW_H * 0.5,
        D.ROW_W, D.ROW_H, D.ROW_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, D.ROW_BG_A))
    nvgFill(vg)

    -- 头像
    local icon = getHeroIcon(entry.heroId)
    if icon and icon >= 0 then
        drawImageCentered(vg, icon, D.AVATAR_CX, cy, D.AVATAR_SZ, D.AVATAR_SZ, 1.0)
    end

    -- 名字（左上）
    drawTextStroke(vg, D.NAME_X, cy - 30, entry.name or "?", D.NAME_FONT,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 255, 255, 255, 4,
        { strokeColor = { 0, 0, 0 } })

    -- 主数值（右上，Tab 色 + 黑描边）
    drawTextStroke(vg, D.VAL_X, cy - 30, NumberUtil.format(mainVal), D.VAL_FONT,
        NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        tab.color[1], tab.color[2], tab.color[3], 5, { strokeColor = { 0, 0, 0 } })

    local sharePct = (totalVal > 0) and (mainVal / totalVal * 100) or 0

    -- 左下副信息：物理/法术细分（飘字色 + 黑描边），仅显示非 0 的类型
    if tab.key == "damage" then
        local segs = {}
        if (entry.physDamage or 0) > 0 then
            segs[#segs + 1] = { str = "物 " .. NumberUtil.format(entry.physDamage), c = COLOR_PHYS }
        end
        if (entry.magDamage or 0) > 0 then
            segs[#segs + 1] = { str = "法 " .. NumberUtil.format(entry.magDamage), c = COLOR_MAG }
        end
        local sx = D.NAME_X
        for _, seg in ipairs(segs) do
            drawTextStroke(vg, sx, cy + 6, seg.str, D.SUB2_FONT,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
                seg.c[1], seg.c[2], seg.c[3], 3, { strokeColor = { 0, 0, 0 } })
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, D.SUB2_FONT)
            sx = sx + nvgTextBounds(vg, 0, 0, seg.str) + 24
        end
    end

    -- 右下副信息（白色 + 黑描边，确保清晰）
    local subStr
    if tab.key == "damage" then
        local dur = BattleStats.getDuration()
        local dps = (dur > 0.1) and (mainVal / dur) or mainVal
        local critDenom = entry.critHitCount or 0
        local critRate = (critDenom > 0) and (entry.critCount / critDenom * 100) or 0
        subStr = string.format("DPS %s · 暴击率%.0f%%", NumberUtil.format(math.floor(dps)), critRate)
    elseif tab.key == "heal" then
        subStr = string.format("占比%.0f%% · 持续%s", sharePct, NumberUtil.format(entry.hotHeal or 0))
    else
        subStr = string.format("占比%.0f%%", sharePct)
    end
    drawTextStroke(vg, D.VAL_X, cy + 6, subStr, D.SUB2_FONT,
        NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, 255, 255, 255, 3, { strokeColor = { 0, 0, 0 } })

    -- 占比条
    local barW = D.BAR_X1 - D.BAR_X0
    local barY = cy + D.ROW_H * 0.5 - D.BAR_H - 8
    -- 背景轨
    nvgBeginPath(vg)
    nvgRoundedRect(vg, D.BAR_X0, barY, barW, D.BAR_H, D.BAR_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)
    -- 前景
    local ratio = (maxVal > 0) and math.max(0.02, mainVal / maxVal) or 0
    local fillW = barW * ratio
    if fillW > 0 then
        if tab.key == "damage" then
            -- 双色分段：先铺法术青（全长），再覆盖物理黄（左段），整体两端圆角
            local total = (entry.physDamage or 0) + (entry.magDamage or 0)
            local physRatio = (total > 0) and ((entry.physDamage or 0) / total) or 1.0
            -- 法术青底
            nvgBeginPath(vg)
            nvgRoundedRect(vg, D.BAR_X0, barY, fillW, D.BAR_H, D.BAR_R)
            nvgFillColor(vg, nvgRGBA(COLOR_MAG[1], COLOR_MAG[2], COLOR_MAG[3], 235))
            nvgFill(vg)
            -- 物理黄（左段）
            local physW2 = fillW * physRatio
            if physW2 > 0 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, D.BAR_X0, barY, physW2, D.BAR_H, D.BAR_R)
                nvgFillColor(vg, nvgRGBA(COLOR_PHYS[1], COLOR_PHYS[2], COLOR_PHYS[3], 235))
                nvgFill(vg)
            end
        else
            nvgBeginPath(vg)
            nvgRoundedRect(vg, D.BAR_X0, barY, fillW, D.BAR_H, D.BAR_R)
            nvgFillColor(vg, nvgRGBA(tab.color[1], tab.color[2], tab.color[3], 235))
            nvgFill(vg)
        end
    end
end

--- 绘制弹窗全部内容
---@param vg any
function DamageStatsPanel.draw(vg)
    if not state.open then return end
    local scale = getAnimScale()
    if scale <= 0.01 then return end

    -- 1) 全屏遮罩
    local ovlAlpha = math.floor(D.OVL_A * math.min(scale * 2, 1.0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, ovlAlpha))
    nvgFill(vg)

    -- 2) 缩放变换
    nvgSave(vg)
    nvgTranslate(vg, D.BG_CX, D.BG_CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -D.BG_CX, -D.BG_CY)

    -- 3) 九宫格背景
    if imgBg >= 0 then
        drawNineSlice(vg, imgBg,
            D.BG_CX - D.BG_W * 0.5, D.BG_CY - D.BG_H * 0.5,
            D.BG_W, D.BG_H, D.BG_IT, D.BG_IR, D.BG_IB, D.BG_IL)
    end

    -- 4) 标题
    drawTextStroke(vg, D.BG_CX, D.TT_Y, "战斗统计",
        D.TT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, D.TT_SW, { strokeColor = { D.TT_SR, D.TT_SG, D.TT_SB } })

    -- 5) 副标题：本次战斗时长
    local dur = BattleStats.getDuration()
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, D.SUB_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(D.SUB_R, D.SUB_G, D.SUB_B, 255))
    nvgText(vg, D.BG_CX, D.SUB_Y, string.format("本次战斗 · 时长 %.1f 秒", dur), nil)

    -- 6) Tab 行
    for i, tab in ipairs(TABS) do
        drawTab(vg, tab, getTabCX(i), tab.key == state.tab)
    end

    -- 7) 列表
    local tab = getCurrentTab()
    local sorted = BattleStats.getSorted(tab.sortKey)
    -- 过滤掉该 Tab 主数值为 0 的英雄
    local rows = {}
    for _, e in ipairs(sorted) do
        if (e[tab.sortKey] or 0) > 0 then rows[#rows + 1] = e end
    end

    if #rows == 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, D.EMPTY_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, 220))
        nvgText(vg, D.BG_CX, D.EMPTY_Y, "暂无数据", nil)
    else
        local maxVal = rows[1][tab.sortKey] or 0
        local totalVal = BattleStats.getTotal(tab.sortKey)
        local count = math.min(#rows, D.MAX_ROWS)
        for i = 1, count do
            local entry = rows[i]
            local cy = D.ROW_FIRST_CY + (i - 1) * D.ROW_STEP
            drawStatRow(vg, entry, cy, tab, entry[tab.sortKey] or 0, maxVal, totalVal)
        end
    end

    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

--- 处理弹窗内点击（Tab 切换 / 点击空白关闭）
---@param x number
---@param y number
---@return boolean consumed
function DamageStatsPanel.handleInput(x, y)
    if not state.open then return false end

    -- Tab 切换
    for i, tab in ipairs(TABS) do
        if hitTestRect(x, y, getTabCX(i), D.TAB_Y, D.TAB_W, D.TAB_H) then
            if state.tab ~= tab.key then
                BF.trigger("dmgstat_tab_" .. tab.key)
                state.tab = tab.key
            end
            return true
        end
    end

    -- 点击背景外关闭
    if not hitTestRect(x, y, D.BG_CX, D.BG_CY, D.BG_W, D.BG_H) then
        DamageStatsPanel.close()
    end
    return true
end

--- 处理入口按钮点击（由 BattleScene 在扫荡按钮判定之后调用）
---@param x number
---@param y number
---@return boolean consumed
function DamageStatsPanel.handleButtonInput(x, y)
    if state.open then return false end
    if hitTestRect(x, y, BTN_CX, BTN_CY, BTN_W, BTN_H) then
        BF.trigger("dmgstat_btn")
        DamageStatsPanel.open()
        return true
    end
    return false
end

return DamageStatsPanel
