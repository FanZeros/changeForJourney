-- 真实Service/Bridge/Dispatcher/Store/Panel/Power/Effect通知链；私有闭包只读Lua源。
-- 不启动main、不读写玩家档，不用动画draw替身冒充原生视觉验收（独立preview负责）。
-- 唯一洗练骰子输入显式注入固定候选，仍执行真实预览/确认/计价/评分/通知。
local TAG = "[power_success_notification_test]"
local checks, groups, failures = 0, 0, {}
local nativeCache, nativeRequire = cache, require
local harnesses = {}
local function noop() end
local function check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function eq(value, expected, label)
    check(value == expected, label .. " actual=" .. tostring(value) .. " expected=" .. tostring(expected))
end
local function near(value, expected, label)
    check(math.abs(value - expected) < .000001, label)
end
local function group(name, fn)
    groups = groups + 1
    local ok, caught = xpcall(fn, debug.traceback)
    if ok then print(TAG .. " PASS " .. name)
    else failures[#failures + 1] = name .. ": " .. tostring(caught); print(TAG .. " FAIL " .. failures[#failures]) end
end
local function source(path)
    check(type(path) == "string" and path:match("^[%w_/]+%.lua$")
        and not path:find("..", 1, true), "only project Lua source reads")
    local file = assert(nativeCache:GetFile(path), "missing real source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function fixture()
    local env = { cache = { GetFile = function(_, path)
        local text = source(path)
        local index, lines = 0, {}
        for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
        return { IsEof = function() return index >= #lines end,
            ReadLine = function() index = index + 1; return lines[index] end, Dispose = noop }
    end } }
    setmetatable(env, { __index = _G })
    env._G = env
    return assert(load(source("tests/InventoryCurationFixture.lua"), "@power-private/Fixture", "t", env))()
end

local function newHarness(F, count, async)
    local h = F.new()
    h.allowBootFixture = true
    h.blockedIo, h.refreshes, h.logs, h.snapshots, h.results = 0, 0, {}, {}, {}
    local function deny()
        h.blockedIo = h.blockedIo + 1
        error("power feedback test forbids production I/O", 0)
    end
    h.env.File, h.env.FileSystem = deny, deny
    h.env.fileSystem = setmetatable({}, { __index = function() return deny end })
    h.env.cache = { GetFile = deny, GetResource = deny }
    h.env.io = setmetatable({}, { __index = function() return deny end })
    h.env.os.execute, h.env.os.remove, h.env.os.rename = deny, deny, deny
    h.env.dofile, h.env.loadfile = deny, deny
    h.env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        local message = table.concat(parts, " ")
        h.logs[#h.logs + 1] = message
        print(TAG .. " " .. message)
    end
    local readRequire = h.require
    local uiReal = { ["ui.character.panel.CharacterPanel"] = true,
        ["ui.character.panel.CharacterHeroSync"] = true, ["ui.character.panel.CharacterDeploy"] = true,
        ["ui.character.panel.CharacterProgress"] = true, ["ui.character.panel.CharacterPower"] = true,
        ["ui.character.panel.CharacterRosterSort"] = true, ["ui.church.talent.TalentStarMap"] = true,
        ["ui.widget.TalentGlyph"] = true, ["ui.widget.TalentGlyphContours"] = true,
        ["ui.widget.TalentGlyphExtra"] = true,
        ["ui.fx.SpinePowerUpEffect"] = true }
    h.require = function(name)
        if name == "urhox-libs/UI" or name == "ui.widget.DesignWidgetSurface" then return nativeRequire(name) end
        check(h.mocks[name] ~= nil or uiReal[name] or name:match("^core%.") or name:match("^config%.")
            or name:match("^systems%.") or name:match("^shared%.") or name:match("^rules%.")
            or name == "runtime.LocalActionBridge" or name == "runtime.LocalDispatcher"
            or name == "runtime.ClientDispatcher" or name == "runtime.ClientMessageHandler", "declared dependency " .. name)
        check(not name:match("^boot%.") and not name:match("^network%."), "no Boot/Save/network imports")
        return readRequire(name)
    end
    h.env.require = h.require
    local drawContext = {}
    h.mocks["ui.character.panel.CharacterPanelDraw2"] = {
        MAX_SLOTS = 4, MAX_PER_ROW = 5, CARD_W = 198, CARD_H = 351, CARD_SPACING = 205,
        CARD_CY = 300, ROW1_CY = 600, ROW_SPACING = 200, NAME_BG_DY = 100, NAME_BG_H = 40,
        SCROLL_TOP = 450, SCROLL_BOTTOM = 2200, SCROLL_LEFT = 0, SCROLL_RIGHT = 1080,
        DESIGN_W = 1080, ROSTER_BOTTOM_DY = 130, getSlotCX = function(i) return i * 205 end,
        setContext = function(ctx) drawContext = ctx end, initImages = noop, resetPresentation = noop,
        getSharedImages = function() return {} end,
    }
    h.mocks["ui.character.detail.CharacterDetail"] = { init = noop, setContext = noop, markPowerDirty = noop }
    h.mocks["ui.character.panel.CharacterInput"] = { bind = function() return {} end }
    h.mocks["ui.battle.tri.BattleTriPage"] = { invalidateTeams = noop, refreshHeroProgressTeams = noop }
    h.mocks["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end }
    h.mocks["ui.battle.scene.BattleScene"].refreshAllyStats = noop
    h.mocks["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop }
    h.mocks["rules.task.TaskService"] = { UpdateProgress = noop, SetPersistCallback = noop }
    -- Controller不调用draw；后端生命周期不启动资源，原生视觉另走真实preview。
    h.mocks["ui.fx.DarkEffectSprites"] = { release = noop, preload = noop }
    local Power = h.require("ui.character.panel.CharacterPower")
    local bind = Power.bind
    Power.bind = function(deps)
        local api = bind(deps)
        local refresh = api.refreshPowerCache
        api.refreshPowerCache = function(cause) h.refreshes = h.refreshes + 1; return refresh(cause) end
        api.refreshNavBadge = noop
        return api
    end
    local data = F.modules(h, 0)
    data.player.level = 100
    data.heroes.roster = { [1] = { level = 100 }, [2] = { level = 100 }, [3] = { level = 100 } }
    data.heroes.deployed = { 1, 0, 0, 0 }
    data.heroes.teams = { { slots = { 1, 0, 0, 0 } }, { slots = { 2, 0, 0, 0 } }, { slots = { 3, 0, 0, 0 } } }
    data.talents, data.artifacts = { litNodes = { 0 } }, { bag = {}, equippedByTeam = {} }
    local defaults = h.require("shared.schemas.CharacterSchema").Fields.currency.getDefault()
    for key in pairs(defaults) do defaults[key] = 1000000 end
    data.currency = defaults
    for seq = 1, count or 1 do
        local template = ({ "W1", "O1", "A1", "H1", "S1", "C1" })[(seq - 1) % 6 + 1]
        local item = F.item(h, template, 1 + (seq - 1) % 12, 1)
        item.seq = seq
        data.equipment.inventory[tostring(seq)] = item
    end
    data.equipment.nextSeq = (count or 1) + 1
    for _, name in ipairs({ "slotEnhance", "task", "redeem", "signin", "market", "tavern",
        "dungeon", "global_profile", "quotas" }) do data[name] = data[name] or {} end
    h:attach(data)
    h.Store, h.State = h.require("core.PlayerStore"), h.require("core.GameState")
    h.State.syncPlayerData(data.player); h.State.syncFromCurrency(data.currency)
    h.Panel = h.require("ui.character.panel.CharacterPanel")
    h.Panel.init(nil); h.Panel.setHeroesData(h.modules.heroes)
    h.Effect, h.Bus, h.Events = h.require("ui.fx.SpinePowerUpEffect"), h.require("core.EventBus"), h.require("config.GameEvents")
    h.Bus.on(h.Events.TEAM_POWER_CHANGED, function(value)
        h.snapshots[#h.snapshots + 1] = F.copy(value)
        if h.onSnapshot then h.onSnapshot(value) end
    end)
    h.Effect.init()
    h.Dispatcher.set("equipment", h.modules.equipment, { normalized = true })
    h:setTime(h.clock + 3)
    h.Service, h.Smith, h.Talent = h.require("rules.equipment.EquipmentService"),
        h.require("rules.blacksmith.BlacksmithService"), h.require("rules.talent.TalentService")
    h.Context = h.require("shared.SuccessNotificationContext")
    h.PDM.Setup({ serverDispatcher = { pushModule = function(_, name, value)
        h.pushes[name] = (h.pushes[name] or 0) + 1
        h.Dispatcher.set(name, value, { normalized = true })
    end } })
    function h:row(team)
        for _, row in ipairs(self.Effect.getDisplayRows()) do if row.teamIdx == team then return row end end
    end
    function h:clear()
        self:setTime(self.clock + 6); self.Effect.update(0)
        eq(#self.Effect.getDisplayRows(), 0, "visible lifetime completed")
    end
    if async then
        for _, name in ipairs({ "battle.Battle", "hero.Hero", "gacha.Gacha", "blacksmith.Blacksmith",
            "task.Task", "redeem.Redeem", "awakening.Awakening", "advancement.Advancement",
            "talent.Talent", "signin.SignIn", "gm.GM", "market.Market", "loot.Loot", "sweep.Sweep",
            "artifact.Artifact", "dungeon.Dungeon", "offline.Offline", "tower.Tower" }) do
            h.mocks["rules." .. name .. "Handler"] = { actionHandlers = {} }
        end
        h.mocks["rules.dungeon.DungeonService"] = { SetPersistCallback = noop }
        h.mocks["rules.redeem.RedeemService"] = { Init = noop }
        for _, name in ipairs({ "ui.hud.popup.RewardPopup", "ui.loot.LootBox", "ui.loot.LootBoxPage",
            "ui.blacksmith.BlacksmithPage", "ui.backpack.BackpackPanel", "ui.church.ChurchPage",
            "ui.church.talent.TalentPage", "ui.tavern.TavernPage", "ui.market.MarketPage", "ui.dungeon.DungeonPage",
            "ui.dungeon.DungeonBattleScene", "ui.dev.GMConsolePanel", "ui.hud.TopBar",
            "ui.character.equip.EquipmentDetail", "ui.hud.popup.RedeemCodePanel" }) do h.mocks[name] = {} end
        h.mocks["systems.TutorialManager"] = { notifyEvent = noop }
        h.mocks["systems.GameSFX"] = { play = noop }
        h.mocks["core.UiToast"] = { show = noop }
        local msg = h.require("runtime.ClientMessageHandler")
        msg.setup({ sendAction = noop, ui = {} })
        local receive = msg.handleActionResult
        msg.handleActionResult = function(value)
            h.results[#h.results + 1] = F.copy(value)
            local refreshes = h.refreshes
            receive(value)
            eq(h.refreshes, refreshes, "real CMH receipt does not rescore or lose first-notification diff")
        end
        h.Bridge = h.require("runtime.LocalActionBridge")
        h.Bridge.init()
        h.AT = h.require("shared.Protocol").ACTION_TYPES
    end
    harnesses[#harnesses + 1] = h
    return h
end

local function assertGrowth(h, cause, old, team)
    team = team or 1
    local snapshot, row = h.snapshots[#h.snapshots], assert(h:row(team), "actual positive row missing")
    eq(snapshot.cause, cause, "first authority notification carries successful cause")
    eq(row.base, old, "baseline is previous official power")
    eq(row.power, h.Panel.getTotalPower(team), "target is current official power")
    eq(row.delta, row.power - old, "precise net positive difference")
    check(row.delta > 0, "only positive real power increase")
    eq(h.Context.takeCause(h.modules.equipment, "equipment"), nil, "equipment context consumed once")
    eq(h.Context.takeCause(h.modules.talents, "talents"), nil, "talent context consumed once")
end

local function run()
    local F = fixture()
    group("single equip first authority publish, duplicate, failure, unequip", function()
        local h = newHarness(F, 1)
        local old, scores, events = h.Panel.getTotalPower(1), h.refreshes, #h.snapshots
        eq(h.Service.EquipItem(1, 1, 1, "weapon"), true, "real EquipItem succeeds")
        eq(h.refreshes, scores + 1, "one final rescore")
        eq(#h.snapshots, events + 1, "one complete authority event")
        assertGrowth(h, "equipment_equip", old)
        h:setTime(h.clock + .4)
        local elapsed = h:row(1).elapsed
        eq(h.Service.EquipItem(1, 1, 1, "weapon"), true, "same item retry original success contract")
        eq(h.snapshots[#h.snapshots].cause, nil, "same item retry has no success cause")
        near(h:row(1).elapsed, elapsed, "retry does not renew visible lifetime")
        events, scores = #h.snapshots, h.refreshes
        eq(h.Service.EquipItem(1, 999, 1, "weapon"), false, "missing item rejects")
        eq(#h.snapshots, events, "failed equip no publish")
        eq(h.refreshes, scores, "failed equip no rescore")
        eq(h.Service.UnequipItem(1, 1, "weapon"), true, "explicit unequip")
        eq(h.snapshots[#h.snapshots].cause, nil, "unequip stays silent")
        eq(h:row(1), nil, "unequip removes previous positive hint")
        eq(h.modules.equipment.cause, nil, "cause never stored on equipment module")
        eq(h.modules.equipment.inventory["1"].cause, nil, "cause never stored on item")
    end)
    group("synchronous EquipAllBest once; no-op and unrelated refresh silent", function()
        local h = newHarness(F, 12)
        local old, scores, events = h.Panel.getTotalPower(1), h.refreshes, #h.snapshots
        local ok, _, result = h.Service.EquipAllBest(1, 1)
        check(ok and result.changes > 0, "real synchronous search commits positive changes")
        eq(h.refreshes, scores + 1, "search commits only one score")
        eq(#h.snapshots, events + 1, "search publishes only final slots")
        assertGrowth(h, "equipment_equip", old)
        events = #h.snapshots
        ok, _, result = h.Service.EquipAllBest(1, 1)
        check(ok and result.changes == 0, "second search no-op")
        eq(#h.snapshots, events, "no-op search publishes nothing")
        h:clear()
        h.Dispatcher.set("equipment", h.modules.equipment, { normalized = true })
        eq(h.snapshots[#h.snapshots].cause, nil, "replayed plain data no retained context")
        eq(#h.Effect.getDisplayRows(), 0, "plain snapshot no fake hint")
        eq(h.Service.ToggleEquipLock(1, 1), true, "lock success not growth")
        eq(h.snapshots[#h.snapshots].cause, nil, "lock update no growth cause")
    end)
    group("async Bridge final notification reaches real Panel before real CMH receipt", function()
        local h = newHarness(F, 30, true)
        local old, events, scores = h.Panel.getTotalPower(1), #h.snapshots, h.refreshes
        h.onSnapshot = function(data)
            if data.cause == "equipment_equip" then eq(#h.results, 0, "authority event precedes receipt") end
        end
        check(h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, { heroId = 1, cause = "level_up" }), "real async dispatch")
        eq(#h.snapshots, events, "request never triggers animation")
        eq(h.refreshes, scores, "request never advances baseline")
        local pumps = 0
        while h.Bridge.isQuickEquipPending() do
            pumps = pumps + 1; check(pumps < 10000, "bounded async completion")
            h.Bridge.updateQuickEquip()
        end
        eq(#h.results, 1, "one true receipt")
        check(h.results[1].success and h.results[1].changes > 0, "actual final result success")
        eq(#h.snapshots, events + 1, "async final event once")
        eq(h.refreshes, scores + 1, "async final scoring once")
        assertGrowth(h, "equipment_equip", old)
        h.onSnapshot = nil
        h:clear(); events = #h.snapshots
        h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, { heroId = 1 })
        while h.Bridge.isQuickEquipPending() do h.Bridge.updateQuickEquip() end
        eq(h.results[2].changes, 0, "async no-op reports zero changes")
        eq(#h.snapshots, events, "async no-op no extra event/hint")
    end)
    group("async stale and cancellation retain slots and no success notification", function()
        local h = newHarness(F, 72, true)
        local before = F.copy(h.modules.equipment.equipped)
        h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, { heroId = 1 })
        h.Bridge.updateQuickEquip()
        check(h.Bridge.isQuickEquipPending(), "search actually yields before mutation")
        h.Dispatcher.set("talents", h.modules.talents, { normalized = true })
        local events = #h.snapshots
        h.Bridge.updateQuickEquip()
        check(not h.Bridge.isQuickEquipPending(), "revision change cancels stale job")
        F.same(h.modules.equipment.equipped, before)
        eq(#h.snapshots, events, "stale no final equipment notification")
        eq(#h.Effect.getDisplayRows(), 0, "stale no animation")
        eq(h.results[1].reason, "quick_equip_stale", "stale receipt original contract")
        h.Bridge.dispatch(h.AT.EQUIP_ALL_BEST, { heroId = 1 }); h.Bridge.updateQuickEquip()
        h.Bridge.cancelQuickEquip(); h.Bridge.updateQuickEquip()
        eq(#h.results, 1, "explicit cancellation no old receipt")
        F.same(h.modules.equipment.equipped, before)
        eq(h.Context.takeCause(h.modules.equipment, "equipment"), nil, "stale/cancel context never installed")
    end)
    group("worn ascend vs unworn/failure; confirmed refine vs preview/cancel", function()
        local h = newHarness(F, 2)
        local worn = h.modules.equipment.inventory["1"]
        worn.level, worn.quality, worn.baseStats = 60, 6, nil
        h.require("systems.EquipmentSystem").hydrate(worn)
        h.Service.EquipItem(1, 1, 1, "weapon"); h:clear()
        local old = h.Panel.getTotalPower(1)
        eq(h.Smith.AscendEquip(1, 1), true, "real worn ascend")
        assertGrowth(h, "equipment_ascend", old)
        h:clear(); old = h.Panel.getTotalPower(1)
        eq(h.Smith.AscendEquipToLevel(1, 1, 2), true, "real multi ascend target")
        assertGrowth(h, "equipment_ascend", old)
        h:clear(); old = h.Panel.getTotalPower(1)
        eq(h.Smith.AscendEquip(1, 2), true, "unworn ascend updates item")
        eq(h.Panel.getTotalPower(1), old, "unworn item official power unchanged")
        eq(#h.Effect.getDisplayRows(), 0, "unworn ascend no false animation")
        h.modules.currency.gold = 0
        local events = #h.snapshots
        eq(h.Smith.AscendEquip(1, 1), false, "insufficient resources rejects")
        eq(#h.snapshots, events, "failed ascend no notification")
        h.modules.currency.gold = 1000000
        local item = h.modules.equipment.inventory["1"]
        item.affixes = { { affixId = 1, quality = 1, key = "str", value = 1, name = "力量" } }
        h.Dispatcher.set("equipment", h.modules.equipment, { normalized = true })
        local ES = h.require("systems.EquipmentSystem")
        ES.rollAffixesForRefine = function() return { { affixId = 1, quality = 1, key = "str", value = 20, name = "力量" } } end
        old = h.Panel.getTotalPower(1)
        eq(h.Smith.RefineEquip(1, 1), true, "real refine only creates pending candidate")
        eq(h.Panel.getTotalPower(1), old, "preview does not apply candidate")
        eq(h.snapshots[#h.snapshots].cause, nil, "preview authority notice remains silent")
        eq(#h.Effect.getDisplayRows(), 0, "preview not success animation")
        -- 实际界面取消不调用Replace，普通刷新也不能消费pending候选。
        h.Dispatcher.set("equipment", h.modules.equipment, { normalized = true })
        eq(#h.Effect.getDisplayRows(), 0, "cancel/ordinary refresh does not pretend confirmation")
        eq(h.Smith.RefineReplace(1, 1), true, "real explicit candidate confirmation")
        assertGrowth(h, "equipment_refine", old)
        events = #h.snapshots
        eq(h.Smith.RefineReplace(1, 1), false, "second replace no pending rejects")
        eq(#h.snapshots, events, "failed replace no replay")
    end)
    group("talent actual activation all teams positive; resets and rejects silent", function()
        local h = newHarness(F, 0)
        local old = { h.Panel.getTotalPower(1), h.Panel.getTotalPower(2), h.Panel.getTotalPower(3) }
        eq(h.Talent.Activate(1, 2), true, "actual adjacent talent activates")
        for team = 1, 3 do assertGrowth(h, "talent_activate", old[team], team) end
        local events = #h.snapshots
        eq(h.Talent.Activate(1, 2), false, "already lit rejects")
        eq(h.Talent.Activate(1, 10000), false, "invalid node rejects")
        eq(#h.snapshots, events, "failed activation no publish")
        eq(h.Talent.DeactivateSingle(1, 2), true, "actual leaf reset")
        eq(h.snapshots[#h.snapshots].cause, nil, "deactivation silent")
        eq(#h.Effect.getDisplayRows(), 0, "deactivation removes old hint")
        eq(h.Talent.ResetAll(1), true, "actual all reset")
        eq(h.snapshots[#h.snapshots].cause, nil, "all reset silent")
    end)
    group("scoped context nested once, exception cleanup, no persisted metadata", function()
        local h = newHarness(F, 0)
        local data, Context = h.modules.equipment, h.Context
        local before = cjson.encode(data)
        Context.withNotification(data, "equipment", "equipment_equip", function()
            eq(Context.takeCause(data, "equipment"), "equipment_equip", "outer cause first consume")
            eq(Context.takeCause(data, "equipment"), nil, "outer consumed once")
            Context.withNotification(data, "equipment", "equipment_refine", function()
                eq(Context.takeCause(data, "equipment"), "equipment_refine", "nested independent cause")
            end)
            eq(Context.takeCause(data, "equipment"), nil, "consumed outer not restored after nested")
        end)
        eq(Context.takeCause(data, "equipment"), nil, "published stack exited clean")
        local ok = pcall(Context.withNotification, data, "equipment", "equipment_equip", function() error("expected publish failure") end)
        eq(ok, false, "publish exception retains error contract")
        eq(Context.takeCause(data, "equipment"), nil, "failed publish no stale cause")
        eq(cjson.encode(data), before, "context never touches serializable module values")
    end)
    group("real service gains survive 5.7s blocking, coalesce three teams and retain lifetime", function()
        local h = newHarness(F, 6)
        local worn = h.modules.equipment.inventory["1"]
        worn.level, worn.quality, worn.baseStats = 60, 6, nil
        h.require("systems.EquipmentSystem").hydrate(worn)
        local Effect = h.Effect
        Effect.setPresentationBlocked(true)
        local old = { h.Panel.getTotalPower(1), h.Panel.getTotalPower(2), h.Panel.getTotalPower(3) }
        eq(h.Service.EquipItem(1, 1, 1, "weapon"), true, "blocked real equip immediately succeeds")
        assertGrowth(h, "equipment_equip", old[1])
        near(h:row(1).elapsed, 0, "pending equip not yet visible")
        h:setTime(h.clock + 5.7); Effect.update(100)
        for _ = 1, 20 do Effect.setPresentationBlocked(true); Effect.update(100) end
        check(Effect.isPlaying(), "5.7s LevelUpPopup-class blocking preserves finite pending presentation")
        near(h:row(1).elapsed, 0, "repeated blocked observation never advances visible clock")
        eq(h:row(1).displayPower, old[1], "first visible frame retains true old value for count-up")
        eq(h.Smith.AscendEquip(1, 1), true, "blocked worn ascend remains ordinary successful business")
        eq(h.Talent.Activate(1, 2), true, "blocked talent success affects every real team")
        eq(#Effect.getDisplayRows(), 3, "coalesced latest state bounded to three teams")
        for team = 1, 3 do
            local row = assert(h:row(team))
            eq(row.base, old[team], "coalesced earliest official baseline team " .. team)
            eq(row.power, h.Panel.getTotalPower(team), "coalesced final authority target team " .. team)
            near(row.elapsed, 0, "blocked rows receive full visible lifetime team " .. team)
        end
        Effect.setPresentationBlocked(false)
        local duration = h:row(1).duration
        h:setTime(h.clock + .65); Effect.update(500)
        local first = h:row(1)
        check(first.displayPower > first.base and first.displayPower < first.power, "count-up actually progressing after unblock")
        local elapsed, progress = first.elapsed, first.progress
        Effect.setPresentationBlocked(true)
        h:setTime(h.clock + 12)
        Effect.update(12)
        near(h:row(1).elapsed, elapsed, "second block freezes remaining lifetime not restarts it")
        near(h:row(1).progress, progress, "second block freezes same count-up sample")
        eq(h.Service.EquipItem(1, 1, 1, "weapon"), true, "blocked duplicate same equip success")
        near(h:row(1).elapsed, elapsed, "blocked duplicate no lifetime renewal")
        Effect.setPresentationBlocked(false)
        h:setTime(h.clock + duration - elapsed - .01); Effect.update(0)
        check(h:row(1) ~= nil, "full remaining visible duration retained after two blockers")
        h:setTime(h.clock + .02); Effect.update(0)
        eq(h:row(1), nil, "finite presentation expires by visible time")
    end)
    group("blocked decrease/plain refresh withdraw, login suppression immediate release, lifecycle", function()
        local h = newHarness(F, 6)
        for seq, template in pairs({ [3] = "A13", [4] = "H13", [5] = "S13" }) do
            local item = F.item(h, template, 1, 3)
            item.seq = seq
            h.modules.equipment.inventory[tostring(seq)] = item
        end
        local Effect = h.Effect
        Effect.setPresentationBlocked(true)
        h.Service.EquipItem(1, 1, 1, "weapon")
        eq(h.Service.UnequipItem(1, 1, "weapon"), true, "blocked actual unequip succeeds without delay")
        eq(h:row(1), nil, "blocked decrease removes outdated pending gain")
        h.Service.EquipItem(1, 1, 1, "weapon")
        local item = h.modules.equipment.inventory["1"]
        item.affixes = { { key = "str", value = 100, quality = 1 } }
        h.Dispatcher.set("equipment", h.modules.equipment, { normalized = true })
        eq(h:row(1), nil, "unattributed changed snapshot cancels pending gain even when increasing")
        Effect.setPresentationBlocked(true, true)
        eq(h.Service.EquipItem(1, 2, 1, "offhand"), true, "title-suppressed real mutation accepted")
        h:setTime(h.clock + 10)
        eq(#Effect.getDisplayRows(), 0, "title does not queue login growth")
        Effect.setPresentationBlocked(false, false)
        local old = h.Panel.getTotalPower(1)
        eq(h.Service.EquipItem(1, 3, 1, "armor"), true, "immediate user equip after title closes")
        assertGrowth(h, "equipment_equip", old)
        check(Effect.isPlaying(), "closing title does not create extra two-second silent window")
        Effect.setPresentationBlocked(true)
        Effect.resetSession(); Effect.resetSession()
        eq(#Effect.getDisplayRows(), 0, "reset is idempotent and clears blocked pending rows")
        h.Dispatcher.set("equipment", h.modules.equipment, { normalized = true })
        eq(#Effect.getDisplayRows(), 0, "reset first real snapshot establishes fresh baseline")
        h:setTime(h.clock + 3)
        h.Talent.Activate(1, 2)
        check(Effect.isPlaying(), "real gain after reset quiet period still works")
        Effect.destroy(); Effect.destroy(); Effect.setPresentationBlocked(true)
        eq(#Effect.getDisplayRows(), 0, "Stop/destroy removes all pending state")
        Effect.init(); Effect.init()
        h.Dispatcher.set("equipment", h.modules.equipment, { normalized = true })
        h:setTime(h.clock + 3)
        old = h.Panel.getTotalPower(1)
        eq(h.Service.EquipItem(1, 4, 1, "helmet"), true, "equip after restart")
        assertGrowth(h, "equipment_equip", old)
        h.Bus.emit(h.Events.TEAM_POWER_CHANGED, { powers = { 0, 0, 0 }, ready = false })
        eq(#Effect.getDisplayRows(), 0, "not-ready snapshot clears all previous presentation")
        h.Dispatcher.set("equipment", h.modules.equipment, { normalized = true })
        eq(#Effect.getDisplayRows(), 0, "first hydrated authority snapshot after not-ready is silent")
        old = h.Panel.getTotalPower(1)
        eq(h.Service.EquipItem(1, 5, 1, "shoes"), true, "next true user gain after hydration")
        assertGrowth(h, "equipment_equip", old)
    end)
    group("all closures forbid player files RNG and swallowed subscriber faults", function()
        for _, h in ipairs(harnesses) do
            eq(h.blockedIo, 0, "no native storage/resource access")
            eq(h.fileCalls + h.fsCalls, 0, "no virtual storage calls")
            eq(h.randomCalls, 0, "animation/notification does not consume RNG")
            for _, message in ipairs(h.logs) do check(not message:find("subscriber error", 1, true), "no swallowed scoring/subscriber failure") end
            for name in pairs(h.loaded) do check(not name:match("^boot%.") and not name:match("^network%."), "closed real source graph no Boot/network") end
        end
    end)
end

function Start()
    local ok, caught = xpcall(run, debug.traceback)
    if not ok then failures[#failures + 1] = "harness: " .. tostring(caught); print(TAG .. " FAIL " .. failures[#failures]) end
    for _, h in ipairs(harnesses) do
        h.Effect.destroy()
        if h.Bridge then h.Bridge.cancelQuickEquip() end
        h.Store.Cleanup()
    end
    print(string.format("%s %s groups=%d assertions=%d failures=%d FileFS=0 RNG=0", TAG,
        #failures == 0 and "ALL PASS" or "FAILED", groups, checks, #failures))
    engine:Exit()
end
