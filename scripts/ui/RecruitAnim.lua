-- ============================================================================
-- RecruitAnim.lua - 酒馆招募动画模块
-- 负责播放 Spine 招募动画 + 展示抽卡结果
-- ============================================================================
---@diagnostic disable: undefined-global
-- nvgSpineCreate / nvgSpineRender 是引擎内置全局函数（NanoVG Spine 扩展）

local HC = require("config.HeroConfig")
local CC = require("config.ClassConfig")
local GameConfig = require("config.GameConfig")
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质框/卡底矢量绘制
local ResourceDefs = require("config.ResourceDefs")
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

local function qualityToCardTag(quality)
    return qualityToBadgeTag(quality)
end

-- [暗黑化 P2-A] 卡面品质 tag → drawQualityFrame 品质号（1粗铁 2青铜 3秘银 4符文 5黄金 6血钻）
local CARD_TAG_QUALITY = { N = 1, R = 2, SR = 3, SSR = 5, UR = 6 }

--- 品质卡底矢量绘制（替代 KP_TY_N~UR 贴图，任意拉伸、零贴图依赖）
local function drawCardBg(vg, qTag, cx, cy, w, h, alpha)
    DarkIcon.drawQualityBg(vg, CARD_TAG_QUALITY[qTag] or 1, cx, cy, w, h, alpha)
end

local function qualityToSpineAnim(quality)
    return qualityToBadgeTag(quality)
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

local CARD_W, CARD_H = 198, 438
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

-- Spine 资源
local SPINE_JSON = "image/spine/UI_SPINE_JGZM.json"

-- 泛光动画
local GLOW_ANIM_DURATION = 0.35
local GLOW_SQUISH_RATIO  = 0.15

-- ======================== 资源定义（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- ======================== 状态 ========================
-- phase: "idle" → "video" → "fadeIn" → "cards" → "fadeOut" → "idle"

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
    glowSR       = -1,
    glowSSR      = -1,
    glowUR       = -1,
    cardBg       = {},
    qualityBadge = {},
    resIconBg    = {},
    classIcons   = {},
    heroCards    = {},
    resIcons     = {},
    shardIcon    = -1,
}

local function getGlowImg(quality)
    if quality >= 4 then return img.glowUR end
    if quality >= 3 then return img.glowSSR end
    if quality >= 2 then return img.glowSR end
    return nil
end

-- Spine 动画实例（单例模式：只创建一次，通过 SetAnimation 复用）
local spineInst_       = nil   -- nvgSpineCreate 创建的实例（单例，生命周期同模块）
local spineLoaded_     = false -- 是否已成功 Load
local spinePendingAnim_ = nil  -- 待播放的动画名（懒加载标记）
local spineAnimStarted_ = false -- 本轮动画是否已通过 SetAnimation 启动（防止 update 先于 draw 误判完成）
local spineCompleted_  = false -- 动画播完标记（由 SetCompleteListener 设置）
local spineLoadFailed_ = false -- 加载失败标记（永久标记，避免反复尝试）
local spineLastT_      = 0     -- 上一帧时间戳，用于计算 dt

-- ======================== 资源管理说明 ========================
-- 1. img.heroCards / img.resIcons 作为模块级持久缓存，生命周期与模块相同。
--    禁止清空或 nvgDeleteImage（会导致共享纹理句柄泄漏）。
-- 2. spineInst_ 使用单例模式：首次 draw 时 nvgSpineCreate+Load，之后永久保留。
--    每次招募只调用 SetAnimation() 切换动画，不再反复 Create/Dispose。
--    ⚠️ 反复 Create/Dispose 会导致引擎内部 atlas 纹理泄漏 → 多次招募后卡死。

-- ======================== 工具函数 ========================

local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

local function drawImageCentered(vg, imgH, cx, cy, w, h, alpha)
    if imgH < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, imgH, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local function getHeroCardImage(vg, heroId)
    if img.heroCards[heroId] then return img.heroCards[heroId] end
    local cardImg = nvgCreateImage(vg, "image/角色卡牌/KP_YX_" .. heroId .. ".png", 0)
    img.heroCards[heroId] = cardImg
    return cardImg
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
    img.resultBg = nvgCreateImage(vg, "image/UI_XKJM.png", 0)
    img.glowSR  = nvgCreateImage(vg, "image/UI_PZG_SR.png", 0)
    img.glowSSR = nvgCreateImage(vg, "image/UI_PZG_SSR.png", 0)
    img.glowUR  = nvgCreateImage(vg, "image/UI_PZG_UR.png", 0)

    -- [暗黑化 P2-A] 卡底 KP_TY_N~UR 改由 drawCardBg 矢量绘制，贴图加载已移除
    if img.glowUR < 0 then
        img.glowUR = img.glowSSR
        print("[RecruitAnim] UI_PZG_UR missing, fallback to SSR glow")
    end
    for _, b in ipairs({ "R", "SR", "SSR", "UR" }) do
        img.qualityBadge[b] = nvgCreateImage(vg, "image/UI_PZBZ_" .. b .. ".png", 0)
    end
    -- [暗黑化 P2-A] 资源图标底 UI_icon_ZBBJ_1~6 改由 DarkIcon.drawQualityBg 绘制，贴图加载已移除
    for i = 1, 6 do
        img.classIcons[i] = nvgCreateImage(vg, "image/ICON_ZY_" .. i .. ".png", 0)
    end
    img.shardIcon = nvgCreateImage(vg, "image/ICON_SP.png", 0)
    print("[RecruitAnim] init OK")
end

function RecruitAnim.start(results, onClose)
    state.results = results or {}
    state.onClose = onClose

    state.highestQ = 0
    for _, r in ipairs(state.results) do
        local q = r.quality or 0
        if q > state.highestQ then state.highestQ = q end
    end

    -- 单例模式：不再 Dispose，仅重置播放状态标志
    -- 实例由 draw 懒加载并永久保留，通过 SetAnimation 切换动画
    spinePendingAnim_ = qualityToSpineAnim(state.highestQ)
    spineAnimStarted_ = false  -- 等 draw() 中 SetAnimation 后才允许检测完成
    spineCompleted_   = false
    spineLastT_       = time.elapsedTime
    state.fadeOutStartT = 0

    state.phase = "video"
    print("[RecruitAnim] start anim=" .. spinePendingAnim_)
end

function RecruitAnim.isPlaying()
    return state.phase ~= "idle"
end

function RecruitAnim.update(dt)
    if state.phase == "idle" then return end

    if state.phase == "video" then
        -- 主动轮询完成状态（listener 有时不触发，IsAnimationComplete 更可靠）
        -- 必须等 draw() 中 SetAnimation 执行后才检查（spineAnimStarted_），
        -- 否则单例复用时上一轮的 IsAnimationComplete=true 会立刻误触发跳转
        if spineAnimStarted_ and spineInst_ and not spineCompleted_ then
            if spineInst_:IsAnimationComplete(0) then
                spineCompleted_ = true
                print("[RecruitAnim] spine IsAnimationComplete(0)=true")
            end
        end
        -- spine 动画播完或加载失败时进入 fadeIn
        if spineCompleted_ or spineLoadFailed_ then
            state.phase = "fadeIn"
            state.fadeStartT = time.elapsedTime
            local reason = spineCompleted_ and "completed" or "load_failed"
            print("[RecruitAnim] video→fadeIn reason=" .. reason)
        end
    end

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
            -- 淡出完毕，真正关闭（不 Dispose spine 实例，单例复用）
            spinePendingAnim_ = nil
            state.glowStartT = 0
            state.phase = "idle"
            state.results = {}
            if state.onClose then
                state.onClose()
                state.onClose = nil
            end
            print("[RecruitAnim] 关闭")
        end
    end
end

---@return boolean
function RecruitAnim.handleInput(dx, dy)
    if state.phase == "idle" then return false end

    -- 视频阶段：不响应点击，不允许跳过
    if state.phase == "video" then
        return true  -- 消费事件但不操作
    end

    if state.phase == "cards" then
        -- 点击触发淡出
        state.phase = "fadeOut"
        state.fadeOutStartT = time.elapsedTime
        return true
    end

    -- fadeIn / fadeOut 阶段消费事件但不操作
    return true
end

function RecruitAnim.close()
    -- 不 Dispose spine 实例（单例复用，生命周期同模块）
    spinePendingAnim_ = nil
    spineCompleted_   = false
    state.glowStartT  = 0
    state.fadeOutStartT = 0
    state.phase = "idle"
    state.results = {}
    if state.onClose then
        state.onClose()
        state.onClose = nil
    end
    print("[RecruitAnim] 关闭")
end

-- ======================== 绘制 ========================

-- 当前帧的全局淡出透明度，供卡片绘制函数内部与自身 alpha 相乘
local _fadeAlpha = 1.0

local function drawResourceCard(vg, cx, cy, item, alpha)
    local qTag = qualityToCardTag(item.quality)
    local def  = RESOURCE_DEFS[item.resType]
    local resQuality = def and def.quality or 1

    drawCardBg(vg, qTag, cx, cy, CARD_W, CARD_H, alpha)

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

    -- 品质图标（卡底居中）
    local badgeImg = img.qualityBadge[qualityToBadgeTag(item.quality)]
    if badgeImg and badgeImg >= 0 then
        local badgeCY = cy + CARD_H * 0.5
        drawImageCentered(vg, badgeImg, cx, badgeCY, QUALITY_BADGE_W, QUALITY_BADGE_H, alpha)
    end

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
    local heroCfg = HC.get(heroId)
    local qTag    = qualityToCardTag(item.quality)

    -- 卡面背景（品质边框）[暗黑化 P2-A]
    drawCardBg(vg, qTag, cx, cy, CARD_W, CARD_H, alpha)

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

    -- 品质角标（卡底居中）
    local badgeImg = img.qualityBadge[qualityToBadgeTag(item.quality)]
    if badgeImg and badgeImg >= 0 then
        local badgeCY = cy + CARD_H * 0.5
        drawImageCentered(vg, badgeImg, cx, badgeCY, QUALITY_BADGE_W, QUALITY_BADGE_H, alpha)
    end

    -- 英雄名 + "碎片"
    local heroName = heroCfg and heroCfg.name or ("英雄" .. heroId)
    local nameCY = cy + CARD_H * 0.5 - RES_NAME_OFFSET_BOTTOM
    drawTextStroke(vg,
        cx, nameCY,
        heroName .. "-碎片",
        RES_NAME_FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255,
        3,
        { strokeColor = { 0, 0, 0 } }
    )
    nvgRestore(vg)
end

--- 重复英雄→碎片卡片（type="dupe_to_shard"）：英雄立绘 + "→碎片×10"
local function drawDupeToShardCard(vg, cx, cy, item, alpha)
    local heroId  = item.heroId
    local heroCfg = HC.get(heroId)
    local qTag    = qualityToCardTag(item.quality)

    -- 正常英雄卡
    local cardImg = getHeroCardImage(vg, heroId)
    drawCardBg(vg, qTag, cx, cy, CARD_W, CARD_H, alpha)
    drawImageCentered(vg, cardImg, cx, cy, CARD_W, CARD_H, alpha)

    -- 品质角标
    local badgeImg = img.qualityBadge[qualityToBadgeTag(item.quality)]
    if badgeImg and badgeImg >= 0 then
        drawImageCentered(vg, badgeImg, cx, cy + CARD_H * 0.5, QUALITY_BADGE_W, QUALITY_BADGE_H, alpha)
    end

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
    local nameCY = cy + CARD_H * 0.5 - CHAR_NAME_OFFSET_BOTTOM
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
    local bgTag = qualityToCardTag(item.quality)
    local bgImg   = img.cardBg[bgTag] or img.cardBg["SSR"]
    local cardImg = getHeroCardImage(vg, heroId)
    drawImageCentered(vg, bgImg, cx, cy, CARD_W, CARD_H, alpha)
    drawImageCentered(vg, cardImg, cx, cy, CARD_W, CARD_H, alpha)

    -- 品质角标
    local badgeImg = img.qualityBadge[qualityToBadgeTag(item.quality)]
    if badgeImg and badgeImg >= 0 then
        drawImageCentered(vg, badgeImg, cx, cy + CARD_H * 0.5, QUALITY_BADGE_W, QUALITY_BADGE_H, alpha)
    end

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
    local nameCY = cy + CARD_H * 0.5 - CHAR_NAME_OFFSET_BOTTOM
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
    local qTag = qualityToCardTag(item.quality)

    local cardImg = getHeroCardImage(vg, heroId)
    drawCardBg(vg, qTag, cx, cy, CARD_W, CARD_H, alpha)
    drawImageCentered(vg, cardImg, cx, cy, CARD_W, CARD_H, alpha)

    local badgeImg = img.qualityBadge[qualityToBadgeTag(item.quality)]
    if badgeImg and badgeImg >= 0 then
        local badgeCY = cy + CARD_H * 0.5
        drawImageCentered(vg, badgeImg, cx, badgeCY, QUALITY_BADGE_W, QUALITY_BADGE_H, alpha)
    end

    -- 角色名称（上移25px：OFFSET从44增到69）
    local combinedAlpha = alpha * _fadeAlpha
    nvgSave(vg)
    nvgGlobalAlpha(vg, combinedAlpha)
    local heroName = heroCfg and heroCfg.name or ("英雄" .. heroId)
    local nameCY = cy + CARD_H * 0.5 - CHAR_NAME_OFFSET_BOTTOM
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
            local classIconCY = cy - CARD_H * 0.5
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

    -- =================== 视频阶段（Spine 动画）===================
    if state.phase == "video" then
        -- 单例懒加载：首次创建并永久保留，后续只切换动画
        if spinePendingAnim_ then
            if not spineInst_ and not spineLoadFailed_ then
                -- 首次创建实例
                local inst = nvgSpineCreate(vg)
                if inst then
                    local loadOk = inst:Load(SPINE_JSON)
                    if loadOk then
                        inst:SetPremultipliedAlpha(true)
                        inst:SetDefaultMix(0)
                        inst:SetSpeed(1.0)
                        inst:SetCompleteListener(function()
                            spineCompleted_ = true
                            print("[RecruitAnim] spine CompleteListener fired")
                        end)
                        spineInst_ = inst
                        spineLoaded_ = true
                        print("[RecruitAnim] spine instance created OK")
                    else
                        inst:Dispose()
                        spineLoadFailed_ = true
                        print("[RecruitAnim] spine load FAILED path=" .. SPINE_JSON)
                    end
                else
                    spineLoadFailed_ = true
                    print("[RecruitAnim] nvgSpineCreate returned nil")
                end
            end

            -- 实例已就绪，设置新动画
            if spineInst_ then
                spineInst_:SetAnimation(0, spinePendingAnim_, false)
                spineAnimStarted_ = true  -- 允许 update() 开始检测完成状态
                spineLastT_ = time.elapsedTime
                print("[RecruitAnim] spine SetAnimation anim=" .. spinePendingAnim_)
            end
            spinePendingAnim_ = nil  -- 只触发一次
        end

        -- 黑色背景
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)

        -- 渲染 spine 动画
        if spineInst_ then
            local now = time.elapsedTime
            local dt = now - spineLastT_
            spineLastT_ = now
            if dt > 0 then
                spineInst_:Update(dt)
            end
            -- Spine Y-up → NanoVG Y-down 需要 Y 轴翻转
            -- 骨架 center = (0,0)，全屏中心 = (540, 1200)
            spineInst_:SetScale(1.0, -1.0)
            spineInst_:SetPosition(540, 1200)
            nvgSpineRender(vg, spineInst_)
        end

        nvgRestore(vg)
        return
    end

    -- =================== fadeIn / cards / fadeOut 阶段 ===================

    -- 背景：黑色（spine 动画结束后不保留帧）
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
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * bgAlpha)))
    nvgFill(vg)

    -- 结果背景
    drawImageCentered(vg, img.resultBg, 540, 1200, DESIGN_W, DESIGN_H, bgAlpha)

    -- 泛光（cards / fadeOut 阶段都绘制）
    if (state.phase == "cards" or state.phase == "fadeOut") and state.glowStartT > 0 then
        local glowElapsed = time.elapsedTime - state.glowStartT
        local gt = math.min(1.0, glowElapsed / GLOW_ANIM_DURATION)
        local glowEased = easeOutCubic(gt)
        local glowHScale = GLOW_SQUISH_RATIO + (1.0 - GLOW_SQUISH_RATIO) * glowEased
        local glowDrawH = GLOW_H * glowHScale
        local glowAlpha = glowEased

        local flashAlpha = 0
        if glowElapsed < 0.25 then
            local ft = glowElapsed / 0.25
            flashAlpha = math.max(0, 1.0 - ft * ft)
        end

        local count = #state.results
        local positions = getCardPositions(count)
        for i, item in ipairs(state.results) do
            if item.quality >= 2 then
                local pos = positions[i]
                if pos then
                    local glowImg = getGlowImg(item.quality)
                    if glowImg and glowImg >= 0 then
                        drawImageCentered(vg, glowImg, pos.x, pos.y, GLOW_W, glowDrawH, glowAlpha)

                        if flashAlpha > 0.01 then
                            nvgSave(vg)
                            nvgGlobalCompositeBlendFunc(vg, NVG_SRC_ALPHA, NVG_ONE)
                            drawImageCentered(vg, glowImg, pos.x, pos.y, GLOW_W, glowDrawH, flashAlpha)
                            nvgGlobalCompositeBlendFunc(vg, NVG_ONE, NVG_ONE_MINUS_SRC_ALPHA)
                            nvgRestore(vg)
                        end
                    end
                end
            end
        end
    end

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
            nvgText(vg, DESIGN_W * 0.5, DESIGN_H - 120, "点击任意处继续", nil)
        end
    end

    nvgRestore(vg)
end

return RecruitAnim
