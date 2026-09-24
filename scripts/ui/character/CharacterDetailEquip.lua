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
local PlayerStore     = require("core.PlayerStore")
local ClientDispatcher = require("runtime.ClientDispatcher")
local EquipmentConfig = require("config.EquipmentConfig")
local EquipmentSystem = require("systems.EquipmentSystem")
local EquipmentSetSystem = require("systems.EquipmentSetSystem")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local ImageCache      = require("ui.widget.ImageCache")
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

local GRID_MIN_ROWS = 5   -- 固定 5 行 = 25 格

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
    lastClickSeq  = nil,
    lastClickTime = 0,
    dragItem      = nil,    -- 拖拽中的装备 item
    dragStartX    = 0,
    dragStartY    = 0,
    itemDragging  = false,
    setCodexId = nil,       -- 打开的套装图鉴 id
    setHits    = {},        -- { {setId, x, y, w, h} }
}

local DOUBLE_CLICK_SEC = 0.35
local ITEM_DRAG_PX     = 28

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

---@type fun()
local refreshItems

local function findItemAt(dx, dy)
    if panelState.dirty then refreshItems() end
    local items = panelState.items
    for idx = 1, #items do
        local row = math.ceil(idx / GRID_COLS)
        local col = ((idx - 1) % GRID_COLS) + 1
        local cx = GRID_FIRST_CX + (col - 1) * GRID_COL_STEP
        local cy = GRID_TOP_Y + (row - 1) * GRID_ROW_STEP - panelState.scrollY
        if hitTest(dx, dy, cx, cy, GRID_CELL, GRID_CELL) then
            return items[idx], cx, cy
        end
    end
    return nil
end

local function equipItemNow(item, heroId, slot)
    if not item or not heroId then return false end
    local I18n = require("core.I18n")
    local Toast = require("core.UiToast")
    local BF = require("systems.ButtonFeedback")
    if not item.canWear then
        Toast.show(I18n.t("cannot_wear"))
        require("systems.GameSFX").playUIClick(1)
        BF.trigger("equip_deny")
        print("[EquipPanel] 不可穿戴 seq=" .. tostring(item.seq))
        return true
    end
    local Client = require("runtime.GameAction")
    local Protocol = require("shared.Protocol")
    if item.equipped then
        Client.sendAction(Protocol.ACTION_TYPES.UNEQUIP_ITEM, {
            heroId = heroId,
            slot   = slot or panelState.slot,
        })
        require("systems.GameSFX").playUIClick(2)
        BF.trigger("unequip_quick")
        Toast.show(I18n.t("unequipped"))
        panelState.dirty = true
        print("[EquipPanel] 右键卸下 seq=" .. tostring(item.seq))
        return true
    end
    Client.sendAction(Protocol.ACTION_TYPES.EQUIP_ITEM, {
        seq    = tonumber(item.seq),
        heroId = heroId,
        slot   = slot or panelState.slot,
    })
    require("systems.GameSFX").play("install")
    BF.trigger("equip_quick")
    Toast.show(I18n.t("equipped_ok"))
    panelState.dirty = true
    print("[EquipPanel] 穿戴 seq=" .. tostring(item.seq) .. " slot=" .. tostring(slot or panelState.slot))
    return true
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
    local heroEquipped = EquipmentSystem.getHeroSlots(equipData, heroId)
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

    if slot == "armor" or slot == "helmet" or slot == "shoes" then
        return EquipmentSystem.getWearableTypeSet(heroId, slot), nil
    end

    return nil, nil
end

--- 刷新背包列表（过滤+排序）
refreshItems = function()
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
    local heroEquipped = EquipmentSystem.getHeroSlots(equipData, heroId)
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
        if not equip.type or not equip.slot then
            EquipmentSystem.hydrate(equip)
        end
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
    local totalRows = math.max(GRID_MIN_ROWS, math.ceil(#result / GRID_COLS))
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

local drawDragGhost

--- 绘制配装面板
---@param vg any NanoVG 上下文
---@param heroId number 当前英雄 ID
---@param detailState table 详情页状态
function M.draw(vg, heroId, detailState)
    ensureHeroIcons(vg)

    -- 装备详情弹窗关闭后刷新列表（穿戴/卸下后数据已变）
    local EquipmentDetail = require("ui.character.EquipmentDetail")
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
    local totalSlots = math.max(itemCount, GRID_COLS * GRID_MIN_ROWS)  -- 5 行 25 格

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

            -- 不能穿的装备额外盖一层灰，和能穿的分开
            if not canWear then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - GRID_CELL * 0.5, cy - GRID_CELL * 0.5,
                    GRID_CELL, GRID_CELL, GRID_RADIUS)
                nvgFillColor(vg, nvgRGBA(18, 18, 18, 150))
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
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
            nvgFill(vg)
        end

        ::continue_cell::
    end

    nvgRestore(vg)
    -- 套装进度（可点开图鉴）[槽位顶栏标题已按 704be5a 移除，不再叠加]
    panelState.setHits = {}
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    if eqData then
        local counts = EquipmentSetSystem.countSets(
            eqData, heroId,
            EquipmentSystem.getFromInventory,
            function(data, hid)
                return EquipmentSystem.getHeroSlots(data, hid)
            end)
        local rows = EquipmentSetSystem.summarize(counts)
        if #rows > 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local labels = {}
            local totalW = 0
            local gap = 28
            for i = 1, math.min(3, #rows) do
                local r = rows[i]
                local lab = string.format("%s %d/6", r.name, r.count)
                local w = nvgTextBounds(vg, 0, 0, lab)
                labels[#labels + 1] = { row = r, lab = lab, w = w }
                totalW = totalW + w
            end
            totalW = totalW + gap * (#labels - 1)
            local x = DESIGN_W * 0.5 - totalW * 0.5
            local y = 910
            for i = 1, #labels do
                local it = labels[i]
                local col = it.row.twoActive and { 0xE8, 0xDC, 0xC8 } or { 0x9A, 0x90, 0x80 }
                nvgFillColor(vg, nvgRGBA(0x23, 0x23, 0x23, 220))
                nvgText(vg, x + 2, y + 2, it.lab, nil)
                nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
                nvgText(vg, x, y, it.lab, nil)
                panelState.setHits[#panelState.setHits + 1] = {
                    setId = it.row.setId, x = x, y = y - 16, w = it.w, h = 32, row = it.row,
                }
                x = x + it.w + gap
            end
        end
    end

    -- 套装图鉴浮层
    if panelState.setCodexId then
        local def = EquipmentSetConfig.get(panelState.setCodexId)
        local hitRow = nil
        for i = 1, #panelState.setHits do
            if panelState.setHits[i].setId == panelState.setCodexId then
                hitRow = panelState.setHits[i].row
                break
            end
        end
        if def then
            local boxW, boxH = 820, 420
            local bx, by = (DESIGN_W - boxW) * 0.5, 980
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, boxW, boxH, 18)
            nvgFillColor(vg, nvgRGBA(0x1A, 0x14, 0x12, 240))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(0xC4, 0xA0, 0x5A, 200))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            local title = def.name .. (hitRow and string.format("  %d/6", hitRow.count) or "")
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 34)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xF7, 0xFE, 0x77, 255))
            nvgText(vg, DESIGN_W * 0.5, by + 46, title, nil)

            local lines = {
                { n = 2, text = def.desc2 or "", on = hitRow and hitRow.twoActive },
                { n = 4, text = def.desc4 or "", on = hitRow and hitRow.fourActive },
                { n = 6, text = def.desc6 or "", on = hitRow and hitRow.sixActive },
            }
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            for i = 1, 3 do
                local ln = lines[i]
                local ly = by + 90 + (i - 1) * 90
                local r, g, b = 0x9A, 0x90, 0x80
                if ln.on then r, g, b = 0xF4, 0xED, 0xE0 end
                nvgFontSize(vg, 26)
                nvgFillColor(vg, nvgRGBA(r, g, b, 255))
                local tag = ln.n .. "件" .. (ln.on and " 已激活" or "")
                nvgText(vg, bx + 40, ly, tag, nil)
                nvgFontSize(vg, 24)
                nvgFillColor(vg, nvgRGBA(r, g, b, 230))
                nvgText(vg, bx + 40, ly + 34, ln.text or "", nil)
            end
            nvgFontSize(vg, 20)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0xC8, 0xC0, 0xB0, 180))
            nvgText(vg, DESIGN_W * 0.5, by + boxH - 28, "点击空白关闭", nil)
        end
    end
    drawDragGhost(vg)
end

local function slotAccepts(equip, slot)
    if not equip or not slot then return false end
    if equip.slot == slot then return true end
    return slot == "offhand" and equip.slot == "weapon" and equip.grip == "onehand"
end

function drawDragGhost(vg)
    if not panelState.itemDragging or not panelState.dragItem then return end
    local equip = panelState.dragItem.equip
    local x = panelState.dragX or panelState.dragStartX or 0
    local y = panelState.dragY or panelState.dragStartY or 0
    local DrawMod = require("ui.character.CharacterDetailDraw")
    local over = nil
    for _, s in ipairs(DrawMod.DT_SLOTS) do
        if hitTest(x, y, s.cx, s.cy, DrawMod.DT_SLOT_SIZE, DrawMod.DT_SLOT_SIZE) then
            over = s
            break
        end
    end
    if over then
        local ok = panelState.dragItem.canWear and slotAccepts(equip, over.slot)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, over.cx - 88, over.cy - 88, 176, 176, 20)
        nvgStrokeWidth(vg, 6)
        if ok then
            nvgStrokeColor(vg, nvgRGBA(255, 214, 102, 230))
        else
            nvgStrokeColor(vg, nvgRGBA(180, 70, 70, 220))
        end
        nvgStroke(vg)
    end
    local icon = equip and ImageCache.getEquipIcon(equip.templateId) or -1
    if icon and icon >= 0 then
        DarkIcon.drawQualityBg(vg, equip.quality or 1, x, y, 120, 120, 0.92)
        DarkIcon.drawIconDark(vg, icon, x, y, 104, 104, 0.92)
    end
end

--- 鼠标悬停格子时打开装备详情；离开未钉住的详情就关掉
function M.handleHover(dx, dy, heroId)
    if panelState.itemDragging then return end
    local item = nil
    if dy >= CLIP_TOP and dy <= CLIP_TOP + CLIP_HEIGHT
        and dx >= GRID_MARGIN_LEFT and dx <= DESIGN_W - GRID_MARGIN_LEFT then
        item = findItemAt(dx, dy)
    end
    local EquipmentDetail = require("ui.character.EquipmentDetail")
    if not item then return end
    local seqStr = tostring(item.seq)
    local _, cx, cy = findItemAt(dx, dy)
    if panelState.hoverSeq == seqStr then
        if EquipmentDetail.setAnchor then EquipmentDetail.setAnchor(cx, cy) end
        return
    end
    panelState.hoverSeq = seqStr
    panelState.hoverPinned = false
    EquipmentDetail.open(item.seq, panelState.slot, heroId, true, "character", cx, cy)
    print("[EquipPanel] 悬停详情 seq=" .. seqStr .. " at " .. tostring(cx) .. "," .. tostring(cy))
end

--- 处理输入（单击详情 / 双击穿戴）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@param heroId number
---@param detailState table
---@return boolean
function M.handleInput(dx, dy, heroId, detailState)
    -- 套装图鉴打开时优先关闭/吞掉点击
    if panelState.setCodexId then
        panelState.setCodexId = nil
        return true
    end
    -- 点套名打开图鉴
    for i = 1, #(panelState.setHits or {}) do
        local h = panelState.setHits[i]
        if dx >= h.x and dx <= h.x + h.w and dy >= h.y and dy <= h.y + h.h then
            panelState.setCodexId = h.setId
            return true
        end
    end
    -- 仅处理格子区域内的点击
    if dy < CLIP_TOP or dy > CLIP_TOP + CLIP_HEIGHT then
        return false
    end
    if dx < GRID_MARGIN_LEFT or dx > DESIGN_W - GRID_MARGIN_LEFT then
        return false
    end

    local item = findItemAt(dx, dy)
    if not item then
        local EquipmentDetail = require("ui.character.EquipmentDetail")
        if EquipmentDetail.isCompactCorner and EquipmentDetail.isCompactCorner() then
            EquipmentDetail.close()
        end
        return true
    end

    local now = time.elapsedTime
    local seqStr = tostring(item.seq)
    local isDouble = panelState.lastClickSeq == seqStr
        and (now - (panelState.lastClickTime or 0)) <= DOUBLE_CLICK_SEC
    panelState.lastClickSeq = seqStr
    panelState.lastClickTime = now

    if isDouble then
        equipItemNow(item, heroId, panelState.slot)
        local EquipmentDetail = require("ui.character.EquipmentDetail")
        if EquipmentDetail.isOpen() then EquipmentDetail.close() end
        return true
    end

    -- 单击：右栏内侧小详情，朝向中栏战斗区（无阴影）
    local EquipmentDetail = require("ui.character.EquipmentDetail")
    panelState.hoverSeq = seqStr
    panelState.hoverPinned = true
    local _, cx, cy = findItemAt(dx, dy)
    EquipmentDetail.open(item.seq, panelState.slot, heroId, true, "character", cx, cy)
    print("[EquipPanel] 单击详情 seq=" .. seqStr)
    return true
end

--- 右键：格子上快速穿戴
---@param dx number
---@param dy number
---@param heroId number
---@return boolean
function M.handleRightClick(dx, dy, heroId)
    if panelState.setCodexId then
        panelState.setCodexId = nil
        return true
    end
    if dy < CLIP_TOP or dy > CLIP_TOP + CLIP_HEIGHT then return false end
    if dx < GRID_MARGIN_LEFT or dx > DESIGN_W - GRID_MARGIN_LEFT then return false end
    local item = findItemAt(dx, dy)
    if not item then return false end
    equipItemNow(item, heroId, panelState.slot)
    local EquipmentDetail = require("ui.character.EquipmentDetail")
    if EquipmentDetail.isOpen() then EquipmentDetail.close() end
    return true
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

function M.beginPointer(dx, dy)
    panelState.dragItem = findItemAt(dx, dy)
    panelState.dragStartX = dx
    panelState.dragStartY = dy
    panelState.itemDragging = false
    panelState.dragging = true
    panelState.dragLastY = dy
    panelState.scrollVel = 0
end

function M.onPointerMove(dx, dy)
    panelState.dragX = dx
    panelState.dragY = dy
    if panelState.dragItem and not panelState.itemDragging then
        local dist = math.abs(dx - (panelState.dragStartX or dx)) + math.abs(dy - (panelState.dragStartY or dy))
        if dist >= ITEM_DRAG_PX then
            panelState.itemDragging = true
            panelState.dragging = false
            panelState.scrollVel = 0
            print("[EquipPanel] 开始拖装备 seq=" .. tostring(panelState.dragItem.seq))
        end
    end
    return panelState.itemDragging
end

function M.isItemDragging()
    return panelState.itemDragging == true
end

function M.getDragItem()
    return panelState.dragItem
end

function M.equipDragged(heroId, slot)
    local item = panelState.dragItem
    panelState.itemDragging = false
    panelState.dragItem = nil
    if not item then return false end
    local target = slot or panelState.slot
    if item.equip and not slotAccepts(item.equip, target) then
        local Toast = require("core.UiToast")
        Toast.show(require("core.I18n").t("cannot_wear"))
        print("[EquipPanel] 拖到不匹配槽位 slot=" .. tostring(target))
        return false
    end
    print("[EquipPanel] 拖放穿戴 seq=" .. tostring(item.seq) .. " slot=" .. tostring(target))
    return equipItemNow(item, heroId, target)
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
    panelState.itemDragging = false
    panelState.dragItem = nil
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
