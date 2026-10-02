-- ============================================================================
-- CharacterDetailEquip - 配装下部属性预览面板（纯 NanoVG / 暗金）
-- 不再显示装备网格，不再创建网格装备热区/hover/快速穿装/拖拽 ghost。
-- 上部六槽由 CharacterDetailDraw 管理；这里只保留 peekSlotEquipAt 协作拖拽。
-- ============================================================================

local PlayerStore = require("core.PlayerStore")
local ClientDispatcher = require("runtime.ClientDispatcher")
local HeroConfig = require("config.HeroConfig")
local EquipmentSystem = require("systems.EquipmentSystem")
local EquipmentSetSystem = require("systems.EquipmentSetSystem")
local DetailAttrs = require("ui.character.detail.CharacterDetailAttrs")
local Stats = require("ui.character.detail.CharacterEquipStats")

local M = {}
local CACHE_SECONDS = 0.2
local SCROLL_FRICTION = 0.90
local SCROLL_MIN_VEL = 0.5

-- 独立滚动区：上左属性、下方完整套装。绝不复用旧侧栏命中表。
local panelState = {
    heroId = nil,
    slot = nil,
    dirty = true,
    cacheKey = nil,
    cacheTime = -1,
    cacheSignature = nil,
    data = nil,
    scrollTarget = nil,
    dragging = false,
    dragLastY = 0,
    scroll = {
        attrs = { y = 0, max = 0, velocity = 0 },
        sets = { y = 0, max = 0, velocity = 0 },
    },
    tooltip = nil,
    hoverKey = nil,
    hoverSince = 0,
    hoverPinned = false,
    attrHits = {},
}

local function now()
    return time and time.elapsedTime or 0
end

local function scrollAt(dx, dy)
    if Stats.contains(Stats.LAYOUT.attrs, dx, dy) then return "attrs" end
    if Stats.contains(Stats.LAYOUT.sets, dx, dy) then return "sets" end
    return nil
end

local function clampScroll(key)
    local state = panelState.scroll[key]
    if not state then return end
    state.y = math.max(0, math.min(state.max, state.y))
end

local function clearTip()
    panelState.tooltip = nil
    panelState.hoverKey = nil
    panelState.hoverSince = 0
    panelState.hoverPinned = false
end

local function getSelection()
    local detail = require("ui.character.equip.EquipmentDetail")
    -- 主模块升级前安全退化为 current；不会从私有 state 猜候选。
    if type(detail.getSelection) ~= "function" then return nil end
    local selected = detail.getSelection()
    if not selected or selected.seq == nil then return nil end
    local owner = selected.owner
    if owner ~= "backpack" and owner ~= "character" and owner ~= "bag" then return nil end
    return selected
end

local function currentFallback(heroId, level)
    -- 预览模块尚未接入时，只走原属性收集展示 current，不自行算试穿。
    local cfg = HeroConfig.get(heroId)
    local current = cfg and DetailAttrs.collectAttributes(heroId, cfg, level)
        or { left = {}, right = {}, stats = {} }
    local rows = {}
    for _, row in ipairs(current.left or {}) do rows[#rows + 1] = row end
    for _, row in ipairs(current.right or {}) do rows[#rows + 1] = row end
    local order = DetailAttrs.displayOrderIndex()
    local indices = {}
    for i, row in ipairs(rows) do indices[row] = i end
    table.sort(rows, function(a, b)
        local ai, bi = order[a.key] or 9999, order[b.key] or 9999
        if ai ~= bi then return ai < bi end
        return indices[a] < indices[b]
    end)
    local equipment = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    local counts = EquipmentSetSystem.countSets(equipment, heroId,
        EquipmentSystem.getFromInventory, EquipmentSystem.getHeroSlots)
    return {
        current = current, preview = nil, rows = rows,
        currentSets = EquipmentSetSystem.summarize(counts), previewSets = {}, candidate = nil,
    }
end

local function heroLevel(heroId)
    local heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes")
    local roster = heroes and heroes.roster
    local own = roster and (roster[heroId] or roster[tostring(heroId)])
    return own and own.level or 1
end

-- 0.2 秒只检查小型装备/养成签名：不深拷贝整背包、不定时重建英雄。
-- 已穿装备与候选原地升阶/洗练也能失效；无关背包条目变化不重算。
local function dataSignature(selection)
    local parts = {}
    local seen = {}
    local function append(value)
        if type(value) ~= "table" then
            parts[#parts + 1] = type(value) .. ":" .. tostring(value)
            return
        end
        if seen[value] then parts[#parts + 1] = "cycle"; return end
        seen[value] = true
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        parts[#parts + 1] = "{"
        for _, key in ipairs(keys) do append(key); append(value[key]) end
        parts[#parts + 1] = "}"
        seen[value] = nil
    end
    local heroes = ClientDispatcher.get("heroes") or PlayerStore.Get("heroes") or {}
    append(heroes.deployed)
    append(heroes.teams)
    for _, id in ipairs({ "1", "2", "3" }) do append(heroes["team" .. id]) end
    local roster = heroes.roster or {}
    local rosterKeys = {}
    for id in pairs(roster) do rosterKeys[#rosterKeys + 1] = id end
    table.sort(rosterKeys, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(rosterKeys) do
        local own = roster[id]
        append(id)
        if type(own) == "table" then
            append(own.level); append(own.advBranch); append(own.awakening); append(own.extraTalent)
        end
    end
    local equipment = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment") or {}
    append(equipment.equipped)
    local inventory = equipment.inventory or {}
    local seqs = {}
    for _, slots in pairs(equipment.equipped or {}) do
        if type(slots) == "table" then
            for _, seq in pairs(slots) do seqs[tostring(seq)] = true end
        end
    end
    if selection then seqs[tostring(selection.seq)] = true end
    local seqKeys = {}
    for seq in pairs(seqs) do seqKeys[#seqKeys + 1] = seq end
    table.sort(seqKeys)
    for _, seq in ipairs(seqKeys) do append(seq); append(inventory[seq] or inventory[tonumber(seq)]) end
    append(ClientDispatcher.get("artifacts") or PlayerStore.Get("artifacts"))
    return table.concat(parts, "\31")
end

local function refreshData(heroId, slot)
    local selection = getSelection()
    local level = heroLevel(heroId)
    -- nil 表示未筛选，直接交给预览 API 选择装备自然槽；不回退主武器。
    -- 显式 offhand 必须保留，允许武器作为副手候选由预览 API 校验。
    local key = table.concat({ tostring(heroId), tostring(level), tostring(slot),
        tostring(selection and selection.seq), tostring(selection and selection.slot),
        tostring(selection and selection.owner), tostring(selection and selection.heroId),
        tostring(selection and selection.pinned) }, "|")
    local elapsed = now()
    local signature = nil
    if not panelState.dirty and panelState.cacheKey == key then
        if elapsed >= panelState.cacheTime and elapsed - panelState.cacheTime < CACHE_SECONDS then
            return panelState.data
        end
        signature = dataSignature(selection)
        panelState.cacheTime = elapsed
        if signature == panelState.cacheSignature then return panelState.data end
    end
    local ok, preview = pcall(require, "ui.character.detail.EquipmentPreview")
    local result = nil
    local failure = nil
    if ok and type(preview.build) == "function" then
        -- 仅调用公共 API；不写 eqData、不发送穿戴动作、不复制预览公式。
        local built, value = pcall(preview.build, heroId, level, selection and selection.seq or nil, slot, {})
        if built then
            result = value
        else
            failure = tostring(value)
            print("[EquipPanel] 属性预览构建失败 hero=" .. tostring(heroId) .. " error=" .. failure)
        end
    elseif not ok then
        failure = tostring(preview)
        print("[EquipPanel] 属性预览模块不可用 error=" .. failure)
    end
    if not result or not result.current then
        result = currentFallback(heroId, level)
        if selection or failure then result.error = "属性预览暂不可用，当前装备未改变" end
    end
    panelState.data = result
    panelState.cacheKey = key
    panelState.cacheTime = elapsed
    panelState.cacheSignature = signature or dataSignature(selection)
    panelState.dirty = false
    return result
end

local function rowAt(dx, dy)
    if not Stats.contains(Stats.LAYOUT.attrs, dx, dy) then return nil end
    return Stats.rowAt(panelState.attrHits, dx, dy)
end

local function makeTip(row, dx, dy)
    local AD = require("systems.AttributeDef")
    local meta = AD.META[row.key]
    return {
        x = dx, y = dy, key = row.key,
        name = row.name or (meta and meta.name) or tostring(row.key),
        desc = row.desc or (meta and meta.desc) or "该属性为当前角色的最终面板数值。",
    }
end

--- 绘制配装下部。六槽与一键按钮继续由上层绘制。
function M.draw(vg, heroId, detailState)
    local slot = detailState and detailState.equipSlot or nil
    if panelState.heroId ~= heroId then M.reset(heroId, slot) end
    if panelState.slot ~= slot then M.onSlotChanged(slot, heroId) end
    local data = refreshData(heroId, slot)
    for _, key in ipairs({ "attrs", "sets" }) do
        local state = panelState.scroll[key]
        if not panelState.dragging and math.abs(state.velocity) > SCROLL_MIN_VEL then
            state.y = state.y + state.velocity
            state.velocity = state.velocity * SCROLL_FRICTION
            clampScroll(key)
        elseif not panelState.dragging then
            state.velocity = 0
        end
    end
    local current = data.current or {}
    local preview = data.preview
    local sets = Stats.unionSets(data.currentSets, preview and data.previewSets or nil)
    Stats.drawHeader(vg, data.candidate, data.error)
    local maxAttrs, hits = Stats.drawRows(vg, data.rows or {}, panelState.scroll.attrs.y)
    panelState.scroll.attrs.max = maxAttrs
    panelState.attrHits = hits
    panelState.scroll.sets.max = Stats.drawSets(vg, sets, panelState.scroll.sets.y, preview ~= nil)
    clampScroll("attrs")
    clampScroll("sets")
    Stats.drawRadar(vg, current.stats, preview and preview.stats or nil)
end

function M.onSlotChanged(slot, heroId)
    panelState.slot = slot
    panelState.heroId = heroId
    M.markDirty()
end

function M.markDirty()
    panelState.dirty = true
    panelState.cacheKey = nil
    clearTip()
end

--- clear/reset 都废弃候选缓存和属性说明，不遗留上一位角色热区。
function M.clear()
    panelState.data = nil
    panelState.cacheKey = nil
    panelState.cacheTime = -1
    panelState.cacheSignature = nil
    panelState.dirty = true
    panelState.attrHits = {}
    panelState.scrollTarget = nil
    panelState.dragging = false
    panelState.dragLastY = 0
    panelState.scroll.attrs = { y = 0, max = 0, velocity = 0 }
    panelState.scroll.sets = { y = 0, max = 0, velocity = 0 }
    clearTip()
end

function M.reset(heroId, slot)
    M.clear()
    panelState.heroId = heroId
    panelState.slot = slot
end

--- 只标识可见比较内容，供外层保留候选详情。上部六槽与页签不属于它。
function M.containsComparisonPoint(dx, dy)
    return scrollAt(dx, dy) ~= nil or Stats.contains(Stats.LAYOUT.radar, dx, dy)
end

function M.handleInput(dx, dy, heroId, detailState)
    if not Stats.contains(Stats.LAYOUT.panel, dx, dy) then return false end
    local row = rowAt(dx, dy)
    if row then
        if panelState.tooltip and panelState.hoverPinned and panelState.tooltip.key == row.key then
            clearTip()
        else
            panelState.tooltip = makeTip(row, dx, dy)
            panelState.hoverPinned = true
        end
    else
        clearTip()
    end
    return true
end

--- 只管理下部属性说明，不再通过装备 grid 触发/关闭 EquipmentDetail。
function M.handleHover(dx, dy, heroId)
    if dx == nil or dy == nil or dx < 0 or dy < 0 then clearTip(); return false end
    if panelState.dragging or panelState.hoverPinned then return false end
    local row = rowAt(dx, dy)
    if not row then clearTip(); return false end
    local key = tostring(row.key)
    if key ~= panelState.hoverKey then
        panelState.hoverKey = key
        panelState.hoverSince = now()
        panelState.tooltip = nil
    elseif now() - panelState.hoverSince >= 0.3 then
        panelState.tooltip = makeTip(row, dx, dy)
    end
    return true
end

function M.handleRightClick(dx, dy, heroId)
    if not Stats.contains(Stats.LAYOUT.panel, dx, dy) then return false end
    clearTip()
    return false -- 没有装备右键动作，不能把旧网格区域当作穿装热区。
end

--- 外层保留旧函数名，但只为下部两块可滚动区域判定，不代表装备网格。
function M.isInGridArea(dy, dx)
    if dx ~= nil then return scrollAt(dx, dy) ~= nil end
    if dy == nil then return false end
    return (dy >= Stats.LAYOUT.attrs.y and dy <= Stats.LAYOUT.attrs.y + Stats.LAYOUT.attrs.h)
        or (dy >= Stats.LAYOUT.sets.y and dy <= Stats.LAYOUT.sets.y + Stats.LAYOUT.sets.h)
end

function M.beginPointer(dx, dy)
    panelState.scrollTarget = scrollAt(dx, dy)
    panelState.dragging = panelState.scrollTarget ~= nil
    panelState.dragLastY = dy
    if panelState.scrollTarget then
        panelState.scroll[panelState.scrollTarget].velocity = 0
        clearTip()
    end
    return panelState.dragging
end

function M.onPointerMove(dx, dy)
    return false -- 不创建 dragItem；外层继续调用 onDrag 滚动。
end

function M.onDrag(deltaY)
    local key = panelState.scrollTarget
    if not key then return end
    local state = panelState.scroll[key]
    state.y = state.y + (deltaY or 0)
    state.velocity = deltaY or 0
    clampScroll(key)
    clearTip()
end

function M.onDragStart(dy)
    panelState.dragging = panelState.scrollTarget ~= nil
    panelState.dragLastY = dy
end

function M.onDragEnd()
    panelState.dragging = false
end

function M.getDragLastY() return panelState.dragLastY or 0 end
function M.setDragLastY(y) panelState.dragLastY = y end
function M.isItemDragging() return false end
function M.getDragItem() return nil end
function M.equipDragged(heroId, slot) return false end
function M.peekItemAt(dx, dy) return nil end

-- 旧顶部左右栏已移除；这些兼容入口不保留任何隐藏 hits。
function M.beginSideDrag(dx, dy) return false end
function M.moveSideDrag(dy) end
function M.endSideDrag() end

--- 新入口便于上层在装备弹窗外优先给下部滚动，不改变旧入口签名。
function M.handleDragBegin(dx, dy) return M.beginPointer(dx, dy) end
function M.handleDragMove(dx, dy)
    if not panelState.dragging then return false end
    M.onDrag(panelState.dragLastY - dy)
    panelState.dragLastY = dy
    return true
end
function M.handleDragEnd(dx, dy)
    if not panelState.dragging then return false end
    M.onDragEnd()
    return true
end

--- 按鼠标所在的实际下部区域滚动；雷达只消费滚轮、不借用上次滚动目标。
function M.handleSideScroll(wheel, dx, dy)
    local key = scrollAt(dx, dy)
    panelState.scrollTarget = key
    if not key then
        return Stats.contains(Stats.LAYOUT.radar, dx, dy)
    end
    local state = panelState.scroll[key]
    state.y = state.y - (wheel or 0) * 60
    state.velocity = 0
    clampScroll(key)
    clearTip()
    return true
end

--- 兼容顶层浮层调用：原图鉴已无入口，现只画本面板自管的属性说明。
function M.drawSetCodex(vg)
    Stats.drawTooltip(vg, panelState.tooltip)
end

--- 保留上部六槽拖拽读取，不得查已删除的配装 grid。
function M.peekSlotEquipAt(dx, dy)
    local Draw = require("ui.character.detail.CharacterDetailDraw")
    local heroId = panelState.heroId
    if not heroId then return nil end
    for _, slot in ipairs(Draw.DT_SLOTS) do
        local half = Draw.DT_SLOT_SIZE * 0.5
        if dx >= slot.cx - half and dx <= slot.cx + half
            and dy >= slot.cy - half and dy <= slot.cy + half then
            local equipment = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
            local slots = EquipmentSystem.getHeroSlots(equipment, heroId)
            if not slots then return nil end
            local seq = slots[slot.slot]
            local equip = seq and EquipmentSystem.getFromInventory(equipment, seq) or nil
            if not equip and slot.slot == "offhand" then
                local weaponSeq = slots.weapon
                local weapon = weaponSeq and EquipmentSystem.getFromInventory(equipment, weaponSeq) or nil
                if weapon and weapon.grip == "twohand" then
                    equip, seq = weapon, weaponSeq
                end
            end
            if not equip or not seq then return nil end
            if not equip.slot or not equip.type then EquipmentSystem.hydrate(equip) end
            return {
                seq = seq, templateId = equip.templateId, quality = equip.quality or 1,
                slot = equip.slot, grip = equip.grip, equipType = equip.type,
            }
        end
    end
    return nil
end

return M
