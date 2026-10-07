-- ============================================================================
-- RecruitAnim.lua - 酒馆招募揭晓与结果
-- 只播放已发奖回执：封印聚光、开门、错峰翻牌与品质余辉。
-- ============================================================================
---@diagnostic disable: undefined-global

local HC = require("config.HeroConfig")
local CC = require("config.ClassConfig")
local GameConfig = require("config.GameConfig")
local BattleLayout = require("core.BattleLayout")
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质框/卡底矢量绘制
local ResourceDefs = require("config.ResourceDefs")
local GachaConfig = require("config.GachaConfig")
local UrGachaConfig = require("config.UrGachaConfig")
local GameState = require("core.GameState")
local HeroAssetUtil = require("config.HeroAssetUtil")
local RepeatDrawButton = require("ui.widget.RepeatDrawButton")
local Timeline = require("ui.tavern.RecruitTimeline")
local Presentation = require("ui.tavern.RecruitPresentation")
local drawTextStroke = DrawUtil.drawTextStroke
local drawImageCenteredUtil = DrawUtil.drawImageCentered

local RecruitAnim = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 品质映射 ========================

local QUALITY_TAG = {
    [0] = "N",
    [1] = "R",
    [2] = "SR",
    [3] = "SSR",
    [4] = "UR",
}

local function qualityToBadgeTag(quality)
    if quality == 4 then return "UR" end
    return QUALITY_TAG[quality] or "R"
end

-- classId → 图标编号
local CLASS_NUM = {
    [CC.KNIGHT]   = 1,
    [CC.WARRIOR]  = 2,
    [CC.MAGE]     = 3,
    [CC.RANGER]   = 4,
    [CC.ASSASSIN] = 5,
    [CC.PRIEST]   = 6,
}

-- ======================== 卡片布局常量 ========================

-- 资源卡保留原高度；只有英雄展示按可见卡框比例缩高。
local CARD_W, CARD_H = 198, 438
local HERO_CARD_H = BattleLayout.cardHeightForWidth(CARD_W)
local QUALITY_BADGE_W, QUALITY_BADGE_H = 107, 47

-- 资源类卡片
local RES_ICON_BG_W, RES_ICON_BG_H = 100, 100
local RES_ICON_W, RES_ICON_H       = 100, 100
local RES_ICON_OFFSET_Y             = -89
local RES_QTY_FONT                  = 28
local RES_NAME_FONT                 = 28
local RES_NAME_OFFSET_BOTTOM        = 69   -- 名称距卡底内侧（原44+25上移）

-- 角色类卡片
local CHAR_NAME_FONT                = 28
local CHAR_NAME_OFFSET_BOTTOM       = 69   -- 名称距卡底内侧（原44+25上移）
local CLASS_ICON_W, CLASS_ICON_H    = 60, 60

-- 光效底图（SR/SSR 专用）
local GLOW_W, GLOW_H = 190, 739

-- 十连布局
local TEN_ROW1_Y = 714
local TEN_ROW2_Y = 1383
local TEN_GAP    = 10

-- 单抽位置
local SINGLE_CX, SINGLE_CY = 540, 1050

-- 动画由独立时间轴统一采样，渲染与命中共用揭晓完成条件。
local FADE_OUT_DURATION = Timeline.FADE_DURATION

-- ======================== 资源定义（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- ======================== 状态 ========================
-- phase: "idle" → "intro" → "cards" → "fadeOut" → "idle"

local state = {
    phase         = "idle",
    results       = {},
    highestQ      = 0,
    introStartT   = 0,
    cardStartT    = 0,
    fadeOutStartT = 0,
    pullCount     = 1,
    poolId        = "standard",
    onClose       = nil,
}

-- ======================== 图片缓存 ========================

local cachedVg = nil

local img = {
    resultBg     = -1,
    cardBg       = {},
    qualityBadge = {},
    resIconBg    = {},
    classIcons   = {},
    heroCards    = {},
    resIcons     = {},
    shardIcon    = -1,
    ticketIcon        = -1,
    ticketIconStellar = -1,
    diamondIcon       = -1,
}

-- ======================== 资源管理说明 ========================
-- img.heroCards / img.resIcons 作为模块级持久缓存，生命周期与模块相同。
-- 禁止清空或 nvgDeleteImage（会导致共享纹理句柄泄漏）。

-- ======================== 工具函数 ========================

local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

local function drawImageCentered(vg, imgH, cx, cy, w, h, alpha)
    if imgH < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, imgH, alpha) --[[@as NVGpaint]]
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local function getHeroCardImage(vg, heroId)
    return HeroAssetUtil.ensureCard(vg, img.heroCards, heroId)
end

--- 招募结果与战斗/详情共用新整卡：边框对槽，保留出框和自然重叠。
local function drawHeroCard(vg, heroId, cx, cy, alpha)
    local card = getHeroCardImage(vg, heroId)
    if not card or card < 0 then return end
    DrawUtil.drawCardImage(vg, card, cx, cy, CARD_W, HERO_CARD_H, alpha)
end

local function getResIcon(vg, resType)
    if img.resIcons[resType] then return img.resIcons[resType] end
    local def = RESOURCE_DEFS[resType]
    if not def then return -1 end
    local icon = nvgCreateImage(vg, def.iconPath, 0)
    img.resIcons[resType] = icon
    return icon
end

local function getCardPositions(count)
    local positions = {}
    if count == 1 then
        positions[1] = { x = SINGLE_CX, y = SINGLE_CY }
    else
        local cols = 5
        local row1Count = math.min(count, cols)
        local row2Count = math.max(0, count - cols)
        for i = 1, count do
            local row = (i <= cols) and 1 or 2
            local colInRow = (row == 1) and i or (i - cols)
            local rowCount = (row == 1) and row1Count or row2Count
            local rowTotalW = rowCount * CARD_W + (rowCount - 1) * TEN_GAP
            local rowStartX = (DESIGN_W - rowTotalW) * 0.5 + CARD_W * 0.5
            local cx = rowStartX + (colInRow - 1) * (CARD_W + TEN_GAP)
            local cy = (row == 1) and TEN_ROW1_Y or TEN_ROW2_Y
            positions[i] = { x = cx, y = cy }
        end
    end
    return positions
end

-- ======================== 公开接口 ========================

---@param vg any NanoVG 上下文
function RecruitAnim.init(vg)
    cachedVg = vg
    Presentation.init(vg)
    img.resultBg = nvgCreateImage(vg, "image/界面底板/酒馆抽卡/UI_XKJM.png", 0)
    -- [暗黑化 P2-A] 卡底 KP_TY_N~UR 改由 drawCardBg 矢量绘制，贴图加载已移除
    for _, b in ipairs({ "R", "SR", "SSR", "UR" }) do
        img.qualityBadge[b] = nvgCreateImage(vg, "image/品质框/UI_PZBZ_" .. b .. ".png", 0)
    end
    -- [暗黑化 P2-A] 资源图标底 UI_icon_ZBBJ_1~6 改由 DarkIcon.drawQualityBg 绘制，贴图加载已移除
    for i = 1, 6 do
        img.classIcons[i] = nvgCreateImage(vg, "image/通用图标/ICON_ZY_" .. i .. ".png", 0)
    end
    img.shardIcon = nvgCreateImage(vg, "image/货币道具/ICON_SP.png", 0)
    -- 招募消耗图标（与 TavernPage 一致）
    img.ticketIcon        = nvgCreateImage(vg, "image/货币道具/UI_icon_ZMQ_X.png", 0)
    img.ticketIconStellar = nvgCreateImage(vg, "image/货币道具/UI_icon_ZMQ2_X.png", 0)
    img.diamondIcon       = nvgCreateImage(vg, "image/货币道具/UI_icon_SJ_X.png", 0)
    print("[RecruitAnim] init OK：新角色卡按可见边框对槽，出框保留")
end

local againFn_ = nil
-- 上一次输入是否落在"继续招募"按钮上：中缝返回条此时不能顺手关页。
local lastInputWasRepeat_ = false
local lastRepeatT_ = -math.huge
local lastRevealT_ = -math.huge
local closeCallbacks_ = {}

local function notifyClosed()
    local callbacks = closeCallbacks_
    closeCallbacks_ = {}
    local onClose = state.onClose
    state.onClose = nil
    if onClose then callbacks[#callbacks + 1] = onClose end
    -- 先取走整批回调，回调内重开或关闭不会重复消费旧结果。
    for _, callback in ipairs(callbacks) do callback() end
end

function RecruitAnim.setOnAgain(fn)
    againFn_ = fn
end

local function resultRank(item)
    local t = item and item.type
    if t == "hero" or t == "dupe_to_shard" or t == "decompose" then return 1 end
    if t == "shard" then return 2 end
    return 3
end

function RecruitAnim.start(results, onClose, count, poolId)
    local list = results or {}
    local ordered = {}
    local buckets = { {}, {}, {} }
    for i = 1, #list do
        local item = list[i]
        local rank = resultRank(item)
        local bucket = buckets[rank]
        bucket[#bucket + 1] = item
    end
    for rank = 1, 3 do
        local bucket = buckets[rank]
        for i = 1, #bucket do
            ordered[#ordered + 1] = bucket[i]
        end
    end
    state.results = ordered
    lastInputWasRepeat_ = false
    lastRevealT_ = -math.huge
    if state.onClose then closeCallbacks_[#closeCallbacks_ + 1] = state.onClose end
    state.onClose = onClose
    state.pullCount = (count == 10 or count == 1) and count or ((#ordered > 1) and 10 or 1)
    state.poolId = poolId

    state.highestQ = 0
    for _, r in ipairs(state.results) do
        local q = r.quality or 0
        if q > state.highestQ then state.highestQ = q end
    end

    -- 结果已由业务层结算，表现阶段只读；较长开场同时给卡面加载留出窗口。
    if cachedVg then
        for _, item in ipairs(state.results) do
            if item.heroId and resultRank(item) == 1 then getHeroCardImage(cachedVg, item.heroId) end
        end
    end
    state.fadeOutStartT = 0
    state.introStartT = time.elapsedTime
    state.cardStartT = state.introStartT + Timeline.INTRO_DURATION
    state.phase = "intro"
    print("[RecruitAnim] 开门 cards=" .. tostring(#state.results) .. " quality=" .. state.highestQ)
end

function RecruitAnim.isPlaying()
    return state.phase ~= "idle"
end

local function cardsReady()
    return time.elapsedTime >= state.cardStartT + Timeline.cardSpan(#state.results)
end

local function revealAll()
    state.phase = "cards"
    state.cardStartT = time.elapsedTime - Timeline.cardSpan(#state.results)
    lastRevealT_ = time.elapsedTime
    lastInputWasRepeat_ = false
    print("[RecruitAnim] 跳过表现，揭晓全部")
end

function RecruitAnim.update(dt)
    if state.phase == "idle" then return end
    if state.phase == "intro" and time.elapsedTime - state.introStartT >= Timeline.INTRO_DURATION then
        state.phase = "cards"
        -- 使用计划时间，不因低帧率/暂停回来而额外延长动画。
        print("[RecruitAnim] 开门结束，开始翻牌")
    end
    if state.phase == "fadeOut" and time.elapsedTime - state.fadeOutStartT >= FADE_OUT_DURATION then
        state.phase = "idle"
        state.results = {}
        notifyClosed()
        print("[RecruitAnim] 关闭")
    end
end

---@return boolean
function RecruitAnim.handleInput(dx, dy)
    if state.phase == "idle" then return false end
    if lastRevealT_ == time.elapsedTime then return true end
    if state.phase == "intro" or (state.phase == "cards" and not cardsReady()) then
        -- 首次点击仅跳到完整结果，不关闭、不重抽，不可能误点尚未显示的继续按钮。
        revealAll()
        return true
    end
    if state.phase == "cards" then
        if againFn_ and math.abs(dx - DESIGN_W * 0.5) <= 240
            and math.abs(dy - (DESIGN_H - 230)) <= 44 then
            lastInputWasRepeat_ = true
            againFn_(state.pullCount, state.poolId)
            -- 单机回执可同步start；在回调返回后重新设置同事件返回条屏障。
            lastInputWasRepeat_ = true
            lastRepeatT_ = time.elapsedTime
            return true
        end
        lastInputWasRepeat_ = false
        state.phase = "fadeOut"
        state.fadeOutStartT = time.elapsedTime
    end
    return true
end

--- 中缝返回会与同一次输入路由连续调用；重复招募/跳过不能被顺手再关闭。
---@return boolean 是否消费
function RecruitAnim.dismiss()
    if (lastInputWasRepeat_ and lastRepeatT_ == time.elapsedTime) or lastRevealT_ == time.elapsedTime then return false end
    lastInputWasRepeat_ = false
    if state.phase == "intro" or (state.phase == "cards" and not cardsReady()) then
        revealAll()
        return true
    end
    if state.phase ~= "cards" then return false end
    state.phase = "fadeOut"
    state.fadeOutStartT = time.elapsedTime
    return true
end

function RecruitAnim.close()
    state.fadeOutStartT = 0
    state.phase = "idle"
    state.results = {}
    lastInputWasRepeat_ = false
    notifyClosed()
    print("[RecruitAnim] 关闭")
end

-- Stop只取消表现，不触发剧情或刷新已销毁的宿主。
function RecruitAnim.destroy()
    state.phase, state.results, state.onClose = "idle", {}, nil
    closeCallbacks_ = {}
    lastInputWasRepeat_ = false
    Presentation.destroy()
    cachedVg = nil
end

-- ======================== 绘制 ========================

-- 当前帧的全局淡出透明度，供卡片绘制函数内部与自身 alpha 相乘
local _fadeAlpha = 1.0

local function drawResourceCard(vg, cx, cy, item, alpha)
    local def  = RESOURCE_DEFS[item.resType]
    local resQuality = def and def.quality or 1

    -- 无底板：只显示图标与数量

    local iconBgIdx = math.max(1, math.min(5, resQuality))
    local iconCY = cy + RES_ICON_OFFSET_Y
    DarkIcon.drawQualityBg(vg, iconBgIdx, cx, iconCY, RES_ICON_BG_W, RES_ICON_BG_H, alpha)

    local resIcon = getResIcon(vg, item.resType)
    drawImageCentered(vg, resIcon, cx, iconCY, RES_ICON_W, RES_ICON_H, alpha)

    -- 数量文本（下移10px）
    local combinedAlpha = alpha * _fadeAlpha
    nvgSave(vg)
    nvgGlobalAlpha(vg, combinedAlpha)
    local qtyText = "X" .. tostring(item.amount or 0)
    drawTextStroke(vg,
        cx, iconCY + RES_ICON_BG_H * 0.5 + 30,  -- 原20+10=30
        qtyText,
        RES_QTY_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255,
        4,
        { strokeColor = { 0, 0, 0 } }
    )

    -- [稀有度显示] 烧字徽章（R/SR/SSR/UR 图）不再显示；保留品质色卡边作隐晦标识
    -- local badgeImg = img.qualityBadge[qualityToBadgeTag(item.quality)]

    -- 资源名称（上移25px：OFFSET从44增到69）
    local resName = def and def.name or "未知"
    local nameCY = cy + CARD_H * 0.5 - RES_NAME_OFFSET_BOTTOM
    drawTextStroke(vg,
        cx, nameCY,
        resName,
        RES_NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255,
        3,
        { strokeColor = { 0, 0, 0 } }
    )
    nvgRestore(vg)
end

--- 碎片类卡片（type="shard"）：图标+角标样式（与资源卡风格一致）
local function drawShardCard(vg, cx, cy, item, alpha)
    local heroId  = item.heroId

    -- 无底板：只显示图标与数量

    -- 图标底图（按英雄品质映射：1→1, 2→3, 3→5）
    local qualityToIconBg = { [1] = 1, [2] = 3, [3] = 5 }
    local iconBgIdx = qualityToIconBg[item.quality] or 1
    iconBgIdx = math.max(1, math.min(5, iconBgIdx))
    local iconCY = cy + RES_ICON_OFFSET_Y
    DarkIcon.drawQualityBg(vg, iconBgIdx, cx, iconCY, RES_ICON_BG_W, RES_ICON_BG_H, alpha)

    -- 碎片图标：英雄头像 + 左上角碎片角标（DrawUtil 统一样式）
    DrawUtil.drawShardIcon(vg, heroId, cx, iconCY, RES_ICON_W, alpha)

    -- 数量文本
    local combinedAlpha = alpha * _fadeAlpha
    nvgSave(vg)
    nvgGlobalAlpha(vg, combinedAlpha)
    local qtyText = "X" .. tostring(item.amount or 1)
    drawTextStroke(vg,
        cx, iconCY + RES_ICON_BG_H * 0.5 + 30,
        qtyText,
        RES_QTY_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255,
        4,
        { strokeColor = { 0, 0, 0 } }
    )

    -- [稀有度显示] 烧字徽章不再显示；保留品质色卡边作隐晦标识

    nvgRestore(vg)
end

--- 重复英雄→碎片卡片（type="dupe_to_shard"）：英雄立绘 + "→碎片×10"
local function drawDupeToShardCard(vg, cx, cy, item, alpha)
    local heroId  = item.heroId
    local heroCfg = HC.get(heroId)

    -- 重复英雄仍使用同一新卡面。
    drawHeroCard(vg, heroId, cx, cy, alpha)

    -- [稀有度显示] 烧字徽章不再显示

    local combinedAlpha = alpha * _fadeAlpha
    nvgSave(vg)
    nvgGlobalAlpha(vg, combinedAlpha)

    -- "→碎片×N" 叠加条
    local labelText = "→碎片×" .. tostring(item.shardGain or 10)
    -- 半透明黑底条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 90, cy + 10, 180, 40, 8)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)
    drawTextStroke(vg,
        cx, cy + 30,
        labelText,
        28,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 200, 80,
        3,
        { strokeColor = { 0, 0, 0 } }
    )

    -- 英雄名
    local heroName = heroCfg and heroCfg.name or ("英雄" .. heroId)
    local nameCY = cy + HERO_CARD_H * 0.5 - CHAR_NAME_OFFSET_BOTTOM
    drawTextStroke(vg,
        cx, nameCY,
        heroName,
        CHAR_NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255,
        3,
        { strokeColor = { 0, 0, 0 } }
    )
    nvgRestore(vg)
end

--- 满觉醒分解卡片（type="decompose"）：英雄立绘 + "→酒馆币×N"
local function drawDecomposeCard(vg, cx, cy, item, alpha)
    local heroId  = item.heroId
    local heroCfg = HC.get(heroId)

    -- 分解英雄仍使用同一新卡面。
    drawHeroCard(vg, heroId, cx, cy, alpha)

    -- [稀有度显示] 烧字徽章不再显示

    local combinedAlpha = alpha * _fadeAlpha
    nvgSave(vg)
    nvgGlobalAlpha(vg, combinedAlpha)

    -- "→酒馆币×N" 叠加条
    local labelText = "→酒馆币×" .. tostring(item.tavernCoin or 0)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 90, cy + 10, 180, 40, 8)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)
    drawTextStroke(vg,
        cx, cy + 30,
        labelText,
        26,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 180, 60,
        3,
        { strokeColor = { 0, 0, 0 } }
    )

    -- 英雄名
    local heroName = heroCfg and heroCfg.name or ("英雄" .. heroId)
    local nameCY = cy + HERO_CARD_H * 0.5 - CHAR_NAME_OFFSET_BOTTOM
    drawTextStroke(vg,
        cx, nameCY,
        heroName,
        CHAR_NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255,
        3,
        { strokeColor = { 0, 0, 0 } }
    )
    nvgRestore(vg)
end

local function drawCharacterCard(vg, cx, cy, item, alpha)
    local heroId = item.heroId
    local heroCfg = HC.get(heroId)

    -- 新整卡自带美术边框，直接对槽绘制；不再叠加第二层品质框。
    drawHeroCard(vg, heroId, cx, cy, alpha)

    -- 角色名称（上移25px：OFFSET从44增到69）
    local combinedAlpha = alpha * _fadeAlpha
    nvgSave(vg)
    nvgGlobalAlpha(vg, combinedAlpha)
    local heroName = heroCfg and heroCfg.name or ("英雄" .. heroId)
    local nameCY = cy + HERO_CARD_H * 0.5 - CHAR_NAME_OFFSET_BOTTOM
    drawTextStroke(vg,
        cx, nameCY,
        heroName,
        CHAR_NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255,
        3,
        { strokeColor = { 0, 0, 0 } }
    )

    if heroCfg then
        local classIdx = CLASS_NUM[heroCfg.classId]
        local classIconImg = classIdx and img.classIcons[classIdx]
        if classIconImg and classIconImg >= 0 then
            local classIconCY = cy - HERO_CARD_H * 0.5
            drawImageCentered(vg, classIconImg, cx, classIconCY, CLASS_ICON_W, CLASS_ICON_H, alpha)
        end
    end
    nvgRestore(vg)
end

function RecruitAnim.draw(vg)
    if state.phase == "idle" then return end

    -- =================== 全局淡出透明度 ===================
    local globalAlpha = 1.0
    if state.phase == "fadeOut" then
        local elapsed = time.elapsedTime - state.fadeOutStartT
        globalAlpha = math.max(0, 1.0 - elapsed / FADE_OUT_DURATION)
        if globalAlpha <= 0.001 then return end
    end

    _fadeAlpha = globalAlpha  -- 供卡片绘制函数内部文本使用

    nvgSave(vg)
    if globalAlpha < 1.0 then
        nvgGlobalAlpha(vg, globalAlpha)
    end

    -- =================== cards / fadeOut 阶段 ===================

    -- 背景：黑色
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg)

    local bgAlpha = 1.0

    -- 半透明黑色遮罩（在视频最后一帧上）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(210 * bgAlpha)))
    nvgFill(vg)

    -- 结果背景
    drawImageCentered(vg, img.resultBg, 540, 1200, DESIGN_W, DESIGN_H, bgAlpha * 0.72)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(8, 10, 16, math.floor(70 * bgAlpha)))
    nvgFill(vg)

    if state.phase == "intro" then
        Presentation.drawIntro(vg, time.elapsedTime - state.introStartT, state.highestQ)
    end

    -- 卡片翻牌只改变局部变换，仍使用原整卡映射和真实结果分组。
    if state.phase == "cards" or state.phase == "fadeOut" then
        local count = #state.results
        local positions = getCardPositions(count)
        for i, item in ipairs(state.results) do
            local pos = positions[i]
            local pose = Timeline.card(time.elapsedTime - state.cardStartT, i)
            if pos and pose.visible then
                local drawY = pos.y + pose.offsetY
                local cardH = resultRank(item) == 1 and HERO_CARD_H or CARD_H
                Presentation.drawCardGlow(vg, pos.x, drawY, CARD_W, cardH, item.quality, pose.glow)
                nvgSave(vg)
                nvgTranslate(vg, pos.x, drawY)
                nvgScale(vg, pose.scaleX * pose.scale, pose.scale)
                nvgTranslate(vg, -pos.x, -drawY)
                if not pose.front then
                    Presentation.drawBack(vg, pos.x, drawY, CARD_W, HERO_CARD_H, pose.alpha)
                elseif item.type == "hero" then
                    drawCharacterCard(vg, pos.x, drawY, item, pose.alpha)
                elseif item.type == "shard" then
                    drawShardCard(vg, pos.x, drawY, item, pose.alpha)
                elseif item.type == "dupe_to_shard" then
                    drawDupeToShardCard(vg, pos.x, drawY, item, pose.alpha)
                elseif item.type == "decompose" then
                    drawDecomposeCard(vg, pos.x, drawY, item, pose.alpha)
                else
                    drawResourceCard(vg, pos.x, drawY, item, pose.alpha)
                end
                nvgRestore(vg)
            end
        end
    end

    -- 继续招募仅在所有卡牌揭晓后显示，热区用同一条件。
    if state.phase == "cards" or state.phase == "fadeOut" then
        if cardsReady() and againFn_ then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 40)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
            local count = state.pullCount == 10 and 10 or 1
            local againText = (count == 10) and "继续十连" or "继续单抽"
            local stellar = state.poolId == "stellar"
            local ticketCost = stellar
                and ((count == 10) and UrGachaConfig.Cost.TEN_TICKET or UrGachaConfig.Cost.SINGLE_TICKET)
                or ((count == 10) and GachaConfig.Cost.TEN_TICKET or GachaConfig.Cost.SINGLE_TICKET)
            local gemCost = stellar
                and ((count == 10) and UrGachaConfig.Cost.TEN_DIAMOND or UrGachaConfig.Cost.SINGLE_DIAMOND)
                or ((count == 10) and GachaConfig.Cost.TEN_DIAMOND or GachaConfig.Cost.SINGLE_DIAMOND)
            local owned = stellar and GameState.getStellarRecruitTicket() or GameState.getRecruitTicket()
            local tickets = math.min(owned or 0, ticketCost)
            local gems = math.floor((ticketCost - tickets) * gemCost / ticketCost + 0.5)
            local parts = {}
            if tickets > 0 then
                parts[#parts + 1] = {
                    icon = stellar and img.ticketIconStellar or img.ticketIcon,
                    type = stellar and "stellar_ticket" or "adventure_ticket", amount = tickets,
                }
            end
            if gems > 0 or tickets <= 0 then
                parts[#parts + 1] = { icon = img.diamondIcon, type = "diamond", amount = gems }
            end
            local enough = tickets >= ticketCost or (GameState.getGems() or 0) >= gems
            RepeatDrawButton.draw(vg, DESIGN_W * 0.5, DESIGN_H - 230, 480, 88,
                againText, parts, enough)
        end
    end

    nvgRestore(vg)
    Presentation.drawLabels(vg, state.phase, cardsReady(), state.poolId, globalAlpha)
end

return RecruitAnim
