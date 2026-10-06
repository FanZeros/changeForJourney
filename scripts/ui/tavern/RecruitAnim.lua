-- ============================================================================
-- RecruitAnim.lua - 酒馆招募结果
-- 直接展示抽卡结果，不再播放开场 Spine。
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

-- 动画时长
local FADE_IN_DURATION   = 0.6
local CARD_FADE_DURATION = 0.5
local CARD_OFFSET_Y      = 290
local FADE_OUT_DURATION  = 0.35  -- 关闭淡出时长

-- 泛光动画
local GLOW_ANIM_DURATION = 0.35
local GLOW_SQUISH_RATIO  = 0.15

-- ======================== 资源定义（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- ======================== 状态 ========================
-- phase: "idle" → "cards" → "fadeOut" → "idle"

local state = {
    phase         = "idle",
    results       = {},
    highestQ      = 0,
    fadeStartT    = 0,
    cardStartT    = 0,
    glowStartT    = 0,
    fadeOutStartT = 0,
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
    if state.onClose then closeCallbacks_[#closeCallbacks_ + 1] = state.onClose end
    state.onClose = onClose
    state.pullCount = (count == 10 or count == 1) and count or ((#ordered > 1) and 10 or 1)
    state.poolId = poolId

    state.highestQ = 0
    for _, r in ipairs(state.results) do
        local q = r.quality or 0
        if q > state.highestQ then state.highestQ = q end
    end

    -- 直接展示抽卡结果
    state.fadeOutStartT = 0
    state.fadeStartT = time.elapsedTime
    state.cardStartT = time.elapsedTime
    state.glowStartT = time.elapsedTime
    state.phase = "cards"
    print("[RecruitAnim] start cards=" .. tostring(#state.results))
end

function RecruitAnim.isPlaying()
    return state.phase ~= "idle"
end

function RecruitAnim.update(dt)
    if state.phase == "idle" then return end

    if state.phase == "fadeIn" then
        local elapsed = time.elapsedTime - state.fadeStartT
        if elapsed >= FADE_IN_DURATION then
            state.phase = "cards"
            state.cardStartT = time.elapsedTime
            state.glowStartT = 0
        end
    end

    if state.phase == "cards" and state.glowStartT == 0 then
        local count = #state.results
        local lastDelay = (count - 1) * 0.05
        local elapsed = time.elapsedTime - state.cardStartT
        if elapsed >= lastDelay + CARD_FADE_DURATION then
            state.glowStartT = time.elapsedTime
        end
    end

    if state.phase == "fadeOut" then
        local elapsed = time.elapsedTime - state.fadeOutStartT
        if elapsed >= FADE_OUT_DURATION then
            state.glowStartT = 0
            state.phase = "idle"
            state.results = {}
            notifyClosed()
            print("[RecruitAnim] 关闭")
        end
    end
end

---@return boolean
function RecruitAnim.handleInput(dx, dy)
    if state.phase == "idle" then return false end

    if state.phase == "cards" then
        local elapsed = time.elapsedTime - state.cardStartT
        if elapsed > 0.4 and againFn_
            and math.abs(dx - DESIGN_W * 0.5) <= 240
            and math.abs(dy - (DESIGN_H - 230)) <= 44 then
            againFn_(state.pullCount or 1)
            return true
        end
        -- 点击触发淡出
        state.phase = "fadeOut"
        state.fadeOutStartT = time.elapsedTime
        return true
    end

    -- fadeIn / fadeOut 阶段消费事件但不操作
    return true
end

function RecruitAnim.close()
    state.glowStartT  = 0
    state.fadeOutStartT = 0
    state.phase = "idle"
    state.results = {}
    notifyClosed()
    print("[RecruitAnim] 关闭")
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
    if state.phase == "fadeIn" then
        local elapsed = time.elapsedTime - state.fadeStartT
        bgAlpha = math.min(1.0, elapsed / FADE_IN_DURATION)
    end

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

    -- 卡片（cards / fadeOut 阶段都绘制）
    if state.phase == "cards" or state.phase == "fadeOut" then
        local count = #state.results
        local positions = getCardPositions(count)

        for i, item in ipairs(state.results) do
            local pos = positions[i]
            if pos then
                local delay = (i - 1) * 0.05
                local elapsed = time.elapsedTime - state.cardStartT - delay
                local t = math.max(0, math.min(1.0, elapsed / CARD_FADE_DURATION))

                if t > 0.001 then
                    local eased = easeOutCubic(t)
                    local drawY = pos.y + CARD_OFFSET_Y * (1.0 - eased)
                    local thisAlpha = eased

                    if item.type == "hero" then
                        drawCharacterCard(vg, pos.x, drawY, item, thisAlpha)
                    elseif item.type == "shard" then
                        drawShardCard(vg, pos.x, drawY, item, thisAlpha)
                    elseif item.type == "dupe_to_shard" then
                        drawDupeToShardCard(vg, pos.x, drawY, item, thisAlpha)
                    elseif item.type == "decompose" then
                        drawDecomposeCard(vg, pos.x, drawY, item, thisAlpha)
                    else
                        drawResourceCard(vg, pos.x, drawY, item, thisAlpha)
                    end
                end
            end
        end
    end

    -- 提示文本（cards 和 fadeOut 阶段都显示，跟着全局淡出）
    if state.phase == "cards" or state.phase == "fadeOut" then
        local elapsed = time.elapsedTime - state.cardStartT
        if elapsed > 0.8 then
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
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 40)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
            nvgText(vg, DESIGN_W * 0.5, DESIGN_H - 120, "点击任意处继续", nil)
        end
    end

    nvgRestore(vg)
end

return RecruitAnim
