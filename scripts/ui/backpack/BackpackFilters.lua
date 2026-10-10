-- 仓库筛选工具条：部位、装备子类型和属性升降序，沿用宿主设计坐标。
-- 筛选只改显示状态，不修改库存、职业限制或穿戴规则。
local EquipmentConfig = require("config.EquipmentConfig")
local AffixConfig = require("config.AffixConfig")
local EquipmentSecondaryStats = require("systems.EquipmentSecondaryStats")
local AD = require("systems.AttributeDef")
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local I18n = require("core.I18n")
local SettingsPanel = require("ui.hud.popup.SettingsPanel")
local M = {}

local SORTS = {
    { value = "default", label = "默认排序" },
    { value = "power", label = "战力" },
    { value = "quality", label = "稀有度" },
    { value = "level", label = "等级" },
    { value = "ascend", label = "升阶等级" },
}

function M.bind(deps)
    local filters, GRID = deps.filters, deps.GRID
    local menu = { key = nil, options = {}, scroll = 0, x = 0, y = 0, w = 0, h = 0,
        dragging = false, dragY = 0, dragScroll = 0, moved = false }
    local api = {}
    local function caption(value, width, vg, x, y)
        local text = I18n.lookup(value)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        local measured = I18n.displayBounds(vg, 0, 0, text)
        local size = math.min(30, 30 * width / math.max(1, measured))
        DrawUtil.drawTextStroke(vg, x, y, text, size,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 244, 237, 224, 2)
    end
    local function changed()
        deps.onChange()
    end
    function api.close()
        menu.key, menu.options, menu.scroll = nil, {}, 0
        menu.dragging, menu.moved = false, false
    end
    function api.isOpen() return menu.key ~= nil end
    function api.getState() return filters end
    function api.reset()
        filters.typeFilter, filters.sortKey, filters.sortAscending = nil, nil, false
        deps.setSlot(nil)
        if deps.clearQualitySets then deps.clearQualitySets() end
        api.close()
        changed()
    end
    local function slotOptions()
        local options = { { value = "all", label = "全部部位" } }
        for _, slot in ipairs(EquipmentConfig.SLOTS) do
            options[#options + 1] = { value = slot, label = EquipmentConfig.SLOT_NAME[slot] }
        end
        return options
    end
    local function typeOptions()
        local options, types = { { value = "all", label = "全部类型" } }, {}
        local slot = deps.getSlot()
        local allowWeapon = slot == "offhand" and deps.isDualWield and deps.isDualWield()
        for _, tpl in pairs(EquipmentConfig.ITEMS) do
            if not slot or tpl.slot == slot or (allowWeapon and tpl.slot == "weapon" and tpl.grip == "onehand") then
                if tpl.type and not types[tpl.type] then
                    types[tpl.type] = true
                    options[#options + 1] = { value = tpl.type, label = tpl.type }
                end
            end
        end
        table.sort(options, function(a, b)
            if a.value == "all" then return b.value ~= "all" end
            if b.value == "all" then return false end
            return a.label < b.label
        end)
        return options
    end
    local function sortOptions()
        local options, keys = {}, {}
        for _, option in ipairs(SORTS) do options[#options + 1] = option end
        for _, tpl in pairs(EquipmentConfig.ITEMS) do
            for _, stat in ipairs(tpl.stats or {}) do keys[stat[1]] = true end
        end
        for _, key in ipairs(EquipmentSecondaryStats.getAttributeKeys()) do keys[key] = true end
        for _, affix in ipairs(AffixConfig.AFFIXES) do keys[affix.key] = true end
        for _, affix in ipairs(AffixConfig.CORRUPT_AFFIXES) do keys[affix.key] = true end
        local attrs = {}
        for key in pairs(keys) do
            local meta = AD.META[key]
            attrs[#attrs + 1] = { value = key, label = meta and meta.name or key }
        end
        table.sort(attrs, function(a, b) return a.label < b.label end)
        for _, attr in ipairs(attrs) do options[#options + 1] = attr end
        return options
    end
    function api.getOptions(key)
        if key == "slot" then return slotOptions() end
        if key == "type" then return typeOptions() end
        return sortOptions()
    end
    local function controls()
        local y1, y2 = GRID.FIRST_ROW_TOP - 226, GRID.FIRST_ROW_TOP - 136
        return {
            { key = "slot", x = 80, y = y1, w = 430, h = 70 },
            { key = "type", x = 530, y = y1, w = 470, h = 70 },
            { key = "sort", x = 80, y = y2, w = 430, h = 70 },
            { key = "order", x = 530, y = y2, w = 150, h = 70 },
            { key = "icons", x = 700, y = y2, w = 160, h = 70 },
            { key = "reset", x = 880, y = y2, w = 120, h = 70 },
        }
    end
    local function label(key)
        if key == "slot" then return "部位 · " .. (EquipmentConfig.SLOT_NAME[deps.getSlot()] or "全部") end
        if key == "type" then return "类型 · " .. (filters.typeFilter or "全部") end
        if key == "sort" then
            local sort = filters.sortKey or "default"
            for _, option in ipairs(SORTS) do
                if option.value == sort then return "排序 · " .. option.label end
            end
            return "属性 · " .. ((AD.META[sort] and AD.META[sort].name) or sort)
        end
        if key == "order" then return filters.sortAscending and "升序 ↑" or "降序 ↓" end
        if key == "icons" then return SettingsPanel.isSetIconsEnabled() and "图标 ✓" or "图标 ×" end
        return "重置"
    end
    local function openMenu(control)
        if menu.key == control.key then api.close(); return end
        menu.key, menu.options = control.key, api.getOptions(control.key)
        menu.scroll, menu.x, menu.w = 0, control.x, control.w
        menu.h = math.min(8, #menu.options) * 62 + 12
        menu.y = math.min(control.y + control.h * 0.5 + 8, GRID.CLIP_BOTTOM - menu.h)
        local selected = control.key == "slot" and (deps.getSlot() or "all")
            or control.key == "type" and (filters.typeFilter or "all") or (filters.sortKey or "default")
        for index, option in ipairs(menu.options) do
            if option.value == selected then menu.scroll = math.max(0, math.min(index - 1, #menu.options - 8)); break end
        end
    end
    function api.draw(vg)
        for _, control in ipairs(controls()) do
            DarkIcon.drawNine(vg, "btn", control.x, control.y - control.h * 0.5, control.w, control.h,
                { accent = menu.key == control.key and "green" or "gold" })
            caption(label(control.key), control.w - 30, vg, control.x + control.w * 0.5, control.y)
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 25)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
        nvgText(vg, 80, GRID.FIRST_ROW_TOP - 66, "属性排序合计固定与随机词条；无该属性的装备置后", nil)
    end
    function api.drawOverlay(vg)
        if not api.isOpen() then return end
        nvgSave(vg)
        DarkIcon.drawNine(vg, "plain", menu.x, menu.y, menu.w, menu.h, { accent = "gold" })
        nvgIntersectScissor(vg, menu.x + 5, menu.y + 5, menu.w - 10, menu.h - 10)
        local selected = menu.key == "slot" and (deps.getSlot() or "all")
            or menu.key == "type" and (filters.typeFilter or "all") or (filters.sortKey or "default")
        for row = 1, math.min(8, #menu.options) do
            local option = menu.options[row + menu.scroll]
            if option then
                local y = menu.y + 6 + (row - 0.5) * 62
                if option.value == selected then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, menu.x + 8, y - 29, menu.w - 16, 58, 6)
                    nvgFillColor(vg, nvgRGBA(72, 65, 42, 255))
                    nvgFill(vg)
                end
                caption(option.label, menu.w - 42, vg, menu.x + menu.w * 0.5, y)
            end
        end
        if #menu.options > 8 then
            local trackH = menu.h - 20
            local thumbH = trackH * 8 / #menu.options
            nvgBeginPath(vg)
            nvgRoundedRect(vg, menu.x + menu.w - 10,
                menu.y + 10 + (trackH - thumbH) * menu.scroll / (#menu.options - 8), 4, thumbH, 2)
            nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
            nvgFill(vg)
        end
        nvgRestore(vg)
    end
    function api.handleInput(dx, dy)
        if api.isOpen() then
            if menu.moved then menu.moved = false; return true end
            if DrawUtil.hitTest(dx, dy, menu.x + menu.w * 0.5, menu.y + menu.h * 0.5, menu.w, menu.h) then
                local row = math.floor((dy - menu.y - 6) / 62) + 1
                local option = row >= 1 and row <= 8 and menu.options[row + menu.scroll] or nil
                if option then
                    if menu.key == "slot" then
                        filters.typeFilter = nil
                        deps.setSlot(option.value ~= "all" and option.value or nil)
                    elseif menu.key == "type" then
                        filters.typeFilter = option.value ~= "all" and option.value or nil
                    else
                        filters.sortKey = option.value ~= "default" and option.value or nil
                    end
                    print("[BackpackFilters] " .. menu.key .. "=" .. option.value)
                    api.close()
                    changed()
                end
                return true
            end
            api.close()
            return true
        end
        for _, control in ipairs(controls()) do
            if DrawUtil.hitTest(dx, dy, control.x + control.w * 0.5, control.y, control.w, control.h) then
                if control.key == "order" then
                    filters.sortAscending = not filters.sortAscending
                    changed()
                elseif control.key == "icons" then
                    SettingsPanel.setSetIconsEnabled(not SettingsPanel.isSetIconsEnabled())
                elseif control.key == "reset" then api.reset()
                else openMenu(control) end
                return true
            end
        end
        return false
    end
    function api.handleScroll(wheel)
        if not api.isOpen() then return false end
        menu.scroll = math.max(0, math.min(math.max(0, #menu.options - 8), menu.scroll - math.floor(wheel)))
        return true
    end
    function api.handleDragBegin(dx, dy)
        if not api.isOpen() then return false end
        menu.dragging = DrawUtil.hitTest(dx, dy, menu.x + menu.w * 0.5,
            menu.y + menu.h * 0.5, menu.w, menu.h)
        menu.dragY, menu.dragScroll, menu.moved = dy, menu.scroll, false
        return true
    end
    function api.handleDragMove(_dx, dy)
        if not api.isOpen() then return false end
        if menu.dragging then
            local delta = menu.dragY - dy
            if math.abs(delta) > 12 then menu.moved = true end
            menu.scroll = math.max(0, math.min(math.max(0, #menu.options - 8),
                menu.dragScroll + math.floor(delta / 62 + 0.5)))
        end
        return true
    end
    function api.handleDragEnd(_dx, _dy)
        if not api.isOpen() then return false end
        menu.dragging = false
        return true
    end
    return api
end
-- 宿主仅提供状态与列表联动；部位上下文、输入模态隔离集中在筛选模块。
function M.bindWarehouse(filters, GRID, state, equipLink, PlayerStore)
    return M.bind({
        filters = filters, GRID = GRID,
        getSlot = function() return equipLink.getEquipmentSlotFilter() end,
        setSlot = function(slot)
            local detail = require("ui.character.detail.CharacterDetail")
            if detail.setEquipmentSlot and detail.setEquipmentSlot(slot) then return end
            local _, heroId = equipLink.getEquipmentSlotFilter()
            equipLink.setEquipmentSlotFilter(slot, heroId)
        end,
        isDualWield = function()
            local _, heroId = equipLink.getEquipmentSlotFilter()
            local heroes = PlayerStore.Get("heroes")
            local roster = heroes and heroes.roster
            local hero = heroId and roster and (roster[heroId] or roster[tostring(heroId)])
            return require("config.AdvancementConfig").getDualWieldMode(hero and hero.advBranch) ~= nil
        end,
        clearQualitySets = function() filters.qualitySet, filters.setFilter = {}, {} end,
        onChange = function()
            state.scrollY = 0
            equipLink.haltScroll()
            equipLink.clearCandidate(true)
        end,
    })
end

function M.attachInput(Panel, state, filterBar, equipLink)
    for _, name in ipairs({ "handleDragBegin", "handleDragMove", "handleDragEnd", "handleScroll" }) do
        Panel[name] = function(...)
            if state.open and state.tab == "equip" and filterBar.isOpen() then
                equipLink.haltScroll()
                return filterBar[name](...)
            end
            return equipLink[name](...)
        end
    end
end
return M
