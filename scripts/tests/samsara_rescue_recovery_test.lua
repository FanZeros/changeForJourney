-- 单场真实全灭恢复专项；基于 scaffold-2d 的 Start/Stop 生命周期，无绘制或玩家档。
-- 原样私有 load：Scene/Phases/Casualty/Reset/UA/TAL/ART/Tracker/Ledger 均为生产源码。
-- 仅本文件；主会话统一 build/Runtime。没有回执只能是 unknown，不代表全局未获救。
local PREFIX = "[samsara_rescue_recovery] "
local assertions, failures, cases, passed = 0, 0, 0, 0

local function check(ok, label)
    assertions = assertions + 1
    if not ok then
        failures = failures + 1
        print(PREFIX .. "FAIL " .. label)
        log:Write(LOG_ERROR, PREFIX .. "FAIL " .. label)
    end
end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function runCase(label, fn)
    cases = cases + 1
    local before = failures
    local ok, err = pcall(fn)
    if not ok then check(false, label .. " exception: " .. tostring(err)) end
    if failures == before then passed = passed + 1; print(PREFIX .. "PASS " .. label) end
end
---@param value any
---@return any
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, item in pairs(a) do if not same(item, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function outsideLedger(session)
    local out = copy(session)
    if out.samsaraStory then out.samsaraStory.rescueLedger = nil end
    return out
end

-- 与 opening/dragon 隔离测试相同的 cache 只读边界；不替换源码，不回退全局 require。
local SOURCES = {}
---@param path string
---@param resolver fun(name: string): any
---@param globals table
---@return any
local function privateLoad(path, resolver, globals)
    if not SOURCES[path] then
        local file = cache:GetFile(path)
        assert(file and file:IsOpen(), "missing real source " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        SOURCES[path] = table.concat(lines, "\n")
    end
    local env = {}; for key, value in pairs(globals) do env[key] = value end
    env.require, env._G = resolver, env
    setmetatable(env, { __index = _G })
    return assert(load(SOURCES[path], "@" .. path, "t", env))()
end

local REAL = {}
for _, name in ipairs({
    "systems.AttributeDef", "systems.UnitAttributes", "systems.TalentManager", "systems.ArtifactRuntime",
    "systems.CombatFormula", "systems.TalentEffect", "systems.SamsaraRescueLedger",
    "config.StageConfig", "config.SamsaraSliceConfig", "config.HeroConfig", "config.ClassConfig",
    "config.AdvancementConfig", "config.ExpTable", "config.GameConfig", "config.AwakeningConfig", "shared.StageUtils",
    "core.BattleLayout", "ui.battle.combat.BattleCombat", "ui.battle.combat.BattleCombatAnim",
    "ui.battle.combat.BattleCasualty", "ui.battle.scene.BattleScene", "ui.battle.scene.BattleScenePhases",
    "ui.battle.scene.BattleAllyReset", "ui.battle.scene.BattleAllyLifecycle",
    "ui.battle.scene.BattleDataRestore", "ui.battle.scene.BattleRescueTracker",
    "ui.battle.stage.BattleStageLoad", "ui.battle.stage.BattleStageFlow",
    "ui.battle.stage.BattleStageNavLogic", "ui.battle.stage.BattleSpeed",
}) do REAL[name] = true end
local TALENTS = {
    "TalentAyane", "TalentLuoxing", "TalentMelissa", "TalentAlex", "TalentElwyn", "TalentSera",
    "TalentSuhua", "TalentUpdate", "TalentRosa", "TalentXin", "TalentAfterAttack", "TalentBeforeAttack",
    "TalentDamageTaken", "TalentModifyDamage", "TalentAllyDeath", "TalentEnemyDeath", "TalentComboAttack",
    "TalentFatFish", "TalentFourNew",
}
for _, name in ipairs(TALENTS) do REAL["systems.talents." .. name] = true end
local CTX_FIELDS = {
    "defeatTimer", "defeatByTimeout", "terminalDefeatPending", "battleActive", "currentStageId",
    "isFirstClear", "allies", "enemies", "enemyQueue", "rescueTracker", "rescueGeneration",
}
local function snapshot(ctx)
    local out = {}; for _, key in ipairs(CTX_FIELDS) do out[key] = ctx[key] end
    return out
end

---@return any
local function fixture(stageId, idle, heroIds)
    local f = {
        calls = {}, events = {}, phases = {}, casualties = {}, modules = {}, hooks = {}, now = 0,
        disk = {}, flushResult = true, owned = {}, animation = {},
        session = { introCompleted = true, initialHeroId = 1, claimedScenarios = { ["17"] = true },
            scenarioRewardsGranted = { ["17"] = true }, tutorialProgress = { untouched = true },
            goldSentinel = 123, unknown = { keep = true },
            samsaraStory = { schemaVersion = 1, nodes = {}, evidence = {}, unknown = { keep = 9 } } },
        currency = { gold = 123, gems = 456 },
    }
    function f.count(name)
        f.calls[name] = (f.calls[name] or 0) + 1
        f.events[#f.events + 1] = name
    end
    function f.n(name) return f.calls[name] or 0 end
    function f.noop(name) return function() f.count(name) end end
    local function boundary(methods)
        local out = {}; for _, method in ipairs(methods) do out[method] = f.noop("boundary." .. method) end
        return out
    end
    local function forbidden(name)
        return function() f.count("forbidden." .. name); error("forbidden player/economic boundary " .. name) end
    end
    local b = {}
    -- 绘制/音频/弹窗精确桩；不创建 NanoVG/GPU/Scene，不覆盖战斗状态或恢复实现。
    b["ui.battle.scene.BattleDraw"] = boundary({ "drawImageCentered", "drawImageMirrored", "drawTextStroke",
        "drawCardGroup", "drawFloatingTexts" })
    for _, name in ipairs({ "ui.battle.combat.BattleEffects", "ui.widget.SpeechBubble" }) do
        b[name] = boundary({ "update", "reset", "init", "spawn", "trigger" })
    end
    b["ui.battle.combat.ProjectileSystem"] = boundary({ "update", "reset" })
    for _, key in ipairs({ "hasProjectile", "hasHeroEffect", "hasMonsterProjectile" }) do
        b["ui.battle.combat.ProjectileSystem"][key] = function() return false end
    end
    b["ui.battle.combat.BattleCombatFx"] = boundary({ "addFloatingText", "updateFloatingTexts", "updateHitFlashes",
        "clearHitFlash", "setHitFlash" })
    b["ui.battle.combat.BattleCombatFx"].getHitFlashAlpha = function() return 0 end
    b["ui.battle.combat.BattleCombatCombo"] = {
        bind = function() return { updateComboQueue = f.noop("visual.combo"), performComboAttack = forbidden("combo") } end,
    }
    for _, name in ipairs({ "ui.battle.popup.TerminalConfirmDialog", "ui.battle.popup.MonsterInfoPopup",
        "ui.battle.popup.BattleResultPanel", "ui.battle.popup.DamageStatsPanel", "ui.battle.stage.SweepDialog" }) do
        b[name] = boundary({ "update", "close", "open", "init" }); b[name].isOpen = function() return false end
    end
    b["ui.hud.BottomNav"] = boundary({ "setAllLocked" })
    b["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return true end }
    b["ui.fx.SpineCardEffect"] = { playRevive = f.noop("visual.revive"), playLevelUp = f.noop("visual.levelUp") }
    b["systems.GameBGM"] = boundary({ "setScene" })
    b["systems.GameSFX"] = boundary({ "play", "playHit" })
    b["core.DarkIcon"], b["ui.battle.stage.BattleTransitionHud"] = {}, {}
    b["ui.battle.stage.BattleStageNav"] = { NAV = {} }
    b["ui.loot.LootBox"] = { setRates = f.noop("visual.rates") }
    b["ui.dungeon.DungeonBattle"] = { isActive = function() return false end }
    b["systems.StoryPlayer"] = { onStage = f.noop("story.onStage") }
    b["config.HeroAssetUtil"] = { getAssetIds = function() return {} end }
    b["core.NumberUtil"] = { format = function(value) return tostring(value) end }
    -- 无装备、星图、词缀、额外天赋的受控队员数据；仅实际 TAL/ART 常规/觉醒复活被测。
    b["systems.BattleDiag"] = { logEnabled = false, installSentinel = function() end,
        scanNow = function() end, update = function() end, reset = function() end }
    b["systems.ThreatManager"] = boundary({ "reset", "onBattleStart", "removeUnit", "update", "clearThreat" })
    b["systems.ThreatManager"].getThreat = function() return 0 end
    b["systems.StatusEffectManager"] = boundary({ "reset", "removeUnit", "apply", "remove", "update" })
    b["systems.StatusEffectManager"].has = function() return false end
    b["systems.StatusEffectManager"].isFrozen = function() return false end
    b["systems.RelicConditionHandler"] = boundary({ "reset", "initBattle", "update" })
    -- 真实 TAL 敌死分发还会调用职业/套装外边界；本夹具无职业门契/套装，仅计数不生成成长或奖励。
    b["systems.ClassGateRuntime"] = boundary({ "onBattleStart", "onEnemyDeath" })
    b["systems.EquipmentSetRuntime"] = boundary({ "resetBattleState", "onBattleStart", "onEnemyDeath" })
    b["systems.MapAffixSystem"] = boundary({ "onStageLoad", "applyStaticAffixes" })
    b["systems.MapAffixSystem"].hasAffixes = function() return false end
    b["systems.BossAffixSystem"] = boundary({ "onStageLoad", "applyToBosses", "clear" })
    b["systems.BossAffixSystem"].hasAffixes = function() return false end
    b["systems.ExtraTalentSystem"] = {
        flush = f.noop("extraTalent.flush"), onBattleStart = f.noop("extraTalent.start"),
        tryTicketRevive = function() return false end, getOwned = function() return {} end,
        getReviveRateBonus = function() return 0 end, onSuccessfulRevive = f.noop("extraTalent.revived"),
        onLoverDeathNuke = f.noop("extraTalent.loverDeath"), onEnemyDeath = f.noop("extraTalent.enemyDeath"),
        applyToAttrs = function() end,
    }
    b["ui.character.panel.CharacterPanel"] = {
        getOwnedHero = function(id) return f.owned[id] end,
        getEffectiveLevel = function() return 1 end,
        getHeroDeployPosition = function(id)
            for _, unit in ipairs(f.Scene.getAllies()) do if unit.heroId == id then return unit.partySlot, 1 end end
        end,
        applyEquippedItems = function() return nil end,
    }
    b["systems.ArtifactBridge"] = { applyToUnit = function() return {} end }
    b["systems.OfflineCalc"] = {
        resolveIdleStageAnchors = function(data) return data.currentStageId, data.currentStageId end,
        calcOnlineIdleRewards = function() return { gold = 0, adventureExp = 0, adventurerExp = 0 } end,
    }
    b["core.GameState"] = { getSpeedCardRemainSecs = function() return 0 end }
    local berserk = false
    b["ui.battle.stage.StageBerserk"] = {
        enter = function() berserk = true end, exit = function() berserk = false end,
        isActive = function() return berserk end, update = function() end,
    }
    b["systems.BattleTimeout"] = { calcMult = function() return 1 end }
    b["systems.BattleStats"] = boundary({ "reset", "recordHeal", "recordDamage" })
    -- 攻击/再生 tick 不属于延迟恢复链；只计数，不伤害/治疗/领奖。Casualty 的生命判定仍真实。
    b["ui.battle.scene.BattleSceneTick"] = { tick = f.noop("tick.outsideRecovery") }
    for _, name in ipairs({ "runtime.GameAction", "runtime.ClientMessageHandler", "rules.character.PlayerDataManager",
        "systems.TutorialManager" }) do
        b[name] = { sendAction = forbidden(name), Flush = forbidden(name), GetModule = forbidden(name) }
    end
    local globals = { time = { elapsedTime = 0 }, File = forbidden("File"),
        fileSystem = { FileExists = forbidden("FileExists"), Rename = forbidden("Rename"), Delete = forbidden("Delete") } }
    local busy = {}
    ---@type fun(name: string): any
    local resolve = function() error("resolver not initialized") end
    resolve = function(name)
        if b[name] then return b[name] end
        if f.modules[name] then return f.modules[name] end
        assert(REAL[name] or name:match("^config%.StageConfig_"), "undeclared dependency " .. name)
        assert(not busy[name], "unexpected circular private dependency " .. name)
        busy[name] = true
        local module = privateLoad(name:gsub("%.", "/") .. ".lua", resolve, globals)
        busy[name] = nil
        f.modules[name] = module
        return module
    end
    b["shared.StageProvider"] = { Get = function() return f.stageConfig or resolve("config.StageConfig") end }
    f.resolve = resolve
    f.AD, f.UA, f.SC = resolve("systems.AttributeDef"), resolve("systems.UnitAttributes"), resolve("config.StageConfig")
    f.Config = resolve("config.SamsaraSliceConfig")
    for index, key in ipairs(f.Config.KEYS) do
        f.session.samsaraStory.nodes[key] = { eligible = index % 2 == 0, contentVersion = 1,
            resolution = index == 1 and "finished" or nil, unknown = { keep = index } }
    end
    f.session.samsaraStory.evidence.E01 = { unlocked = true, source = "samsara.log_leaf", unknown = "keep" }
    f.Ledger = resolve("systems.SamsaraRescueLedger")
    f.TrackerClass = resolve("ui.battle.scene.BattleRescueTracker")
    local actualNew = f.TrackerClass.new
    f.TrackerClass.new = function(getState)
        local tracker = actualNew(getState)
        f.tracker = tracker
        return tracker
    end
    -- 观测实际 UA 方法；clone 仍保留实际类，恢复阶段每次 fill/治疗均可计数，绝不替换结果。
    local actualFill, actualHeal = f.UA.fillHp, f.UA.heal
    f.UA.fillHp = function(attrs) f.count("attrs.fillHp"); return actualFill(attrs) end
    f.UA.heal = function(attrs, amount) f.count("attrs.heal"); return actualHeal(attrs, amount) end
    f.Reset = resolve("ui.battle.scene.BattleAllyReset")
    local actualReset = f.Reset.resetAllyUnit
    f.Reset.resetAllyUnit = function(...)
        f.count("ally.reset")
        local result = actualReset(...)
        if f.hooks.afterReset then f.hooks.afterReset(...) end
        return result
    end
    f.Phases, f.Casualty = resolve("ui.battle.scene.BattleScenePhases"), resolve("ui.battle.combat.BattleCasualty")
    for _, spec in ipairs({ { f.Phases, "phase", f.phases }, { f.Casualty, "casualty", f.casualties } }) do
        local module, kind, records = spec[1], spec[2], spec[3]
        local actual = module.process
        module.process = function(ctx, dt)
            f.count(kind .. ".enter")
            local record = { before = snapshot(ctx), dt = dt, ctx = ctx }
            records[#records + 1] = record
            local consumed = actual(ctx, dt)
            record.after, record.consumed = snapshot(ctx), consumed
            f.count(kind .. ".exit")
            if f.hooks[kind .. "Exit"] then f.hooks[kind .. "Exit"](ctx, record) end
            return consumed
        end
    end
    f.Load, f.Flow = resolve("ui.battle.stage.BattleStageLoad"), resolve("ui.battle.stage.BattleStageFlow")
    local actualLoad, actualTalents = f.Load.load, f.Flow.startBattleTalents
    f.Load.load = function(ctx, id, skip)
        f.count("stage.load")
        if f.hooks.loadEnter then f.hooks.loadEnter(ctx, id, skip) end
        local result = actualLoad(ctx, id, skip)
        if f.hooks.loadExit then f.hooks.loadExit(ctx, id, skip) end
        return result
    end
    f.Flow.startBattleTalents = function(...)
        f.count("talents.start")
        local result = actualTalents(...)
        if f.hooks.talentsExit then f.hooks.talentsExit(...) end
        return result
    end
    f.Flow.ensureBattleCards = function() return {} end
    f.Flow.pumpBattleCards = function() return nil end
    -- 真实导航 bind/get/tick 只转发观测；缺失 victoryMarch getter/setter 必须照实失败，不造状态。
    f.Nav = resolve("ui.battle.stage.BattleStageNavLogic")
    local actualNavBind = f.Nav.bind
    f.Nav.bind = function(deps)
        local bound = actualNavBind(deps)
        f.getVictoryMarch = function() return deps.get("victoryMarch") end
        local actualMarchTick = bound.tickVictoryMarch
        bound.tickVictoryMarch = function(dt)
            f.count("march.tick")
            return actualMarchTick(dt)
        end
        return bound
    end
    -- 出怪数据精确边界：实际 StageLoad 与 actual UA，非空鲜活敌人防全灭被胜利短路。
    local enemySeq = 0
    local function enemy()
        enemySeq = enemySeq + 1
        local attrs = f.UA.create({ [f.AD.MAX_HP] = 200, [f.AD.ATK_INTERVAL] = 1000 })
        attrs:fillHp()
        return { monsterId = 1, instanceId = enemySeq, name = "fixture enemy", level = 1, attrs = attrs,
            hp = attrs:get(f.AD.HP), maxHp = attrs:get(f.AD.MAX_HP), atkInterval = 1000 }
    end
    b["ui.battle.stage.BattleEnemySpawn"] = {
        generateEnemyList = function() return { enemy() } end,
        generateIdleEnemyList = function() return { enemy() }, 1 end,
        assignEnemiesToField = function(list) return list, {} end,
    }
    f.Scene = resolve("ui.battle.scene.BattleScene")
    f.BC, f.TAL, f.ART = resolve("ui.battle.combat.BattleCombat"), resolve("systems.TalentManager"), resolve("systems.ArtifactRuntime")
    function f.makeParty(ids)
        local party = {}
        for index, id in ipairs(ids or { 1, 2 }) do
            local attrs = f.UA.create({ [f.AD.MAX_HP] = 100 + index * 10, [f.AD.ATK_INTERVAL] = 1000 })
            attrs:fillHp()
            party[index] = { heroId = id, name = "fixture hero " .. id, level = 1, attrs = attrs,
                hp = attrs:get(f.AD.HP), maxHp = attrs:get(f.AD.MAX_HP), partySlot = index, artifactTeamIdx = 1,
                atkInterval = 1000, advTalentIds = {}, awakeningNodes = {}, litNodeSet = {}, _etsDisabled = true }
        end
        return party
    end
    f.party = f.makeParty(heroIds)
    f.Scene.setOnEnemyKill(f.noop("reward.kill"))
    f.Scene.setOnEnemyDrop(f.noop("reward.drop"))
    f.Scene.setOnFirstClear(f.noop("reward.firstClear"))
    f.Scene.setOnAllDead(f.noop("legacy.allDead"))
    f.Scene.setOnStageChanged(function(id)
        f.count("stage.changed")
        if f.hooks.stageChanged then f.hooks.stageChanged(id) end
    end)
    f.Ledger.init({ getSession = function() return f.session end,
        setSession = function(session) f.count("session.set"); eq(session, f.session, "shared session identity") end,
        flush = function()
            f.count("ledger.flush")
            if f.flushResult == true then f.disk = copy(f.session) end
            return f.flushResult
        end })
    function f.attach()
        assert(type(f.Scene.setRescueCallbacks) == "function", "real Scene rescue bridge not installed")
        f.Scene.setRescueCallbacks(function()
            f.count("ledger.capture")
            local ticket = f.Ledger.capture()
            if f.hooks.capture then f.hooks.capture(ticket) end
            return ticket
        end, function(ticket, receipt)
            f.count("ledger.commit")
            f.lastTicket, f.lastReceipt = ticket, copy(receipt)
            if f.hooks.commit then
                local observed, observerError = pcall(f.hooks.commit, ticket, receipt)
                if not observed then
                    check(false, "commit observer exception (not a successful rejection): " .. tostring(observerError))
                    error(observerError, 0)
                end
            end
            local accepted = f.Ledger.commit(ticket, receipt)
            if accepted then f.count("ledger.accepted") end
            return accepted
        end)
    end
    function f.advance(dt)
        f.now = f.now + dt; globals.time.elapsedTime = f.now
        f.Scene.update(dt)
    end
    function f.wipe()
        for _, unit in ipairs(f.Scene.getAllies()) do unit.hp, unit.attrs.final[f.AD.HP] = 0, 0 end
        f.advance(0)
    end
    function f.unknown(label)
        eq(f.Ledger.getReceipt(), nil, label .. " no receipt")
        eq(f.Ledger.getExperience(), "unknown", label .. " not a trustworthy negative")
    end
    function f.noRewards(label)
        eq(f.n("reward.kill"), 0, label .. " no kill reward")
        eq(f.n("reward.drop"), 0, label .. " no drop reward")
        eq(f.n("reward.firstClear"), 0, label .. " no first-clear reward")
        check(same(f.currency, { gold = 123, gems = 456 }), label .. " currency unchanged")
        check(same(outsideLedger(f.session), f.outside), label .. " ten-node story/outer ledgers unchanged")
        for key, value in pairs(f.calls) do
            if key:match("^forbidden%.") then eq(value, 0, label .. " " .. key) end
        end
    end
    f.outside = outsideLedger(f.session)
    f.Scene.setBattleData({ currentStageId = stageId or 102, maxStageId = stageId or 102,
        clearedStages = idle and { [stageId or 102] = true } or {} })
    f.Scene.setAllies(f.party)
    f.advance(3) -- 真实 Phases 完成首次寻怪；不推进一次攻击。
    f.calls, f.events = {}, {}
    for i = #f.phases, 1, -1 do f.phases[i] = nil end
    for i = #f.casualties, 1, -1 do f.casualties[i] = nil end
    return f
end

local EXPECTED_KEYS = { "samsara.log_leaf", "samsara.cargo_match", "samsara.gray_order", "samsara.people_record",
    "samsara.returned_manifest", "samsara.dog_mirror", "samsara.bell_mirror", "samsara.opening_roster",
    "samsara.dragon_mirror", "samsara.nightmare_afterimage" }
local function originalRecoveryCases()
    for _, item in ipairs({ { 102, false, 101 }, { 101, false, 101 }, { 102, true, 102 } }) do
        runCase("original actual recovery " .. item[1] .. " idle=" .. tostring(item[2]), function()
            local f = fixture(item[1], item[2])
            check(same(f.Config.KEYS, EXPECTED_KEYS), "real original ten KEYs retained exactly")
            f.unknown("before defeat")
            f.wipe()
            eq(f.n("legacy.allDead"), 1, "actual Casualty first wipe callback once")
            eq(f.casualties[#f.casualties].after.defeatTimer, 0, "actual Casualty starts delay")
            f.advance(1)
            eq(f.Scene.getStageId(), item[1], "threshold not reached")
            f.Scene.pause(); f.advance(20)
            eq(f.phases[#f.phases].after.defeatTimer, 1, "pause preserves real delay")
            f.Scene.resume(); f.advance(0.25)
            f.unknown("before recovery completion")
            for _, unit in ipairs(f.party) do eq(unit.hp, 0, "no early revival") end
            f.advance(0.25)
            eq(f.Scene.getStageId(), item[3], "actual Phases target")
            eq(f.phases[#f.phases].after.defeatTimer, nil, "actual phase delay consumed")
            eq(f.n("stage.load"), 1, "actual recovery loads once")
            eq(f.n("ally.reset"), 2, "actual recovery resets each unit once")
            eq(f.n("stage.changed"), 1, "actual recovery stage notification once")
            for _, unit in ipairs(f.party) do
                eq(unit.hp, unit.maxHp, "actual Reset full HP")
                eq(unit.attrs.final[f.AD.HP], unit.hp, "actual attrs/display synchronized")
            end
            f.noRewards("original recovery")
        end)
    end
end

local function receiptCheck(f, failed, recovered, ids)
    local receipt = assert(f.Ledger.getReceipt(), "actual recovery did not produce a receipt")
    eq(receipt.schemaVersion, 1, "receipt schema")
    eq(receipt.source, "live_nonterminal_wipe_recovery", "receipt real source")
    eq(receipt.scope, "single_scene", "receipt explicitly partial coverage")
    eq(receipt.failedStageId, failed, "receipt failed stage")
    eq(receipt.recoveredStageId, recovered, "receipt recovered stage")
    eq(receipt.recoveryComplete, true, "receipt completion is explicit")
    check(same(receipt.heroIds, ids or { 1, 2 }), "receipt original party sorted by slots")
    eq(f.Ledger.getExperience(), "rescued", "confirmed experience")
    eq(f.n("ledger.capture"), 1, "actual source capture once")
    eq(f.n("ledger.commit"), 1, "actual host commit once")
    eq(f.n("ledger.accepted"), 1, "actual Ledger accepted once")
    eq(f.n("ledger.flush"), 1, "one memory Flush")
    check(same(f.disk, f.session), "memory persistence is the actual committed session")
    eq(f.Ledger.isSavePending(), false, "save succeeded")
    local fields = 0; for _ in pairs(receipt) do fields = fields + 1 end
    eq(fields, 7, "receipt does not serialize internal ticket/context")
    eq(f.session.samsaraStory.rescueLedger.coverage, "unknown", "not global negative coverage")
    f.noRewards("committed recovery")
    return receipt
end

local function chainCases()
    local schedules = { { 1.5 }, { 1, 0.25, 0.25 }, { 0.5, 0.5, 0.5 } }
    for _, stage in ipairs({ { 102, false, 101 }, { 101, false, 101 }, { 102, true, 102 } }) do
        for index, schedule in ipairs(schedules) do
            runCase("real chain " .. stage[1] .. " idle=" .. tostring(stage[2]) .. " dt=" .. index, function()
                local f = fixture(stage[1], stage[2]); f.attach()
                check(same(f.Config.KEYS, EXPECTED_KEYS), "ten KEY configuration stays unchanged")
                f.unknown("pre-wipe")
                f.hooks.commit = function()
                    eq(f.Scene.getStageId(), stage[3], "commit after actual host target state is written")
                    local state = f.tracker.getState()
                    eq(state.defeatTimer, nil, "host delay cleared before commit callback")
                    eq(state.battleActive, true, "host active before commit callback")
                    for _, unit in ipairs(state.allies) do eq(unit.hp, unit.maxHp, "host full party before callback") end
                    eq(f.n("phase.enter"), f.n("phase.exit"), "commit is after actual Phases returned")
                    -- Tracker 合法地 pcall 提交回调；夹具观察器异常必须先显式 FAIL，不能被当成拒票成功。
                    local reentered, reentryError = pcall(f.advance, 0)
                    check(reentered, "commit callback real Scene reentry completes: " .. tostring(reentryError))
                    if not reentered then error(reentryError, 0) end
                end
                f.wipe()
                eq(f.n("ledger.capture"), 1, "real Casualty captures only at failure")
                eq(f.n("ledger.commit"), 0, "failure itself never commits")
                f.unknown("failure delay")
                eq(f.n("ally.reset"), 0, "failure does not auto reset")
                eq(f.n("attrs.fillHp"), 0, "failure does not fill HP")
                for i, dt in ipairs(schedule) do
                    f.advance(dt)
                    if i < #schedule then f.unknown("split threshold not reached") end
                end
                local receipt = receiptCheck(f, stage[1], stage[3])
                eq(f.n("ally.reset"), 2, "bridge adds no extra unit reset")
                eq(f.n("attrs.fillHp"), 5, "existing recovery: enemy fill plus two fills per hero only")
                eq(f.n("attrs.heal"), 0, "bridge never performs ordinary healing")
                eq(f.n("talents.start"), 1, "existing battle talents start once")
                local counts = { f.n("ally.reset"), f.n("attrs.fillHp"), f.n("ledger.flush") }
                for _ = 1, 4 do f.advance(0.1) end
                eq(f.n("ally.reset"), counts[1], "following frames do not revive again")
                eq(f.n("attrs.fillHp"), counts[2], "following frames do not fill again")
                eq(f.n("ledger.flush"), counts[3], "following frames do not save again")
                check(same(f.Ledger.getReceipt(), receipt), "first receipt stable after re-entry and later frames")
                f.noRewards("later frames")
            end)
        end
    end
    runCase("real pause blocks delay despite large wall-clock dt", function()
        local f = fixture(); f.attach(); f.wipe(); f.advance(1)
        f.Scene.pause(); f.advance(20)
        eq(f.phases[#f.phases].after.defeatTimer, 1, "paused delay still one second")
        eq(f.n("ledger.capture"), 1, "pause did not recapture")
        eq(f.n("stage.load"), 0, "pause did not recover/load")
        f.unknown("paused")
        f.Scene.resume(); f.advance(0.25); f.unknown("1.25 second")
        f.advance(0.25); receiptCheck(f, 102, 101)
    end)
    runCase("death compaction retains receipt party slot order", function()
        local f = fixture(); f.attach()
        f.party[1], f.party[2] = f.party[2], f.party[1]
        f.wipe(); f.advance(1.5)
        receiptCheck(f, 102, 101, { 1, 2 })
        eq(f.Scene.getAllies()[1].heroId, 1, "actual restoreOrder restores original first slot")
    end)
    runCase("second actual recovery cannot overwrite first receipt", function()
        local f = fixture(102, true); f.attach(); f.wipe(); f.advance(1.5)
        local first = receiptCheck(f, 102, 102)
        f.wipe(); f.advance(1.5)
        eq(f.n("ledger.capture"), 2, "second real wipe takes its own context")
        eq(f.n("ledger.commit"), 2, "second real recovery reaches ledger")
        eq(f.n("ledger.accepted"), 1, "only first experience accepted")
        eq(f.n("ledger.flush"), 1, "second experience does not write again")
        check(same(f.Ledger.getReceipt(), first), "first receipt frozen")
        f.noRewards("second recovery")
    end)
end

local function exclusionCases()
    local specs = {
        { "timeout with alive party", function(f)
            f.advance(f.resolve("config.GameConfig").Battle.TIME_LIMIT_SEC)
            eq(f.n("legacy.allDead"), 1, "legacy notification still runs on timeout")
            eq(f.tracker.getState().defeatByTimeout, true, "actual Scene timeout flag")
        end },
        { "empty party", function(f) f.Scene.setAllies({}); f.advance(0) end },
        { "terminal temple", function(f) f.Scene.debugJumpToStage(999); f.wipe() end },
        { "one survivor", function(f)
            f.party[1].hp, f.party[1].attrs.final[f.AD.HP] = 0, 0; f.advance(0)
        end },
        { "actual artifact instant revive", function(f)
            local unit = f.party[1]
            unit.artifactEffects = { { effectType = "revive_damage_bonus", value = 50 } }
            f.ART.initBattle(f.party); f.wipe()
            eq(unit.hp, math.floor(unit.maxHp * 0.5 + 0.5), "actual ART half-HP revive happened")
            eq(f.n("visual.revive"), 1, "actual Casualty recognized artifact revive")
        end },
        { "actual talent guaranteed self revive", function(f)
            f.Scene.setAllies(f.makeParty({ 15 }))
            local unit = f.Scene.getAllies()[1]
            unit.awakeningNodes = { [3] = true, _awk3Migrated = true }
            f.wipe()
            eq(unit.hp, unit.maxHp, "actual TAL lover self revive happened")
            eq(f.n("visual.revive"), 1, "actual Casualty recognized talent revive")
        end },
        { "inconsistent displayed/attribute death", function(f)
            for _, unit in ipairs(f.party) do unit.hp = 0 end
            f.advance(0)
        end },
        { "alive ghost untargetable is not a wipe", function(f)
            for _, unit in ipairs(f.party) do unit.artifactUntargetable = true end
            f.advance(0)
        end },
    }
    for _, spec in ipairs(specs) do
        runCase("source excludes " .. spec[1], function()
            local f = fixture(); f.attach(); spec[2](f)
            eq(f.n("ledger.capture"), 0, "excluded actual source never issues a context ticket")
            f.unknown("excluded source before recovery")
            f.advance(1.5)
            eq(f.n("ledger.commit"), 0, "excluded source never commits after recovery delay")
            eq(f.n("ledger.flush"), 0, "excluded source does not write")
            f.unknown("excluded source after delay")
            f.noRewards("excluded source")
        end)
    end
end

-- 公共调试操作后的新真实全灭也不能开票；不只验证已捕获旧票被撤销。
-- debugInstantClear 的杀敌只作为明确调试来源，然后沿真实 reload 新建鲜活敌场，避免胜利短路。
local function debugSourceCases()
    local specs = {
        { "nonterminal debugJump", function(f) f.Scene.debugJumpToStage(103) end },
        { "debugInstantClear then real fresh load", function(f)
            f.Scene.debugInstantClear()
            f.Scene.reloadStage()
        end },
        { "debug setEnemies", function(f) f.Scene.setEnemies(f.Scene.getEnemies()) end },
    }
    local function rejectsNewWipe(f, label)
        local state = f.tracker.getState()
        check(f.SC.isTerminalTemple(state.currentStageId) == false, label .. " ordinary nonterminal source")
        check(state.battleActive == true and #state.enemies > 0, label .. " real active enemy field")
        check(state.enemies[1].hp > 0, label .. " living enemy avoids victory short circuit")
        local defeats, resets = f.n("legacy.allDead"), f.n("ally.reset")
        f.wipe()
        eq(f.n("legacy.allDead"), defeats + 1, label .. " actual Casualty processes new wipe")
        eq(f.tracker.getState().defeatTimer, 0, label .. " real defeat delay starts")
        eq(f.n("ledger.capture"), 0, label .. " debug source never captures new ticket")
        f.unknown(label .. " before recovery")
        f.advance(1); f.unknown(label .. " before threshold")
        f.advance(0.5)
        eq(f.tracker.getState().defeatTimer, nil, label .. " actual Phases recovery completed")
        eq(f.n("ally.reset"), resets + #f.Scene.getAllies(), label .. " recovery still resets each unit once")
        for _, unit in ipairs(f.Scene.getAllies()) do
            eq(unit.hp, unit.maxHp, label .. " gameplay recovery remains full HP")
            eq(unit.attrs.final[f.AD.HP], unit.hp, label .. " gameplay HP remains synchronized")
        end
        eq(f.n("ledger.capture"), 0, label .. " recovery did not retroactively capture")
        eq(f.n("ledger.commit"), 0, label .. " debug recovery never commits")
        eq(f.n("ledger.flush"), 0, label .. " debug recovery never saves receipt")
        f.unknown(label .. " after actual recovery")
        f.noRewards(label)
    end
    for _, spec in ipairs(specs) do
        runCase("new wipe excludes debug source " .. spec[1], function()
            local f = fixture(); f.attach(); spec[2](f)
            rejectsNewWipe(f, spec[1])
        end)
        runCase("debug source cannot be laundered by reload or party reset: " .. spec[1], function()
            local f = fixture(); f.attach(); spec[2](f)
            f.Scene.reloadStage()
            rejectsNewWipe(f, spec[1] .. " after same-stage public reload")
            f.Scene.setAllies(f.makeParty({ 2, 3 }))
            rejectsNewWipe(f, spec[1] .. " after new real party")
            f.attach()
            rejectsNewWipe(f, spec[1] .. " after callback reattach")
        end)
    end
    runCase("ordinary never-debugged scene remains eligible after reload and party change", function()
        local f = fixture(); f.attach()
        f.Scene.reloadStage()
        f.Scene.setAllies(f.makeParty({ 2, 3 }))
        f.wipe(); f.advance(1.5)
        receiptCheck(f, 102, 101, { 2, 3 })
    end)
end

local function victoryMarchCases()
    runCase("actual first-clear victory marches through pause and advances once at two seconds", function()
        local f = fixture(); f.attach()
        for _, unit in ipairs(f.Scene.getEnemies()) do unit.hp, unit.attrs.final[f.AD.HP] = 0, 0 end
        f.advance(0) -- 实际 Casualty 首通胜利 -> actual Nav.beginVictoryMarch。
        eq(f.n("reward.firstClear"), 1, "genuine first-clear notification once")
        eq(f.Scene.getStageId(), 102, "first-clear does not skip march")
        local march = assert(f.getVictoryMarch(), "actual host victoryMarch getter/setter not connected")
        eq(march.nextId, 103, "actual march reserves real next stage")
        eq(march.timer, 0, "actual march starts at zero")
        eq(f.tracker.getState().battleActive, false, "actual march stops combat")
        eq(f.n("stage.load"), 0, "no nextStage load at victory instant")
        eq(f.n("ledger.capture"), 0, "victory never captures wipe source")
        local combatTicks = f.n("tick.outsideRecovery")
        f.advance(1)
        eq(f.getVictoryMarch().timer, 1, "actual Nav march tick advances one second")
        eq(f.Scene.getStageId(), 102, "one-second march remains in source stage")
        f.Scene.pause(); f.advance(20)
        eq(f.getVictoryMarch(), march, "pause keeps actual host march identity")
        eq(march.timer, 1, "paused wall-clock does not advance march")
        eq(f.n("march.tick"), 1, "pause intercepted before actual navigation tick")
        eq(f.n("stage.load"), 0, "pause does not trigger nextStage")
        f.Scene.resume(); f.advance(0.75)
        eq(march.timer, 1.75, "split dt keeps real march below threshold")
        eq(f.n("stage.load"), 0, "1.75-second march has not loaded next stage")
        eq(f.n("tick.outsideRecovery"), combatTicks, "no attack tick while paused or marching")
        f.advance(0.25)
        eq(f.getVictoryMarch(), nil, "real march is consumed at two seconds")
        eq(f.Scene.getStageId(), 103, "actual forward-bound nextStage reaches reserved target")
        eq(f.n("stage.load"), 1, "actual nextStage loads exactly once")
        eq(f.n("stage.changed"), 1, "actual nextStage notification exactly once")
        eq(f.tracker.getState().battleActive, true, "real target battle active after navigation")
        for _ = 1, 4 do f.advance(0.1) end
        eq(f.n("stage.load"), 1, "following active frames do not repeat navigation")
        eq(f.n("stage.changed"), 1, "following active frames do not repeat stage notification")
        eq(f.n("reward.firstClear"), 1, "first-clear notification not repeated")
        eq(f.n("tick.outsideRecovery"), combatTicks + 4, "target reaches active tick on all later frames")
        eq(f.n("ledger.commit"), 0, "victory never commits rescue")
        eq(f.n("ledger.flush"), 0, "victory never saves rescue")
        f.unknown("real victory march")
        check(same(f.currency, { gold = 123, gems = 456 }), "victory test reward boundary leaves currency unchanged")
        check(same(outsideLedger(f.session), f.outside), "victory leaves story/outer ledgers unchanged")
    end)
end

local function invalidationCases()
    local changes = {
        { "different stage", function(f) f.Scene.debugJumpToStage(103) end },
        { "party replaced", function(f) f.Scene.setAllies(f.makeParty({ 2, 3 })) end },
        { "same IDs different units", function(f) f.Scene.setAllies(f.makeParty({ 1, 2 })) end },
        { "same-stage reload", function(f) f.Scene.reloadStage() end },
        { "reset generation", function(f) f.Scene.resetToDefault() end },
        { "context restore", function(f) f.Scene.restoreContext() end },
        { "same callback context reattach", function(f) f.attach() end },
        { "callbacks removed", function(f) f.Scene.setRescueCallbacks(nil, nil) end },
        { "generation cancel", function(f) f.tracker:cancel() end },
        { "same-party public reset", function(f) f.Scene.setAllies(f.party) end },
        { "party slot mutation", function(f) f.party[1].partySlot = 4 end },
        { "hero identity mutation", function(f) f.party[1].heroId = 3 end },
        { "unit reference mutation", function(f) f.party[1] = f.makeParty({ 1 })[1] end },
        { "stage-provider context mutation", function(f)
            f.stageConfig = setmetatable({}, { __index = f.SC })
        end },
        { "session silent swap", function(f) f.session = copy(f.session) end },
        { "story identity swap", function(f) f.session.samsaraStory = copy(f.session.samsaraStory) end },
        { "future story schema", function(f) f.session.samsaraStory.schemaVersion = 2 end },
        { "future rescue domain", function(f)
            f.session.samsaraStory.rescueLedger = { schemaVersion = 2, scope = "single_scene", keep = true }
        end },
        { "Ledger canceled", function(f) f.Ledger.cancel() end },
    }
    for _, spec in ipairs(changes) do
        runCase("pending recovery invalidated by " .. spec[1], function()
            local f = fixture(); f.attach(); f.wipe(); f.advance(0.5)
            eq(f.n("ledger.capture"), 1, "valid original wipe captured")
            spec[2](f)
            local afterChange = outsideLedger(f.session)
            f.advance(1)
            eq(f.n("ledger.accepted"), 0, "changed context never accepted as old rescue")
            eq(f.n("ledger.flush"), 0, "changed context does not persist rescue")
            f.unknown("invalidated context")
            check(same(outsideLedger(f.session), afterChange), "only intentional test mutation remains")
            eq(f.n("reward.kill"), 0, "no kill rewards from invalidation")
            eq(f.n("reward.firstClear"), 0, "no first-clear rewards from invalidation")
        end)
    end
    for _, point in ipairs({ "loadEnter", "loadExit", "talentsExit", "phaseExit", "stageChanged" }) do
        runCase("recovery callback reentry invalidates generation at " .. point, function()
            local f = fixture(); f.attach(); f.wipe()
            f.hooks[point] = function()
                f.hooks[point] = nil
                f.Scene.reloadStage() -- public same-stage actual load, not a forged generation field.
            end
            f.advance(1.5)
            eq(f.n("ledger.accepted"), 0, "reentrant reload rejects old recovery")
            eq(f.n("ledger.flush"), 0, "reentrant reload does not persist rescue")
            f.unknown("reentrant generation change")
            f.noRewards("reentrant load")
        end)
    end
end

local function failedRecoveryCases()
    for _, spec in ipairs({
        { "actual stage load throws", "loadEnter", function() error("fixture stage transport failure") end },
        { "actual restore callback throws", "afterReset", function() error("fixture restore observer failure") end },
        { "actual talent callback throws", "talentsExit", function() error("fixture start observer failure") end },
        { "recovery not full after actual reset", "talentsExit", function(f)
            local unit = f.Scene.getAllies()[1]
            unit.hp, unit.attrs.final[f.AD.HP] = unit.maxHp - 1, unit.maxHp - 1
        end },
        { "attrs/display mismatch after actual reset", "phaseExit", function(f)
            f.Scene.getAllies()[1].hp = 0
        end },
    }) do
        runCase("actual recovery failure rejects receipt: " .. spec[1], function()
            local f = fixture(); f.attach(); f.wipe()
            f.hooks[spec[2]] = function() f.hooks[spec[2]] = nil; spec[3](f) end
            local ok = pcall(f.advance, 1.5)
            if spec[1]:find("throws", 1, true) then eq(ok, false, "original error still propagates") end
            eq(f.n("ledger.accepted"), 0, "incomplete actual recovery never registers rescued")
            eq(f.n("ledger.flush"), 0, "incomplete actual recovery never persists receipt")
            f.unknown("recovery incomplete")
            f.noRewards("recovery failed")
        end)
    end
    runCase("later new genuine wipe can recover after canceled old generation", function()
        local f = fixture(); f.attach(); f.wipe(); f.Scene.reloadStage()
        f.unknown("old generation canceled")
        f.wipe(); f.advance(1.5)
        eq(f.n("ledger.capture"), 2, "new actual wipe captured independently")
        eq(f.n("ledger.commit"), 1, "only new recovery committed")
        eq(f.n("ledger.accepted"), 1, "new generation can produce trusted receipt")
        eq(f.Ledger.getExperience(), "rescued", "new confirmed experience")
        f.noRewards("fresh generation")
    end)
end

local function persistenceCases()
    runCase("actual receipt survives memory JSON save and failed Flush retry", function()
        local f = fixture(); f.attach(); f.flushResult = false; f.wipe(); f.advance(1.5)
        eq(f.n("ledger.accepted"), 1, "real recovery accepted even if Flush fails")
        eq(f.Ledger.isSavePending(), true, "actual Ledger pending save")
        eq(f.disk.samsaraStory, nil, "failed Flush never claims disk success")
        local receipt = assert(f.Ledger.getReceipt())
        f.Ledger.update(1); f.Ledger.update(0.75)
        eq(f.n("ledger.flush"), 1, "retry not before two seconds")
        f.flushResult = true; f.Ledger.update(0.25)
        eq(f.n("ledger.flush"), 2, "retry at two seconds once")
        eq(f.Ledger.isSavePending(), false, "retry succeeds")
        check(same(f.disk, cjson.decode(cjson.encode(f.session))), "actual committed receipt JSON roundtrip")
        check(same(f.Ledger.getReceipt(), receipt), "retry does not replace receipt")
        eq(f.Ledger.commit(f.lastTicket, f.lastReceipt), false, "consumed opaque ticket cannot replay")
        eq(f.Ledger.commit(copy(f.lastTicket), f.lastReceipt), false, "copied ticket cannot forge commit")
        f.noRewards("save retry")
    end)
end

-- 生命周期来自官方2D脚手架；专项不初始化UI、不订阅Update，不触碰真实玩家文件。
function Start()
    local originalRequire = require
    local loadedBefore = {}; for key, value in pairs(package.loaded) do loadedBefore[key] = value end
    local ok, err = pcall(function()
        originalRecoveryCases()
        chainCases()
        exclusionCases()
        debugSourceCases()
        victoryMarchCases()
        invalidationCases()
        failedRecoveryCases()
        persistenceCases()
    end)
    if not ok then check(false, "suite exception: " .. tostring(err)) end
    eq(require, originalRequire, "global require untouched")
    local packageUnchanged = true
    for key, value in pairs(loadedBefore) do if package.loaded[key] ~= value then packageUnchanged = false end end
    for key, value in pairs(package.loaded) do if loadedBefore[key] ~= value then packageUnchanged = false end end
    check(packageUnchanged, "global package.loaded untouched")
    print(PREFIX .. "RESULT cases=" .. passed .. "/" .. cases .. " assertions=" .. assertions .. " failures=" .. failures)
    if failures == 0 and cases > 0 and passed == cases then print(PREFIX .. "ALL PASS") end
    engine:Exit()
end
function Stop() end
