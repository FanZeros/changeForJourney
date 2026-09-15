-- ============================================================================
-- CharacterDetailEquip - 配装面板（角色详情第二个 Tab）
-- 显示背包格子区域，可装备排前且高亮，不可装备变暗
-- 点击格子直接穿戴；点击左侧装备槽位触发重新过滤/排序
-- ============================================================================

local GameConfig      = require("config.GameConfig")
local DarkIcon        = require("core.DarkIcon")  -- [暗黑化 P2-A] 品质底框矢量绘制
local HeroConfig      = require("config.HeroConfig")
local HeroAssetUtil   = require("config.HeroAssetUtil")
local ClassConfig     = require("config.ClassConfig")
local AD              = require("systems.AttributeDef")
local PlayerStore     = require("client.data.PlayerStore")
local EquipmentConfig = require("config.EquipmentConfig")
local ImageCache      = require("ui.ImageCache")
local AVC             = require("config.AdvancementConfig")
local BF              = require("systems.ButtonFeedback")

local M = {}

-- ======================== 图片资源 ========================

local imgHeroIcons = {}   -- [heroId] = nvgImage handle（角色头像角标）
local heroIconsLoaded = false

--- 懒加载英雄头像图标
local function ensureHeroIcons(vg)
    if heroIconsLoaded then return end
    heroIconsLoaded = true
    HeroAssetUtil.preloadIcons(vg, imgHeroIcons)
end

-- ======================== 设计分辨率 ========================

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

-- ======================== 布局常量 ========================

-- 格子区域（参考 BlacksmithDecompose 布局）
local GRID_COLS     = 5
local GRID_CELL     = 160
local GRID_GAP      = 35
local GRID_RADIUS   = 24
local GRID_COL_STEP = GRID_CELL + GRID_GAP   -- 195
local GRID_ROW_STEP = GRID_CELL + GRID_GAP   -- 195

-- 内容区域：配装tab隐藏了经验条/角色名后上移
local GRID_TOP_Y    = 1144    -- 第一行中心 Y（比属性页上移150px）
local GRID_BOTTOM_Y = 2230    -- 底部裁剪 Y（Tab栏上方留白）

-- 水平居中：5列 = 5*160 + 4*35 = 940px；(1080-940)/2 = 70 左边距
local GRID_MARGIN_LEFT = 70
local GRID_FIRST_CX = GRID_MARGIN_LEFT + GRID_CELL * 0.5  -- 150

-- 裁剪区域
local CLIP_TOP    = GRID_TOP_Y - GRID_CELL * 0.5   -- 1214
local CLIP_HEIGHT = GRID_BOTTOM_Y - CLIP_TOP        -- 1016

-- 暗化遮罩（不可装备物品）
local DIM_ALPHA = 160  -- 0-255

-- 滚动参数
local SCROLL_FRICTION   = 0.90
local SCROLL_MIN_VEL    = 0.5

-- ======================== 面板状态 ========================

local panelState = {
    slot       = "weapon",  -- 当前选中槽位
    heroId     = nil,
    scrollY    = 0,
    scrollMax  = 0,
    dragging   = false,
    dragLastY  = 0,
    scrollVel  = 0,
    items      = {},        -- 排序后的装备列表
    dirty      = true,      -- 需要刷新列表
    edWasOpen  = false,     -- 上帧装备详情弹窗是否打开
}

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
    panelState.scrollY = math.max(0, math.min(panelState.scrollMax, panelState.scrollY))
end

-- ======================== 数据逻辑 ========================

--- 获取英雄的 advBranch（用于双持天赋判断）
---@param heroId number
---@return table|nil
local function getHeroAdvBranch(heroId)
    local heroesData = PlayerStore.Get("heroes")
    if not heroesData or not heroesData.roster then return nil end
    local hd = heroesData.roster[heroId] or heroesData.roster[tostring(heroId)]
    return hd and hd.advBranch or nil
end

--- 获取英雄当前主手装备的武器类型
---@param heroId number
---@return string|nil
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

--- 构建英雄可穿戴子类型集合
---@param heroId number
---@param slot string
---@return table|nil set
---@return string|nil dualWieldMode
local function buildWearableSet(heroId, slot)
    if slot == "accessory" then return nil, nil end

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
        local advBranch = getHeroAdvBranch(heroId)
        local dualMode = AVC.getDualWieldMode(advBranch)

        if dualMode then
            local weaponTypes = heroCfg.weaponTypes
            if not weaponTypes or #weaponTypes == 0 then return nil, dualMode end
            local mainWeaponType = getEquippedWeaponType(heroId)
            local set = {}
            for _, wt in ipairs(weaponTypes) do
                local isTwohandOnly = (wt == "双手剑" or wt == "双手斧" or wt == "法杖" or wt == "弓箭")
                if not isTwohandOnly then
                    if dualMode == "different" then
                        if mainWeaponType == nil or wt ~= mainWeaponType then
                            set[wt] = true
                        end
                    elseif dualMode == "same" then
                        if mainWeaponType ~= nil and wt == mainWeaponType then
                            set[wt] = true
                        end
                    end
                end
            end
            return set, dualMode
        end

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

--- 刷新背包列表（过滤+排序）
local function refreshItems()
    local heroId = panelState.heroId
    local slot   = panelState.slot
    if not heroId then
        panelState.items = {}
        panelState.dirty = false
        return
    end

    local equipData = PlayerStore.Get("equipment")
    if not equipData or not equipData.inventory then
        panelState.items = {}
        panelState.dirty = false
        return
    end

    local wearableSet, dualWieldMode = buildWearableSet(heroId, slot)

    -- 收集全局已装备 seq（用于判断是否被其他角色穿戴）
    local equippedByHero = {}  -- [seqStr] = heroId
    if equipData.equipped then
        for hid, heroSlots in pairs(equipData.equipped) do
            if type(heroSlots) == "table" then
                for _, eqSeq in pairs(heroSlots) do
                    equippedByHero[tostring(eqSeq)] = hid
                end
            end
        end
    end

    -- 当前英雄该槽位已装备的 seq（标记为已穿戴，排第一）
    local heroEquipped = equipData.equipped and equipData.equipped[heroId]
    local currentEquipSeq = nil
    if heroEquipped then
        currentEquipSeq = heroEquipped[slot]
    end

    local result = {}
    for seq, equip in pairs(equipData.inventory) do
        -- 槽位过滤
        local slotMatch = false
        if equip.slot == slot then
            slotMatch = true
        elseif dualWieldMode and slot == "offhand" and equip.slot == "weapon" and equip.grip == "onehand" then
            slotMatch = true
        end
        if not slotMatch then goto skip end

        local seqStr = tostring(seq)

        -- 判断是否可穿戴
        local canWear = true
        if wearableSet and not wearableSet[equip.type] then
            canWear = false
        end

        -- 判断是否是当前英雄已装备
        local isEquipped = (currentEquipSeq ~= nil and tostring(currentEquipSeq) == seqStr)

        -- 归属英雄（用于显示其他角色头像角标）
        local ownerHeroId = equippedByHero[seqStr]

        result[#result + 1] = {
            seq       = seq,
            equip     = equip,
            canWear   = canWear,
            equipped  = isEquipped,
            ownerHeroId = ownerHeroId,
        }

        ::skip::
    end

    -- 排序：已装备排第一，可装备在前；同组内按品质降序、等级降序
    table.sort(result, function(a, b)
        -- 已装备的始终排第一
        if a.equipped ~= b.equipped then
            return a.equipped  -- true 排前面
        end
        if a.canWear ~= b.canWear then
            return a.canWear  -- true 排前面
        end
        if a.equip.quality ~= b.equip.quality then
            return a.equip.quality > b.equip.quality
        end
        if a.equip.level ~= b.equip.level then
            return a.equip.level > b.equip.level
        end
        return tostring(a.seq) < tostring(b.seq)
    end)

    panelState.items = result
    panelState.dirty = false

    -- 重新计算滚动范围
    local totalRows = math.ceil(#result / GRID_COLS)
    local contentH  = totalRows * GRID_ROW_STEP - GRID_GAP
    panelState.scrollMax = math.max(0, contentH - CLIP_HEIGHT)
    clampScroll()
end

-- ======================== Public API ========================

--- 当槽位改变时调用（由 CharacterDetail 触发）
---@param slot string
---@param heroId number
function M.onSlotChanged(slot, heroId)
    panelState.slot   = slot
    panelState.heroId = heroId
    panelState.scrollY = 0
    panelState.dirty  = true
end

--- 绘制配装面板
---@param vg any NanoVG 上下文
---@param heroId number 当前英雄 ID
---@param detailState table 详情页状态
function M.draw(vg, heroId, detailState)
    ensureHeroIcons(vg)

    -- 装备详情弹窗关闭后刷新列表（穿戴/卸下后数据已变）
    local EquipmentDetail = require("ui.EquipmentDetail")
    local edOpen = EquipmentDetail.isOpen()
    if panelState.edWasOpen and not edOpen then
        panelState.dirty = true
    end
    panelState.edWasOpen = edOpen

    -- 同步 heroId
    if panelState.heroId ~= heroId then
        panelState.heroId = heroId
        panelState.slot   = detailState.equipSlot or "weapon"
        panelState.dirty  = true
    end

    -- 惯性滚动
    if not panelState.dragging and math.abs(panelState.scrollVel) > SCROLL_MIN_VEL then
        panelState.scrollY = panelState.scrollY + panelState.scrollVel
        panelState.scrollVel = panelState.scrollVel * SCROLL_FRICTION
        clampScroll()
    elseif not panelState.dragging then
        panelState.scrollVel = 0
    end

    -- 数据刷新
    if panelState.dirty then
        refreshItems()
    end

    local items = panelState.items
    local itemCount = #items
    local totalSlots = math.max(itemCount, GRID_COLS * 2)  -- 至少显示 2 行空格

    -- 裁剪区域
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, CLIP_TOP, DESIGN_W, CLIP_HEIGHT)

    for idx = 1, totalSlots do
        local row = math.ceil(idx / GRID_COLS)
        local col = ((idx - 1) % GRID_COLS) + 1
        local cx = GRID_FIRST_CX + (col - 1) * GRID_COL_STEP
        local cy = GRID_TOP_Y + (row - 1) * GRID_ROW_STEP - panelState.scrollY

        -- 视口裁剪优化
        if cy + GRID_CELL * 0.5 < CLIP_TOP or cy - GRID_CELL * 0.5 > CLIP_TOP + CLIP_HEIGHT then
            goto continue_cell
        end

        if idx <= itemCount then
            local item = items[idx]
            local equip = item.equip
            local canWear = item.canWear

            local didScale = BF.begin(vg, "eqp_cell_" .. idx, cx, cy, GRID_CELL, GRID_CELL)

            -- 品质背景
            DarkIcon.drawQualityBg(vg, equip.quality or 1, cx, cy, GRID_CELL, GRID_CELL, 1.0)  -- [暗黑化 P2-A]

            -- 装备图标
            local eqIcon = ImageCache.getEquipIcon(equip.templateId)
            if eqIcon and eqIcon >= 0 then
                DarkIcon.drawIconDark(vg, eqIcon, cx, cy, GRID_CELL - 16, GRID_CELL - 16, 1.0)  -- [暗黑化 P2-B]
            end

            -- 强化角标
            local enhLv = equip.enhanceLevel or 0
            if enhLv > 0 then
                local enhText = "+" .. enhLv
                local enhX = cx + GRID_CELL * 0.5 - 8
                local enhY = cy - GRID_CELL * 0.5 + 8
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, enhX + math.cos(sa) * 3, enhY + math.sin(sa) * 3, enhText, nil)
                end
                nvgFillColor(vg, nvgRGBA(0x00, 0xff, 0x60, 255))
                nvgText(vg, enhX, enhY, enhText, nil)
            end

            -- 等级角标
            local itemLv = equip.level or 1
            if itemLv >= 1 then
                local lvlText = "Lv." .. itemLv
                local lvlX = cx + GRID_CELL * 0.5 - 8
                local lvlY = cy + GRID_CELL * 0.5 - 6
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 40)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, lvlX + math.cos(sa) * 4, lvlY + math.sin(sa) * 4, lvlText, nil)
                end
                nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                nvgText(vg, lvlX, lvlY, lvlText, nil)
            end

            -- 不可装备遮罩（变暗）
            if not canWear then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - GRID_CELL * 0.5, cy - GRID_CELL * 0.5,
                    GRID_CELL, GRID_CELL, GRID_RADIUS)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, DIM_ALPHA))
                nvgFill(vg)
            end

            -- 左上角角标（与临时背包相同逻辑）
            if item.equipped then
                -- 当前英雄已装备 → "E" 文字角标（绿色斜体描边）
                local pad = 28
                local eX = cx - GRID_CELL * 0.5 + pad
                local eY = cy - GRID_CELL * 0.5 + pad
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 48)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgSave(vg)
                nvgTranslate(vg, eX, eY)
                nvgSkewX(vg, -0.18)
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
            elseif item.ownerHeroId and item.ownerHeroId ~= heroId then
                -- 其他英雄已装备 → 英雄头像圆形角标
                local ownerIcon = imgHeroIcons[item.ownerHeroId]
                if ownerIcon and ownerIcon >= 0 then
                    local badgeSize = 66
                    local badgeX = cx - GRID_CELL * 0.5 + badgeSize * 0.5 + 1
                    local badgeY = cy - GRID_CELL * 0.5 + badgeSize * 0.5 + 1
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

            BF.finish(vg, didScale)
        else
            -- 空格子
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - GRID_CELL * 0.5, cy - GRID_CELL * 0.5,
                GRID_CELL, GRID_CELL, GRID_RADIUS)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
            nvgFill(vg)
        end

        ::continue_cell::
    end

    nvgRestore(vg)

    -- 槽位名称（与卡片角色名相同样式，位于格子区域上方）
    local slotNames = { weapon = "主武器", offhand = "副武器", armor = "护甲", accessory = "饰品" }
    local slotLabel = slotNames[panelState.slot] or "装备"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0x7b, 0x53, 0x39, 255))
    nvgText(vg, DESIGN_W * 0.5, 995, slotLabel, nil)
end

--- 处理输入（格子点击+滚动）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@param heroId number
---@param detailState table
---@return boolean
function M.handleInput(dx, dy, heroId, detailState)
    -- 仅处理格子区域内的点击
    if dy < CLIP_TOP or dy > CLIP_TOP + CLIP_HEIGHT then
        return false
    end
    if dx < GRID_MARGIN_LEFT or dx > DESIGN_W - GRID_MARGIN_LEFT then
        return false
    end

    -- 确保数据已刷新
    if panelState.dirty then
        refreshItems()
    end

    local items = panelState.items
    local itemCount = #items

    -- 查找点中的格子
    for idx = 1, itemCount do
        local row = math.ceil(idx / GRID_COLS)
        local col = ((idx - 1) % GRID_COLS) + 1
        local cx = GRID_FIRST_CX + (col - 1) * GRID_COL_STEP
        local cy = GRID_TOP_Y + (row - 1) * GRID_ROW_STEP - panelState.scrollY

        if hitTest(dx, dy, cx, cy, GRID_CELL, GRID_CELL) then
            local item = items[idx]
            if not item then return true end

            -- 不可穿戴的装备（黑色遮罩）禁止点击
            if not item.canWear then
                return true
            end

            -- 打开装备详情弹窗（同临时背包逻辑）
            local EquipmentDetail = require("ui.EquipmentDetail")
            EquipmentDetail.open(item.seq, panelState.slot, heroId)
            print("[EquipPanel] 打开装备详情 seq=" .. tostring(item.seq) .. " slot=" .. panelState.slot)
            return true
        end
    end

    return true  -- 在格子区域内消费事件（防穿透）
end

--- 处理滚动输入（由外层 drag handler 调用）
---@param deltaY number 拖拽增量
function M.onDrag(deltaY)
    panelState.scrollY = panelState.scrollY + deltaY
    panelState.scrollVel = deltaY
    clampScroll()
end

--- 开始拖拽
function M.onDragStart(dy)
    panelState.dragging = true
    panelState.dragLastY = dy
    panelState.scrollVel = 0
end

--- 获取上次拖拽Y坐标
function M.getDragLastY()
    return panelState.dragLastY or 0
end

--- 设置上次拖拽Y坐标
function M.setDragLastY(y)
    panelState.dragLastY = y
end

--- 结束拖拽
function M.onDragEnd()
    panelState.dragging = false
end

--- 判断触摸点是否在格子区域内
---@param dy number 屏幕Y坐标（设计分辨率）
---@return boolean
function M.isInGridArea(dy)
    return dy >= CLIP_TOP and dy <= CLIP_TOP + CLIP_HEIGHT
end

--- 重置面板状态（角色切换时）
function M.reset(heroId, slot)
    panelState.heroId  = heroId
    panelState.slot    = slot or "weapon"
    panelState.scrollY = 0
    panelState.scrollMax = 0
    panelState.dragging = false
    panelState.scrollVel = 0
    panelState.dirty   = true
end

return M
