-- ============================================================================
-- TargetRecruitPanel - 指定招募 / 星辉指定UP角色面板
-- 从酒馆页面点击“指定招募”或“指定UP角色”按钮打开
-- 常规招募: 指定一个SSR冒险家，在保底次数内必出
-- 星辉招募: 指定一个UR角色，抽到UR时50%概率获得该角色
-- ============================================================================

local GameConfig    = require("config.GameConfig")
local HeroConfig    = require("config.HeroConfig")
local ClassConfig   = require("config.ClassConfig")
local DrawUtil      = require("core.DrawUtil")
local BF            = require("systems.ButtonFeedback")

local drawImageCentered       = DrawUtil.drawImageCentered
local drawNineSlice           = DrawUtil.drawNineSlice
local drawTextStroke          = DrawUtil.drawTextStroke
local drawRoundedRectCentered = DrawUtil.drawRoundedRectCentered
local hitTest                 = DrawUtil.hitTest

local PlayerStore   = require("client.data.PlayerStore")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local M = {}

-- ======================== 设计分辨率 ========================
local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 职业编号映射 ========================
local CLASS_NUM = {
    [ClassConfig.KNIGHT]   = 1,
    [ClassConfig.WARRIOR]  = 2,
    [ClassConfig.MAGE]     = 3,
    [ClassConfig.RANGER]   = 4,
    [ClassConfig.ASSASSIN] = 5,
    [ClassConfig.PRIEST]   = 6,
}

-- ======================== 布局常量 ========================

-- 二级背景框 UI_TY_EJQRK
local BG_CX, BG_CY = 540, 1224
local BG_W, BG_H   = 950, 1487
local BG_INSET_TOP, BG_INSET_RIGHT, BG_INSET_BOTTOM, BG_INSET_LEFT = 180, 40, 50, 40

-- 标题
local TITLE_CX, TITLE_CY = 540, 543
local TITLE_FONT = 60
local TITLE_STROKE_R, TITLE_STROKE_G, TITLE_STROKE_B = 0x59, 0x32, 0x19
local TITLE_STROKE_W = 6

-- 说明文本
local DESC_CX, DESC_CY = 540, 657
local DESC_FONT = 40
local DESC_COLOR_R, DESC_COLOR_G, DESC_COLOR_B = 0xb6, 0xb0, 0x9d
local DESC_NUM_R, DESC_NUM_G, DESC_NUM_B = 0x24, 0xb2, 0x42

-- 冒险家选择区域
local SELECT_CX, SELECT_CY = 540, 1058
local SELECT_W, SELECT_H   = 800, 716
local SELECT_R = 16
local SELECT_PAD = 30  -- 内边距

-- 头像
local AVATAR_SIZE = 160
local AVATAR_GAP  = 16
local CLASS_BADGE_SIZE = 48  -- 职业角标尺寸

-- 已指定区域
local CHOSEN_BG_CX, CHOSEN_BG_CY = 540, 1609
local CHOSEN_BG_W, CHOSEN_BG_H   = 800, 322
local CHOSEN_BG_R = 16

-- 已指定头像
local CHOSEN_AVATAR_CX, CHOSEN_AVATAR_CY = 540, 1574

-- 已指定文本
local CHOSEN_TEXT_CX, CHOSEN_TEXT_CY = 540, 1704

-- 确定按钮
local CONFIRM_CX, CONFIRM_CY = 540, 1862
local CONFIRM_W, CONFIRM_H   = 410, 100
local CONFIRM_FONT = 40
local BTN_INSET_TOP, BTN_INSET_RIGHT, BTN_INSET_BOTTOM, BTN_INSET_LEFT = 10, 40, 10, 40

-- ======================== 状态 ========================
local state = {
    open = false,
    mode = "standard",       -- "standard"=常规指定招募；"stellar"=星辉指定UP角色
    selectedHeroId = nil,  -- 当前点选的英雄 ID
    confirmedHeroId = nil, -- 已确认指定的英雄 ID（来自服务端数据）
    pityRemain = 3,        -- 保底剩余次数
}

-- ======================== 图片句柄 ========================
local img = {
    bg         = -1,  -- UI_TY_EJQRK.png
    btnYellow  = -1,  -- UI_AN_HUANG.png
    heroIcons  = {},   -- [heroId] = handle
    classBadge = {},   -- [1-6] = handle (UI_icon_ZBBJ_1~6)
    qualityBgStandard = -1,   -- SSR品质框 UI_icon_ZBBJ_5
    qualityBgStellar  = -1,   -- UR品质框 UI_icon_ZBBJ_6
}

---@type any
local vg_ = nil

-- 英雄列表缓存
local heroLists = {
    standard = {}, -- SSR 英雄
    stellar  = {}, -- UR 英雄
}

local function getActiveHeroes()
    return heroLists[state.mode] or heroLists.standard
end

--- [暗黑化 P2-A] 品质框改为矢量绘制：返回品质号（standard=SSR 5 黄金 / stellar=UR 6 血钻）
local function getQualityFrame(mode)
    if mode == "stellar" then
        return 6
    end
    return 5
end

-- ======================== 初始化 ========================

function M.init(vg)
    vg_ = vg
    -- [暗黑化 P1-B5] 原 image/UI_AN_HUANG.png 贴图加载已移除（矢量绘制替代）
    img.btnYellow = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    img.qualityBgStandard = nvgCreateImage(vg, "image/UI_icon_ZBBJ_5.png", 0)
    img.qualityBgStellar  = nvgCreateImage(vg, "image/UI_icon_ZBBJ_6.png", 0)

    -- 加载职业图标
    for i = 1, 6 do
        img.classBadge[i] = nvgCreateImage(vg, "image/ICON_ZY_" .. i .. ".png", 0)
    end

    heroLists.standard = {}
    heroLists.stellar = {}

    local function cacheHeroes(mode, quality)
        local ids = HeroConfig.getIdsByQuality(quality)
        for _, id in ipairs(ids) do
            local hero = HeroConfig.HEROES[id]
            if hero then
                local classIdx = CLASS_NUM[hero.classId] or 1
                heroLists[mode][#heroLists[mode] + 1] = {
                    id = id,
                    name = hero.name,
                    classId = hero.classId,
                    classIdx = classIdx,
                }
                if not img.heroIcons[id] then
                    img.heroIcons[id] = nvgCreateImage(vg, "image/角色图标/UI_icon_hero_" .. id .. ".png", 0)
                end
            end
        end
    end

    cacheHeroes("standard", HeroConfig.QUALITY_SSR)
    cacheHeroes("stellar", HeroConfig.QUALITY_UR)

    print("[TargetRecruitPanel] init OK, SSR heroes: " .. #heroLists.standard
        .. " UR heroes: " .. #heroLists.stellar)
end

-- ======================== 打开/关闭 ========================

--- 打开面板
---@param mode string|nil "standard" | "stellar"
function M.open(mode)
    state.mode = (mode == "stellar") and "stellar" or "standard"

    local targetId
    local remain
    if state.mode == "stellar" then
        targetId = PlayerStore.GetField("currency", "stellarTargetUpHeroId")
        remain = 0
    else
        targetId = PlayerStore.GetField("currency", "targetRecruitHeroId")
        remain   = PlayerStore.GetField("currency", "targetRecruitRemain")
    end

    state.confirmedHeroId = targetId
    state.pityRemain = (remain and remain > 0) and remain or 3

    state.open = true
    state.selectedHeroId = state.confirmedHeroId  -- 默认选中已指定的
    print("[TargetRecruitPanel] opened mode=" .. state.mode
        .. " target=" .. tostring(targetId) .. " remain=" .. tostring(state.pityRemain))
end

function M.close()
    state.open = false
    print("[TargetRecruitPanel] closed")
end

function M.isOpen()
    return state.open
end

--- 设置服务端数据（已指定的英雄和剩余保底次数）
---@param heroId number|nil
---@param remain number
function M.setData(heroId, remain)
    state.confirmedHeroId = heroId
    state.pityRemain = remain or 3
end

-- ======================== 绘制 ========================

function M.draw(vg)
    if not state.open then return end

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 背景九宫格
    DarkIcon.drawNine(vg, "panel", BG_CX - BG_W * 0.5, BG_CY - BG_H * 0.5, BG_W, BG_H, { titleH = BG_INSET_TOP })

    local isStellarMode = state.mode == "stellar"
    local titleText = isStellarMode and "指定UP角色" or "指定招募"
    local qualityFrame = getQualityFrame(state.mode)
    local activeHeroes = getActiveHeroes()

    -- 标题
    drawTextStroke(vg, TITLE_CX, TITLE_CY, titleText, TITLE_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255,
        TITLE_STROKE_W, { strokeColor = { TITLE_STROKE_R, TITLE_STROKE_G, TITLE_STROKE_B } })

    -- 说明文本（带高亮数字）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DESC_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 分段绘制说明文本
    local prefix, numStr, suffix
    if isStellarMode then
        prefix = "指定一个UR角色，抽到UR时"
        numStr = "50%"
        suffix = "概率获得"
    else
        prefix = "指定一个冒险家在"
        numStr = tostring(state.pityRemain)
        suffix = "次SSR内必出"
    end

    -- 测量各段宽度
    nvgFillColor(vg, nvgRGBA(DESC_COLOR_R, DESC_COLOR_G, DESC_COLOR_B, 255))
    local prefixW = nvgTextBounds(vg, 0, 0, prefix)
    nvgFillColor(vg, nvgRGBA(DESC_NUM_R, DESC_NUM_G, DESC_NUM_B, 255))
    local numW = nvgTextBounds(vg, 0, 0, numStr)
    nvgFillColor(vg, nvgRGBA(DESC_COLOR_R, DESC_COLOR_G, DESC_COLOR_B, 255))
    local suffixW = nvgTextBounds(vg, 0, 0, suffix)

    local totalW = prefixW + numW + suffixW
    local startX = DESC_CX - totalW * 0.5

    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DESC_COLOR_R, DESC_COLOR_G, DESC_COLOR_B, 255))
    nvgText(vg, startX, DESC_CY, prefix, nil)

    nvgFillColor(vg, nvgRGBA(DESC_NUM_R, DESC_NUM_G, DESC_NUM_B, 255))
    nvgText(vg, startX + prefixW, DESC_CY, numStr, nil)

    nvgFillColor(vg, nvgRGBA(DESC_COLOR_R, DESC_COLOR_G, DESC_COLOR_B, 255))
    nvgText(vg, startX + prefixW + numW, DESC_CY, suffix, nil)

    -- 冒险家选择区域背景
    drawRoundedRectCentered(vg, SELECT_CX, SELECT_CY, SELECT_W, SELECT_H, SELECT_R, 0, 0, 0, 13)

    -- 绘制 SSR 英雄头像网格（居中排列）
    local areaW    = SELECT_W - SELECT_PAD * 2
    local areaTop  = SELECT_CY - SELECT_H * 0.5 + SELECT_PAD
    local cols     = math.floor((areaW + AVATAR_GAP) / (AVATAR_SIZE + AVATAR_GAP))
    if cols < 1 then cols = 1 end
    -- 实际网格宽度，用于水平居中
    local gridW    = cols * AVATAR_SIZE + (cols - 1) * AVATAR_GAP
    local gridLeft = SELECT_CX - gridW * 0.5

    for i, hero in ipairs(activeHeroes) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local cx = gridLeft + col * (AVATAR_SIZE + AVATAR_GAP) + AVATAR_SIZE * 0.5
        local cy = areaTop + row * (AVATAR_SIZE + AVATAR_GAP) + AVATAR_SIZE * 0.5

        -- 选中高亮
        local isSelected = (state.selectedHeroId == hero.id)
        if isSelected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - AVATAR_SIZE * 0.5 - 4, cy - AVATAR_SIZE * 0.5 - 4,
                AVATAR_SIZE + 8, AVATAR_SIZE + 8, 12)
            nvgFillColor(vg, nvgRGBA(0x24, 0xb2, 0x42, 180))
            nvgFill(vg)
        end

        -- 品质框 [暗黑化 P2-A]
        DarkIcon.drawQualityBg(vg, qualityFrame, cx, cy, AVATAR_SIZE, AVATAR_SIZE, 1.0)

        -- 英雄头像（160x160 与品质框同尺寸）
        local heroIcon = img.heroIcons[hero.id]
        if heroIcon and heroIcon >= 0 then
            drawImageCentered(vg, heroIcon, cx, cy, AVATAR_SIZE, AVATAR_SIZE, 1.0)
        end

        -- 职业图标（右上角）
        local badgeImg = img.classBadge[hero.classIdx]
        if badgeImg and badgeImg >= 0 then
            local badgeCX = cx + AVATAR_SIZE * 0.5 - CLASS_BADGE_SIZE * 0.35
            local badgeCY = cy - AVATAR_SIZE * 0.5 + CLASS_BADGE_SIZE * 0.35
            drawImageCentered(vg, badgeImg, badgeCX, badgeCY, CLASS_BADGE_SIZE, CLASS_BADGE_SIZE, 1.0)
        end
    end

    -- 已指定区域背景
    drawRoundedRectCentered(vg, CHOSEN_BG_CX, CHOSEN_BG_CY, CHOSEN_BG_W, CHOSEN_BG_H, CHOSEN_BG_R, 0, 0, 0, 13)

    -- 已指定头像
    local displayId = state.selectedHeroId or state.confirmedHeroId
    if displayId then
        local heroIcon = img.heroIcons[displayId]
        if qualityFrame then
            DarkIcon.drawQualityBg(vg, qualityFrame, CHOSEN_AVATAR_CX, CHOSEN_AVATAR_CY, AVATAR_SIZE, AVATAR_SIZE, 1.0)  -- [暗黑化 P2-A]
        end
        if heroIcon and heroIcon >= 0 then
            drawImageCentered(vg, heroIcon, CHOSEN_AVATAR_CX, CHOSEN_AVATAR_CY, AVATAR_SIZE, AVATAR_SIZE, 1.0)
        end

        -- 已指定文本
        local heroCfg = HeroConfig.HEROES[displayId]
        if heroCfg then
            local className = ClassConfig.CLASSES[heroCfg.classId] and ClassConfig.CLASSES[heroCfg.classId].name or ""
            local displayText
            if isStellarMode then
                displayText = "已指定UP[" .. className .. "]" .. heroCfg.name
            else
                displayText = "已指定[" .. className .. "]" .. heroCfg.name
            end

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 36)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0x5f, 0x37, 0x37, 255))
            nvgText(vg, CHOSEN_TEXT_CX, CHOSEN_TEXT_CY, displayText, nil)
        end
    else
        -- 未指定时显示提示
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 150))
        local tipText = isStellarMode and "请选择UR角色" or "请选择冒险家"
        nvgText(vg, CHOSEN_AVATAR_CX, CHOSEN_AVATAR_CY, tipText, nil)
    end

    local activeHeroes = getActiveHeroes()

    -- 确定按钮
    local ds = BF.begin(vg, "target_confirm", CONFIRM_CX, CONFIRM_CY, CONFIRM_W, CONFIRM_H)
    DarkIcon.drawNine(vg, "btn", CONFIRM_CX - CONFIRM_W * 0.5, CONFIRM_CY - CONFIRM_H * 0.5, CONFIRM_W, CONFIRM_H, { accent = "gold" })
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, CONFIRM_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 191))  -- 纯黑75%不透明度
    nvgText(vg, CONFIRM_CX, CONFIRM_CY, "确定", nil)
    BF.finish(vg, ds)
end

-- ======================== 输入处理 ========================

function M.handleInput(dx, dy)
    if not state.open then return false end
    local activeHeroes = getActiveHeroes()

    -- 确定按钮
    if hitTest(dx, dy, CONFIRM_CX, CONFIRM_CY, CONFIRM_W, CONFIRM_H) then
        BF.trigger("target_confirm")
        if state.selectedHeroId then
            state.confirmedHeroId = state.selectedHeroId
            print("[TargetRecruitPanel] confirmed mode=" .. state.mode
                .. " heroId=" .. tostring(state.selectedHeroId))
            -- 发送服务端请求
            local Protocol = require("shared.Protocol")
            local action = (state.mode == "stellar")
                and Protocol.ACTION_TYPES.STELLAR_TARGET_UP
                or Protocol.ACTION_TYPES.TARGET_RECRUIT
            require("network.Client").sendAction(action, {
                heroId = state.selectedHeroId,
            })
            -- 乐观更新：立即刷新 TavernPage 显示
            local TavernPage = require("ui.TavernPage")
            local HeroConfig = require("config.HeroConfig")
            local heroCfg = HeroConfig.get(state.selectedHeroId)
            if state.mode == "stellar" then
                TavernPage.setStellarTargetUp(
                    state.selectedHeroId,
                    heroCfg and heroCfg.name or "未知"
                )
            else
                TavernPage.setTargetRecruit(
                    state.selectedHeroId,
                    heroCfg and heroCfg.name or "未知"
                )
            end
        end
        M.close()
        return true
    end

    -- 英雄头像点击（居中网格，与绘制一致）
    local areaW    = SELECT_W - SELECT_PAD * 2
    local areaTop  = SELECT_CY - SELECT_H * 0.5 + SELECT_PAD
    local cols     = math.floor((areaW + AVATAR_GAP) / (AVATAR_SIZE + AVATAR_GAP))
    if cols < 1 then cols = 1 end
    local gridW    = cols * AVATAR_SIZE + (cols - 1) * AVATAR_GAP
    local gridLeft = SELECT_CX - gridW * 0.5

    for i, hero in ipairs(activeHeroes) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local cx = gridLeft + col * (AVATAR_SIZE + AVATAR_GAP) + AVATAR_SIZE * 0.5
        local cy = areaTop + row * (AVATAR_SIZE + AVATAR_GAP) + AVATAR_SIZE * 0.5

        if hitTest(dx, dy, cx, cy, AVATAR_SIZE, AVATAR_SIZE) then
            state.selectedHeroId = hero.id
            print("[TargetRecruitPanel] selected: " .. hero.name .. " (id=" .. hero.id .. ")")
            require("systems.GameSFX").play("click")
            return true
        end
    end

    -- 点击面板外部区域关闭
    if not hitTest(dx, dy, BG_CX, BG_CY, BG_W, BG_H) then
        M.close()
        return true
    end

    return true  -- 面板打开时吞噬所有输入
end

return M
