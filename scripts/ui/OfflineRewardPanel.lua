-- ============================================================================
-- OfflineRewardPanel - 离线收益弹窗
-- ============================================================================
--
-- 【使用说明】
--   local OfflineRewardPanel = require("ui.OfflineRewardPanel")
--
--   -- 初始化（仅一次）：
--   OfflineRewardPanel.init(vg)
--
--   -- 展示离线收益：
--   OfflineRewardPanel.show({
--       offlineSeconds  = 43200,       -- 离线秒数
--       maxSeconds      = 43200,       -- 最大可累积秒数（12小时）
--       multiplier      = 1.0,         -- 收益倍率
--       adventureExp    = 12000,       -- 冒险等级经验
--       adventurerExp   = 5600,        -- 冒险家经验（总合）
--       rewards = {                    -- 奖励物品列表
--           { type = "gold",    amount = 5000 },
--           { type = "diamond", amount = 20 },
--           { type = "equip",   templateId = "W3", quality = 3, level = 5 },
--       },
--       onClaim   = function(doubled) end,  -- 领取回调(doubled=是否翻倍)
--   })
--
--   -- 在渲染/更新/输入中调用对应方法
-- ============================================================================

local AdManager       = require("systems.AdManager")

local GameConfig        = require("config.GameConfig")
local EquipmentConfig   = require("config.EquipmentConfig")
local NumberUtil        = require("core.NumberUtil")
local ImageCache        = require("ui.ImageCache")
local DrawUtil          = require("core.DrawUtil")
local BF                = require("systems.ButtonFeedback")
local ResourceDefs      = require("config.ResourceDefs")
local ClientDispatcher  = require("network.ClientDispatcher")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local Panel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量（依据需求文档） ========================

-- 1. 全屏遮罩
local MASK_ALPHA = 128  -- 50% 不透明度

-- 2. 弹窗背景框（九宫格）
local BG = {
    CX = 540, CY = 1160, W = 950, H = 1631,
    IT = 180, IL = 40, IR = 40, IB = 50,  -- 九宫格切割
}

-- 3. 标题 "对战记录"
local TTL = {
    X = 540, Y = 413, FONT = 60,
    FR = 255, FG = 255, FB = 255,            -- 纯白
    SR = 0x59, SG = 0x32, SB = 0x19, SW = 6, -- 描边 #593219
}

-- 4+5+6. 离线收益倍率行
local MULT_ROW = {
    CX = 540, CY = 552, W = 800, H = 80, R = 16,  -- 背景框
    LABEL_X = 180, LABEL_FONT = 40,                  -- "离线收益倍率" 左对齐
    LABEL_R = 0x72, LABEL_G = 0x58, LABEL_B = 0x50,  -- #725850
    VALUE_X = 921, VALUE_FONT = 40,                   -- 值 右对齐
    VALUE_SW = 5,                                      -- 纯黑描边
}

-- 7+8+9. 离线时间进度条
local PROG = {
    CX = 540, CY = 649, W = 810, H = 60,  -- 背景 UI_LXSYJDT_2
    TIME_FONT = 40, TIME_SW = 5,            -- 计时文字
    TIME_SR = 0x31, TIME_SG = 0x24, TIME_SB = 0x24, -- 描边 #312424
}

-- 10. 提示文本
local HINT = {
    CX = 540, CY = 714, FONT = 40,
    NR = 0xb6, NG = 0xb0, NB = 0x9d,         -- 普通文字 #b6b09d
    HR = 0x1b, HG = 0xa1, HB = 0x24,         -- 高亮 "12小时" #1ba124
}

-- 11+12. 装饰框 + "离线收益"
local DECO = {
    CX = 540, CY = 796, W = 660, H = 60,
    FONT = 40,
    FR = 0x8d, FG = 0x5f, FB = 0x41,  -- #8d5f41
}

-- 13+14+15. 冒险等级经验行
local EXP_ROW1 = {
    CX = 540, CY = 899, W = 800, H = 80, R = 16,
    LABEL_X = 180, LABEL = "冒险等级经验",
    LABEL_R = 0x72, LABEL_G = 0x58, LABEL_B = 0x50,
    VALUE_X = 921,
    VALUE_R = 0x63, VALUE_G = 0xff, VALUE_B = 0x84, VALUE_SW = 5,
}

-- 冒险家经验行
local EXP_ROW2 = {
    CX = 540, CY = 994, W = 800, H = 80, R = 16,
    LABEL_X = 180, LABEL = "冒险家经验（总合）",
    LABEL_R = 0x72, LABEL_G = 0x58, LABEL_B = 0x50,
    VALUE_X = 921,
    VALUE_R = 0x63, VALUE_G = 0xff, VALUE_B = 0x84, VALUE_SW = 5,
}

-- 16+17. 奖励内容区域
local REWARD_AREA = {
    CX = 540, CY = 1406, W = 800, H = 714, R = 16,
    PAD = 40,  -- 内边距
}
-- 奖励图标网格
local ICON_SIZE = 160
local ROW_GAP   = 16
local COL_GAP   = 14
local COLS      = 4

-- 奖励裁剪区域（内容背景框内边距40）
local CLIP = {}
do
    local left   = REWARD_AREA.CX - REWARD_AREA.W * 0.5 + REWARD_AREA.PAD
    local top    = REWARD_AREA.CY - REWARD_AREA.H * 0.5 + REWARD_AREA.PAD
    local right  = REWARD_AREA.CX + REWARD_AREA.W * 0.5 - REWARD_AREA.PAD
    local bottom = REWARD_AREA.CY + REWARD_AREA.H * 0.5 - REWARD_AREA.PAD
    CLIP.LEFT   = left
    CLIP.TOP    = top
    CLIP.RIGHT  = right
    CLIP.BOTTOM = bottom
    CLIP.W      = right - left
    CLIP.H      = bottom - top
end

-- 列 X 坐标（4列居中排布在裁剪区域内）
local TOTAL_ROW_W = COLS * ICON_SIZE + (COLS - 1) * COL_GAP
local FIRST_COL_LEFT = CLIP.LEFT + (CLIP.W - TOTAL_ROW_W) * 0.5
local COL_CX = {}
for c = 1, COLS do
    COL_CX[c] = FIRST_COL_LEFT + (c - 1) * (ICON_SIZE + COL_GAP) + ICON_SIZE * 0.5
end

-- 19+20+21. 翻倍按钮
local BTN_DOUBLE = {
    CX = 330, CY = 1855, W = 390, H = 100,
    NP = 35,  -- 九宫格切割
    ICON_CX = 271, ICON_CY = 1855, ICON_W = 70, ICON_H = 70,
    TEXT_CX = 361, TEXT_CY = 1855, FONT = 40,
    TR = 0, TG = 0, TB = 0, TA = 191,  -- 纯黑75%
}

-- 22+23. 领取按钮
local BTN_CLAIM = {
    CX = 750, CY = 1855, W = 390, H = 100,
    NP = 35,
    TEXT_CX = 750, TEXT_CY = 1855, FONT = 40,
    TR = 0, TG = 0, TB = 0, TA = 191,
}

-- 数量角标
local BADGE_FONT   = 36
local BADGE_STROKE = 4

-- ======================== 资源定义表（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- ======================== 图片句柄 ========================

local img = {
    bg            = -1,   -- UI_TY_EJQRK.png
    progBg        = -1,   -- UI_LXSYJDT_2.png
    progFill      = -1,   -- UI_LXSYJDT_1.png
    decoFrame     = -1,   -- UI_JJC_BTBJ.png
    btnYellow     = -1,   -- UI_AN_HUANG.png
    btnGreen      = -1,   -- UI_AN_LV.png
    adIcon        = -1,   -- UI_icon_KGG_X.png
    privPointIcon = -1,   -- UI_icon_TQD.png（特权点图标）
}

-- 资源图标缓存
local resourceIconCache = {}

-- ======================== 状态 ========================

local state = {
    open = false,
    -- 数据
    offlineSeconds  = 0,
    maxSeconds      = 43200,  -- 12小时
    multiplier      = 1.0,
    adventureExp    = 0,
    adventurerExp   = 0,
    rewards         = {},
    onClaim         = nil,
    noDouble        = false,   -- 是否禁用翻倍按钮（扫荡等已应用奖励的场景）
    doubled         = false,   -- 是否已点击翻倍
    privilegePoint  = 0,       -- 当前特权点数（>0 时用特权点翻倍，否则看广告）
    usedPrivilege   = false,   -- 是否消耗了特权点翻倍
    -- 浮动提示
    floatText     = nil,
    floatTextTime = 0,
    -- 滚动
    scrollY    = 0,
    scrollMax  = 0,
    dragging   = false,
    dragLastY  = 0,
    scrollVel  = 0,
    -- 动画
    animPhase  = "none",  -- "none"|"opening"|"open"|"closing"
    animStart  = 0,
}

-- 滚动参数
local SCROLL_FRICTION = 0.90
local SCROLL_MIN_VEL  = 0.5

-- 动画参数
local ANIM_OPEN_DUR  = 0.30
local ANIM_CLOSE_DUR = 0.20

local cachedVg = nil

-- ======================== 缓动函数 ========================

local function easeOutBack(t)
    local s = 1.70158; t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 工具函数 ========================

local function clampScroll()
    state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY))
end

local function getResourceIcon(resType)
    local cached = resourceIconCache[resType]
    if cached then return cached end
    if not cachedVg then return -1 end
    local def = RESOURCE_DEFS[resType]
    if not def then return -1 end
    local h = nvgCreateImage(cachedVg, def.iconPath, 0)
    resourceIconCache[resType] = h
    return h
end

--- 格式化秒数为 HH:MM:SS
local function formatTime(seconds)
    local s = math.floor(math.max(0, seconds))
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    return string.format("%02d:%02d:%02d", h, m, sec)
end

--- 格式化最大小时（从秒数）
local function formatMaxHours(seconds)
    return tostring(math.floor(seconds / 3600))
end

--- 获取格子中心坐标
local function getCellCenter(row, col)
    local cx = COL_CX[col]
    local cy = CLIP.TOP + ICON_SIZE * 0.5 + (row - 1) * (ICON_SIZE + ROW_GAP)
    return cx, cy
end

-- ======================== Public API ========================

--- 初始化
---@param vg any NanoVG 上下文
function Panel.init(vg)
    cachedVg = vg
    img.bg            = nvgCreateImage(vg, "image/UI_TY_EJQRK.png", 0)
    img.progBg        = nvgCreateImage(vg, "image/UI_LXSYJDT_2.png", 0)
    img.progFill      = nvgCreateImage(vg, "image/UI_XDZJDT.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_AN_HUANG.png 贴图加载已移除（矢量绘制替代）
    -- [暗黑化 P1-B5] 原 image/UI_AN_LV.png 贴图加载已移除（矢量绘制替代）
    img.btnGreen      = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    img.adIcon        = nvgCreateImage(vg, "image/UI_icon_KGG_X.png", 0)
    img.privPointIcon = nvgCreateImage(vg, "image/UI_icon_TQD.png", 0)

    if img.bg < 0 then print("[OfflineRewardPanel] WARN: UI_TY_EJQRK.png load failed") end
    print("[OfflineRewardPanel] init OK")
end

--- 展示离线收益弹窗
---@param data table 离线收益数据
function Panel.show(data)
    state.offlineSeconds = data.offlineSeconds or 0
    state.maxSeconds     = data.maxSeconds or 43200
    state.multiplier     = data.multiplier or 1.0
    state.adventureExp   = data.adventureExp or 0
    state.adventurerExp  = data.adventurerExp or 0
    state.onClaim        = data.onClaim
    state.noDouble       = data.noDouble or false

    -- 排序奖励：资源在前，装备在后
    local resources = {}
    local equips = {}
    for _, item in ipairs(data.rewards or {}) do
        if item.type == "equip" then
            equips[#equips + 1] = item
        else
            resources[#resources + 1] = item
        end
    end
    table.sort(equips, function(a, b)
        local qa = a.quality or 1
        local qb = b.quality or 1
        if qa ~= qb then return qa > qb end
        return (a.level or 1) > (b.level or 1)
    end)
    state.rewards = {}
    for _, item in ipairs(resources) do state.rewards[#state.rewards + 1] = item end
    for _, item in ipairs(equips)    do state.rewards[#state.rewards + 1] = item end

    -- 计算滚动范围
    local totalRows = math.ceil(math.max(#state.rewards, 1) / COLS)
    local totalH = totalRows * ICON_SIZE + (totalRows - 1) * ROW_GAP
    state.scrollMax = math.max(0, totalH - CLIP.H)

    state.scrollY        = 0
    state.scrollVel      = 0
    state.dragging       = false
    state.bonusClaimed   = false   -- 是否已领取额外奖励
    state.bonusPreviewApplied = false
    state.privilegePoint = data.privilegePoint or 0
    state.usedPrivilege  = false
    -- 额外奖励相关
    state.bonusRemaining = data.bonusRemaining or 0
    state.bonusMaxDaily  = data.bonusMaxDaily or 3
    state.bonusHours     = data.bonusHours or 2
    state.bonusPreview   = data.bonusPreview  -- { gold, adventureExp, adventurerExp }
    state.open           = true
    state.animPhase = "opening"
    state.animStart = time.elapsedTime
    -- 订阅 adConfirmed 模块：处理断线重连期间服务端确认的广告奖励
    ClientDispatcher.subscribe("adConfirmed", Panel._onAdConfirmed)
    print("[OfflineRewardPanel] show: offline=" .. state.offlineSeconds .. "s, rewards=" .. #state.rewards)
end

--- 关闭
function Panel.close()
    if state.animPhase == "closing" then return end
    state.animPhase = "closing"
    state.animStart = time.elapsedTime
end

--- 是否打开
---@return boolean
function Panel.isOpen()
    return state.open
end

--- adConfirmed 模块推送回调（断线重连期间服务端确认广告奖励）
function Panel._onAdConfirmed(data)
    if not state.open then return end
    if not data or data.scene ~= "offline_bonus" then return end
    if state.bonusClaimed then return end  -- 已标记过，忽略重复推送
    print("[OfflineRewardPanel] _onAdConfirmed: server confirmed offline_bonus ad, applying bonus")
    state.bonusClaimed = true
    self_applyBonusPreview()
end

--- 更新（惯性滚动 + 动画状态机）
---@param dt number
function Panel.update(dt)
    if not state.open then return end

    -- 动画
    if state.animPhase == "opening" then
        if time.elapsedTime - state.animStart >= ANIM_OPEN_DUR then
            state.animPhase = "open"
        end
    elseif state.animPhase == "closing" then
        if time.elapsedTime - state.animStart >= ANIM_CLOSE_DUR then
            state.open = false
            state.animPhase = "none"
            ClientDispatcher.unsubscribe("adConfirmed", Panel._onAdConfirmed)
            return
        end
    end

    -- 惯性滚动
    if not state.dragging and math.abs(state.scrollVel) > SCROLL_MIN_VEL then
        state.scrollY = state.scrollY + state.scrollVel
        state.scrollVel = state.scrollVel * SCROLL_FRICTION
        clampScroll()
    elseif not state.dragging then
        state.scrollVel = 0
    end
end

-- ======================== 绘制 ========================

--- 绘制离线收益弹窗
---@param vg any NanoVG 上下文
function Panel.draw(vg)
    if not state.open then return end

    local drawOk, drawErr = pcall(function()

    -- 动画进度
    local animAlpha = 1.0
    local animScale = 1.0
    if state.animPhase == "opening" then
        local t = math.min(1.0, (time.elapsedTime - state.animStart) / ANIM_OPEN_DUR)
        animAlpha = t
        animScale = easeOutBack(t)
    elseif state.animPhase == "closing" then
        local t = math.min(1.0, (time.elapsedTime - state.animStart) / ANIM_CLOSE_DUR)
        animAlpha = 1.0 - t
        animScale = 1.0 - easeInCubic(t) * 0.3
    end

    -- 1. 全屏黑色遮罩 50%
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(MASK_ALPHA * animAlpha)))
    nvgFill(vg)

    -- 缩放动画
    local pivotX, pivotY = BG.CX, BG.CY
    nvgSave(vg)
    nvgTranslate(vg, pivotX, pivotY)
    nvgScale(vg, animScale, animScale)
    nvgTranslate(vg, -pivotX, -pivotY)
    nvgGlobalAlpha(vg, animAlpha)

    -- 2. 弹窗背景框（九宫格）
    DarkIcon.drawNine(vg, "panel", BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5, BG.W, BG.H, { titleH = BG.IT })

    -- 3. 标题 "欢迎回来"
    DrawUtil.drawTextStroke(vg, TTL.X, TTL.Y, "欢迎回来",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        TTL.FR, TTL.FG, TTL.FB, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- 4. 离线收益倍率背景框
    DrawUtil.drawRoundedRectCentered(vg,
        MULT_ROW.CX, MULT_ROW.CY, MULT_ROW.W, MULT_ROW.H, MULT_ROW.R,
        0, 0, 0, 13)  -- 纯黑 5% 不透明度

    -- 5. "离线收益倍率" 文字（左对齐）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, MULT_ROW.LABEL_FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(MULT_ROW.LABEL_R, MULT_ROW.LABEL_G, MULT_ROW.LABEL_B, 255))
    nvgText(vg, MULT_ROW.LABEL_X, MULT_ROW.CY, "离线收益倍率", nil)

    -- 6. 倍率值（右对齐，纯黑描边）
    local multText = string.format("%.0f%%", state.multiplier * 100)
    DrawUtil.drawTextStroke(vg, MULT_ROW.VALUE_X, MULT_ROW.CY, multText,
        MULT_ROW.VALUE_FONT, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        255, 255, 255, MULT_ROW.VALUE_SW)

    -- 7. 离线时间进度条背景
    DrawUtil.drawImageCentered(vg, img.progBg,
        PROG.CX, PROG.CY, PROG.W, PROG.H, 1.0)

    -- 8. 进度条填充（与背景保持 5 像素内边距）
    local progress = 0
    if state.maxSeconds > 0 then
        progress = math.min(1.0, state.offlineSeconds / state.maxSeconds)
    end
    if progress > 0 and img.progFill >= 0 then
        local pad = 5
        local innerW = PROG.W - pad * 2
        local innerH = PROG.H - pad * 2
        local fillW = innerW * progress
        local innerLeft = PROG.CX - PROG.W * 0.5 + pad
        local innerTop  = PROG.CY - PROG.H * 0.5 + pad
        nvgSave(vg)
        nvgScissor(vg, innerLeft, innerTop, fillW, innerH)
        DrawUtil.drawImageCentered(vg, img.progFill,
            PROG.CX, PROG.CY, innerW, innerH, 1.0)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- 9. 进度条上的时间文字
    DrawUtil.drawTextStroke(vg, PROG.CX, PROG.CY, formatTime(state.offlineSeconds),
        PROG.TIME_FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, PROG.TIME_SW,
        { strokeColor = { PROG.TIME_SR, PROG.TIME_SG, PROG.TIME_SB } })

    -- 10. 提示文本 "当前最多可获得离线12小时收益"（混合颜色）
    do
        local maxHours = formatMaxHours(state.maxSeconds)
        local prefix   = "当前最多可获得离线"
        local highlight = maxHours .. "小时"
        local suffix   = "收益"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, HINT.FONT)
        -- 测量各段实际绘制文本的宽度
        local wPre  = nvgTextBounds(vg, 0, 0, prefix)
        local wHigh = nvgTextBounds(vg, 0, 0, highlight)
        local wSuf  = nvgTextBounds(vg, 0, 0, suffix)
        local totalW = wPre + wHigh + wSuf
        local startX = HINT.CX - totalW * 0.5
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        -- 前缀（普通色）
        nvgFillColor(vg, nvgRGBA(HINT.NR, HINT.NG, HINT.NB, 255))
        nvgText(vg, startX, HINT.CY, prefix, nil)
        -- 高亮小时数
        nvgFillColor(vg, nvgRGBA(HINT.HR, HINT.HG, HINT.HB, 255))
        nvgText(vg, startX + wPre, HINT.CY, highlight, nil)
        -- 后缀（普通色）
        nvgFillColor(vg, nvgRGBA(HINT.NR, HINT.NG, HINT.NB, 255))
        nvgText(vg, startX + wPre + wHigh, HINT.CY, suffix, nil)
    end

    -- 11. 装饰框
    DrawUtil.drawImageCentered(vg, img.decoFrame,
        DECO.CX, DECO.CY, DECO.W, DECO.H, 1.0)

    -- 12. "离线收益" 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, DECO.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(DECO.FR, DECO.FG, DECO.FB, 255))
    nvgText(vg, DECO.CX, DECO.CY, "离线收益", nil)

    -- 13. 冒险等级经验行
    self_drawExpRow(vg, EXP_ROW1, state.adventureExp)

    -- 14. 冒险家经验行
    self_drawExpRow(vg, EXP_ROW2, state.adventurerExp)

    -- 16. 奖励内容背景框
    DrawUtil.drawRoundedRectCentered(vg,
        REWARD_AREA.CX, REWARD_AREA.CY, REWARD_AREA.W, REWARD_AREA.H, REWARD_AREA.R,
        0, 0, 0, 13)

    -- 17. 奖励物品网格（可滚动裁剪区域）
    self_drawRewardGrid(vg)

    -- 额外奖励按钮可用条件：未领取过、未禁用、有剩余次数
    local canBonus = not state.bonusClaimed and not state.noDouble and state.bonusRemaining > 0

    if canBonus then
        -- 19. "+2小时"按钮（黄色九宫格）— 左侧
        local _bf1 = BF.begin(vg, "orp_bonus", BTN_DOUBLE.CX, BTN_DOUBLE.CY, BTN_DOUBLE.W, BTN_DOUBLE.H)
        DarkIcon.drawNine(vg, "btn", BTN_DOUBLE.CX - BTN_DOUBLE.W * 0.5, BTN_DOUBLE.CY - BTN_DOUBLE.H * 0.5, BTN_DOUBLE.W, BTN_DOUBLE.H, { accent = "gold" })

        -- 20. 图标（有特权点→特权点图标，否则→广告图标）
        local bonusIcon = (state.privilegePoint > 0) and img.privPointIcon or img.adIcon
        DrawUtil.drawImageCentered(vg, bonusIcon,
            BTN_DOUBLE.ICON_CX, BTN_DOUBLE.ICON_CY,
            BTN_DOUBLE.ICON_W, BTN_DOUBLE.ICON_H, 1.0)

        -- 21. "+2小时" 文字 + 消耗提示 + 剩余次数
        local bonusBtnText = "+" .. tostring(state.bonusHours) .. "小时"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_DOUBLE.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_DOUBLE.TR, BTN_DOUBLE.TG, BTN_DOUBLE.TB, BTN_DOUBLE.TA))
        nvgText(vg, BTN_DOUBLE.TEXT_CX, BTN_DOUBLE.TEXT_CY - 16, bonusBtnText, nil)
        -- 消耗提示：有特权点→固定扣1点；否则看广告
        nvgFontSize(vg, 24)
        if state.privilegePoint > 0 then
            nvgFillColor(vg, nvgRGBA(80, 60, 40, 200))
            nvgText(vg, BTN_DOUBLE.TEXT_CX, BTN_DOUBLE.TEXT_CY + 10,
                "消耗1特权点", nil)
        else
            nvgFillColor(vg, nvgRGBA(80, 60, 40, 180))
            nvgText(vg, BTN_DOUBLE.TEXT_CX, BTN_DOUBLE.TEXT_CY + 10,
                "观看广告", nil)
        end
        -- 剩余次数小字
        nvgFontSize(vg, 24)
        nvgFillColor(vg, nvgRGBA(80, 60, 40, 160))
        nvgText(vg, BTN_DOUBLE.TEXT_CX, BTN_DOUBLE.TEXT_CY + 34,
            "剩余" .. tostring(state.bonusRemaining) .. "次", nil)
        BF.finish(vg, _bf1)

        -- 22. 领取按钮（绿色九宫格）— 右侧
        local _bf2 = BF.begin(vg, "orp_claim", BTN_CLAIM.CX, BTN_CLAIM.CY, BTN_CLAIM.W, BTN_CLAIM.H)
        DarkIcon.drawNine(vg, "btn", BTN_CLAIM.CX - BTN_CLAIM.W * 0.5, BTN_CLAIM.CY - BTN_CLAIM.H * 0.5, BTN_CLAIM.W, BTN_CLAIM.H, { accent = "green" })

        -- 23. "领取" 文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_CLAIM.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_CLAIM.TR, BTN_CLAIM.TG, BTN_CLAIM.TB, BTN_CLAIM.TA))
        nvgText(vg, BTN_CLAIM.TEXT_CX, BTN_CLAIM.TEXT_CY, "领取", nil)
        BF.finish(vg, _bf2)
    else
        -- 已领取额外奖励 或 noDouble 或次数用完：隐藏额外按钮，领取按钮居中
        local claimCX = BG.CX  -- 弹窗水平中心
        local _bf2 = BF.begin(vg, "orp_claim", claimCX, BTN_CLAIM.CY, BTN_CLAIM.W, BTN_CLAIM.H)
        DarkIcon.drawNine(vg, "btn", claimCX - BTN_CLAIM.W * 0.5, BTN_CLAIM.CY - BTN_CLAIM.H * 0.5, BTN_CLAIM.W, BTN_CLAIM.H, { accent = "green" })

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_CLAIM.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_CLAIM.TR, BTN_CLAIM.TG, BTN_CLAIM.TB, BTN_CLAIM.TA))
        nvgText(vg, claimCX, BTN_CLAIM.TEXT_CY, "领取", nil)
        BF.finish(vg, _bf2)
    end

    -- 浮动提示（PC端无法播放广告等）
    if state.floatText then
        local FLOAT_DUR  = 1.5
        local FLOAT_DIST = 100
        local elapsed = time.elapsedTime - state.floatTextTime
        if elapsed >= FLOAT_DUR then
            state.floatText = nil
        else
            local t      = elapsed / FLOAT_DUR
            local offsetY = -FLOAT_DIST * t
            DrawUtil.drawTextStroke(vg,
                BTN_DOUBLE.CX, BTN_DOUBLE.CY + offsetY,
                state.floatText,
                40, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 80, 80, 6,
                { alpha = 1.0 - t })
        end
    end

    -- 恢复变换
    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)

    end) -- pcall end
    if not drawOk then
        print("[OfflineRewardPanel] DRAW ERROR: " .. tostring(drawErr))
    end
end

-- ======================== 内部辅助函数 ========================

--- 重新计算奖励列表滚动范围
local function refreshRewardScrollMax()
    local totalRows = math.ceil(math.max(#state.rewards, 1) / COLS)
    local totalH = totalRows * ICON_SIZE + (totalRows - 1) * ROW_GAP
    state.scrollMax = math.max(0, totalH - CLIP.H)
    clampScroll()
end

--- 将额外奖励预览值叠加到面板显示数据上
function self_applyBonusPreview()
    if state.bonusPreviewApplied then return end
    local bp = state.bonusPreview
    if not bp then return end
    state.bonusPreviewApplied = true
    state.adventureExp  = state.adventureExp  + (bp.adventureExp or 0)
    state.adventurerExp = state.adventurerExp + (bp.adventurerExp or 0)
    -- 叠加金币到 rewards 列表中对应条目
    local goldAdded = bp.gold or 0
    if goldAdded > 0 then
        for _, item in ipairs(state.rewards) do
            if item.type == "gold" then
                item.amount = (item.amount or 0) + goldAdded
                goldAdded = 0
                break
            end
        end
        -- 如果没有金币条目，新增一个
        if goldAdded > 0 then
            state.rewards[#state.rewards + 1] = { type = "gold", amount = goldAdded }
        end
    end

    for _, item in ipairs(bp.rewards or {}) do
        state.rewards[#state.rewards + 1] = item
    end
    refreshRewardScrollMax()
end

-- ======================== 内部绘制函数 ========================

--- 绘制经验行（背景 + 标签 + 值）
function self_drawExpRow(vg, cfg, value)
    -- 背景框
    DrawUtil.drawRoundedRectCentered(vg,
        cfg.CX, cfg.CY, cfg.W, cfg.H, cfg.R,
        0, 0, 0, 13)
    -- 标签（左对齐）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 40)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(cfg.LABEL_R, cfg.LABEL_G, cfg.LABEL_B, 255))
    nvgText(vg, cfg.LABEL_X, cfg.CY, cfg.LABEL, nil)
    -- 值（右对齐，绿色描边）
    local valText = "+" .. NumberUtil.format(value)
    DrawUtil.drawTextStroke(vg, cfg.VALUE_X, cfg.CY, valText,
        40, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        cfg.VALUE_R, cfg.VALUE_G, cfg.VALUE_B, cfg.VALUE_SW)
end

--- 绘制奖励物品网格
function self_drawRewardGrid(vg)
    local items = state.rewards
    if #items == 0 then return end

    local totalRows = math.ceil(#items / COLS)

    nvgSave(vg)
    nvgScissor(vg, CLIP.LEFT, CLIP.TOP, CLIP.W, CLIP.H)

    for row = 1, totalRows do
        for col = 1, COLS do
            local idx = (row - 1) * COLS + col
            local item = items[idx]
            if not item then goto continue end

            local cx, rawCY = getCellCenter(row, col)
            local cy = rawCY - state.scrollY

            -- 跳过不可见
            if cy + ICON_SIZE * 0.5 < CLIP.TOP - 10 then goto continue end
            if cy - ICON_SIZE * 0.5 > CLIP.BOTTOM + 10 then goto continue end

            if item.type == "equip" then
                -- 装备种子图标（问号样式，与战利品界面一致）
                local q = item.quality or 1
                local qBgImg = ImageCache.getQualityBg(q)
                if qBgImg >= 0 then
                    DrawUtil.drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end
                -- "?" 问号（居中）
                DrawUtil.drawTextStroke(vg, cx, cy, "?", 56,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
                -- 等级角标（底部居中）
                if item.level and item.level > 0 then
                    local lvlText = "Lv." .. tostring(item.level)
                    DrawUtil.drawTextStroke(vg, cx, cy + ICON_SIZE * 0.35, lvlText, 32,
                        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
                end
                -- 数量角标（右上角，仅 count>1 时显示）
                if item.count and item.count > 1 then
                    local cntText = "x" .. tostring(item.count)
                    local bx2 = cx + ICON_SIZE * 0.5 - 8
                    local by2 = cy - ICON_SIZE * 0.5 + 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, BADGE_FONT)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep2 = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep2
                        nvgText(vg, bx2 + math.cos(sa) * BADGE_STROKE, by2 + math.sin(sa) * BADGE_STROKE, cntText, nil)
                    end
                    nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
                    nvgText(vg, bx2, by2, cntText, nil)
                end
            else
                -- 资源图标
                local def = RESOURCE_DEFS[item.type]
                local q = def and def.quality or 1
                local qBgImg = ImageCache.getQualityBg(q)
                if qBgImg >= 0 then
                    DrawUtil.drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end
                local resImg = getResourceIcon(item.type)
                if resImg >= 0 then
                    local inner = ICON_SIZE - 24
                    DrawUtil.drawImageCentered(vg, resImg, cx, cy, inner, inner, 1.0)
                end
                -- 数量角标（右下角）
                if item.amount and item.amount > 0 then
                    local amtText = NumberUtil.format(item.amount)
                    local bx = cx + ICON_SIZE * 0.5 - 8
                    local by = cy + ICON_SIZE * 0.5 - 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, BADGE_FONT)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, bx + math.cos(sa) * BADGE_STROKE, by + math.sin(sa) * BADGE_STROKE, amtText, nil)
                    end
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, bx, by, amtText, nil)
                end
            end

            ::continue::
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

--- 处理点击（松开时调用）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function Panel.handleInput(dx, dy)
    if not state.open then return false end

    -- "+2小时"额外奖励按钮（仅可用时可点击）
    local canBonus = not state.bonusClaimed and not state.noDouble and state.bonusRemaining > 0
    if canBonus
       and DrawUtil.hitTest(dx, dy, BTN_DOUBLE.CX, BTN_DOUBLE.CY, BTN_DOUBLE.W, BTN_DOUBLE.H) then
        BF.trigger("orp_bonus")
        if state.privilegePoint > 0 then
            -- 有特权点：直接消耗特权点领取额外奖励
            print("[OfflineRewardPanel] 特权点+2小时 clicked")
            state.bonusClaimed  = true
            state.usedPrivilege = true
            -- 增加显示数值（加上 bonusPreview）
            self_applyBonusPreview()
        else
            -- 无特权点：看广告领取额外奖励（含 PC/Web）
            print("[OfflineRewardPanel] 广告+2小时 clicked — showing ad")
            AdManager.ShowAdWithMute(function(result)
                if not result.success then
                    print("[OfflineRewardPanel] 广告未完成（reason=" .. tostring(result.reason) .. "），不领取额外")
                    if result.reason == "already_loading" then
                        state.floatText = "广告正在加载中…"
                    else
                        state.floatText = "广告加载失败，请稍后再试"
                    end
                    state.floatTextTime = time.elapsedTime
                    return
                end
                -- AD_CONFIRM 已由 AdManager 统一发送（AdHandler 推送 adConfirmed 模块）
                print("[OfflineRewardPanel] 广告完成 — applying +2h bonus preview")
                state.bonusClaimed = true
                self_applyBonusPreview()
            end, "offline_bonus")
        end
        return true
    end

    -- 领取按钮（额外奖励已领/不可用时居中，否则在右侧）
    local claimHitCX = (not canBonus) and BG.CX or BTN_CLAIM.CX
    if DrawUtil.hitTest(dx, dy, claimHitCX, BTN_CLAIM.CY, BTN_CLAIM.W, BTN_CLAIM.H) then
        BF.trigger("orp_claim")
        print("[OfflineRewardPanel] 领取 clicked, bonusClaimed=" .. tostring(state.bonusClaimed)
            .. " usedPrivilege=" .. tostring(state.usedPrivilege))
        if state.onClaim then
            state.onClaim(state.bonusClaimed, state.usedPrivilege)
        end
        Panel.close()
        return true
    end

    -- 弹窗内部消费事件（阻止穿透）
    if DrawUtil.hitTest(dx, dy, BG.CX, BG.CY, BG.W, BG.H) then
        return true
    end

    -- 弹窗外部 → 不关闭（必须点按钮领取）
    return true  -- 仍然消费事件阻止穿透
end

--- 处理拖拽开始
---@param dx number
---@param dy number
---@return boolean
function Panel.handleDragBegin(dx, dy)
    if not state.open then return false end
    -- 奖励区域内开始拖拽
    if dx >= CLIP.LEFT and dx <= CLIP.RIGHT
       and dy >= CLIP.TOP and dy <= CLIP.BOTTOM then
        state.dragging  = true
        state.dragLastY = dy
        state.scrollVel = 0
    end
    return true
end

--- 处理拖拽移动
---@param dx number
---@param dy number
---@return boolean
function Panel.handleDragMove(dx, dy)
    if not state.open then return false end
    if state.dragging then
        local delta = state.dragLastY - dy
        state.scrollY = state.scrollY + delta
        state.scrollVel = delta
        state.dragLastY = dy
        clampScroll()
    end
    return true
end

--- 处理拖拽结束
---@param dx number
---@param dy number
---@return boolean
function Panel.handleDragEnd(dx, dy)
    if not state.open then return false end
    if state.dragging then
        state.dragging = false
    end
    return true
end

--- 处理滚轮
---@param wheel number
function Panel.handleScroll(wheel)
    if not state.open then return end
    state.scrollY = state.scrollY - wheel * 60
    clampScroll()
    state.scrollVel = 0
end

return Panel
