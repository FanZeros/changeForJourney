-- ============================================================================
-- RewardPopup - 通用奖励弹窗模块
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
local HeroConfig      = require("config.HeroConfig")
local NumberUtil      = require("core.NumberUtil")
local DrawUtil        = require("core.DrawUtil")
local ImageCache        = require("ui.ImageCache")
local ArtifactAssetUtil = require("config.ArtifactAssetUtil")
local ResourceDefs      = require("config.ResourceDefs")

local RewardPopup = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- ======================== 布局常量 ========================

-- 背景遮罩
local MASK_ALPHA = 204  -- 80% 不透明度 (255 * 0.8 ≈ 204)

-- 背景光晕: UI_GXHD_2.png
local GLOW_CX, GLOW_CY = 540, 1044
local GLOW_W,  GLOW_H  = 908, 908
local GLOW_ROTATE_SPEED = 0.5  -- 旋转速度（弧度/秒），与竞技场结算面板一致

-- 背景面板: UI_GXHD_1.png
local PANEL_CX, PANEL_CY = 540, 1194
local PANEL_W,  PANEL_H  = 1080, 685

-- 奖励类型文本
local TITLE_CX, TITLE_CY = 540, 996
local TITLE_FONT = 40

-- 奖励图标区域
local GRID_CX, GRID_CY = 540, 1258
local GRID_W,  GRID_H  = 938, 424

-- 图标尺寸与间距
local ICON_SIZE = 160
local ROW_GAP   = 20
local COL_GAP   = 34
local COLS      = 5

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

-- 底部提示文本
local HINT_CX, HINT_CY = 540, 1697
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
    title    = "",
    subtitle = "",
    items    = {},     -- 排序后的奖励列表
    scrollY  = 0,
    scrollMax = 0,
    dragging  = false,
    dragLastY = 0,
    scrollVel = 0,
    -- 动画状态
    animPhase  = "none",  -- "none"|"opening"|"open"|"closing"
    animStart  = 0,       -- 动画开始时刻（time.elapsedTime）
    -- 光晕旋转
    glowAngle  = 0,
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

-- ======================== 图片资源 ========================

local imgGlow  = -1   -- 背景光晕
local imgPanel = -1   -- 背景面板

-- 资源图标缓存: [type] = nvgImage handle
local resourceIconCache = {}

-- 角色头像图标缓存: [heroId] = nvgImage handle
local heroIconCache = {}

-- 遗物类型图标缓存: [relicType] = nvgImage handle
local relicIconCache = {}
local RELIC_ICON_PATHS = {
    [1] = "image/ICON_YWX_GUI.png",   -- 岩龟
    [2] = "image/ICON_YWX_SHE.png",   -- 毒蛇
    [3] = "image/ICON_YWX_LU.png",    -- 白鹿
    [4] = "image/ICON_YWX_LANG.png",  -- 灰狼
    [5] = "image/ICON_YWX_YING.png",  -- 猎鹰
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

local function drawImageRotated(vg, img, cx, cy, w, h, angle, alpha)
    if img < 0 or alpha <= 0.01 then return end
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)
    local x = -w * 0.5
    local y = -h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
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

-- ======================== Public API ========================

--- 初始化（加载图片资源，仅调用一次）
---@param vg any NanoVG 上下文
function RewardPopup.init(vg)
    cachedVg = vg
    ImageCache.init(vg)
    imgGlow  = nvgCreateImage(vg, "image/UI_GXHD_2.png", 0)
    imgPanel = nvgCreateImage(vg, "image/UI_GXHD_1.png", 0)
    if imgGlow  < 0 then print("[RewardPopup] WARN: UI_GXHD_2.png load failed") end
    if imgPanel < 0 then print("[RewardPopup] WARN: UI_GXHD_1.png load failed") end
end

--- 展示奖励弹窗
---@param title string 奖励类型标题（如 "首通奖励"、"宝箱奖励"）
---@param rewards table[] 奖励列表，每项格式见文件头部注释
---@param opts table|nil 可选参数 { onItemClick = function(item, index), onClose = function(), subtitle = string }
function RewardPopup.show(title, rewards, opts)
    state.title    = title or "奖励"
    state.subtitle = (opts and opts.subtitle) or ""
    state.scrollY = 0
    state.scrollMax = 0
    state.dragging = false
    state.scrollVel = 0
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
    state.glowAngle = 0
    print("[RewardPopup] show: " .. title .. ", items=" .. #state.items)
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

    -- 光晕旋转
    state.glowAngle = state.glowAngle + GLOW_ROTATE_SPEED * dt

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
    clampScroll()
    state.scrollVel = 0
end

-- ======================== 绘制 ========================

--- 绘制奖励弹窗（在设计空间内调用）
---@param vg any NanoVG 上下文
function RewardPopup.draw(vg)
    if not state.open then return end

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

    -- 1) 全屏黑色遮罩（透明度随动画）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(MASK_ALPHA * animAlpha)))
    nvgFill(vg)

    -- === 以弹窗中心为原点进行缩放 ===
    local pivotX, pivotY = DESIGN_W * 0.5, GLOW_CY
    nvgSave(vg)
    nvgTranslate(vg, pivotX, pivotY)
    nvgScale(vg, animScale, animScale)
    nvgTranslate(vg, -pivotX, -pivotY)
    nvgGlobalAlpha(vg, animAlpha)

    -- 2) 背景光晕（持续旋转）
    drawImageRotated(vg, imgGlow, GLOW_CX, GLOW_CY, GLOW_W, GLOW_H, state.glowAngle, 1.0)

    -- 3) 背景面板
    drawImageCentered(vg, imgPanel, PANEL_CX, PANEL_CY, PANEL_W, PANEL_H, 1.0)

    -- 4) 奖励类型文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, TITLE_CX, TITLE_CY, state.title, nil)

    if state.subtitle and state.subtitle ~= "" then
        nvgFontSize(vg, 28)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 230))
        nvgText(vg, TITLE_CX, TITLE_CY + 42, state.subtitle, nil)
    end

    -- 5) 奖励图标网格（裁剪区域内）
    local items = state.items
    local totalRows = math.ceil(math.max(#items, 1) / COLS)

    nvgSave(vg)
    nvgScissor(vg, CLIP_LEFT, CLIP_TOP, GRID_W, GRID_H)

    for row = 1, totalRows do
        -- 计算该行实际物品数，不满一行时居中偏移
        local rowStartIdx = (row - 1) * COLS + 1
        local rowItemCount = math.min(COLS, #items - rowStartIdx + 1)
        local rowOffsetX = 0
        if rowItemCount < COLS then
            rowOffsetX = (COLS - rowItemCount) * (ICON_SIZE + COL_GAP) * 0.5
        end

        for col = 1, COLS do
            local idx = (row - 1) * COLS + col
            local item = items[idx]
            if not item then goto continue end

            local cx, rawCY = getCellCenter(row, col)
            cx = cx + rowOffsetX  -- 不满一行时居中
            local cy = rawCY - state.scrollY

            -- 跳过不可见
            if cy + ICON_SIZE * 0.5 < CLIP_TOP - 10 then goto continue end
            if cy - ICON_SIZE * 0.5 > CLIP_BOTTOM + 10 then goto continue end

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
                    drawImageCentered(vg, equipImg, cx, cy, iconInner, iconInner, 1.0)
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
                local SEED_Q_COLORS = {
                    [1] = { 0xb5, 0xb5, 0xb5 },  -- 普通 - 灰
                    [2] = { 0xa2, 0xff, 0x94 },  -- 优质 - 绿
                    [3] = { 0x72, 0xf2, 0xf5 },  -- 稀有 - 蓝
                    [4] = { 0xef, 0x79, 0xff },  -- 史诗 - 紫
                    [5] = { 0xff, 0xed, 0x00 },  -- 传说 - 金
                    [6] = { 0xff, 0x00, 0x00 },  -- 至臻 - 红
                }
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

            ::continue::
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 6) 底部提示文本 "点击空白处关闭"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, HINT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, HINT_CX, HINT_CY, HINT_TEXT, nil)

    -- 恢复缩放/透明变换
    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)
end

return RewardPopup
