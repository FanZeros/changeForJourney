-- ============================================================================
-- ArenaLogDialog - 竞技场对战记录弹窗
-- 全屏遮罩 + 九宫格弹窗 + 可滚动日志列表
-- ============================================================================

local GameConfig = require("config.GameConfig")
local drawTextStroke = require("core.DrawUtil").drawTextStroke
local DarkIcon        = require("core.DarkIcon")  -- [暗黑化 P1] 矢量弹窗底板

local Dialog = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 遮罩
local MASK_A = 128  -- 50% 不透明度

-- 弹窗背景（九宫格 UI_TY_EJQRK）
local BG = {
    CX = 540, CY = 1029, W = 950, H = 1287,
    IT = 180, IL = 40, IR = 40, IB = 50,
}

-- 标题 "对战记录"
local TTL = {
    X = 540, Y = 454, FONT = 60, SW = 6,
    SR = 0x59, SG = 0x32, SB = 0x19,
}

-- 副标题
local SUB = {
    X = 540, Y = 578, FONT = 40,
    R = 0xb6, G = 0xb0, B = 0x9d,
}

-- 日志条目
local LOG = {
    CX = 540, FIRST_CY = 658, W = 860, H = 80, R = 20, GAP = 10,
    BG_A = 13,  -- 5% of 255 ≈ 13
    -- 状态文本（左对齐）
    STATUS_X = 160, STATUS_FONT = 38,
    WIN_R = 0x90, WIN_G = 0xFF, WIN_B = 0x8A,
    LOSE_R = 0xFF, LOSE_G = 0x78, LOSE_B = 0x78,
    -- 分数图标
    ICON_CX = 840, ICON_CY_OFF = 0, ICON_W = 50, ICON_H = 50,
    -- 分数文本（左对齐）
    SCORE_X = 868, SCORE_FONT = 30,
    SCORE_WIN_R = 0x90, SCORE_WIN_G = 0xFF, SCORE_WIN_B = 0x8A,
    SCORE_LOSE_R = 0xFF, SCORE_LOSE_G = 0x78, SCORE_LOSE_B = 0x78,
}
LOG.STEP = LOG.H + LOG.GAP  -- 90

-- 可滚动裁剪区域（从第一条日志到弹窗内容底部）
local CLIP = {
    TOP = LOG.FIRST_CY - LOG.H * 0.5,   -- 618
}
-- 弹窗内容底部 = BG bottom - BG.IB
CLIP.BOT = BG.CY + BG.H * 0.5 - BG.IB  -- 1029 + 643.5 - 50 = 1622.5
CLIP.H = CLIP.BOT - CLIP.TOP
CLIP.VIS_COUNT = math.floor(CLIP.H / LOG.STEP) -- ~11 条可见

-- ======================== 图片句柄 ========================

local imgScoreIcon = -1 -- UI_icon_JJCFS_X

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
    logs = {},      -- 日志数据数组
    scrollY = 0,
    dragging = false,
    lastDragY = 0,
    -- 弹窗动画
    popupAnimTime  = 0,
    popupClosing   = false,
    popupCloseTime = 0,
}

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

-- ======================== 工具函数 ========================

local function drawImageCentered(vg, imgH, cx, cy, w, h, alpha)
    if imgH < 0 or alpha <= 0.01 then return end
    local x, y = cx - w * 0.5, cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, imgH, alpha)
    nvgBeginPath(vg); nvgRect(vg, x, y, w, h); nvgFillPaint(vg, paint); nvgFill(vg)
end


function Dialog.init(vg)
    imgScoreIcon = nvgCreateImage(vg, "image/UI_icon_JJCFS_X.png", 0)
    print("[ArenaLogDialog] init OK")
end

function Dialog.open(logs)
    state.open = true
    state.scrollY = 0
    state.dragging = false
    state.popupAnimTime = time.elapsedTime
    state.popupClosing = false
    -- 按时间倒序排列（最新在前）
    state.logs = {}
    if logs then
        for i = #logs, 1, -1 do
            state.logs[#state.logs + 1] = logs[i]
        end
    end
    print("[ArenaLogDialog] open, logs=" .. #state.logs)
end

function Dialog.close()
    if state.popupClosing then return end
    state.popupClosing = true
    state.popupCloseTime = time.elapsedTime
    state.dragging = false
    print("[ArenaLogDialog] close (anim)")
end

function Dialog.isOpen()
    return state.open
end

function Dialog.update(dt)
    if not state.open then return end
    if state.popupClosing then
        local _, _, done = getPopupAnim()
        if done then
            state.popupClosing = false
            state.open = false
            return
        end
    end
end

function Dialog.draw(vg)
    if not state.open then return end

    local pScale, pAlpha, _ = getPopupAnim()

    -- 1. 全屏遮罩（alpha 跟随弹窗动画）
    nvgBeginPath(vg); nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(MASK_A * pAlpha))); nvgFill(vg)

    -- 弹窗 scale+fade 变换
    nvgSave(vg)
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, pScale, pScale)
    nvgTranslate(vg, -BG.CX, -BG.CY)
    nvgGlobalAlpha(vg, pAlpha)

    -- 2. 弹窗背景 [暗黑化 P1: 矢量九宫格]
    DarkIcon.drawNine(vg, "panel",
        BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5,
        BG.W, BG.H, { titleH = BG.IT })

    -- 3. 标题 "对战记录"（描边文字）
    drawTextStroke(vg, TTL.X, TTL.Y, "对战记录",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- 4. 副标题
    nvgFontFace(vg, "sans"); nvgFontSize(vg, SUB.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(SUB.R, SUB.G, SUB.B, 255))
    nvgText(vg, SUB.X, SUB.Y, "竞技场进攻与防守的对战日志", nil)

    -- 5. 日志列表（可滚动）
    local logCount = #state.logs
    if logCount == 0 then
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(SUB.R, SUB.G, SUB.B, 180))
        nvgText(vg, 540, 900, "暂无对战记录", nil)
        nvgRestore(vg)  -- 恢复弹窗 scale+fade 变换
        return
    end

    local totalH = logCount * LOG.STEP - LOG.GAP
    local maxScroll = math.max(0, totalH - CLIP.H)
    state.scrollY = math.max(0, math.min(state.scrollY, maxScroll))

    nvgSave(vg)
    nvgScissor(vg, LOG.CX - LOG.W * 0.5, CLIP.TOP, LOG.W, CLIP.H)
    nvgTranslate(vg, 0, -state.scrollY)

    for i, log in ipairs(state.logs) do
        local cy = LOG.FIRST_CY + (i - 1) * LOG.STEP
        local screenCY = cy - state.scrollY

        -- 可见性检测
        if screenCY >= CLIP.TOP - LOG.H and screenCY <= CLIP.BOT + LOG.H then
            -- 条目背景（圆角矩形，黑色 5% 透明度）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, LOG.CX - LOG.W * 0.5, cy - LOG.H * 0.5,
                LOG.W, LOG.H, LOG.R)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, LOG.BG_A))
            nvgFill(vg)

            -- 判断胜负和类型
            local isWin = (log.result == "win")
            local isAttack = (log.type == "attack")
            local opName = log.opponentName or log.attackerName or "未知"

            -- 构建前缀（带颜色）和后缀（纯白）
            local prefix, suffix
            if isAttack then
                prefix = isWin and "进攻成功" or "进攻失败"
                suffix = isWin and ("击败了" .. opName) or ("败给了" .. opName)
            else
                prefix = isWin and "防守成功" or "防守失败"
                suffix = opName .. "的进攻"
            end

            -- 前缀颜色
            local pR, pG, pB
            if isWin then
                pR, pG, pB = 0x90, 0xFF, 0x8A
            else
                pR, pG, pB = 0xFF, 0x78, 0x78
            end
            local stColor = { 0x23, 0x23, 0x23 }
            local stAlign = NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE

            -- 绘制前缀（带色 + 描边）
            drawTextStroke(vg, LOG.STATUS_X, cy, prefix,
                LOG.STATUS_FONT, stAlign, pR, pG, pB, 4,
                { strokeColor = stColor })

            -- 测量前缀宽度
            nvgFontFace(vg, "sans"); nvgFontSize(vg, LOG.STATUS_FONT)
            local prefixW = nvgTextBounds(vg, 0, 0, prefix)

            -- 绘制后缀（纯白 + 描边）
            drawTextStroke(vg, LOG.STATUS_X + prefixW, cy, suffix,
                LOG.STATUS_FONT, stAlign, 255, 255, 255, 4,
                { strokeColor = stColor })

            -- 分数图标
            local iconCY = cy + LOG.ICON_CY_OFF
            drawImageCentered(vg, imgScoreIcon, LOG.ICON_CX, iconCY,
                LOG.ICON_W, LOG.ICON_H, 1.0)

            -- 分数文本（带描边）
            local sc = log.scoreChange or 0
            local scoreText = (sc >= 0) and ("+" .. sc) or tostring(sc)
            local scR, scG, scB
            if sc >= 0 then
                scR, scG, scB = 0x90, 0xFF, 0x8A
            else
                scR, scG, scB = 0xFF, 0x78, 0x78
            end
            drawTextStroke(vg, LOG.SCORE_X, cy, scoreText,
                LOG.SCORE_FONT, stAlign, scR, scG, scB, 4,
                { strokeColor = stColor })
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)  -- 恢复滚动裁剪

    nvgRestore(vg)  -- 恢复弹窗 scale+fade 变换
end

-- ======================== 输入处理 ========================

function Dialog.handleInput(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.popupAnimTime < 0.05 then return true end

    -- 点击弹窗外部 → 关闭
    local bgL = BG.CX - BG.W * 0.5
    local bgT = BG.CY - BG.H * 0.5
    if dx < bgL or dx > bgL + BG.W or dy < bgT or dy > bgT + BG.H then
        Dialog.close()
        return true
    end

    return true  -- 消费事件防穿透
end

function Dialog.handleDragBegin(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    -- 在裁剪区域内才可拖拽
    if dy >= CLIP.TOP and dy <= CLIP.BOT
       and dx >= LOG.CX - LOG.W * 0.5 and dx <= LOG.CX + LOG.W * 0.5 then
        state.dragging = true
        state.lastDragY = dy
    end
    return true
end

function Dialog.handleDragMove(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    if state.dragging then
        state.scrollY = state.scrollY + (state.lastDragY - dy)
        state.lastDragY = dy
    end
    return true
end

function Dialog.handleDragEnd(dx, dy)
    if not state.open then return false end
    if state.popupClosing then return true end
    state.dragging = false
    return true
end

function Dialog.handleScroll(wheel)
    if not state.open then return false end
    if state.popupClosing then return true end
    state.scrollY = state.scrollY - wheel * 60
    return true
end

return Dialog
