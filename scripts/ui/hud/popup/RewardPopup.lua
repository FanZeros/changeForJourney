-- ============================================================================
-- RewardPopup - 通用奖励弹窗模块
-- 首通奖励逐个获得：前 8 个间隔 0.12s，超过 8 个后间隔 0.1s
-- ============================================================================
--
-- 【使用说明】
-- 本模块用于项目中所有奖励弹出展示（首通奖励、宝箱奖励、成就奖励等）。
-- 未来新增奖励类型时，只需调用 RewardPopup.show() 即可：
--
--   local RewardPopup = require("ui.hud.popup.RewardPopup")
--
--   -- 在 init 阶段（仅一次）：
--   RewardPopup.init(vg)
--
--   -- 展示奖励：
--   RewardPopup.show("首通奖励", {
--       { type = "gold",    amount = 100 },                -- 金币（品质2框）
--       { type = "diamond", amount = 10 },                 -- 钻石（品质5框）
--       { type = "equip",   templateId = "W3", quality = 3, level = 5 },  -- 装备
--   })
--
--   -- 在渲染回调中：
--   RewardPopup.draw(vg)
--
--   -- 在输入处理中（点击空白处关闭）：
--   if RewardPopup.handleInput(dx, dy) then return end
--
--   -- 在 update 中（滚动惯性）：
--   RewardPopup.update(dt)
--
-- 【奖励 item 格式】
--   资源类:  { type = "gold"|"diamond", amount = number }
--   装备类:  { type = "equip", templateId = string, quality = number, level = number }
--
-- 【排序规则】
--   资源类（金币/钻石）排在前面，装备类排在后面
--
-- 【未来扩展】
--   如需添加新资源类型（如经验药水、材料等），只需：
--   1. 在 RESOURCE_DEFS 表中新增条目（指定图标路径和品质框等级）
--   2. 在 show() 中传入对应 type 即可
-- ============================================================================

local EquipmentConfig = require("config.EquipmentConfig")
local DarkIcon        = require("core.DarkIcon")  -- 图标压暗绘制
local HeroConfig      = require("config.HeroConfig")
local NumberUtil      = require("core.NumberUtil")
local DrawUtil        = require("core.DrawUtil")
local ImageCache        = require("ui.widget.ImageCache")
local ArtifactAssetUtil = require("config.ArtifactAssetUtil")
local ResourceDefs      = require("config.ResourceDefs")
local GameSFX           = require("systems.GameSFX")
local RewardCascade     = require("ui.widget.RewardCascade")
local BattleRewardQueue = require("ui.widget.BattleRewardQueue")
local HeroFrame = require("ui.widget.HeroFrame")
local ResultRepeatFooter = require("ui.widget.ResultRepeatFooter")

local RewardPopup = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- ======================== 布局常量 ========================

-- 去掉全屏/行内黑色叠加层：弹窗直接浮在暗黑场景上，靠光晕与面板自带对比

-- 奖励弹窗整体上移，避免在横屏中栏里显得偏下
local POPUP_LIFT = 220

-- 奖励弹窗锚点（原光晕中心，旋转底图已去掉）
local GLOW_CX, GLOW_CY = 540, 1044 - POPUP_LIFT
local GLOW_H = 908

-- 背景面板: UI_GXHD_1.png
local PANEL_CX, PANEL_CY = 540, 1194 - POPUP_LIFT
local PANEL_W,  PANEL_H  = 1080, 685

-- 奖励类型文本
local TITLE_CX, TITLE_CY = 540, 996 - POPUP_LIFT
local TITLE_FONT = 40

-- 奖励图标区域：只露两行，超出部分上滚，不能画出面板
local ICON_SIZE = 160
local ROW_GAP   = 20
local COL_GAP   = 34
local COLS      = 5
local VISIBLE_ROWS = 2
local GRID_CX = 540
local GRID_H = VISIBLE_ROWS * ICON_SIZE + (VISIBLE_ROWS - 1) * ROW_GAP
local GRID_CY = 1228 - POPUP_LIFT
local GRID_W = 938

-- 裁剪区域（基于图标区域）
local CLIP_LEFT   = GRID_CX - GRID_W * 0.5
local CLIP_TOP    = GRID_CY - GRID_H * 0.5
local CLIP_RIGHT  = GRID_CX + GRID_W * 0.5
local CLIP_BOTTOM = GRID_CY + GRID_H * 0.5

-- 列 X 坐标（5列居中排布）
local TOTAL_ROW_W = COLS * ICON_SIZE + (COLS - 1) * COL_GAP  -- 5*160 + 4*34 = 936
local FIRST_COL_LEFT = GRID_CX - TOTAL_ROW_W * 0.5
local COL_CX = {}
for c = 1, COLS do
    COL_CX[c] = FIRST_COL_LEFT + (c - 1) * (ICON_SIZE + COL_GAP) + ICON_SIZE * 0.5
end

-- 第一行顶部 Y
local FIRST_ROW_TOP = CLIP_TOP

-- 底部提示上收至面板内，位于两行网格下方，避免横屏战斗框裁掉文字。
local HINT_CX = 540
local HINT_FONT = 40
local HINT_CY = PANEL_CY + PANEL_H * 0.5 - HINT_FONT - 24
local HINT_TEXT = "点击空白处关闭"

-- 数量/等级角标（统一右下角角标样式）
local BADGE_FONT   = 40
local BADGE_STROKE = 4

-- 角标字号自适应：按实际文本宽度测量，太长（大数值/长名字）时等比缩小，避免溢出图标
local BADGE_FONT_MIN = 24
local function fitBadgeFont(vg, text)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BADGE_FONT)
    local w = nvgTextBounds(vg, 0, 0, text)
    local maxW = ICON_SIZE - 20
    if w <= maxW then return BADGE_FONT end
    return math.max(BADGE_FONT_MIN, BADGE_FONT * maxW / w)
end

-- ======================== 资源定义表（统一引用中央注册表） ========================
local RESOURCE_DEFS = ResourceDefs.DEFS

-- ======================== 状态 ========================

local state = {
    open     = false,
    rowTag   = nil,    -- [三行并行] 归属战斗行（1..3）; nil=全局弹窗（外侧显示）
    title    = "",
    subtitle = "",
    items    = {},     -- 排序后的奖励列表
    scrollY  = 0,
    scrollMax = 0,
    dragging  = false,
    dragLastY = 0,
    scrollVel = 0,
    followScroll = true,
    autoScroll = nil,  -- { t, dur, to } 非逐件弹出时开屏平滑滚到底部（显示最新/最下方奖励）
    panel = nil,       -- 触发面板 'left'|'center'|'right'（横屏三面板跟随绘制/输入）；nil=全屏居中
    layoutScale = 1.0, -- 布局自适应缩放：少量物品时整体等比缩小，避免 1 件物品撑满大面板
    gridRowOffset = 0, -- 显示行数不足两行时网格整体下移量（垂直居中）
    -- 动画状态
    animPhase  = "none",  -- "none"|"opening"|"open"|"closing"
    animStart  = 0,       -- 动画开始时刻（time.elapsedTime）
    -- 首通逐个获得（时间轴见模块级 cascade）
    cascade     = false,
    sfxPlayed   = 0,
    -- 物品点击回调
    onItemClick = nil,    -- function(item, index) 点击某个物品时触发
    repeatDraw = nil,     ---@type table|nil { getCost(count), onContinue(count) } 主动开箱结果
    repeatAfterClose = nil, ---@type fun()|nil 仅明确点击继续后执行一次
    battleHoldStart = nil, -- 逐件动画结束后，开始累计无遮挡的战斗展示停留时间
}

local BATTLE_HOLD_DURATION = 3.0 -- 仅自动战斗奖励自动收起，主动领取仍手动关闭

-- 滚动参数
local SCROLL_FRICTION  = 0.90
local SCROLL_MIN_VEL   = 0.5

-- 动画参数
local ANIM_OPEN_DURATION  = 0.35   -- 打开动画时长（秒）
local ANIM_CLOSE_DURATION = 0.25   -- 关闭动画时长
local CLOSE_GUARD_DURATION = 0.15  -- 关闭后事件吞噬保护期（防止点击穿透到下层界面）

-- 首通奖励逐件弹出：时间轴与动画原语统一走 ui.widget.RewardCascade
local CASCADE_LEAD          = RewardCascade.LEAD
local CASCADE_INTERVAL      = RewardCascade.INTERVAL
local CASCADE_INTERVAL_TAIL = RewardCascade.INTERVAL_TAIL
local CASCADE_FAST_AFTER    = RewardCascade.FAST_AFTER
local CASCADE_POP_DUR       = RewardCascade.POP_DUR

-- 本弹窗的时间轴（件数在 show() 里定）
---@class RewardCascadeTimeline : table  逐件弹出时间轴（定义见 ui/widget/RewardCascade.lua）
---@type RewardCascadeTimeline|nil
local cascade = nil

--- 第 idx 件与上一件的间隔。idx 从 1 开始，第 1 件没有间隔。
local function cascadeGap(idx)
    if not cascade then return 0 end
    return cascade:gap(idx)
end

--- 第 idx 件的出场时刻（第 1 件为 0）
local function cascadeStartAt(idx)
    if not cascade then return 0 end
    return cascade:startAt(idx)
end

--- 当前已经开始出场的件数
local function cascadeShownCount(elapsed)
    if not cascade then return 0 end
    return cascade:shownCount(elapsed)
end

-- 关闭保护时间戳（关闭完成时记录，保护期内 isOpen() 仍返回 true 以吞噬事件）
local closedAt_ = 0

---@type fun(): boolean
local battleBlocked_ = function() return false end
local pendingBattle_ = BattleRewardQueue.new(RESOURCE_DEFS)
---@type number|nil
local battlePausedAt_ = nil
local battleResumedAt_ = 0
local blockerError_ = false

local function battleBlocked()
    local ok, blocked = pcall(battleBlocked_)
    if not ok then
        if not blockerError_ then print("[RewardPopup] 遮挡查询失败: " .. tostring(blocked)) end
        blockerError_ = true
        return true
    end
    blockerError_ = false
    return blocked == true
end

local function syncBattleVisibility()
    if not state.open or not state.rowTag then return true end
    local now = time.elapsedTime
    if battleBlocked() then
        if not battlePausedAt_ then
            battlePausedAt_ = now
            state.dragging = false
            state.dragMoved = 0
            state.scrollVel = 0
            print("[RewardPopup] 中栏覆盖，暂停战斗奖励")
        end
        return false
    end
    if battlePausedAt_ then
        local paused = math.max(0, now - battlePausedAt_)
        state.animStart = state.animStart + paused
        if cascade then cascade.revealStart = cascade.revealStart + paused end
        if state.battleHoldStart then state.battleHoldStart = state.battleHoldStart + paused end
        battlePausedAt_ = nil
        battleResumedAt_ = now
        print("[RewardPopup] 中栏关闭，恢复战斗奖励")
    end
    return true
end

local function copyRewardData(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for k, v in pairs(value) do result[k] = copyRewardData(v, seen) end
    return result
end

function RewardPopup.setBattleBlocked(predicate)
    battleBlocked_ = predicate or function() return false end
end

function RewardPopup.hasPendingBattleRewards()
    return pendingBattle_:hasPending() or (state.open and state.rowTag ~= nil)
end

-- 会话重置只清战斗展示，不重发奖励，也不触发旧的关闭回调。
function RewardPopup.clearBattleRewards()
    pendingBattle_:clear()
    battlePausedAt_ = nil
    battleResumedAt_ = 0
    if state.rowTag then
        state.open, state.rowTag, state.animPhase = false, nil, "none"
        state.items, state.onClose, state.onItemClick = {}, nil, nil
        state.dragging, state.scrollVel = false, 0
        cascade = nil
        closedAt_ = 0
    end
end

local easeOutBack = RewardCascade.easeOutBack

--- ease-in cubic 缓动（加速离开）
local function easeInCubic(t)
    return t * t * t
end

local function wantsCascade(title, opts)
    if opts and opts.cascade == false then return false end
    if opts and opts.cascade == true then return true end
    return type(title) == "string" and string.find(title, "首通", 1, true) ~= nil
end

local function cascadeElapsed()
    if not cascade then return 0 end
    return cascade:elapsed()
end

local function cascadeFinished()
    if not state.cascade then return true end
    if not cascade then return true end
    return cascade:finished()
end

--- nil = 尚未出场；0..1 = 弹出中；>1 = 已落地
local function cascadeT(idx)
    if not state.cascade or not cascade then return 1 end
    return cascade:t(idx)
end

local function itemAccent(item)
    local q = 2
    if item.type == "equip" or item.type == "hero"
        or item.type == "artifact" or item.type == "seed" then
        q = item.quality or 1
    elseif item.type == "shard" and item.heroId then
        local heroDef = HeroConfig.get(tonumber(item.heroId))
        q = (heroDef and heroDef.quality) or 3
    else
        local def = RESOURCE_DEFS[item.type]
        q = (def and def.quality) or 2
    end
    local trim = DarkIcon.QUALITY_TRIM[q] or DarkIcon.QUALITY_TRIM[5]
    return trim[1], trim[2], trim[3]
end

local function playObtainSfx(item)
    if item and (item.type == "equip" or item.type == "artifact") then
        GameSFX.play("install")
    elseif item and item.type == "hero" then
        GameSFX.play("level_up")
    else
        GameSFX.play("ui_click_3")
    end
end

local function skipCascade()
    if not state.cascade or cascadeFinished() then return false end
    if cascade then cascade:skipToEnd() end
    state.sfxPlayed = #state.items
    state.followScroll = true
    state.scrollY = state.scrollMax
    if state.scrollY < 0 then state.scrollY = 0 end
    print("[RewardPopup] cascade skipped, items=" .. tostring(#state.items)
        .. " scroll=" .. tostring(state.scrollY))
    GameSFX.play("level_up")
    return true
end

--- 单件获得：光柱、冲击环、射线、火花（绘制在图标下层）
local function drawCascadeBurst(vg, cx, cy, t, r, g, b)
    RewardCascade.burst(vg, cx, cy, t, ICON_SIZE, r, g, b)
end


--- 图标上层扫光
local function drawCascadeGlint(vg, cx, cy, t)
    RewardCascade.glint(vg, cx, cy, t, ICON_SIZE)
end

local function drawCascadeAnticipate(vg, cx, cy, idx)
    RewardCascade.anticipate(vg, cx, cy, cascadeElapsed() - cascadeStartAt(idx), ICON_SIZE)
end

-- ======================== 图片资源 ========================

local imgPanel = -1   -- 背景面板

-- 资源图标缓存: [type] = nvgImage handle
local resourceIconCache = {}

-- 角色头像图标缓存: [heroId] = nvgImage handle
local heroIconCache = {}

-- 装备图标/品质背景缓存由 ImageCache 共享模块提供（LRU 淘汰，防止 VRAM 累积）

local cachedVg = nil

-- ======================== 工具函数 ========================

local drawImageCentered = DrawUtil.drawImageCentered

local function clampScroll()
    state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY))
end

--- 获取资源图标（懒加载）
local function getResourceIcon(resType)
    local cached = resourceIconCache[resType]
    if cached then return cached end
    if not cachedVg then return -1 end
    local def = RESOURCE_DEFS[resType]
    if not def then return -1 end
    local img = nvgCreateImage(cachedVg, def.iconPath, 0)
    resourceIconCache[resType] = img
    return img
end

--- 获取角色头像图标（懒加载）
local function getHeroIcon(heroId)
    local cached = heroIconCache[heroId]
    if cached then return cached end
    if not cachedVg then return -1 end
    local path = "image/角色图标/UI_icon_hero_" .. heroId .. ".png"
    local img = nvgCreateImage(cachedVg, path, 0)
    heroIconCache[heroId] = img
    return img
end

-- 装备图标/品质框复用共享缓存。
local getEquipIcon = ImageCache.getEquipIcon
local getQualityBg = ImageCache.getQualityBg

--- 获取格子中心坐标（含不足两行时的垂直居中偏移）
local function getCellCenter(row, col)
    local cx = COL_CX[col]
    local cy = FIRST_ROW_TOP + ICON_SIZE * 0.5 + (row - 1) * (ICON_SIZE + ROW_GAP)
        + (state.gridRowOffset or 0)
    return cx, cy
end

-- ======================== 布局自适应 ========================
-- 物品少时整套布局（面板/标题/网格/提示）等比缩小并垂直居中，
-- 避免 1~2 件物品占据两行大面板显得空荡。绘制层包一层缩放变换，
-- 输入层用逆变换算回设计坐标，滚动/级联逻辑全部无需改动。

local LAYOUT_ANCHOR_Y = PANEL_CY  -- 布局缩放锚点（面板中心）
local LAYOUT_MIN = 0.66

--- 按当前物品数重算布局缩放与网格垂直偏移（show/removeItem 后调用）
local function recomputeLayoutScale()
    local visibleRows = math.min(2, math.max(1, math.ceil(math.max(#state.items, 1) / COLS)))
    local fullH = 2 * ICON_SIZE + ROW_GAP
    local visH = visibleRows * ICON_SIZE + (visibleRows - 1) * ROW_GAP
    -- 面板高度按可见行数比例收缩后再留一点余量，整体再缩一档让少量物品更精致
    local scale = (visH + 260) / (fullH + 260)
    scale = math.max(LAYOUT_MIN, math.min(1.0, scale))
    if visibleRows >= 2 then scale = 1.0 end
    state.layoutScale = scale
    state.gridRowOffset = (GRID_H - visH) * 0.5
end

--- 绘制层：以面板中心为锚点应用布局缩放（调用方需配对一个 nvgRestore）
local function applyLayoutTransform(vg)
    local s = state.layoutScale or 1.0
    if s == 1.0 then return end
    nvgSave(vg)
    nvgTranslate(vg, DESIGN_W * 0.5, LAYOUT_ANCHOR_Y)
    nvgScale(vg, s, s)
    nvgTranslate(vg, -DESIGN_W * 0.5, -LAYOUT_ANCHOR_Y)
end

--- 输入层：屏幕设计坐标 → 布局坐标系
local function invLayoutX(x)
    local s = state.layoutScale or 1.0
    if s == 1.0 then return x end
    return (x - DESIGN_W * 0.5) / s + DESIGN_W * 0.5
end
local function invLayoutY(y)
    local s = state.layoutScale or 1.0
    if s == 1.0 then return y end
    return (y - LAYOUT_ANCHOR_Y) / s + LAYOUT_ANCHOR_Y
end

local function syncCascadeScroll()
    if not state.cascade or state.dragging or not state.followScroll then return end
    if cascadeFinished() then
        -- 全部出场后停到最底部，保证看到的是最新（最下方）的奖励
        if state.scrollMax > 0 then
            state.scrollY = state.scrollMax
            state.scrollVel = 0
        end
        return
    end
    local elapsed = cascadeElapsed() + 0.04
    if elapsed < 0 then return end
    local shown = cascadeShownCount(elapsed)
    if shown <= VISIBLE_ROWS * COLS then
        state.scrollY = 0
        return
    end
    local row = math.ceil(shown / COLS)
    local _, rawCY = getCellCenter(row, 1)
    local bottom = rawCY + ICON_SIZE * 0.5
    -- 第三行及以后自动上滚，新图标底边贴住两行窗口
    state.scrollY = bottom - CLIP_BOTTOM
    clampScroll()
    state.scrollVel = 0
end

-- ======================== Public API ========================

--- 初始化（加载图片资源，仅调用一次）
---@param vg any NanoVG 上下文
function RewardPopup.init(vg)
    cachedVg = vg
    ImageCache.init(vg)
    imgPanel = nvgCreateImage(vg, "image/界面底板/弹窗奖励/UI_GXHD_1_dark.png", 0)
    if imgPanel < 0 then print("[RewardPopup] WARN: UI_GXHD_1_dark.png load failed") end
end

--- 展示奖励弹窗
---@param title string 奖励类型标题（如 "首通奖励"、"宝箱奖励"）
---@param rewards table[] 奖励列表，每项格式见文件头部注释
---@param opts table|nil 可选参数 { onItemClick = function(item, index), onClose = function(), subtitle = string }
local function showNow(title, rewards, opts)
    battlePausedAt_ = nil
    battleResumedAt_ = 0
    state.title    = title or "奖励"
    state.rowTag   = opts and opts.row or nil
    state.subtitle = (opts and opts.subtitle) or ""
    state.scrollY = 0
    state.scrollMax = 0
    state.dragging = false
    state.dragMoved = 0
    state.scrollVel = 0
    state.followScroll = false
    state.onItemClick = opts and opts.onItemClick or nil
    state.onClose     = opts and opts.onClose     or nil
    state.repeatDraw = opts and not opts.row and opts.repeatDraw or nil
    if state.repeatDraw and (type(state.repeatDraw.getCost) ~= "function"
        or type(state.repeatDraw.onContinue) ~= "function") then state.repeatDraw = nil end
    state.repeatAfterClose = nil
    state.battleHoldStart = nil
    -- 跟随触发面板：显式 opts.panel 优先，否则取横屏当前焦点面板（全局 H_focusPanel）
    state.panel = (opts and opts.panel) or (H_focusPanel or nil)

    -- 排序：资源类排前，角色/装备类排后
    local resources = {}
    local heroes = {}
    local equips = {}
    local artifacts = {}
    for _, item in ipairs(rewards) do
        if item.type == "hero" then
            heroes[#heroes + 1] = item
        elseif item.type == "equip" then
            equips[#equips + 1] = item
        elseif item.type == "artifact" then
            artifacts[#artifacts + 1] = item
        else
            resources[#resources + 1] = item
        end
    end

    -- 角色按品质降序排列
    table.sort(heroes, function(a, b)
        local qa = a.quality or 1
        local qb = b.quality or 1
        return qa > qb
    end)

    -- 装备按品质降序、等级降序排列
    table.sort(equips, function(a, b)
        local qa = a.quality or 1
        local qb = b.quality or 1
        if qa ~= qb then return qa > qb end
        local la = a.level or 1
        local lb = b.level or 1
        return la > lb
    end)

    -- 神器按品质降序排列
    table.sort(artifacts, function(a, b)
        local qa = a.quality or 1
        local qb = b.quality or 1
        return qa > qb
    end)

    -- 合并：资源在前，角色居中，装备在后，神器最后
    state.items = {}
    for _, item in ipairs(resources) do
        state.items[#state.items + 1] = item
    end
    for _, item in ipairs(heroes) do
        state.items[#state.items + 1] = item
    end
    for _, item in ipairs(equips) do
        state.items[#state.items + 1] = item
    end
    for _, item in ipairs(artifacts) do
        state.items[#state.items + 1] = item
    end

    -- 计算滚动最大值
    local totalRows = math.ceil(math.max(#state.items, 1) / COLS)
    local totalContentH = totalRows * ICON_SIZE + (totalRows - 1) * ROW_GAP
    state.scrollMax = math.max(0, totalContentH - GRID_H)
    recomputeLayoutScale()

    state.open = true
    state.animPhase = "opening"
    state.animStart = time.elapsedTime
    closedAt_ = 0  -- 重置关闭保护（重新打开时清除残留）
    state.cascade = wantsCascade(state.title, opts)
    state.followScroll = state.rowTag ~= nil and state.cascade
    -- 非逐件弹出（整屏立即显示）且内容超出一屏时：开屏自动平滑滚到最底部，
    -- 让玩家直接看到最新（最下方）的奖励；手动拖拽/滚轮会取消该动画。
    state.autoScroll = nil
    if not state.cascade and state.scrollMax > 0 then
        state.autoScroll = { t = 0, dur = 0.5, to = state.scrollMax }
    end
    cascade = RewardCascade.new(#state.items, {
        interval     = CASCADE_INTERVAL,
        intervalTail = CASCADE_INTERVAL_TAIL,
        fastAfter    = CASCADE_FAST_AFTER,
        popDur       = CASCADE_POP_DUR,
        lead         = CASCADE_LEAD,
    })
    cascade:start(time.elapsedTime)
    state.sfxPlayed = 0
    print("[RewardPopup] show: " .. title .. ", items=" .. #state.items
        .. ", rows=" .. tostring(math.ceil(#state.items / COLS))
        .. ", scrollMax=" .. tostring(state.scrollMax)
        .. ", hintY=" .. tostring(HINT_CY)
        .. ", panelBottom=" .. tostring(PANEL_CY + PANEL_H * 0.5)
        .. ", cascade=" .. tostring(state.cascade))
    if state.cascade then
        print(string.format("[RewardPopup] cascade start lead=%.2f head=%.2f tail=%.2f after=%d pop=%.2f",
            CASCADE_LEAD, CASCADE_INTERVAL, CASCADE_INTERVAL_TAIL, CASCADE_FAST_AFTER, CASCADE_POP_DUR))
        GameSFX.play("level_up")
    end
end

local function queueBattle(title, rewards, opts)
    local queueOpts = copyRewardData(opts or {})
    queueOpts.cascade = wantsCascade(title, opts)
    queueOpts.panel = queueOpts.panel or "center" -- 行内奖励不随侧栏焦点拆成多个队列
    pendingBattle_:push(title, rewards, queueOpts)
end

function RewardPopup.show(title, rewards, opts)
    if opts and opts.row then
        if battleBlocked() or state.open or pendingBattle_:hasPending() or RewardPopup.isOpen() then
            queueBattle(title, rewards, opts)
            return
        end
    elseif state.open and state.rowTag then
        -- 主动领奖优先，保留完整展示进度；关闭中的行也要完成原回调。
        ---@type table<string, any>
        local snapshot = {}
        for key, value in pairs(state) do rawset(snapshot, key, value) end
        snapshot.dragging, snapshot.dragMoved, snapshot.scrollVel = false, 0, 0
        pendingBattle_:prepend({
            state = snapshot, cascade = cascade, pausedAt = battlePausedAt_ or time.elapsedTime,
        })
    end
    showNow(title, rewards, opts)
end

local function pumpBattleRewards()
    if state.open or not pendingBattle_:hasPending() or battleBlocked() or RewardPopup.isOpen() then return end
    local entry = pendingBattle_:pop()
    if entry.state then
        for key in pairs(state) do state[key] = nil end
        for key, value in pairs(entry.state) do state[key] = value end
        cascade = entry.cascade
        local paused = math.max(0, time.elapsedTime - entry.pausedAt)
        state.animStart = state.animStart + paused
        if cascade then cascade.revealStart = cascade.revealStart + paused end
        if state.battleHoldStart then state.battleHoldStart = state.battleHoldStart + paused end
        battlePausedAt_, battleResumedAt_, closedAt_ = nil, time.elapsedTime, 0
        print("[RewardPopup] 主动领奖结束，恢复战斗奖励进度")
    else
        showNow(entry.title, entry.rewards, entry.opts)
    end
end

--- 关闭奖励弹窗（启动关闭动画）
function RewardPopup.close()
    if not syncBattleVisibility() then return end
    if state.animPhase == "closing" then return end
    state.animPhase = "closing"
    state.animStart = time.elapsedTime
    print("[RewardPopup] closing (anim)")
end

---@param dx number
---@param dy number
---@return boolean
function RewardPopup.hitPanel(dx, dy)
    if not syncBattleVisibility() then return false end
    if not state.open then return false end
    dx = invLayoutX(dx)
    dy = invLayoutY(dy)
    local bottom = math.max(PANEL_CY + PANEL_H * 0.5
        + (state.repeatDraw and ResultRepeatFooter.EXTRA_HEIGHT or 0),
        (state.repeatDraw and ResultRepeatFooter.HINT_Y or HINT_CY) + HINT_FONT)
    return dx >= PANEL_CX - PANEL_W * 0.5 and dx <= PANEL_CX + PANEL_W * 0.5
        and dy >= GLOW_CY - GLOW_H * 0.5 and dy <= bottom + 24
end

--- 是否打开（含关闭后保护期，防止点击穿透）
---@return boolean
function RewardPopup.isOpen()
    if not syncBattleVisibility() then return false end
    if state.open then return true end
    -- 关闭后保护期：吞噬残留事件，防止穿透到下层界面
    if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
        return true
    end
    return false
end

--- 移除指定索引的物品并刷新布局（领取单个后调用）
---@param index number 1-based 物品索引
function RewardPopup.removeItem(index)
    if not state.open then return end
    if index < 1 or index > #state.items then return end
    table.remove(state.items, index)
    -- 重算滚动上限
    local totalRows = math.ceil(math.max(#state.items, 1) / COLS)
    local totalContentH = totalRows * ICON_SIZE + (totalRows - 1) * ROW_GAP
    state.scrollMax = math.max(0, totalContentH - GRID_H)
    recomputeLayoutScale()
    clampScroll()
    -- 如果物品已全部领取，自动关闭弹窗
    if #state.items == 0 then
        RewardPopup.close()
    end
end

--- 更新标题（领取后刷新剩余件数）
---@param title string
function RewardPopup.setTitle(title)
    state.title = title or state.title
end

--- 更新（惯性滚动 + 动画状态机）
---@param dt number
function RewardPopup.update(dt)
    if not syncBattleVisibility() then return end
    if not state.open then
        pumpBattleRewards()
        return
    end

    -- 动画状态机
    if state.animPhase == "opening" then
        local elapsed = time.elapsedTime - state.animStart
        if elapsed >= ANIM_OPEN_DURATION then
            state.animPhase = "open"
        end
    elseif state.animPhase == "closing" then
        local elapsed = time.elapsedTime - state.animStart
        if elapsed >= ANIM_CLOSE_DURATION then
            state.open = false
            state.animPhase = "none"
            state.items = {}
            closedAt_ = time.elapsedTime  -- 记录关闭时刻，启动点击穿透保护
            print("[RewardPopup] closed")
            local cb = state.onClose
            local continueDraw = state.repeatAfterClose
            state.onClose, state.repeatAfterClose, state.repeatDraw = nil, nil, nil
            if cb then cb() end
            if continueDraw and not state.open then continueDraw() end
            return
        end
    end

    if state.cascade and state.animPhase ~= "closing" then
        local elapsed = cascadeElapsed()
        local due = 0
        if elapsed >= 0 then
            due = cascadeShownCount(elapsed)
        end
        while state.sfxPlayed < due do
            state.sfxPlayed = state.sfxPlayed + 1
            local item = state.items[state.sfxPlayed]
            print(string.format("[RewardPopup] cascade reveal %d/%d type=%s",
                state.sfxPlayed, #state.items, item and item.type or "?"))
            playObtainSfx(item)
        end
        syncCascadeScroll()
    end

    -- 自动战斗掉落只在完整出场后停留三秒；遮挡和主动领奖会平移起点。
    -- 等待队列不追加到当前动画，避免持续掉落反复重开、永远无法收起。
    if state.rowTag and not state.onItemClick and state.animPhase == "open" and cascadeFinished() then
        if not state.battleHoldStart then
            local readyAt = state.animStart + ANIM_OPEN_DURATION
            if state.cascade and cascade then
                readyAt = math.max(readyAt, cascade.revealStart + cascade:startAt(cascade.count) + cascade.popDur)
            end
            state.battleHoldStart = readyAt
        end
        if state.dragging then state.battleHoldStart = time.elapsedTime end
        if time.elapsedTime - state.battleHoldStart >= BATTLE_HOLD_DURATION then
            print("[RewardPopup] 战斗掉落展示完成，自动收起")
            RewardPopup.close()
            return
        end
    end

    -- 非逐件弹出：开屏平滑滚到底部（显示最下方的最新奖励）
    local as = state.autoScroll
    if as and not state.dragging then
        as.t = as.t + dt
        local k = math.min(1, as.t / as.dur)
        state.scrollY = as.to * (1 - (1 - k) * (1 - k))  -- ease-out quad
        if k >= 1 then
            state.scrollY = as.to
            state.autoScroll = nil
        end
        state.scrollVel = 0
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

--- 刚滑过奖励列表时，这次松开不算点击
---@return boolean
function RewardPopup.consumedDrag()
    if not syncBattleVisibility() then return false end
    return (state.dragMoved or 0) > 12
end

--- 处理点击（松开时调用）
--- 点击面板外部区域关闭弹窗；点击物品图标触发 onItemClick 回调
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function RewardPopup.handleInput(dx, dy)
    if not syncBattleVisibility() then return false end
    if state.open and state.rowTag and battleResumedAt_ > 0
        and time.elapsedTime - battleResumedAt_ < 0.05 then return true end
    if not state.open then
        -- 关闭保护期内：吞噬事件，防止穿透
        if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
            return true
        end
        return false
    end

    -- 关闭动画中不再改写继续动作，连点只消费一次。
    if state.animPhase == "closing" then return true end
    -- 同帧保护：防止 show() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.animStart < 0.05 then return true end
    -- 拖动列表后松开，不关闭、不点物品
    if RewardPopup.consumedDrag() then
        state.dragMoved = 0
        return true
    end

    -- 逐个获得未结束时，点击只跳过动画，避免奖励还没看完就被关掉
    if skipCascade() then return true end

    -- 屏幕设计坐标 → 布局坐标系（与绘制层缩放对应）
    dx = invLayoutX(dx)
    dy = invLayoutY(dy)

    if state.repeatDraw then
        local count = ResultRepeatFooter.hit(dx, dy)
        if count > 0 then
            local onContinue = state.repeatDraw.onContinue
            state.repeatAfterClose = function() onContinue(count) end
            RewardPopup.close()
            return true
        end
    end

    -- 任何点击都能关闭奖励弹窗：面板外点击同样关闭并消费事件，
    -- 避免弹窗一直挂着挡住后续操作。
    local inPanel = dx >= PANEL_CX - PANEL_W * 0.5 and dx <= PANEL_CX + PANEL_W * 0.5
                and dy >= GLOW_CY - GLOW_H * 0.5 and dy <= PANEL_CY + PANEL_H * 0.5
    if not inPanel then
        RewardPopup.close()
        return true
    end

    -- 点击物品图标检测（仅在裁剪区域内且有回调时）
    if state.onItemClick
       and dx >= CLIP_LEFT and dx <= CLIP_RIGHT
       and dy >= CLIP_TOP  and dy <= CLIP_BOTTOM then
        local items = state.items
        local totalRows = math.ceil(math.max(#items, 1) / COLS)
        for row = 1, totalRows do
            -- 不满一行时居中偏移（与绘制一致）
            local rowStartIdx = (row - 1) * COLS + 1
            local rowItemCount = math.min(COLS, #items - rowStartIdx + 1)
            local rowOffsetX = 0
            if rowItemCount < COLS then
                rowOffsetX = (COLS - rowItemCount) * (ICON_SIZE + COL_GAP) * 0.5
            end

            for col = 1, COLS do
                local idx = (row - 1) * COLS + col
                local item = items[idx]
                if not item then goto skip end
                local cx, rawCY = getCellCenter(row, col)
                cx = cx + rowOffsetX  -- 不满一行时居中
                local cy = rawCY - state.scrollY
                -- 跳过不可见
                if cy + ICON_SIZE * 0.5 < CLIP_TOP or cy - ICON_SIZE * 0.5 > CLIP_BOTTOM then
                    goto skip
                end
                -- AABB 碰撞检测
                local half = ICON_SIZE * 0.5
                if dx >= cx - half and dx <= cx + half
                   and dy >= cy - half and dy <= cy + half then
                    state.onItemClick(item, idx)
                    return true
                end
                ::skip::
            end
        end
    end

    -- 点击面板任意位置 → 关闭
    RewardPopup.close()
    return true
end

--- 处理拖拽开始
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function RewardPopup.handleDragBegin(dx, dy)
    if not syncBattleVisibility() then return false end
    if not state.open then
        -- 关闭保护期内：吞噬事件，防止穿透
        if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
            return true
        end
        return false
    end

    -- 屏幕设计坐标 → 布局坐标系
    dx = invLayoutX(dx)
    dy = invLayoutY(dy)

    -- 在图标区域内开始拖拽 → 滚动
    if dx >= CLIP_LEFT and dx <= CLIP_RIGHT
       and dy >= CLIP_TOP and dy <= CLIP_BOTTOM then
        state.dragging  = true
        state.dragLastY = dy
        state.dragMoved = 0
        state.scrollVel = 0
        state.followScroll = false
        state.autoScroll = nil  -- 手动拖拽取消开屏自动滚动
    end

    return true
end

--- 处理拖拽移动
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function RewardPopup.handleDragMove(dx, dy)
    if not syncBattleVisibility() then return false end
    if not state.open then
        if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
            return true
        end
        return false
    end

    if state.dragging then
        local delta = state.dragLastY - invLayoutY(dy)
        state.dragMoved = (state.dragMoved or 0) + math.abs(delta)
        if state.scrollMax > 0 then
            state.scrollY = state.scrollY + delta
            state.scrollVel = delta
            clampScroll()
        end
        state.dragLastY = invLayoutY(dy)
    end

    return true
end

--- 处理拖拽结束
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function RewardPopup.handleDragEnd(dx, dy)
    if not syncBattleVisibility() then return false end
    if not state.open then
        if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
            return true
        end
        return false
    end

    if state.rowTag and state.battleHoldStart then state.battleHoldStart = time.elapsedTime end
    if state.dragging then
        state.dragging = false
    end

    return true
end

--- 处理滚轮
---@param wheel number
function RewardPopup.handleScroll(wheel)
    if not syncBattleVisibility() then return end
    if not state.open then return end
    if state.rowTag and state.battleHoldStart then state.battleHoldStart = time.elapsedTime end
    state.scrollY = state.scrollY - wheel * 60
    state.followScroll = false
    state.autoScroll = nil  -- 手动滚轮取消开屏自动滚动
    clampScroll()
    state.scrollVel = 0
end

-- ======================== 绘制 ========================

--- 行内区域绘制用的变换参数（逆映射必须与 drawRegion 完全一致）
---@param rx number
---@param ry number
---@param rw number
---@param rh number
---@return number ox, number oy, number fit
local function regionTransform(rx, ry, rw, rh)
    local fit = math.min(rw / (DESIGN_W * 1.04), rh / 920)
    return rx + rw * 0.5, ry + rh * 0.48, fit
end

local function regionToDesign(wx, wy, rx, ry, rw, rh)
    local ox, oy, fit = regionTransform(rx, ry, rw, rh)
    return (wx - ox) / fit + PANEL_CX, (wy - oy) / fit + PANEL_CY
end

--- [三行并行] 行内绘制: 遮罩只盖本行, 弹窗等比缩放嵌入行内
---@param vg any NanoVG 上下文
---@param rx number
---@param ry number
---@param rw number
---@param rh number
---@param rowTag number 归属行（1..3）; 不匹配则不绘制
function RewardPopup.drawRegion(vg, rx, ry, rw, rh, rowTag)
    if not syncBattleVisibility() then return end
    if not state.open or state.rowTag ~= rowTag then return end

    -- 不再画行内黑色叠加层，弹窗直接嵌入行内
    -- 按面板中心嵌入真实战斗行，不再以偏上的旧光晕中心定位。
    local ox, oy, fit = regionTransform(rx, ry, rw, rh)
    nvgSave(vg)
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, fit, fit)
    nvgTranslate(vg, -PANEL_CX, -PANEL_CY)
    RewardPopup.drawContent(vg)
    nvgRestore(vg)
end

--- [三行并行] 当前归属行（nil=全局）
function RewardPopup.currentRowTag()
    if not syncBattleVisibility() then return nil end
    return state.open and state.rowTag or nil
end

--- [三面板] 当前归属面板 'left'|'center'|'right'（nil=全屏居中）
function RewardPopup.currentPanel()
    if not syncBattleVisibility() then return nil end
    return state.open and state.panel or nil
end

--- [三行并行] 行内输入：窗口坐标 → 设计空间，交给统一的 handleInput。
--- 走这里才能保留同帧保护与「逐个获得未结束时先跳过动画」的行为；
--- 直接调 close() 会让玩家通关后随手一点就把弹窗关掉，看起来像没弹。
---@param wx number 窗口坐标 X
---@param wy number 窗口坐标 Y
---@param rx number 行内矩形
---@param ry number
---@param rw number
---@param rh number
---@return boolean 是否消费事件
function RewardPopup.handleInputRegion(wx, wy, rx, ry, rw, rh)
    if not syncBattleVisibility() then return false end
    if not state.open or state.rowTag == nil then return false end
    local dx, dy = regionToDesign(wx, wy, rx, ry, rw, rh)
    return RewardPopup.handleInput(dx, dy)
end

-- 行内滚动与点击复用同一逆变换，布局缩放仍由原输入函数处理。
function RewardPopup.handleDragRegion(phase, wx, wy, rx, ry, rw, rh)
    if not syncBattleVisibility() or not state.open or not state.rowTag then return false end
    local dx, dy = regionToDesign(wx, wy, rx, ry, rw, rh)
    if phase == "begin" then return RewardPopup.handleDragBegin(dx, dy) end
    if phase == "move" then return RewardPopup.handleDragMove(dx, dy) end
    if phase == "end" then return RewardPopup.handleDragEnd(dx, dy) end
    return false
end

function RewardPopup.handleScrollRegion(wheel, wx, wy, rx, ry, rw, rh)
    if not syncBattleVisibility() or not state.open or not state.rowTag then return false end
    if not wx or not wy or wx < rx or wx > rx + rw or wy < ry or wy > ry + rh then return false end
    RewardPopup.handleScroll(wheel)
    return true
end

--- 全局绘制（无行归属时走原全屏路径；归属左/右面板时由 drawRegion 在面板视口内绘制）
function RewardPopup.draw(vg)
    if not syncBattleVisibility() then return end
    if not state.open or state.rowTag then return end
    if state.panel and state.panel ~= 'center' then return end

    -- 不再画全屏黑色叠加层，弹窗直接浮在场景上
    RewardPopup.drawContent(vg)
end

--- 弹窗内容（无遮罩; 由 draw/drawRegion 包裹）
function RewardPopup.drawContent(vg)
    if not state.open or not syncBattleVisibility() then return end

    -- === 动画进度计算 ===
    local animAlpha = 1.0   -- 整体透明度
    local animScale = 1.0   -- 内容缩放

    if state.animPhase == "opening" then
        local elapsed = time.elapsedTime - state.animStart
        local t = math.min(1.0, elapsed / ANIM_OPEN_DURATION)
        animAlpha = t              -- 线性淡入
        animScale = easeOutBack(t) -- 从小到大回弹
    elseif state.animPhase == "closing" then
        local elapsed = time.elapsedTime - state.animStart
        local t = math.min(1.0, elapsed / ANIM_CLOSE_DURATION)
        animAlpha = 1.0 - t                -- 线性淡出
        animScale = 1.0 - easeInCubic(t) * 0.3  -- 缩小到 0.7
    end

    -- （遮罩由 draw / drawRegion 外层负责）

    -- === 以弹窗中心为原点进行缩放 ===
    local pivotX, pivotY = DESIGN_W * 0.5, GLOW_CY
    nvgSave(vg)
    nvgTranslate(vg, pivotX, pivotY)
    nvgScale(vg, animScale, animScale)
    nvgTranslate(vg, -pivotX, -pivotY)
    nvgGlobalAlpha(vg, animAlpha)

    -- 布局自适应缩放（少量物品时整体缩小，最内层变换）
    applyLayoutTransform(vg)

    if state.cascade and not cascadeFinished() then
        local elapsed = cascadeElapsed()
        if elapsed >= 0 then
            local shown = math.max(1, cascadeShownCount(elapsed))
            local gap = cascadeGap(shown + 1)
            if gap <= 0 then gap = CASCADE_INTERVAL_TAIL end
            local phase = (elapsed - cascadeStartAt(shown)) / gap
            if phase < 0 then phase = 0 end
            if phase > 1 then phase = 1 end
            local pulse = (1 - phase) * (1 - phase)
            local haloInner = nvgRGBA(255, 210, 90, math.floor(90 * pulse))
            local haloOuter = nvgRGBA(255, 170, 40, 0)
            ---@cast haloInner NVGcolor
            ---@cast haloOuter NVGcolor
            local halo = nvgRadialGradient(vg, GLOW_CX, GLOW_CY, 30, 380, haloInner, haloOuter)
            nvgBeginPath(vg)
            nvgCircle(vg, GLOW_CX, GLOW_CY, 380)
            nvgFillPaint(vg, halo)
            nvgFill(vg)
        end
    end

    -- 3) 背景面板
    local extraHeight = state.repeatDraw and ResultRepeatFooter.EXTRA_HEIGHT or 0
    drawImageCentered(vg, imgPanel, PANEL_CX, PANEL_CY + extraHeight * 0.5,
        PANEL_W, PANEL_H + extraHeight, 1.0)

    -- 4) 奖励类型文本（暗金亮 + 深色描边，贴合暗黑主题）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x23, 0x1a, 0x10, 255))
    local tStep = math.pi * 2 / 16
    for si = 0, 15 do
        local sa = si * tStep
        nvgText(vg, TITLE_CX + math.cos(sa) * 3, TITLE_CY + math.sin(sa) * 3, state.title, nil)
    end
    nvgFillColor(vg, nvgRGBA(0xf7, 0xfe, 0x77, 255))
    nvgText(vg, TITLE_CX, TITLE_CY, state.title, nil)

    if state.subtitle and state.subtitle ~= "" then
        nvgFontSize(vg, 28)
        nvgFillColor(vg, nvgRGBA(0xE8, 0xDC, 0xC8, 230))
        nvgText(vg, TITLE_CX, TITLE_CY + 42, state.subtitle, nil)
    end

    -- 5) 奖励图标网格（裁剪区域内）
    local items = state.items
    local totalRows = math.ceil(math.max(#items, 1) / COLS)

    nvgSave(vg)
    -- 只裁在两行窗口内。放宽裁剪会让图标和光效画出面板。
    nvgIntersectScissor(vg, CLIP_LEFT, CLIP_TOP, GRID_W, GRID_H)

    if state.cascade and not cascadeFinished() then
        local elapsed = math.max(0, cascadeElapsed())
        for i = 1, 16 do
            local seed = i * 97.3
            local x = CLIP_LEFT + ((seed * 13 + elapsed * (16 + i)) % GRID_W)
            local y = CLIP_TOP + ((seed * 7 + elapsed * (36 + i * 2.4)) % GRID_H)
            nvgBeginPath(vg)
            nvgCircle(vg, x, y, 1.1 + (i % 3) * 0.55)
            nvgFillColor(vg, nvgRGBA(255, 214, 120, 36 + (i % 5) * 14))
            nvgFill(vg)
        end
    end

    for row = 1, totalRows do
        -- 计算该行实际物品数，不满一行时居中偏移
        local rowStartIdx = (row - 1) * COLS + 1
        local rowItemCount = math.min(COLS, #items - rowStartIdx + 1)
        local rowOffsetX = 0
        if rowItemCount < COLS then
            rowOffsetX = (COLS - rowItemCount) * (ICON_SIZE + COL_GAP) * 0.5
        end

        for col = 1, COLS do
            local popping = false
            local popT = 1.0
            local drawThis = true
            local idx = (row - 1) * COLS + col
            local item = items[idx]
            if not item then goto continue end

            local cx, rawCY = getCellCenter(row, col)
            cx = cx + rowOffsetX  -- 不满一行时居中
            local cy = rawCY - state.scrollY

            -- 跳过不可见
            if cy + ICON_SIZE * 0.5 < CLIP_TOP then goto continue end
            if cy - ICON_SIZE * 0.5 > CLIP_BOTTOM then goto continue end

            local tNow = cascadeT(idx)
            if not tNow then
                drawCascadeAnticipate(vg, cx, cy, idx)
                drawThis = false
            else
                popT = tNow
                popping = popT < 1
            end
            if drawThis then
            if popping then
                local ar, ag, ab = itemAccent(item)
                drawCascadeBurst(vg, cx, cy, popT, ar, ag, ab)
            end
            nvgSave(vg)
            if popping then
                RewardCascade.applyPop(vg, cx, cy, popT or 1.0, animAlpha)
            end

            if item.type == "equip" then
                -- ========== 装备图标 ==========
                local q = item.quality or 1

                -- 品质背景框
                local qBgImg = getQualityBg(q)
                if qBgImg >= 0 then
                    drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end

                -- 装备图标（内缩 12px）
                local equipImg = getEquipIcon(item.templateId)
                if equipImg >= 0 then
                    local iconPadding = 12
                    local iconInner = ICON_SIZE - iconPadding * 2
                    DarkIcon.drawIconDark(vg, equipImg, cx, cy, iconInner, iconInner, 1.0)  --
                end

                -- 满包转存的装备仍展示奖励，但明确标示实际去向。
                if item.destination == "lootbox" then
                    DrawUtil.drawTextStroke(vg, cx, cy - ICON_SIZE * 0.5 + 18,
                        "已入遗匣", 27, NVG_ALIGN_CENTER + NVG_ALIGN_TOP,
                        230, 198, 125, 3)
                end
                -- 等级角标（右下角，描边）
                if item.level and item.level > 0 then
                    do
                        local lvlText = "Lv." .. tostring(item.level)
                        local lvlX = cx + ICON_SIZE * 0.5 - 8
                        local lvlY = cy + ICON_SIZE * 0.5 - 8
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, fitBadgeFont(vg, lvlText))
                        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                        local sStep = math.pi * 2 / 16
                        for si = 0, 15 do
                            local sa = si * sStep
                            nvgText(vg, lvlX + math.cos(sa) * BADGE_STROKE, lvlY + math.sin(sa) * BADGE_STROKE, lvlText, nil)
                        end
                        nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                        nvgText(vg, lvlX, lvlY, lvlText, nil)
                    end
                end
            elseif item.type == "hero" then
                -- ========== 角色头像图标（[统一角色框] 品质色描边，替代 ZBBJ 贴图底） ==========
                local iconPadding = 12
                local iconInner = ICON_SIZE - iconPadding * 2
                local heroImg = getHeroIcon(item.heroId)
                HeroFrame.draw(vg, {
                    cx = cx, cy = cy, size = iconInner,
                    heroId = item.heroId,
                    iconHandle = heroImg,
                    quality = item.quality or 3,
                    state = "owned",
                })

                -- 名称角标（右下角，描边）
                if item.name then
                    local nameText = item.name
                    local nameX = cx + ICON_SIZE * 0.5 - 8
                    local nameY = cy + ICON_SIZE * 0.5 - 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, fitBadgeFont(vg, nameText))
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, nameX + math.cos(sa) * BADGE_STROKE, nameY + math.sin(sa) * BADGE_STROKE, nameText, nil)
                    end
                    nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                    nvgText(vg, nameX, nameY, nameText, nil)
                end
            elseif item.type == "artifact" then
                ArtifactAssetUtil.drawIcon(vg, item, cx, cy, ICON_SIZE, {})

            elseif item.type == "seed" then
                -- ========== 种子图标（待鉴定装备）==========
                local q = item.quality or 1

                -- 品质背景框
                local qBgImg = getQualityBg(q)
                if qBgImg >= 0 then
                    drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end

                -- "?" 问号图标（居中，描边，品质色）
                local SEED_Q_COLORS = DarkIcon.QUALITY_TRIM  -- [B-方案] 统一古卷色表
                local qc = SEED_Q_COLORS[q] or SEED_Q_COLORS[1]
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 80)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                -- 描边
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
                local sStep = math.pi * 2 / 12
                for si = 0, 11 do
                    local sa = si * sStep
                    nvgText(vg, cx + math.cos(sa) * 3, cy + math.sin(sa) * 3, "?", nil)
                end
                -- 正文（品质色）
                nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
                nvgText(vg, cx, cy, "?", nil)

                -- 数量角标（右下角，描边）
                if item.amount and item.amount > 0 then
                    local amtText = "×" .. NumberUtil.format(item.amount)
                    local amtX = cx + ICON_SIZE * 0.5 - 8
                    local amtY = cy + ICON_SIZE * 0.5 - 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, fitBadgeFont(vg, amtText))
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local bStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * bStep
                        nvgText(vg, amtX + math.cos(sa) * BADGE_STROKE, amtY + math.sin(sa) * BADGE_STROKE, amtText, nil)
                    end
                    nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                    nvgText(vg, amtX, amtY, amtText, nil)
                end
            elseif item.type == "shard" and item.heroId then
                -- ========== 英雄碎片 ==========
                local heroId = tonumber(item.heroId)
                local heroDef = HeroConfig.get(heroId)
                local q = heroDef and heroDef.quality or 3

                -- [统一角色框] 碎片：品质色描边头像 + 左上碎片角标
                local shardSize = ICON_SIZE - 12
                HeroFrame.draw(vg, {
                    cx = cx, cy = cy, size = shardSize,
                    heroId = heroId,
                    quality = q,
                    state = "owned",
                })
                local badgeSize = math.floor(shardSize * 53 / 160 + 0.5)
                if DrawUtil._shardBadgeImg and DrawUtil._shardBadgeImg >= 0 then
                    drawImageCentered(vg, DrawUtil._shardBadgeImg,
                        cx - shardSize * 0.5 + badgeSize * 0.5,
                        cy - shardSize * 0.5 + badgeSize * 0.5,
                        badgeSize, badgeSize, 1.0)
                end

                if item.amount and item.amount > 0 then
                    do
                        local amtText = "×" .. NumberUtil.format(item.amount)
                        local amtX = cx + ICON_SIZE * 0.5 - 8
                        local amtY = cy + ICON_SIZE * 0.5 - 8
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, fitBadgeFont(vg, amtText))
                        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                        local bStep = math.pi * 2 / 16
                        for si = 0, 15 do
                            local sa = si * bStep
                            nvgText(vg, amtX + math.cos(sa) * BADGE_STROKE, amtY + math.sin(sa) * BADGE_STROKE, amtText, nil)
                        end
                        nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                        nvgText(vg, amtX, amtY, amtText, nil)
                    end
                end
            else
                local def = RESOURCE_DEFS[item.type]
                local q = def and def.quality or 1

                -- 品质背景框
                local qBgImg = getQualityBg(q)
                if qBgImg >= 0 then
                    drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end

                -- 资源图标（内缩 12px）
                local resImg = getResourceIcon(item.type)
                if resImg >= 0 then
                    local iconPadding = 12
                    local iconInner = ICON_SIZE - iconPadding * 2
                    drawImageCentered(vg, resImg, cx, cy, iconInner, iconInner, 1.0)
                end

                -- 数量角标（右下角，描边，K/M格式化）
                if item.amount and item.amount > 0 then
                    do
                        local amtText = "×" .. NumberUtil.format(item.amount)
                        local amtX = cx + ICON_SIZE * 0.5 - 8
                        local amtY = cy + ICON_SIZE * 0.5 - 8
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, fitBadgeFont(vg, amtText))
                        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                        local sStep = math.pi * 2 / 16
                        for si = 0, 15 do
                            local sa = si * sStep
                            nvgText(vg, amtX + math.cos(sa) * BADGE_STROKE, amtY + math.sin(sa) * BADGE_STROKE, amtText, nil)
                        end
                        nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                        nvgText(vg, amtX, amtY, amtText, nil)
                    end
                end
            end

            nvgRestore(vg)
            if popping then
                drawCascadeGlint(vg, cx, cy, popT)
            end
            end

            ::continue::
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    if state.scrollMax > 8 then
        local trackH = GRID_H - 16
        local thumbH = math.max(36, trackH * (GRID_H / (GRID_H + state.scrollMax)))
        local travel = math.max(1, trackH - thumbH)
        local thumbY = CLIP_TOP + 8 + (state.scrollY / state.scrollMax) * travel
        nvgBeginPath(vg)
        nvgRoundedRect(vg, CLIP_RIGHT - 8, thumbY, 6, thumbH, 3)
        nvgFillColor(vg, nvgRGBA(0xf7, 0xfe, 0x77, 170))
        nvgFill(vg)
    end

    -- 6) 宝箱继续按钮仅在奖励全部出场后可见，普通奖励保持原提示。
    local hint = HINT_TEXT
    if state.cascade and not cascadeFinished() then
        hint = "点击跳过"
    elseif state.repeatDraw then
        ResultRepeatFooter.draw(vg, state.repeatDraw, getResourceIcon)
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, HINT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xC8, 0xC0, 0xB0, 200))
    nvgText(vg, HINT_CX, state.repeatDraw and ResultRepeatFooter.HINT_Y or HINT_CY, hint, nil)

    -- 恢复布局缩放，再恢复缩放/透明变换
    if (state.layoutScale or 1.0) ~= 1.0 then nvgRestore(vg) end
    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)
end

return RewardPopup
