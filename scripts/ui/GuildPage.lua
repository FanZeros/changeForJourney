-- ============================================================================
-- GuildPage - 冒险者公会界面
-- 从城镇页面点击冒险者公会进入的二级界面
-- 包含两个 Tab：排名 / 未开放（照搬教堂底部按钮+滑块）
-- 排名内容复制自竞技场排行榜，文本修改：
--   竞技排行榜 → 主线排行榜
--   当前段位 → 主线进度
--   段位信息 → 主线进度信息
-- ============================================================================

local GameConfig        = require("config.GameConfig")
local DrawUtil          = require("core.DrawUtil")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库
local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest
local TopBar            = require("ui.TopBar")
local BF                = require("systems.ButtonFeedback")
local Protocol          = require("shared.Protocol")
local GameState         = require("core.GameState")
local HeroAssetUtil     = require("config.HeroAssetUtil")
local AvatarFrameUtil   = require("config.AvatarFrameUtil")
local RelicPanel        = require("ui.RelicPanel")
-- Client 延迟加载，避免循环依赖（Client → GuildPage → Client）

local GuildPage = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量（建筑外壳） ========================

-- 建筑名称背景
local NAME = {
    BG_CX = 147, BG_CY = 136, BG_W = 294, BG_H = 123,
    TEXT_CX = 173, TEXT_CY = 130, FONT = 50,
}

-- 下方面板（九宫格）
local LOWER = {
    CX = 540, CY = 1371, W = 1080, H = 2058,
    IT = 200, IR = 10, IB = 200, IL = 10,
}

-- 动画常量
local ANIM_DUR   = 0.45
local CLOSE_DUR  = 0.38
local UPPER_DIST = 1200
local LOWER_DIST = 1600

-- ======================== 底部按钮+滑块（照搬教堂） ========================

local BTN_BACK = { CX = 122, CY = 2308, W = 184, H = 143 }

local TAB = {
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 410, SLIDER_H = 143,
    SI_T = 10, SI_R = 70, SI_B = 10, SI_L = 70,
    TEXT_Y = 2302, FONT = 40,
    ACT_R = 0x81, ACT_G = 0x57, ACT_B = 0x3c,
    INA_R = 255, INA_G = 255, INA_B = 255,
    ANIM_DUR = 0.35,
}

local TAB_ITEMS = {
    { name = "排名",   cx = 439, cy = 2308 },
    { name = "遗物", cx = 839, cy = 2308 },
}

-- ======================== 排名内容布局（复制自 ArenaRankPage） ========================

local MAX_RANK_DISPLAY = 50

-- 全屏排名背景
local RBG = { CX = 540, CY = 1200, W = 1080, H = 2400 }

-- 标题
local TTL = { X = 540, Y = 111, FONT = 64, SW = 6 }

-- 前三名公共参数
local CARD = {
    TROPHY_W = 160, TROPHY_H = 160,
    NUM_FONT = 38, NUM_SW = 6,
    AV_W = 128, AV_H = 128, AV_R = 16,
    NAME_FONT = 38, NAME_SW = 6,
    TIER_LABEL_FONT = 34, TIER_LABEL_A = 102,
    TIER_FONT = 38,
    TIER_R = 0xFF, TIER_G = 0xF6, TIER_B = 0x66,
}

-- 第1/2/3名布局
local TOP1 = {
    BG_CX = 540, BG_CY = 495, BG_W = 322, BG_H = 511,
    TROPHY_CX = 540, TROPHY_CY = 251, NUM_CX = 540, NUM_CY = 246,
    AV_CX = 540, AV_CY = 396, NAME_CX = 540, NAME_CY = 501,
    LABEL_CX = 540, LABEL_CY = 592, TIER_CX = 540, TIER_CY = 644,
}
local TOP2 = {
    BG_CX = 199, BG_CY = 518, BG_W = 322, BG_H = 511,
    TROPHY_CX = 199, TROPHY_CY = 251, NUM_CX = 199, NUM_CY = 246,
    AV_CX = 199, AV_CY = 396, NAME_CX = 199, NAME_CY = 501,
    LABEL_CX = 199, LABEL_CY = 592, TIER_CX = 199, TIER_CY = 644,
}
local TOP3 = {
    BG_CX = 881, BG_CY = 518, BG_W = 322, BG_H = 511,
    TROPHY_CX = 881, TROPHY_CY = 251, NUM_CX = 881, NUM_CY = 246,
    AV_CX = 881, AV_CY = 396, NAME_CX = 881, NAME_CY = 501,
    LABEL_CX = 881, LABEL_CY = 592, TIER_CX = 881, TIER_CY = 644,
}

local function applyOffset(layout)
    local dy = layout.BG_CY - TOP1.BG_CY
    layout.TROPHY_CY = TOP1.TROPHY_CY + dy
    layout.NUM_CY    = TOP1.NUM_CY + dy
    layout.AV_CY     = TOP1.AV_CY + dy
    layout.NAME_CY   = TOP1.NAME_CY + dy
    layout.LABEL_CY  = TOP1.LABEL_CY + dy
    layout.TIER_CY   = TOP1.TIER_CY + dy
end
applyOffset(TOP2)
applyOffset(TOP3)

local TOPS = { TOP1, TOP2, TOP3 }

-- 列表卡片（第4名起）
local LIST = {
    BG_CX = 540, BG_CY1 = 886, BG_W = 1010, BG_H = 170,
    GAP = 14, STEP = 184,
    RANK_CX = 112, RANK_FONT = 68, RANK_SW = 7,
    RANK_R = 0xF8, RANK_G = 0xE1, RANK_B = 0x60,
    RANK_SR = 0x31, RANK_SG = 0x24, RANK_SB = 0x24,
    AV_CX = 298, AV_W = 128, AV_H = 128, AV_R = 16,
    NAME_X = 387, NAME_FONT = 38, NAME_SW = 6,
    NAME_SR = 0x23, NAME_SG = 0x23, NAME_SB = 0x23,
    TIER_LABEL_CX = 883, TIER_LABEL_DY = -37,
    TIER_LABEL_FONT = 34, TIER_LABEL_A = 102,
    TIER_BG_CX = 883, TIER_BG_DY = 25,
    TIER_BG_W = 240, TIER_BG_H = 72, TIER_BG_R = 20, TIER_BG_A = 26,
    TIER_CX = 883, TIER_DY = 25,
    TIER_FONT = 38, TIER_SW = 6,
    TIER_R = 0xFF, TIER_G = 0xF6, TIER_B = 0x66,
}

-- 滚动裁剪区域
local CLIP = { TOP = 801, BOT = 1936 }
CLIP.H = CLIP.BOT - CLIP.TOP

-- 当前玩家卡片
local SELF = {
    CX = 540, CY = 2039, W = 1010, H = 178,
    SCALE_W = 1.0, SCALE_H = 178 / 170,
}

local UNRANKED = { TEXT = "未上榜", FONT = 40 }

-- ======================== 缓动函数 ========================

local function easeOutCubic(t) t = t - 1; return t * t * t + 1 end
local function easeInCubic(t) return t * t * t end
local function easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t
    else local f = 2 * t - 2; return 0.5 * f * f * f + 1 end
end

-- ======================== 图片句柄 ========================

local img = {
    lowerBg = -1, nameBg = -1,
    btnBack = -1, tabBg = -1, slider = -1,
    rankBg  = -1, listBg = -1,
    top     = {}, trophy = {},
    heroIcons = {}, frameIcons = {},
}

-- ======================== 状态 ========================

local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    tab = 1, tabFrom = 1, tabSwitchTime = 0,
    rankData = {}, myRankData = nil,
    rankLowerOY = 0,
}

-- ======================== 滚动状态 ========================

local scroll = {
    y = 0, dragging = false, lastY = 0, maxY = 0,
}

local function resetScroll()
    scroll.y = 0
    scroll.dragging = false
end

-- ======================== 文本自适应缩放 ========================

--- 计算适配指定最大宽度的字号（不低于 minFont）
local function fitFontSize(vg, text, maxFont, maxW, minFont)
    minFont = minFont or 20
    nvgFontSize(vg, maxFont)
    local tw = nvgTextBounds(vg, 0, 0, text, nil)
    if tw <= maxW then return maxFont end
    local fitted = math.floor(maxFont * maxW / tw)
    return math.max(minFont, fitted)
end

-- ======================== 进度显示名（替代段位显示） ========================

local function getProgressDisplayName(r)
    return r.progressName or "普通1-1"
end

-- ======================== 前三名卡片 ========================

local function drawTopCard(vg, layout, rank, data)
    drawImageCentered(vg, img.top[rank], layout.BG_CX, layout.BG_CY, layout.BG_W, layout.BG_H, 1.0)
    drawImageCentered(vg, img.trophy[rank], layout.TROPHY_CX, layout.TROPHY_CY,
        CARD.TROPHY_W, CARD.TROPHY_H, 1.0)

    drawTextStroke(vg, layout.NUM_CX, layout.NUM_CY, tostring(rank),
        CARD.NUM_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, CARD.NUM_SW,
        { strokeColor = { 0, 0, 0 } })

    -- 头像（灰色底 → 头像图 → 头像框）
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        layout.AV_CX - CARD.AV_W * 0.5, layout.AV_CY - CARD.AV_H * 0.5,
        CARD.AV_W, CARD.AV_H, CARD.AV_R)
    nvgFillColor(vg, nvgRGBA(80, 80, 80, 180))
    nvgFill(vg)
    local avatarHeroId = (data and data.avatarHeroId) or 1
    local avatarImg = img.heroIcons[avatarHeroId] or img.heroIcons[1]
    if avatarImg and avatarImg >= 0 then
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            layout.AV_CX - CARD.AV_W * 0.5, layout.AV_CY - CARD.AV_H * 0.5,
            CARD.AV_W, CARD.AV_H, CARD.AV_R)
        local paint = nvgImagePattern(vg,
            layout.AV_CX - CARD.AV_W * 0.5, layout.AV_CY - CARD.AV_H * 0.5,
            CARD.AV_W, CARD.AV_H, 0, avatarImg, 1.0)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end
    local avatarFrameId = (data and data.avatarFrameId) or 1
    local frameImg = AvatarFrameUtil.getIconHandle(img.frameIcons, avatarFrameId)
    drawImageCentered(vg, frameImg, layout.AV_CX, layout.AV_CY, 160, 160, 1.0)

    local name = (data and data.name) or "虚位以待"
    nvgFontFace(vg, "sans")
    local nameFit = fitFontSize(vg, name, CARD.NAME_FONT, layout.BG_W - 40, 22)
    drawTextStroke(vg, layout.NAME_CX, layout.NAME_CY, name,
        nameFit, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, CARD.NAME_SW,
        { strokeColor = { 0, 0, 0 } })

    nvgFontFace(vg, "sans"); nvgFontSize(vg, CARD.TIER_LABEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, CARD.TIER_LABEL_A))
    nvgText(vg, layout.LABEL_CX, layout.LABEL_CY, "主线进度", nil)

    local progressName = (data and data.tierName) or "未知"
    local tierText = "- " .. progressName .. " -"
    nvgFontFace(vg, "sans")
    local tierFit = fitFontSize(vg, tierText, CARD.TIER_FONT, layout.BG_W - 30, 20)
    nvgFontSize(vg, tierFit)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(CARD.TIER_R, CARD.TIER_G, CARD.TIER_B, 255))
    nvgText(vg, layout.TIER_CX, layout.TIER_CY, tierText, nil)
end

-- ======================== 列表卡片（第4名起） ========================

local function drawListCard(vg, cy, rankNum, name, tierName, bgW, bgH, scale, isUnranked, avatarHeroId, avatarFrameId)
    local cx = LIST.BG_CX
    drawImageCentered(vg, img.listBg, cx, cy, bgW, bgH, 1.0)

    local rankCX      = cx + (LIST.RANK_CX       - LIST.BG_CX) * scale
    local avCX        = cx + (LIST.AV_CX          - LIST.BG_CX) * scale
    local nameX       = cx + (LIST.NAME_X         - LIST.BG_CX) * scale
    local tierLabelCX = cx + (LIST.TIER_LABEL_CX  - LIST.BG_CX) * scale
    local tierBgCX    = cx + (LIST.TIER_BG_CX     - LIST.BG_CX) * scale
    local tierCX      = cx + (LIST.TIER_CX        - LIST.BG_CX) * scale
    local avW  = LIST.AV_W * scale
    local avH  = LIST.AV_H * scale
    local avR  = LIST.AV_R * scale

    -- 排名数字
    if isUnranked then
        drawTextStroke(vg, rankCX, cy, UNRANKED.TEXT,
            UNRANKED.FONT * scale, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, LIST.RANK_SW * scale,
            { strokeColor = { LIST.RANK_SR, LIST.RANK_SG, LIST.RANK_SB } })
    else
        drawTextStroke(vg, rankCX, cy, tostring(rankNum),
            LIST.RANK_FONT * scale, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            LIST.RANK_R, LIST.RANK_G, LIST.RANK_B, LIST.RANK_SW * scale,
            { strokeColor = { LIST.RANK_SR, LIST.RANK_SG, LIST.RANK_SB } })
    end

    -- 头像
    nvgBeginPath(vg)
    nvgRoundedRect(vg, avCX - avW * 0.5, cy - avH * 0.5, avW, avH, avR)
    nvgFillColor(vg, nvgRGBA(80, 80, 80, 180))
    nvgFill(vg)
    local hId = avatarHeroId or 1
    local avatarImg = img.heroIcons[hId] or img.heroIcons[1]
    if avatarImg and avatarImg >= 0 then
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, avCX - avW * 0.5, cy - avH * 0.5, avW, avH, avR)
        local paint = nvgImagePattern(vg, avCX - avW * 0.5, cy - avH * 0.5,
            avW, avH, 0, avatarImg, 1.0)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end
    local frameImg = AvatarFrameUtil.getIconHandle(img.frameIcons, avatarFrameId or 1)
    drawImageCentered(vg, frameImg, avCX, cy, 160, 160, 1.0)

    -- 玩家名称（自适应缩放）
    local nameMaxW = (tierLabelCX - LIST.TIER_BG_W * 0.5 * scale - nameX - 10 * scale)
    nvgFontFace(vg, "sans")
    local listNameFit = fitFontSize(vg, name, LIST.NAME_FONT * scale, nameMaxW, 22 * scale)
    drawTextStroke(vg, nameX, cy, name,
        listNameFit, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, LIST.NAME_SW * scale,
        { strokeColor = { LIST.NAME_SR, LIST.NAME_SG, LIST.NAME_SB } })

    -- "主线进度" 标签
    local labelY = cy + LIST.TIER_LABEL_DY * scale
    nvgFontFace(vg, "sans"); nvgFontSize(vg, LIST.TIER_LABEL_FONT * scale)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, LIST.TIER_LABEL_A))
    nvgText(vg, tierLabelCX, labelY, "主线进度", nil)

    -- 进度背景圆角矩形
    local tierBgY = cy + LIST.TIER_BG_DY * scale
    local tbW = LIST.TIER_BG_W * scale
    local tbH = LIST.TIER_BG_H * scale
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tierBgCX - tbW * 0.5, tierBgY - tbH * 0.5, tbW, tbH, LIST.TIER_BG_R * scale)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, LIST.TIER_BG_A))
    nvgFill(vg)

    -- 主线进度信息（自适应缩放）
    local tierY = cy + LIST.TIER_DY * scale
    local listTierText = "- " .. tierName .. " -"
    nvgFontFace(vg, "sans")
    local listTierFit = fitFontSize(vg, listTierText, LIST.TIER_FONT * scale, tbW - 16 * scale, 20 * scale)
    drawTextStroke(vg, tierCX, tierY, listTierText,
        listTierFit, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        LIST.TIER_R, LIST.TIER_G, LIST.TIER_B, LIST.TIER_SW * scale,
        { strokeColor = { 0, 0, 0 } })
end

-- ======================== 排名内容绘制 ========================

local function drawRankTabContent(vg, rankData, myRankData, offsetY)
    nvgSave(vg)
    nvgTranslate(vg, 0, -offsetY)

    -- 标题
    drawTextStroke(vg, TTL.X, TTL.Y, "主线排行榜",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TTL.SW,
        { strokeColor = { 0, 0, 0 } })

    -- 前三名卡片（绘制顺序 2→3→1，确保第1名在最上层）
    local order = { 2, 3, 1 }
    for _, rank in ipairs(order) do
        local data = nil
        for _, r in ipairs(rankData) do
            if r.rank == rank then
                data = {
                    name = (r.name ~= "" and r.name) or ("玩家" .. rank),
                    tierName = getProgressDisplayName(r),
                    avatarHeroId = r.avatarHeroId or 1,
                    avatarFrameId = r.avatarFrameId or 1,
                }
                break
            end
        end
        if not data and myRankData and myRankData.rank == rank then
            data = {
                name = (myRankData.name ~= "" and myRankData.name) or GameState.getName() or "我",
                tierName = getProgressDisplayName(myRankData),
                avatarHeroId = myRankData.avatarHeroId
                    or (TopBar.getAvatarHeroId and TopBar.getAvatarHeroId() or 1),
                avatarFrameId = myRankData.avatarFrameId
                    or (TopBar.getAvatarFrameId and TopBar.getAvatarFrameId() or 1),
            }
        end
        drawTopCard(vg, TOPS[rank], rank, data)
    end

    -- 第4名起排名列表（可滚动）
    local listData = {}
    for _, r in ipairs(rankData) do
        if r.rank >= 4 and r.rank <= MAX_RANK_DISPLAY then
            listData[#listData + 1] = r
        end
    end
    table.sort(listData, function(a, b) return a.rank < b.rank end)

    local listCount = #listData
    if listCount > 0 then
        local totalH = listCount * LIST.STEP - LIST.GAP
        local maxScroll = math.max(0, totalH - CLIP.H)
        scroll.maxY = maxScroll
        scroll.y = math.max(0, math.min(scroll.y, maxScroll))

        nvgSave(vg)
        nvgIntersectScissor(vg, 20, CLIP.TOP, DESIGN_W - 40, CLIP.H)
        nvgTranslate(vg, 0, -scroll.y)

        for idx, r in ipairs(listData) do
            local cy = LIST.BG_CY1 + (idx - 1) * LIST.STEP
            local screenCY = cy - scroll.y
            if screenCY >= CLIP.TOP - LIST.BG_H and screenCY <= CLIP.BOT + LIST.BG_H then
                local tierName = getProgressDisplayName(r)
                drawListCard(vg, cy, r.rank, (r.name ~= "" and r.name) or ("玩家" .. r.rank),
                    tierName, LIST.BG_W, LIST.BG_H, 1.0, false, r.avatarHeroId or 1, r.avatarFrameId or 1)
            end
        end

        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- 当前玩家卡片（底部固定，不随滚动）
    if myRankData then
        local myProgressName = getProgressDisplayName(myRankData)
        local isUnranked = (not myRankData.rank) or (myRankData.rank <= 0)
            or (myRankData.rank > MAX_RANK_DISPLAY)
        local displayRank = isUnranked and UNRANKED.TEXT or myRankData.rank
        local myAvatarId = myRankData.avatarHeroId
            or (TopBar.getAvatarHeroId and TopBar.getAvatarHeroId() or 1)
        local myFrameId = myRankData.avatarFrameId
            or (TopBar.getAvatarFrameId and TopBar.getAvatarFrameId() or 1)
        drawListCard(vg, SELF.CY, displayRank,
            (myRankData.name ~= "" and myRankData.name) or GameState.getName() or "我的角色", myProgressName,
            SELF.W, SELF.H, SELF.SCALE_W, isUnranked, myAvatarId, myFrameId)
    end

    nvgRestore(vg)
end

-- ======================== 遗物内容（Tab 2） ========================

local function drawRelicContent(vg)
    RelicPanel.draw(vg)
end

--- 绘制遗物背包覆盖层（在所有 Tab 内容和底部栏之上）
local function drawRelicBagOverlay(vg)
    if state.tab == 2 and RelicPanel.isBagOpen() then
        RelicPanel.drawBagPanel(vg)
    end
end

-- ======================== Public API ========================

function GuildPage.init(vg)
    -- [暗黑化 P1-B5] 原 image/UI_TJP_1.png 贴图加载已移除（矢量绘制替代）
    img.nameBg  = nvgCreateImage(vg, "image/UI_TJP_MC.png", 0)
    img.btnBack = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    img.tabBg   = nvgCreateImage(vg, "image/UI_AN_1.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_AN_2.png 贴图加载已移除（矢量绘制替代）
    img.rankBg  = nvgCreateImage(vg, "image/UI_PHB_BJ.png", 0)
    img.listBg  = nvgCreateImage(vg, "image/UI_PHB_1.png", 0)
    for i = 1, 3 do
        img.top[i]    = nvgCreateImage(vg, "image/UI_PHBTOP" .. i .. ".png", 0)
        img.trophy[i] = nvgCreateImage(vg, "image/ICON_PHB_TOP" .. i .. ".png", 0)
    end
    HeroAssetUtil.preloadIcons(vg, img.heroIcons)
    AvatarFrameUtil.preloadFrames(vg, img.frameIcons)

    state.rankData = {}
    state.myRankData = nil

    -- 初始化遗物面板
    RelicPanel.init(vg)

    print("[GuildPage] init OK")
end

function GuildPage.open()
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.tab = 1
    state.tabFrom = 1
    state.tabSwitchTime = 0
    resetScroll()
    -- 向服务端请求排行榜数据（延迟 require 避免循环依赖）
    require("network.Client").sendAction(Protocol.ACTION_TYPES.GUILD_ENTER, {})
    -- 通知引导系统进入公会面板
    require("systems.TutorialManager").notifyEvent("enter_panel_guild")
    print("[GuildPage] open → sent GUILD_ENTER")
end

--- 接收服务端返回的排行榜结果
---@param data table  { success, action, rankData, myRankData }
function GuildPage.onActionResult(data)
    if data.action ~= Protocol.ACTION_TYPES.GUILD_ENTER then return end
    if data.success and data.rankData then
        GuildPage.setRankData(data.rankData, data.myRankData)
        print("[GuildPage] rank data received, count=" .. #data.rankData)
        -- 客户端批量查询昵称（走 Lobby 服务器，能查到任意用户包括离线玩家）
        local uids = {}
        for _, r in ipairs(data.rankData) do
            if r.uid then
                uids[#uids + 1] = r.uid
            end
        end
        if #uids > 0 then
            GetUserNickname({
                userIds = uids,
                onSuccess = function(nicknames)
                    if not nicknames then return end
                    -- 构建 uid → nickname 映射
                    local map = {}
                    for _, info in ipairs(nicknames) do
                        if info.userId and info.nickname and info.nickname ~= "" then
                            map[info.userId] = info.nickname
                        end
                    end
                    -- 回填排行榜名称
                    for _, r in ipairs(state.rankData) do
                        if r.uid and map[r.uid] then
                            r.name = map[r.uid]
                        end
                    end
                    print("[GuildPage] nicknames resolved, count=" .. #nicknames)
                end,
            })
        end
    else
        print("[GuildPage] rank query failed: " .. tostring(data.reason))
    end
end

function GuildPage.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    print("[GuildPage] close (animate)")
end

function GuildPage.isOpen() return state.open end

function GuildPage.forceClose()
    if not state.open then return end
    print("[GuildPage] forceClose")
    state.open = false
    state.closing = false
end

function GuildPage.getAnimProgress()
    if not state.open then return 0 end
    if state.closing then
        local t = math.min(1.0, (time.elapsedTime - state.closeTime) / CLOSE_DUR)
        return 1 - easeInCubic(t)
    else
        local t = math.min(1.0, (time.elapsedTime - state.openTime) / ANIM_DUR)
        return easeOutCubic(t)
    end
end

--- 设置排名数据（由外部模块调用）
function GuildPage.setRankData(rankData, myRankData)
    state.rankData = rankData or {}
    state.myRankData = myRankData
end

-- ======================== 主绘制 ========================

function GuildPage.draw(vg)
    if not state.open then return end

    local rawT, progress, lowerProgress

    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        rawT = math.min(1.0, elapsed / CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
        lowerProgress = progress
        if rawT >= 1.0 then
            state.open = false; state.closing = false; return
        end
    else
        local elapsed = time.elapsedTime - state.openTime
        rawT = math.min(1.0, elapsed / ANIM_DUR)
        progress = easeOutCubic(rawT)
        lowerProgress = progress
    end

    local upperOY = -UPPER_DIST * (1 - progress)
    local lowerOY =  LOWER_DIST * (1 - lowerProgress)
    local overlayAlpha = math.floor(180 * progress)

    state.rankLowerOY = lowerOY

    -- 全屏遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha)); nvgFill(vg)

    local isRankTab = (state.tab == 1)

    -- Tab 切换进度
    local tabT = 1.0
    if state.tabSwitchTime > 0 then
        tabT = math.min(1.0, (time.elapsedTime - state.tabSwitchTime) / TAB.ANIM_DUR)
    end
    local tabEased = easeInOutCubic(tabT)

    -- ========== 上半部分（从上方滑入） ==========
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    local upperAlpha = 1.0
    if isRankTab and state.tabFrom ~= 1 and tabT < 1.0 then
        upperAlpha = 1 - tabEased
    elseif not isRankTab and state.tabFrom == 1 and tabT < 1.0 then
        upperAlpha = tabEased
    elseif isRankTab then
        upperAlpha = 0
    end
    if upperAlpha > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, upperAlpha)
        drawImageCentered(vg, img.nameBg, NAME.BG_CX, NAME.BG_CY, NAME.BG_W, NAME.BG_H, 1.0)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, NAME.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, NAME.TEXT_CX, NAME.TEXT_CY, "冒险者公会", nil)
        nvgRestore(vg)
    end

    nvgRestore(vg)

    -- ========== 下半部分（从下方滑入） ==========
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- 下方背景框
    DarkIcon.drawNine(vg, "plain", LOWER.CX - LOWER.W * 0.5, LOWER.CY - LOWER.H * 0.5, LOWER.W, LOWER.H)

    -- 排名 Tab 全屏背景（淡入/淡出）
    local rankBgAlpha = 0
    if isRankTab then
        if state.tabFrom == 1 or tabT >= 1.0 then
            rankBgAlpha = progress
        else
            rankBgAlpha = progress * tabEased
        end
    elseif state.tabFrom == 1 and tabT < 1.0 then
        rankBgAlpha = progress * (1 - tabEased)
    end
    if rankBgAlpha > 0.01 then
        nvgSave(vg)
        nvgTranslate(vg, 0, -lowerOY)
        drawImageCentered(vg, img.rankBg, RBG.CX, RBG.CY, RBG.W, RBG.H, rankBgAlpha)
        nvgRestore(vg)
    end

    -- ========== Tab 内容 ==========
    local tabIdx  = state.tab
    local fromIdx = state.tabFrom
    local contentClipBot = DESIGN_H - lowerOY

    local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)
    if isAnimating then
        local dir = (tabIdx > fromIdx) and 1 or -1
        local newOX = DESIGN_W * dir * (1 - tabEased)
        local oldOX = -DESIGN_W * dir * tabEased

        local clipTop = 0
        local clipH   = contentClipBot - clipTop

        nvgSave(vg); nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)

        nvgSave(vg); nvgTranslate(vg, oldOX, 0)
        if fromIdx == 1 then
            drawRankTabContent(vg, state.rankData, state.myRankData, lowerOY)
        else
            drawRelicContent(vg)
        end
        nvgRestore(vg)

        nvgSave(vg); nvgTranslate(vg, newOX, 0)
        if tabIdx == 1 then
            drawRankTabContent(vg, state.rankData, state.myRankData, lowerOY)
        else
            drawRelicContent(vg)
        end
        nvgRestore(vg)

        nvgResetScissor(vg); nvgRestore(vg)
    else
        local clipTop = 0
        local clipH   = contentClipBot - clipTop
        nvgSave(vg); nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)
        if tabIdx == 1 then
            drawRankTabContent(vg, state.rankData, state.myRankData, lowerOY)
        else
            drawRelicContent(vg)
        end
        nvgResetScissor(vg); nvgRestore(vg)
    end

    -- ========== 返回按钮 & Tab 栏（调整模式下隐藏） ==========
    local hideBottomUI = (state.tab == 2 and RelicPanel.isAdjustMode())
    if not hideBottomUI then
        local _bf_back = BF.begin(vg, "guild_back", BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H)
        drawImageCentered(vg, img.btnBack, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H, 1.0)
        BF.finish(vg, _bf_back)
        drawImageCentered(vg, img.tabBg, TAB.BG_CX, TAB.BG_CY, TAB.BG_W, TAB.BG_H, 1.0)

        -- 滑块动画
        local targetItem = TAB_ITEMS[tabIdx]
        local fromItem   = TAB_ITEMS[fromIdx]
        local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
        local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased
        DarkIcon.drawNine(vg, "btn", sliderCX - TAB.SLIDER_W * 0.5, sliderCY - TAB.SLIDER_H * 0.5, TAB.SLIDER_W, TAB.SLIDER_H, { accent = "gold" })

        -- Tab 文字
        for i, item in ipairs(TAB_ITEMS) do
            local isActive = (state.tab == i)
            nvgFontFace(vg, "sans"); nvgFontSize(vg, TAB.FONT)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if isActive then
                nvgFillColor(vg, nvgRGBA(TAB.ACT_R, TAB.ACT_G, TAB.ACT_B, 255))
            else
                nvgFillColor(vg, nvgRGBA(TAB.INA_R, TAB.INA_G, TAB.INA_B, 255))
            end
            nvgText(vg, item.cx, TAB.TEXT_Y, item.name, nil)
        end

        -- 遗物标签页角标（仅非当前 tab 时显示）
        if state.tab ~= 2 then
            local okRS, RS = pcall(require, "systems.RelicSystem")
            if okRS and RS and RS.getRelicBadgeInfo then
                local show, style = RS.getRelicBadgeInfo()
                if show then
                    local relicTab = TAB_ITEMS[2]
                    local badgeSz = 32
                    local badgeX = relicTab.cx + TAB.SLIDER_W * 0.25
                    local badgeY = TAB.TEXT_Y - TAB.SLIDER_H * 0.25
                    if style == "redDot" then
                        DarkIcon.draw(vg, "reddot", badgeX, badgeY, badgeSz, 1.0)elseif style ~= "redDot" and img.iconUp >= 0 then
                        drawImageCentered(vg, img.iconUp, badgeX, badgeY, badgeSz, badgeSz, 1.0)
                    end
                end
            end
        end

        -- 新手引导热点：遗物标签
        local _TM = require("systems.TutorialManager")
        if _TM.isActive() then
            local relicTab = TAB_ITEMS[2]
            _TM.registerHotspot("relic_tab", relicTab.cx, relicTab.cy, TAB.SLIDER_W, TAB.SLIDER_H)
        end
    end

    -- 遗物背包覆盖层（在底部 Tab 栏之上）
    drawRelicBagOverlay(vg)

    -- 遗物详情弹窗（在背包之上）
    if state.tab == 2 and RelicPanel.isDetailOpen() then
        RelicPanel.drawDetailPanel(vg)
    end

    -- 遗物洗练面板（在详情之上，最顶层）
    if state.tab == 2 and RelicPanel.isReforgeOpen() then
        RelicPanel.drawReforgePanel(vg)
    end

    -- 遗物效果总览弹窗
    if state.tab == 2 and RelicPanel.isOverviewOpen() then
        RelicPanel.drawOverviewPanel(vg)
    end

    nvgRestore(vg)  -- 下半部分 end
end

-- ======================== 输入处理 ========================

function GuildPage.handleInput(dx, dy)
    if not state.open or state.closing then return false end

    -- 遗物效果总览（模态，优先于背包）
    if state.tab == 2 and RelicPanel.isOverviewOpen() then
        return RelicPanel.handleOverviewTap(dx, dy)
    end

    -- 遗物洗练词缀说明弹窗
    if state.tab == 2 and RelicPanel.isReforgePoolOpen() then
        return RelicPanel.handleReforgePoolTap(dx, dy)
    end

    -- 遗物背包面板优先处理（覆盖层）
    if state.tab == 2 and RelicPanel.isBagOpen() then
        return RelicPanel.handleBagTap(dx, dy)
    end

    -- 返回按钮 & Tab 切换（调整模式下禁用）
    local blockBottomInput = (state.tab == 2 and RelicPanel.isAdjustMode())
    if not blockBottomInput then
        if hitTest(dx, dy, BTN_BACK.CX, BTN_BACK.CY, BTN_BACK.W, BTN_BACK.H) then
            BF.trigger("guild_back")
            GuildPage.close()
            return true
        end

        -- Tab 切换
        for i, item in ipairs(TAB_ITEMS) do
            if hitTest(dx, dy, item.cx, item.cy, TAB.SLIDER_W, TAB.SLIDER_H) then
                if state.tab ~= i then
                    state.tabFrom = state.tab
                    state.tabSwitchTime = time.elapsedTime
                    state.tab = i
                    require("systems.GameSFX").playUIMove(2)
                    resetScroll()
                    -- 切换到遗物标签时通知引导系统 & 标记遗物已读
                    if i == 2 then
                        require("systems.TutorialManager").notifyEvent("enter_relic_panel")
                        -- 标记所有遗物已查看，清除新遗物红点
                        local okRS2, RS2 = pcall(require, "systems.RelicSystem")
                        if okRS2 and RS2 and RS2.markAllSeen then
                            RS2.markAllSeen()
                        end
                        -- 刷新角标链（TownScene 建筑 → BottomNav Tab）
                        local okTS2, TS2 = pcall(require, "ui.TownScene")
                        if okTS2 and TS2 and TS2.setGuildRelicBadge then
                            local show2, style2 = RS2.getRelicBadgeInfo()
                            TS2.setGuildRelicBadge(show2, style2)
                        end
                        local okBN2, BN2 = pcall(require, "ui.BottomNav")
                        if okBN2 and BN2 and BN2.refreshTownBadge then
                            BN2.refreshTownBadge()
                        end
                    end
                    print("[GuildPage] switch tab → " .. item.name)
                end
                return true
            end
        end
    end

    -- 遗物面板内容区点击
    if state.tab == 2 then
        if RelicPanel.handleTap(dx, dy) then
            return true
        end
    end

    return true  -- 消费事件防穿透
end

function GuildPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    if state.tab == 2 and RelicPanel.isOverviewOpen() then
        return RelicPanel.handleOverviewDragBegin(dx, dy)
    end
    if state.tab == 2 and RelicPanel.isReforgePoolOpen() then
        return RelicPanel.handleReforgePoolDragBegin(dx, dy)
    end
    -- 遗物背包面板优先
    if state.tab == 2 and RelicPanel.isBagOpen() then
        return RelicPanel.handleBagDragBegin(dx, dy)
    end
    -- 遗物安装模式拖拽
    if state.tab == 2 and RelicPanel.isPlacementMode() then
        return RelicPanel.handleDragBegin(dx, dy)
    end
    -- 遗物调整模式拖拽（拖拽拾取网格遗物）
    if state.tab == 2 and RelicPanel.isAdjustMode() then
        return RelicPanel.handleAdjustDragBegin(dx, dy)
    end
    if state.tab == 1 and dy >= CLIP.TOP and dy <= CLIP.BOT then
        scroll.dragging = true
        scroll.lastY = dy
        return true
    end
    return true
end

function GuildPage.handleDragMove(dx, dy)
    if not state.open or state.closing then return false end
    if state.tab == 2 and RelicPanel.isOverviewOpen() then
        return RelicPanel.handleOverviewDragMove(dx, dy)
    end
    if state.tab == 2 and RelicPanel.isReforgePoolOpen() then
        return RelicPanel.handleReforgePoolDragMove(dx, dy)
    end
    -- 遗物背包面板优先
    if state.tab == 2 and RelicPanel.isBagOpen() then
        return RelicPanel.handleBagDragMove(dx, dy)
    end
    -- 遗物安装模式拖拽
    if state.tab == 2 and RelicPanel.isPlacementMode() then
        return RelicPanel.handleDragMove(dx, dy)
    end
    -- 遗物调整模式拖拽
    if state.tab == 2 and RelicPanel.isAdjustMode() then
        return RelicPanel.handleAdjustDragMove(dx, dy)
    end
    if scroll.dragging then
        scroll.y = scroll.y + (scroll.lastY - dy)
        scroll.y = math.max(0, math.min(scroll.y, scroll.maxY))
        scroll.lastY = dy
        return true
    end
    return true
end

function GuildPage.handleDragEnd(dx, dy)
    if not state.open or state.closing then return false end
    if state.tab == 2 and RelicPanel.isOverviewOpen() then
        return RelicPanel.handleOverviewDragEnd(dx, dy)
    end
    if state.tab == 2 and RelicPanel.isReforgePoolOpen() then
        return RelicPanel.handleReforgePoolDragEnd(dx, dy)
    end
    -- 遗物背包面板优先
    if state.tab == 2 and RelicPanel.isBagOpen() then
        return RelicPanel.handleBagDragEnd(dx, dy)
    end
    -- 遗物安装模式拖拽
    if state.tab == 2 and RelicPanel.isPlacementMode() then
        return RelicPanel.handleDragEnd(dx, dy)
    end
    -- 遗物调整模式拖拽
    if state.tab == 2 and RelicPanel.isAdjustMode() then
        return RelicPanel.handleAdjustDragEnd(dx, dy)
    end
    scroll.dragging = false
    return true
end

function GuildPage.handleScroll(wheel)
    if not state.open or state.closing then return false end
    if state.tab == 2 and RelicPanel.isOverviewOpen() then
        return RelicPanel.handleOverviewScroll(wheel)
    end
    if state.tab == 2 and RelicPanel.isReforgePoolOpen() then
        return RelicPanel.handleReforgePoolScroll(wheel)
    end
    -- 遗物背包面板优先
    if state.tab == 2 and RelicPanel.isBagOpen() then
        return RelicPanel.handleBagScroll(wheel)
    end
    if state.tab == 1 then
        scroll.y = scroll.y - wheel * 60
        scroll.y = math.max(0, math.min(scroll.y, scroll.maxY))
    end
    return true
end

return GuildPage
