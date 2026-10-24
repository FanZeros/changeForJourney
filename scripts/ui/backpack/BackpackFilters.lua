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
local ClassConfig = require("config.ClassConfig")
local HeroConfig = require("config.HeroConfig")
local EquipmentWearability = require("ui.character.detail.EquipmentWearability")
local HeroFrame = require("ui.widget.HeroFrame")
local UI = require("urhox-libs/UI")
local Surface = require("ui.widget.DesignWidgetSurface")
local M = {}

local CLASS_IDS = { "seal", "spoil", "rift", "echo", "mask", "debt" }
local WHITE = { 244, 237, 224, 255 }

local SORTS = {
    { value = "default", label = "默认排序" },
    { value = "power", label = "战力" },
    { value = "quality", label = "稀有度" },
    { value = "level", label = "等级" },
    { value = "ascend", label = "升阶等级" },
}

-- 魔化属性仅退出可选菜单，不改词条配置、装备数据或生效计算。
local CORRUPT_SORT_KEYS = {}
for _, affix in ipairs(AffixConfig.CORRUPT_AFFIXES) do CORRUPT_SORT_KEYS[affix.key] = true end

function M.bind(deps)
    local filters, GRID = deps.filters, deps.GRID
    -- 两个宿主均使用运行时状态；接入旧选择时只回退排序键，保留其他筛选和方向。
    if CORRUPT_SORT_KEYS[filters.sortKey] then filters.sortKey = nil end
    local menu = { key = nil, options = {}, scroll = 0, x = 0, y = 0, w = 0, h = 0,
        dragging = false, dragY = 0, dragScroll = 0, moved = false }
    local api = {}
    ---@type table<string, {root: Panel, text: Label}>
    local classViews = {}
    function api.init(_vg)
        if deps.enableClassFilter then Surface.init() end
    end
    local function currentHeroId()
        return deps.getHeroId and deps.getHeroId() or nil
    end
    local function currentClassId()
        local heroId = currentHeroId()
        local hero = heroId and HeroConfig.get(tonumber(heroId))
        return hero and ClassConfig.normalize(hero.classId) or nil
    end
    local function classColor(classId)
        return classId ~= nil and classId == currentClassId() and HeroFrame.GOLD_HI or WHITE
    end
    local function classCaption(vg, text, classId, x, y, width, height, viewKey)
        local view = classViews[viewKey]
        if not view then
            local textLabel = UI.Label { text = "", fontSize = 22.5, minFontSize = 12,
                fontFamily = "sans", fontWeight = "normal", verticalAlign = "middle",
                textAlign = "center", width = "100%", height = "100%", flexShrink = 1 }
            view = { text = textLabel, root = UI.Panel { width = width - 80, height = height,
                pointerEvents = "none", children = { textLabel } } }
            classViews[viewKey] = view
        end
        view.root:SetWidth(width - 80)
        view.root:SetHeight(height)
        view.text:SetText(I18n.lookup(text))
        view.text:SetFontColor(classColor(classId))
        nvgSave(vg)
        nvgTranslate(vg, x + 62, y - height * 0.5)
        Surface.draw(view.root, vg, width - 80, height)
        nvgRestore(vg)
        local images = HeroFrame.getImages()
        local index = classId and HeroFrame.CLASS_ICON_MAP[classId]
        local icon = images.vg == vg and index and images.classIcons[index] or -1
        if icon and icon >= 0 then
            DrawUtil.drawImageCentered(vg, icon, x + 34, y, 44, 44, 1)
        else
            -- 「全部」或资源未就绪用同尺寸菱形；不新建图片/字体、不抢输入。
            nvgBeginPath(vg)
            nvgMoveTo(vg, x + 34, y - 14)
            nvgLineTo(vg, x + 48, y)
            nvgLineTo(vg, x + 34, y + 14)
            nvgLineTo(vg, x + 20, y)
            nvgClosePath(vg)
            nvgStrokeWidth(vg, 2)
            nvgStrokeColor(vg, nvgRGBA(212, 175, 90, 255))
            nvgStroke(vg)
        end
    end
    local function caption(value, width, vg, x, y, color)
        local text = I18n.lookup(value)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 30)
        local measured = I18n.displayBounds(vg, 0, 0, text)
        local size = math.min(30, 30 * width / math.max(1, measured))
        color = color or WHITE
        DrawUtil.drawTextStroke(vg, x, y, text, size,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, color[1], color[2], color[3], 2)
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
        filters.typeFilter, filters.classFilter, filters.sortKey, filters.sortAscending = nil, nil, nil, false
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
        -- 显式按魔化 key 排除，也防止模板/副属性来源重新将它们带回菜单。
        for key in pairs(CORRUPT_SORT_KEYS) do keys[key] = nil end
        local attrs = {}
        for key in pairs(keys) do
            local meta = AD.META[key]
            attrs[#attrs + 1] = { value = key, label = meta and meta.name or key }
        end
        table.sort(attrs, function(a, b) return a.label < b.label end)
        for _, attr in ipairs(attrs) do options[#options + 1] = attr end
        return options
    end
    local function classOptions()
        local options = { { value = "all", label = "全部职业" } }
        for _, classId in ipairs(CLASS_IDS) do
            options[#options + 1] = { value = classId, label = ClassConfig.get(classId).name }
        end
        return options
    end
    -- 同一类型可能有多个模板；只要当前部位中一种可穿，该类型就作黄色提示。
    -- 每次绘制重新读当前详情角色和主副手，换人/转职/装备回包不借旧菜单快照。
    local function highlightedTypes()
        local result = {}
        local heroId = currentHeroId()
        if not heroId or not deps.PlayerStore then return result end
        local checker = EquipmentWearability.createTypeChecker(deps.PlayerStore.Get("equipment"),
            heroId, deps.PlayerStore.Get("heroes"))
        local slot = deps.getSlot()
        for _, tpl in pairs(EquipmentConfig.ITEMS) do
            if checker(tpl, slot) then result[tpl.type] = true end
        end
        return result
    end
    local function selectedValue(key)
        if key == "slot" then return deps.getSlot() or "all" end
        if key == "type" then return filters.typeFilter or "all" end
        if key == "class" then return ClassConfig.normalize(filters.classFilter) or "all" end
        return filters.sortKey or "default"
    end
    function api.getOptions(key)
        if key == "slot" then return slotOptions() end
        if key == "type" then return typeOptions() end
        if key == "class" and deps.enableClassFilter then return classOptions() end
        return sortOptions()
    end
    local function controls()
        local y1, y2 = GRID.FIRST_ROW_TOP - (deps.enableClassFilter and 316 or 226), GRID.FIRST_ROW_TOP - 136
        local result = {
            { key = "slot", x = 80, y = y1, w = 430, h = 70 },
            { key = "type", x = 530, y = y1, w = 470, h = 70 },
            { key = "sort", x = 80, y = y2, w = 430, h = 70 },
            { key = "order", x = 530, y = y2, w = 150, h = 70 },
            { key = "icons", x = 700, y = y2, w = 160, h = 70 },
            { key = "reset", x = 880, y = y2, w = 120, h = 70 },
        }
        if deps.enableClassFilter then
            result[#result + 1] = { key = "class", x = 80, y = GRID.FIRST_ROW_TOP - 226, w = 920, h = 70 }
        end
        return result
    end
    local function label(key)
        if key == "slot" then return "部位 · " .. (EquipmentConfig.SLOT_NAME[deps.getSlot()] or "全部") end
        if key == "type" then return "类型 · " .. (filters.typeFilter or "全部") end
        if key == "class" then
            local class = ClassConfig.get(filters.classFilter)
            return I18n.lookup("适用职业") .. " · " .. I18n.lookup(class and class.name or "全部")
        end
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
        local selected = selectedValue(control.key)
        for index, option in ipairs(menu.options) do
            if option.value == selected then menu.scroll = math.max(0, math.min(index - 1, #menu.options - 8)); break end
        end
    end
    -- 遗匣与优选入口共享底行，由宿主指定说明位置；其他页面保持原布局。
    function api.drawSortHint(vg, x, y, width, size)
        local hint = I18n.lookup("属性排序合计固定与随机词条；无该属性的装备置后")
        size = size or 25
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, size)
        if width then
            local measured = nvgTextBounds(vg, 0, 0, hint)
            nvgFontSize(vg, math.min(size, size * width / math.max(1, measured)))
        end
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
        nvgText(vg, x, y, hint, nil)
    end
    function api.draw(vg)
        local types = filters.typeFilter and highlightedTypes() or {}
        for _, control in ipairs(controls()) do
            DarkIcon.drawNine(vg, "btn", control.x, control.y - control.h * 0.5, control.w, control.h,
                { accent = menu.key == control.key and "green" or "gold" })
            if control.key == "class" then
                classCaption(vg, label("class"), ClassConfig.normalize(filters.classFilter),
                    control.x, control.y, control.w, control.h, "trigger")
            else
                local color = control.key == "type" and types[filters.typeFilter] and HeroFrame.GOLD_HI or WHITE
                caption(label(control.key), control.w - 30, vg, control.x + control.w * 0.5, control.y, color)
            end
        end
        if deps.sortHint ~= false then
            api.drawSortHint(vg, 80, GRID.FIRST_ROW_TOP - 66)
        end
    end
    function api.drawOverlay(vg)
        if not api.isOpen() then return end
        nvgSave(vg)
        DarkIcon.drawNine(vg, "plain", menu.x, menu.y, menu.w, menu.h, { accent = "gold" })
        nvgIntersectScissor(vg, menu.x + 5, menu.y + 5, menu.w - 10, menu.h - 10)
        local selected = selectedValue(menu.key)
        local types = menu.key == "type" and highlightedTypes() or {}
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
                if menu.key == "class" then
                    local classId = option.value ~= "all" and option.value or nil
                    classCaption(vg, option.label, classId, menu.x + 8, y, menu.w - 16, 58, option.value)
                else
                    caption(option.label, menu.w - 42, vg, menu.x + menu.w * 0.5, y,
                        types[option.value] and HeroFrame.GOLD_HI or WHITE)
                end
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
                    elseif menu.key == "class" then
                        filters.classFilter = option.value ~= "all" and option.value or nil
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
        filters = filters, GRID = GRID, enableClassFilter = true, PlayerStore = PlayerStore,
        getHeroId = function()
            local detail = require("ui.character.detail.CharacterDetail")
            return detail.getHeroId and detail.getHeroId() or nil
        end,
        getSlot = function() return equipLink.getEquipmentSlotFilter() end,
        setSlot = function(slot)
            local detail = require("ui.character.detail.CharacterDetail")
            if detail.setEquipmentSlot and detail.setEquipmentSlot(slot) then return end
            local _, heroId = equipLink.getEquipmentSlotFilter()
            equipLink.setEquipmentSlotFilter(slot, heroId)
        end,
        isDualWield = function()
            local detail = require("ui.character.detail.CharacterDetail")
            local _, filterHeroId = equipLink.getEquipmentSlotFilter()
            local heroId = detail.getHeroId and detail.getHeroId() or filterHeroId
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
