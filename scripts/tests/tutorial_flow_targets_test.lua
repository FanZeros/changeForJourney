-- Tutorial target-chain regression; real modules, mocked rendering and action bridge.
-- .cli/UrhoXRuntime tests/tutorial_flow_targets_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local passes, failures = 0, 0
local function check(ok, label)
    if ok then passes = passes + 1; print("[PASS] " .. label)
    else failures = failures + 1; print("[FAIL] " .. label) end
end
local testStubs = {}
local originalRequire = require
-- Runtime 的资源 require 不保证使用 package.preload，显式拦截测试依赖。
require = function(name)
    if testStubs[name] then return testStubs[name] end
    return originalRequire(name)
end
local function stub(name, value)
    testStubs[name] = value
    package.loaded[name] = value
    package.preload[name] = function() return value end
end
local function noop() end
local clock = { elapsedTime = 20 }
time = clock
local events, hotspots = {}, {}
local tutorialState = { active = true, preferred = "equip", heroId = 99 }
local tutorial = {
    isActive = function() return tutorialState.active end,
    getPreferredCharacterTab = function() return tutorialState.preferred end,
    setNewHeroId = function(id) tutorialState.heroId = id end,
    notifyEvent = function(event) events[#events + 1] = event end,
    registerHotspot = function(key, cx, cy, w, h, panel)
        hotspots[#hotspots + 1] = { key = key, cx = cx, cy = cy, w = w, h = h, panel = panel }
    end,
}
stub("systems.TutorialManager", tutorial)
local function resetEvents() events = {} end
local function eventCount(name)
    local n = 0
    for _, event in ipairs(events) do if event == name then n = n + 1 end end
    return n
end
local draw = { hitTest = function(x, y, cx, cy, w, h)
    return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
end, drawImageCentered = noop, seamSlideX = function() return 0 end }
stub("core.DrawUtil", draw)
stub("core.DarkIcon", { drawQualityBg = noop, drawIconDark = noop, drawNine = noop })
stub("systems.GameSFX", { play = noop, playUIMove = noop })
stub("ui.widget.SetFilterDialog", { isOpen = function() return false end })
stub("ui.widget.ImageCache", { getEquipIcon = function() return -1 end })
stub("ui.widget.HeroFrame", { draw = noop })
stub("ui.widget.EquipmentSetIcon", {
    drawBadge = noop, hasBadge = function() return false end,
    badgeLayout = function(cx, cy) return { x = cx - 20, y = cy, size = 20 } end,
    levelLayout = function(_, cx, cy) return { x = cx + 30, y = cy, fontSize = 20, align = 0 } end,
})
stub("ui.character.panel.CharacterPanel", { getShards = function() return 0 end })
stub("config.GameConfig", { Design = { WIDTH = 1080, HEIGHT = 2400 } })
stub("core.GameState", {})
stub("config.HeroConfig", { get = function() return { name = "Test hero" } end,
    getAllIds = function() return {} end })
stub("config.AdvancementConfig", { getDualWieldMode = function() return nil end })
local inventoryState = { inventory = {}, equipped = {} }
stub("core.PlayerStore", { Get = function(key)
    if key == "equipment" then return inventoryState end
    if key == "heroes" then return { roster = { [1] = { level = 10 } } } end
end })
stub("config.EquipmentConfig", { ITEMS = {
    W1 = { slot = "weapon", name = "Sword" }, A1 = { slot = "armor", name = "Armor" },
} })
local wearability = {
    getFields = function(item) return item.slot, "sword", "onehand", item.level or 1 end,
    canEquip = function(data, seq)
        local item = data.inventory[tostring(seq)]
        return item and item.allowed == true, "not wearable"
    end,
    createChecker = function(data)
        return function(seq) return data.inventory[tostring(seq)].allowed == true end
    end,
}
stub("ui.character.detail.EquipmentWearability", wearability)
local candidate = { open = false }
local equipmentDetail = {
    open = function(seq, slot, hero, compact, owner)
        candidate = { open = true, seq = seq, slot = slot, hero = hero, compact = compact, owner = owner }
    end,
    getOwner = function() return candidate.owner end,
    getSelection = function() return candidate end,
    isOpen = function() return candidate.open end,
    pin = noop, close = function() candidate.open = false end, dismissHover = noop,
}
stub("ui.character.equip.EquipmentDetail", equipmentDetail)
nvgSave, nvgRestore, nvgScissor, nvgTranslate = noop, noop, noop, noop
nvgBeginPath, nvgRoundedRect, nvgFillColor, nvgFill = noop, noop, noop, noop
nvgStrokeColor, nvgStrokeWidth, nvgStroke = noop, noop, noop
nvgFontFace, nvgFontSize, nvgTextAlign, nvgText = noop, noop, noop, noop
nvgTextBounds = function() return 40 end

local function testConfig()
    local config = require("config.TutorialConfig")
    check(#config[1].steps == 3 and config[1].steps[3].advanceOn == "equipment_equipped",
        "group1 teaches existing shortcut and waits for successful equip")
    check(config[1].steps[3].highlight == "equip_item_gifted"
        and config[1].steps[3].text:find("双击", 1, true)
        and config[1].steps[3].text:find("右键", 1, true), "shortcut hint has both supported actions")
    check(config[2].steps[2].advanceOn == "equipment_equipped", "group2 waits for auto-equip success")
    check(config[8].steps[1].advanceOn == "gacha10_started"
        and config[8].steps[2].advanceOn == "gacha10_complete", "group8 waits for actual request, not click")
end

local function testCharacterTab()
    stub("config.ClassConfig", {})
    stub("systems.AttributeDef", {})
    stub("config.ExpTable", {})
    stub("systems.EquipmentSystem", {})
    stub("systems.ButtonFeedback", { trigger = noop })
    stub("ui.character.equip.EquipmentBag", {})
    stub("ui.character.detail.CharacterDetailAttrs", { collectAttributes = function() return {} end })
    stub("ui.character.detail.CharacterDetailDraw", { SIDE_CARD_W = 100, SIDE_CARD_H = 100 })
    stub("ui.character.hero.AwakeningPanel", { reset = noop })
    stub("ui.character.detail.CharacterDetailEquip", { reset = noop, endSideDrag = noop })
    stub("ui.character.hero.HeroScenario", { onOpenHero = noop, onRecruitResults = noop })
    local warehouse = { acquired = 0, released = 0 }
    stub("ui.backpack.BackpackPanel", {
        acquireForEquipment = function() warehouse.acquired = warehouse.acquired + 1 end,
        releaseForEquipment = function() warehouse.released = warehouse.released + 1 end,
        setEquipmentSlotFilter = noop,
    })
    local detail = require("ui.character.detail.CharacterDetail")
    detail.open(1)
    check(detail.isEquipTab() and warehouse.acquired == 1, "tutorial default opens equip and acquires warehouse")
    detail.open(1, "attr")
    check(not detail.isEquipTab() and warehouse.released == 1, "explicit attr wins over tutorial preference")
    detail.open(1, "awaken")
    check(not detail.isEquipTab(), "explicit awaken stays unchanged")
    tutorialState.preferred = nil
    detail.open(1)
    check(not detail.isEquipTab(), "non-tutorial default stays attr")
    tutorialState.preferred = "equip"
end

local GRID = { COLS = 1, CELL_SIZE = 80, CELL_RADIUS = 6, GAP = 20,
    FIRST_ROW_TOP = 100, CLIP_BOTTOM = 310 }
local function testGridTargets()
    local state = { scrollY = 0, closing = false }
    local filter = { slot = "weapon", hero = 1, left = true }
    local grids = require("ui.backpack.BackpackGrids").bind({
        GRID = GRID, CELL_COL_CX = { 60 }, DESIGN_W = 200, state = state, ITEM_DEFS = {},
        getEquipmentSlotFilter = function() return filter.slot, filter.hero end,
        isLeftMode = function() return filter.left end,
        getImgHeroIcons = function() return {} end, getImgLock = function() return -1 end,
        calcScrollMax = function() return 1000 end, clampScroll = noop,
    })
    local function render()
        hotspots = {}
        grids.drawEquipGrid({})
        return hotspots[1]
    end
    inventoryState.inventory = {}
    check(render() == nil, "empty warehouse never advertises a tutorial cell")
    inventoryState.inventory = {
        ["1"] = { templateId = "W1", slot = "weapon", quality = 3, allowed = false },
        ["2"] = { templateId = "W1", slot = "weapon", quality = 2, allowed = true },
        ["3"] = { templateId = "W1", slot = "weapon", quality = 1, allowed = true },
    }
    local hs = render()
    check(hs and #hotspots == 1 and hs.cy == 240 and hs.panel == "left",
        "first legal visible weapon chosen once in actual left warehouse")
    state.scrollY = 120
    hs = render()
    check(hs and hs.cy == 220 and hs.cy - hs.h * 0.5 >= GRID.FIRST_ROW_TOP
        and hs.cy + hs.h * 0.5 <= GRID.CLIP_BOTTOM, "partially clipped cell skipped for fully visible successor")
    state.scrollY = 0
    filter.slot = nil
    check(render() == nil, "all-slot warehouse cannot advertise weapon tutorial target")
    filter.slot, filter.hero = "weapon", nil
    check(render() == nil, "no hero means no verified wearable target")
    filter.hero, filter.left = 1, false
    check(render() == nil, "inline/window warehouse cannot register left-panel hotspot")
    filter.left, state.closing = true, true
    check(render() == nil, "closing warehouse has no tutorial target")
    state.closing = false
end

local function testEquipEvents()
    local eq = { seq = 7, slot = "weapon" }
    inventoryState = { inventory = { ["7"] = { slot = "weapon", allowed = true } }, equipped = {} }
    local sends = 0
    local api = require("ui.backpack.BackpackEquipLink").bind({
        state = { open = true, tab = "equip", scrollY = 0 }, GRID = GRID, CELL_COL_CX = { 60 },
        getEquipList = function() return { eq } end, itemDetState = { open = false },
        getCharacterDetail = function() return {
            isEquipTab = function() return true end, getHeroId = function() return 1 end,
        } end,
        getEquipmentData = function() return inventoryState end, getHeroesData = function() return {} end,
        EquipmentWearability = wearability, toast = noop, markPanelDirty = noop,
        GameSFX = { play = noop }, sendAction = function() sends = sends + 1; return true end,
    })
    local action = require("shared.Protocol").ACTION_TYPES.EQUIP_ITEM
    local function receipt(success, seq, hero, slot)
        api.onActionResult({ action = action, seq = seq or 7, heroId = hero or 1,
            slot = slot or "weapon", success = success })
    end
    resetEvents()
    api.handleEquipClick(60, 140)
    check(sends == 0 and eventCount("equipment_equipped") == 0 and candidate.compact,
        "single candidate click never completes tutorial")
    clock.elapsedTime = clock.elapsedTime + 0.1
    api.handleEquipClick(60, 140)
    check(sends == 1 and eventCount("equipment_equipped") == 0, "double click sends but does not complete before receipt")
    receipt(true, 8); receipt(true, 7, 2); receipt(true, 7, 1, "offhand")
    check(eventCount("equipment_equipped") == 0, "unmatched seq/hero/slot cannot complete tutorial")
    receipt(false)
    check(eventCount("equipment_equipped") == 0, "matched failure cannot complete tutorial")
    api.handleRightClick(60, 140); receipt(true)
    check(eventCount("equipment_equipped") == 1, "matched right-click equip success completes tutorial once")
    receipt(true)
    check(eventCount("equipment_equipped") == 1, "duplicate receipt cannot complete next step")
    inventoryState.equipped = { [1] = { weapon = "7" } }
    api.handleRightClick(60, 140)
    check(sends == 2 and eventCount("equipment_equipped") == 2, "already equipped satisfies tutorial without another action")
end

local function testRecruitEvents()
    stub("config.GachaConfig", { Pity = { SSR_THRESHOLD = 100 } })
    stub("config.UrGachaConfig", {
        UI = { poolTabCx = 700, poolTabCy = 340 }, Pity = { UR_THRESHOLD = 100 },
        getTimeDisplayText = function() return "test" end, isPoolEnabled = function() return true end,
        checkPoolUnlocked = function() return true end, getUpPortraitPath = function() return "test.png" end,
    })
    stub("core.GameState", { getRecruitTicket = function() return 20 end, getGems = function() return 1000 end })
    stub("core.I18n", {})
    stub("runtime.ClientDispatcher", { get = function() return nil end, subscribe = noop })
    stub("ui.town.TownPageChrome", { easeOutCubic = function(t) return t end,
        easeInCubic = function(t) return t end, hitBack = function() return false end, hitTab = function() return nil end })
    local recruitState = { canPull = true, confirm = true, sendCount = 0, mode = "pending" }
    stub("systems.GachaSystem", { canPull = function() return recruitState.canPull, "ticket" end,
        getSSRPityRemain = function() return 100 end, setPityCounts = noop })
    local popupContext = {}
    stub("ui.tavern.TavernPopups", { init = noop, setContext = function(ctx)
        for k, v in pairs(ctx) do popupContext[k] = v end
    end, checkAndShowConfirm = function() return recruitState.confirm end,
        isBlocking = function() return false end, showFloatText = noop, recordHistory = noop,
        resetAll = noop, update = noop, formatGachaFailReason = function() return "failed" end })
    stub("ui.tavern.RecruitAnim", { init = noop, setOnAgain = noop, isPlaying = function() return false end,
        start = function(_, callback) callback() end, update = noop })
    stub("ui.tavern.TavernShopPage", { init = noop, resetScroll = noop, syncPurchasedFromStore = noop,
        isPendingBuy = function() return false end, update = noop })
    stub("ui.tavern.TargetRecruitPanel", { init = noop, isOpen = function() return false end })
    nvgCreateImage = function() return -1 end
    local tavern = require("ui.tavern.TavernPage")
    tavern.init({}); tavern.open()
    local action = require("shared.Protocol").ACTION_TYPES.GACHA_PULL
    tavern.setSendAction(function()
        recruitState.sendCount = recruitState.sendCount + 1
        check(events[#events] == "gacha10_started" and tutorialState.heroId == nil,
            "started and cleared target occur before synchronous dispatch")
        if recruitState.mode == "unhandled" then return false end
        if recruitState.mode == "sync" then
            tavern.onActionResult({ action = action, success = true,
                gachaResults = { { type = "hero", heroId = 6 } } })
        end
        return true
    end)
    resetEvents(); recruitState.confirm = false
    tavern.handleInput(766, 1902)
    check(#events == 0 and recruitState.sendCount == 0, "cancelled confirmation never starts waiting step")
    recruitState.confirm, recruitState.canPull = true, false
    tavern.handleInput(766, 1902)
    check(#events == 0 and recruitState.sendCount == 0, "insufficient resources never start waiting step")
    recruitState.canPull, recruitState.mode = true, "unhandled"
    tavern.handleInput(766, 1902)
    check(eventCount("gacha10_failed") == 1 and eventCount("gacha10_complete") == 0, "unhandled request emits failure immediately")
    resetEvents(); recruitState.mode = "pending"
    tavern.handleInput(766, 1902)
    tavern.onActionResult({ action = action, success = false, reason = "test" })
    check(eventCount("gacha10_failed") == 1, "failed receipt rolls tutorial back")
    resetEvents(); tavern.handleInput(766, 1902)
    tavern.onActionResult({ action = action, success = true })
    check(eventCount("gacha10_failed") == 1, "missing results roll tutorial back")
    resetEvents(); tavern.handleInput(766, 1902)
    tavern.onActionResult({ action = action, success = true, gachaResults = { { type = "dupe_to_shard" } } })
    check(tutorialState.heroId == nil and eventCount("gacha10_complete") == 1, "all duplicate results clear stale hero and complete successful ten-pull")
    resetEvents(); recruitState.mode = "sync"
    tavern.handleInput(766, 1902)
    check(tutorialState.heroId == 6 and eventCount("gacha10_complete") == 1,
        "synchronous ten-pull success records hero before completion")
    resetEvents(); recruitState.mode = "pending"
    tavern.handleInput(766, 1902); clock.elapsedTime = clock.elapsedTime + 9; tavern.update(0.1)
    check(eventCount("gacha10_failed") == 1, "timeout emits failure and releases retry lock")
    resetEvents(); tavern.handleInput(766, 1902); tavern.onServerDisconnect()
    check(eventCount("gacha10_failed") == 1, "disconnect emits failure and releases retry lock")
    -- Direct path uses the same confirmed request entry supplied to popups.
    resetEvents(); tavern.setSendAction(function() return true end)
    popupContext.doRecruitDirect(1)
    tavern.onActionResult({ action = action, success = true, gachaResults = { { type = "hero", heroId = 7 } } })
    check(eventCount("gacha10_started") == 0 and eventCount("gacha10_complete") == 0,
        "single pull does not masquerade as ten-pull tutorial event")
end

function Start()
    local ok, err = pcall(function()
        testConfig(); testCharacterTab(); testGridTargets(); testEquipEvents(); testRecruitEvents()
    end)
    if not ok then failures = failures + 1; print("[FAIL] exception: " .. tostring(err)) end
    print("[tutorial_flow_targets_test] " .. (failures == 0 and "ALL PASS" or "FAILURES=" .. failures)
        .. " (" .. passes .. " assertions)")
    engine:Exit()
end
