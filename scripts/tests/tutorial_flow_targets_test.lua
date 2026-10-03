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
        POOL_NAME = "Test stellar",
        UI = { poolTabCx = 700, poolTabCy = 340 }, Pity = { UR_THRESHOLD = 100 },
        getTimeDisplayText = function() return "test" end, isPoolEnabled = function() return true end,
        checkPoolUnlocked = function() return true end, getUpPortraitPath = function() return "test.png" end,
    })
    stub("core.GameState", { getRecruitTicket = function() return 20 end, getGems = function() return 1000 end,
        getStellarRecruitTicket = function() return 20 end })
    stub("core.I18n", {})
    stub("runtime.ClientDispatcher", { get = function() return nil end, subscribe = noop })
    local chromeState = { nextTab = nil }
    stub("ui.town.TownPageChrome", { easeOutCubic = function(t) return t end,
        easeInCubic = function(t) return t end, hitBack = function() return false end,
        hitTab = function() local tab = chromeState.nextTab; chromeState.nextTab = nil; return tab end })
    local recruitState = { canPull = true, confirm = true, sendCount = 0, mode = "pending",
        playing = false, popup = false, purchaseConfirm = false, target = false, resetCount = 0 }
    stub("systems.GachaSystem", { canPull = function() return recruitState.canPull, "ticket" end,
        getSSRPityRemain = function() return 100 end, setPityCounts = noop })
    local popupContext = {}
    stub("ui.tavern.TavernPopups", { init = noop, setContext = function(ctx)
        for k, v in pairs(ctx) do popupContext[k] = v end
    end, checkAndShowConfirm = function() return recruitState.confirm end,
        isRecruitConfirmOpen = function() return recruitState.purchaseConfirm end,
        isBlocking = function() return recruitState.popup end, showFloatText = noop, recordHistory = noop,
        resetAll = function() recruitState.popup = false; recruitState.resetCount = recruitState.resetCount + 1 end,
        update = noop, formatGachaFailReason = function() return "failed" end })
    stub("ui.tavern.RecruitAnim", { init = noop, setOnAgain = noop,
        isPlaying = function() return recruitState.playing end,
        start = function(_, callback) callback() end, update = noop })
    stub("ui.tavern.TavernShopPage", { init = noop, resetScroll = noop, syncPurchasedFromStore = noop,
        isPendingBuy = function() return false end, update = noop, handleInput = function() return false end })
    stub("ui.tavern.TargetRecruitPanel", { init = noop, isOpen = function() return recruitState.target end,
        close = function() recruitState.target = false end })
    nvgCreateImage = function() return -1 end
    local tavern = require("ui.tavern.TavernPage")
    check(tavern.prepareTutorial(nil) == false and not tavern.isOpen(), "tutorial tavern waits safely for initialization context")
    check(tavern.prepareTutorial({}) == true and tavern.isOpen() and popupContext.getSelectedPoolId() == "standard",
        "tutorial tavern initializes and opens recruit first pool")
    local ot = tavern.getSeamAnim()
    clock.elapsedTime = clock.elapsedTime + 1
    check(tavern.prepareTutorial() == false and tavern.getSeamAnim() == ot and recruitState.sendCount == 0,
        "stable tavern prepare preserves open time and never sends recruit")
    tavern.handleInput(700, 340)
    check(popupContext.getSelectedPoolId() == "stellar", "fixture selects second pool before recovery")
    check(tavern.prepareTutorial() == true and popupContext.getSelectedPoolId() == "standard"
        and tavern.prepareTutorial() == false, "tutorial tavern restores first pool once")
    chromeState.nextTab = 2; tavern.handleInput(0, 0)
    check(tavern.prepareTutorial() == true and tavern.prepareTutorial() == false,
        "tutorial tavern restores recruit tab once without reopening")
    recruitState.popup, recruitState.target = true, true
    check(tavern.prepareTutorial() == true and not recruitState.popup and not recruitState.target
        and tavern.prepareTutorial() == false, "tutorial tavern closes interfering local popups once")
    recruitState.purchaseConfirm = true
    local confirmReset = recruitState.resetCount
    check(tavern.isRecruitConfirmOpen() and tavern.isRecruitBusy() and not tavern.prepareTutorial()
        and recruitState.purchaseConfirm and recruitState.resetCount == confirmReset,
        "真实补券确认处于业务等待，不被教程清掉")
    recruitState.purchaseConfirm = false
    stub("systems.StoryPlayer", { onPlace = noop })
    tavern.close()
    check(tavern.prepareTutorial() == true and tavern.isOpen() and tavern.prepareTutorial() == false,
        "tutorial tavern restores during close animation, then is stable")
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
    local pendingTime, sendsBefore = tavern.getSeamAnim(), recruitState.sendCount
    check(tavern.isRecruitBusy() and tavern.prepareTutorial() == false
        and tavern.getSeamAnim() == pendingTime and recruitState.sendCount == sendsBefore,
        "pending recruit blocks tutorial preparation without resetting time or sending")
    clock.elapsedTime = clock.elapsedTime + 9
    check(tavern.prepareTutorial() == false and tavern.isRecruitBusy() and eventCount("gacha10_failed") == 0,
        "prepare never times out/releases even an aged pending request")
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
    recruitState.playing = true
    recruitState.popup, recruitState.target = true, true
    local resetBefore = recruitState.resetCount
    check(tavern.isRecruitBusy() and tavern.prepareTutorial() == false and recruitState.playing
        and recruitState.popup and recruitState.target and recruitState.resetCount == resetBefore,
        "playing animation blocks tutorial preparation without closing its UI")
    recruitState.playing = false
    check(not tavern.isRecruitBusy() and tavern.prepareTutorial() == true
        and tavern.prepareTutorial() == false, "animation finish allows one cleanup then stable prepare")
end

local function testBlacksmithPreparation()
    stub("config.AffixConfig", {})
    stub("systems.AttributeDef", {})
    stub("config.ExpTable", {})
    stub("config.HeroAssetUtil", { preloadIcons = noop })
    stub("ui.fx.SpineResultEffect", {})
    stub("ui.widget.ImageCache", { init = noop, getEquipIcon = function() return -1 end })
    stub("ui.blacksmith.BlacksmithEnhanceCache", {})
    local smithState = {}
    local counts = { enhance = 0, refine = 0, opens = 0, holds = 0, releases = 0, sent = 0 }
    stub("ui.blacksmith.BlacksmithEnhance", {
        setContext = function(ctx) smithState = ctx.state end, init = noop,
        updateEnhanceData = function() counts.enhance = counts.enhance + 1 end,
        onOpen = function() counts.opens = counts.opens + 1 end,
    })
    stub("ui.blacksmith.BlacksmithRefine", { setContext = noop, init = noop,
        updateRefineData = function() counts.refine = counts.refine + 1 end })
    local smithInventory = { inventory = {
        ["1"] = { templateId = "missing", ascendLevel = 0 },
        ["2"] = { templateId = "W1", enhanceLevel = 100 },
        [3] = { templateId = "A1", ascendLevel = 99 },
        ["4"] = { templateId = "W1", ascendLevel = 3 },
    } }
    stub("runtime.ClientDispatcher", { get = function(key) if key == "equipment" then return smithInventory end end })
    stub("core.PlayerStore", { Get = function() return nil end, Subscribe = noop })
    stub("runtime.GameAction", { sendAction = function() counts.sent = counts.sent + 1 end })
    stub("systems.EquipmentSystem", { hydrate = function(equip)
        equip.slot = equip.templateId == "A1" and "armor" or "weapon"
    end, getAscendLevel = function(equip) return equip.ascendLevel or equip.enhanceLevel or 0 end })
    stub("ui.backpack.BackpackPanel", {
        acquireWarehouse = function() counts.holds = counts.holds + 1 end,
        releaseWarehouse = function() counts.releases = counts.releases + 1 end,
    })
    for _, path in ipairs({ "ui.loot.LootBoxPage", "ui.church.talent.TalentPage", "ui.church.ChurchPage",
        "ui.tavern.TavernPage", "ui.market.MarketPage", "ui.story.task.TaskPage" }) do
        stub(path, { isOpen = function() return false end, resetHorizonLayout = noop })
    end
    local smith = require("ui.blacksmith.BlacksmithPage")
    check(smith.prepareTutorial(nil) == false and not smith.isOpen(), "tutorial smith waits safely for initialization context")
    check(smith.prepareTutorial({}) == true and smith.isOpen() and smithState.tab == "qianghua"
        and smithState.selectedSeq == 3 and smithState.selectedEquip == smithInventory.inventory[3],
        "tutorial smith skips invalid templates/full legacy enhance and selects numeric-key valid equipment")
    local enhanceBefore, openTime = counts.enhance, smithState.openTime
    clock.elapsedTime = clock.elapsedTime + 1
    check(smith.prepareTutorial() == false and counts.enhance == enhanceBefore
        and smithState.openTime == openTime and counts.holds == 1 and counts.sent == 0,
        "stable smith prepare retains selection/open time without reset or action")
    smithInventory.inventory["4"].seq = 4
    smith.setSelectedEquip(smithInventory.inventory["4"])
    check(smith.prepareTutorial() == false and smithState.selectedSeq == 4,
        "tutorial smith retains legal player-selected item rather than smallest seq")
    smithState.tab, smithState.tabFrom, smithState.tabSwitchTime = "xilian", "qianghua", clock.elapsedTime
    check(smith.prepareTutorial() == true and smithState.tab == "qianghua"
        and smithState.selectedSeq == 4 and smith.prepareTutorial() == false,
        "tutorial smith switches to enhance without replacing legal selection")
    smithInventory.inventory["4"].ascendLevel = 100
    check(smith.prepareTutorial() == true and smithState.selectedSeq == 3,
        "tutorial smith replaces selected item once it reaches max ascend level")
    smith.close()
    check(smith.prepareTutorial() == true and not smithState.closing and smithState.selectedSeq == 3
        and smith.prepareTutorial() == false, "tutorial smith recovers close animation and retains legal selection")
    smithInventory.inventory[3] = nil
    check(smith.prepareTutorial() == true and smithState.selectedEquip == nil and smithState.selectedSeq == nil
        and smith.prepareTutorial() == false and counts.sent == 0,
        "no valid nonmax smith item clears stale selection once and never sends action")
end

local function testTaskForceClose()
    testStubs["ui.story.task.TaskPage"], package.loaded["ui.story.task.TaskPage"] = nil, nil
    package.preload["ui.story.task.TaskPage"] = nil
    local task = require("ui.story.task.TaskPage")
    task.forceClose()
    check(not task.isOpen(), "task force close is safe before opening")
    task.open(); task.handleDragBegin(100, 600); task.close(); task.forceClose()
    check(not task.isOpen() and not task.handleDragMove(100, 800),
        "task force close cancels open/closing/drag state immediately")
    task.forceClose()
    check(not task.isOpen(), "task force close is idempotent")
end

function Start()
    local ok, err = pcall(function()
        testConfig(); testCharacterTab(); testGridTargets(); testEquipEvents(); testRecruitEvents()
        testBlacksmithPreparation(); testTaskForceClose()
    end)
    if not ok then failures = failures + 1; print("[FAIL] exception: " .. tostring(err)) end
    print("[tutorial_flow_targets_test] " .. (failures == 0 and "ALL PASS" or "FAILURES=" .. failures)
        .. " (" .. passes .. " assertions)")
    engine:Exit()
end
