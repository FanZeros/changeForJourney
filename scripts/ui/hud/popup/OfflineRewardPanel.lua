-- ============================================================================
-- OfflineRewardPanel - 离线收益弹窗
-- ============================================================================
--
-- 【使用说明】
--   local OfflineRewardPanel = require("ui.hud.popup.OfflineRewardPanel")
--
--   -- 初始化（仅一次）：
--   OfflineRewardPanel.init(vg)
--
--   -- 展示离线收益：
--   OfflineRewardPanel.show({
--       offlineSeconds  = 90000,       -- 实际离线秒数
--       maxSeconds      = 86400,       -- 满额时长（24小时），超出按 tailRatio 计
--       tailRatio       = 0.5,         -- 超出满额部分的收益比例
--       multiplier      = 1.0,         -- 收益倍率
--       adventureExp    = 12000,       -- 远征等级经验
--       adventurerExp   = 5600,        -- 远征队员经验（总合）
--       rewards = {                    -- 奖励物品列表
--           { type = "gold",    amount = 5000 },
--           { type = "diamond", amount = 20 },
--           { type = "equip",   templateId = "W3", quality = 3, level = 5 },
--       },
--       onClaim   = function() end,  -- 领取回调
--   })
--
--   -- 在渲染/更新/输入中调用对应方法
-- ============================================================================


local GameConfig        = require("config.GameConfig")
local EquipmentConfig   = require("config.EquipmentConfig")
local ExpTable          = require("config.ExpTable")
local NumberUtil        = require("core.NumberUtil")
local ImageCache        = require("ui.widget.ImageCache")
local DrawUtil          = require("core.DrawUtil")
local BF                = require("systems.ButtonFeedback")
local ResourceDefs      = require("config.ResourceDefs")
local ClientDispatcher  = require("runtime.ClientDispatcher")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格
local RewardCascade = require("ui.widget.RewardCascade")  -- 奖励逐件弹出动画（与关卡奖励同款）
local GameSFX       = require("systems.GameSFX")

local Panel = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量（依据需求文档） ========================

-- 弹窗整体居中于设计稿（1080 宽）。
-- 历史遗留：弹窗加宽到 1760 时 CX 被写成 960，导致整体右移 145px；这里统一以 CENTER_X 推导。
local CENTER_X = DESIGN_W * 0.5  -- 540
-- 面板内边距：弹窗左右各留 20，行内容与面板边缘对齐
local PANEL_W = 1760
local PANEL_LEFT  = CENTER_X - PANEL_W * 0.5
local PANEL_RIGHT = CENTER_X + PANEL_W * 0.5
local ROW_W   = PANEL_W - 160           -- 行背景框宽
local ROW_L   = CENTER_X - ROW_W * 0.5  -- 行左缘
local ROW_R   = CENTER_X + ROW_W * 0.5  -- 行右缘
local ROW_PAD = 60                      -- 行内文字左右内缩

-- 2. 弹窗背景框（九宫格）。奖励区 8 列，面板加宽到接近设计宽。
-- 高度按内容收紧：顶部 220 + 内容到底部按钮 + 50 边距
local PANEL_TOP = 220
local PANEL_H   = 1852
local BG = {
    CX = CENTER_X, CY = PANEL_TOP + PANEL_H * 0.5, W = PANEL_W, H = PANEL_H,
    IT = 180, IL = 40, IR = 40, IB = 50,  -- 九宫格切割
}

-- 3. 标题 "欢迎回来"
local TTL = {
    X = CENTER_X, Y = 413, FONT = 60,
    FR = 255, FG = 255, FB = 255,            -- 纯白
    SR = 0x59, SG = 0x32, SB = 0x19, SW = 6, -- 描边 #593219
}

-- 4+5+6. 离线收益倍率行
local MULT_ROW = {
    CX = CENTER_X, CY = 552, W = ROW_W, H = 72, R = 16,  -- 背景框
    LABEL_X = ROW_L + ROW_PAD, LABEL_FONT = 40,          -- "离线收益倍率" 左对齐
    LABEL_R = 0x72, LABEL_G = 0x58, LABEL_B = 0x50,      -- #725850
    VALUE_X = ROW_R - ROW_PAD, VALUE_FONT = 40,          -- 值 右对齐
    VALUE_SW = 5,                                        -- 纯黑描边
}

-- 7+8+9. 离线时间进度条
local PROG = {
    CX = CENTER_X, CY = 649, W = ROW_W - 200, H = 60,  -- 背景 UI_LXSYJDT_2
    TIME_FONT = 40, TIME_SW = 5,                       -- 计时文字
    TIME_SR = 0x31, TIME_SG = 0x24, TIME_SB = 0x24,    -- 描边 #312424
}

-- 10. 提示文本
local HINT = {
    CX = CENTER_X, CY = 714, FONT = 40,
    NR = 0xb6, NG = 0xb0, NB = 0x9d,         -- 普通文字 #b6b09d
    HR = 0x1b, HG = 0xa1, HB = 0x24,         -- 高亮色 #1ba124
}

-- 11+12. 装饰框 + "离线收益"
local DECO = {
    CX = CENTER_X, CY = 796, W = 900, H = 60,
    FONT = 40,
    FR = 0x8d, FG = 0x5f, FB = 0x41,  -- #8d5f41
}

-- 13+14+15. 远征等级经验行
local EXP_ROW1 = {
    CX = CENTER_X, CY = 899, W = ROW_W, H = 72, R = 16,
    LABEL_X = ROW_L + ROW_PAD, LABEL = "远征等级经验",
    LABEL_R = 0x72, LABEL_G = 0x58, LABEL_B = 0x50,
    VALUE_X = ROW_R - ROW_PAD,
    VALUE_R = 0x63, VALUE_G = 0xff, VALUE_B = 0x84, VALUE_SW = 5,
}

-- 远征队员经验行
local EXP_ROW2 = {
    CX = CENTER_X, CY = 994, W = ROW_W, H = 72, R = 16,
    LABEL_X = ROW_L + ROW_PAD, LABEL = "远征队员经验（总合）",
    LABEL_R = 0x72, LABEL_G = 0x58, LABEL_B = 0x50,
    VALUE_X = ROW_R - ROW_PAD,
    VALUE_R = 0x63, VALUE_G = 0xff, VALUE_B = 0x84, VALUE_SW = 5,
}

-- 队员升级预览行（头像 + 名字 + Lv 变化 + 经验进度条 + 剩余经验数字）
-- 每队最多 4 人（ExpTable.TEAM_MAX_SLOTS），4 行一次排满不滚动。
-- TOP 为整块上缘；每行中心 = TOP + (i-1)*(H+GAP) + H/2
local HERO_ROW = {
    TOP    = 1030,          -- 整块上缘 Y
    H      = 88,            -- 行高
    GAP    = 8,             -- 行间距
    VISIBLE = 4,            -- 可视行数
    ICON   = 68,            -- 头像边长
    ICON_L = ROW_L + 16,    -- 头像左缘
    NAME_X = ROW_L + 16 + 68 + 20,   -- 名字左对齐 X
    NAME_FONT = 30,
    LV_X   = ROW_R - ROW_PAD,        -- Lv 变化右对齐 X
    LV_FONT = 30,
    BAR_X  = ROW_L + 16 + 68 + 20,   -- 经验条左缘
    BAR_W  = 700,                    -- 经验条长度（留出右侧剩余经验数字的位置）
    BAR_H  = 16,
    BAR_CY_OFF = 62,        -- 经验条中心相对行上缘的偏移
    EXP_X  = ROW_R - ROW_PAD,        -- 剩余经验数字右对齐 X
    EXP_FONT = 26,
    TEXT_CY_OFF = 22,       -- 名字/Lv 行中心相对行上缘的偏移
    BG_A   = 13,            -- 行底色透明度（纯黑 5%）
}

-- 16+17. 奖励内容区域
local REWARD_AREA = {
    CX = CENTER_X, CY = 1700, W = ROW_W, H = 460, R = 16,
    PAD = 16,  -- 内边距
}
-- 奖励图标网格（8 列）
local ICON_SIZE = 132
local ROW_GAP   = 14
local COL_GAP   = 12
local COLS      = 8

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

-- 22+23. 领取按钮（底部居中，面板下缘留 70）
local BTN_CLAIM = {
    CX = CENTER_X, CY = PANEL_TOP + PANEL_H - 120, W = 420, H = 100,
    NP = 35,
    TEXT_CX = CENTER_X, TEXT_CY = PANEL_TOP + PANEL_H - 120, FONT = 40,
    TR = 0xD8, TG = 0xC9, TB = 0xA3, TA = 255,
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
}

-- 资源图标缓存
local resourceIconCache = {}

-- ======================== 状态 ========================

local state = {
    open = false,
    -- 数据
    offlineSeconds  = 0,
    maxSeconds      = 86400,  -- 满额 24 小时
    tailRatio       = 0.5,
    multiplier      = 1.0,
    adventureExp    = 0,
    adventurerExp   = 0,
    rewards         = {},
    heroExpPreview  = {},   -- 出战队员升级预览（服务端下发）
    onClaim         = nil,
    -- 滚动
    scrollY    = 0,
    scrollMax  = 0,
    dragging   = false,
    dragLastY  = 0,
    scrollVel  = 0,
    -- 队员升级动画
    heroAnim   = {},   -- [i] = { level = 动画等级, exp = 动画内经验, remain = 剩余待发放经验 }
    heroTime   = 0,    -- 动画已播放秒数
    -- 奖励逐件弹出（与关卡奖励同款；队员经验发完后才开始）
    cascade    = nil,  ---@type table|nil
    cascadeSfx = 0,    -- 已播放入场音的件数
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

-- 队员升级动画参数
local HERO_ANIM_DELAY = 0.55   -- 弹窗开完后停顿多久开始发放
local HERO_EXP_PER_SEC = 0.34  -- 经验发放速度（占总经验比例/秒），1/0.34 ≈ 2.9 秒发完

-- 奖励逐件弹出参数（关卡奖励同款节奏）
local CASCADE_LEAD   = 0.15    -- 队员经验发完后再停顿多久开始发奖励
local CASCADE_INTERVAL = 0.14  -- 逐件间隔
local CASCADE_POP_DUR  = 0.24  -- 单件弹出时长

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

--- 奖励物品的强调色（品质色，用于弹出爆发光效）
---@param item table
---@return number r, number g, number b
local function itemAccent(item)
    local q = 2
    if item.type == "equip" then
        q = item.quality or 1
    else
        local def = RESOURCE_DEFS[item.type]
        q = (def and def.quality) or 2
    end
    local trim = DarkIcon.QUALITY_TRIM[q] or DarkIcon.QUALITY_TRIM[5]
    return trim[1], trim[2], trim[3]
end

--- 队员行上缘 Y
local function heroRowTop(i)
    return HERO_ROW.TOP + (i - 1) * (HERO_ROW.H + HERO_ROW.GAP)
end

--- 队员头像懒加载
local heroIconCache = {}
local function getHeroIcon(heroId)
    local cached = heroIconCache[heroId]
    if cached then return cached end
    if not cachedVg then return -1 end
    local h = nvgCreateImage(cachedVg, "image/角色图标/UI_icon_hero_" .. tostring(heroId) .. ".png", 0)
    heroIconCache[heroId] = h
    return h
end

--- 初始化队员升级动画状态（把每条预览的经验从 0 逐级累积到最终等级）
--- 动画口径与服务端一致：在「原始等级/原始经验」上逐级消耗待发放经验。
local function resetHeroAnim()
    local anim = {}
    for i, item in ipairs(state.heroExpPreview) do
        anim[i] = {
            level  = item.startLevel or item.level or 1,
            exp    = item.startExp or 0,
            remain = item.expGain or 0,
        }
    end
    state.heroAnim = anim
    state.heroTime = 0
end

--- 推进队员升级动画：把 remain 里的经验按等级曲线逐级消耗
local function updateHeroAnim(dt)
    if #state.heroAnim == 0 then return end
    if state.animPhase ~= "open" and state.animPhase ~= "opening" then return end
    state.heroTime = state.heroTime + dt
    if state.heroTime < HERO_ANIM_DELAY then return end

    local budget = (state.heroTime - HERO_ANIM_DELAY) * HERO_EXP_PER_SEC
    for i, a in ipairs(state.heroAnim) do
        local item = state.heroExpPreview[i]
        local total = (item and item.expGain) or 0
        if total > 0 and a.remain > 0 then
            local want = math.floor(total * math.min(1, budget))
            if want > a.remain then want = a.remain end
            -- 逐级消耗
            local consumed = 0
            while want > consumed do
                if a.capped then break end
                local needed = ExpTable.getHeroExpForLevel(a.level) or 0
                if needed <= 0 then a.capped = true break end
                local room = needed - a.exp
                local step = want - consumed
                if step >= room then
                    consumed = consumed + room
                    a.exp = 0
                    a.level = a.level + 1
                    if ExpTable.isHeroMaxLevel(a.level) then a.capped = true end
                else
                    a.exp = a.exp + step
                    consumed = consumed + step
                end
            end
            a.remain = a.remain - consumed
        end
    end
end

--- 动画是否已全部发完
local function heroAnimDone()
    for _, a in ipairs(state.heroAnim) do
        if a.remain > 0 then return false end
    end
    return true
end

-- ======================== Public API ========================

--- 初始化
---@param vg any NanoVG 上下文
function Panel.init(vg)
    cachedVg = vg
    img.bg            = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK.png", 0)
    img.progBg        = nvgCreateImage(vg, "image/进度条/UI_LXSYJDT_2.png", 0)
    img.progFill      = nvgCreateImage(vg, "image/进度条/UI_XDZJDT.png", 0)
    -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_HUANG.png 贴图加载已移除（矢量绘制替代）
    -- [暗黑化 P1-B5] 原 image/按钮/UI_AN_LV.png 贴图加载已移除（矢量绘制替代）
    img.btnGreen      = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)

    if img.bg < 0 then print("[OfflineRewardPanel] WARN: UI_TY_EJQRK.png load failed") end
    print("[OfflineRewardPanel] init OK")
end

--- 展示离线收益弹窗
---@param data table 离线收益数据
function Panel.show(data)
    state.offlineSeconds = data.offlineSeconds or 0
    state.maxSeconds     = data.maxSeconds or 86400
    state.tailRatio      = data.tailRatio or 0.5
    state.multiplier     = data.multiplier or 1.0
    state.adventureExp   = data.adventureExp or 0
    state.adventurerExp  = data.adventurerExp or 0
    state.heroExpPreview = data.heroExpPreview or {}
    state.onClaim        = data.onClaim

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
    state.open           = true
    state.animPhase = "opening"
    state.animStart = time.elapsedTime
    resetHeroAnim()
    state.cascade = RewardCascade.new(#state.rewards, {
        interval     = CASCADE_INTERVAL,
        intervalTail = CASCADE_INTERVAL,
        fastAfter    = 8,
        popDur       = CASCADE_POP_DUR,
        lead         = CASCADE_LEAD,
    })
    state.cascadeSfx = 0
    print("[OfflineRewardPanel] show: offline=" .. state.offlineSeconds .. "s, rewards=" .. #state.rewards
        .. ", heroPreview=" .. #state.heroExpPreview)
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
            return
        end
    end

    -- 队员升级动画
    updateHeroAnim(dt)

    -- 奖励逐件弹出：等队员经验全部发完（或本来就没有队员行）再开始
    if state.cascade then
        if state.cascade.revealStart == 0 then
            if #state.heroAnim == 0 or heroAnimDone() then
                state.cascade:start(time.elapsedTime)
                print("[OfflineRewardPanel] cascade start, items=" .. tostring(#state.rewards))
            end
        else
            -- 逐件入场音
            local due = state.cascade:shownCount()
            while state.cascadeSfx < due do
                state.cascadeSfx = state.cascadeSfx + 1
                local item = state.rewards[state.cascadeSfx]
                if item and item.type == "equip" then
                    GameSFX.play("install")
                else
                    GameSFX.play("ui_click_3")
                end
            end
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

    -- [去阴影] 不再铺全屏黑色遮罩，背景画面保持原亮度（与遗匣页去黑影一致）

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

    -- 8. 进度条填充：满额前按比例，超出满额后保持满格
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

    -- 10. 提示：24 小时内满额，超出部分减半，不封顶
    do
        local fullHours = formatMaxHours(state.maxSeconds)
        local tailPct = math.floor((state.tailRatio or 0.5) * 100 + 0.5)
        local parts
        if state.offlineSeconds > state.maxSeconds then
            parts = {
                { "离线超过", false },
                { fullHours .. "小时", true },
                { "，超出部分按" .. tailPct .. "%计算", false },
            }
        else
            parts = {
                { fullHours .. "小时", true },
                { "内全额，超出按" .. tailPct .. "%", false },
            }
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, HINT.FONT)
        local totalW = 0
        local widths = {}
        for i, part in ipairs(parts) do
            widths[i] = nvgTextBounds(vg, 0, 0, part[1])
            totalW = totalW + widths[i]
        end
        local startX = HINT.CX - totalW * 0.5
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local x = startX
        for i, part in ipairs(parts) do
            if part[2] then
                nvgFillColor(vg, nvgRGBA(HINT.HR, HINT.HG, HINT.HB, 255))
            else
                nvgFillColor(vg, nvgRGBA(HINT.NR, HINT.NG, HINT.NB, 255))
            end
            nvgText(vg, x, HINT.CY, part[1], nil)
            x = x + widths[i]
        end
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

    -- 13. 远征等级经验行
    self_drawExpRow(vg, EXP_ROW1, state.adventureExp)

    -- 14. 远征队员经验行
    self_drawExpRow(vg, EXP_ROW2, state.adventurerExp)

    -- 15. 每个远征队员的实际升级情况（逐级动画）
    self_drawHeroExpList(vg)

    -- 16. 奖励内容背景框
    DrawUtil.drawRoundedRectCentered(vg,
        REWARD_AREA.CX, REWARD_AREA.CY, REWARD_AREA.W, REWARD_AREA.H, REWARD_AREA.R,
        0, 0, 0, 13)

    -- 17. 奖励物品网格（可滚动裁剪区域）
    self_drawRewardGrid(vg)

    -- 领取按钮（居中）
    local _bf2 = BF.begin(vg, "orp_claim", BG.CX, BTN_CLAIM.CY, BTN_CLAIM.W, BTN_CLAIM.H)
    DarkIcon.drawNine(vg, "btn", BG.CX - BTN_CLAIM.W * 0.5, BTN_CLAIM.CY - BTN_CLAIM.H * 0.5, BTN_CLAIM.W, BTN_CLAIM.H, { accent = "gold" })

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_CLAIM.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(BTN_CLAIM.TR, BTN_CLAIM.TG, BTN_CLAIM.TB, BTN_CLAIM.TA))
    nvgText(vg, BG.CX, BTN_CLAIM.TEXT_CY, "领取", nil)
    BF.finish(vg, _bf2)

    -- 恢复变换
    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)

    end) -- pcall end
    if not drawOk then
        print("[OfflineRewardPanel] DRAW ERROR: " .. tostring(drawErr))
    end
end

-- ======================== 内部辅助函数 ========================

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

--- 绘制队员升级列表（头像 + 名字 + Lv 变化 + 经验进度条 + 剩余待发放经验）
function self_drawHeroExpList(vg)
    local preview = state.heroExpPreview
    if #preview == 0 then return end

    local viewH = HERO_ROW.VISIBLE * HERO_ROW.H + (HERO_ROW.VISIBLE - 1) * HERO_ROW.GAP
    local animDone = heroAnimDone()

    nvgSave(vg)
    nvgScissor(vg, ROW_L, HERO_ROW.TOP, ROW_W, viewH)

    for i, item in ipairs(preview) do
        local top = heroRowTop(i)
        local cy  = top + HERO_ROW.H * 0.5
        if cy + HERO_ROW.H * 0.5 >= HERO_ROW.TOP and cy - HERO_ROW.H * 0.5 <= HERO_ROW.TOP + viewH then
            local a = state.heroAnim[i]
            local curLevel = (a and a.level) or item.level or 1
            local curExp   = (a and a.exp) or 0
            local remain   = (a and a.remain) or 0
            local maxExp   = ExpTable.getHeroExpForLevel(curLevel) or 0
            if item.capped or (a and a.capped) then maxExp = 0 end

            -- 行底
            DrawUtil.drawRoundedRectCentered(vg, CENTER_X, cy, ROW_W, HERO_ROW.H, 12,
                0, 0, 0, HERO_ROW.BG_A)

            -- 头像（品质底 + 角色图标）
            local iconCX = HERO_ROW.ICON_L + HERO_ROW.ICON * 0.5
            local q = (item.quality and item.quality > 0) and item.quality or 2
            local qBg = ImageCache.getQualityBg(q)
            if qBg >= 0 then
                DrawUtil.drawImageCentered(vg, qBg, iconCX, cy, HERO_ROW.ICON, HERO_ROW.ICON, 1.0)
            end
            local heroImg = getHeroIcon(item.heroId)
            if heroImg >= 0 then
                local inner = HERO_ROW.ICON - 12
                DrawUtil.drawImageCentered(vg, heroImg, iconCX, cy, inner, inner, 1.0)
            end

            -- 名字（左对齐）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, HERO_ROW.NAME_FONT)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xd8, 0xc9, 0xa3, 255))
            nvgText(vg, HERO_ROW.NAME_X, top + HERO_ROW.TEXT_CY_OFF, item.name or "", nil)

            -- Lv 变化（右对齐；动画中只有真升过级才画「旧 → 新」并转金色）
            local startLevel = item.startLevel or curLevel
            local lvText
            if curLevel > startLevel then
                lvText = "Lv." .. tostring(startLevel) .. " → Lv." .. tostring(curLevel)
            else
                lvText = "Lv." .. tostring(curLevel)
            end
            local lvR, lvG, lvB = 0x9a, 0x9a, 0x9a
            if curLevel > startLevel then
                lvR, lvG, lvB = 0xff, 0xd7, 0x6b
            end
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, HERO_ROW.LV_FONT)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(lvR, lvG, lvB, 255))
            nvgText(vg, HERO_ROW.LV_X, top + HERO_ROW.TEXT_CY_OFF, lvText, nil)

            -- 经验进度条
            local barCY = top + HERO_ROW.BAR_CY_OFF
            local barW  = HERO_ROW.BAR_W
            nvgBeginPath(vg)
            nvgRoundedRect(vg, HERO_ROW.BAR_X, barCY - HERO_ROW.BAR_H * 0.5, barW, HERO_ROW.BAR_H,
                HERO_ROW.BAR_H * 0.5)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
            nvgFill(vg)

            local ratio = 0
            if maxExp > 0 then
                ratio = math.max(0, math.min(1, curExp / maxExp))
            elseif (item.capped or (a and a.capped)) then
                ratio = 1
            end
            if ratio > 0 then
                local fillW = math.max(HERO_ROW.BAR_H, barW * ratio)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, HERO_ROW.BAR_X, barCY - HERO_ROW.BAR_H * 0.5, fillW, HERO_ROW.BAR_H,
                    HERO_ROW.BAR_H * 0.5)
                if animDone then
                    nvgFillColor(vg, nvgRGBA(0x63, 0xff, 0x84, 255))
                else
                    nvgFillColor(vg, nvgRGBA(0xff, 0xc8, 0x4a, 255))
                end
                nvgFill(vg)
            end

            -- 剩余待发放经验（右对齐，数字递减到 0 时显示该级进度）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, HERO_ROW.EXP_FONT)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            if remain > 0 then
                nvgFillColor(vg, nvgRGBA(0xff, 0xc8, 0x4a, 255))
                nvgText(vg, HERO_ROW.EXP_X, barCY, "+" .. NumberUtil.format(remain), nil)
            elseif maxExp > 0 then
                nvgFillColor(vg, nvgRGBA(0x9a, 0x9a, 0x9a, 255))
                nvgText(vg, HERO_ROW.EXP_X, barCY, NumberUtil.format(curExp) .. "/" .. NumberUtil.format(maxExp), nil)
            else
                nvgFillColor(vg, nvgRGBA(0xff, 0xd7, 0x6b, 255))
                nvgText(vg, HERO_ROW.EXP_X, barCY, "已满级", nil)
            end
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)
end

--- 绘制奖励物品网格（逐件弹出，与关卡奖励同款动画）
function self_drawRewardGrid(vg)
    local items = state.rewards
    if #items == 0 then return end

    local totalRows = math.ceil(#items / COLS)
    local cascade = state.cascade

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

            -- 逐件弹出：未到出场时刻只画预告框，弹出中叠加爆发+变换
            local popT = cascade and cascade:t(idx) or 1
            local popping = false
            if popT == nil then
                RewardCascade.anticipate(vg, cx, cy,
                    cascade:elapsed() - cascade:startAt(idx), ICON_SIZE)
                goto continue
            elseif popT < 1 then
                popping = true
            end

            nvgSave(vg)
            if popping then
                local ar, ag, ab = itemAccent(item)
                RewardCascade.burst(vg, cx, cy, popT, ICON_SIZE, ar, ag, ab)
                RewardCascade.applyPop(vg, cx, cy, popT, 1.0)
            end

            if item.type == "equip" then
                -- 已生成的真实装备：品质底 + 模板图标
                local q = item.quality or 1
                local qBgImg = ImageCache.getQualityBg(q)
                if qBgImg >= 0 then
                    DrawUtil.drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end
                local equipImg = ImageCache.getEquipIcon(item.templateId)
                if equipImg >= 0 then
                    local inner = ICON_SIZE - 16
                    DrawUtil.drawImageCentered(vg, equipImg, cx, cy, inner, inner, 1.0)
                else
                    DrawUtil.drawTextStroke(vg, cx, cy, "?", 40,
                        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
                end
                -- 等级角标（底部居中）
                if item.level and item.level > 0 then
                    local lvlText = "Lv." .. tostring(item.level)
                    DrawUtil.drawTextStroke(vg, cx, cy + ICON_SIZE * 0.34, lvlText, 22,
                        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
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

            nvgRestore(vg)
            if popping then
                RewardCascade.glint(vg, cx, cy, popT, ICON_SIZE)
            end

            ::continue::
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)
end

-- ======================== 输入处理 ========================

function Panel.claim()
    if not state.open then return false end
    print("[OfflineRewardPanel] 领取 clicked")
    if state.onClaim then
        state.onClaim()
    end
    Panel.close()
    return true
end

--- 处理点击（松开时调用）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function Panel.handleInput(dx, dy)
    if not state.open then return false end

    -- 领取按钮（居中）
    if DrawUtil.hitTest(dx, dy, BG.CX, BTN_CLAIM.CY, BTN_CLAIM.W, BTN_CLAIM.H) then
        BF.trigger("orp_claim")
        return Panel.claim()
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
