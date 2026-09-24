-- ============================================================================
-- AvatarSelectPanel - 更换头像界面（上半部分）
-- 入口：玩家信息界面点击头像
-- 坐标系: 设计分辨率 1080×2400，所有位置为中心点坐标
-- ============================================================================

local DrawUtil       = require("core.DrawUtil")
local HeroConfig        = require("config.HeroConfig")
local HeroAssetUtil     = require("config.HeroAssetUtil")
local CharacterPanel = require("ui.character.panel.CharacterPanel")
local BF             = require("systems.ButtonFeedback")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest

local AvatarSelectPanel = {}

-- ======================== 状态 ========================

local state = {
    open      = false,
    animTime  = 0,
    closing   = false,
    closeTime = 0,
    selectedHeroId      = 1,    -- 当前选中预览的英雄 ID
    confirmedHeroId     = 1,    -- 已确认使用的头像英雄 ID
    -- 网格滚动
    scrollY      = 0,      -- 当前滚动偏移（像素）
    scrollMaxY   = 0,      -- 最大滚动量
    dragging     = false,  -- 是否正在拖拽滚动
    dragStartY   = 0,      -- 拖拽起始 Y
    dragStartScr = 0,      -- 拖拽起始 scrollY
}

-- ======================== 图片资源句柄 ========================

local img = {
    bg           = -1,   -- UI_TY_EJQRK.png 九宫格弹窗背景
    heroIcons    = {},    -- [heroId] 角色头像图标
    wearBtn      = -1,   -- UI_AN_LV.png 穿戴按钮
    lockIcon     = -1,   -- UI_ICON_SUO.png 上锁图标
}

-- ======================== 布局常量 ========================

-- 动画
local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.15

-- 1. 全屏黑色遮罩
local MASK_ALPHA = 128  -- 50%

-- 2. 弹窗背景（九宫格）
local BG = {
    CX = 540, CY = 902, W = 950, H = 1417,
    IT = 180, IL = 40, IR = 40, IB = 50,
}

-- 3. 标题 "更换头像"
local TTL = {
    X = 540, Y = 262, FONT = 60,
    FR = 255, FG = 255, FB = 255,
    SW = 6, SR = 0x59, SG = 0x32, SB = 0x19,
}

-- 4. 上方信息区域背景
local INFO_BG = {
    CX = 540, CY = 477, W = 800, H = 216, R = 16,
    A = 13,  -- 黑色 5%
}

-- 5. 头像
local AVATAR = {
    CX = 261, CY = 477, W = 160, H = 160,
}

-- 7. 角色名称
local HERO_NAME = {
    X = 380, Y = 424, FONT = 42,
    R = 0x50, G = 0x2c, B = 0x15,
}

-- 8. "(已解锁)" / "(未解锁)" 状态文本
local UNLOCK_TEXT = {
    DX = 23,  -- 在名字后偏移 23px
    Y = 430, FONT = 42,
    UNLOCKED_R = 0x1b, UNLOCKED_G = 0xa7, UNLOCKED_B = 0x14,  -- 绿色
    LOCKED_R = 0x80, LOCKED_G = 0x80, LOCKED_B = 0x80,          -- 灰色
}

-- 9. 获取途径描述（文本段落框 534×101）
local ACQ_DESC = {
    X = 648, Y = 510, W = 534, H = 101, FONT = 38,
    R = 0x8d, G = 0x73, B = 0x62,
}

-- 10. 内容区域背景
local CONTENT_BG = {
    CX = 540, CY = 1020, W = 800, H = 810, R = 16,
    A = 13,  -- 黑色 5%
}

-- 下半部分：头像排列区域
local GRID_AREA = {
    CX = 540, CY = 1020, W = 720, H = 720,
}

-- 每个格子
local CELL = {
    SIZE = 160,     -- 160×160
    RADIUS = 12,    -- 圆角
    BG_A = 26,      -- 黑色 10% 不透明度
    COLS = 4,       -- 4 列（720 / 160 ≈ 4，留间距）
    SPACING_Y = 18, -- 固定行间距 18px
}

-- 穿戴按钮
local WEAR_BTN = {
    CX = 540, CY = 1505, W = 410, H = 100,
    FONT = 40,
    TEXT_A = 179,   -- 纯黑 70% 不透明度
}

-- ======================== 回调 ========================

---@type fun(heroId: number)|nil
local onAvatarConfirmed = nil

-- ============================================================================
-- Public API
-- ============================================================================

--- 初始化（加载图片资源，仅调用一次）
function AvatarSelectPanel.init(vg)
    -- 弹窗背景
    img.bg = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK.png", 0)
    -- 角色头像图标
    HeroAssetUtil.preloadIcons(vg, img.heroIcons)
    -- 穿戴按钮
    img.wearBtn = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)
    img.lockIcon = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0)

    print("[AvatarSelectPanel] init OK")
end

--- 打开面板
---@param opts table|number 配置表或兼容旧版的 avatarHeroId
---@param callback fun(heroId: number)|nil 兼容旧版头像回调
function AvatarSelectPanel.open(opts, callback)
    if state.open then return end

    local avatarHeroId = 1
    onAvatarConfirmed = nil

    if type(opts) == "table" then
        avatarHeroId = opts.avatarHeroId or 1
        onAvatarConfirmed = opts.onAvatarConfirmed
    else
        avatarHeroId = opts or 1
        onAvatarConfirmed = callback
    end

    state.open = true
    state.closing = false
    state.animTime = time.elapsedTime
    state.selectedHeroId = avatarHeroId
    state.confirmedHeroId = avatarHeroId
    state.scrollY = 0
    state.scrollMaxY = 0
    state.dragging = false
    print("[AvatarSelectPanel] 打开, 当前头像: hero_" .. state.selectedHeroId)
end

--- 关闭面板
function AvatarSelectPanel.close()
    if not state.open or state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    print("[AvatarSelectPanel] 关闭")
end

--- 是否打开
function AvatarSelectPanel.isOpen()
    return state.open
end

--- 获取当前确认的头像英雄 ID
function AvatarSelectPanel.getConfirmedHeroId()
    return state.confirmedHeroId
end

--- 计算网格内容总高度和最大滚动量
local function updateScrollMax()
    local count = #HeroConfig.getAllIds()
    local rows = math.ceil(count / CELL.COLS)
    local contentH = rows * CELL.SIZE + (rows - 1) * CELL.SPACING_Y
    state.scrollMaxY = math.max(0, contentH - GRID_AREA.H)
end

--- 滚动处理（鼠标滚轮）
function AvatarSelectPanel.handleWheel(dy)
    if not state.open or state.closing then return false end
    updateScrollMax()
    state.scrollY = state.scrollY - dy * 40
    state.scrollY = math.max(0, math.min(state.scrollY, state.scrollMaxY))
    return true
end

--- 触摸/鼠标拖拽开始
function AvatarSelectPanel.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end
    -- 检查是否在网格区域内
    if not hitTest(dx, dy, GRID_AREA.CX, GRID_AREA.CY, GRID_AREA.W, GRID_AREA.H) then
        return false
    end
    state.dragging = true
    state.dragStartY = dy
    state.dragStartScr = state.scrollY
    return true
end

--- 触摸/鼠标拖拽移动
function AvatarSelectPanel.handleDragMove(dx, dy)
    if not state.dragging then return false end
    updateScrollMax()
    local delta = state.dragStartY - dy
    state.scrollY = state.dragStartScr + delta
    state.scrollY = math.max(0, math.min(state.scrollY, state.scrollMaxY))
    return true
end

--- 触摸/鼠标拖拽结束
function AvatarSelectPanel.handleDragEnd()
    state.dragging = false
end

--- 点击处理
function AvatarSelectPanel.handleInput(dx, dy)
    if not state.open or state.closing then return true end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.animTime < 0.05 then return true end

    -- 点击弹窗外部 → 关闭
    if not hitTest(dx, dy, BG.CX, BG.CY, BG.W, BG.H) then
        AvatarSelectPanel.close()
        return true
    end

    -- 穿戴按钮点击
    if hitTest(dx, dy, WEAR_BTN.CX, WEAR_BTN.CY, WEAR_BTN.W, WEAR_BTN.H) then
        BF.trigger("asp_wear")
        state.confirmedHeroId = state.selectedHeroId
        if onAvatarConfirmed then
            onAvatarConfirmed(state.confirmedHeroId)
        end
        print("[AvatarSelectPanel] 穿戴确认: hero_" .. state.confirmedHeroId)
        AvatarSelectPanel.close()
        return true
    end

    -- 头像网格点击（考虑滚动偏移）
    local cols = CELL.COLS
    local areaLeft = GRID_AREA.CX - GRID_AREA.W * 0.5
    local areaTop  = GRID_AREA.CY - GRID_AREA.H * 0.5
    local spacingX = (GRID_AREA.W - cols * CELL.SIZE) / (cols - 1)

    -- 先检查点击是否在网格区域内
    if hitTest(dx, dy, GRID_AREA.CX, GRID_AREA.CY, GRID_AREA.W, GRID_AREA.H) then
        local allIds = HeroConfig.getAllIds()
        for idx, heroId in ipairs(allIds) do
            local row = math.ceil(idx / cols)
            local col = ((idx - 1) % cols) + 1
            local cx = areaLeft + (col - 1) * (CELL.SIZE + spacingX) + CELL.SIZE * 0.5
            local cy = areaTop  + (row - 1) * (CELL.SIZE + CELL.SPACING_Y) + CELL.SIZE * 0.5 - state.scrollY
            if cy + CELL.SIZE * 0.5 >= areaTop and cy - CELL.SIZE * 0.5 <= areaTop + GRID_AREA.H then
                if hitTest(dx, dy, cx, cy, CELL.SIZE, CELL.SIZE) then
                    state.selectedHeroId = heroId
                    print("[AvatarSelectPanel] 选中头像: hero_" .. heroId)
                    return true
                end
            end
        end
    end

    -- 弹窗内部消费事件
    return true
end

-- ======================== 绘制 ========================

function AvatarSelectPanel.draw(vg)
    if not state.open then return end

    -- 动画进度
    local animProgress = 1.0
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        animProgress = 1.0 - math.min(elapsed / ANIM_CLOSE_DUR, 1.0)
        if animProgress <= 0 then
            state.open = false
            state.closing = false
            return
        end
    else
        local elapsed = time.elapsedTime - state.animTime
        animProgress = math.min(elapsed / ANIM_OPEN_DUR, 1.0)
        animProgress = DrawUtil.easeOutBack(animProgress)
    end

    nvgSave(vg)

    -- ── 1. 全屏黑色遮罩 50% ──
    local maskAlpha = math.floor(MASK_ALPHA * (state.closing
        and (1.0 - math.min((time.elapsedTime - state.closeTime) / ANIM_CLOSE_DUR, 1.0))
        or math.min((time.elapsedTime - state.animTime) / ANIM_OPEN_DUR, 1.0)))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(vg)

    -- 弹窗缩放动画
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, animProgress, animProgress)
    nvgTranslate(vg, -BG.CX, -BG.CY)

    -- ── 2. 弹窗背景框（九宫格）──
    DarkIcon.drawNine(vg, "panel", BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5, BG.W, BG.H, { titleH = BG.IT })

    -- ── 3. 标题 "更换头像" ──
    drawTextStroke(vg, TTL.X, TTL.Y, "更换头像",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        TTL.FR, TTL.FG, TTL.FB, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- ── 4. 上方信息区域背景 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        INFO_BG.CX - INFO_BG.W * 0.5, INFO_BG.CY - INFO_BG.H * 0.5,
        INFO_BG.W, INFO_BG.H, INFO_BG.R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, INFO_BG.A))
    nvgFill(vg)

    -- 获取选中英雄数据
    local selHeroId = state.selectedHeroId
    local heroCfg = HeroConfig.get(selHeroId)
    local isOwned = CharacterPanel.isOwned(selHeroId)

    -- ── 5. 头像 ──
    local avatarImg = img.heroIcons[selHeroId]
    if avatarImg and avatarImg >= 0 then
        drawImageCentered(vg, avatarImg, AVATAR.CX, AVATAR.CY, AVATAR.W, AVATAR.H, 1.0)
    end

    -- ── 7. 名称（左对齐）──
    local displayName = heroCfg and heroCfg.name or "未知"
    local showUnlockState = isOwned
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, HERO_NAME.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(HERO_NAME.R, HERO_NAME.G, HERO_NAME.B, 255))
    local nameEndX = nvgText(vg, HERO_NAME.X, HERO_NAME.Y, displayName, nil)

    -- ── 8. "(已解锁)" / "(未解锁)" 状态文本 ──
    local unlockStr, ur, ug, ub
    if showUnlockState then
        unlockStr = "(已解锁)"
        ur = UNLOCK_TEXT.UNLOCKED_R
        ug = UNLOCK_TEXT.UNLOCKED_G
        ub = UNLOCK_TEXT.UNLOCKED_B
    else
        unlockStr = "(未解锁)"
        ur = UNLOCK_TEXT.LOCKED_R
        ug = UNLOCK_TEXT.LOCKED_G
        ub = UNLOCK_TEXT.LOCKED_B
    end
    nvgFontSize(vg, UNLOCK_TEXT.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(ur, ug, ub, 255))
    nvgText(vg, nameEndX + UNLOCK_TEXT.DX, UNLOCK_TEXT.Y, unlockStr, nil)

    -- ── 9. 获取途径 ──
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg, ACQ_DESC.FONT)
    nvgFillColor(vg, nvgRGBA(ACQ_DESC.R, ACQ_DESC.G, ACQ_DESC.B, 255))
    nvgTextBox(
        vg,
        ACQ_DESC.X - ACQ_DESC.W * 0.5,
        ACQ_DESC.Y - ACQ_DESC.H * 0.5,
        ACQ_DESC.W,
        "获取途径：获取该远征队员",
        nil
    )

    -- ── 10. 内容区域背景 ──
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        CONTENT_BG.CX - CONTENT_BG.W * 0.5, CONTENT_BG.CY - CONTENT_BG.H * 0.5,
        CONTENT_BG.W, CONTENT_BG.H, CONTENT_BG.R)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, CONTENT_BG.A))
    nvgFill(vg)

    -- ── 下半部分：头像网格 ──
    local cols = CELL.COLS
    local areaLeft = GRID_AREA.CX - GRID_AREA.W * 0.5
    local areaTop  = GRID_AREA.CY - GRID_AREA.H * 0.5
    local spacingX = (GRID_AREA.W - cols * CELL.SIZE) / (cols - 1)

    -- 裁剪到网格区域
    nvgSave(vg)
    nvgScissor(vg, areaLeft, areaTop, GRID_AREA.W, GRID_AREA.H)

    do
        local allIds = HeroConfig.getAllIds()
        updateScrollMax()

        for idx, heroId in ipairs(allIds) do
            local row = math.ceil(idx / cols)
            local col = ((idx - 1) % cols) + 1
            local cx = areaLeft + (col - 1) * (CELL.SIZE + spacingX) + CELL.SIZE * 0.5
            local cy = areaTop  + (row - 1) * (CELL.SIZE + CELL.SPACING_Y) + CELL.SIZE * 0.5 - state.scrollY
            local cellLeft = cx - CELL.SIZE * 0.5
            local cellTop  = cy - CELL.SIZE * 0.5

            -- 跳过不在可见区域内的格子（裁剪优化）
            if cy + CELL.SIZE * 0.5 < areaTop or cy - CELL.SIZE * 0.5 > areaTop + GRID_AREA.H then
                goto continue_cell
            end

            local heroOwned = CharacterPanel.isOwned(heroId)
            local iconImg = img.heroIcons[heroId]

            -- 1) 内容背景框：160×160 圆角12 黑色10%
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cellLeft, cellTop, CELL.SIZE, CELL.SIZE, CELL.RADIUS)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, CELL.BG_A))
            nvgFill(vg)

            -- 2) 头像图标 160×160
            if iconImg and iconImg >= 0 then
                local iconAlpha = heroOwned and 1.0 or 0.4
                drawImageCentered(vg, iconImg, cx, cy, CELL.SIZE, CELL.SIZE, iconAlpha)
            end

            -- 未拥有：半透明蒙版 + 锁定图标
            if not heroOwned then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cellLeft, cellTop, CELL.SIZE, CELL.SIZE, CELL.RADIUS)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
                nvgFill(vg)

                if img.lockIcon >= 0 then
                    local lockSize = 40
                    drawImageCentered(vg, img.lockIcon, cx, cy, lockSize, lockSize, 0.9)
                end
            end

            -- 选中高亮边框
            if heroId == state.selectedHeroId then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cellLeft - 4, cellTop - 4,
                    CELL.SIZE + 8, CELL.SIZE + 8, CELL.RADIUS + 2)
                nvgStrokeColor(vg, nvgRGBA(0xFF, 0xD7, 0x00, 255))
                nvgStrokeWidth(vg, 4)
                nvgStroke(vg)
            end

            ::continue_cell::
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- ── 穿戴按钮 ──
    local _bf1 = BF.begin(vg, "asp_wear", WEAR_BTN.CX, WEAR_BTN.CY, WEAR_BTN.W, WEAR_BTN.H)
    -- 3) 按钮图片 UI_AN_LV
    if img.wearBtn >= 0 then
        drawImageCentered(vg, img.wearBtn, WEAR_BTN.CX, WEAR_BTN.CY, WEAR_BTN.W, WEAR_BTN.H, 1.0)
    end
    -- 4) "穿戴" 文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, WEAR_BTN.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(244, 237, 224, WEAR_BTN.TEXT_A))
    nvgText(vg, WEAR_BTN.CX, WEAR_BTN.CY, "穿戴", nil)
    BF.finish(vg, _bf1)

    nvgRestore(vg)
end

return AvatarSelectPanel
