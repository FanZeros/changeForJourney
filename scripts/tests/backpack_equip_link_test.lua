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
local filterDialog = { NONE_KEY = "none", isOpen = function() return false end, close = function() end }
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
    local ok, err = pcall(function() runLifecycle(); runFilter(); runSetCounts(); runSourceParity() end)
    if not ok then failures = failures + 1; print("[FAIL] exception: " .. tostring(err)) end
    print("[backpack_equip_link_test] " .. (failures == 0 and "ALL PASS" or "FAILURES=" .. failures) .. " (" .. passes .. " assertions)")
    engine:Exit()
end
