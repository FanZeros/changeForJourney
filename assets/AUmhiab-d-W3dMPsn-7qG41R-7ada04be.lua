-- ============================================================================
-- ArenaRankPage - 竞技场排名页面
-- 上部分: 全屏背景 + 标题 + 前三名展示
-- 下部分: 第4名起排名列表（可滚动）+ 当前玩家卡片（底部固定）
-- 由 ArenaPage 的排名 Tab 调用
-- ============================================================================

local GameConfig    = require("config.GameConfig")
local ArenaConfig   = require("config.ArenaConfig")
local HeroAssetUtil   = require("config.HeroAssetUtil")
local AvatarFrameUtil = require("config.AvatarFrameUtil")
local TopBar        = require("ui.TopBar")
local drawTextStroke = require("core.DrawUtil").drawTextStroke

local RankPage = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 配置 ========================

local MAX_RANK_DISPLAY = 50  -- 客户端最多显示前50名

-- ======================== 工具函数 ========================

local function drawImageCentered(vg, imgH, cx, cy, w, h, alpha)
    if imgH < 0 or alpha <= 0.01 then return end
    local x, y = cx - w * 0.5, cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, imgH, alpha)
    nvgBeginPath(vg); nvgRect(vg, x, y, w, h); nvgFillPaint(vg, paint); nvgFill(vg)
end

-- ======================== 布局常量（上部分） ========================

-- 全屏背景
local BG = { CX = 540, CY = 1200, W = 1080, H = 2400 }

-- 标题 "竞技排行榜"
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

-- 第1名布局
local TOP1 = {
    BG_CX = 540, BG_CY = 495, BG_W = 322, BG_H = 511,
    TROPHY_CX = 540, TROPHY_CY = 251,
    NUM_CX = 540, NUM_CY = 246,
    AV_CX = 540, AV_CY = 396,
    NAME_CX = 540, NAME_CY = 501,
    LABEL_CX = 540, LABEL_CY = 592,
    TIER_CX = 540, TIER_CY = 644,
}

-- 第2名布局
local TOP2 = {
    BG_CX = 199, BG_CY = 518, BG_W = 322, BG_H = 511,
    TROPHY_CX = 199, TROPHY_CY = 251,
    NUM_CX = 199, NUM_CY = 246,
    AV_CX = 199, AV_CY = 396,
    NAME_CX = 199, NAME_CY = 501,
    LABEL_CX = 199, LABEL_CY = 592,
    TIER_CX = 199, TIER_CY = 644,
}

-- 第3名布局
local TOP3 = {
    BG_CX = 881, BG_CY = 518, BG_W = 322, BG_H = 511,
    TROPHY_CX = 881, TROPHY_CY = 251,
    NUM_CX = 881, NUM_CY = 246,
    AV_CX = 881, AV_CY = 396,
    NAME_CX = 881, NAME_CY = 501,
    LABEL_CX = 881, LABEL_CY = 592,
    TIER_CX = 881, TIER_CY = 644,
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

-- ======================== 布局常量（下部分 - 第4名起列表） ========================

local LIST = {
    -- 卡片背景
    BG_CX = 540, BG_CY1 = 886, BG_W = 1010, BG_H = 170,
    GAP = 14,
    STEP = 184,       -- 170 + 14

    -- 排名数字
    RANK_CX = 112,
    RANK_FONT = 68, RANK_SW = 7,
    RANK_R = 0xF8, RANK_G = 0xE1, RANK_B = 0x60,
    RANK_SR = 0x31, RANK_SG = 0x24, RANK_SB = 0x24,

    -- 头像
    AV_CX = 298, AV_W = 128, AV_H = 128, AV_R = 16,

    -- 名称（左对齐）
    NAME_X = 387,
    NAME_FONT = 38, NAME_SW = 6,
    NAME_SR = 0x23, NAME_SG = 0x23, NAME_SB = 0x23,

    -- "当前段位"标签（相对卡片CY的偏移）
    TIER_LABEL_CX = 883,
    TIER_LABEL_DY = -37,     -- 849 - 886 = -37
    TIER_LABEL_FONT = 34,
    TIER_LABEL_A = 102,      -- 40% opacity

    -- 段位背景圆角矩形
    TIER_BG_CX = 883,
    TIER_BG_DY = 25,         -- 911 - 886 = +25
    TIER_BG_W = 240, TIER_BG_H = 72, TIER_BG_R = 20,
    TIER_BG_A = 26,          -- 10% opacity

    -- 段位名称
    TIER_CX = 883,
    TIER_DY = 25,
    TIER_FONT = 38, TIER_SW = 6,
    TIER_R = 0xFF, TIER_G = 0xF6, TIER_B = 0x66,
}

-- 滚动裁剪区域（全局设计坐标）
local CLIP = {
    TOP = 801,               -- BG_CY1 - BG_H/2 = 886 - 85
    BOT = 1936,              -- SELF.CY - SELF.H/2 - 14 间隔
}
CLIP.H = CLIP.BOT - CLIP.TOP

-- ======================== 布局常量（当前玩家卡片 - 底部固定） ========================

local SELF = {
    CX = 540, CY = 2039,
    W = 1010, H = 178,
    SCALE_W = 1010 / 1010,   -- 1.0（与列表卡片等宽，避免超出面板边界）
    SCALE_H = 178 / 170,     -- ≈ 1.047
}

-- 未上榜配置
local UNRANKED = {
    TEXT = "未上榜",
    FONT = 40,
}

-- ======================== 图片句柄 ========================

local img = {
    bg      = -1,   -- UI_PHB_BJ.png
    top     = {},   -- UI_PHBTOP1~3.png (前三名背景)
    trophy  = {},   -- ICON_PHB_TOP1~3.png (奖杯)
    tier    = {},   -- ICON_DW_1~8.png (段位图标，备用)
    listBg  = -1,   -- UI_PHB_1.png (列表卡片背景)
    heroIcons = {},  -- 角色头像图标
    frameIcons = {},  -- [frameId] 头像框
}

-- ======================== 滚动状态 ========================

local scroll = {
    y       = 0,
    dragging = false,
    lastY    = 0,
    maxY     = 0,
}

-- ======================== 重置滚动 ========================

function RankPage.resetScroll()
    scroll.y = 0
    scroll.dragging = false
end

-- ======================== 初始化 ========================

function RankPage.init(vg)
    img.bg = nvgCreateImage(vg, "image/UI_PHB_BJ.png", 0)
    img.listBg = nvgCreateImage(vg, "image/UI_PHB_1.png", 0)
    for i = 1, 3 do
        img.top[i]    = nvgCreateImage(vg, "image/UI_PHBTOP" .. i .. ".png", 0)
        img.trophy[i] = nvgCreateImage(vg, "image/ICON_PHB_TOP" .. i .. ".png", 0)
    end
    for i = 1, 8 do
        img.tier[i] = nvgCreateImage(vg, "image/ICON_DW_" .. i .. ".png", 0)
    end
    HeroAssetUtil.preloadIcons(vg, img.heroIcons)
    AvatarFrameUtil.preloadFrames(vg, img.frameIcons)
    print("[ArenaRankPage] init OK")
end

-- ======================== 全屏背景 ========================

function RankPage.drawBackground(vg, progress)
    drawImageCentered(vg, img.bg, BG.CX, BG.CY, BG.W, BG.H, progress)
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
    -- 始终先画灰色底作为底层背景
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
    -- 头像框覆盖层
    local avatarFrameId = (data and data.avatarFrameId) or 1
    local frameImg = AvatarFrameUtil.getIconHandle(img.frameIcons, avatarFrameId)
    drawImageCentered(vg, frameImg, layout.AV_CX, layout.AV_CY, 160, 160, 1.0)

    local name = (data and data.name) or "虚位以待"
    drawTextStroke(vg, layout.NAME_CX, layout.NAME_CY, name,
        CARD.NAME_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, CARD.NAME_SW,
        { strokeColor = { 0, 0, 0 } })

    nvgFontFace(vg, "sans"); nvgFontSize(vg, CARD.TIER_LABEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, CARD.TIER_LABEL_A))
    nvgText(vg, layout.LABEL_CX, layout.LABEL_CY, "当前段位", nil)

    local tierName = (data and data.tierName) or "未知"
    nvgFontFace(vg, "sans"); nvgFontSize(vg, CARD.TIER_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(CARD.TIER_R, CARD.TIER_G, CARD.TIER_B, 255))
    nvgText(vg, layout.TIER_CX, layout.TIER_CY, "- " .. tierName .. " -", nil)
end

-- ======================== 列表卡片（第4名起） ========================

--- 绘制一张列表排名卡片
--- @param vg any
--- @param cy number 卡片中心Y（全局设计坐标）
--- @param rankNum number|string 排名数字或文本
--- @param name string 玩家名称
--- @param tierName string 段位名称
--- @param bgW number 背景宽度
--- @param bgH number 背景高度
--- @param scale number 缩放因子（1.0=普通卡片）
--- @param isUnranked boolean 是否未上榜
local function drawListCard(vg, cy, rankNum, name, tierName, bgW, bgH, scale, isUnranked, avatarHeroId, avatarFrameId)
    local cx = LIST.BG_CX

    -- 背景
    drawImageCentered(vg, img.listBg, cx, cy, bgW, bgH, 1.0)

    -- 各子元素相对于基准卡片中心的偏移，乘以 scale
    local rankCX = cx + (LIST.RANK_CX - LIST.BG_CX) * scale
    local avCX   = cx + (LIST.AV_CX   - LIST.BG_CX) * scale
    local nameX  = cx + (LIST.NAME_X   - LIST.BG_CX) * scale
    local tierLabelCX = cx + (LIST.TIER_LABEL_CX - LIST.BG_CX) * scale
    local tierBgCX    = cx + (LIST.TIER_BG_CX    - LIST.BG_CX) * scale
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

    -- 头像（灰色底 → 头像图 → 头像框）
    -- 始终先画灰色底作为底层背景
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
    -- 头像框覆盖层
    local frameImg = AvatarFrameUtil.getIconHandle(img.frameIcons, avatarFrameId or 1)
    drawImageCentered(vg, frameImg, avCX, cy, 160, 160, 1.0)

    -- 玩家名称（左对齐）
    drawTextStroke(vg, nameX, cy, name,
        LIST.NAME_FONT * scale, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, LIST.NAME_SW * scale,
        { strokeColor = { LIST.NAME_SR, LIST.NAME_SG, LIST.NAME_SB } })

    -- "当前段位" 标签
    local labelY = cy + LIST.TIER_LABEL_DY * scale
    nvgFontFace(vg, "sans"); nvgFontSize(vg, LIST.TIER_LABEL_FONT * scale)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, LIST.TIER_LABEL_A))
    nvgText(vg, tierLabelCX, labelY, "当前段位", nil)

    -- 段位背景圆角矩形
    local tierBgY = cy + LIST.TIER_BG_DY * scale
    local tbW = LIST.TIER_BG_W * scale
    local tbH = LIST.TIER_BG_H * scale
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tierBgCX - tbW * 0.5, tierBgY - tbH * 0.5, tbW, tbH, LIST.TIER_BG_R * scale)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, LIST.TIER_BG_A))
    nvgFill(vg)

    -- 段位名称
    local tierY = cy + LIST.TIER_DY * scale
    drawTextStroke(vg, tierCX, tierY, "- " .. tierName .. " -",
        LIST.TIER_FONT * scale, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        LIST.TIER_R, LIST.TIER_G, LIST.TIER_B, LIST.TIER_SW * scale,
        { strokeColor = { 0, 0, 0 } })
end

-- ======================== 获取段位显示名 ========================

local function getTierDisplayName(r)
    local tierObj = ArenaConfig.getTierByScore(r.rankScore or 0)
    return tierObj and ArenaConfig.getTierDisplayName(tierObj) or "黑铁级 V"
end

-- ======================== 主绘制 ========================

--- @param vg any
--- @param rankData table 排名数据列表
--- @param myRankData table|nil 当前玩家排名数据
--- @param offsetY number 下半部分的Y偏移
function RankPage.drawContent(vg, rankData, myRankData, offsetY)
    nvgSave(vg)
    nvgTranslate(vg, 0, -offsetY)

    -- ========== 标题 ==========
    drawTextStroke(vg, TTL.X, TTL.Y, "竞技排行榜",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TTL.SW,
        { strokeColor = { 0, 0, 0 } })

    -- ========== 前三名卡片（绘制顺序 2→3→1） ==========
    local order = { 2, 3, 1 }
    for _, rank in ipairs(order) do
        local data = nil
        for _, r in ipairs(rankData) do
            if r.rank == rank then
                data = {
                    name = (r.name and r.name ~= "") and r.name or ("玩家" .. rank),
                    tierName = getTierDisplayName(r),
                    avatarHeroId = r.avatarHeroId or 1,
                    avatarFrameId = r.avatarFrameId or 1,
                }
                break
            end
        end
        -- 排行榜列表中没找到，但当前玩家排名恰好是该位置，则用自己的数据
        if not data and myRankData and myRankData.rank == rank then
            data = {
                name = (myRankData.name and myRankData.name ~= "") and myRankData.name or "我",
                tierName = getTierDisplayName(myRankData),
                avatarHeroId = myRankData.avatarHeroId or (TopBar.getAvatarHeroId and TopBar.getAvatarHeroId() or 1),
                avatarFrameId = myRankData.avatarFrameId or (TopBar.getAvatarFrameId and TopBar.getAvatarFrameId() or 1),
            }
        end
        drawTopCard(vg, TOPS[rank], rank, data)
    end

    -- ========== 第4名起排名列表（可滚动） ==========

    -- 筛选第4名以后的数据（上限 MAX_RANK_DISPLAY）
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
            -- 仅绘制可见区域内的卡片（加半卡片缓冲）
            if screenCY >= CLIP.TOP - LIST.BG_H and screenCY <= CLIP.BOT + LIST.BG_H then
                local tierName = getTierDisplayName(r)
                drawListCard(vg, cy, r.rank, (r.name and r.name ~= "") and r.name or ("玩家" .. r.rank),
                    tierName, LIST.BG_W, LIST.BG_H, 1.0, false, r.avatarHeroId or 1, r.avatarFrameId or 1)
            end
        end

        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- ========== 当前玩家卡片（底部固定，不随滚动） ==========
    if myRankData then
        local myTierName = getTierDisplayName(myRankData)
        local isUnranked = (not myRankData.rank) or (myRankData.rank <= 0) or (myRankData.rank > MAX_RANK_DISPLAY)
        local displayRank = isUnranked and UNRANKED.TEXT or myRankData.rank
        local myAvatarId = myRankData.avatarHeroId or (TopBar.getAvatarHeroId and TopBar.getAvatarHeroId() or 1)
        local myFrameId = myRankData.avatarFrameId or (TopBar.getAvatarFrameId and TopBar.getAvatarFrameId() or 1)
        drawListCard(vg, SELF.CY, displayRank,
            (myRankData.name and myRankData.name ~= "") and myRankData.name or "我的角色", myTierName,
            SELF.W, SELF.H, SELF.SCALE_W, isUnranked, myAvatarId, myFrameId)
    end

    nvgRestore(vg)
end

-- ======================== 滚动/拖拽处理 ========================

--- @param dy number 设计坐标Y
--- @return boolean consumed
function RankPage.handleDragBegin(dy)
    if dy >= CLIP.TOP and dy <= CLIP.BOT then
        scroll.dragging = true
        scroll.lastY = dy
        return true
    end
    return false
end

function RankPage.handleDragMove(dy)
    if scroll.dragging then
        scroll.y = scroll.y + (scroll.lastY - dy)
        scroll.y = math.max(0, math.min(scroll.y, scroll.maxY))
        scroll.lastY = dy
        return true
    end
    return false
end

function RankPage.handleDragEnd()
    scroll.dragging = false
end

function RankPage.isDragging()
    return scroll.dragging
end

function RankPage.handleScroll(wheel)
    scroll.y = scroll.y - wheel * 60
    scroll.y = math.max(0, math.min(scroll.y, scroll.maxY))
end

return RankPage
