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
local I18n              = require("core.I18n")
local ClientDispatcher  = require("runtime.ClientDispatcher")
local DarkIcon = require("core.DarkIcon")  -- 矢量九宫格
local RewardCascade = require("ui.widget.RewardCascade")  -- 奖励逐件弹出动画（与关卡奖励同款）
---@class RewardCascadeTimeline : table  逐件弹出时间轴（定义见 ui/widget/RewardCascade.lua）
local GameSFX       = require("systems.GameSFX")
local HeroFrame = require("ui.widget.HeroFrame")
local EquipmentDetail = require("ui.character.equip.EquipmentDetail")  -- [奖励可点击] 装备只读详情（遗匣同款）

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
local PANEL_H   = 1400
local BG = {
    CX = CENTER_X, CY = PANEL_TOP + PANEL_H * 0.5, W = PANEL_W, H = PANEL_H,
    IT = 180, IL = 40, IR = 40, IB = 50,  -- 九宫格切割
}

-- 3. 标题 "欢迎回来"（顶栏装饰线上一行，字号收一档）
local TTL = {
    X = CENTER_X, Y = 312, FONT = 46,
    FR = 255, FG = 255, FB = 255,            -- 纯白
    SR = 0x59, SG = 0x32, SB = 0x19, SW = 6, -- 描边 #593219
}

-- 7+8+9. 离线时间进度条（倍率行已去掉，整体上移）
local PROG = {
    CX = CENTER_X, CY = 580, W = ROW_W - 200, H = 60,  -- 背景 UI_LXSYJDT_2
    TIME_FONT = 40, TIME_SW = 5,                       -- 计时文字
    TIME_SR = 0x31, TIME_SG = 0x24, TIME_SB = 0x24,    -- 描边 #312424
}

-- 10. 提示文本
local HINT = {
    CX = CENTER_X, CY = 648, FONT = 34,
    NR = 0xb6, NG = 0xb0, NB = 0x9d,         -- 普通文字 #b6b09d
    HR = 0x1b, HG = 0xa1, HB = 0x24,         -- 高亮色 #1ba124
}

-- 远征等级经验行（挪到时间条上方）
local EXP_ROW1 = {
    CX = CENTER_X, CY = 468, W = ROW_W, H = 84, R = 16, FONT = 52,
    LABEL_X = ROW_L + ROW_PAD, LABEL = "远征等级经验",
    LABEL_R = 0x72, LABEL_G = 0x58, LABEL_B = 0x50,
    VALUE_X = ROW_R - ROW_PAD,
    VALUE_R = 0x63, VALUE_G = 0xff, VALUE_B = 0x84, VALUE_SW = 5,
}

-- 队员升级预览：一行一个队伍。头像在上，经验条和等级在头像下方。
-- 行高按头像放大一倍留出；实际只显示有人的队伍，空队不占高度。
local HERO_ROW = {
    TOP     = 710,          -- 整块上缘 Y
    H       = 220,          -- 一行（一个队伍）的高度
    GAP     = 14,           -- 队与队之间的间距
    VISIBLE = 3,            -- 最多三队
    SLOTS   = 4,            -- 每队槽位数
    PAD_X   = 24,           -- 行内左右留白
    ICON    = 128,          -- 头像边长（原 64 放大一倍）
    LV_FONT   = 26,
    BAR_H     = 12,
    BG_A      = 26,         -- 行底色透明度
}

-- 16+17. 奖励内容区域（紧跟队员区，避免中间留大片空白）
local REWARD_AREA = {
    CX = CENTER_X, CY = 1270, W = ROW_W, H = 552, R = 16,
    PAD = 12,  -- 内边距
}
-- 奖励图标网格（10 列，一行多放两个）
local ICON_SIZE = 120
local ROW_GAP   = 12
local COL_GAP   = 16
local COLS      = 10

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

-- 角标字号自适应：按实际文本宽度测量，太长（大数值/长名字）时等比缩小，避免溢出图标
local BADGE_FONT_MIN = 22
local function fitBadgeFont(vg, text)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BADGE_FONT)
    local w = nvgTextBounds(vg, 0, 0, text)
    local maxW = ICON_SIZE - 16
    if w <= maxW then return BADGE_FONT end
    return math.max(BADGE_FONT_MIN, BADGE_FONT * maxW / w)
end

-- ======================== 资源定义表（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- ======================== 图片句柄 ========================

local img = {
    bg            = -1,   -- UI_TY_EJQRK.png
    progBg        = -1,   -- UI_LXSYJDT_2.png
    progFill      = -1,   -- UI_LXSYJDT_1.png
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
    hardCapSeconds  = 86400 * 7,  -- [7日硬顶] 离线收益最多累积 7 日
    cappedByHardCap = false,      -- [7日硬顶] 本次是否触顶
    multiplier      = 1.0,
    adventureExp    = 0,
    adventurerExp   = 0,
    playerStartLevel = nil, ---@type number|nil
    playerEndLevel   = nil, ---@type number|nil
    rewards         = {},
    teamSources     = {},   -- 结算时冻结的各队来源，不从当前战线重新推断。
    heroExpPreview  = {},   -- 出战队员升级预览（服务端下发）
    onClaim         = nil,
    -- [奖励可点击] 点击查看的物品详情
    detailItem      = nil,  -- 当前查看的奖励 item
    detailIdx       = 0,    -- 当前查看的奖励索引
    -- 滚动
    scrollY    = 0,
    scrollMax  = 0,
    dragging   = false,
    dragLastY  = 0,
    scrollVel  = 0,
    followScroll = true,  -- 奖励逐件弹出时自动跟随滚到最新一行（底部）
    -- 队员升级动画
    heroAnim   = {},   -- [i] = { level = 动画等级, exp = 动画内经验, remain = 剩余待发放经验 }
    heroTime   = 0,    -- 动画已播放秒数
    -- 奖励逐件弹出（与队员经验动画同时开始，大批量时尾段加速）
    cascade    = nil,  ---@type any
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
local HERO_ANIM_STAGGER = 0.1  -- 相邻队员错开的秒数
local HERO_ANIM_TICKS_PER_SEC = 1000000  -- 仅显示时钟按最近微秒归一，不逐帧舍入 dt
local HERO_ANIM_DURATION_TICKS = 5000000 -- 约 5 秒发完，不随帧率加速

-- 奖励逐件弹出参数：前段保留仪式感，后段按总件数加速。
local CASCADE_INTERVAL = 0.14  -- 前 10 件间隔
local CASCADE_INTERVAL_TAIL = 0.06  -- 第 11~20 件间隔
local CASCADE_INTERVAL_FASTER = 0.02  -- 第 21 件起的最大间隔
local CASCADE_FAST_AFTER = 10
local CASCADE_FASTER_AFTER = 20
local CASCADE_TAIL_BUDGET = 2.0  -- 第 20 件之后最多再排队 2 秒
local CASCADE_POP_DUR  = 0.24  -- 单件弹出时长不变

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

--- 奖励逐件弹出时自动跟随：把最新出场的那行滚到裁剪区底部（显示最下方内容）。
--- 玩家手动拖拽/滚轮后停止跟随。
local function syncCascadeScroll()
    local cascade = state.cascade
    if not cascade or cascade.revealStart == 0 then return end
    if state.dragging or not state.followScroll then return end
    if state.scrollMax <= 0 then return end
    local shown = cascade:shownCount()
    if shown <= COLS then
        state.scrollY = 0
        return
    end
    local row = math.ceil(shown / COLS)
    local _, rawCY = getCellCenter(row, 1)
    local bottom = rawCY + ICON_SIZE * 0.5
    state.scrollY = bottom - CLIP.BOTTOM
    clampScroll()
    state.scrollVel = 0
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

--- 按实际队号匹配来源，来源数组可以乱序，旧数据按数组位置兼容。
local function sourceForTeam(teamIdx)
    for index, source in ipairs(state.teamSources) do
        if (source.teamIdx or index) == teamIdx then return source end
    end
    return nil
end

--- 有来源但无经验的队伍仍显示说明（例如通天塔暂停离线收益）。
local function heroRowHeight(members, source)
    if #members > 0 then return HERO_ROW.H end
    return source and 48 or 0
end

--- 绘制和输入共用队伍并集高度，来源专用行也纳入奖励区定位。
---@param groups table[]
---@return number
local function heroBlockHeight(groups)
    local height = 0
    for t = 1, HERO_ROW.VISIBLE do
        local rowH = heroRowHeight(groups[t], sourceForTeam(t))
        if rowH > 0 then
            if height > 0 then height = height + HERO_ROW.GAP end
            height = height + rowH
        end
    end
    return height
end

--- 按队伍把预览分成 1..3 行，每行最多 4 人。
--- 没有 teamIdx 的旧数据按出现顺序每 4 人一队。
---@param preview table[]
---@return table[]
local function groupHeroPreview(preview)
    ---@type table[]
    local groups = { {}, {}, {} }
    local hasTeam = false
    for _, item in ipairs(preview) do
        if item.teamIdx then hasTeam = true break end
    end
    if hasTeam then
        for _, item in ipairs(preview) do
            local t = item.teamIdx or 1
            if t < 1 then t = 1 elseif t > 3 then t = 3 end
            if #groups[t] < HERO_ROW.SLOTS then
                groups[t][#groups[t] + 1] = item
            end
        end
    else
        local t = 1
        for _, item in ipairs(preview) do
            if #groups[t] >= HERO_ROW.SLOTS then
                t = t + 1
                if t > 3 then break end
            end
            groups[t][#groups[t] + 1] = item
        end
    end
    return groups
end

--- 当前弹窗的动态布局：奖励区和按钮紧跟实际队员区，面板高度按内容算
--- 返回的 shift 是奖励网格相对静态裁剪区的上移量
---@return number shift, number panelH, number panelCY, number rewardCY, number claimCY
local function layoutNow()
    local blockH = heroBlockHeight(groupHeroPreview(state.heroExpPreview))
    local rewardTop = HERO_ROW.TOP + blockH + 24
    local rewardCY = rewardTop + REWARD_AREA.H * 0.5
    local claimCY = rewardTop + REWARD_AREA.H + 30 + BTN_CLAIM.H * 0.5
    local panelBottom = claimCY + BTN_CLAIM.H * 0.5 + 50
    local panelH = panelBottom - PANEL_TOP
    local clipTop = rewardTop + REWARD_AREA.PAD
    return CLIP.TOP - clipTop, panelH, PANEL_TOP + panelH * 0.5, rewardCY, claimCY
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

-- ======================== [奖励可点击] 详情查看 ========================

--- 命中检测：设计坐标 → 奖励网格索引（仅已弹出的奖励可点）
---@param dx number
---@param dy number
---@return integer|nil
local function hitRewardCell(dx, dy)
    if #state.rewards == 0 then return nil end
    -- 逐件弹出未开始/未出场的奖励不可点
    local cascade = state.cascade
    if not cascade or cascade.revealStart == 0 then return nil end

    local saved = layoutNow()  -- 第一个返回值 = 奖励网格整体上移量
    local clipTop = CLIP.TOP - saved
    if dx < CLIP.LEFT or dx > CLIP.RIGHT or dy < clipTop or dy > clipTop + CLIP.H then
        return nil
    end

    local totalRows = math.ceil(#state.rewards / COLS)
    for row = 1, totalRows do
        for col = 1, COLS do
            local idx = (row - 1) * COLS + col
            if state.rewards[idx] then
                local cx, rawCY = getCellCenter(row, col)
                local cy = rawCY - saved - state.scrollY
                local half = ICON_SIZE * 0.5
                if dx >= cx - half and dx <= cx + half and dy >= cy - half and dy <= cy + half then
                    local popT = cascade:t(idx)
                    if popT and popT >= 1 then return idx end
                    return nil
                end
            end
        end
    end
    return nil
end

--- 用显示译文逐字折行，显式换行保留，资源用途不被裁成单行。
local function descriptionLines(vg, item)
    local desc = ResourceDefs.getRewardDescription(item)
    local source = I18n.lookup(desc)
    local lines, line = {}, ""
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    for _, codepoint in utf8.codes(source) do
        local char = utf8.char(codepoint)
        if char == "\n" then
            lines[#lines + 1], line = line, ""
        elseif line ~= "" and I18n.displayBounds(vg, 0, 0, line .. char) > 680 then
            lines[#lines + 1], line = line, char
        else
            line = line .. char
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

--- 详情浮层尺寸/位置（装备=遗匣同款只读详情；资源=信息卡）
---@return number x, number y, number w, number h
local function detailBounds(vg)
    local item = state.detailItem
    if item and item.type == "equip" and item.equip then
        local w, h = EquipmentDetail.readOnlySize(item.equip)
        local x = CENTER_X - w * 0.5
        local y = math.max(PANEL_TOP + 120, 900 - h * 0.5)
        return x, y, w, h
    end
    local lines = descriptionLines(vg, item)
    local w, h = 760, 280 + #lines * 38
    return CENTER_X - w * 0.5, 900 - h * 0.5, w, h
end

--- 绘制详情浮层（在面板内容之后、动画变换之内）
---@param vg any
local function drawDetailOverlay(vg)
    local item = state.detailItem
    if not item then return end

    -- 半透明遮罩压暗弹窗其余部分，突出详情
    local _, panelH = layoutNow()
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgRect(vg, BG.CX - BG.W * 0.5, PANEL_TOP, BG.W, panelH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    if item.type == "equip" and item.equip then
        -- 装备：遗匣同款只读详情（无穿戴/分解按钮）
        local x, y = detailBounds()
        EquipmentDetail.drawReadOnly(vg, item.equip, x, y)
    else
        -- 资源：信息卡（图标 + 名称 + 数量）
        local x, y, w, h = detailBounds(vg)
        local cx, cy = x + w * 0.5, y + h * 0.5
        DrawUtil.drawRoundedRectCentered(vg, cx, cy, w, h, 20, 24, 20, 18, 245)
        DrawUtil.drawRoundedRectCentered(vg, cx, cy, w - 8, h - 8, 16, 40, 33, 28, 255)

        local def = RESOURCE_DEFS[item.type]
        local q = (def and def.quality) or 2
        -- 品质底 + 图标
        local qBgImg = ImageCache.getQualityBg(q)
        local iconCY = y + 96
        if qBgImg >= 0 then
            DrawUtil.drawImageCentered(vg, qBgImg, cx, iconCY, 150, 150, 1.0)
        end
        local resImg = getResourceIcon(item.type)
        if resImg >= 0 then
            DrawUtil.drawImageCentered(vg, resImg, cx, iconCY, 120, 120, 1.0)
        end
        -- 名称
        local name = ResourceDefs.getRewardDisplayName(item)
        DrawUtil.drawTextStroke(vg, cx, y + 184, name, 36,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 231, 210, 161, 4,
            { strokeColor = { 0x31, 0x24, 0x24 } })
        -- 数量
        if item.amount and item.amount > 0 then
            DrawUtil.drawTextStroke(vg, cx, y + 228, "x" .. NumberUtil.format(item.amount), 32,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 0x63, 0xff, 0x84, 4,
                { strokeColor = { 0x31, 0x24, 0x24 } })
        end
        local lines = descriptionLines(vg, item)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(232, 220, 200, 255))
        for index, line in ipairs(lines) do
            I18n.displayText(vg, x + 40, y + 270 + (index - 1) * 38, line, nil)
        end
    end

    -- 关闭提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xb6, 0xb0, 0x9d, 220))
    nvgText(vg, BG.CX, PANEL_TOP + panelH - 40, "点击任意处返回", nil)
    nvgRestore(vg)
end

--- 初始化动画只读副本，使用与正式英雄升级相同的经验曲线。
local function resetHeroAnim()
    local anim = {}
    for i, item in ipairs(state.heroExpPreview) do
        local start = ExpTable.simulateHeroExp(item.startLevel or item.level or 1, item.startExp or 0, 0)
        anim[i] = {
            level  = start.level,
            exp    = start.exp,
            remain = start.capped and 0 or math.max(0, math.floor(item.expGain or 0)),
            issued = 0,
            capped = start.capped,
        }
    end
    state.heroAnim = anim
    state.heroTime = 0
end

--- 累计目标减去已发经验，只消费本帧增量；达到满级后动画正常完成。
local function updateHeroAnim(dt)
    if #state.heroAnim == 0 then return end
    if state.animPhase ~= "open" and state.animPhase ~= "opening" then return end
    state.heroTime = state.heroTime + dt
    -- 只归一累计显示时间，避免整数经验边界被不同帧率的浮点尾差提前/延后。
    local ticks = math.floor(state.heroTime * HERO_ANIM_TICKS_PER_SEC + 0.5)
    local delayTicks = math.floor(HERO_ANIM_DELAY * HERO_ANIM_TICKS_PER_SEC)
    local staggerTicks = math.floor(HERO_ANIM_STAGGER * HERO_ANIM_TICKS_PER_SEC)
    if ticks < delayTicks then return end

    for i, a in ipairs(state.heroAnim) do
        local progress = math.max(0, math.min(HERO_ANIM_DURATION_TICKS,
            ticks - delayTicks - (i - 1) * staggerTicks))
        local item = state.heroExpPreview[i]
        local total = math.max(0, math.floor((item and item.expGain) or 0))
        if total > 0 and a.remain > 0 then
            -- 先转浮点乘法，避免大额经验乘 tick 发生 Lua integer 溢出。
            local target = math.floor(total * 1.0 * progress / HERO_ANIM_DURATION_TICKS)
            local want = math.max(0, math.min(a.remain, target - a.issued))
            if want > 0 then
                local nextValue = ExpTable.simulateHeroExp(a.level, a.exp, want)
                a.level, a.exp, a.capped = nextValue.level, nextValue.exp, nextValue.capped
                a.issued = a.issued + want
                a.remain = nextValue.capped and 0 or a.remain - want
            end
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
    -- 背景由 DarkIcon.drawNine 矢量绘制
    img.progBg        = nvgCreateImage(vg, "image/进度条/UI_LXSYJDT_2.png", 0)
    img.progFill      = nvgCreateImage(vg, "image/进度条/UI_XDZJDT.png", 0)
    img.btnGreen      = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)

    print("[OfflineRewardPanel] init OK")
end

--- 展示离线收益弹窗
---@param data table 离线收益数据
function Panel.show(data)
    state.offlineSeconds = data.offlineSeconds or 0
    state.maxSeconds     = data.maxSeconds or 86400
    state.tailRatio      = data.tailRatio or 0.5
    state.hardCapSeconds = data.hardCapSeconds or 86400 * 7
    state.cappedByHardCap = data.cappedByHardCap or false
    state.multiplier     = data.multiplier or 1.0
    state.adventureExp   = data.adventureExp or 0
    state.adventurerExp  = data.adventurerExp or 0
    state.heroExpPreview = data.heroExpPreview or {}
    state.teamSources    = data.teamSources or {}
    -- 只读玩家副本，领取口径为经验取整后沿正式曲线连续升级。
    -- 数字在 show 时冻结；绘制和切语言不重复预估，也不写回玩家模块。
    state.playerStartLevel, state.playerEndLevel = nil, nil
    local player = ClientDispatcher.get("player")
    if player then
        local beforeLevel = player.level or 1
        local preview = { level = beforeLevel, exp = (player.exp or 0) + math.floor(state.adventureExp) }
        ExpTable.autoLevelUpPlayer(preview)
        state.playerStartLevel, state.playerEndLevel = beforeLevel, preview.level
    end
    state.onClaim        = data.onClaim
    state.detailItem     = nil
    state.detailIdx      = 0

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
    state.followScroll   = true
    state.open           = true
    state.animPhase = "opening"
    state.animStart = time.elapsedTime
    resetHeroAnim()
    local tailCount = math.max(1, #state.rewards - CASCADE_FASTER_AFTER)
    local fasterInterval = math.min(CASCADE_INTERVAL_FASTER, CASCADE_TAIL_BUDGET / tailCount)
    state.cascade = RewardCascade.new(#state.rewards, {
        interval       = CASCADE_INTERVAL,
        intervalTail   = CASCADE_INTERVAL_TAIL,
        fastAfter      = CASCADE_FAST_AFTER,
        intervalFaster = fasterInterval,
        fasterAfter    = CASCADE_FASTER_AFTER,
        popDur         = CASCADE_POP_DUR,
        lead           = HERO_ANIM_DELAY,
    })
    state.cascadeSfx = 0
    if #state.rewards > 0 then
        state.cascade:start(time.elapsedTime)
    end
    print("[OfflineRewardPanel] show: offline=" .. state.offlineSeconds .. "s, rewards=" .. #state.rewards
        .. ", heroPreview=" .. #state.heroExpPreview
        .. string.format(", tailGap=%.4fs, reveal=%.2fs", fasterInterval,
            HERO_ANIM_DELAY + state.cascade:startAt(#state.rewards) + CASCADE_POP_DUR))
end

--- 关闭
function Panel.close()
    if state.animPhase == "closing" then return end
    state.detailItem = nil
    state.detailIdx = 0
    state.animPhase = "closing"
    state.animStart = time.elapsedTime
end

--- 是否打开
---@return boolean
function Panel.isOpen()
    return state.open
end

--- 阵容刷新后覆盖队员经验预览，奖励内容不变。
---@param preview table[]|nil
function Panel.refreshHeroPreview(preview)
    if not state.open or type(preview) ~= "table" or #preview == 0 then return end
    state.heroExpPreview = preview
    resetHeroAnim()
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

    -- 奖励逐件弹出与队员升级同时开始（show 里已 start）
    if state.cascade then
        if state.cascade.revealStart ~= 0 then
            -- 同帧弹出的奖励共用一次入场音，避免尾段加速或掉帧后音效集中重播。
            local due = state.cascade:shownCount()
            if state.cascadeSfx < due then
                state.cascadeSfx = due
                local item = state.rewards[due]
                if item and item.type == "equip" then
                    GameSFX.play("install")
                else
                    GameSFX.play("ui_click_3")
                end
            end
            -- 内容超出可视区时自动滚到最新一行（底部）
            syncCascadeScroll()
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

    -- 空队不占高度：奖励区和领取按钮整体上移，面板高度跟着收
    local saved, panelH, panelCY, rewardCY, claimCY = layoutNow()

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
    local pivotX, pivotY = BG.CX, panelCY
    nvgSave(vg)
    nvgTranslate(vg, pivotX, pivotY)
    nvgScale(vg, animScale, animScale)
    nvgTranslate(vg, -pivotX, -pivotY)
    nvgGlobalAlpha(vg, animAlpha)

    -- 2. 弹窗背景框（九宫格）
    DarkIcon.drawNine(vg, "panel", BG.CX - BG.W * 0.5, PANEL_TOP, BG.W, panelH, { titleH = BG.IT })

    -- 3. 标题 "欢迎回来"
    DrawUtil.drawTextStroke(vg, TTL.X, TTL.Y, "欢迎回来",
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        TTL.FR, TTL.FG, TTL.FB, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- 远征等级经验与本次领取前后的等级（时间条上方）
    local playerLevels = nil ---@type string|nil
    if state.playerStartLevel and state.playerEndLevel then
        playerLevels = "Lv." .. tostring(state.playerStartLevel) .. " → Lv." .. tostring(state.playerEndLevel)
    end
    self_drawExpRow(vg, EXP_ROW1, state.adventureExp, playerLevels)

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

    -- 10. 提示：24 小时内满额，超出部分减半，7 日硬顶
    do
        local fullHours = formatMaxHours(state.maxSeconds)
        local tailPct = math.floor((state.tailRatio or 0.5) * 100 + 0.5)
        local capDays = math.floor((state.hardCapSeconds or 604800) / 86400)
        local parts
        if state.cappedByHardCap then
            parts = {
                { "离线超过", false },
                { capDays .. "日", true },
                { "，已按上限结算", false },
            }
        elseif state.offlineSeconds > state.maxSeconds then
            parts = {
                { "离线超过", false },
                { fullHours .. "小时", true },
                { "，超出部分按" .. tailPct .. "%计算，" .. capDays .. "日封顶", false },
            }
        else
            parts = {
                { fullHours .. "小时", true },
                { "内全额，超出按" .. tailPct .. "%，" .. capDays .. "日封顶", false },
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

    -- 每个远征队员的实际升级情况（逐级动画）
    self_drawHeroExpList(vg)

    -- 16. 奖励内容背景框
    DrawUtil.drawRoundedRectCentered(vg,
        REWARD_AREA.CX, rewardCY, REWARD_AREA.W, REWARD_AREA.H, REWARD_AREA.R,
        0, 0, 0, 13)

    -- 17. 奖励物品网格（可滚动裁剪区域，跟随奖励框上移）
    self_drawRewardGrid(vg, saved)

    -- 领取按钮（居中）
    local _bf2 = BF.begin(vg, "orp_claim", BG.CX, claimCY, BTN_CLAIM.W, BTN_CLAIM.H)
    DarkIcon.drawNine(vg, "btn", BG.CX - BTN_CLAIM.W * 0.5, claimCY - BTN_CLAIM.H * 0.5, BTN_CLAIM.W, BTN_CLAIM.H, { accent = "gold" })

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BTN_CLAIM.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(BTN_CLAIM.TR, BTN_CLAIM.TG, BTN_CLAIM.TB, BTN_CLAIM.TA))
    nvgText(vg, BG.CX, claimCY, "领取", nil)
    BF.finish(vg, _bf2)

    -- [奖励可点击] 详情浮层（盖在弹窗内容最上层）
    drawDetailOverlay(vg)

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

--- 经验标签、前后等级、奖励值共用实测宽度预算，完整保留五语文字。
function self_drawExpRow(vg, cfg, value, levels)
    DrawUtil.drawRoundedRectCentered(vg,
        cfg.CX, cfg.CY, cfg.W, cfg.H, cfg.R,
        0, 0, 0, 13)
    local label = I18n.lookup(cfg.LABEL)
    local valText = "+" .. NumberUtil.format(value)
    local font = cfg.FONT or 40
    local levelFont = 32
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, font)
    local labelW = I18n.displayBounds(vg, 0, 0, label)
    local valueW = I18n.displayBounds(vg, 0, 0, valText)
    nvgFontSize(vg, levelFont)
    local levelW = levels and I18n.displayBounds(vg, 0, 0, levels) or 0
    local gapW = levels and 48 or 24
    local scale = math.min(1, (cfg.VALUE_X - cfg.LABEL_X - gapW) / (labelW + valueW + levelW))
    nvgFontSize(vg, font * scale)
    labelW = I18n.displayBounds(vg, 0, 0, label)
    valueW = I18n.displayBounds(vg, 0, 0, valText)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(cfg.LABEL_R, cfg.LABEL_G, cfg.LABEL_B, 255))
    I18n.displayText(vg, cfg.LABEL_X, cfg.CY, label, nil)
    if levels then
        nvgFontSize(vg, levelFont * scale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
        local left, right = cfg.LABEL_X + labelW + 24, cfg.VALUE_X - valueW - 24
        I18n.displayText(vg, (left + right) * 0.5, cfg.CY, levels, nil)
    end
    DrawUtil.drawTextStroke(vg, cfg.VALUE_X, cfg.CY, valText,
        font * scale, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        cfg.VALUE_R, cfg.VALUE_G, cfg.VALUE_B, cfg.VALUE_SW)
end

--- 完整来源在对应队经验区显示，按译文测量缩字而不截掉关卡名。
local function drawTeamSource(vg, source, teamIdx, cy, textTop, textBottom)
    local entry = require("config.StageConfig").getStage(source.stageId)
    local name = source.sourceName or (entry and entry.name) or tostring(source.stageId)
    local translatedName = I18n.lookup(name)
    if source.sourceKind == "tower" then
        translatedName = I18n.format("通天塔 第%d层", (source.stageId or 400001) - 400000)
    end
    local label = source.paused and I18n.format("小队%d · %s · 暂停离线收益", teamIdx, translatedName)
        or I18n.format("小队%d · %s", teamIdx, translatedName)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 22)
    local width = I18n.displayBounds(vg, 0, 0, label)
    local font = width > ROW_W - 48 and 22 * (ROW_W - 48) / width or 22
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 字体字墨上下缘不一定对称；保留位置，按实际测量缩号，留出行底空隙。
    -- 有界迭代：测量边界若不随字号收敛也不能死循环，最多缩到明显小于原字号即止。
    for _ = 1, 24 do
        nvgFontSize(vg, font)
        local bounds = {}
        I18n.displayBounds(vg, CENTER_X, cy, label, nil, bounds)
        local above = cy - (bounds[2] or cy)
        local below = (bounds[4] or cy) - cy
        local fit = math.min(1, above > 0 and (cy - textTop) / above or 1,
            below > 0 and (textBottom - cy) / below or 1)
        if fit >= 1 then break end
        local nextFont = font * math.min(0.95, fit)
        if not (nextFont > 0) or nextFont >= font then break end
        font = nextFont
    end
    nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
    I18n.displayText(vg, CENTER_X, cy, label, nil)
end

--- 绘制队员升级列表：一行一个队伍，队伍内头像横向均分
function self_drawHeroExpList(vg)
    local preview = state.heroExpPreview
    local groups = groupHeroPreview(preview)
    local viewH = heroBlockHeight(groups)
    if viewH <= 0 then return end
    local animDone = heroAnimDone()
    local cellW = (ROW_W - HERO_ROW.PAD_X * 2) / HERO_ROW.SLOTS

    nvgSave(vg)
    nvgScissor(vg, ROW_L, HERO_ROW.TOP, ROW_W, math.max(viewH, 1))

    local top = HERO_ROW.TOP
    for t = 1, HERO_ROW.VISIBLE do
        local members = groups[t]
        local source = sourceForTeam(t)
        local rowH = heroRowHeight(members, source)
        if rowH > 0 then
            local cy = top + rowH * 0.5

            -- 行底 + 队伍名；来源专用行直接显示完整说明。
            DrawUtil.drawRoundedRectCentered(vg, CENTER_X, cy, ROW_W, rowH, 12,
                0, 0, 0, HERO_ROW.BG_A)
            if #members > 0 then
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 20)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(0xff, 0xd6, 0x66, 255))
                I18n.displayText(vg, ROW_L + 14, top + 16, I18n.format("小队%d", t), nil)
            end

            for s = 1, #members do
                local item = members[s]
                local i = 0
                for k, p in ipairs(preview) do
                    if p == item then i = k break end
                end
                local a = state.heroAnim[i]
                local curLevel = (a and a.level) or item.level or 1
                local curExp   = (a and a.exp) or 0
                local maxExp   = ExpTable.getHeroExpForLevel(curLevel) or 0
                if a and a.capped then maxExp = 0 end

                -- 按本队实际人数居中，避免人少时头像被拉到两边
                local cellCX = CENTER_X + (s - (#members + 1) * 0.5) * cellW
                local iconCY = top + 16 + HERO_ROW.ICON * 0.5
                local iconCX = cellCX

                -- [统一角色框] 头像（品质色描边，替代 ZBBJ 贴图底）
                local q = (item.quality and item.quality > 0) and item.quality or 2
                ---@type number
                local hid = item.heroId
                local heroImg = getHeroIcon(hid)
                HeroFrame.draw(vg, {
                    cx = iconCX, cy = iconCY, size = HERO_ROW.ICON - 10,
                    heroId = hid,
                    iconHandle = heroImg,
                    quality = q,
                    state = "owned",
                })

                -- 经验条与实际头像框等宽，收紧垂直间距给关卡说明留空。
                local barW  = HERO_ROW.ICON - 10
                local barCY = iconCY + barW * 0.5 + 12
                local barX  = cellCX - barW * 0.5
                nvgBeginPath(vg)
                nvgRoundedRect(vg, barX, barCY - HERO_ROW.BAR_H * 0.5, barW, HERO_ROW.BAR_H,
                    HERO_ROW.BAR_H * 0.5)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
                nvgFill(vg)

                local ratio = 0
                if maxExp > 0 then
                    ratio = math.max(0, math.min(1, curExp / maxExp))
                elseif a and a.capped then
                    ratio = 1
                end
                if ratio > 0 then
                    local fillW = math.max(HERO_ROW.BAR_H, barW * ratio)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, barX, barCY - HERO_ROW.BAR_H * 0.5, fillW, HERO_ROW.BAR_H,
                        HERO_ROW.BAR_H * 0.5)
                    if animDone then
                        nvgFillColor(vg, nvgRGBA(0x63, 0xff, 0x84, 255))
                    else
                        nvgFillColor(vg, nvgRGBA(0xff, 0xc8, 0x4a, 255))
                    end
                    nvgFill(vg)
                end

                -- 等级（经验条下方居中；升过级显示「Lv.14→15」并转金色）
                local startLevel = item.startLevel or curLevel
                local lvText
                if curLevel > startLevel then
                    lvText = "Lv." .. tostring(startLevel) .. "→" .. tostring(curLevel)
                else
                    lvText = "Lv." .. tostring(curLevel)
                end
                local lvR, lvG, lvB = 0xd8, 0xc9, 0xa3
                if curLevel > startLevel then
                    lvR, lvG, lvB = 0xff, 0xd7, 0x6b
                end
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, HERO_ROW.LV_FONT)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(lvR, lvG, lvB, 255))
                nvgText(vg, cellCX, barCY + 22, lvText, nil)
            end
            if source then
                drawTeamSource(vg, source, t, #members > 0 and top + 206 or cy,
                    #members > 0 and top + 193 or top + 2, top + rowH - 2)
            end
            top = top + rowH + HERO_ROW.GAP
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)
end

--- 绘制奖励物品网格（逐件弹出，与关卡奖励同款动画）
---@param shiftY number 整体上移量（空队省下的高度）
function self_drawRewardGrid(vg, shiftY)
    local items = state.rewards
    if #items == 0 then return end

    local totalRows = math.ceil(#items / COLS)
    local cascade = state.cascade
    local clipTop = CLIP.TOP - shiftY

    nvgSave(vg)
    nvgScissor(vg, CLIP.LEFT, clipTop, CLIP.W, CLIP.H)

    for row = 1, totalRows do
        for col = 1, COLS do
            local idx = (row - 1) * COLS + col
            local item = items[idx]
            if not item then goto continue end

            local cx, rawCY = getCellCenter(row, col)
            local cy = rawCY - shiftY - state.scrollY

            -- 跳过不可见
            if cy + ICON_SIZE * 0.5 < clipTop - 10 then goto continue end
            if cy - ICON_SIZE * 0.5 > clipTop + CLIP.H + 10 then goto continue end

            -- 逐件弹出：未到出场时刻只画预告框，弹出中叠加爆发+变换
            -- revealStart 为 0 表示还没开始。此时 cascade:t 会按「从游戏启动算起」
            -- 得出已落地，奖励会在动画前整排显示，必须整件跳过。
            local popping = false
            local popT = 1
            if cascade then
                if cascade.revealStart == 0 then goto continue end
                popT = cascade:t(idx)
            end
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
                    local cntText = "x" .. NumberUtil.format(item.count)
                    local bx2 = cx + ICON_SIZE * 0.5 - 8
                    local by2 = cy - ICON_SIZE * 0.5 + 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, fitBadgeFont(vg, cntText))
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
                    nvgFontSize(vg, fitBadgeFont(vg, amtText))
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

    -- 滚动条：内容超出可视区时右侧显示细条，提示可滚动
    if state.scrollMax > 8 then
        local trackTop = clipTop + 8
        local trackH = CLIP.H - 16
        local thumbH = math.max(36, trackH * (CLIP.H / (CLIP.H + state.scrollMax)))
        local travel = math.max(1, trackH - thumbH)
        local thumbY = trackTop + (state.scrollY / state.scrollMax) * travel
        nvgBeginPath(vg)
        nvgRoundedRect(vg, CLIP.RIGHT - 8, thumbY, 6, thumbH, 3)
        nvgFillColor(vg, nvgRGBA(0xf7, 0xfe, 0x77, 170))
        nvgFill(vg)
    end
end

-- ======================== 输入处理 ========================

function Panel.claim()
    if not state.open then return false end
    print("[OfflineRewardPanel] 领取 clicked")
    if state.onClaim and state.onClaim() == false then
        return true  -- 领取失败时保留弹窗，不能让未领奖励卡在不可再次点击的状态。
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

    -- [奖励可点击] 详情打开时：任意点击先关闭详情（不触发领取/其他交互）
    if state.detailItem then
        state.detailItem = nil
        state.detailIdx = 0
        GameSFX.play("ui_click_3")
        return true
    end

    local _, panelH, panelCY, _, claimCY = layoutNow()

    -- [奖励可点击] 奖励图标命中 → 打开详情浮层
    local hitIdx = hitRewardCell(dx, dy)
    if hitIdx then
        local item = state.rewards[hitIdx]
        -- 装备必须带完整实例才能开只读详情；资源都可查看
        if item and (item.type ~= "equip" or item.equip) then
            state.detailItem = item
            state.detailIdx = hitIdx
            GameSFX.play("ui_click_3")
            return true
        end
    end

    -- 领取按钮（居中，随空队上移）
    if DrawUtil.hitTest(dx, dy, BG.CX, claimCY, BTN_CLAIM.W, BTN_CLAIM.H) then
        BF.trigger("orp_claim")
        return Panel.claim()
    end

    -- 弹窗内部消费事件（阻止穿透）
    if DrawUtil.hitTest(dx, dy, BG.CX, panelCY, BG.W, panelH) then
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
    -- 奖励区域内开始拖拽（区域随空队上移）
    local saved = layoutNow()
    if dx >= CLIP.LEFT and dx <= CLIP.RIGHT
       and dy >= CLIP.TOP - saved and dy <= CLIP.BOTTOM - saved then
        state.dragging  = true
        state.dragLastY = dy
        state.scrollVel = 0
        state.followScroll = false  -- 手动拖拽后不再自动跟随
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
    state.followScroll = false  -- 手动滚轮后不再自动跟随
    clampScroll()
    state.scrollVel = 0
end

return Panel
