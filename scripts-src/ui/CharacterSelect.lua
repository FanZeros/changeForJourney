-- ============================================================================
-- CharacterSelect.lua — 选择初始角色界面
-- 情景对话1结束后进入，全屏覆盖，选好角色后开始冒险
-- ============================================================================

local DrawUtil   = require("core.DrawUtil")
local GameConfig = require("config.GameConfig")
local BF         = require("systems.ButtonFeedback")

local CharacterSelect = {}

-- ======================== 设计常量 ========================
local DW = GameConfig.Design.WIDTH   -- 1080
local DH = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 角色数据 ========================
local CHARACTERS = {
    {
        id       = 1,
        heroId   = 3,       -- 对应 HeroConfig: 琳达（射手/Ranger）
        class    = "射手",
        title    = "疾风之箭",
        intro    = "擅长远程射击的射手",
        icon     = "image/ICON_ZY_4.png",
        portrait = "image/角色立绘/UI_DLH_3.png",
        classColor = { 0x8e, 0xff, 0x78 },  -- #8eff78
        titleColor = { 0xc2, 0xff, 0xb6 },  -- #c2ffb6
    },
    {
        id       = 2,
        heroId   = 1,       -- 对应 HeroConfig: 卡琳（战士/Warrior）
        class    = "战士",
        title    = "初心之剑",
        intro    = "擅长快速打击的战士",
        icon     = "image/ICON_ZY_2.png",
        portrait = "image/角色立绘/UI_DLH_1.png",
        classColor = { 0xff, 0xb4, 0x00 },  -- #ffb400
        titleColor = { 0xff, 0xd9, 0x7e },  -- #ffd97e
    },
    {
        id       = 3,
        heroId   = 2,       -- 对应 HeroConfig: 麦琪（法师/Mage）
        class    = "法师",
        title    = "炽焰之心",
        intro    = "擅长火焰魔法的法师",
        icon     = "image/ICON_ZY_3.png",
        portrait = "image/角色立绘/UI_DLH_2.png",
        classColor = { 0x2b, 0xed, 0xff },  -- #2bedff
        titleColor = { 0xa4, 0xfc, 0xff },  -- #a4fcff
    },
}

-- ======================== 布局参数 ========================

--- 角色立绘
local PORTRAIT = { cx = 540, cy = 902, w = 1696, h = 1113 }

--- 下方背景面板: 1080×1450，底部对齐屏幕底部
local BG_PANEL = { cx = 540, cy = DH - 1450 * 0.5, w = 1080, h = 1450 }

--- 职业名称: "战士" 等
local CLASS_NAME = {
    cx = 174, cy = 1291, fontSize = 100,
    r = 0xff, g = 0xb4, b = 0x00,     -- #ffb400
    strokeSize = 6,
}

--- 角色称号: "初心之剑" 等 (左对齐)
local TITLE = {
    x = 306, cy = 1306, fontSize = 56,
    r = 255, g = 255, b = 255,
    strokeSize = 6,
}

--- 一句话介绍 (左对齐)
local INTRO = {
    x = 74, cy = 1397, fontSize = 48,
    r = 255, g = 255, b = 255,
    strokeSize = 6,
}

--- "选择一位初始伙伴"
local SELECT_TEXT = {
    cx = 542, cy = 1526, fontSize = 58,
    r = 0x5f, g = 0x37, b = 0x37,      -- #5f3737
}

--- 职业卡片
local CARD = { w = 270, h = 340 }
local CARD_GAP = 41
--- 三张卡片中心 X: 射手=229, 战士=540, 法师=851
local CARD_CX = { 229, 229 + CARD.w + CARD_GAP, 229 + (CARD.w + CARD_GAP) * 2 }
local CARD_CY = 1798

--- 卡片内-职业图标
local ICON = { w = 168, h = 168 }
local ICON_CY = 1747

--- 卡片内-职业名称
local CARD_NAME = {
    cy = 1881, fontSize = 48,
    r = 255, g = 255, b = 255,
    strokeColor = { 0x31, 0x24, 0x24 },
    strokeSize = 6,
}

--- 卡片内-已选择文本
local SELECTED_TEXT = {
    cy = 2014, fontSize = 48,
    r = 0xff, g = 0xef, b = 0x67,       -- #ffef67
    strokeColor = { 0x25, 0x25, 0x25 },
    strokeSize = 6,
}

--- 开始冒险按钮
local BTN = { cx = 540, cy = 2164, w = 410, h = 100 }
local BTN_TEXT = {
    cx = 540, cy = 2164, fontSize = 48,
    r = 0, g = 0, b = 0, alpha = 0.75,
}

-- ======================== 动画参数 ========================
local ANIM_ENTER_DURATION = 0.5   -- 进入动画时长（秒）
local ANIM_EXIT_DURATION  = 0.35  -- 退出动画时长（秒）

-- 进入动画：面板从下方滑入的距离
local PANEL_SLIDE_DIST    = 300

-- ======================== 内部状态 ========================
local vg_           = nil
local active_       = false
local selectedIdx_  = 2        -- 默认选中战士（中间）
local onFinishCb_   = nil

-- 动画状态
local animState_    = "none"   -- "none" | "entering" | "idle" | "exiting"
local animTimer_    = 0
local pendingFinishId_ = nil   -- 退出动画结束后要传给回调的 characterId

-- 图片句柄
local imgBG_        = -1       -- 关卡背景（MAP_1）
local imgPanel_     = -1       -- UI_XZCSZY_1
local imgCardBG1_   = -1       -- 未选中卡片背景
local imgCardBG2_   = -1       -- 已选中卡片背景
local imgButton_    = -1       -- 开始冒险按钮
local imgPortraits_ = {}       -- [1..3] 角色立绘
local imgIcons_     = {}       -- [1..3] 职业图标

-- ======================== 动画辅助 ========================

--- ease-out cubic: 快进慢出
local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

--- ease-in cubic: 慢进快出（用于退出）
local function easeInCubic(t)
    return t * t * t
end

-- ======================== 公开接口 ========================

--- 初始化（加载共享图片资源，只调用一次）
---@param vg any NanoVG context
function CharacterSelect.init(vg)
    vg_ = vg
    imgPanel_   = nvgCreateImage(vg, "image/UI_XZCSZY_1.png", 0)
    imgCardBG1_ = nvgCreateImage(vg, "image/UI_XZCSZY_AN1.png", 0)
    imgCardBG2_ = nvgCreateImage(vg, "image/UI_XZCSZY_AN2.png", 0)
    imgButton_  = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)

    for i, ch in ipairs(CHARACTERS) do
        imgPortraits_[i] = nvgCreateImage(vg, ch.portrait, 0)
        imgIcons_[i]     = nvgCreateImage(vg, ch.icon, 0)
    end

    print("[CharacterSelect] init: panel=" .. imgPanel_
        .. " card1=" .. imgCardBG1_ .. " card2=" .. imgCardBG2_
        .. " btn=" .. imgButton_)
end

--- 显示角色选择界面
---@param config table
---   config.background  string|nil 背景图路径
---   config.onFinish    function(characterId) 选择完成的回调
function CharacterSelect.show(config)
    config = config or {}
    active_      = true
    selectedIdx_ = 2   -- 默认选中战士

    -- 启动进入动画
    animState_ = "entering"
    animTimer_ = 0
    pendingFinishId_ = nil

    -- 加载关卡背景
    local bgPath = config.background or "image/关卡地图/MAP_1.png"
    imgBG_ = nvgCreateImage(vg_, bgPath, 0)
    print("[CharacterSelect] show: bg=" .. imgBG_)

    onFinishCb_ = config.onFinish
end

--- 每帧更新
---@param dt number
function CharacterSelect.update(dt)
    if not active_ then return end

    if animState_ == "entering" then
        animTimer_ = animTimer_ + dt
        if animTimer_ >= ANIM_ENTER_DURATION then
            animTimer_ = ANIM_ENTER_DURATION
            animState_ = "idle"
        end
    elseif animState_ == "exiting" then
        animTimer_ = animTimer_ + dt
        if animTimer_ >= ANIM_EXIT_DURATION then
            -- 退出动画完成
            animState_ = "none"
            active_ = false
            if onFinishCb_ and pendingFinishId_ then
                local cb = onFinishCb_
                local id = pendingFinishId_
                onFinishCb_ = nil
                pendingFinishId_ = nil
                cb(id)
            end
        end
    end
end

--- 绘制
function CharacterSelect.draw()
    if not active_ then return end

    -- 计算动画进度
    local globalAlpha = 1.0
    local panelOffsetY = 0
    local portraitScale = 1.0

    if animState_ == "entering" then
        local t = animTimer_ / ANIM_ENTER_DURATION
        local ease = easeOutCubic(t)
        globalAlpha = ease
        panelOffsetY = PANEL_SLIDE_DIST * (1 - ease)  -- 从下方滑入
        portraitScale = 0.85 + 0.15 * ease             -- 从 85% 缩放到 100%
    elseif animState_ == "exiting" then
        local t = animTimer_ / ANIM_EXIT_DURATION
        local ease = easeInCubic(t)
        globalAlpha = 1.0 - ease
        panelOffsetY = PANEL_SLIDE_DIST * ease          -- 向下滑出
        portraitScale = 1.0 - 0.15 * ease               -- 从 100% 缩放到 85%
    end

    nvgSave(vg_)
    nvgScissor(vg_, 0, 0, DW, DH)
    nvgGlobalAlpha(vg_, globalAlpha)

    -- 0. 全屏黑底
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, DW, DH)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg_)

    -- 1. 关卡背景图
    if imgBG_ >= 0 then
        DrawUtil.drawImageCentered(vg_, imgBG_, DW * 0.5, DH * 0.5, DW, DH, 1.0)
    end

    -- 2. 当前选中角色的立绘（带缩放动画）
    local portrait = imgPortraits_[selectedIdx_]
    if portrait and portrait >= 0 then
        local pw = PORTRAIT.w * portraitScale
        local ph = PORTRAIT.h * portraitScale
        DrawUtil.drawImageCentered(vg_, portrait, PORTRAIT.cx, PORTRAIT.cy, pw, ph, 1.0)
    end

    -- 以下 UI 元素都带下方偏移动画
    nvgSave(vg_)
    nvgTranslate(vg_, 0, panelOffsetY)

    -- 3. 下方背景面板
    if imgPanel_ >= 0 then
        DrawUtil.drawImageCentered(vg_, imgPanel_, BG_PANEL.cx, BG_PANEL.cy, BG_PANEL.w, BG_PANEL.h, 1.0)
    end

    -- 4. 当前选中角色的文字信息
    local ch = CHARACTERS[selectedIdx_]
    if ch then
        -- 职业名称（居中, 斜体, 每角色独立颜色）
        local cc = ch.classColor
        DrawUtil.drawTextStroke(vg_,
            CLASS_NAME.cx, CLASS_NAME.cy, ch.class, CLASS_NAME.fontSize,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            cc[1], cc[2], cc[3],
            CLASS_NAME.strokeSize,
            { italic = true })

        -- 角色称号（左对齐, 斜体, 每角色独立颜色）
        local tc = ch.titleColor
        DrawUtil.drawTextStroke(vg_,
            TITLE.x, TITLE.cy, ch.title, TITLE.fontSize,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            tc[1], tc[2], tc[3],
            TITLE.strokeSize,
            { italic = true })

        -- 一句话介绍（左对齐）
        DrawUtil.drawTextStroke(vg_,
            INTRO.x, INTRO.cy, ch.intro, INTRO.fontSize,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
            INTRO.r, INTRO.g, INTRO.b,
            INTRO.strokeSize)
    end

    -- 5. "选择一位初始伙伴"（斜体，无描边）
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, SELECT_TEXT.fontSize)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 斜体：通过 skewX 模拟
    nvgSave(vg_)
    nvgTranslate(vg_, SELECT_TEXT.cx, SELECT_TEXT.cy)
    nvgSkewX(vg_, -0.18)
    nvgTranslate(vg_, -SELECT_TEXT.cx, -SELECT_TEXT.cy)
    nvgFillColor(vg_, nvgRGBA(SELECT_TEXT.r, SELECT_TEXT.g, SELECT_TEXT.b, 255))
    nvgText(vg_, SELECT_TEXT.cx, SELECT_TEXT.cy, "选择一位初始伙伴", nil)
    nvgRestore(vg_)

    -- 6. 三张职业卡片
    for i, ch2 in ipairs(CHARACTERS) do
        local cx = CARD_CX[i]
        local isSelected = (i == selectedIdx_)

        local _bfCard = BF.begin(vg_, "cs_card_" .. i, cx, CARD_CY, CARD.w, CARD.h)

        -- 卡片背景
        local cardImg = isSelected and imgCardBG2_ or imgCardBG1_
        if cardImg >= 0 then
            DrawUtil.drawImageCentered(vg_, cardImg, cx, CARD_CY, CARD.w, CARD.h, 1.0)
        end

        -- 职业图标
        local icon = imgIcons_[i]
        if icon and icon >= 0 then
            DrawUtil.drawImageCentered(vg_, icon, cx, ICON_CY, ICON.w, ICON.h, 1.0)
        end

        -- 职业名称
        DrawUtil.drawTextStroke(vg_,
            cx, CARD_NAME.cy, ch2.class, CARD_NAME.fontSize,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            CARD_NAME.r, CARD_NAME.g, CARD_NAME.b,
            CARD_NAME.strokeSize,
            { strokeColor = CARD_NAME.strokeColor })

        -- 已选择标签
        if isSelected then
            DrawUtil.drawTextStroke(vg_,
                cx, SELECTED_TEXT.cy, "已选择", SELECTED_TEXT.fontSize,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                SELECTED_TEXT.r, SELECTED_TEXT.g, SELECTED_TEXT.b,
                SELECTED_TEXT.strokeSize,
                { strokeColor = SELECTED_TEXT.strokeColor })
        end

        BF.finish(vg_, _bfCard)
    end

    -- 7. 开始冒险按钮
    local _bfStart = BF.begin(vg_, "cs_start", BTN.cx, BTN.cy, BTN.w, BTN.h)
    if imgButton_ >= 0 then
        DrawUtil.drawImageCentered(vg_, imgButton_, BTN.cx, BTN.cy, BTN.w, BTN.h, 1.0)
    end

    -- 按钮文本
    nvgFontFace(vg_, "sans")
    nvgFontSize(vg_, BTN_TEXT.fontSize)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(BTN_TEXT.r, BTN_TEXT.g, BTN_TEXT.b,
                               math.floor(BTN_TEXT.alpha * 255)))
    nvgText(vg_, BTN_TEXT.cx, BTN_TEXT.cy, "开始冒险", nil)
    BF.finish(vg_, _bfStart)

    nvgRestore(vg_)  -- panelOffsetY translate

    nvgResetScissor(vg_)
    nvgRestore(vg_)  -- globalAlpha + scissor
end

--- 处理点击
---@param x number 设计坐标 X
---@param y number 设计坐标 Y
---@return boolean consumed 是否消费了该事件
function CharacterSelect.handleTap(x, y)
    if not active_ then return false end
    -- 动画期间不响应点击
    if animState_ ~= "idle" then return true end

    -- 检查三张职业卡片
    for i = 1, #CHARACTERS do
        if DrawUtil.hitTest(x, y, CARD_CX[i], CARD_CY, CARD.w, CARD.h) then
            BF.trigger("cs_card_" .. i)
            if selectedIdx_ ~= i then
                selectedIdx_ = i
                print("[CharacterSelect] selected: " .. CHARACTERS[i].class)
            end
            return true
        end
    end

    -- 检查开始冒险按钮
    if DrawUtil.hitTest(x, y, BTN.cx, BTN.cy, BTN.w, BTN.h) then
        BF.trigger("cs_start")
        local ch = CHARACTERS[selectedIdx_]
        print("[CharacterSelect] confirm: " .. ch.class .. " (heroId=" .. ch.heroId .. ")")
        -- 启动退出动画
        animState_ = "exiting"
        animTimer_ = 0
        pendingFinishId_ = ch.heroId  -- 传实际 HeroConfig ID
        return true
    end

    -- 全屏覆盖，吞掉其他点击
    return true
end

--- 是否正在显示
---@return boolean
function CharacterSelect.isActive()
    return active_
end

function CharacterSelect.close()
    active_ = false
    animState_ = "none"
    animTimer_ = 0
    pendingFinishId_ = nil
    onFinishCb_ = nil
end

--- 获取当前选中的角色 ID
---@return number|nil
function CharacterSelect.getSelectedId()
    if not active_ then return nil end
    return CHARACTERS[selectedIdx_].id
end

return CharacterSelect
