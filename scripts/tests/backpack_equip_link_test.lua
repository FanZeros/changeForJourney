-- Mock 回归：仓库持有/配装筛选/锻炉交接，无需真实绘图或存档。
-- .cli/UrhoXRuntime scripts/tests/backpack_equip_link_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
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
local GRID = { FIRST_ROW_TOP = 470, CLIP_BOTTOM = 1980, CELL_SIZE = 160, GAP = 30, COLS = 5 }
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
local AVC = require("config.AdvancementConfig")
local fake = { inventory = {}, equipped = {} }
local heroId, weaponType
for _, hid in ipairs(HC.getAllIds()) do
    local cfg = HC.get(hid)
    if cfg and cfg.weaponTypes and #cfg.weaponTypes > 1 then heroId, weaponType = hid, cfg.weaponTypes[1]; break end
end
local sameBranch, diffBranch
for id in pairs(AVC.BRANCHES) do
    local branch = { second = id }
    if AVC.getDualWieldMode(branch) == "same" then sameBranch = branch end
    if AVC.getDualWieldMode(branch) == "different" then diffBranch = branch end
end
local heroes = { roster = {} }
Store.Get = function(key) if key == "equipment" then return fake elseif key == "heroes" then return heroes end end
local filterSlot, filterHero, quality, setTemplate = nil, nil, nil, nil
local Grids = require("ui.backpack.BackpackGrids")
local grids = Grids.bind({ GRID = GRID, CELL_COL_CX = cells, DESIGN_W = 1080,
    state = { scrollY = 0 }, ITEM_DEFS = {},
    qualityChecked = function(q) return not quality or q == quality end,
    setChecked = function(tid) return not setTemplate or tid == setTemplate end,
    getEquipmentSlotFilter = function() return filterSlot, filterHero end,
})
local function runFilter()
    check(heroId ~= nil, "found hero with multiple legal weapon types")
    check(sameBranch ~= nil and diffBranch ~= nil, "found both dual-wield branches")
    local seq = 0
    local sameSeq, diffSeq
    for tid, tpl in pairs(EC.ITEMS) do
        if tpl.slot == "offhand" or tpl.slot == "armor" or tpl.slot == "helmet" or
            (tpl.slot == "weapon" and (tpl.grip == "onehand" or tpl.grip == "twohand")) then
            seq = seq + 1
            local equip = ES.generate(tid, 85, (seq % 2) + 1)
            equip.seq = seq
            fake.inventory[tostring(seq)] = equip
            if tpl.slot == "weapon" and tpl.grip == "onehand" then
                if tpl.type == weaponType then sameSeq = seq
                elseif ES.getWearableTypeSet(heroId, "weapon")[tpl.type] then diffSeq = seq end
            end
        end
    end
    check(sameSeq ~= nil and diffSeq ~= nil, "fixture has legal same/different onehand weapons")
    filterSlot, filterHero = nil, heroId
    local all = grids.getEquipList()
    check(#all == seq, "nil filter means every item")
    check(all[1].slot ~= nil, "eqItem carries hydrated slot")
    fake.equipped[heroId] = { weapon = sameSeq }
    heroes.roster[heroId] = { advBranch = sameBranch }
    filterSlot = "offhand"
    local list, foundNormal, foundSame = grids.getEquipList(), false, false
    for _, equip in ipairs(list) do
        if equip.slot == "offhand" then foundNormal = true end
        if equip.slot == "weapon" then foundSame = true; check(equip.grip == "onehand" and equip.type == weaponType,
            "same branch only legal same-type onehand") end
    end
    check(foundNormal and foundSame, "offhand includes normal offhands AND legal dual-wield weapon")
    heroes.roster[heroId].advBranch = diffBranch
    list = grids.getEquipList()
    for _, equip in ipairs(list) do
        if equip.slot == "weapon" then check(equip.type ~= weaponType and equip.grip == "onehand", "different branch candidate rule") end
    end
    heroes.roster[heroId].advBranch = nil
    for _, equip in ipairs(grids.getEquipList()) do check(equip.slot == "offhand", "nondual hero has no weapon in offhand filter") end
    filterSlot, quality = "armor", 2
    for _, equip in ipairs(grids.getEquipList()) do check(equip.slot == "armor" and equip.quality == 2, "slot AND quality") end
    local selected = grids.getEquipList()[1]
    check(selected ~= nil, "quality filtered armor fixture nonempty")
    setTemplate = selected and selected.templateId
    for _, equip in ipairs(grids.getEquipList()) do check(equip.templateId == setTemplate and equip.slot == "armor" and equip.quality == 2,
        "slot AND quality AND set predicate") end
end

function Start()
    local ok, err = pcall(function() runLifecycle(); runFilter() end)
    if not ok then failures = failures + 1; print("[FAIL] exception: " .. tostring(err)) end
    print("[backpack_equip_link_test] " .. (failures == 0 and "ALL PASS" or "FAILURES=" .. failures) .. " (" .. passes .. " assertions)")
    engine:Exit()
end
