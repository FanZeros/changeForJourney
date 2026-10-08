-- Mock 回归：仓库持有/部位筛选/不可穿灰显/锻炉交接，无需真实绘图或存档。
-- .cli/UrhoXRuntime tests/backpack_equip_link_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
local passes, failures = 0, 0
local function check(ok, label)
    if ok then passes = passes + 1; print("[PASS] " .. label)
    else failures = failures + 1; print("[FAIL] " .. label) end
end
local clock = { elapsedTime = 10 }
time = clock
local detailState = { open = false }
local Detail = {
    getOwner = function() return detailState.owner end,
    isOpen = function() return detailState.open end,
    isPinned = function() return detailState.pinned == true end,
    close = function() detailState.open, detailState.pinned = false, false end,
    dismissHover = function(owner)
        if owner == detailState.owner and not detailState.pinned then detailState.open = false end
    end,
    open = function(seq, slot, hero, _, owner)
        detailState = { open = true, seq = seq, slot = slot, heroId = hero, owner = owner, pinned = false }
    end,
    pin = function() detailState.pinned = true end,
    setAnchor = function() end, init = function() end,
    handleInput = function() return true end,
}
package.loaded["ui.character.equip.EquipmentDetail"] = Detail
local Draw = { hitTest = function(x, y, cx, cy, w, h)
    return x >= cx-w/2 and x <= cx+w/2 and y >= cy-h/2 and y <= cy+h/2
end }
package.loaded["core.DrawUtil"] = Draw
package.loaded["core.DarkIcon"] = { QUALITY_TRIM = {}, drawNine = function() end }
local filterDialogState = { open = false, closes = 0 }
local filterDialog = { NONE_KEY = "none", isOpen = function() return filterDialogState.open end,
    close = function() filterDialogState.open = false; filterDialogState.closes = filterDialogState.closes + 1 end }
package.loaded["ui.widget.SetFilterDialog"] = filterDialog
local leftPages = {}
for _, path in ipairs({ "ui.loot.LootBoxPage", "ui.story.task.TaskPage", "ui.church.talent.TalentPage",
    "ui.church.ChurchPage", "ui.tavern.TavernPage", "ui.market.MarketPage" }) do
    local page = { open = false, closed = 0 }
    page.isOpen = function() return page.open end
    page.forceClose = function() page.open = false; page.closed = page.closed + 1 end
    page.close = page.forceClose
    package.loaded[path] = page
    leftPages[path] = page
end
local slotClearCount = 0
package.loaded["ui.character.detail.CharacterDetail"] = {
    clearEquipmentSlot = function() slotClearCount = slotClearCount + 1 end,
}
-- 引擎资源 require 使用 preload 路由，不能只替换 package.loaded。
for _, key in ipairs({ "ui.character.equip.EquipmentDetail", "core.DrawUtil", "core.DarkIcon",
    "ui.widget.SetFilterDialog", "ui.character.detail.CharacterDetail" }) do
    local stub = package.loaded[key]
    package.preload[key] = function() return stub end
end
for key, stub in pairs(leftPages) do
    package.preload[key] = function() return stub end
end
local Link = require("ui.backpack.BackpackEquipLink")
local GRID = { FIRST_ROW_TOP = 470, CLIP_BOTTOM = 1980, CELL_SIZE = 160, CELL_RADIUS = 16, GAP = 30, COLS = 5 }
local cells = {160,350,540,730,920}
local function fixture()
    local state = { open = false, closing = false, tab = "equip", scrollY = 0, scrollMax = 900, scrollVel = 0 }
    local counts = { opens = 0, closes = 0, restores = 0, mode = "left" }
    local api = Link.bind({ state = state, GRID = GRID, CELL_COL_CX = cells,
        EquipmentDetail = Detail, DrawUtil = Draw,
        getLeftPage = function(path) return leftPages[path] end,
        onClearEquipmentSlot = function() slotClearCount = slotClearCount + 1 end,
        itemDetState = { open = false }, getEquipList = function() return {} end,
        getHostMode = function() return counts.mode end,
        setLeftMode = function() counts.mode = "left" end,
        openPage = function(mode, tab)
            counts.opens = counts.opens + 1; counts.mode = mode
            state.open, state.closing, state.tab, state.scrollY = true, false, tab, 0
        end,
        closePage = function() counts.closes = counts.closes + 1; state.closing = true end,
        selectEquipTab = function() state.tab = "equip" end,
        restoreView = function(view)
            counts.restores = counts.restores + 1; counts.mode = view.mode
            state.tab, state.scrollY, state.scrollMax = view.tab, view.scrollY, view.scrollMax
        end,
        clampScroll = function() end, SCROLL_WHEEL_STEP = 60,
    })
    return api, state, counts
end
local function runLifecycle()
    local api, s, c = fixture()
    api.acquireWarehouse("equipment", 1, "weapon")
    check(c.opens == 1 and s.tab == "equip", "auto enter opens equip once")
    s.scrollY = 600
    api.acquireWarehouse("equipment", 1, "weapon")
    check(c.opens == 1 and s.scrollY == 600, "repeat acquire never reset/reopen")
    api.releaseWarehouse("equipment")
    check(c.closes == 1 and s.closing, "last auto release hides warehouse")
    api.acquireWarehouse("blacksmith")
    check(c.opens == 1 and not s.closing, "inflight auto close cancelled on handoff")
    api.acquireWarehouse("equipment", 1, "armor")
    api.releaseWarehouse("blacksmith")
    check(c.closes == 1 and not s.closing and api.getEquipmentSlotFilter() == "armor", "smith release keeps equipment holder/filter")
    api.releaseWarehouse("equipment")
    check(c.closes == 2, "handoff final holder closes auto warehouse")

    api, s, c = fixture()
    s.open, s.tab, s.scrollY = true, "item", 380
    api.onManualOpen()
    s.scrollY = 380
    api.acquireWarehouse("equipment", 1, "offhand")
    check(c.opens == 0 and s.tab == "equip", "manual item warehouse reused, not reopened")
    api.releaseWarehouse("equipment")
    check(s.open and not s.closing and s.tab == "item" and s.scrollY == 380 and c.closes == 0,
        "manual tab/scroll restored and warehouse preserved")
    check(api.getEquipmentSlotFilter() == nil, "temporary slot cleared on release")
    api.acquireWarehouse("equipment", 1, "weapon")
    api.acquireWarehouse("blacksmith")
    check(api.getEquipmentSlotFilter() == nil, "smith can temporarily clear equipment filter")
    api.releaseWarehouse("blacksmith")
    check(api.getEquipmentSlotFilter() == "weapon", "smith release restores other holder filter")
    api.releaseWarehouse("equipment")

    api, s, c = fixture()
    api.acquireWarehouse("equipment", 1, "helmet")
    api.onManualOpen()
    s.tab, s.scrollY = "item", 0
    api.onManualTabChange()
    api.releaseWarehouse("equipment")
    check(c.closes == 0 and s.tab == "item", "manual takeover of auto session survives release")

    api, s, c = fixture()
    api.acquireWarehouse("equipment", 1, "weapon")
    api.onManualClose(); s.open, s.closing = false, false
    api.acquireWarehouse("equipment", 2, "offhand")
    api.acquireWarehouse("blacksmith")
    api.setEquipmentSlotFilter("armor", 2)
    check(c.opens == 1 and not s.open, "manual close blocks all same-session autoreopen")
    api.releaseWarehouse("blacksmith"); api.releaseWarehouse("equipment")
    api.acquireWarehouse("equipment", 2)
    check(c.opens == 2 and s.open, "next genuine enter edge can open again")
    local page = leftPages["ui.market.MarketPage"]
    page.open = true; api.update()
    check(s.closing and c.closes == 1 and page.open, "player opens other left page: warehouse yields")
    s.open, s.closing = false, false
    api.acquireWarehouse("equipment", 2)
    check(c.opens == 2 and page.open, "yielded warehouse does not force reopen/close new page")
    api.releaseWarehouse("equipment"); page.open = false

    api, s, c = fixture()
    page.open = true
    api.acquireWarehouse("equipment", 1)
    check(not page.open and s.open, "enter edge clears other left page")
    Detail.open(1, nil, nil, true, "backpack"); Detail.pin()
    api.setEquipmentSlotFilter("weapon", 1)
    check(not Detail.isOpen(), "slot change clears pinned old candidate")
    Detail.open(1, nil, nil, true, "backpack"); Detail.pin()
    api.setEquipmentSlotFilter(nil, 1)
    check(Detail.isPinned(), "nil/samehero expansion preserves valid pinned candidate")
    api.setEquipmentSlotFilter(nil, 2)
    check(not Detail.isOpen(), "hero change clears old candidate even with nil slot")
    api.setEquipmentSlotFilter("offhand", 2)
    check(api.handleFilterInput(890, GRID.FIRST_ROW_TOP - 54) and slotClearCount == 1,
        "filter cancel notifies right detail slot cancellation")
end

local function runTutorialEnsure()
    local s = { open = false, closing = false, tab = "item", scrollY = 0, scrollVel = 0,
        qualitySet = { [6] = true }, setFilter = { none = true } }
    local c = { opens = 0, closes = 0, mode = "window" }
    local item = { open = true }
    local api = Link.bind({ state = s, GRID = GRID, CELL_COL_CX = cells,
        EquipmentDetail = Detail, DrawUtil = Draw, SetFilterDialog = filterDialog, itemDetState = item,
        getLeftPage = function(path) return leftPages[path] end,
        getHostMode = function() return c.mode end,
        setLeftMode = function() c.mode = "left" end,
        clearTutorialFilters = function()
            local changed = next(s.qualitySet) ~= nil or next(s.setFilter) ~= nil
            if changed then s.qualitySet, s.setFilter = {}, {} end
            return changed
        end,
        openPage = function(mode, tab)
            c.opens = c.opens + 1; c.mode = mode
            s.open, s.closing, s.tab, s.scrollY = true, false, tab, 0
        end,
        closePage = function() c.closes = c.closes + 1; s.closing = true end,
        selectEquipTab = function() s.tab = "equip" end,
    })
    local otherPage = leftPages["ui.market.MarketPage"]
    otherPage.open, filterDialogState.open = true, true
    Detail.open(1, nil, nil, true, "backpack"); Detail.pin()
    check(api.ensureTutorialEquipment("1", "weapon") == true and c.opens == 1
        and c.mode == "left" and s.tab == "equip" and not otherPage.open,
        "tutorial ensure explicitly opens left equip and clears unrelated left page")
    local slot, hero = api.getEquipmentSlotFilter()
    check(slot == "weapon" and hero == 1 and not next(s.qualitySet) and not next(s.setFilter)
        and not filterDialogState.open and not item.open and not Detail.isOpen(),
        "tutorial initial ensure clears restrictive filters, filter layer and candidate")
    s.scrollY = 600
    Detail.open(1, nil, nil, true, "backpack"); Detail.pin()
    local closed = filterDialogState.closes
    check(api.ensureTutorialEquipment(1, "weapon") == false and s.scrollY == 600
        and Detail.isPinned() and c.opens == 1 and filterDialogState.closes == closed,
        "stable tutorial ensure preserves scroll and candidate without repeated cleanup")
    check(api.ensureTutorialEquipment(2, "helmet") == true and s.scrollY == 0
        and not Detail.isOpen() and c.opens == 1,
        "tutorial changed hero/slot refreshes filter and clears candidate, never reopens")
    api.onManualClose(); s.open, s.closing = false, false
    check(api.acquireWarehouse("equipment", 2, "helmet") == false and c.opens == 1,
        "normal acquire still cannot reopen a tutorial-held manually closed warehouse")
    check(api.ensureTutorialEquipment(2, "helmet") == true and c.opens == 2 and s.open,
        "only tutorial ensure releases manual-close suppression and reopens")
    api.onManualClose(); s.closing = true
    check(api.ensureTutorialEquipment(2, "helmet") == true and c.opens == 3 and not s.closing,
        "tutorial ensure safely restores warehouse during manual close animation")
    s.qualitySet[1], s.setFilter.none = true, true
    filterDialogState.open = true
    check(api.ensureTutorialEquipment(2, "helmet") == true and c.opens == 3
        and not next(s.qualitySet) and not next(s.setFilter) and not filterDialogState.open,
        "changed tutorial filters/layer are cleared without reopening page")
    api.releaseWarehouse("equipment")
    s.open, s.closing = false, false
    check(api.ensureTutorialEquipment(2, "helmet") == true and c.opens == 4,
        "new tutorial equipment session restores after release")
    Detail.close()
    filterDialogState.open = false
end

-- 真实模板+双持分支规则，持有测试 mock 不修改任何装备穿戴数据。
package.loaded["ui.widget.ImageCache"] = { init = function() end, getEquipIcon = function() return 1 end }
package.loaded["ui.widget.HeroFrame"] = { draw = function() end }
package.loaded["ui.character.panel.CharacterPanel"] = { getShards = function() return 0 end }
for _, key in ipairs({ "ui.widget.ImageCache", "ui.widget.HeroFrame", "ui.character.panel.CharacterPanel" }) do
    local stub = package.loaded[key]
    package.preload[key] = function() return stub end
end
local Store = require("core.PlayerStore")
local EC = require("config.EquipmentConfig")
local ES = require("systems.EquipmentSystem")
local HC = require("config.HeroConfig")
local AC = require("config.AdvancementConfig")
local Wearability = require("ui.character.detail.EquipmentWearability")
local fake = { inventory = {}, equipped = {} }
---@type table
local heroes = { roster = {} }
Store.Get = function(key) if key == "equipment" then return fake elseif key == "heroes" then return heroes end end
local filterSlot, filterHero, quality, setTemplate = nil, nil, nil, nil
local gridState = { open = true, tab = "equip", scrollY = 0 }
local drawingHeroIcons, drawingLock = {}, -1
local Grids = require("ui.backpack.BackpackGrids")
local grids = Grids.bind({ GRID = GRID, CELL_COL_CX = cells, DESIGN_W = 1080, DrawUtil = Draw,
    state = gridState, ITEM_DEFS = {},
    qualityChecked = function(q) return not quality or q == quality end,
    setChecked = function(tid) return not setTemplate or tid == setTemplate end,
    getEquipmentSlotFilter = function() return filterSlot, filterHero end,
    getImgHeroIcons = function() return drawingHeroIcons end, getImgLock = function() return drawingLock end,
    calcScrollMax = function() return 0 end, clampScroll = function() end,
})

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
end
local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
-- 真实 applyEquip oracle 只复制其会读取/水合的 candidate/main/offhand 与槽映射。
-- 其余装备根本不被访问，避免差分矩阵每次复制全仓数百件。
local function equipProbe(source, seq, heroId)
    local probe = { inventory = {}, equipped = {} }
    local function copyEquip(key)
        if key == nil then return end
        local equip = source.inventory[tostring(key)] or source.inventory[key]
        if equip then probe.inventory[tostring(key)] = deepCopy(equip) end
    end
    copyEquip(tonumber(seq))
    local slots = ES.getHeroSlots(source, heroId) or {}
    copyEquip(slots.weapon); copyEquip(slots.offhand)
    for hid, map in pairs(source.equipped or {}) do
        if type(map) == "table" then
            local out = {}
            for slot, id in pairs(map) do out[slot] = id end
            probe.equipped[hid] = out
        else probe.equipped[hid] = map end
    end
    return probe
end
local function listed(seq)
    for _, equip in ipairs(grids.getEquipList()) do if equip.seq == seq then return equip end end
    return nil
end
local function contains(seq) return listed(seq) ~= nil end
local function hasWearability(seq, expected)
    local equip = listed(seq)
    if not equip or equip.canWear ~= expected then return false end
    if expected then return equip.cannotEquipReason == nil end
    return type(equip.cannotEquipReason) == "string" and equip.cannotEquipReason ~= ""
end
local seqByTemplate = {}
local function context(heroId, slot, branch, main, off, level)
    filterHero, filterSlot, quality, setTemplate = heroId, slot, nil, nil
    heroes.roster = { [tostring(heroId)] = { level = level or 100, advBranch = branch } }
    fake.equipped = { [tostring(heroId)] = { weapon = main, offhand = off },
        [99] = { armor = seqByTemplate.A31 } }
end

-- 新筛选专项独立运行：不借用下方全模板 applyEquip oracle，不改变旧断言。
-- 评分只用确定性 mock；筛选/排序/缓存与词条水合执行真实生产模块。
local function runDetailedFilters()
    local Filters = require("ui.backpack.BackpackFilters")
    local Affixes = require("config.AffixConfig")
    local AD = require("systems.AttributeDef")
    local Sets = require("config.EquipmentSetConfig")
    local Power = require("systems.EquipmentPower")
    local savedGet, savedRevision = Store.Get, Store.GetRevision
    local savedScore, savedContext, savedEvaluate = Power.score, Power.getContext, Power.evaluate
    local source = { equipment = { inventory = {}, equipped = {} },
        heroes = { roster = { [1] = { level = 100 } } }, artifacts = {}, talents = {} }
    local revisions = { equipment = 1, heroes = 1, artifacts = 1, talents = 1 }
    local settings = { sortAscending = false, setFilter = {} }
    local view = { open = true, tab = "equip", scrollY = 0 }
    ---@type string|nil
    local slot = nil
    ---@type number|nil
    local hero = nil
    local dual = false
    local selectedQualities, changes, scoreCalls = {}, 0, 0
    Store.Get = function(key) return source[key] end
    Store.GetRevision = function(key) return revisions[key] or 0 end
    Power.score = function(equip) scoreCalls = scoreCalls + 1; return equip.testPower or 0 end
    Power.getContext = function(id) return { heroId = id } end
    Power.evaluate = function() return { valid = true, gain = 0, power = 0 } end
    local function qualityMatches(q) return not next(selectedQualities) or selectedQualities[q] == true end
    local smallGrids = Grids.bind({ GRID = GRID, CELL_COL_CX = cells, DESIGN_W = 1080,
        state = view, decomposeState = settings, ITEM_DEFS = {}, DrawUtil = Draw,
        getEquipmentSlotFilter = function() return slot, hero end,
        qualityChecked = qualityMatches,
        setChecked = function(tid)
            return not next(settings.setFilter)
                or settings.setFilter[Sets.getSetIdForTemplate(EC.ITEMS[tid]) or "none"] == true
        end,
        calcScrollMax = function() return 0 end, clampScroll = function() end,
    })
    local toolbar = Filters.bind({ filters = settings, GRID = GRID,
        getSlot = function() return slot end, setSlot = function(value) slot = value end,
        isDualWield = function() return dual end,
        onChange = function() changes = changes + 1 end,
        clearQualitySets = function() selectedQualities, settings.setFilter = {}, {} end,
    })
    local function install(inventory)
        source.equipment = { inventory = inventory, equipped = {} }
        revisions.equipment = revisions.equipment + 1
    end
    local function ids(list)
        local out = {}
        for _, entry in ipairs(list) do out[#out + 1] = tostring(entry.seq) end
        return table.concat(out, ",")
    end
    local function order(expected, label) check(ids(smallGrids.getEquipList()) == expected, label) end
    local function optionValues(options)
        local values, unique = {}, true
        for _, option in ipairs(options) do
            if values[option.value] then unique = false end
            values[option.value] = true
        end
        return values, unique
    end
    -- 按实际工具条坐标选菜单项；覆盖滚轮后的第八行而不访问私有 menu。
    local function choose(key, value)
        local x = key == "type" and 765 or 295
        local y = GRID.FIRST_ROW_TOP - (key == "sort" and 136 or 226)
        local options, index = toolbar.getOptions(key), nil
        for i, option in ipairs(options) do if option.value == value then index = i; break end end
        if not index then error("missing toolbar option " .. key .. ":" .. tostring(value)) end
        if not toolbar.handleInput(x, y) or not toolbar.isOpen() then error("menu did not open: " .. key) end
        toolbar.handleScroll(#options) -- 已选项可能让菜单自动滚动，先归零再定位。
        local scroll = math.max(0, index - 8)
        toolbar.handleScroll(-scroll)
        local h = math.min(8, #options) * 62 + 12
        local top = math.min(y + 43, GRID.CLIP_BOTTOM - h)
        toolbar.handleInput(x, top + 6 + (index - scroll - 0.5) * 62)
    end
    local ok, err = pcall(function()
        local slotValues, uniqueSlots = optionValues(toolbar.getOptions("slot"))
        local expectedSlots = { all = true }
        for _, value in ipairs(EC.SLOTS) do expectedSlots[value] = true end
        check(uniqueSlots and deepEqual(slotValues, expectedSlots), "detailed slot options cover all six slots exactly once")
        local attrs = {}
        for _, tpl in pairs(EC.ITEMS) do for _, stat in ipairs(tpl.stats or {}) do attrs[stat[1]] = true end end
        for _, affix in ipairs(Affixes.AFFIXES) do attrs[affix.key] = true end
        for _, affix in ipairs(Affixes.CORRUPT_AFFIXES) do attrs[affix.key] = true end
        local expectedSorts = { default = true, power = true, quality = true, level = true, ascend = true }
        for key in pairs(attrs) do expectedSorts[key] = true end
        local sortValues, uniqueSorts = optionValues(toolbar.getOptions("sort"))
        check(uniqueSorts and deepEqual(sortValues, expectedSorts),
            "detailed sorts include five modes plus every fixed, normal and corrupt attribute")
        for _, target in ipairs({ "all", "weapon", "offhand", "armor", "helmet", "shoes", "accessory" }) do
            for _, allowDual in ipairs({ false, true }) do
                slot, dual = target ~= "all" and target or nil, allowDual
                local expectedTypes = { all = true }
                for _, tpl in pairs(EC.ITEMS) do
                    if not slot or tpl.slot == slot or (allowDual and slot == "offhand"
                        and tpl.slot == "weapon" and tpl.grip == "onehand") then expectedTypes[tpl.type] = true end
                end
                local typeValues, uniqueTypes = optionValues(toolbar.getOptions("type"))
                check(uniqueTypes and deepEqual(typeValues, expectedTypes),
                    "detailed types match structural slot " .. target .. ", dual=" .. tostring(allowDual))
            end
        end
        slot, dual = nil, false
        choose("type", EC.ITEMS.W1.type)
        check(settings.typeFilter == EC.ITEMS.W1.type and not toolbar.isOpen(), "type menu writes selected subtype and closes")
        choose("slot", "armor")
        check(slot == "armor" and settings.typeFilter == nil, "slot change clears stale subtype")
        choose("slot", "all"); choose("type", "all")
        check(slot == nil and settings.typeFilter == nil, "all slot and type remove structural restrictions")
        for key in pairs(expectedSorts) do
            choose("sort", key)
            check(settings.sortKey == (key ~= "default" and key or nil), "sort menu writes stable key " .. key)
        end
        local beforeChanges = changes
        toolbar.handleInput(605, GRID.FIRST_ROW_TOP - 136)
        check(settings.sortAscending == true and changes == beforeChanges + 1, "order control selects ascending and invalidates display")
        toolbar.handleInput(605, GRID.FIRST_ROW_TOP - 136)
        check(settings.sortAscending == false, "order control selects descending")
        toolbar.handleInput(295, GRID.FIRST_ROW_TOP - 136)
        toolbar.handleInput(10, GRID.CLIP_BOTTOM + 20)
        check(not toolbar.isOpen() and changes == beforeChanges + 2 and not toolbar.handleScroll(1),
            "outside menu dismissal and closed scroll never change filters")
        slot, settings.typeFilter, settings.sortKey, settings.sortAscending = "armor", "stale", "str", true
        selectedQualities[6], settings.setFilter.none = true, true
        toolbar.reset()
        check(slot == nil and settings.typeFilter == nil and settings.sortKey == nil
            and settings.sortAscending == false and not next(selectedQualities) and not next(settings.setFilter),
            "reset clears slot, subtype, order, quality and set selections")

        -- 冷存档只含 templateId；逐部位 + 逐类型独立验证 AND 筛选与套装基础计数。
        local inventory = {}
        for i, tid in ipairs({ "W1", "W13", "W7", "O7", "A31", "H1", "S1", "C1" }) do
            inventory[tostring(i)] = { templateId = tid, level = 1, quality = i % 2 + 1 }
        end
        install(inventory)
        local structuralBefore = deepCopy(source)
        for _, target in ipairs(EC.SLOTS) do
            slot = target
            for _, option in ipairs(toolbar.getOptions("type")) do
                settings.typeFilter = option.value ~= "all" and option.value or nil
                local expectedIds = {}
                for key, equip in pairs(inventory) do
                    local tpl = EC.ITEMS[equip.templateId]
                    if tpl.slot == target and (not settings.typeFilter or tpl.type == settings.typeFilter) then expectedIds[key] = true end
                end
                local actualIds, count = {}, 0
                for _, entry in ipairs(smallGrids.getEquipList()) do actualIds[tostring(entry.seq)] = true end
                for _, amount in pairs(smallGrids.getSetCounts()) do count = count + amount end
                local n = 0; for _ in pairs(expectedIds) do n = n + 1 end
                check(deepEqual(actualIds, expectedIds) and count == n,
                    "slot AND subtype filters list and base counts: " .. target .. "/" .. option.value)
            end
        end
        check(deepEqual(source, structuralBefore), "structural filters leave cold source and hero inventory unchanged")
        slot, hero = "offhand", 1
        source.heroes.roster[1].advBranch = { first = 104, second = 207 }
        revisions.heroes = revisions.heroes + 1
        settings.typeFilter = EC.ITEMS.W1.type
        check(ids(smallGrids.getEquipList()) == "1", "dual offhand AND subtype adds matching onehand but excludes ordinary offhand and twohand")
        selectedQualities[1] = true
        check(#smallGrids.getEquipList() == 0, "dual offhand AND subtype AND quality never unions excluded candidates")
        selectedQualities = { [2] = true }
        check(ids(smallGrids.getEquipList()) == "1", "dual offhand matching quality restores selected onehand")
        slot, hero, settings.typeFilter, selectedQualities = nil, nil, nil, {}
        source.heroes.roster[1].advBranch = nil
        revisions.heroes = revisions.heroes + 1
        -- pairs 遍历模板无序，任取套装可能撞上基础库存已有套装，破坏精确1/0期望。
        -- 按模板ID稳定选择基础库存完全没有的真实套装，不放宽下方交集断言。
        local occupiedSets, templateIds = {}, {}
        for _, equip in pairs(inventory) do
            local id = Sets.getSetIdForTemplate(EC.ITEMS[equip.templateId])
            if id then occupiedSets[id] = true end
        end
        for tid in pairs(EC.ITEMS) do templateIds[#templateIds + 1] = tid end
        table.sort(templateIds)
        ---@type string|nil
        local setTid = nil
        ---@type string|nil
        local setId = nil
        for _, tid in ipairs(templateIds) do
            local id = Sets.getSetIdForTemplate(EC.ITEMS[tid])
            if id and not occupiedSets[id] then setTid, setId = tid, id; break end
        end
        check(setTid ~= nil, "detailed set fixture includes a real affiliated template")
        inventory["9"] = { templateId = setTid, level = 1, quality = 2 }
        revisions.equipment = revisions.equipment + 1
        settings.setFilter[setId] = true
        check(ids(smallGrids.getEquipList()) == "9" and smallGrids.getSetCounts()[setId] == 1,
            "set selection retains matching template while base count includes its instance")
        selectedQualities[1] = true
        check(#smallGrids.getEquipList() == 0 and smallGrids.getSetCounts()[setId] == 0,
            "set AND quality intersection hides selected set rather than unioning qualities")
        selectedQualities, settings.setFilter = {}, {}
        inventory["9"] = nil
        revisions.equipment = revisions.equipment + 1

        install({
            ["1"] = { templateId = "W1", quality = 1, level = 50, ascendLevel = 9, testPower = 10 },
            [2] = { templateId = "W1", quality = 3, level = 20, ascendLevel = 2, testPower = 30 },
            ["3"] = { templateId = "W1", quality = 3, level = 40, ascendLevel = 7, testPower = 20 },
            [4] = { templateId = "W1", quality = 3, level = 20, ascendLevel = 2, testPower = 30 },
            ["5"] = { templateId = "W1", quality = 2, level = 10, ascendLevel = 4, testPower = 40 },
        })
        local orders = {
            { key = "default", descending = "2,4,3,5,1", ascending = "1,5,3,4,2" },
            { key = "power", descending = "5,2,4,3,1", ascending = "1,3,2,4,5" },
            { key = "quality", descending = "2,4,3,5,1", ascending = "1,5,2,4,3" },
            { key = "level", descending = "1,3,2,4,5", ascending = "5,2,4,3,1" },
            { key = "ascend", descending = "1,3,5,2,4", ascending = "2,4,5,3,1" },
        }
        local sortBefore = deepCopy(source)
        for _, mode in ipairs(orders) do
            choose("sort", mode.key)
            settings.sortAscending = false; order(mode.descending, mode.key .. " descending has deterministic tie order")
            settings.sortAscending = true; order(mode.ascending, mode.key .. " ascending has deterministic tie order")
        end
        check(deepEqual(source, sortBefore), "numeric modes never hydrate ascendLevel-only source")

        -- 每个属性都测试固定+重复随机词条合计、显式零与缺属性；5件而非巨大试穿矩阵。
        for key in pairs(attrs) do
            check(AD.META[key] ~= nil, "sortable attribute has metadata: " .. key)
            local affixTpl = Affixes.BY_KEY[key]
            local function affix(value)
                return { affixId = affixTpl and tostring(affixTpl.id) or nil,
                    key = not affixTpl and key or nil, quality = 0, value = tostring(value) }
            end
            install({
                [1] = { templateId = "W1", level = 1, quality = 1, baseStats = { { key, 10 } }, affixes = { affix(2), affix(3) } },
                [2] = { templateId = "W1", level = 1, quality = 1, baseStats = { { key, 8 } }, affixes = { affix(1) } },
                [3] = { templateId = "W1", level = 1, quality = 6, baseStats = {}, affixes = {} },
                [4] = { templateId = "W1", level = 1, quality = 1, baseStats = { { key, 0 } }, affixes = {} },
                [5] = { templateId = "W1", level = 1, quality = 1, baseStats = { { key, -2 } }, affixes = {} },
            })
            local before = deepCopy(source)
            settings.sortKey, settings.sortAscending = key, false
            order("1,2,4,5,3", key .. " descending sums fixed and repeated random attributes, missing stays last")
            local values, presence = {}, {}
            for _, entry in ipairs(smallGrids.getEquipList()) do values[entry.seq], presence[entry.seq] = entry.sortValue, entry.hasSortAttribute end
            check(values[1] == 15 and values[2] == 9 and values[4] == 0 and values[5] == -2
                and presence[4] == true and presence[3] == false, key .. " projection distinguishes zero/negative from missing")
            settings.sortAscending = true
            order("5,4,2,1,3", key .. " ascending still puts missing after zero/negative")
            check(deepEqual(source, before), key .. " attribute hydration never rewrites nested source")
        end

        -- 真正精简、冷词条 key 缺失，含会被 hydrate 规范化的嵌套腐化回退快照。
        install({ ["1"] = { templateId = "W1", level = 1, quality = 1, ascendLevel = 2,
            affixMult = "1.5", affixes = { { affixId = "1", value = "7", ascBonus = "2" } },
            corruptRevert = { baseMult = "1", affixCount = "1", patches = {
                { ["1"] = "s", ["2"] = "1", ["3"] = "3", layer = "1" } } } } })
        settings.sortKey, settings.sortAscending = "str", false
        local coldBefore = deepCopy(source)
        local cold = smallGrids.getEquipList()[1]
        local fixed = 0
        for index, stat in ipairs(EC.ITEMS.W1.stats) do
            if stat[1] == "str" then
                local steps = index == 1 and 2 or math.floor((2 - (index - 1)) / (#EC.ITEMS.W1.stats - 1)) + 1
                fixed = fixed + stat[2] * (1 + math.max(0, steps) * 0.05)
            end
        end
        check(cold and cold.hasSortAttribute == true and math.abs(cold.sortValue - (fixed + 7 * 1.5 + 2)) < 1e-9,
            "cold affixId hydration includes fixed ascend, affix multiplier and ascBonus")
        check(deepEqual(source, coldBefore) and source.equipment.inventory["1"].affixes[1].key == nil
            and source.equipment.inventory["1"].baseStats == nil,
            "cold nested corruptRevert and slim affixes stay byte-value unchanged after display hydration")
        install({ [1] = { templateId = "W1", level = 1, quality = 1, baseStats = {},
            affixMult = 9, affixes = { { affixId = "1001", quality = 0, value = "6", ascBonus = "99" } } } })
        settings.sortKey = "finalPhysAtkBonus"
        local corruptBefore = deepCopy(source)
        local corrupt = smallGrids.getEquipList()[1]
        check(corrupt and corrupt.sortValue == 6 and corrupt.hasSortAttribute == true,
            "cold corrupt attribute does not receive ordinary affix multiplier or ascBonus")
        check(deepEqual(source, corruptBefore), "cold corrupt hydration leaves source quality/key/ascBonus unchanged")

        -- 独立缓存夹具：只在模拟正式 Store 版本通知时修改库存，滚动不评分。
        install(inventory)
        settings.sortKey, settings.sortAscending, settings.typeFilter = nil, false, nil
        selectedQualities, settings.setFilter, slot, hero = {}, {}, nil, nil
        local current = smallGrids.getEquipList()
        local calls = scoreCalls
        view.scrollY = 500
        check(smallGrids.getEquipList() == current and scoreCalls == calls, "cache reuses list across repeated calls and scroll")
        local function refresh(label)
            local nextList = smallGrids.getEquipList()
            check(nextList ~= current, "cache key refreshes " .. label)
            current = nextList
            local scored = scoreCalls
            check(smallGrids.getEquipList() == current and scoreCalls == scored, "cache settles after " .. label)
        end
        settings.sortKey = "level"; refresh("sort key")
        settings.sortAscending = true; refresh("sort direction")
        settings.typeFilter = EC.ITEMS.W1.type; refresh("subtype")
        settings.typeFilter = nil; refresh("subtype clear")
        slot = "weapon"; refresh("slot")
        hero = 1; refresh("hero context")
        slot = "offhand"; refresh("offhand slot")
        source.heroes.roster[1].advBranch = { first = 104, second = 207 }; refresh("dual wield context")
        selectedQualities[1] = true; refresh("in-place quality selection")
        selectedQualities[2] = true; refresh("in-place second quality selection")
        settings.setFilter.none = true; refresh("in-place set selection")
        settings.setFilter.none = nil; refresh("in-place set deselection")
        for _, key in ipairs({ "equipment", "heroes", "artifacts", "talents" }) do
            revisions[key] = revisions[key] + 1; refresh(key .. " revision")
            source[key] = deepCopy(source[key]); refresh(key .. " source replacement")
        end
        slot, hero, selectedQualities = nil, nil, {}
        settings.typeFilter, settings.setFilter = nil, {}
        current = smallGrids.getEquipList()
        source.equipment.inventory["99"] = { templateId = "W1", quality = 1, level = 1 }
        revisions.equipment = revisions.equipment + 1; refresh("published inventory insertion")
        check(#current == 9, "cache inventory revision exposes inserted candidate")
        source.equipment.inventory["99"] = nil
        revisions.equipment = revisions.equipment + 1; refresh("published inventory removal")
        check(#current == 8, "cache inventory revision removes deleted candidate")
        source.equipment = nil
        current = smallGrids.getEquipList()
        check(#current == 0, "cache source clear discards all previous candidates")
        install(inventory); refresh("equipment source restore")
        check(#current == 8, "cache source restore rebuilds after clear")
        Store.GetRevision = nil
        current = smallGrids.getEquipList()
        local fresh = smallGrids.getEquipList()
        check(fresh ~= current and #fresh == 8, "revision-less fixture rebuilds instead of retaining stale list")
    end)
    Store.Get, Store.GetRevision = savedGet, savedRevision
    Power.score, Power.getContext, Power.evaluate = savedScore, savedContext, savedEvaluate
    check(Store.Get == savedGet and Store.GetRevision == savedRevision and Power.score == savedScore
        and Power.getContext == savedContext and Power.evaluate == savedEvaluate,
        "detailed fixture restores Store and power APIs before legacy tests")
    if not ok then error(err) end
end

local function runSharedReentry()
    for _, closing in ipairs({ false, true }) do
        local api, s, c = fixture()
        check(type(api.enterEquipmentWarehouse) == "function", "genuine equipment entry API exists")
        if not api.enterEquipmentWarehouse then return end
        api.acquireWarehouse("blacksmith")
        api.onManualClose(); s.open, s.closing = closing, closing
        local opens = c.opens
        check(api.acquireWarehouse("blacksmith") == false and c.opens == opens,
            "smith repeat acquire respects shared manual-close suppression")
        check(api.enterEquipmentWarehouse("1", "armor") == true and s.open and not s.closing
            and s.tab == "equip" and c.opens == opens + 1,
            "genuine equipment enter restores shared suppressed warehouse, closing=" .. tostring(closing))
        local selectedSlot, selectedHero = api.getEquipmentSlotFilter()
        check(selectedSlot == "armor" and selectedHero == 1, "genuine entry applies normalized hero and selected slot")
        s.scrollY = 620
        api.acquireWarehouse("equipment", 1, "armor")
        check(c.opens == opens + 1 and s.scrollY == 620, "ordinary repeated equipment acquire never reopens restored warehouse")
        api.releaseWarehouse("equipment")
        check(s.open and not s.closing and c.closes == 0 and api.getEquipmentSlotFilter() == nil,
            "equipment release preserves original smith holder and restores smith filter")
        api.acquireWarehouse("blacksmith")
        check(c.opens == opens + 1 and s.scrollY == 0, "smith still owns restored warehouse without duplicate reopen")
        api.releaseWarehouse("blacksmith")
        check(c.closes == 1 and s.closing, "last smith release closes restored auto session")
    end
end

local function runIndependent(label, run)
    local beforePasses, beforeFailures = passes, failures
    local ok, err = pcall(run)
    if not ok then check(false, label .. " exception: " .. tostring(err)) end
    print("[backpack_equip_link_test " .. label .. "] passes=" .. (passes - beforePasses)
        .. " failures=" .. (failures - beforeFailures))
end

local function runFilter()
    local seq = 0
    for tid in pairs(EC.ITEMS) do
        seq = seq + 1
        -- 精简存档：预检不得 hydrate 原对象或词缀/腐化快照。
        fake.inventory[tostring(seq)] = { templateId = tid, level = 85, quality = 2,
            affixes = { { affixId = "1", value = "7" } },
            corruptRevert = { affixCount = "1", patches = { { "s", 1, 3 } } } }
        seqByTemplate[tid] = seq
    end
    local sword, axe, greatsword = seqByTemplate.W1, seqByTemplate.W13, seqByTemplate.W7
    local rapier, dagger = seqByTemplate.W61, seqByTemplate.W55
    local shield, tome = seqByTemplate.O7, seqByTemplate.O13
    local same = { first = 110, second = 220 }
    local different = { first = 104, second = 207 }
    check(sword and axe and greatsword and rapier and dagger and shield and tome,
        "fixture includes exact templates from applyEquip regressions")

    context(1, nil, nil, nil, nil, 84)
    local belowList = grids.getEquipList()
    local allBelow = #belowList == seq
    for _, equip in ipairs(belowList) do
        if equip.canWear ~= false or type(equip.cannotEquipReason) ~= "string"
            or not equip.cannotEquipReason:find("角色等级不足", 1, true) then allBelow = false end
    end
    check(allBelow, "below equipment level retains every item with level reason and grey flag")
    check(hasWearability(sword, false), "legal sword is grey before reaching required level")
    heroes.roster["1"].level = 85
    check(hasWearability(sword, true) and hasWearability(seqByTemplate.W31, false),
        "level upgrade refreshes legal sword to true, wrong-class weapon remains listed grey")
    check(hasWearability(seqByTemplate.A31, true) and hasWearability(seqByTemplate.A55, false),
        "heavy armor normal, cloth armor retained grey")
    check(hasWearability(shield, true) and hasWearability(tome, false),
        "ordinary offhand respects hero types through grey flag, not removal")
    filterSlot = "helmet"
    for _, equip in ipairs(grids.getEquipList()) do check(equip.slot == "helmet", "helmet context structurally keeps only helmets") end
    context(2, "armor", nil)
    check(hasWearability(seqByTemplate.A55, true) and hasWearability(seqByTemplate.A31, false),
        "mage cloth armor normal, heavy armor retained grey")
    context(1, "weapon", nil)
    check(hasWearability(sword, true) and hasWearability(greatsword, true) and not contains(tome)
        and hasWearability(seqByTemplate.W31, false), "weapon structure excludes ordinary offhand, retains wrong-class weapons grey")
    context(1, "offhand", nil, greatsword)
    check(hasWearability(shield, true) and hasWearability(tome, false) and not contains(sword),
        "nondual offhand is ordinary offhand only, including wrong-class grey items")

    context(18, "offhand", same, nil)
    check(hasWearability(rapier, false) and hasWearability(seqByTemplate.O1, false),
        "same dual without main retains both weapon and ordinary offhand grey")
    context(18, nil, same, nil)
    check(hasWearability(rapier, true) and #grids.getEquipList() == seq,
        "nil slot retains all inventory, legal same-dual weapon uses natural main")
    context(18, "offhand", same, rapier)
    check(hasWearability(rapier, true) and hasWearability(dagger, false) and hasWearability(seqByTemplate.O1, false),
        "same dual retains mismatched onehand and ordinary offhand grey")
    context(18, "weapon", same, rapier, rapier)
    check(hasWearability(rapier, true) and hasWearability(dagger, false),
        "same dual main replacement retains wrong existing-offhand type grey")
    context(1, "offhand", different, sword)
    check(hasWearability(axe, true) and hasWearability(sword, false) and hasWearability(shield, false)
        and hasWearability(seqByTemplate.W31, false) and not contains(greatsword),
        "different dual offhand adds all onehands, wrong type/class and ordinary offhand grey, twohand excluded")
    context(1, "weapon", different, sword, axe)
    check(hasWearability(sword, true) and hasWearability(axe, false) and hasWearability(greatsword, true),
        "different dual main replacement retains mismatched onehand grey, twohand stays legal")
    context(1, nil, different, sword, axe)
    check(#grids.getEquipList() == seq and hasWearability(sword, true) and hasWearability(axe, false)
        and hasWearability(shield, false) and hasWearability(greatsword, true),
        "nil slot retains full inventory and marks natural-slot incompatibility grey")

    -- 全模板 × 上下文 × 六个目标槽 + natural，对照真实 applyEquip 的返回值和错误。
    -- 仅测试 oracle 深拷贝；生产预检没有 inventory 拷贝、applyEquip 或 print 替换。
    local contexts = {
        { hero = 1 }, { hero = 2 }, { hero = 3 }, { hero = 4 }, { hero = 9 },
        { hero = 18, branch = same }, { hero = 18, branch = same, main = rapier },
        { hero = 18, branch = same, main = rapier, off = dagger },
        { hero = 1, branch = different }, { hero = 1, branch = different, main = sword },
        { hero = 1, branch = different, main = sword, off = axe },
        { hero = 1, main = greatsword }, { hero = 1, level = 84 }, { hero = 999 },
    }
    for _, hid in ipairs(HC.getAllIds()) do
        contexts[#contexts + 1] = { hero = hid }
    end
    local comparisons, mismatches = 0, 0
    for _, c in ipairs(contexts) do
        context(c.hero, nil, c.branch, c.main, c.off, c.level)
        -- 数字和字符串的 inventory / equipped / roster key 交替覆盖。
        if comparisons % 2 == 0 then
            fake.equipped[c.hero] = fake.equipped[tostring(c.hero)]
            fake.equipped[tostring(c.hero)] = nil
            heroes.roster[c.hero] = heroes.roster[tostring(c.hero)]
            heroes.roster[tostring(c.hero)] = nil
            if c.main then fake.equipped[c.hero].weapon = tostring(c.main) end
            if c.off then fake.equipped[c.hero].offhand = tostring(c.off) end
        end
        local before, beforeHeroes = deepCopy(fake), deepCopy(heroes)
        local checker = Wearability.createChecker(fake, c.hero, heroes)
        ---@type table<string, table<number, {ok:boolean, err:string|nil}>>
        local expectedBySlot = {}
        for eqSeq, equip in pairs(fake.inventory) do
            local natural = EC.ITEMS[equip.templateId].slot
            for i = 1, #EC.SLOTS + 1 do
                local slot = EC.SLOTS[i]
                local previewOk, previewErr = checker(eqSeq, slot)
                local probe = equipProbe(fake, eqSeq, c.hero)
                local actualOk, actualErr = ES.applyEquip(probe, eqSeq, c.hero, slot or natural, heroes)
                local slotKey = slot or "natural"
                expectedBySlot[slotKey] = expectedBySlot[slotKey] or {}
                expectedBySlot[slotKey][tonumber(eqSeq)] = { ok = actualOk, err = actualErr }
                comparisons = comparisons + 1
                if previewOk ~= actualOk or previewErr ~= actualErr then
                    mismatches = mismatches + 1
                    print("[FAIL] parity " .. tostring(c.hero) .. " " .. equip.templateId .. " "
                        .. tostring(slot) .. " preview=" .. tostring(previewErr) .. " actual=" .. tostring(actualErr))
                end
            end
        end
        -- 现在名单只做部位结构筛选；真实 applyEquip 结果必须反映为每项标记与原因。
        local allListsAgree, listComparisons = true, 0
        local dualMode = AC.getDualWieldMode(c.branch)
        for i = 1, #EC.SLOTS + 1 do
            filterSlot = EC.SLOTS[i]
            local expected = expectedBySlot[filterSlot or "natural"]
            local structurallyExpected, n = {}, 0
            for eqSeq, equip in pairs(before.inventory) do
                local tpl = EC.ITEMS[equip.templateId]
                local slotOk = not filterSlot or tpl.slot == filterSlot
                    or (filterSlot == "offhand" and dualMode and tpl.slot == "weapon" and tpl.grip == "onehand")
                if slotOk then structurallyExpected[tonumber(eqSeq)] = true; n = n + 1 end
            end
            local list, seen = grids.getEquipList(), {}
            if #list ~= n then allListsAgree = false end
            for _, equip in ipairs(list) do
                local result = expected[equip.seq]
                listComparisons = listComparisons + 1
                if not structurallyExpected[equip.seq] or seen[equip.seq] or not result
                    or equip.canWear ~= result.ok or equip.cannotEquipReason ~= result.err then
                    allListsAgree = false
                end
                seen[equip.seq] = true
            end
            for id in pairs(structurallyExpected) do if not seen[id] then allListsAgree = false end end
        end
        check(allListsAgree, "all-slot lists retain structural set and match applyEquip flags/reasons, hero="
            .. c.hero .. " items=" .. listComparisons)
        check(deepEqual(fake, before) and deepEqual(heroes, beforeHeroes),
            "all preview/list calls leave nested source unchanged, hero=" .. c.hero)
    end
    check(comparisons > 10000 and mismatches == 0, "full applyEquip parity: " .. comparisons .. " checks, mismatches=" .. mismatches)
    context(1, "offhand", different, sword)
    fake.inventory[sword] = fake.inventory[tostring(sword)]
    fake.inventory[tostring(sword)] = nil
    fake.equipped = { [1] = { weapon = tostring(sword) } }
    heroes.roster[1] = heroes.roster["1"]; heroes.roster["1"] = nil
    local keyedBefore = deepCopy(fake)
    local keyChecker = Wearability.createChecker(fake, "1", heroes)
    local keyOk, keyErr = keyChecker(tostring(axe), "offhand")
    local actualKeyOk, actualKeyErr = ES.applyEquip(equipProbe(fake, axe, 1), axe, 1, "offhand", heroes)
    check(keyOk == actualKeyOk and keyErr == actualKeyErr and hasWearability(axe, true),
        "numeric inventory, string main seq and string hero id match actual applyEquip")
    check(deepEqual(fake, keyedBefore), "mixed-key lookup never hydrates source")

    context(1, "armor", nil)
    quality, setTemplate = 1, "A31"
    check(#grids.getEquipList() == 0, "quality AND template still filter candidates structurally")
    quality = 2
    check(#grids.getEquipList() == 1 and hasWearability(seqByTemplate.A31, true), "quality AND set AND armor includes wearable item")
    setTemplate = "A55"
    check(#grids.getEquipList() == 1 and hasWearability(seqByTemplate.A55, false),
        "quality AND set AND armor keeps selected unwearable item grey")
    filterSlot = "helmet"
    check(#grids.getEquipList() == 0, "slot AND quality AND set rejects wrong natural slot even if unwearable")
    filterSlot = "armor"; quality = 1
    check(#grids.getEquipList() == 0, "quality can hide grey candidate without altering its wearability")
    quality, setTemplate, filterSlot, filterHero = nil, nil, nil, nil
    local ordinaryList, allNormal = grids.getEquipList(), true
    for _, equip in ipairs(ordinaryList) do
        if equip.canWear ~= true or equip.cannotEquipReason ~= nil then allNormal = false end
    end
    check(#ordinaryList == seq and allNormal, "manual warehouse without hero retains complete inventory with no grey flags")
    quality, setTemplate = 2, "A55"
    check(#grids.getEquipList() == 1 and hasWearability(seqByTemplate.A55, true),
        "manual warehouse still honors quality/set but ignores class compatibility")
    quality, setTemplate = 1, nil
    check(#grids.getEquipList() == 0, "manual no-hero quality filter remains active")
    quality, setTemplate = nil, nil
    check(HC.get(1) ~= nil, "uses real hero configuration")
end

-- 独立计数夹具：恢复原 inventory/equipped/roster 引用及筛选，后续 source parity 不受影响。
local function runSetCounts()
    local SetConfig = require("config.EquipmentSetConfig")
    local savedInventory, savedEquipped, savedRoster = fake.inventory, fake.equipped, heroes.roster
    local savedSlot, savedHero, savedQuality, savedSet = filterSlot, filterHero, quality, setTemplate
    local original, originalHeroes = deepCopy(fake), deepCopy(heroes)
    local templatesBefore = deepCopy(EC.ITEMS)
    fake.inventory = deepCopy(savedInventory)
    local ok, err = pcall(function()
        local sword, axe = seqByTemplate.W1, seqByTemplate.W13
        context(1, nil, nil, sword, nil, 84)
        fake.inventory[tostring(seqByTemplate.A55)].locked = true
        local source, roster = deepCopy(fake), deepCopy(heroes)
        -- oracle 只读真实模板；不借用生产列表/计数实现。
        local function expectedCounts(allowOnehand)
            local counts = { none = 0 }
            for _, id in ipairs(SetConfig.orderedSetIds()) do counts[id] = 0 end
            for _, equip in pairs(fake.inventory) do
                local tpl = EC.ITEMS[equip.templateId]
                if tpl and (not quality or (equip.quality or tpl.quality or 1) == quality)
                    and (not filterSlot or tpl.slot == filterSlot
                        or (allowOnehand and filterSlot == "offhand" and tpl.slot == "weapon" and tpl.grip == "onehand")) then
                    local id = SetConfig.getSetIdForTemplate(tpl) or "none"
                    counts[id] = counts[id] + 1
                end
            end
            return counts
        end
        local function agrees(allowOnehand, label)
            local actual = grids.getSetCounts()
            check(deepEqual(actual, expectedCounts(allowOnehand)), label)
            return actual
        end
        local all = agrees(false, "set counts cover complete base inventory, including grey/locked/equipped")
        local total = all.none
        check(all.none > 0, "none counts real templates without set affiliation")
        for _, id in ipairs(SetConfig.orderedSetIds()) do
            check(all[id] > 0, "every set has its instance count: " .. id)
            total = total + all[id]
        end
        check(total == #grids.getEquipList() and hasWearability(seqByTemplate.A55, false)
            and fake.inventory[tostring(seqByTemplate.A55)].locked
            and fake.equipped["1"].weapon == sword,
            "counts do not remove level/class grey, locked or already-equipped candidates")
        check(deepEqual(fake, source) and deepEqual(heroes, roster), "counting leaves slim nested equipment and hero data read-only")

        quality = 1
        local zero = agrees(false, "unmatched quality gives explicit zeros for every set and none")
        local allZero = true
        for _, value in pairs(zero) do if value ~= 0 then allZero = false end end
        check(allZero, "empty quality result keeps every count key at zero")
        local helmetSeq
        for tid, tpl in pairs(EC.ITEMS) do
            if tpl.slot == "helmet" then helmetSeq = seqByTemplate[tid]; break end
        end
        check(helmetSeq ~= nil, "count fixture has a real helmet")
        fake.inventory[tostring(helmetSeq)].quality = 3
        fake.inventory[tostring(seqByTemplate.A31)].quality = 3
        fake.inventory[tostring(seqByTemplate.A55)].quality = 3
        quality, filterSlot = 3, "helmet"
        local helmets = agrees(false, "quality AND helmet counts only the selected-quality helmet")
        local helmetTotal = 0
        for _, value in pairs(helmets) do helmetTotal = helmetTotal + value end
        check(helmetTotal == 1, "quality AND slot never unions other-quality helmets or same-quality armor")
        filterSlot = "armor"
        agrees(false, "quality AND armor retains legal and wrong-class grey candidates")
        filterSlot = "weapon"
        local weapons = agrees(false, "quality AND weapon rejects same-quality nonweapon items")
        check(deepEqual(weapons, zero), "disjoint quality/slot combination is all zero")

        context(1, "offhand", nil, sword)
        quality = 2
        local ordinary = agrees(false, "ordinary offhand counts exclude mainhand weapons")
        context(1, "offhand", { first = 104, second = 207 }, sword)
        quality = 2
        local dual = agrees(true, "different dual offhand extends counts to every onehand, never twohand")
        local ordinaryTotal, dualTotal, onehands = 0, 0, 0
        for _, value in pairs(ordinary) do ordinaryTotal = ordinaryTotal + value end
        for _, value in pairs(dual) do dualTotal = dualTotal + value end
        for _, tpl in pairs(EC.ITEMS) do
            if tpl.slot == "weapon" and tpl.grip == "onehand" then onehands = onehands + 1 end
        end
        check(dualTotal == ordinaryTotal + onehands and hasWearability(axe, true)
            and hasWearability(sword, false) and not contains(seqByTemplate.W7),
            "dual counts add mismatched/grey onehands as base candidates but no twohands")
        context(18, "offhand", { first = 110, second = 220 }, nil)
        quality = 2
        check(deepEqual(grids.getSetCounts(), dual), "same dual without main counts same base candidates despite all-grey offhands")

        context(1, nil, nil)
        local unselected = grids.getSetCounts()
        local selectedSets = {}
        for tid, tpl in pairs(EC.ITEMS) do
            local id = SetConfig.getSetIdForTemplate(tpl) or "none"
            if not selectedSets[id] then
                selectedSets[id] = true
                setTemplate = tid
                check(deepEqual(grids.getSetCounts(), unselected), "setChecked never restricts count rows: " .. id)
            end
        end
        setTemplate = "unknown_template"
        check(#grids.getEquipList() == 0 and deepEqual(grids.getSetCounts(), unselected),
            "even setChecked rejecting every item leaves base counts unchanged")
        setTemplate = nil
        fake.inventory["100001"] = { templateId = "unknown_template", quality = 2, slot = "weapon", type = "sword", grip = "onehand" }
        fake.inventory[100002] = { templateId = "another_unknown", quality = 2, affixes = { { value = "9" } } }
        check(deepEqual(grids.getSetCounts(), unselected), "unknown templates skipped even with matching fields or slim data")
        fake.inventory["100003"] = deepCopy(fake.inventory[tostring(sword)] or fake.inventory[sword])
        local swordSet = SetConfig.getSetIdForTemplate(EC.ITEMS.W1) or "none"
        local added = grids.getSetCounts()
        check(added[swordSet] == unselected[swordSet] + 1, "inventory insertion refreshes instance count without rebinding")
        fake.inventory["100003"] = nil
        check(deepEqual(grids.getSetCounts(), unselected), "inventory removal refreshes counts without reopening")
        local finalSource, finalHeroes = deepCopy(fake), deepCopy(heroes)
        grids.getSetCounts(); grids.getEquipList(); grids.getSetCounts()
        local slim = true
        for key, equip in pairs(fake.inventory) do
            if key ~= "100001" and (equip.slot ~= nil or equip.type ~= nil or equip.grip ~= nil) then slim = false end
        end
        check(slim and deepEqual(fake, finalSource) and deepEqual(heroes, finalHeroes)
            and deepEqual(EC.ITEMS, templatesBefore), "repeated counting/list projection never hydrates slim equipment or mutates snapshots/templates")
    end)
    fake.inventory, fake.equipped, heroes.roster = savedInventory, savedEquipped, savedRoster
    filterSlot, filterHero, quality, setTemplate = savedSlot, savedHero, savedQuality, savedSet
    check(deepEqual(fake, original) and deepEqual(heroes, originalHeroes), "set-count fixture restores original filter/source parity state")
    if not ok then error(err) end
end

local function runSourceParity()
    context(1, "armor", nil)
    setTemplate = "A31"
    local list, before = grids.getEquipList(), deepCopy(fake)
    local pointer = Link.bind({ state = gridState, GRID = GRID, CELL_COL_CX = cells,
        EquipmentDetail = Detail, DrawUtil = Draw, getEquipList = grids.getEquipList })
    local x, y = cells[1], GRID.FIRST_ROW_TOP + GRID.CELL_SIZE * 0.5
    local cell = pointer.cellAt(x, y)
    local peek = pointer.peekEquipAt(x, y)
    check(#list == 1 and cell and peek and cell.seq == list[1].seq and peek.seq == list[1].seq,
        "cellAt/peek share filtered grid list")
    pointer.openCandidate(cell, x, y, true)
    check(detailState.seq == list[1].seq and Detail.isPinned(), "click/open candidate resolves same filtered item")
    Detail.close()
    pointer.handleHover(x, y); clock.elapsedTime = clock.elapsedTime + 1; pointer.handleHover(x, y)
    check(detailState.seq == list[1].seq and Detail.isOpen(), "hover resolves same filtered item")
    Detail.close()
    check(pointer.cellAt(cells[2], y) == nil and pointer.peekEquipAt(cells[2], y) == nil,
        "structurally filtered-out cell has no click/peek target")

    -- native nvgRGBA 保留：只在 fillColor stub 读取 NVGcolor，避免污染全工作区颜色类型。
    local painted, events, masks = {}, {}, {}
    local pathRect = {}
    local greyFill = false
    local function record(kind) events[#events + 1] = kind end
    local iconCache = require("ui.widget.ImageCache")
    iconCache.getEquipIcon = function(tid) painted[#painted + 1] = tid; record("icon"); return 1 end
    local dark = require("core.DarkIcon")
    dark.drawQualityBg = function() record("quality") end
    dark.drawIconDark = function() record("iconDraw") end
    Draw.drawImageCentered = function() record("lock") end
    local heroFrame = require("ui.widget.HeroFrame")
    heroFrame.draw = function() record("ownerBadge") end
    package.preload["systems.TutorialManager"] = function() return { isActive = function() return false end } end
    nvgSave, nvgRestore, nvgScissor, nvgTranslate = function() end, function() end, function() end, function() end
    nvgBeginPath = function() pathRect = {} end
    nvgRoundedRect = function(_, rx, ry, w, h, radius)
        pathRect = { x = rx, y = ry, w = w, h = h, radius = radius }
    end
    ---@param color NVGcolor
    nvgFillColor = function(_, color)
        greyFill = math.abs(color.r * 255 - 38) < 0.01 and math.abs(color.g * 255 - 38) < 0.01
            and math.abs(color.b * 255 - 38) < 0.01 and math.abs(color.a * 255 - 175) < 0.01
    end
    nvgFill = function()
        if greyFill then record("greyMask"); masks[#masks + 1] = { rect = pathRect, eventIndex = #events } end
    end
    nvgStroke, nvgStrokeColor, nvgStrokeWidth = function() end, function() end, function() end
    nvgFontFace, nvgFontSize, nvgTextAlign = function() end, function() end, function() end
    nvgText = function() record("text") end
    local function drawOnce()
        painted, events, masks = {}, {}, {}
        pathRect, greyFill = {}, false
        grids.drawEquipGrid({})
    end
    drawOnce()
    check(#painted == 1 and painted[1] == list[1].templateId and #masks == 0,
        "wearable A31 draw matches click/hover/peek and has no grey overlay")
    check(deepEqual(fake, before), "draw/click/hover/peek do not hydrate or change source")

    setTemplate = "A55"
    list = grids.getEquipList()
    cell, peek = pointer.cellAt(x, y), pointer.peekEquipAt(x, y)
    check(#list == 1 and cell and cell.canWear == false and peek and peek.seq == list[1].seq,
        "unwearable A55 remains cellAt/peek target with grey flag")
    pointer.openCandidate(cell, x, y, true)
    check(detailState.seq == list[1].seq and Detail.isPinned(), "unwearable grey item can open and pin detail")
    Detail.close()
    pointer.handleHover(x, y); clock.elapsedTime = clock.elapsedTime + 1; pointer.handleHover(x, y)
    check(detailState.seq == list[1].seq and Detail.isOpen(), "unwearable grey item can hover-open detail")
    Detail.close()
    local actualOk, actualErr = ES.applyEquip(equipProbe(fake, list[1].seq, 1), list[1].seq, 1, "armor", heroes)
    check(actualOk == false and actualErr == list[1].cannotEquipReason,
        "grey display never relaxes real applyEquip rejection")
    check(deepEqual(fake, before), "unwearable click/hover/peek and applyEquip probe leave source unchanged")

    -- 人为准备锁、提升角标、归属角标；只读路径仍不得回写此快照。
    local greySeq = list[1].seq
    fake.inventory[tostring(greySeq)].locked = true
    fake.inventory[tostring(greySeq)].enhanceLevel = 5
    fake.equipped[99].armor = greySeq
    drawingHeroIcons, drawingLock = { [99] = 1 }, 1
    before = deepCopy(fake)
    drawOnce()
    check(#painted == 1 and painted[1] == "A55" and #masks == 1,
        "unwearable A55 draws exactly one RGBA(38,38,38,175) grey mask")
    local mask = masks[1]
    local rect = mask and mask.rect
    check(rect and rect.x == x - GRID.CELL_SIZE * 0.5 and rect.y == GRID.FIRST_ROW_TOP
        and rect.w == GRID.CELL_SIZE and rect.h == GRID.CELL_SIZE and rect.radius == GRID.CELL_RADIUS + 6,
        "grey mask covers full cell with same rounded corners")
    local positions = {}
    for index, event in ipairs(events) do positions[event] = index end
    if not positions.ownerBadge or not positions.lock then
        print("[greyMask order] " .. table.concat(events, ","))
    end
    check(mask and positions.quality and positions.iconDraw and positions.text and positions.ownerBadge and positions.lock
        and mask.eventIndex > positions.quality and mask.eventIndex > positions.iconDraw
        and mask.eventIndex > positions.text and mask.eventIndex > positions.ownerBadge and mask.eventIndex > positions.lock,
        "full-card grey mask is drawn after icon, level/enhance text, owner badge and lock")
    check(deepEqual(fake, before), "grey draw never modifies nested equipment source")
    filterHero = nil
    drawOnce()
    check(#painted == 1 and painted[1] == "A55" and hasWearability(greySeq, true) and #masks == 0,
        "manual no-hero A55 draw has no grey mask, even with lock and owner badge")
    filterHero, setTemplate = 1, "A31"
    heroes.roster["1"].level = 84
    drawOnce()
    check(hasWearability(seqByTemplate.A31, false) and #masks == 1, "level-gated A31 draws grey before upgrade")
    heroes.roster["1"].level = 85
    drawOnce()
    check(hasWearability(seqByTemplate.A31, true) and #masks == 0, "upgrade refresh removes A31 grey mask without reopening")
    check(deepEqual(fake, before), "manual and upgrade redraws leave inventory unchanged")
end

function Start()
    runIndependent("detailed_filters", runDetailedFilters)
    runIndependent("shared_reentry", runSharedReentry)
    local ok, err = pcall(function() runLifecycle(); runTutorialEnsure(); runFilter(); runSetCounts(); runSourceParity() end)
    if not ok then failures = failures + 1; print("[FAIL] exception: " .. tostring(err)) end
    print("[backpack_equip_link_test] " .. (failures == 0 and "ALL PASS" or "FAILURES=" .. failures) .. " (" .. passes .. " assertions)")
    engine:Exit()
end
