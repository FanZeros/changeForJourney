-- ============================================================================
-- RewardPopup - 通用奖励弹窗模块
-- 首通奖励逐个获得：前 8 个间隔 0.12s，超过 8 个后间隔 0.1s
-- ============================================================================
--
-- 【使用说明】
-- 本模块用于项目中所有奖励弹出展示（首通奖励、宝箱奖励、成就奖励等）。
-- 未来新增奖励类型时，只需调用 RewardPopup.show() 即可：
--
--   local RewardPopup = require("ui.RewardPopup")
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
local DarkIcon        = require("core.DarkIcon")  -- [暗黑化 P2-B] 图标压暗绘制
local HeroConfig      = require("config.HeroConfig")
local NumberUtil      = require("core.NumberUtil")
local DrawUtil        = require("core.DrawUtil")
local ImageCache        = require("ui.ImageCache")
local ArtifactAssetUtil = require("config.ArtifactAssetUtil")
local ResourceDefs      = require("config.ResourceDefs")
local GameSFX           = require("systems.GameSFX")

local RewardPopup = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- ======================== 布局常量 ========================

-- [暗黑化] 去掉全屏/行内黑色叠加层：弹窗直接浮在暗黑场景上，靠光晕与面板自带对比

-- 奖励弹窗锚点（原光晕中心，旋转底图已去掉）
local GLOW_CX, GLOW_CY = 540, 1044
local GLOW_H = 908

-- 背景面板: UI_GXHD_1.png
local PANEL_CX, PANEL_CY = 540, 1194
local PANEL_W,  PANEL_H  = 1080, 685

-- 奖励类型文本
local TITLE_CX, TITLE_CY = 540, 996
local TITLE_FONT = 40

-- 奖励图标区域：只露两行，超出部分上滚，不能画出面板
local ICON_SIZE = 160
local ROW_GAP   = 20
local COL_GAP   = 34
local COLS      = 5
local VISIBLE_ROWS = 2
local GRID_CX = 540
local GRID_H = VISIBLE_ROWS * ICON_SIZE + (VISIBLE_ROWS - 1) * ROW_GAP
local GRID_CY = 1228
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

-- 底部提示文本（[暗黑化] 上移贴近面板底，不再飘在屏幕下沿）
local HINT_CX, HINT_CY = 540, 1596
local HINT_FONT = 50
local HINT_TEXT = "点击空白处关闭"

-- 数量/等级角标（统一右下角角标样式）
local BADGE_FONT   = 40
local BADGE_STROKE = 4

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
    -- 动画状态
    animPhase  = "none",  -- "none"|"opening"|"open"|"closing"
    animStart  = 0,       -- 动画开始时刻（time.elapsedTime）
    -- 首通逐个获得
    cascade     = false,
    revealStart = 0,
    sfxPlayed   = 0,
    -- 物品点击回调
    onItemClick = nil,    -- function(item, index) 点击某个物品时触发
}

-- 滚动参数
local SCROLL_FRICTION  = 0.90
local SCROLL_MIN_VEL   = 0.5

-- 动画参数
local ANIM_OPEN_DURATION  = 0.35   -- 打开动画时长（秒）
local ANIM_CLOSE_DURATION = 0.25   -- 关闭动画时长
local CLOSE_GUARD_DURATION = 0.15  -- 关闭后事件吞噬保护期（防止点击穿透到下层界面）

-- 首通奖励：前 8 个更快弹出，第 9 个起间隔固定 0.1s
local CASCADE_LEAD          = 0.1
local CASCADE_INTERVAL      = 0.12
local CASCADE_INTERVAL_TAIL = 0.1
local CASCADE_FAST_AFTER    = 8
local CASCADE_POP_DUR       = 0.22

--- 第 idx 件与上一件的间隔。idx 从 1 开始，第 1 件没有间隔。
local function cascadeGap(idx)
    if idx <= 1 then return 0 end
    if idx > CASCADE_FAST_AFTER then
        return CASCADE_INTERVAL_TAIL
    end
    return CASCADE_INTERVAL
end

--- 第 idx 件的出场时刻（第 1 件为 0）
local function cascadeStartAt(idx)
    if idx <= 1 then return 0 end
    local t = 0
    for i = 2, idx do
        t = t + cascadeGap(i)
    end
    return t
end

--- 当前已经开始出场的件数
local function cascadeShownCount(elapsed)
    local n = #state.items
    if elapsed < 0 or n <= 0 then return 0 end
    local shown = 0
    for i = 1, n do
        if elapsed + 0.0001 >= cascadeStartAt(i) then
            shown = i
        else
            break
        end
    end
    return shown
end

-- 关闭保护时间戳（关闭完成时记录，保护期内 isOpen() 仍返回 true 以吞噬事件）
local closedAt_ = 0

--- ease-out back 缓动（带回弹）
local function easeOutBack(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

--- ease-in cubic 缓动（加速离开）
local function easeInCubic(t)
    return t * t * t
end

--- ease-out cubic
local function easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

local function wantsCascade(title, opts)
    if opts and opts.cascade == false then return false end
    if opts and opts.cascade == true then return true end
    return type(title) == "string" and string.find(title, "首通", 1, true) ~= nil
end

local function cascadeElapsed()
    return time.elapsedTime - state.revealStart
end

local function cascadeFinished()
    if not state.cascade then return true end
    local n = #state.items
    if n <= 0 then return true end
    return cascadeElapsed() >= cascadeStartAt(n) + CASCADE_POP_DUR
end

--- nil = 尚未出场；0..1 = 弹出中；>1 = 已落地
local function cascadeT(idx)
    if not state.cascade then return 1 end
    local elapsed = cascadeElapsed()
    local startAt = cascadeStartAt(idx)
    if elapsed < startAt then return nil end
    return (elapsed - startAt) / CASCADE_POP_DUR
end

local function itemAccent(item)
    local q = 2
    if item.type == "equip" or item.type == "hero" or item.type == "relic"
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
    if item and (item.type == "equip" or item.type == "artifact" or item.type == "relic") then
        GameSFX.play("install")
    elseif item and item.type == "hero" then
        GameSFX.play("level_up")
    else
        GameSFX.play("ui_click_3")
    end
end

local function skipCascade()
    if not state.cascade or cascadeFinished() then return false end
    state.revealStart = time.elapsedTime - (cascadeStartAt(#state.items) + CASCADE_POP_DUR)
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
    local glowR = ICON_SIZE * (0.28 + t * 0.95)
    local glowA = math.floor(150 * (1 - t) + 28)
    local glow = nvgRadialGradient(vg, cx, cy, 6, glowR,
        nvgRGBA(r, g, b, glowA), nvgRGBA(r, g, b, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, glowR)
    nvgFillPaint(vg, glow)
    nvgFill(vg)

    if t < 0.5 then
        local bt = t / 0.5
        local beamA = math.floor(230 * (1 - bt))
        local beamH = 70 + bt * 150
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 5 - bt * 8, cy - beamH)
        nvgLineTo(vg, cx + 5 + bt * 8, cy - beamH)
        nvgLineTo(vg, cx + 26, cy + 6)
        nvgLineTo(vg, cx - 26, cy + 6)
        nvgClosePath(vg)
        local beam = nvgLinearGradient(vg, cx, cy - beamH, cx, cy,
            nvgRGBA(255, 248, 210, 0), nvgRGBA(255, 228, 120, beamA))
        nvgFillPaint(vg, beam)
        nvgFill(vg)
    end

    for i = 1, 2 do
        local rt = (t - (i - 1) * 0.1) / 0.72
        if rt > 0 and rt < 1 then
            local radius = 16 + rt * (ICON_SIZE * 0.62 + i * 22)
            local a = math.floor(220 * (1 - rt) * (1 - rt))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius)
            nvgStrokeWidth(vg, 2.2 + (1 - rt) * 5)
            nvgStrokeColor(vg, nvgRGBA(255, 236, 168, a))
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius * 0.78)
            nvgStrokeWidth(vg, 1.6)
            nvgStrokeColor(vg, nvgRGBA(r, g, b, math.floor(a * 0.75)))
            nvgStroke(vg)
        end
    end

    if t < 0.72 then
        local rt = t / 0.72
        nvgSave(vg)
        nvgTranslate(vg, cx, cy)
        nvgRotate(vg, rt * 0.55)
        for i = 1, 10 do
            local ang = (i - 1) / 10 * math.pi * 2
            local inner = 18
            local len = 30 + rt * (58 + (i % 3) * 14)
            local a = math.floor(170 * (1 - rt))
            nvgBeginPath(vg)
            nvgMoveTo(vg, math.cos(ang) * inner, math.sin(ang) * inner)
            nvgLineTo(vg, math.cos(ang) * len, math.sin(ang) * len)
            nvgStrokeWidth(vg, 1.4 + (1 - rt) * 2.4)
            nvgStrokeColor(vg, nvgRGBA(255, 232, 150, a))
            nvgStroke(vg)
        end
        nvgRestore(vg)
    end

    for i = 1, 14 do
        local ang = (i - 1) / 14 * math.pi * 2 + 0.35
        local dist = 8 + t * (62 + (i % 4) * 16)
        local sx = cx + math.cos(ang) * dist
        local sy = cy + math.sin(ang) * dist * 0.7 - (1 - t) * 28
        local sa = math.floor(255 * (1 - t) * (1 - t * 0.25))
        local tail = 16 * (1 - t)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        nvgLineTo(vg, sx - math.cos(ang) * tail, sy - math.sin(ang) * tail * 0.7)
        nvgStrokeWidth(vg, 1.8)
        nvgStrokeColor(vg, nvgRGBA(255, 248, 220, sa))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 1.6 + (1 - t) * 2.4)
        nvgFillColor(vg, nvgRGBA(255, 255, 240, sa))
        nvgFill(vg)
    end

    if t < 0.26 then
        local fa = math.floor(210 * (1 - t / 0.26))
        local fr = 18 + (t / 0.26) * 40
        local flash = nvgRadialGradient(vg, cx, cy, 2, fr,
            nvgRGBA(255, 255, 245, fa), nvgRGBA(255, 220, 120, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, fr)
        nvgFillPaint(vg, flash)
        nvgFill(vg)
    end
end

--- 图标上层扫光
local function drawCascadeGlint(vg, cx, cy, t)
    if t < 0.18 or t > 0.82 then return end
    local gt = (t - 0.18) / 0.64
    local glide = -ICON_SIZE * 0.55 + gt * ICON_SIZE * 1.2
    local a = math.floor(150 * math.sin(gt * math.pi))
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, -0.55)
    nvgBeginPath(vg)
    nvgRect(vg, glide - 10, -ICON_SIZE * 0.55, 18, ICON_SIZE * 1.1)
    nvgFillColor(vg, nvgRGBA(255, 255, 245, a))
    nvgFill(vg)
    nvgRestore(vg)
end

local function drawCascadeAnticipate(vg, cx, cy, idx)
    local lead = cascadeElapsed() - cascadeStartAt(idx)
    if lead <= -0.08 then return end
    local a = math.floor(110 * ((lead + 0.08) / 0.08))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - ICON_SIZE * 0.42, cy - ICON_SIZE * 0.42, ICON_SIZE * 0.84, ICON_SIZE * 0.84, 14)
    nvgStrokeWidth(vg, 2)
    nvgStrokeColor(vg, nvgRGBA(247, 220, 120, a))
    nvgStroke(vg)
end

-- ======================== 图片资源 ========================

local imgPanel = -1   -- 背景面板

-- 资源图标缓存: [type] = nvgImage handle
local resourceIconCache = {}

-- 角色头像图标缓存: [heroId] = nvgImage handle
local heroIconCache = {}

-- 遗物类型图标缓存: [relicType] = nvgImage handle
local relicIconCache = {}
local RELIC_ICON_PATHS = {
    [1] = "image/遗物图标/ICON_YWX_GUI.png",   -- 岩龟
    [2] = "image/遗物图标/ICON_YWX_SHE.png",   -- 毒蛇
    [3] = "image/遗物图标/ICON_YWX_LU.png",    -- 白鹿
    [4] = "image/遗物图标/ICON_YWX_LANG.png",  -- 灰狼
    [5] = "image/遗物图标/ICON_YWX_YING.png",  -- 猎鹰
}

-- 装备图标/品质背景缓存已迁移至 ImageCache 共享模块（LRU 淘汰，防止 VRAM 累积）

local cachedVg = nil

-- ======================== 工具函数 ========================

local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

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

--- 获取遗物类型图标（懒加载）
local function getRelicIcon(relicType)
    local cached = relicIconCache[relicType]
    if cached then return cached end
    if not cachedVg then return -1 end
    local path = RELIC_ICON_PATHS[relicType]
    if not path then return -1 end
    local img = nvgCreateImage(cachedVg, path, 0)
    relicIconCache[relicType] = img
    return img
end

--- 获取装备图标（委托 ImageCache 共享缓存）
local function getEquipIcon(templateId)
    return ImageCache.getEquipIcon(templateId)
end

--- 获取品质背景框（委托 ImageCache 共享缓存）
local function getQualityBg(quality)
    return ImageCache.getQualityBg(quality)
end

--- 获取格子中心坐标
local function getCellCenter(row, col)
    local cx = COL_CX[col]
    local cy = FIRST_ROW_TOP + ICON_SIZE * 0.5 + (row - 1) * (ICON_SIZE + ROW_GAP)
    return cx, cy
end

local function syncCascadeScroll()
    if not state.cascade or state.dragging or not state.followScroll then return end
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
function RewardPopup.show(title, rewards, opts)
    state.title    = title or "奖励"
    state.rowTag   = opts and opts.row or nil
    state.subtitle = (opts and opts.subtitle) or ""
    state.scrollY = 0
    state.scrollMax = 0
    state.dragging = false
    state.scrollVel = 0
    state.followScroll = true
    state.onItemClick = opts and opts.onItemClick or nil
    state.onClose     = opts and opts.onClose     or nil

    -- 排序：资源类排前，角色/装备/遗物类排后
    local resources = {}
    local heroes = {}
    local equips = {}
    local relics = {}
    local artifacts = {}
    for _, item in ipairs(rewards) do
        if item.type == "hero" then
            heroes[#heroes + 1] = item
        elseif item.type == "equip" then
            equips[#equips + 1] = item
        elseif item.type == "relic" then
            relics[#relics + 1] = item
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

    -- 遗物按品质降序排列
    table.sort(relics, function(a, b)
        local qa = a.quality or 1
        local qb = b.quality or 1
        return qa > qb
    end)

    -- 神器按品质降序排列
    table.sort(artifacts, function(a, b)
        local qa = a.quality or 1
        local qb = b.quality or 1
        return qa > qb
    end)

    -- 合并：资源在前，角色居中，装备在后，遗物/神器最后
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
    for _, item in ipairs(relics) do
        state.items[#state.items + 1] = item
    end
    for _, item in ipairs(artifacts) do
        state.items[#state.items + 1] = item
    end

    -- 计算滚动最大值
    local totalRows = math.ceil(math.max(#state.items, 1) / COLS)
    local totalContentH = totalRows * ICON_SIZE + (totalRows - 1) * ROW_GAP
    state.scrollMax = math.max(0, totalContentH - GRID_H)

    state.open = true
    state.animPhase = "opening"
    state.animStart = time.elapsedTime
    closedAt_ = 0  -- 重置关闭保护（重新打开时清除残留）
    state.cascade = wantsCascade(state.title, opts)
    state.revealStart = time.elapsedTime + CASCADE_LEAD
    state.sfxPlayed = 0
    print("[RewardPopup] show: " .. title .. ", items=" .. #state.items
        .. ", rows=" .. tostring(math.ceil(#state.items / COLS))
        .. ", scrollMax=" .. tostring(state.scrollMax)
        .. ", cascade=" .. tostring(state.cascade))
    if state.cascade then
        print(string.format("[RewardPopup] cascade start lead=%.2f head=%.2f tail=%.2f after=%d pop=%.2f",
            CASCADE_LEAD, CASCADE_INTERVAL, CASCADE_INTERVAL_TAIL, CASCADE_FAST_AFTER, CASCADE_POP_DUR))
        GameSFX.play("level_up")
    end
end

--- 关闭奖励弹窗（启动关闭动画）
function RewardPopup.close()
    if state.animPhase == "closing" then return end
    state.animPhase = "closing"
    state.animStart = time.elapsedTime
    print("[RewardPopup] closing (anim)")
end

--- 是否打开（含关闭后保护期，防止点击穿透）
---@return boolean
function RewardPopup.isOpen()
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
    if not state.open then return end

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
            state.onClose = nil
            if cb then cb() end
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
    elseif state.followScroll and not state.dragging and state.scrollMax > 0 then
        -- 一次性展示超过两行时，自动上滚到末行，避免图标停在窗口外
        local delta = state.scrollMax - state.scrollY
        if math.abs(delta) > 0.5 then
            state.scrollY = state.scrollY + delta * math.min(1, dt * 5)
            clampScroll()
        else
            state.scrollY = state.scrollMax
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

--- 处理点击（松开时调用）
--- 点击面板外部区域关闭弹窗；点击物品图标触发 onItemClick 回调
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function RewardPopup.handleInput(dx, dy)
    if not state.open then
        -- 关闭保护期内：吞噬事件，防止穿透
        if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
            return true
        end
        return false
    end

    -- 同帧保护：防止 show() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.animStart < 0.05 then return true end

    -- 逐个获得未结束时，点击只跳过动画，避免奖励还没看完就被关掉
    if skipCascade() then return true end

    -- 点击面板外部 → 关闭
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
    if not state.open then
        -- 关闭保护期内：吞噬事件，防止穿透
        if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
            return true
        end
        return false
    end

    -- 在图标区域内开始拖拽 → 滚动
    if dx >= CLIP_LEFT and dx <= CLIP_RIGHT
       and dy >= CLIP_TOP and dy <= CLIP_BOTTOM then
        state.dragging  = true
        state.dragLastY = dy
        state.scrollVel = 0
        state.followScroll = false
    end

    return true
end

--- 处理拖拽移动
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function RewardPopup.handleDragMove(dx, dy)
    if not state.open then
        if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
            return true
        end
        return false
    end

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
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function RewardPopup.handleDragEnd(dx, dy)
    if not state.open then
        if closedAt_ > 0 and (time.elapsedTime - closedAt_) < CLOSE_GUARD_DURATION then
            return true
        end
        return false
    end

    if state.dragging then
        state.dragging = false
    end

    return true
end

--- 处理滚轮
---@param wheel number
function RewardPopup.handleScroll(wheel)
    if not state.open then return end
    state.scrollY = state.scrollY - wheel * 60
    state.followScroll = false
    clampScroll()
    state.scrollVel = 0
end

-- ======================== 绘制 ========================

--- 绘制奖励弹窗（在设计空间内调用）
---@param vg any NanoVG 上下文
--- [三行并行] 行内绘制: 遮罩只盖本行, 弹窗等比缩放嵌入行内
--- @param rowTag number 归属行（1..3）; 不匹配则不绘制
function RewardPopup.drawRegion(vg, rx, ry, rw, rh, rowTag)
    if not state.open or state.rowTag ~= rowTag then return end

    -- [暗黑化] 不再画行内黑色叠加层，弹窗直接嵌入行内
    -- 弹窗内容等比嵌入: 设计锚点(540, GLOW_CY=1044) → 行中心
    local fit = math.min(rw / (DESIGN_W * 1.04), rh / 920)
    nvgSave(vg)
    nvgTranslate(vg, rx + rw * 0.5, ry + rh * 0.48)
    nvgScale(vg, fit, fit)
    nvgTranslate(vg, -540, -GLOW_CY)
    RewardPopup.drawContent(vg)
    nvgRestore(vg)
end

--- [三行并行] 当前归属行（nil=全局）
function RewardPopup.currentRowTag()
    return state.open and state.rowTag or nil
end

--- 全局绘制（无行归属时走原全屏路径）
function RewardPopup.draw(vg)
    if not state.open or state.rowTag then return end

    -- [暗黑化] 不再画全屏黑色叠加层，弹窗直接浮在场景上
    RewardPopup.drawContent(vg)
end

--- 弹窗内容（无遮罩; 由 draw/drawRegion 包裹）
function RewardPopup.drawContent(vg)

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
            local halo = nvgRadialGradient(vg, GLOW_CX, GLOW_CY, 30, 380,
                nvgRGBA(255, 210, 90, math.floor(90 * pulse)),
                nvgRGBA(255, 170, 40, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, GLOW_CX, GLOW_CY, 380)
            nvgFillPaint(vg, halo)
            nvgFill(vg)
        end
    end

    -- 3) 背景面板
    drawImageCentered(vg, imgPanel, PANEL_CX, PANEL_CY, PANEL_W, PANEL_H, 1.0)

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
            local popT = 1
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

            popT = cascadeT(idx) or -1
            if popT < 0 then
                drawCascadeAnticipate(vg, cx, cy, idx)
                drawThis = false
                popT = 1
            else
                popping = popT < 1
            end
            if drawThis then
            if popping then
                local ar, ag, ab = itemAccent(item)
                drawCascadeBurst(vg, cx, cy, popT, ar, ag, ab)
            end
            nvgSave(vg)
            if popping then
                local appear = math.min(1, popT / 0.16)
                local pop = math.min(1, popT / 0.68)
                local iconScale = 0.16 + 0.84 * easeOutBack(pop)
                if iconScale < 0.04 then iconScale = 0.04 end
                local wobble = math.sin(popT * math.pi * 2.4) * (1 - math.min(1, popT)) * 0.2
                local lift = (1 - easeOutCubic(math.min(1, popT / 0.5))) * -56
                nvgGlobalAlpha(vg, animAlpha * appear)
                nvgTranslate(vg, cx, cy + lift)
                nvgRotate(vg, wobble)
                nvgScale(vg, iconScale, iconScale)
                nvgTranslate(vg, -cx, -cy)
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
                    DarkIcon.drawIconDark(vg, equipImg, cx, cy, iconInner, iconInner, 1.0)  -- [暗黑化 P2-B]
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
                        nvgFontSize(vg, BADGE_FONT)
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
                -- ========== 角色头像图标 ==========
                local q = item.quality or 3

                -- 品质背景框
                local qBgImg = getQualityBg(q)
                if qBgImg >= 0 then
                    drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end

                -- 角色头像图标（内缩 12px）
                local heroImg = getHeroIcon(item.heroId)
                if heroImg >= 0 then
                    local iconPadding = 12
                    local iconInner = ICON_SIZE - iconPadding * 2
                    drawImageCentered(vg, heroImg, cx, cy, iconInner, iconInner, 1.0)
                end

                -- 名称角标（右下角，描边）
                if item.name then
                    local nameText = item.name
                    local nameX = cx + ICON_SIZE * 0.5 - 8
                    local nameY = cy + ICON_SIZE * 0.5 - 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, BADGE_FONT)
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
            elseif item.type == "relic" then
                -- ========== 遗物图标（品质背景 + 类型图标）==========
                local q = item.quality or 1

                -- 品质背景框
                local qBgImg = getQualityBg(q)
                if qBgImg >= 0 then
                    drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end

                -- 遗物类型图标（内缩 12px）
                local relicImg = getRelicIcon(item.relicType)
                if relicImg >= 0 then
                    local iconPadding = 12
                    local iconInner = ICON_SIZE - iconPadding * 2
                    drawImageCentered(vg, relicImg, cx, cy, iconInner, iconInner, 1.0)
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
                    nvgFontSize(vg, BADGE_FONT)
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

                local qBgImg = getQualityBg(q)
                if qBgImg >= 0 then
                    drawImageCentered(vg, qBgImg, cx, cy, ICON_SIZE, ICON_SIZE, 1.0)
                end

                DrawUtil.drawShardIcon(vg, heroId, cx, cy, ICON_SIZE - 12, 1.0)

                if item.amount and item.amount > 0 then
                    do
                        local amtText = "×" .. NumberUtil.format(item.amount)
                        local amtX = cx + ICON_SIZE * 0.5 - 8
                        local amtY = cy + ICON_SIZE * 0.5 - 8
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, BADGE_FONT)
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
                        nvgFontSize(vg, BADGE_FONT)
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

    -- 6) 底部提示文本（逐个获得中可点击跳过）
    local hint = HINT_TEXT
    if state.cascade and not cascadeFinished() then
        hint = "点击跳过"
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, HINT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xC8, 0xC0, 0xB0, 200))
    nvgText(vg, HINT_CX, HINT_CY, hint, nil)

    -- 恢复缩放/透明变换
    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)
end

return RewardPopup
