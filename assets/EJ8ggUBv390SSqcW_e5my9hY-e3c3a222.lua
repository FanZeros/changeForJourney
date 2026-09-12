-- ============================================================================
-- ArenaPage - 竞技场界面（战斗页面 第一部分 + 第二部分）
-- 从城镇页面点击竞技场进入的二级界面
-- 职责：竞技场 UI 背景、资源展示、段位信息、排名列表、对战入口
-- 包含三个 Tab：商店 / 排名 / 战斗（默认战斗）
-- ============================================================================

local GameConfig = require("config.GameConfig")
local GameState  = require("core.GameState")
local CharacterPanel = require("ui.CharacterPanel")
local drawTextStroke = require("core.DrawUtil").drawTextStroke
local ArenaOpponentDialog = require("ui.ArenaOpponentDialog")
local ArenaRankRewardDialog = require("ui.ArenaRankRewardDialog")
local ArenaLogDialog = require("ui.ArenaLogDialog")
local ArenaRankPage  = require("ui.ArenaRankPage")
local ArenaShopPage  = require("ui.ArenaShopPage")
local Protocol    = require("shared.Protocol")
local ArenaConfig = require("config.ArenaConfig")
local HeroAssetUtil   = require("config.HeroAssetUtil")
local AvatarFrameUtil = require("config.AvatarFrameUtil")
local TopBar = require("ui.TopBar")
local BF = require("systems.ButtonFeedback")
-- Client 延迟加载，避免循环依赖（Client → ArenaPage → Client）

local ArenaPage = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量（合并到 table 减少 local 数量） ========================

-- 第一部分
local P1 = {
    -- 1. 竞技场背景图
    BG_CX = 540, BG_W = 1080, BG_H = 783,
    -- 2. 名称背景
    NAME_BG_CX = 147, NAME_BG_CY = 136, NAME_BG_W = 294, NAME_BG_H = 123,
    NAME_TEXT_CX = 173, NAME_TEXT_CY = 130, NAME_FONT = 50,
    -- 资源栏公共
    RES_BG_W = 170, RES_BG_H = 47, RES_BG_R = 18, RES_BG_A = 204,
    RES_FONT = 33, RES_SW = 4, RES_SR = 0x23, RES_SG = 0x23, RES_SB = 0x23,
    -- 资源1（竞技币）
    R1_BG_CX = 534, R1_BG_CY = 303,
    R1_ICON_CX = 463, R1_ICON_CY = 300, R1_ICON_W = 82, R1_ICON_H = 82,
    R1_TX = 549, R1_TY = 304,
    -- 资源2（竞技券）
    R2_BG_CX = 738, R2_BG_CY = 303,
    R2_ICON_CX = 674, R2_ICON_CY = 303, R2_ICON_W = 70, R2_ICON_H = 70,
    R2_TX = 757, R2_TY = 304,
    -- 资源3（钻石）
    R3_BG_CX = 971, R3_BG_CY = 303,
    R3_ICON_CX = 898, R3_ICON_CY = 304, R3_ICON_W = 70, R3_ICON_H = 70,
    R3_TX = 988, R3_TY = 304,
    -- 下方面板
    LOWER_CX = 540, LOWER_CY = 1371, LOWER_W = 1080, LOWER_H = 2058,
    LOWER_IT = 200, LOWER_IR = 10, LOWER_IB = 200, LOWER_IL = 10,
    -- 标题装饰
    DECO_CX = 540, DECO_CY = 497, DECO_W = 660, DECO_H = 60,
    -- 标题文字
    TITLE_CX = 540, TITLE_CY = 497, TITLE_FONT = 42,
    TITLE_R = 0x7b, TITLE_G = 0x53, TITLE_B = 0x39,
}
P1.BG_CY = P1.BG_H * 0.5

-- 第二部分
local P2 = {
    -- 1. 结算倒计时
    CD_CX = 540, CD_CY = 560, CD_FONT = 42,
    CD_LR = 0x45, CD_LG = 0x45, CD_LB = 0x45,  -- label 颜色
    CD_VR = 0xff, CD_VG = 0x2c, CD_VB = 0x2c,  -- value 颜色
    -- 2. 排名项布局
    RANK_CY1 = 697, RANK_H = 170, RANK_GAP = 27, RANK_VIS = 6,
    RANK_CX = 540, RANK_W = 1010,
    -- 排名子元素
    RK_NUM_X = 112, RK_NUM_FONT = 68, RK_NUM_SW = 7,
    RK_NUM_SR = 0x31, RK_NUM_SG = 0x24, RK_NUM_SB = 0x24,
    RK_AV_CX = 298, RK_AV_W = 128, RK_AV_H = 128,
    RK_NM_X = 385, RK_NM_YO = -24, RK_NM_FONT = 38, RK_NM_SW = 6,
    RK_PW_X = 385, RK_PW_YO = 28, RK_PW_IW = 44, RK_PW_IH = 44,
    RK_PW_FONT = 30, RK_PW_R = 0xf7, RK_PW_G = 0xfe, RK_PW_B = 0x77, RK_PW_SW = 4,
    RK_TI_CX = 785, RK_TI_W = 128, RK_TI_H = 128,
    RK_SBG_CX = 883, RK_SBG_W = 240, RK_SBG_H = 72, RK_SBG_R = 20,
    RK_SC_X = 974, RK_SC_FONT = 38,
    -- 4. 我的排名
    MY_CX = 540, MY_CY = 1889, MY_W = 1010, MY_H = 196,
    -- 5. 段位背景
    TB_CX = 230, TB_CY = 2108, TB_W = 423, TB_H = 174, TB_R = 60, TB_A = 26,
    -- 6. 段位图标
    TI_CX = 236, TI_CY = 2107, TI_W = 232, TI_H = 232,
    -- 7. 段位名
    TN_CX = 238, TN_CY = 2171, TN_FONT = 50, TN_SW = 5,
    -- 8. 对战按钮
    BB_CX = 759, BB_CY = 2108, BB_W = 570, BB_H = 148,
    -- 9. 对战文本
    BT_CX = 762, BT_CY = 2083, BT_FONT = 50, BT_SW = 5, BT_SKEW = -12,
    -- 10. 消耗图标
    CI_CX = 724, CI_CY = 2139, CI_W = 70, CI_H = 70,
    -- 11. 消耗数值
    CT_X = 782, CT_CY = 2140, CT_FONT = 40,
    CT_R = 0x64, CT_G = 0x51, CT_B = 0x29,
    -- 12. 对战记录入口按钮
    LOG_CX = 1001, LOG_CY = 497, LOG_W = 157, LOG_H = 110,
    LOG_TX = 1001, LOG_TY = 497, LOG_FONT = 38,
    LOG_TR = 0x00, LOG_TG = 0x00, LOG_TB = 0x00, LOG_TA = 191,  -- 75% opacity
}
P2.RANK_STEP = P2.RANK_H + P2.RANK_GAP  -- 197
P2.MY_SCALE  = P2.MY_W / P2.RANK_W       -- ≈1.0436
-- 裁剪区域
P2.CLIP_TOP = P2.RANK_CY1 - P2.RANK_H * 0.5  -- 612
P2.CLIP_H   = P2.RANK_VIS * P2.RANK_STEP - P2.RANK_GAP  -- 1155
P2.CLIP_BOT = P2.CLIP_TOP + P2.CLIP_H  -- 1767

-- Tab 系统（参考铁匠铺）
local TAB = {
    BACK_CX = 122, BACK_CY = 2308, BACK_W = 184, BACK_H = 143,
    BG_CX = 639, BG_CY = 2308, BG_W = 810, BG_H = 143,
    SLIDER_W = 277, SLIDER_H = 143,
    SI_T = 10, SI_R = 70, SI_B = 10, SI_L = 70,
    TEXT_Y = 2302, FONT = 40,
    ACT_R = 0x81, ACT_G = 0x57, ACT_B = 0x3c,
    INA_R = 255, INA_G = 255, INA_B = 255,
    ANIM_DUR = 0.35,
    ITEMS = {
        { name = "战斗", cx = 372, cy = 2308 },
        { name = "排名", cx = 638, cy = 2308 },
        { name = "商店", cx = 905, cy = 2308 },
    },
    MAP   = { battle = 1, rank = 2, shop = 3 },
    KEYS  = { "battle", "rank", "shop" },
}

-- ======================== 动画参数 ========================

local ANIM_DUR       = 0.45
local CLOSE_DUR      = 0.38
local UPPER_DIST     = 1200
local LOWER_DIST     = 1600

-- ======================== 缓动函数 ========================

local function easeOutCubic(t) t = t - 1; return t * t * t + 1 end
local function easeInCubic(t) return t * t * t end
local function easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t
    else local f = 2 * t - 2; return 0.5 * f * f * f + 1 end
end

-- ======================== 图片句柄 ========================

local img = {
    bg = -1, nameBg = -1, lowerBg = -1, titleDeco = -1,
    coin = -1, ticket = -1, gem = -1,
    rankBg = -1, myRankBg = -1, battleBtn = -1, powerIcon = -1,
    btnBack = -1, tabBg = -1, slider = -1, costIcon = -1, imgRedDot = -1,
    tier = {},  -- 1~8
    heroIcons = {},  -- [heroId] 角色头像图标
    frameIcons = {},  -- [frameId] 头像框
}

-- ======================== 加载状态 ========================

local LOAD_IDLE    = 0  -- 未请求
local LOAD_PENDING = 1  -- 等待服务器响应
local LOAD_OK      = 2  -- 数据已就绪
local LOAD_FAIL    = 3  -- 请求失败

-- ======================== 状态 ========================

local onCloseCallback_ = nil  -- 关闭动画完成后的回调（用于触发离场情景）
local onOpenCallback_  = nil  -- 打开动画完成后的回调（用于触发入场情景）

local state = {
    open = false, closing = false, openTime = 0, closeTime = 0,
    rankName = "黑铁场",
    tab = "battle", tabFrom = "battle", tabSwitchTime = 0,
    scrollY = 0, dragging = false, lastDragY = 0,
    tierIndex = 1, tierName = "黑铁I",
    rankData = {}, myRankData = nil,
    -- 全服排行榜（真人玩家，按段位分排序）
    globalRankData = {}, globalMyRank = nil,
    -- 服务器数据
    loadState = LOAD_IDLE,
    weekId = 0,           -- 当前周期 ID（用于计算结算倒计时）
    weekSettlement = 0,   -- 周结算数据
    weekScore = 0,        -- 周期分
    rankScore = 0,        -- 段位分
    tickets = 0,          -- 剩余竞技券
    battleHistory = {},   -- 完整对战历史（进攻+防守）
    reachedTiers = {},    -- 已到达的段位 id 集合（服务端）
    claimedTiers = {},    -- 已领取奖励的段位 id 集合（服务端）
}

-- ======================== 工具函数 ========================

local function drawImageCentered(vg, imgH, cx, cy, w, h, alpha)
    if imgH < 0 or alpha <= 0.01 then return end
    local x, y = cx - w * 0.5, cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, imgH, alpha)
    nvgBeginPath(vg); nvgRect(vg, x, y, w, h); nvgFillPaint(vg, paint); nvgFill(vg)
end

local function drawNineSlice(vg, imgH, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if imgH < 0 then return end
    local srcW, srcH = nvgImageSize(vg, imgH)
    if srcW <= 0 or srcH <= 0 then return end
    local sL, sR, sT, sB = iLeft, iRight, iTop, iBottom
    local sMW, sMH = srcW - sL - sR, srcH - sT - sB
    local dL = math.min(iLeft, dw * 0.5)
    local dR = math.min(iRight, dw * 0.5)
    local dT = math.min(iTop, dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)
    if sMW <= 0 or sMH <= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, imgH, 1.0)
        nvgBeginPath(vg); nvgRect(vg, dx, dy, dw, dh); nvgFillPaint(vg, paint); nvgFill(vg)
        return
    end
    local ix0 = math.floor(dx + 0.5)
    local iy0 = math.floor(dy + 0.5)
    local ix1 = math.floor(dx + dL + 0.5)
    local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5)
    local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5)
    local iy3 = math.floor(dy + dh + 0.5)
    local OV = 1
    local patches = {
        { ix1-OV, iy1-OV, ix2-ix1+OV*2, iy2-iy1+OV*2, sL, sT, sMW, sMH },
        { ix1-OV, iy0,    ix2-ix1+OV*2, iy1-iy0+OV,   sL, 0,  sMW, sT  },
        { ix1-OV, iy2-OV, ix2-ix1+OV*2, iy3-iy2+OV,   sL, sT+sMH, sMW, sB  },
        { ix0,    iy1-OV, ix1-ix0+OV,   iy2-iy1+OV*2, 0,  sT, sL,  sMH },
        { ix2-OV, iy1-OV, ix3-ix2+OV,   iy2-iy1+OV*2, sL+sMW, sT, sR, sMH },
        { ix0,    iy0,    ix1-ix0+OV, iy1-iy0+OV, 0,      0,      sL, sT },
        { ix2-OV, iy0,    ix3-ix2+OV, iy1-iy0+OV, sL+sMW, 0,      sR, sT },
        { ix0,    iy2-OV, ix1-ix0+OV, iy3-iy2+OV, 0,      sT+sMH, sL, sB },
        { ix2-OV, iy2-OV, ix3-ix2+OV, iy3-iy2+OV, sL+sMW, sT+sMH, sR, sB },
    }
    nvgShapeAntiAlias(vg, 0)
    for _, p in ipairs(patches) do
        local px, py, pw, ph = p[1], p[2], p[3], p[4]
        local sx, sy, sw, sh = p[5], p[6], p[7], p[8]
        if pw > 0 and ph > 0 and sw > 0 and sh > 0 then
            local scX, scY = pw / sw, ph / sh
            local paint = nvgImagePattern(vg, px - sx * scX, py - sy * scY,
                srcW * scX, srcH * scY, 0, imgH, 1.0)
            nvgBeginPath(vg); nvgRect(vg, px, py, pw, ph); nvgFillPaint(vg, paint); nvgFill(vg)
        end
    end
    nvgShapeAntiAlias(vg, 1)
end

local function formatPower(val)
    if val < 10000 then return tostring(val) end
    local k = val / 1000
    if k == math.floor(k) then return string.format("%dK", k) end
    return string.format("%.1fK", k)
end

local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

-- ======================== 排名项绘制 ========================

local function drawRankItem(vg, bgImg, cx, cy, bgW, bgH, data, s)
    drawImageCentered(vg, bgImg, cx, cy, bgW, bgH, 1.0)

    -- 排名数字
    local numX = cx - (P2.RANK_CX - P2.RK_NUM_X) * s
    drawTextStroke(vg, numX, cy, tostring(data.rank),
        math.floor(P2.RK_NUM_FONT * s), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, math.floor(P2.RK_NUM_SW * s),
        { strokeColor = { P2.RK_NUM_SR, P2.RK_NUM_SG, P2.RK_NUM_SB } })

    -- 玩家头像图标（圆角矩形裁剪）
    local avCX = cx - (P2.RANK_CX - P2.RK_AV_CX) * s
    local avW, avH = math.floor(P2.RK_AV_W * s), math.floor(P2.RK_AV_H * s)
    local avR = math.floor(avW * 0.15)
    -- 始终先画灰色底作为底层背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, avCX - avW * 0.5, cy - avH * 0.5, avW, avH, avR)
    nvgFillColor(vg, nvgRGBA(80, 80, 80, 180))
    nvgFill(vg)
    local avatarHeroId = data.avatarHeroId or 1
    local avatarImg = img.heroIcons[avatarHeroId] or img.heroIcons[1]
    if avatarImg and avatarImg >= 0 then
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, avCX - avW * 0.5, cy - avH * 0.5, avW, avH, avR)
        local paint = nvgImagePattern(vg, avCX - avW * 0.5, cy - avH * 0.5, avW, avH, 0, avatarImg, 1.0)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    end
    -- 头像框覆盖层
    local avatarFrameId = data.avatarFrameId or 1
    local frameImg = AvatarFrameUtil.getIconHandle(img.frameIcons, avatarFrameId)
    drawImageCentered(vg, frameImg, avCX, cy, 160, 160, 1.0)

    -- 玩家名
    local nmX = cx - (P2.RANK_CX - P2.RK_NM_X) * s
    local nmY = cy + P2.RK_NM_YO * s
    drawTextStroke(vg, nmX, nmY, data.name,
        math.floor(P2.RK_NM_FONT * s), NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, math.floor(P2.RK_NM_SW * s),
        { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 战斗力图标+数值
    local pwX = cx - (P2.RANK_CX - P2.RK_PW_X) * s
    local pwY = cy + P2.RK_PW_YO * s
    local piW, piH = math.floor(P2.RK_PW_IW * s), math.floor(P2.RK_PW_IH * s)
    drawImageCentered(vg, img.powerIcon, pwX + piW * 0.5, pwY, piW, piH, 1.0)
    drawTextStroke(vg, pwX + piW + 4 * s, pwY, formatPower(data.power),
        math.floor(P2.RK_PW_FONT * s), NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        P2.RK_PW_R, P2.RK_PW_G, P2.RK_PW_B, math.floor(P2.RK_PW_SW * s),
        { strokeColor = { 0x23, 0x23, 0x23 } })

    -- 分数背景（先绘制，在段位图标下方）
    local sbCX = cx + (P2.RK_SBG_CX - P2.RANK_CX) * s
    local sbW, sbH = math.floor(P2.RK_SBG_W * s), math.floor(P2.RK_SBG_H * s)
    local sbR = math.floor(P2.RK_SBG_R * s)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sbCX - sbW * 0.5, cy - sbH * 0.5, sbW, sbH, sbR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
    nvgFill(vg)

    -- 小组分图标（后绘制，在分数背景上方）
    local tiCX = cx + (P2.RK_TI_CX - P2.RANK_CX) * s
    local tiW, tiH = math.floor(P2.RK_TI_W * s), math.floor(P2.RK_TI_H * s)
    if img.scoreIcon and img.scoreIcon >= 0 then
        drawImageCentered(vg, img.scoreIcon, tiCX, cy, tiW, tiH, 1.0)
    end

    -- 分数数值
    local scX = cx + (P2.RK_SC_X - P2.RANK_CX) * s
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(P2.RK_SC_FONT * s))
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, scX, cy, tostring(data.score), nil)
end

-- ======================== Public API ========================

function ArenaPage.init(vg)
    img.bg       = nvgCreateImage(vg, "image/UI_JJC_BJ1.png", 0)
    img.nameBg   = nvgCreateImage(vg, "image/UI_TJP_MC.png", 0)
    img.lowerBg  = nvgCreateImage(vg, "image/UI_TJP_1.png", 0)
    img.titleDeco = nvgCreateImage(vg, "image/UI_JJC_BTBJ.png", 0)
    img.coin     = nvgCreateImage(vg, "image/UI_icon_JJB_X.png", 0)
    img.ticket   = nvgCreateImage(vg, "image/UI_icon_JJCQ_X.png", 0)
    img.gem      = nvgCreateImage(vg, "image/UI_icon_SJ_X.png", 0)

    img.rankBg   = nvgCreateImage(vg, "image/UI_JJC_1.png", 0)
    img.myRankBg = nvgCreateImage(vg, "image/UI_JJC_2.png", 0)
    img.battleBtn = nvgCreateImage(vg, "image/UI_AN_DA.png", 0)
    img.powerIcon = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    img.btnBack  = nvgCreateImage(vg, "image/UI_AN_FH.png", 0)
    img.tabBg    = nvgCreateImage(vg, "image/UI_AN_1.png", 0)
    img.slider   = nvgCreateImage(vg, "image/UI_AN_2.png", 0)
    img.costIcon = nvgCreateImage(vg, "image/UI_icon_JJCQ_X.png", 0)

    for i = 1, 8 do
        img.tier[i] = nvgCreateImage(vg, "image/ICON_DW_" .. i .. ".png", 0)
    end
    img.scoreIcon = nvgCreateImage(vg, "image/UI_icon_JJCFS_X.png", 0)
    AvatarFrameUtil.preloadFrames(vg, img.frameIcons)

    -- 角色头像图标
    HeroAssetUtil.preloadIcons(vg, img.heroIcons)
    img.logBtn    = nvgCreateImage(vg, "image/UI_JLAN.png", 0)
    img.imgRedDot = nvgCreateImage(vg, "image/ICON_HD.png", 0)

    state.rankData = {}
    state.myRankData = nil

    ArenaOpponentDialog.init(vg)
    ArenaRankRewardDialog.init(vg)
    ArenaLogDialog.init(vg)
    ArenaRankPage.init(vg)
    ArenaShopPage.init(vg)

    print("[ArenaPage] init OK (Part1 + Part2 + Shop)")
end

function ArenaPage.open()
    state.open = true
    state.closing = false
    state.openTime = time.elapsedTime
    require("systems.GameSFX").playUIMove(1)
    state.scrollY = 0
    state.dragging = false
    state.tab = "battle"
    state.tabFrom = "battle"
    state.tabSwitchTime = 0

    -- 请求服务器数据（携带最新战斗力供服务端同步）
    state.loadState = LOAD_PENDING
    state.pendingElapsed = 0
    state.retryCount = 0
    state.rankData = {}
    state.myRankData = nil
    local myPower = CharacterPanel.getTotalPower and CharacterPanel.getTotalPower() or 0
    require("network.Client").sendAction(Protocol.ACTION_TYPES.ARENA_ENTER, {
        power = myPower,
    })
    print("[ArenaPage] 打开竞技场 → 发送 ARENA_ENTER power=" .. tostring(myPower))
end

function ArenaPage.close()
    if state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    print("[ArenaPage] 关闭竞技场（动画）")
end

--- 注册关闭动画完成后的回调（触发一次后自动清除）
function ArenaPage.setOnCloseCallback(fn)
    onCloseCallback_ = fn
end

--- 注册打开动画完成后的回调（触发一次后自动清除）
function ArenaPage.setOnOpenCallback(fn)
    onOpenCallback_ = fn
end

function ArenaPage.isOpen() return state.open end

--- 强制关闭（跳过动画，用于安全恢复 — 离开 tab4 时调用）
function ArenaPage.forceClose()
    if not state.open then return end
    print("[ArenaPage] forceClose: 跳过动画强制关闭 (closing=" .. tostring(state.closing) .. ")")
    state.open = false
    state.closing = false
end

--- 获取段位分（供外部模块如 PlayerInfoPanel 读取）
---@return number
function ArenaPage.getRankScore() return state.rankScore or 0 end

--- 获取段位索引（1~36）
---@return number
function ArenaPage.getTierIndex() return state.tierIndex or 1 end

--- 获取段位名称（如 "黑铁I"）
---@return string
function ArenaPage.getTierName() return state.tierName or "黑铁I" end

function ArenaPage.getAnimProgress()
    if not state.open then return 0 end
    if state.closing then
        local t = math.min(1.0, (time.elapsedTime - state.closeTime) / CLOSE_DUR)
        return 1 - easeInCubic(t)
    else
        local t = math.min(1.0, (time.elapsedTime - state.openTime) / ANIM_DUR)
        return easeOutCubic(t)
    end
end

local LOAD_TIMEOUT = 15  -- 请求超时秒数

function ArenaPage.update(dt)
    if not state.open then return end
    ArenaRankRewardDialog.update(dt)
    ArenaOpponentDialog.update(dt)
    ArenaLogDialog.update(dt)
    ArenaShopPage.update(dt)

    -- 请求超时检测
    if state.loadState == LOAD_PENDING then
        state.pendingElapsed = (state.pendingElapsed or 0) + dt
        if state.pendingElapsed >= LOAD_TIMEOUT then
            print("[ArenaPage] ARENA_ENTER 请求超时 (" .. LOAD_TIMEOUT .. "s)")
            state.loadState = LOAD_FAIL
            state.retryCount = (state.retryCount or 0) + 1
            state.pendingElapsed = 0
        end
    end
end

--- 处理服务器 action result（由 Client.lua 分发）
function ArenaPage.onActionResult(data)
    -- ARENA_ENTER 失败响应
    if data.success == false and state.loadState == LOAD_PENDING then
        print("[ArenaPage] ARENA_ENTER FAIL: " .. tostring(data.reason))
        state.loadState = LOAD_FAIL
        state.retryCount = (state.retryCount or 0) + 1
        return
    end

    -- ARENA_ENTER 响应：包含 rankings 字段
    if data.rankings then
        state.loadState = LOAD_OK
        state.retryCount = 0  -- 成功后重置重试计数

        -- 排名列表（服务端格式: { uid, name, weekScore, power, rank, listId, joinTime }）
        -- 转换为 UI 所需格式
        local rankings = data.rankings or {}
        local myRank = data.myRank or 0
        local myPowerLocal = CharacterPanel.getTotalPower and CharacterPanel.getTotalPower() or 0
        local uiRanks = {}
        for i, r in ipairs(rankings) do
            local isSelf = (r.rank == myRank)
            uiRanks[i] = {
                rank  = r.rank or i,
                uid   = r.uid,
                name  = (r.name and r.name ~= "") and r.name or ("玩家" .. i),
                power = isSelf and myPowerLocal or (r.power or 0),
                tier  = 1,  -- 排名列表不含个人段位分，默认图标
                score = r.weekScore or 0,
                rankScore = r.rankScore or 0,  -- 段位分（用于排名页段位显示）
                avatarHeroId = r.avatarHeroId or 1,
            }
        end
        state.rankData = uiRanks

        -- 我的排名（myRank 已在上方声明）
        local myTier = ArenaConfig.getTierByScore(data.rankScore or 0)
        -- 从排名列表中提取自己的 uid（用于对手选取时排除自己）
        local myUid = nil
        for _, r in ipairs(rankings) do
            if r.rank == myRank then
                myUid = r.uid
                break
            end
        end
        state.myRankData = {
            rank  = myRank,
            uid   = myUid,
            name  = GameState.getName() or "我的角色",
            power = CharacterPanel.getTotalPower and CharacterPanel.getTotalPower() or 0,
            tier  = myTier and myTier.icon or 1,
            score = data.weekScore or 0,
            avatarHeroId = TopBar.getAvatarHeroId and TopBar.getAvatarHeroId() or 1,
            avatarFrameId = TopBar.getAvatarFrameId and TopBar.getAvatarFrameId() or 1,
        }

        -- 段位信息
        state.tierIndex = myTier and myTier.icon or 1
        state.tierName  = data.tier or (myTier and ArenaConfig.getTierDisplayName(myTier) or "黑铁级 V")
        state.weekScore = data.weekScore or 0
        state.rankScore = data.rankScore or 0
        state.tickets   = data.tickets or 0
        -- 竞技券由 PlayerStore 代理，无需写入 GameState

        -- 周期 ID（用于计算结算倒计时）
        state.weekId = data.weekId or ArenaConfig.calcWeekId()
        state.weekSettlement = data.weekSettlement or 0

        -- 对战历史（含进攻+防守）
        state.battleHistory = data.battleHistory or {}

        -- 段位奖励领取状态（服务端权威数据）
        state.reachedTiers = data.reachedTiers or {}
        state.claimedTiers = data.claimedTiers or {}

        -- 竞技场名称：根据段位大段显示
        local rankName = myTier and myTier.major or "黑铁级"
        state.rankName = rankName .. "场"

        -- 全服排行榜（真人玩家，按段位分排序）
        local globalRankings = data.globalRankings or {}
        local uiGlobalRanks = {}
        for i, r in ipairs(globalRankings) do
            local gTier = ArenaConfig.getTierByScore(r.rankScore or 0)
            uiGlobalRanks[i] = {
                rank         = r.rank or i,
                uid          = r.uid,
                name         = (r.name and r.name ~= "") and r.name or ("玩家" .. tostring(r.uid)),
                power        = 0,  -- 全服排行榜暂不含战力
                tier         = gTier and gTier.icon or 1,
                score        = r.rankScore or 0,
                rankScore    = r.rankScore or 0,
                avatarHeroId = r.avatarHeroId or 1,
            }
        end
        state.globalRankData = uiGlobalRanks
        state.globalMyRank   = data.globalMyRank

        -- 商店已购数据
        ArenaShopPage.setPurchased(data.shopPurchased or {})

        print("[ArenaPage] ARENA_ENTER OK: rank=" .. myRank
            .. " tier=" .. state.tierName
            .. " weekScore=" .. state.weekScore
            .. " tickets=" .. state.tickets
            .. " rankings=" .. #uiRanks
            .. " globalRankings=" .. #uiGlobalRanks
            .. " globalMyRank=" .. tostring(data.globalMyRank))
        return
    end

    -- ARENA_SHOP_BUY 响应
    if data.itemId ~= nil and data.purchased ~= nil then
        ArenaShopPage.onBuyResult(data)
        return
    end

    -- ARENA_CLAIM_TIER 响应
    if data.tierId ~= nil and data.claimedTiers ~= nil then
        if data.success then
            -- 同步最新 claimedTiers 到页面 state
            state.claimedTiers = data.claimedTiers
            -- 通知 Dialog 更新本地 claimedIds（弹窗可能还开着）
            ArenaRankRewardDialog.onClaimResult(data.tierId, true, data.claimedTiers)
            -- 显示奖励弹窗
            if (data.diamond or 0) > 0 then
                print("[ArenaPage] CLAIM_TIER 成功 tierId=" .. tostring(data.tierId)
                    .. " diamond=" .. tostring(data.diamond))
                ArenaRankRewardDialog.showRewardPopup("段位奖励",
                    { { type = "diamond", amount = data.diamond } })
            end
        else
            -- 服务端拒绝：回滚 Dialog 的乐观更新
            ArenaRankRewardDialog.onClaimResult(data.tierId, false, nil)
            print("[ArenaPage] CLAIM_TIER 失败: " .. tostring(data.reason))
        end
        return
    end

    -- ARENA_BATTLE_RESULT 响应：包含 scoreChange 字段
    -- 战斗结束后重新拉取排名数据以刷新 UI
    if data.scoreChange ~= nil then
        -- 更新本地 UI 状态（竞技券由 PlayerStore 代理，无需写入 GameState）
        if data.tickets ~= nil then
            state.tickets = data.tickets
        end
        -- 触发 ARENA_ENTER 重新拉取完整排名
        print("[ArenaPage] 战斗结束 scoreChange=" .. tostring(data.scoreChange)
            .. " weekScore=" .. tostring(data.weekScore)
            .. " → 重新拉取排名")
        state.loadState = LOAD_PENDING
        state.pendingElapsed = 0
        local myPower = CharacterPanel.getTotalPower and CharacterPanel.getTotalPower() or 0
        require("network.Client").sendAction(Protocol.ACTION_TYPES.ARENA_ENTER, {
            power = myPower,
        })
        return
    end
end

-- ======================== Tab 内容绘制 ========================

local function drawBattleContent(vg)
    -- 加载中提示
    if state.loadState == LOAD_PENDING then
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
        nvgText(vg, 540, 1100, "加载中...", nil)
        return
    end
    if state.loadState == LOAD_FAIL then
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
        nvgText(vg, 540, 1080, "数据加载失败", nil)
        -- 重试按钮
        local rbW, rbH = 240, 70
        local rbX, rbY = 540 - rbW * 0.5, 1120
        local _bf_retry = BF.begin(vg, "arena_retry", 540, rbY + rbH * 0.5, rbW, rbH)
        nvgBeginPath(vg); nvgRoundedRect(vg, rbX, rbY, rbW, rbH, 12)
        nvgFillColor(vg, nvgRGBA(60, 130, 220, 220)); nvgFill(vg)
        nvgFontSize(vg, 36)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, 540, rbY + rbH * 0.5, "点击重试", nil)
        BF.finish(vg, _bf_retry)
        -- 存储按钮区域供 hit-test
        state.retryBtn = { x = rbX, y = rbY, w = rbW, h = rbH }
        return
    end

    -- 1. 结算倒计时（双色）— 根据 weekId 计算下次结算时间
    local nextSettlement = ArenaConfig.WEEK_EPOCH + (state.weekId + 1) * ArenaConfig.WEEK_SECONDS
    local remainSec = math.max(0, nextSettlement - os.time())
    local days  = math.floor(remainSec / 86400)
    local hours = math.floor((remainSec % 86400) / 3600)
    local valueText
    if days > 0 then
        valueText = days .. "天" .. hours .. "时"
    else
        local mins = math.floor((remainSec % 3600) / 60)
        valueText = hours .. "时" .. mins .. "分"
    end
    local labelText = "结算倒计时："
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, P2.CD_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local bounds = {}
    local labelW = nvgTextBounds(vg, 0, 0, labelText, nil, bounds)
    local valueW = nvgTextBounds(vg, 0, 0, valueText, nil, bounds)
    local startX = P2.CD_CX - (labelW + valueW) * 0.5

    nvgFillColor(vg, nvgRGBA(P2.CD_LR, P2.CD_LG, P2.CD_LB, 255))
    nvgText(vg, startX, P2.CD_CY, labelText, nil)
    nvgFillColor(vg, nvgRGBA(P2.CD_VR, P2.CD_VG, P2.CD_VB, 255))
    nvgText(vg, startX + labelW, P2.CD_CY, valueText, nil)

    -- 2-3. 小组排名列表（可滚动）
    local rankCount = #state.rankData
    local totalH = rankCount * P2.RANK_STEP - P2.RANK_GAP
    local maxScroll = math.max(0, totalH - P2.CLIP_H)
    state.scrollY = math.max(0, math.min(state.scrollY, maxScroll))

    nvgSave(vg)
    nvgIntersectScissor(vg, 20, P2.CLIP_TOP, DESIGN_W - 40, P2.CLIP_H)
    nvgTranslate(vg, 0, -state.scrollY)

    for i, data in ipairs(state.rankData) do
        local cy = P2.RANK_CY1 + (i - 1) * P2.RANK_STEP
        local screenCY = cy - state.scrollY
        if screenCY >= P2.CLIP_TOP - P2.RANK_H and screenCY <= P2.CLIP_BOT + P2.RANK_H then
            drawRankItem(vg, img.rankBg, P2.RANK_CX, cy, P2.RANK_W, P2.RANK_H, data, 1.0)
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 4. 我的排名
    if state.myRankData then
        drawRankItem(vg, img.myRankBg, P2.MY_CX, P2.MY_CY,
            P2.MY_W, P2.MY_H, state.myRankData, P2.MY_SCALE)
    end

    -- 5. 段位图标背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, P2.TB_CX - P2.TB_W * 0.5, P2.TB_CY - P2.TB_H * 0.5,
        P2.TB_W, P2.TB_H, P2.TB_R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, P2.TB_A))
    nvgFill(vg)

    -- 6. 大段位图标
    local tierImg = img.tier[state.tierIndex] or img.tier[1]
    if tierImg and tierImg >= 0 then
        local _bf_tier = BF.begin(vg, "arena_tier", P2.TI_CX, P2.TI_CY, P2.TI_W, P2.TI_H)
        drawImageCentered(vg, tierImg, P2.TI_CX, P2.TI_CY, P2.TI_W, P2.TI_H, 1.0)
        BF.finish(vg, _bf_tier)
    end

    -- 6.1 段位奖励红点（有未领取的段位首通奖励时显示）
    if img.imgRedDot >= 0 and ArenaPage.hasTierRewardRedDot() then
        local rdSz = 40
        drawImageCentered(vg, img.imgRedDot,
            P2.TI_CX + P2.TI_W * 0.5 - 30, P2.TI_CY - P2.TI_H * 0.5 + 30, rdSz, rdSz, 1.0)
    end

    -- 7. 段位名称
    drawTextStroke(vg, P2.TN_CX, P2.TN_CY, state.tierName,
        P2.TN_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, P2.TN_SW, { strokeColor = { 0, 0, 0 } })

    -- 8. 开始对战按钮
    local _bf_battle = BF.begin(vg, "arena_battle", P2.BB_CX, P2.BB_CY, P2.BB_W, P2.BB_H)
    drawImageCentered(vg, img.battleBtn, P2.BB_CX, P2.BB_CY, P2.BB_W, P2.BB_H, 1.0)

    -- 9. "开始对战" 斜体文本
    nvgSave(vg)
    nvgTranslate(vg, P2.BT_CX, P2.BT_CY)
    nvgSkewX(vg, math.rad(P2.BT_SKEW))
    drawTextStroke(vg, 0, 0, "开始对战",
        P2.BT_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, P2.BT_SW, { strokeColor = { 0, 0, 0 } })
    nvgRestore(vg)

    -- 10. 消耗竞技券图标
    drawImageCentered(vg, img.costIcon, P2.CI_CX, P2.CI_CY, P2.CI_W, P2.CI_H, 1.0)

    -- 11. 消耗竞技券数值
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, P2.CT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(P2.CT_R, P2.CT_G, P2.CT_B, 255))
    nvgText(vg, P2.CT_X, P2.CT_CY, "×1", nil)
    BF.finish(vg, _bf_battle)
    local _TM = require("systems.TutorialManager")
    if _TM.isActive() then _TM.registerHotspot("arena_btn_start", P2.BB_CX, P2.BB_CY, P2.BB_W, P2.BB_H) end

    -- 12. 对战记录入口按钮
    local _bf_log = BF.begin(vg, "arena_log", P2.LOG_CX, P2.LOG_CY, P2.LOG_W, P2.LOG_H)
    drawImageCentered(vg, img.logBtn, P2.LOG_CX, P2.LOG_CY, P2.LOG_W, P2.LOG_H, 1.0)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, P2.LOG_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(P2.LOG_TR, P2.LOG_TG, P2.LOG_TB, P2.LOG_TA))
    nvgText(vg, P2.LOG_TX, P2.LOG_TY, "记录", nil)
    BF.finish(vg, _bf_log)
end

local function drawShopContent(vg)
    ArenaShopPage.drawContent(vg, state.weekId)
end

local function drawRankContent(vg)
    -- 由 ArenaRankPage 绘制全服排名内容（前三名 + 列表 + 自己）
    -- 使用 globalRankData（全服真人排行榜），而非 rankData（小组排名）

    -- 构造全服"我的排名"数据
    local globalMyRD = nil
    if state.myRankData then
        globalMyRD = {
            rank         = state.globalMyRank or 0,
            name         = state.myRankData.name,
            power        = state.myRankData.power,
            tier         = state.myRankData.tier,
            score        = state.rankScore or 0,
            rankScore    = state.rankScore or 0,
            avatarHeroId = TopBar.getAvatarHeroId and TopBar.getAvatarHeroId() or 1,
            avatarFrameId = TopBar.getAvatarFrameId and TopBar.getAvatarFrameId() or 1,
        }
    end

    ArenaRankPage.drawContent(vg, state.globalRankData, globalMyRD, state.rankLowerOY or 0)
end

local TAB_DRAW = { shop = drawShopContent, rank = drawRankContent, battle = drawBattleContent }

-- ======================== 主绘制 ========================

function ArenaPage.draw(vg)
    if not state.open then return end

    local rawT, progress, lowerProgress

    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        rawT = math.min(1.0, elapsed / CLOSE_DUR)
        progress = 1 - easeInCubic(rawT)
        lowerProgress = progress
        if rawT >= 1.0 then
            state.open = false; state.closing = false
            local cb = onCloseCallback_
            onCloseCallback_ = nil
            if cb then cb() end
            return
        end
    else
        local elapsed = time.elapsedTime - state.openTime
        rawT = math.min(1.0, elapsed / ANIM_DUR)
        progress = easeOutCubic(rawT)
        lowerProgress = progress
        if rawT >= 1.0 and onOpenCallback_ then
            local cb = onOpenCallback_
            onOpenCallback_ = nil
            cb()
        end
    end

    local upperOY = -UPPER_DIST * (1 - progress)
    local lowerOY =  LOWER_DIST * (1 - lowerProgress)
    local overlayAlpha = math.floor(180 * progress)

    -- 保存 lowerOY 供 drawRankContent 反向偏移使用
    state.rankLowerOY = lowerOY

    -- 全屏遮罩
    nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha)); nvgFill(vg)

    local isRankTab = (state.tab == "rank")

    -- Tab 切换进度（提前计算，上半部分淡入淡出和下半部分内容滑动都需要）
    local tabT = 1.0
    if state.tabSwitchTime > 0 then
        tabT = math.min(1.0, (time.elapsedTime - state.tabSwitchTime) / TAB.ANIM_DUR)
    end
    local tabEased = easeInOutCubic(tabT)

    -- ========== 上半部分（从上方滑入） ==========
    nvgSave(vg)
    nvgTranslate(vg, 0, upperOY)

    -- 排名 Tab 时跳过上半部分（竞技场背景、名称、资源栏），由排名全屏背景替代
    -- Tab 切换动画期间上半部分也需要淡入/淡出
    local upperAlpha = 1.0
    if isRankTab and state.tabFrom ~= "rank" and tabT < 1.0 then
        upperAlpha = 1 - tabEased  -- 切入排名，上半部分淡出
    elseif not isRankTab and state.tabFrom == "rank" and tabT < 1.0 then
        upperAlpha = tabEased      -- 从排名切出，上半部分淡入
    elseif isRankTab then
        upperAlpha = 0             -- 已在排名Tab，不显示上半部分
    end
    if upperAlpha > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, upperAlpha)
        -- 背景图
        nvgSave(vg); nvgScissor(vg, 0, 0, DESIGN_W, DESIGN_H)
        drawImageCentered(vg, img.bg, P1.BG_CX, P1.BG_CY, P1.BG_W, P1.BG_H, 1.0)
        nvgResetScissor(vg); nvgRestore(vg)

        -- 名称背景 + 文字
        drawImageCentered(vg, img.nameBg, P1.NAME_BG_CX, P1.NAME_BG_CY, P1.NAME_BG_W, P1.NAME_BG_H, 1.0)
        nvgFontFace(vg, "sans"); nvgFontSize(vg, P1.NAME_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, P1.NAME_TEXT_CX, P1.NAME_TEXT_CY, "竞技场", nil)

        -- 资源栏绘制（3组：竞技币、竞技券、钻石）
        local resGroups = {
            { bgCX = P1.R1_BG_CX, bgCY = P1.R1_BG_CY, iCX = P1.R1_ICON_CX, iCY = P1.R1_ICON_CY,
              iW = P1.R1_ICON_W, iH = P1.R1_ICON_H, tX = P1.R1_TX, tY = P1.R1_TY,
              icon = img.coin, val = tostring(GameState.getArenaCoin()) },
            { bgCX = P1.R2_BG_CX, bgCY = P1.R2_BG_CY, iCX = P1.R2_ICON_CX, iCY = P1.R2_ICON_CY,
              iW = P1.R2_ICON_W, iH = P1.R2_ICON_H, tX = P1.R2_TX, tY = P1.R2_TY,
              icon = img.ticket, val = tostring(state.tickets or 0) },
            { bgCX = P1.R3_BG_CX, bgCY = P1.R3_BG_CY, iCX = P1.R3_ICON_CX, iCY = P1.R3_ICON_CY,
              iW = P1.R3_ICON_W, iH = P1.R3_ICON_H, tX = P1.R3_TX, tY = P1.R3_TY,
              icon = img.gem, val = tostring(GameState.getGems()) },
        }
        for _, r in ipairs(resGroups) do
            nvgBeginPath(vg)
            nvgRoundedRect(vg, r.bgCX - P1.RES_BG_W * 0.5, r.bgCY - P1.RES_BG_H * 0.5,
                P1.RES_BG_W, P1.RES_BG_H, P1.RES_BG_R)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, P1.RES_BG_A)); nvgFill(vg)
            drawImageCentered(vg, r.icon, r.iCX, r.iCY, r.iW, r.iH, 1.0)
            drawTextStroke(vg, r.tX, r.tY, r.val,
                P1.RES_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, P1.RES_SW,
                { strokeColor = { P1.RES_SR, P1.RES_SG, P1.RES_SB } })
        end
        nvgRestore(vg)  -- restore globalAlpha
    end

    nvgRestore(vg)  -- 上半部分 end

    -- ========== 下半部分（从下方滑入） ==========
    nvgSave(vg)
    nvgTranslate(vg, 0, lowerOY)

    -- 下方背景框
    drawNineSlice(vg, img.lowerBg,
        P1.LOWER_CX - P1.LOWER_W * 0.5, P1.LOWER_CY - P1.LOWER_H * 0.5,
        P1.LOWER_W, P1.LOWER_H, P1.LOWER_IT, P1.LOWER_IR, P1.LOWER_IB, P1.LOWER_IL)

    -- 排名 Tab 全屏背景（图层在下方背景框上方，标签栏下方）
    -- Tab 切换时添加淡入/淡出动画，避免背景突然出现/消失
    local rankBgAlpha = 0
    if isRankTab then
        -- 当前是排名 Tab
        if state.tabFrom == "rank" or tabT >= 1.0 then
            rankBgAlpha = progress  -- 非切换状态或同Tab，使用页面进度
        else
            rankBgAlpha = progress * tabEased  -- 从其他Tab切入排名，淡入
        end
    elseif state.tabFrom == "rank" and tabT < 1.0 then
        -- 从排名 Tab 切出，淡出
        rankBgAlpha = progress * (1 - tabEased)
    end
    if rankBgAlpha > 0.01 then
        nvgSave(vg)
        nvgTranslate(vg, 0, -lowerOY)  -- 反向偏移到全局坐标
        ArenaRankPage.drawBackground(vg, rankBgAlpha)
        nvgRestore(vg)
    end

    -- 标题装饰图（战斗tab + 商店tab 共用装饰图）
    if state.tab == "battle" or state.tab == "shop" then
        drawImageCentered(vg, img.titleDeco, P1.DECO_CX, P1.DECO_CY, P1.DECO_W, P1.DECO_H, 1.0)
    end
    -- 段位名称文字仅战斗tab显示（商店有自己的标题"竞技场商店"）
    if state.tab == "battle" then
        nvgFontFace(vg, "sans"); nvgFontSize(vg, P1.TITLE_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(P1.TITLE_R, P1.TITLE_G, P1.TITLE_B, 255))
        nvgText(vg, P1.TITLE_CX, P1.TITLE_CY, state.rankName, nil)
    end

    -- ========== Tab 内容 ==========
    local tabIdx = TAB.MAP[state.tab] or 3
    local fromIdx = TAB.MAP[state.tabFrom] or tabIdx
    -- 内容区域上下界（相对于 lower panel 本地坐标）
    -- 上界：标题装饰下方留出空间
    -- 下界：确保不超出 DESIGN_H（需减去 lowerOY 偏移量）
    local contentClipTop = 430
    local contentClipBot = math.min(DESIGN_H - lowerOY, 2300)
    local contentClipH = math.max(0, contentClipBot - contentClipTop)
    -- 水平内边距：防止内容超出面板九宫格圆角边框
    local contentClipL = 20
    local contentClipW = DESIGN_W - contentClipL * 2

    local isAnimating = (tabT < 1.0 and tabIdx ~= fromIdx)
    if isAnimating then
        local dir = (tabIdx > fromIdx) and 1 or -1
        local newOX = DESIGN_W * dir * (1 - tabEased)
        local oldOX = -DESIGN_W * dir * tabEased

        -- 裁剪区域：根据是否涉及排名 tab 调整上界
        local isRankInvolved = (state.tab == "rank" or state.tabFrom == "rank")
        local clipTop = isRankInvolved and 0 or contentClipTop
        local clipH   = contentClipBot - clipTop

        nvgSave(vg); nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)

        nvgSave(vg); nvgTranslate(vg, oldOX, 0)
        local oldFn = TAB_DRAW[state.tabFrom]
        if oldFn then oldFn(vg) end
        nvgRestore(vg)

        nvgSave(vg); nvgTranslate(vg, newOX, 0)
        local newFn = TAB_DRAW[state.tab]
        if newFn then newFn(vg) end
        nvgRestore(vg)

        nvgResetScissor(vg); nvgRestore(vg)
    else
        -- 非动画状态也需裁剪，防止开场/关闭动画期间内容溢出
        local clipTop = isRankTab and 0 or contentClipTop
        local clipH   = contentClipBot - clipTop
        nvgSave(vg); nvgScissor(vg, 0, clipTop, DESIGN_W, clipH)
        local fn = TAB_DRAW[state.tab]
        if fn then fn(vg) end
        nvgResetScissor(vg); nvgRestore(vg)
    end

    -- ========== 返回按钮 & Tab 栏 ==========
    local _bf_back = BF.begin(vg, "arena_back", TAB.BACK_CX, TAB.BACK_CY, TAB.BACK_W, TAB.BACK_H)
    drawImageCentered(vg, img.btnBack, TAB.BACK_CX, TAB.BACK_CY, TAB.BACK_W, TAB.BACK_H, 1.0)
    BF.finish(vg, _bf_back)
    drawImageCentered(vg, img.tabBg, TAB.BG_CX, TAB.BG_CY, TAB.BG_W, TAB.BG_H, 1.0)

    -- 滑块动画
    local targetItem = TAB.ITEMS[tabIdx]
    local fromItem = TAB.ITEMS[fromIdx]
    local sliderCX = fromItem.cx + (targetItem.cx - fromItem.cx) * tabEased
    local sliderCY = fromItem.cy + (targetItem.cy - fromItem.cy) * tabEased
    drawNineSlice(vg, img.slider,
        sliderCX - TAB.SLIDER_W * 0.5, sliderCY - TAB.SLIDER_H * 0.5,
        TAB.SLIDER_W, TAB.SLIDER_H, TAB.SI_T, TAB.SI_R, TAB.SI_B, TAB.SI_L)

    -- Tab 文字
    for i, item in ipairs(TAB.ITEMS) do
        local isActive = (state.tab == TAB.KEYS[i])
        nvgFontFace(vg, "sans"); nvgFontSize(vg, TAB.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(TAB.ACT_R, TAB.ACT_G, TAB.ACT_B, 255))
        else
            nvgFillColor(vg, nvgRGBA(TAB.INA_R, TAB.INA_G, TAB.INA_B, 255))
        end
        nvgText(vg, item.cx, TAB.TEXT_Y, item.name, nil)

        -- 战斗 tab（index 1）有竞技券时显示红点角标（用 state.tickets 合计值，含免费额度）
        if i == 1 and img.imgRedDot >= 0 and (state.tickets or 0) > 0 then
            local textW = nvgTextBounds(vg, 0, 0, item.name)  -- 返回单一宽度值
            local rdSz = 30
            drawImageCentered(vg, img.imgRedDot,
                item.cx + textW * 0.5 + 10, TAB.TEXT_Y - 18, rdSz, rdSz, 1.0)
        end
    end

    nvgRestore(vg)  -- 下半部分 end

    -- 选择对手弹窗
    ArenaOpponentDialog.draw(vg)

    -- 对战记录弹窗
    ArenaLogDialog.draw(vg)

    -- 段位奖励弹窗（最顶层）
    ArenaRankRewardDialog.draw(vg)
end

-- ======================== 输入处理 ========================

function ArenaPage.handleInput(dx, dy)
    if not state.open or state.closing then return false end

    -- 段位奖励弹窗优先拦截
    if ArenaRankRewardDialog.isOpen() then
        ArenaRankRewardDialog.handleInput(dx, dy)
        return true
    end

    -- 对战记录弹窗
    if ArenaLogDialog.isOpen() then
        return ArenaLogDialog.handleInput(dx, dy)
    end

    -- 选择对手弹窗优先
    if ArenaOpponentDialog.isOpen() then
        return ArenaOpponentDialog.handleInput(dx, dy)
    end

    -- 返回按钮
    if hitTest(dx, dy, TAB.BACK_CX, TAB.BACK_CY, TAB.BACK_W, TAB.BACK_H) then
        BF.trigger("arena_back")
        ArenaPage.close(); return true
    end

    -- Tab 切换
    for i, item in ipairs(TAB.ITEMS) do
        if hitTest(dx, dy, item.cx, item.cy, TAB.SLIDER_W, TAB.SLIDER_H) then
            local newTab = TAB.KEYS[i]
            if state.tab ~= newTab then
                state.tabFrom = state.tab
                state.tabSwitchTime = time.elapsedTime
                state.tab = newTab
                require("systems.GameSFX").playUIMove(2)
                state.scrollY = 0
                ArenaRankPage.resetScroll()  -- 重置排名页滚动
                ArenaShopPage.resetScroll()  -- 重置商店页滚动
                print("[ArenaPage] 切换到: " .. item.name)
            end
            return true
        end
    end

    -- 重试按钮（加载失败时，仅在战斗 tab 有效）
    if state.tab == "battle" and state.loadState == LOAD_FAIL and state.retryBtn then
        local rb = state.retryBtn
        if hitTest(dx, dy, rb.x + rb.w * 0.5, rb.y + rb.h * 0.5, rb.w, rb.h) then
            BF.trigger("arena_retry")
            print("[ArenaPage] 点击重试, retryCount=" .. tostring(state.retryCount or 0))
            state.loadState = LOAD_PENDING
            state.pendingElapsed = 0
            local myPower = CharacterPanel.getTotalPower and CharacterPanel.getTotalPower() or 0
            require("network.Client").sendAction(Protocol.ACTION_TYPES.ARENA_ENTER, {
                power = myPower,
            })
            return true
        end
    end

    -- 对战记录入口按钮
    if state.tab == "battle" and state.loadState == LOAD_OK then
        if hitTest(dx, dy, P2.LOG_CX, P2.LOG_CY, P2.LOG_W, P2.LOG_H) then
            BF.trigger("arena_log")
            print("[ArenaPage] 点击对战记录按钮")
            ArenaLogDialog.open(state.battleHistory)
            return true
        end
    end

    -- 段位图标点击 → 打开段位奖励弹窗
    if state.tab == "battle" then
        if hitTest(dx, dy, P2.TI_CX, P2.TI_CY, P2.TI_W, P2.TI_H) then
            BF.trigger("arena_tier")
            print("[ArenaPage] 点击段位图标 → 打开段位奖励")
            -- 将 claimedTiers table 的 key 转成 id 列表传给 Dialog
            local claimedIdList = {}
            for id, _ in pairs(state.claimedTiers) do
                claimedIdList[#claimedIdList + 1] = tonumber(id) or id
            end
            ArenaRankRewardDialog.open({
                currentScore = state.rankScore,
                claimedIds   = claimedIdList,
                reachedIds   = state.reachedTiers,
            })
            return true
        end
    end

    -- 商店 Tab：转发购买点击
    if state.tab == "shop" then
        return ArenaShopPage.handleInput(dx, dy)
    end

    -- 开始对战按钮 → 打开选择对手弹窗
    if state.tab == "battle" then
        if hitTest(dx, dy, P2.BB_CX, P2.BB_CY, P2.BB_W, P2.BB_H) then
            BF.trigger("arena_battle")
            if state.loadState ~= LOAD_OK then
                print("[ArenaPage] 数据未就绪，无法开始对战")
                return true
            end
            if (state.tickets or 0) <= 0 then
                print("[ArenaPage] 竞技券不足 (tickets=" .. tostring(state.tickets) .. ")")
                return true
            end
            ArenaOpponentDialog.open(state.rankData, state.myRankData, state.tickets)
            return true
        end
    end

    return true  -- 消费事件防穿透
end

function ArenaPage.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    if ArenaRankRewardDialog.isOpen() then return ArenaRankRewardDialog.handleDragBegin(dx, dy) end
    if ArenaLogDialog.isOpen() then return ArenaLogDialog.handleDragBegin(dx, dy) end
    if ArenaOpponentDialog.isOpen() then return true end
    if state.tab == "battle" and dy >= P2.CLIP_TOP and dy <= P2.CLIP_BOT then
        state.dragging = true
        state.lastDragY = dy
        return true
    end
    if state.tab == "rank" then
        ArenaRankPage.handleDragBegin(dy)
        return true
    end
    if state.tab == "shop" then
        ArenaShopPage.handleDragBegin(dx, dy)
        return true
    end
    return true
end

function ArenaPage.handleDragMove(dx, dy)
    if not state.open or state.closing then return false end
    if ArenaRankRewardDialog.isOpen() then return ArenaRankRewardDialog.handleDragMove(dx, dy) end
    if ArenaLogDialog.isOpen() then return ArenaLogDialog.handleDragMove(dx, dy) end
    if ArenaOpponentDialog.isOpen() then return true end
    if state.dragging then
        state.scrollY = state.scrollY + (state.lastDragY - dy)
        state.lastDragY = dy
        return true
    end
    if state.tab == "rank" and ArenaRankPage.isDragging() then
        ArenaRankPage.handleDragMove(dy)
        return true
    end
    if state.tab == "shop" and ArenaShopPage.isDragging() then
        ArenaShopPage.handleDragMove(dx, dy)
        return true
    end
    return true
end

function ArenaPage.handleDragEnd(dx, dy)
    if not state.open or state.closing then return false end
    if ArenaRankRewardDialog.isOpen() then return ArenaRankRewardDialog.handleDragEnd(dx, dy) end
    if ArenaLogDialog.isOpen() then return ArenaLogDialog.handleDragEnd(dx, dy) end
    if ArenaOpponentDialog.isOpen() then return true end
    state.dragging = false
    if state.tab == "rank" then
        ArenaRankPage.handleDragEnd()
    end
    if state.tab == "shop" then
        ArenaShopPage.handleDragEnd()
    end
    return true
end

--- 是否需要在竞技场建筑标签显示红点（有竞技券时返回 true）
function ArenaPage.hasTicketRedDot()
    return GameState.getArenaTicket() > 0
end

--- 是否有未领取的段位首通奖励（用于段位图标右上角红点）
function ArenaPage.hasTierRewardRedDot()
    for id, _ in pairs(state.reachedTiers) do
        if not state.claimedTiers[id] then
            return true
        end
    end
    return false
end

--- 更新 claimedTiers（领取成功后由 Dialog 回调）
function ArenaPage.onTierRewardClaimed(newClaimedTiers)
    if newClaimedTiers then
        state.claimedTiers = newClaimedTiers
    end
end

function ArenaPage.handleScroll(wheel)
    if not state.open or state.closing then return false end
    if ArenaRankRewardDialog.isOpen() then return ArenaRankRewardDialog.handleScroll(wheel) end
    if ArenaLogDialog.isOpen() then return ArenaLogDialog.handleScroll(wheel) end
    if ArenaOpponentDialog.isOpen() then return true end
    if state.tab == "rank" then
        ArenaRankPage.handleScroll(wheel)
    elseif state.tab == "shop" then
        ArenaShopPage.handleScroll(wheel)
    elseif state.tab == "battle" then
        state.scrollY = state.scrollY - wheel * 60
    end
    return true
end

return ArenaPage
