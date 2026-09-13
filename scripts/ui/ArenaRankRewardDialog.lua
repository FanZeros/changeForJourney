-- ============================================================================
-- ArenaRankRewardDialog - 竞技场段位奖励二级面板
-- 全屏遮罩 + 九宫格弹窗 + 段位进度条 + 段位组合列表（可滚动）
-- ============================================================================

local GameConfig = require("config.GameConfig")
local EquipmentConfig = require("config.EquipmentConfig")
local ArenaConfig = require("config.ArenaConfig")
local drawTextStroke = require("core.DrawUtil").drawTextStroke
local RewardPopup = require("ui.RewardPopup")
local BF = require("systems.ButtonFeedback")
local Protocol = require("shared.Protocol")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local Dialog = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 遮罩
local MASK = { A = 128 }  -- 50% 不透明度

-- 弹窗背景（九宫格）
local BG = {
    CX = 540, CY = 1029, W = 950, H = 1287,
    IT = 180, IL = 40, IR = 40, IB = 50,
}

-- 标题
local TTL = {
    X = 540, Y = 454, FONT = 60, SW = 6,
    SR = 0x59, SG = 0x32, SB = 0x19,
}

-- 进度条背景
local PB = {
    CX = 379, CY = 1058, W = 46, H = 1004,
    PAD = 5,  -- 内边距
}

-- 进度条裁剪区域（列表滚动裁剪以进度条背景上下为准）
-- BOT 需覆盖最底段位名称(NAME_CY=1539)+半行高，确保底部条目不被截断
local CLIP = {
    TOP = PB.CY - PB.H * 0.5,   -- 556
    BOT = PB.CY + PB.H * 0.5,   -- 1560
}
CLIP.H = CLIP.BOT - CLIP.TOP      -- 1004

-- 段位组合
local RK = {
    -- 徽章
    BADGE_CX = 378, BADGE_CY = 1479, BADGE_W = 211, BADGE_H = 211,
    -- 名称
    NAME_CX = 378, NAME_CY = 1539, NAME_FONT = 40, NAME_SW = 5,
    -- 奖励背景框
    RBG_CX = 629, RBG_CY = 1485, RBG_W = 291, RBG_H = 205,
    -- 品质背景 & 奖励图标
    ICON_CX = 643, ICON_CY = 1487, ICON_W = 160, ICON_H = 160,
    -- 奖励数量（角标，图标左下角）
    QTY_FONT = 40, QTY_SW = 5,
    -- 不可领取遮罩
    LOCK_R = 20, LOCK_A = 128,
    -- "可领取" 文本
    CLAIM_X = 646, CLAIM_Y = 1402, CLAIM_FONT = 40, CLAIM_SW = 5,
    CLAIM_R = 0x66, CLAIM_G = 0xff, CLAIM_B = 0x71,
    -- 组间距
    STEP = 257,
}

-- 段位奖励数据：直接从 ArenaConfig.TIERS 生成，保证与配置表一致

local RANK_DATA = {}
for _, tier in ipairs(ArenaConfig.TIERS) do
    RANK_DATA[#RANK_DATA + 1] = {
        id       = tier.id,
        name     = ArenaConfig.getTierDisplayName(tier),
        icon     = tier.icon,
        reward   = {
            type    = "gem",
            quality = 5,  -- 奖励均为钻石，统一最高品质背景
            icon    = "image/UI_icon_SJ.png",
            qty     = tier.firstRewardDiamond,
        },
        scoreReq = tier.scoreMin,
    }
end

-- ======================== 图片句柄 ========================

local img = {
    bg = -1,           -- UI_TY_EJQRK.png
    barBg = -1,        -- UI_JJCJL_DYT2.png
    barFill = -1,      -- UI_JJCJL_DYT1.png
    rewardBg = -1,     -- UI_JJC_DWJLBJ.png
    tier = {},         -- ICON_DW_1~8
    qualityBg = {},    -- UI_icon_ZBBJ_1~5
    rewardIcon = {},   -- 各种奖励图标（按路径缓存）
}

-- ======================== 弹窗动画常量 ========================

local POPUP_OPEN_DUR   = 0.25
local POPUP_CLOSE_DUR  = 0.20
local POPUP_SCALE_FROM = 0.8
local POPUP_SCALE_TO   = 1.0

local function easeOutCubic(t) local f = t - 1; return f * f * f + 1 end
local function easeInCubic(t) return t * t * t end

-- ======================== 状态 ========================

local state = {
    open = false,
    scrollY = 0,          -- 滚动偏移
    dragging = false,
    lastDragY = 0,
    velocity = 0,         -- 惯性速度
    -- 模拟数据
    currentScore = 1850,  -- 当前积分
    claimedIds = {},      -- 已领取的段位ID集合
    -- 弹窗动画
    popupAnimTime  = 0,
    popupClosing   = false,
    popupCloseTime = 0,
}

-- ======================== 九宫格绘制 ========================

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

-- ======================== 工具函数 ========================

local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

local function drawImageCentered(vg, imgH, cx, cy, w, h, alpha)
    if imgH < 0 then return end
    local paint = nvgImagePattern(vg, cx - w * 0.5, cy - h * 0.5, w, h, 0, imgH, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, cx - w * 0.5, cy - h * 0.5, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 获取奖励图标句柄（按路径缓存）
local function getRewardIcon(vg, path)
    if not img.rewardIcon[path] then
        img.rewardIcon[path] = nvgCreateImage(vg, path, 0)
    end
    return img.rewardIcon[path]
end

-- ======================== 弹窗动画辅助 ========================

local function getPopupAnim()
    if state.popupClosing then
        local t = math.min(1.0, (time.elapsedTime - state.popupCloseTime) / POPUP_CLOSE_DUR)
        local e = easeInCubic(t)
        local scale = POPUP_SCALE_TO + (POPUP_SCALE_FROM - POPUP_SCALE_TO) * e
        return scale, 1.0 - e, (t >= 1.0)
    else
        local t = math.min(1.0, (time.elapsedTime - state.popupAnimTime) / POPUP_OPEN_DUR)
        local e = easeOutCubic(t)
        local scale = POPUP_SCALE_FROM + (POPUP_SCALE_TO - POPUP_SCALE_FROM) * e
        return scale, e, false
    end
end

-- ======================== Public API ========================

function Dialog.init(vg)
    img.bg       = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    img.barBg    = nvgCreateImage(vg, "image/UI_JJCJL_DYT2.png", 0)
    img.barFill  = nvgCreateImage(vg, "image/UI_JJCJL_DYT1.png", 0)
    img.rewardBg = nvgCreateImage(vg, "image/UI_JJC_DWJLBJ.png", 0)
    for i = 1, 8 do
        img.tier[i] = nvgCreateImage(vg, "image/ICON_DW_" .. i .. ".png", 0)
    end
    for i = 1, 6 do
    -- [暗黑化 P2-A] 原 ZBBJ 贴图加载已移除（矢量品质框替代）
    end
    RewardPopup.init(vg)
    print("[ArenaRankRewardDialog] init OK")
end

--- 打开段位奖励弹窗
---@param opts table|nil { currentScore, claimedIds, reachedIds }
function Dialog.open(opts)
    opts = opts or {}
    state.open = true
    state.scrollY = 0
    state.dragging = false
    state.velocity = 0
    state.currentScore = opts.currentScore or 1850
    state.claimedIds = opts.claimedIds or {}
    state.reachedIds = opts.reachedIds or {}
    state.popupAnimTime = time.elapsedTime
    state.popupClosing = false
    print("[ArenaRankRewardDialog] 打开段位奖励 score=" .. state.currentScore)
end

function Dialog.close()
    if state.popupClosing then return end
    state.popupClosing = true
    state.popupCloseTime = time.elapsedTime
    state.dragging = false
    state.velocity = 0
    print("[ArenaRankRewardDialog] 关闭（动画中）")
end

function Dialog.isOpen()
    return state.open
end

-- ======================== 绘制 ========================

function Dialog.draw(vg)
    if not state.open then return end

    -- 弹窗动画参数
    local pScale, pAlpha, _ = getPopupAnim()

    -- 1. 全屏黑色遮罩（alpha 跟随动画）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(MASK.A * pAlpha)))
    nvgFill(vg)

    -- 弹窗内容整体应用 scale + fade
    nvgSave(vg)
    nvgTranslate(vg, DESIGN_W * 0.5, DESIGN_H * 0.5)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -DESIGN_W * 0.5, -DESIGN_H * 0.5)
    nvgGlobalAlpha(vg, pAlpha)

    -- 2. 弹窗背景（九宫格）
    local bgX = BG.CX - BG.W * 0.5
    local bgY = BG.CY - BG.H * 0.5
    DarkIcon.drawNine(vg, "panel", bgX, bgY, BG.W, BG.H, { titleH = BG.IT })

    -- 3. 标题 "段位奖励"
    drawTextStroke(vg, TTL.X, TTL.Y, "段位奖励",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- 找到当前积分对应的最高段位索引
    local curRankIdx = 1
    for i = 1, #RANK_DATA do
        if state.currentScore >= RANK_DATA[i].scoreReq then
            curRankIdx = i
        end
    end

    -- 4 & 5 & 6. 进度条 + 段位列表（共享裁剪区域和滚动偏移）
    -- 核心原则：进度条端点直接绑定到段位徽章的节点坐标+scrollOffset
    -- 节点怎么动，进度条就怎么动

    local totalRanks = #RANK_DATA

    nvgSave(vg)
    nvgScissor(vg, 0, CLIP.TOP, DESIGN_W, CLIP.H)

    -- 4. 段位进度条背景（在裁剪区域内绘制，额外延长高度隐藏图片两端锥形瑕疵）
    local BAR_EXTEND = 60
    drawImageCentered(vg, img.barBg, PB.CX, PB.CY, PB.W, PB.H + BAR_EXTEND * 2, 1.0)

    -- 5. 进度条填充（在裁剪区域内，跟随滚动）
    if img.barFill >= 0 then
        local barInnerW = PB.W - PB.PAD * 2
        local barLeft = PB.CX - barInnerW * 0.5

        -- 最底段位（idx=1）的徽章Y = 进度条底端
        local bottomNodeY = RK.BADGE_CY - (1 - 1) * RK.STEP + state.scrollY
        -- 最高段位（idx=totalRanks）的徽章Y = 进度条顶端
        local topNodeY = RK.BADGE_CY - (totalRanks - 1) * RK.STEP + state.scrollY
        -- 当前段位的徽章Y = 填充截止点
        local curNodeY = RK.BADGE_CY - (curRankIdx - 1) * RK.STEP + state.scrollY

        -- 未激活背景条：从当前段位到最高段位（上方灰色部分）
        if topNodeY < curNodeY then
            local inactiveTop = topNodeY
            local inactiveH = curNodeY - topNodeY
            if inactiveH > 0 then
                nvgBeginPath(vg)
                nvgRect(vg, barLeft, inactiveTop, barInnerW, inactiveH)
                nvgFillColor(vg, nvgRGBA(60, 60, 60, 120))
                nvgFill(vg)
            end
        end

        -- 已激活填充条：从当前段位到最底段位（下方亮色部分）
        -- 使用九宫格垂直拉伸
        local fillTop = curNodeY
        local fillBot = bottomNodeY
        local fillH = fillBot - fillTop
        if fillH > 0 then
            DarkIcon.drawNine(vg, "fill", barLeft, fillTop, barInnerW, fillH, { accent = "gold" })
        end
    end

    -- 6. 段位组合列表（在同一裁剪区域内）
    for idx = 1, totalRanks do
        local rk = RANK_DATA[idx]
        -- 基准Y = 最底部段位Y，向上每个段位减少 STEP
        local baseY = RK.BADGE_CY - (idx - 1) * RK.STEP + state.scrollY
        local itemCenterY = baseY

        -- 跳过不在可见区域的项
        if itemCenterY >= CLIP.TOP - RK.BADGE_H and itemCenterY <= CLIP.BOT + RK.BADGE_H then
            -- 段位Y偏移
            local offsetY = baseY - RK.BADGE_CY

            -- 6.1 段位徽章图标
            local tierImg = img.tier[rk.icon] or img.tier[1]
            drawImageCentered(vg, tierImg, RK.BADGE_CX, RK.BADGE_CY + offsetY, RK.BADGE_W, RK.BADGE_H, 1.0)

            -- 6.2 段位名称
            drawTextStroke(vg, RK.NAME_CX, RK.NAME_CY + offsetY, rk.name,
                RK.NAME_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, RK.NAME_SW, { strokeColor = { 0, 0, 0 } })

            -- 6.3 奖励背景框
            drawImageCentered(vg, img.rewardBg, RK.RBG_CX, RK.RBG_CY + offsetY, RK.RBG_W, RK.RBG_H, 1.0)

            -- 6.4 品质背景框
            local _bfIcon = BF.begin(vg, "arrd_claim_" .. idx, RK.ICON_CX, RK.ICON_CY + offsetY, RK.ICON_W, RK.ICON_H)
            local qIdx = math.max(1, math.min(6, rk.reward.quality))
            DarkIcon.drawQualityBg(vg, qIdx, RK.ICON_CX, RK.ICON_CY + offsetY, RK.ICON_W, RK.ICON_H, 1.0)  -- [暗黑化 P2-A]

            -- 6.5 奖励图标
            local rwIcon = getRewardIcon(vg, rk.reward.icon)
            drawImageCentered(vg, rwIcon, RK.ICON_CX, RK.ICON_CY + offsetY, RK.ICON_W, RK.ICON_H, 1.0)

            -- 6.6 奖励数量（角标，图标右下角）
            local qtyX = RK.ICON_CX + RK.ICON_W * 0.5 - 10
            local qtyY = RK.ICON_CY + offsetY + RK.ICON_H * 0.5 - 10
            drawTextStroke(vg, qtyX, qtyY, tostring(rk.reward.qty),
                RK.QTY_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM,
                255, 255, 255, RK.QTY_SW, { strokeColor = { 0, 0, 0 } })
            BF.finish(vg, _bfIcon)

            -- 判断领取状态
            local scoreOk = (state.currentScore >= rk.scoreReq)
            local reached = state.reachedIds[rk.id] or state.reachedIds[tostring(rk.id)]
            local canClaim = scoreOk and reached
            local claimed = false
            for _, cid in ipairs(state.claimedIds) do
                if cid == rk.id then claimed = true; break end
            end

            -- 6.7 不可领取：黑色遮罩
            if not canClaim then
                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    RK.ICON_CX - RK.ICON_W * 0.5, RK.ICON_CY + offsetY - RK.ICON_H * 0.5,
                    RK.ICON_W, RK.ICON_H, RK.LOCK_R)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, RK.LOCK_A))
                nvgFill(vg)
            end

            -- 6.8 可领取：斜体 "可领取" 文本
            if canClaim and not claimed then
                nvgSave(vg)
                local claimTextX = RK.CLAIM_X
                local claimTextY = RK.CLAIM_Y + offsetY
                nvgTranslate(vg, claimTextX, claimTextY)
                nvgSkewX(vg, math.rad(-8))
                drawTextStroke(vg, 0, 0, "可领取",
                    RK.CLAIM_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    RK.CLAIM_R, RK.CLAIM_G, RK.CLAIM_B, RK.CLAIM_SW,
                    { strokeColor = { 0, 0, 0 } })
                nvgRestore(vg)
            end

            -- 6.9 已领取不显示 "可领取"（不需要额外代码）
        end
    end

    nvgRestore(vg)  -- 恢复裁剪

    nvgRestore(vg)  -- 恢复弹窗 scale+fade 变换

    -- 7. 通用奖励弹窗（最上层，在弹窗变换之外绘制）
    RewardPopup.draw(vg)
end

-- ======================== 更新 ========================

function Dialog.update(dt)
    if not state.open then return end

    -- 弹窗关闭动画完成检测
    if state.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            state.popupClosing = false
            state.open = false
            return
        end
    end

    -- 更新奖励弹窗动画
    RewardPopup.update(dt)

    -- 惯性滚动
    if not state.dragging and math.abs(state.velocity) > 0.5 then
        state.scrollY = state.scrollY + state.velocity * dt
        state.velocity = state.velocity * 0.92  -- 摩擦衰减
    elseif not state.dragging then
        state.velocity = 0
    end

    -- 限制滚动范围
    local totalRanks = #RANK_DATA
    local contentH = (totalRanks - 1) * RK.STEP
    local maxScroll = contentH - CLIP.H + RK.BADGE_H
    if maxScroll < 0 then maxScroll = 0 end
    state.scrollY = math.max(0, math.min(maxScroll, state.scrollY))
end

-- ======================== 拖拽 ========================

function Dialog.handleDragBegin(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    if RewardPopup.isOpen() then
        RewardPopup.handleDragBegin(dx, dy)
        return true
    end
    state.dragging = true
    state.lastDragY = dy
    state.velocity = 0
    return true
end

function Dialog.handleDragMove(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    if RewardPopup.isOpen() then
        RewardPopup.handleDragMove(dx, dy)
        return true
    end
    if not state.dragging then return false end
    local deltaY = dy - state.lastDragY  -- 向上拖 = 负 = scrollY减少（列表从底向上排列）
    state.scrollY = state.scrollY + deltaY
    state.velocity = deltaY / 0.016  -- 估算速度（假设 ~60fps）
    state.lastDragY = dy
    return true
end

function Dialog.handleDragEnd(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    if RewardPopup.isOpen() then
        RewardPopup.handleDragEnd(dx, dy)
        return true
    end
    state.dragging = false
    return true
end

-- ======================== 点击处理 ========================

function Dialog.handleInput(dx, dy)
    if not state.open then return false end

    -- 关闭动画期间阻断输入
    if state.popupClosing then return true end

    -- RewardPopup 打开时优先拦截
    if RewardPopup.isOpen() then
        RewardPopup.handleInput(dx, dy)
        return true
    end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.popupAnimTime < 0.05 then return true end

    -- 点击弹窗外部关闭
    if not hitTest(dx, dy, BG.CX, BG.CY, BG.W, BG.H) then
        Dialog.close()
        return true
    end

    -- 点击奖励图标：尝试领取
    local totalRanks = #RANK_DATA
    for idx = 1, totalRanks do
        local rk = RANK_DATA[idx]
        local offsetY = -(idx - 1) * RK.STEP + state.scrollY
        local iconCY = RK.ICON_CY + offsetY

        -- 检查是否在裁剪区域内
        if iconCY >= CLIP.TOP and iconCY <= CLIP.BOT then
            if hitTest(dx, dy, RK.ICON_CX, iconCY, RK.ICON_W, RK.ICON_H) then
                -- 判断是否可领取：分数达标 且 已到达该段位（reachedIds 中存在）
                local scoreOk = (state.currentScore >= rk.scoreReq)
                local reached = state.reachedIds[rk.id] or state.reachedIds[tostring(rk.id)]
                local canClaim = scoreOk and reached
                local claimed = false
                for _, cid in ipairs(state.claimedIds) do
                    if cid == rk.id then claimed = true; break end
                end
                if canClaim and not claimed then
                    BF.trigger("arrd_claim_" .. idx)
                    -- 乐观更新本地状态，防止双击
                    table.insert(state.claimedIds, rk.id)
                    print("[ArenaRankRewardDialog] 发送领取请求 tierId=" .. tostring(rk.id))
                    -- 发送服务端请求
                    require("network.Client").sendAction(
                        Protocol.ACTION_TYPES.ARENA_CLAIM_TIER,
                        { tierId = rk.id }
                    )
                elseif claimed then
                    print("[ArenaRankRewardDialog] 已领取: " .. rk.name)
                else
                    print("[ArenaRankRewardDialog] 未达到段位: " .. rk.name .. " (需要 " .. rk.scoreReq .. " 分)")
                end
                return true
            end
        end
    end

    return true  -- 消费事件防穿透
end

-- ======================== 滚动 ========================

function Dialog.handleScroll(wheel)
    if not state.open then return false end
    if state.popupClosing then return true end
    if RewardPopup.isOpen() then
        RewardPopup.handleScroll(wheel)
        return true
    end
    state.scrollY = state.scrollY + wheel * 60
    return true
end

-- ======================== 服务端响应回调 ========================

--- 服务端领取结果回调（由 ArenaPage.onActionResult 调用）
---@param tierId number 段位 ID
---@param success boolean 是否成功
---@param newClaimedTiers table|nil 服务端返回的最新 claimedTiers（成功时有效）
function Dialog.onClaimResult(tierId, success, newClaimedTiers)
    if success and newClaimedTiers then
        -- 用服务端权威数据重建 claimedIds 列表
        local newList = {}
        for id, _ in pairs(newClaimedTiers) do
            newList[#newList + 1] = tonumber(id) or id
        end
        state.claimedIds = newList
        print("[ArenaRankRewardDialog] onClaimResult 成功 tierId=" .. tostring(tierId))
    else
        -- 服务端拒绝：从乐观更新中移除该 tierId
        for i = #state.claimedIds, 1, -1 do
            if state.claimedIds[i] == tierId then
                table.remove(state.claimedIds, i)
                break
            end
        end
        print("[ArenaRankRewardDialog] onClaimResult 失败 tierId=" .. tostring(tierId) .. " 已回滚")
    end
end

--- 显示奖励弹窗（由 ArenaPage 在领取成功后调用）
function Dialog.showRewardPopup(title, rewards)
    if state.open then
        local typeMap = { diamond = "diamond", gold = "gold", arena_ticket = "arena_ticket" }
        local mapped = {}
        for _, r in ipairs(rewards) do
            mapped[#mapped + 1] = { type = typeMap[r.type] or r.type, amount = r.amount }
        end
        RewardPopup.show(title, mapped)
    end
end

return Dialog
