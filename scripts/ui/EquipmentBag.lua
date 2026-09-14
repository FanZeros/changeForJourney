-- ============================================================================
-- EquipmentBag - 临时装备背包界面
-- 从 CharacterDetail 的装备槽位点击打开
-- 按槽位类型过滤显示背包中的装备
-- ============================================================================

local GameConfig       = require("config.GameConfig")
local DarkIcon         = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local EquipmentConfig  = require("config.EquipmentConfig")
local HeroConfig       = require("config.HeroConfig")
local HeroAssetUtil    = require("config.HeroAssetUtil")
local ClassConfig      = require("config.ClassConfig")
local AD               = require("systems.AttributeDef")
local PlayerStore      = require("client.data.PlayerStore")
local AVC              = require("config.AdvancementConfig")
local EquipmentDetail  = require("ui.EquipmentDetail")
local ImageCache       = require("ui.ImageCache")
local BF               = require("systems.ButtonFeedback")

local EquipmentBag = {}

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 背包状态 ========================

local bagState = {
    open       = false,
    closing    = false,   -- 关闭动画中
    slot       = nil,     -- 打开时的目标槽位 "weapon" | "offhand" | "armor" | "accessory" | nil
    filter     = nil,     -- 当前页签过滤；nil = 所有
    slotName   = "",      -- "主武器" | "副武器" | "护甲" | "饰品" | "全部装备"
    heroId     = nil,     -- 当前角色 ID（传递给 EquipmentDetail）
    scrollY    = 0,
    scrollMax  = 0,
    dragging   = false,
    dragLastY  = 0,
    scrollVel  = 0,
    openTime   = 0,       -- 打开动画开始时间
    closeTime  = 0,       -- 关闭动画开始时间
    onSelect   = nil,     -- 选择回调 function(seq, equip)，设置后点击格子直接回调而非打开详情
}

-- ======================== 动画常量 ========================

local ANIM_DURATION       = 0.25   -- 打开动画时长(秒)
local CLOSE_ANIM_DURATION = 0.20   -- 关闭动画时长(秒)
local SLIDE_DIST          = 1200   -- 从上方滑入的距离（像素）

local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 布局常量 ========================

-- 背包背景
local BAG_BG_CX, BAG_BG_CY = 540, 1183
local BAG_BG_W,  BAG_BG_H  = 996, 1589

-- 标题 "背包"
local BAG_TITLE_CX, BAG_TITLE_CY = 540, 522
local BAG_TITLE_FONT = 60
local BAG_TITLE_R, BAG_TITLE_G, BAG_TITLE_B = 0x36, 0x2c, 0x21

-- 部位名称 / 过滤页签
local BAG_SLOT_CX, BAG_SLOT_CY = 540, 585
local BAG_SLOT_FONT = 40
local BAG_SLOT_R, BAG_SLOT_G, BAG_SLOT_B = 0xb6, 0xb0, 0x9d

local FILTER_TABS = {
    { key = nil,        label = "所有",   slotName = "全部装备" },
    { key = "weapon",   label = "主武器", slotName = "主武器" },
    { key = "offhand",  label = "副武器", slotName = "副武器" },
    { key = "armor",    label = "护甲",   slotName = "护甲" },
    { key = "accessory",label = "饰品",   slotName = "饰品" },
}
local TAB_Y    = 585
local TAB_H    = 44
local TAB_W    = 140
local TAB_GAP  = 10
local TAB_FONT = 26
local TAB_TOTAL_W = #FILTER_TABS * TAB_W + (#FILTER_TABS - 1) * TAB_GAP
local TAB_X0   = BAG_BG_CX - TAB_TOTAL_W * 0.5

local function tabRect(i)
    local x = TAB_X0 + (i - 1) * (TAB_W + TAB_GAP)
    return x, TAB_Y - TAB_H * 0.5, TAB_W, TAB_H
end

local function sameFilter(a, b)
    if a == nil and b == nil then return true end
    return a == b
end

-- 格子
local CELL_SIZE   = 160
local CELL_RADIUS = 16  -- [B-方案] 圆角收紧，贴合古卷硬朗感
local CELL_GAP    = 30
local CELL_COLS   = 4
local CELL_FIRST_ROW_TOP = 627   -- 第一行顶部 Y

-- 列位置计算：第一列左边距 176px
local CELL_MARGIN_LEFT = 176
local CELL_COL_CX = {}
for c = 1, CELL_COLS do
    CELL_COL_CX[c] = CELL_MARGIN_LEFT + (c - 1) * (CELL_SIZE + CELL_GAP) + CELL_SIZE * 0.5
end

-- 裁剪区域：顶部 Y=627，底部 Y=1780
local GRID_CLIP_TOP = CELL_FIRST_ROW_TOP
local GRID_CLIP_BOTTOM = 1780
local GRID_CLIP_H   = GRID_CLIP_BOTTOM - GRID_CLIP_TOP  -- 1780 - 627 = 1153

-- 可见行数（根据裁剪高度反算，用于滚动最大值计算）
local VISIBLE_CONTENT_H = GRID_CLIP_H

-- 滚动参数
local SCROLL_FRICTION  = 0.90
local SCROLL_MIN_VEL   = 0.5
local SCROLL_WHEEL_STEP = 60

-- [B-方案] 原空格平涂常量已废弃（空格子改用 DarkIcon.drawNine "slot" 暗铁凹槽）

-- 品质边框颜色：[B-方案] 统一引用 DarkIcon.QUALITY_TRIM 古卷色表
local QUALITY_BORDER = DarkIcon.QUALITY_TRIM

-- ======================== 图片资源 ========================

local imgBagBg = -1
local imgIconUp = -1  -- ICON_UP 角标（战斗力提升指示）
local imgLock = -1    -- 锁定角标 UI_ICON_SUO
local imgHeroIcons = {}  -- [heroId] = nvgImage handle, 角色头像角标
-- 装备图标/品质背景缓存已迁移至 ImageCache 共享模块（LRU 淘汰，防止 VRAM 累积）

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

local function hitTest(dx, dy, cx, cy, w, h)
    return dx >= cx - w * 0.5 and dx <= cx + w * 0.5
       and dy >= cy - h * 0.5 and dy <= cy + h * 0.5
end

local function clampScroll()
    bagState.scrollY = math.max(0, math.min(bagState.scrollMax, bagState.scrollY))
end

--- 三行战斗页覆盖层：背包画在中间战斗区，不盖灰底、不被右侧栏裁剪
local overlayRegion = nil  -- { x, y, w, h } 窗口坐标，nil = 不覆盖

local function overlayFit()
    if not overlayRegion then return 1 end
    return math.min(overlayRegion.w / BAG_BG_W, overlayRegion.h / BAG_BG_H)
end

--- 窗口坐标 → 背包设计坐标（覆盖层开启时）
---@param wx number
---@param wy number
---@return number dx
---@return number dy
function EquipmentBag.overlayToDesign(wx, wy)
    local R = overlayRegion
    if not R then return wx, wy end
    local fit = overlayFit()
    return (wx - R.x - R.w * 0.5) / fit + BAG_BG_CX,
           (wy - R.y - R.h * 0.5) / fit + BAG_BG_CY
end

--- 设置/清除战斗区覆盖矩形
---@param x number|nil
---@param y number|nil
---@param w number|nil
---@param h number|nil
function EquipmentBag.setOverlayRegion(x, y, w, h)
    if x == nil then
        overlayRegion = nil
        return
    end
    overlayRegion = { x = x, y = y, w = w, h = h }
end

function EquipmentBag.hasOverlayRegion()
    return overlayRegion ~= nil
end

--- 角色装备栏打开的背包才覆盖战斗页（铁匠铺选择模式不覆盖）
function EquipmentBag.shouldBattleOverlay()
    return bagState.open and bagState.onSelect == nil
end

--- 覆盖层绘制：无灰底，等比铺进战斗区内矩形
---@param vg any
function EquipmentBag.drawOverlay(vg)
    if not bagState.open or not overlayRegion then return end
    local R = overlayRegion
    local fit = overlayFit()
    nvgSave(vg)
    nvgIntersectScissor(vg, R.x, R.y, R.w, R.h)
    nvgTranslate(vg, R.x + R.w * 0.5, R.y + R.h * 0.5)
    nvgScale(vg, fit, fit)
    nvgTranslate(vg, -BAG_BG_CX, -BAG_BG_CY)
    EquipmentBag.draw(vg, { skipOverlay = true })
    nvgRestore(vg)
end

-- ======================== Public API ========================

--- 初始化（加载图片资源）
---@param vg any NanoVG 上下文
function EquipmentBag.init(vg)
    imgBagBg = nvgCreateImage(vg, "image/UI_EJBB.png", 0)
    imgIconUp = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    imgLock = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)

    -- 加载角色头像角标
    HeroAssetUtil.preloadIcons(vg, imgHeroIcons)

    ImageCache.init(vg)
    EquipmentDetail.init(vg)
end

--- 获取装备图标（委托 ImageCache 共享缓存）
---@param templateId string 模板 ID（如 "W1"）
---@return number nvgImage handle (-1 if failed)
local function getEquipIcon(templateId)
    return ImageCache.getEquipIcon(templateId)
end

--- 获取品质背景框（委托 ImageCache 共享缓存）
---@param quality number 品质等级（1-5）
---@return number nvgImage handle (-1 if failed)
local function getQualityBg(quality)
    return ImageCache.getQualityBg(quality)
end

--- 打开背包
---@param slot string 槽位类型 "weapon"|"offhand"|"armor"|"accessory"
---@param slotName string 显示名称 "主武器"|"副武器"|"护甲"|"饰品"
---@param heroId number|nil 当前角色 ID（传递给 EquipmentDetail，选择模式可为 nil）
---@param onSelect function|nil 选择回调 function(seq, equip)，设置后点击格子直接回调而非打开详情
function EquipmentBag.open(slot, slotName, heroId, onSelect)
    bagState.open      = true
    bagState.closing   = false
    bagState.slot       = slot
    bagState.filter     = slot          -- 打开时定位到该部位；nil 则为「所有」
    bagState.slotName   = slotName or (slot == nil and "全部装备" or "")
    bagState.heroId     = heroId
    bagState.scrollY    = 0
    bagState.scrollMax  = 0
    bagState.dragging   = false
    bagState.scrollVel  = 0
    bagState.openTime   = time.elapsedTime
    bagState.onSelect   = onSelect
    print("[EquipmentBag] open slot=" .. tostring(slot) .. " name=" .. tostring(slotName) .. " heroId=" .. tostring(heroId) .. " selectMode=" .. tostring(onSelect ~= nil))
end

--- 关闭背包（启动关闭动画）
function EquipmentBag.close()
    if bagState.closing then return end
    bagState.closing  = true
    bagState.closeTime = time.elapsedTime
    print("[EquipmentBag] close")
end

--- 是否打开（包含关闭动画中）
---@return boolean
function EquipmentBag.isOpen()
    return bagState.open
end

--- 获取英雄的 advBranch（从客户端缓存的 heroes 数据中读取）
---@param heroId number
---@return table|nil advBranch
local function getHeroAdvBranch(heroId)
    local heroesData = PlayerStore.Get("heroes")
    if not heroesData or not heroesData.roster then return nil end
    local hd = heroesData.roster[heroId] or heroesData.roster[tostring(heroId)]
    return hd and hd.advBranch or nil
end

--- 获取英雄当前主手装备的武器类型（用于 207/220 双持判断）
---@param heroId number
---@return string|nil weaponType 武器子类型名（如 "单手剑"），nil 表示未装备主手
local function getEquippedWeaponType(heroId)
    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.equipped or not equipData.inventory then return nil end
    local heroEquipped = equipData.equipped[heroId]
    if not heroEquipped then return nil end
    local weaponSeq = heroEquipped["weapon"]
    if not weaponSeq then return nil end
    local weaponEquip = equipData.inventory[tostring(weaponSeq)]
    if not weaponEquip then return nil end
    return weaponEquip.type
end

--- 构建英雄可穿戴的装备子类型集合（按槽位）
--- weapon/offhand 来自 HeroConfig，armor 来自 ClassConfig 的 armorTypes
--- 207/220 双持天赋：offhand 槽改为显示武器而非常规副手
---@param heroId number
---@param slot string
---@return table|nil 可穿戴子类型 set { ["单手剑"]=true, ... }；nil 表示不限制
---@return string|nil dualWieldMode "different"(207)|"same"(220)|nil
local function buildWearableSet(heroId, slot)
    if slot == "accessory" then
        return nil, nil  -- 饰品无限制
    end

    local heroCfg = HeroConfig.get(heroId)
    if not heroCfg then return nil, nil end

    if slot == "weapon" then
        local types = heroCfg.weaponTypes
        if not types or #types == 0 then return nil, nil end
        local set = {}
        for _, t in ipairs(types) do set[t] = true end
        return set, nil
    end

    if slot == "offhand" then
        -- 检查 207/220 双持天赋
        local advBranch = getHeroAdvBranch(heroId)
        local dualMode = AVC.getDualWieldMode(advBranch)

        if dualMode then
            -- 双持模式：副手槽改为显示单手武器
            -- 基于英雄的 weaponTypes 构建可选武器类型集合
            local weaponTypes = heroCfg.weaponTypes
            if not weaponTypes or #weaponTypes == 0 then return nil, dualMode end

            -- 获取当前主手武器类型
            local mainWeaponType = getEquippedWeaponType(heroId)

            local set = {}
            for _, wt in ipairs(weaponTypes) do
                -- 只允许单手武器（双手武器不能放副手）
                -- 检查该类型是否有 onehand 的装备（通过名称判断）
                -- 双手剑/双手斧/法杖/弓箭 是 twohand，不能放副手
                local isTwohandOnly = (wt == "双手剑" or wt == "双手斧" or wt == "法杖" or wt == "弓箭")
                if not isTwohandOnly then
                    if dualMode == "different" then
                        -- 207: 只显示与主手不同类型的武器
                        if mainWeaponType == nil or wt ~= mainWeaponType then
                            set[wt] = true
                        end
                    elseif dualMode == "same" then
                        -- 220: 只显示与主手相同类型的武器
                        if mainWeaponType ~= nil and wt == mainWeaponType then
                            set[wt] = true
                        end
                    end
                end
            end
            return set, dualMode
        end

        -- 常规模式
        local types = heroCfg.offhandTypes
        if not types or #types == 0 then return nil, nil end
        local set = {}
        for _, t in ipairs(types) do set[t] = true end
        return set, nil
    end

    if slot == "armor" then
        local classCfg = ClassConfig.get(heroCfg.classId)
        if not classCfg or not classCfg.armorTypes or #classCfg.armorTypes == 0 then
            return nil, nil
        end
        local set = {}
        for _, armorEnum in ipairs(classCfg.armorTypes) do
            local name = AD.ARMOR_TYPE_NAME[armorEnum]
            if name then set[name] = true end
        end
        return set, nil
    end

    return nil, nil
end

--- 获取背包中当前槽位的装备列表（按英雄可穿戴类型过滤）
---@return table[] 装备列表 { {seq, equip, equipped}, ... }
local function getFilteredEquips()
    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.inventory then
        return {}
    end

    local slot = bagState.filter   -- 页签过滤；nil = 所有
    local heroId = bagState.heroId

    -- 构建可穿戴子类型过滤集合
    local wearableSet, dualWieldMode = buildWearableSet(heroId, slot)

    -- 收集已装备的 seq → 归属英雄 ID（用于标记"已装备"及角色头像角标）
    local equippedSeqs = {}  -- [seqStr] = true (本英雄/当前槽位维度)
    local equippedByHero = {} -- [seqStr] = heroId (全局维度：哪个英雄穿戴了该装备)

    -- 1) 先扫描所有英雄，构建全局归属映射
    if equipData.equipped then
        for hid, heroSlots in pairs(equipData.equipped) do
            if type(heroSlots) == "table" then
                for _, eqSeq in pairs(heroSlots) do
                    equippedByHero[tostring(eqSeq)] = hid
                end
            end
        end
    end

    -- 2) 再按原逻辑构建 equippedSeqs（控制"已装备"标签显示）
    if equipData.equipped then
        if heroId and equipData.equipped[heroId] then
            -- 指定英雄模式：只标记该英雄已装备的装备
            local heroEquipped = equipData.equipped[heroId]
            if slot == "offhand" then
                -- 副手槽位：副手本身 + 主手双手武器也算占用
                if heroEquipped["offhand"] then
                    equippedSeqs[tostring(heroEquipped["offhand"])] = true
                end
                if heroEquipped["weapon"] then
                    local wSeq = tostring(heroEquipped["weapon"])
                    local wEquip = equipData.inventory[wSeq]
                    if wEquip and wEquip.grip == "twohand" then
                        equippedSeqs[wSeq] = true
                    end
                    -- 207/220 双持模式：主手武器也标记为已装备（防止同一武器装两个槽）
                    if dualWieldMode then
                        equippedSeqs[wSeq] = true
                    end
                end
            elseif slot == nil then
                -- 「所有」页签：当前英雄四个槽位都算已装备
                for _, sk in ipairs({ "weapon", "offhand", "armor", "accessory" }) do
                    if heroEquipped[sk] then
                        equippedSeqs[tostring(heroEquipped[sk])] = true
                    end
                end
            else
                if heroEquipped[slot] then
                    equippedSeqs[tostring(heroEquipped[slot])] = true
                end
            end
        elseif not heroId then
            -- 铁匠铺模式（heroId=nil）：遍历所有英雄，标记全部已装备的装备
            for _, heroSlots in pairs(equipData.equipped) do
                if type(heroSlots) == "table" then
                    for _, eqSeq in pairs(heroSlots) do
                        equippedSeqs[tostring(eqSeq)] = true
                    end
                end
            end
        end
    end

    local result = {}
    for seq, equip in pairs(equipData.inventory) do
        -- slot 为 nil 时不过滤槽位（铁匠铺模式：显示全部装备）
        local slotMatch = false
        if slot == nil then
            slotMatch = true
        elseif equip.slot == slot then
            slotMatch = true
        elseif dualWieldMode and slot == "offhand" and equip.slot == "weapon" and equip.grip == "onehand" then
            -- 207/220 天赋：副手槽位也可显示单手武器
            slotMatch = true
        end

        if slotMatch then
            -- 按英雄可穿戴类型过滤
            if wearableSet and not wearableSet[equip.type] then
                goto skip
            end
            local seqStr2 = tostring(seq)
            local isEquipped = equippedSeqs[seqStr2] or false
            local ownerHeroId = equippedByHero[seqStr2]  -- nil 或 heroId
            result[#result + 1] = { seq = seq, equip = equip, equipped = isEquipped, equippedByHeroId = ownerHeroId }
        end
        ::skip::
    end

    -- 已装备排最前，然后按品质降序、等级降序排序
    table.sort(result, function(a, b)
        if a.equipped ~= b.equipped then
            return a.equipped  -- true 排前面
        end
        if a.equip.quality ~= b.equip.quality then
            return a.equip.quality > b.equip.quality
        end
        if a.equip.level ~= b.equip.level then
            return a.equip.level > b.equip.level
        end
        return tostring(a.seq) < tostring(b.seq)
    end)

    return result
end

--- 获取格子行列位置中心坐标
---@param row number 行号（从1开始）
---@param col number 列号（从1开始）
---@return number|nil cx, number cy
local function getCellCenter(row, col)
    local cx = CELL_COL_CX[col]
    local cy = CELL_FIRST_ROW_TOP + CELL_SIZE * 0.5 + (row - 1) * (CELL_SIZE + CELL_GAP)
    return cx, cy
end

-- ======================== 输入处理 ========================

--- 处理点击
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function EquipmentBag.handleInput(dx, dy)
    if not bagState.open then return false end
    if bagState.closing then return true end  -- 关闭动画中消费事件

    -- 装备详情优先处理
    if EquipmentDetail.isOpen() then
        return EquipmentDetail.handleInput(dx, dy)
    end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - bagState.openTime < 0.05 then return true end

    -- 部位页签
    for i, tab in ipairs(FILTER_TABS) do
        local tx, ty, tw, th = tabRect(i)
        if dx >= tx and dx <= tx + tw and dy >= ty and dy <= ty + th then
            if not sameFilter(bagState.filter, tab.key) then
                bagState.filter   = tab.key
                bagState.slotName = tab.slotName
                bagState.scrollY  = 0
                bagState.scrollVel = 0
                BF.trigger("bag_filter_" .. tostring(tab.key or "all"))
            end
            return true
        end
    end

    -- 点击背包背景外部 → 关闭
    if not hitTest(dx, dy, BAG_BG_CX, BAG_BG_CY, BAG_BG_W, BAG_BG_H) then
        EquipmentBag.close()
        return true
    end

    -- 格子区域点击检测
    if dy >= GRID_CLIP_TOP and dy <= GRID_CLIP_BOTTOM then
        local equips = getFilteredEquips()
        local totalRows = math.ceil(math.max(#equips, CELL_COLS) / CELL_COLS)

        for row = 1, totalRows do
            for col = 1, CELL_COLS do
                local idx = (row - 1) * CELL_COLS + col
                ---@type table?
                local entry = equips[idx]
                if entry then
                    local cx, rawCY = getCellCenter(row, col)
                    local cy = rawCY - bagState.scrollY
                    -- 检查点击在可见区域内且命中格子
                    if cy >= GRID_CLIP_TOP - CELL_SIZE * 0.5
                       and cy <= GRID_CLIP_BOTTOM + CELL_SIZE * 0.5
                       and hitTest(dx, dy, cx, cy, CELL_SIZE, CELL_SIZE) then
                        if bagState.onSelect then
                            -- 选择模式：直接回调并关闭背包
                            bagState.onSelect(entry.seq, entry.equip)
                            EquipmentBag.close()
                        else
                            -- 装备模式：打开装备详情面板
                            EquipmentDetail.open(entry.seq, bagState.filter or entry.equip.slot, bagState.heroId)
                        end
                        return true
                    end
                end
            end
        end
    end

    -- 消费事件防止穿透
    return true
end

--- 处理拖拽开始
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function EquipmentBag.handleDragBegin(dx, dy)
    if not bagState.open then return false end
    if bagState.closing then return true end

    -- 在格子区域内开始拖拽 → 启动滚动
    if dy >= GRID_CLIP_TOP and dy <= GRID_CLIP_TOP + GRID_CLIP_H
       and dx >= CELL_MARGIN_LEFT and dx <= CELL_MARGIN_LEFT + CELL_COLS * CELL_SIZE + (CELL_COLS - 1) * CELL_GAP then
        bagState.dragging  = true
        bagState.dragLastY = dy
        bagState.scrollVel = 0
    end

    return true  -- 消费事件
end

--- 处理拖拽移动
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function EquipmentBag.handleDragMove(dx, dy)
    if not bagState.open then return false end

    if bagState.dragging then
        local delta = bagState.dragLastY - dy
        bagState.scrollY = bagState.scrollY + delta
        bagState.scrollVel = delta
        bagState.dragLastY = dy
        clampScroll()
    end

    return true
end

--- 处理拖拽结束
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function EquipmentBag.handleDragEnd(dx, dy)
    if not bagState.open then return false end

    if bagState.dragging then
        bagState.dragging = false
    end

    return true
end

--- 处理滚轮
---@param wheel number 滚轮值
function EquipmentBag.handleScroll(wheel)
    if not bagState.open then return end
    bagState.scrollY = bagState.scrollY - wheel * SCROLL_WHEEL_STEP
    clampScroll()
    bagState.scrollVel = 0
end

-- ======================== 绘制 ========================

--- 绘制背包界面
---@param vg any NanoVG 上下文
---@param opts table|nil { skipOverlay = boolean } 覆盖层绘制时跳过灰底
function EquipmentBag.draw(vg, opts)
    if not bagState.open then return end
    -- 战斗页覆盖开启时，角色栏内不再画背包（本体由 drawOverlay 画）
    -- 首帧 overlayRegion 尚未设置，也要跳过，避免闪在右侧栏
    if not (opts and opts.skipOverlay) then
        if overlayRegion then return end
        if bagState.onSelect == nil then
            local BTP = require("ui.BattleTriPage")
            if BTP.isOpen() then return end
        end
    end

    -- === 动画计算 ===
    local progress, slideOY, overlayAlpha

    if bagState.closing then
        -- 关闭动画
        local elapsed = time.elapsedTime - bagState.closeTime
        local rawT = math.min(1.0, elapsed / CLOSE_ANIM_DURATION)
        progress = 1 - easeInCubic(rawT)       -- 1→0
        if rawT >= 1.0 then
            bagState.open    = false
            bagState.closing = false
            bagState.slot    = nil
            bagState.filter  = nil
            bagState.slotName = ""
            bagState.onSelect = nil
            return
        end
    else
        -- 打开动画
        local elapsed = time.elapsedTime - bagState.openTime
        local rawT = math.min(1.0, elapsed / ANIM_DURATION)
        progress = easeOutCubic(rawT)           -- 0→1
    end

    slideOY      = -SLIDE_DIST * (1 - progress)  -- 从上方滑入
    overlayAlpha = math.floor(128 * progress)     -- 遮罩渐入（50%黑色）
    if overlayRegion then
        overlayAlpha = 0  -- 覆盖战斗页时不加灰底
    end

    -- === 惯性滚动 ===
    if not bagState.dragging and math.abs(bagState.scrollVel) > SCROLL_MIN_VEL then
        bagState.scrollY = bagState.scrollY + bagState.scrollVel
        bagState.scrollVel = bagState.scrollVel * SCROLL_FRICTION
        clampScroll()
    elseif not bagState.dragging then
        bagState.scrollVel = 0
    end

    -- === 获取装备数据 ===
    local equips = getFilteredEquips()
    local totalCells = math.max(#equips, CELL_COLS * 8)  -- 至少显示 8 行空格子
    local totalRows = math.ceil(totalCells / CELL_COLS)

    -- === 计算当前已装备装备的战斗力（用于 ICON_UP 角标判断）===
    local equippedPower = 0
    local offhandPower = 0   -- 副手战斗力（仅 weapon 槽使用，供双手武器对比）
    local heroId = bagState.heroId
    local equipData = heroId and PlayerStore.Get("equipment") or nil
    local heroEquipped = equipData and equipData.equipped and equipData.equipped[heroId]
    if heroEquipped and equipData.inventory then
        -- 当前槽位已装备的战斗力
        local cmpSlot = bagState.filter or bagState.slot
        local eqSeq = cmpSlot and heroEquipped[cmpSlot]
        if eqSeq then
            local eqItem = equipData.inventory[tostring(eqSeq)]
            if eqItem then
                equippedPower = EquipmentDetail.calcEquipPower(eqItem, heroId)
            end
        end

        -- 副手槽：若副手为空但主手是双手武器，基准 = 双手武器战斗力 / 2
        if cmpSlot == "offhand" and equippedPower == 0 then
            local weaponSeq = heroEquipped["weapon"]
            if weaponSeq then
                local weaponItem = equipData.inventory[tostring(weaponSeq)]
                if weaponItem and weaponItem.grip == "twohand" then
                    equippedPower = math.floor(
                        EquipmentDetail.calcEquipPower(weaponItem, heroId) / 2
                    )
                end
            end
        end

        -- 主手槽：预计算副手战斗力（供双手武器 ICON_UP 对比用）
        if cmpSlot == "weapon" then
            local ohSeq = heroEquipped["offhand"]
            if ohSeq then
                local ohItem = equipData.inventory[tostring(ohSeq)]
                if ohItem then
                    offhandPower = EquipmentDetail.calcEquipPower(ohItem, heroId)
                end
            end
        end
    end

    -- 计算滚动最大值
    local totalContentH = totalRows * CELL_SIZE + (totalRows - 1) * CELL_GAP
    bagState.scrollMax = math.max(0, totalContentH - VISIBLE_CONTENT_H)
    clampScroll()

    -- === 1) 全屏半透明遮罩（战斗页覆盖时不加灰底）===
    if overlayAlpha > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
        nvgFill(vg)
    end

    -- === 应用滑入偏移 ===
    nvgSave(vg)
    nvgTranslate(vg, 0, slideOY)

    -- === 2) 背包背景图 ===
    drawImageCentered(vg, imgBagBg, BAG_BG_CX, BAG_BG_CY, BAG_BG_W, BAG_BG_H, 1.0)

    -- === 3) 标题 "背包" ===
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BAG_TITLE_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(BAG_TITLE_R, BAG_TITLE_G, BAG_TITLE_B, 255))
    nvgText(vg, BAG_TITLE_CX, BAG_TITLE_CY, "背包", nil)

    -- === 4) 部位页签（所有 / 主武器 / 副武器 / 护甲 / 饰品）===
    for i, tab in ipairs(FILTER_TABS) do
        local tx, ty, tw, th = tabRect(i)
        local selected = sameFilter(bagState.filter, tab.key)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, ty, tw, th, 10)
        if selected then
            nvgFillColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, 230))
        else
            nvgFillColor(vg, nvgRGBA(0x36, 0x2c, 0x21, 70))
        end
        nvgFill(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, TAB_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if selected then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        else
            nvgFillColor(vg, nvgRGBA(BAG_SLOT_R, BAG_SLOT_G, BAG_SLOT_B, 255))
        end
        nvgText(vg, tx + tw * 0.5, ty + th * 0.5, tab.label, nil)
    end

    -- === 5) 装备格子（裁剪区域） ===
    nvgSave(vg)
    nvgScissor(vg, 0, GRID_CLIP_TOP, DESIGN_W, GRID_CLIP_H)

    for row = 1, totalRows do
        for col = 1, CELL_COLS do
            local idx = (row - 1) * CELL_COLS + col
            local cx, rawCY = getCellCenter(row, col)
            local cy = rawCY - bagState.scrollY

            -- 新手引导热点：第一个装备格子（在可见性裁剪前注册，确保不被 goto 跳过）
            if idx == 1 then
                local _TM = require("systems.TutorialManager")
                if _TM.isActive() then
                    _TM.registerHotspot("equip_item_gifted", cx, cy, CELL_SIZE, CELL_SIZE)
                end
            end

            -- 跳过不可见格子
            if cy + CELL_SIZE * 0.5 < GRID_CLIP_TOP - 10 then
                goto continue
            end
            if cy - CELL_SIZE * 0.5 > GRID_CLIP_TOP + GRID_CLIP_H + 10 then
                goto continue
            end

            ---@diagnostic disable-next-line: assign-type-mismatch
            local entry = equips[idx]

            if entry then
                -- 有装备的格子
                local equip = entry.equip
                local q = equip.quality or 1
                local qColor = QUALITY_BORDER[q] or QUALITY_BORDER[1]

                -- 品质背景框（铺满整个格子）[暗黑化 P2-A]（矢量绘制无条件可用，原贴图+fallback 已废弃）
                DarkIcon.drawQualityBg(vg, q, cx, cy, CELL_SIZE, CELL_SIZE, 1.0)

                -- 装备图标
                local iconImg = getEquipIcon(equip.templateId)
                if iconImg >= 0 then
                    local iconPadding = 12
                    local iconSize = CELL_SIZE - iconPadding * 2
                    DarkIcon.drawIconDark(vg, iconImg, cx, cy, iconSize, iconSize, 1.0)  -- [暗黑化 P2-B]
                else
                    -- 无图标时回退为文字显示
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, 26)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(qColor[1], qColor[2], qColor[3], 255))
                    local displayName = equip.name or "???"
                    if #displayName > 12 then
                        ---@diagnostic disable-next-line: assign-type-mismatch
                        displayName = string.sub(displayName, 1, 12) .. ".."
                    end
                    nvgText(vg, cx, cy, displayName, nil)
                end

                -- 等级角标（右下角，描边）
                do
                    local lvlText = "Lv." .. (equip.level or 1)
                    local lvlX = cx + CELL_SIZE * 0.5 - 8
                    local lvlY = cy + CELL_SIZE * 0.5 - 6
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, 40)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                    -- 黑色描边 16方向
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, lvlX + math.cos(sa) * 4, lvlY + math.sin(sa) * 4, lvlText, nil)
                    end
                    -- 白色填充
                    nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                    nvgText(vg, lvlX, lvlY, lvlText, nil)
                end

                -- 强化角标（右上角，描边，+X）
                if equip.enhanceLevel and equip.enhanceLevel > 0 then
                    local enhText = "+" .. equip.enhanceLevel
                    local enhX = cx + CELL_SIZE * 0.5 - 8
                    local enhY = cy - CELL_SIZE * 0.5 + 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, 36)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                    -- 黑色描边 16方向
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, enhX + math.cos(sa) * 3, enhY + math.sin(sa) * 3, enhText, nil)
                    end
                    -- 绿色填充
                    nvgFillColor(vg, nvgRGBA(0x00, 0xff, 0x60, 255))
                    nvgText(vg, enhX, enhY, enhText, nil)
                end

                -- 左上角角标
                if entry.equipped and heroId then
                    -- 当前英雄已装备 → 显示 "E" 文字角标（48号 斜体 #00ff36 描边5 纯黑）
                    local pad = 28  -- 从单元格边缘到字符视觉中心的距离
                    local eX = cx - CELL_SIZE * 0.5 + pad
                    local eY = cy - CELL_SIZE * 0.5 + pad
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, 48)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgSave(vg)
                    nvgTranslate(vg, eX, eY)  -- 先移到文字位置
                    nvgSkewX(vg, -0.18)       -- 再局部倾斜
                    -- 黑色描边 16方向
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, math.cos(sa) * 5, math.sin(sa) * 5, "E", nil)
                    end
                    -- 绿色填充
                    nvgFillColor(vg, nvgRGBA(0x00, 0xff, 0x36, 255))
                    nvgText(vg, 0, 0, "E", nil)
                    nvgRestore(vg)
                elseif entry.equippedByHeroId then
                    -- 其他英雄已装备 → 显示英雄头像角标
                    local ownerIcon = imgHeroIcons[entry.equippedByHeroId]
                    if ownerIcon and ownerIcon >= 0 then
                        local badgeSize = 66
                        local badgeX = cx - CELL_SIZE * 0.5 + badgeSize * 0.5 + 1
                        local badgeY = cy - CELL_SIZE * 0.5 + badgeSize * 0.5 + 1
                        -- 圆形裁剪绘制头像
                        nvgSave(vg)
                        nvgBeginPath(vg)
                        nvgCircle(vg, badgeX, badgeY, badgeSize * 0.5)
                        nvgFillPaint(vg, nvgImagePattern(vg, badgeX - badgeSize * 0.5, badgeY - badgeSize * 0.5, badgeSize, badgeSize, 0, ownerIcon, 1.0))
                        nvgFill(vg)
                        -- 白色圆形描边
                        nvgBeginPath(vg)
                        nvgCircle(vg, badgeX, badgeY, badgeSize * 0.5)
                        nvgStrokeColor(vg, nvgRGBA(0xff, 0xff, 0xff, 200))
                        nvgStrokeWidth(vg, 2)
                        nvgStroke(vg)
                        nvgRestore(vg)
                    end
                end

                -- ICON_UP 角标（左上角，战斗力高于当前已装备时显示；有角色头像角标时不显示避免重叠）
                if not entry.equipped and not entry.equippedByHeroId and heroId and imgIconUp >= 0 then
                    local itemPower = EquipmentDetail.calcEquipPower(equip, heroId)
                    -- 双手武器替换主手+副手，基准用两者之和
                    local baseline = equippedPower
                    if (bagState.filter or bagState.slot) == "weapon" and equip.grip == "twohand" then
                        baseline = equippedPower + offhandPower
                    end
                    if itemPower > baseline then
                        local upSize = 40
                        local upX = cx - CELL_SIZE * 0.5 + upSize * 0.5 + 2
                        local upY = cy - CELL_SIZE * 0.5 + upSize * 0.5 + 2
                        drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
                    end
                end

                -- 锁定角标：未装备→左上角（与铁匠铺一致）；已装备→左下角避让 E/头像角标
                if equip.locked and imgLock >= 0 then
                    local lockSize = 56
                    local lockX = cx - CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                    local lockY
                    if entry.equipped or entry.equippedByHeroId then
                        lockY = cy + CELL_SIZE * 0.5 - lockSize * 0.5 - 4
                    else
                        lockY = cy - CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                    end
                    drawImageCentered(vg, imgLock, lockX, lockY, lockSize, lockSize, 1.0)
                end
            else
                -- 空格子：暗铁凹槽底（[B-方案] 古卷化，顶部高光+描边材质感）
                DarkIcon.drawNine(vg, "slot", cx - CELL_SIZE * 0.5, cy - CELL_SIZE * 0.5,
                    CELL_SIZE, CELL_SIZE, { radius = CELL_RADIUS })
            end

            ::continue::
        end
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 结束滑入偏移
    nvgRestore(vg)

    -- 装备详情面板（绘制在背包之上）
    EquipmentDetail.draw(vg)
end

return EquipmentBag
