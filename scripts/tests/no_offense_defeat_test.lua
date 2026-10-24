-- 无进攻能力专项：真实英雄/天赋/神器/投射物/驱动；不运行main、不读取玩家档。
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local ART = require("systems.ArtifactRuntime")
local Driver = require("ui.battle.tri.BattleTriDriver")
local Guard = require("systems.BattleOffenseGuard")
local Cap = require("systems.BattleOffenseCapabilities")

local checks, failures, cases = 0, 0, 0
local function check(value, message)
    checks = checks + 1
    if not value then failures = failures + 1; print("[no_offense_test] FAIL " .. message) end
end
local function case(name, fn)
    cases = cases + 1
    local ok, err = xpcall(fn, debug.traceback)
    check(ok, name .. " " .. tostring(err))
    print("[no_offense_test] CASE " .. name .. " " .. (ok and "DONE" or "ERROR"))
end
local function hero(id, stage)
    local nodes = { _awk3Migrated = true }
    for i = 1, stage or 0 do nodes[i] = true end
    return assert(HC.createHero(id, 1, nil, nodes, false))
end
local function fixture(ids)
    local allies = {}
    for _, id in ipairs(ids or { 19 }) do allies[#allies + 1] = hero(id) end
    local drv = Driver.new(2, { battleLab = true, timeLimit = 300,
        allyFactory = function() return allies end })
    drv:start(102)
    drv.introTimer = 0
    BC.mount(drv.combatState)
    BC.reset()
    PS.mount(drv.psState)
    PS.reset()
    return drv
end
local function lane(drv)
    return { allies = drv.allies, enemies = drv.enemies,
        combatState = drv.combatState, projectileState = drv.psState, semState = drv.semState,
        talentStates = drv.talUnitStates, talentRefs = drv.talRefs, etsState = drv.etsState }
end
local function prove(drv, expected, label)
    local value, reason = Cap.inspect(lane(drv))
    check(value == expected, label .. " result=" .. tostring(value) .. " reason=" .. tostring(reason))
end
local function ready(owner, lanes)
    check(not Guard.update(owner, 100, lanes, true), "首次观察不倒算100秒")
    for _ = 1, 4 do check(not Guard.update(owner, 1, lanes, true), "5秒前不失败") end
    check(Guard.update(owner, 1, lanes, true), "连续完整5秒失败")
    check(not Guard.update(owner, 1, lanes, true), "同一状态不重复失败")
end
local function basic()
    for _, id in ipairs({ 9, 15, 19, 23 }) do
        local drv = fixture({ id })
        prove(drv, true, "普通裸治疗可证明无进攻 " .. id)
        ready({}, { lane(drv) })
    end
    local drv = fixture({ 9, 15, 19, 23 })
    prove(drv, true, "四治疗阵容")
    local before = {}
    for i, unit in ipairs(drv.allies) do before[i] = unit.hp end
    ready({}, { lane(drv) })
    for i, unit in ipairs(drv.allies) do check(unit.hp == before[i], "判败不伪造治疗死亡 " .. i) end
end
local function clock()
    local drv = fixture()
    local lanes, owner = { lane(drv) }, {}
    Guard.update(owner, 1, lanes, true)
    Guard.update(owner, 4, lanes, true)
    check(not Guard.update(owner, 99, lanes, false), "暂停/入场/行军门禁不计时")
    ready(owner, lanes)
    for _, dt in ipairs({ 0, -1, math.huge, 0 / 0 }) do
        check(not Guard.update({}, dt, lanes, true), "非法dt不提前失败")
    end
    Guard.reset(owner)
    check(owner._noOffenseElapsed == nil, "reset释放计时和旧引用")
    Guard.update(owner, 1, lanes, true)
    Guard.update(owner, 4, lanes, true)
    local other = fixture()
    check(not Guard.update(owner, 1, { lane(other) }, true), "换战斗不继承旧四秒")
    check(owner._noOffenseElapsed == 0, "新引用建立新基线")
    Guard.update(owner, 4, { lane(other) }, true)
    local replacement = fixture()
    other.allies[1] = replacement.allies[1]
    other.talUnitStates[other.allies[1]] = replacement.talUnitStates[replacement.allies[1]]
    check(not Guard.update(owner, 1, { lane(other) }, true), "同一名册原表换人不沿用旧宽限")
    check(owner._noOffenseElapsed == 0, "原位换人重新建立基线")
    local a, b, c = fixture(), fixture(), fixture()
    local all = { lane(a), lane(b), lane(c) }
    ready({}, all)
    local damage = hero(1)
    c.allies[#c.allies + 1] = damage
    check(not Guard.update({}, 100, all, true), "终焉第三队仍有输出不败")
    check(not Guard.update({}, 100, {}, true), "空raid不以无进攻判败")
end
local function potential()
    local drv = fixture({ 19, 1 })
    prove(drv, false, "存在输出角色")
    drv.allies[2].hp = 0
    -- 死亡钩子由真实宿主处理；能力检查不代替复活裁决。
    drv.allies[2]._triDeathHandled = true
    drv.allies[2]._fallenPending = true
    drv.allies[2]._fallenGone = true
    drv.allies[2].reviveTimer = 0
    drv.talRefs.pendingDeaths = {}
    prove(drv, true, "已完成死亡处理的普通输出不永久阻挡")
    local healer = drv.allies[1]
    local original = healer.attrs.atkType
    healer.attrs.atkType = AD.ATK_FIRE
    prove(drv, false, "当前攻击类型可伤害优先于角色标签")
    healer.attrs.atkType = original
    healer.heroId = 9999
    prove(drv, false, "未知英雄保守放行")
    healer.heroId = 19
    healer.advTalentIds = { "future_offense" }
    prove(drv, false, "未知转职机制保守放行")
    healer.advTalentIds = { "gate_224_punish" }
    prove(drv, false, "罚忏未积累也保留未来转伤")
    healer.advTalentIds = { "adv_224_divine_punishment" }
    prove(drv, false, "旧惩戒机制不误判")
    healer.advTalentIds = {}
    healer.artifactEffects = { { effectType = "counter_attack", value = 80 } }
    drv.mount(); ART.initBattle(drv.allies)
    prove(drv, false, "反击神器队列为空仍有输出能力")
    healer.artifactEffects = { { effectType = "dodge_decay", value = 25 } }
    ART.initBattle(drv.allies)
    prove(drv, true, "普通防守神器不永久阻挡")
    healer.artifactEffects = { { effectType = "future_artifact", value = 1 } }
    ART.initBattle(drv.allies)
    prove(drv, false, "未知神器保守放行")
    healer.artifactEffects = {}; ART.initBattle(drv.allies)
    healer.attrs._setSix = "ironwall"
    prove(drv, false, "铁壁六件反伤")
    healer.attrs._setSix = "starless"
    prove(drv, false, "无星六件周期伤害")
    healer.attrs._setSix = nil
    healer.attrs._setFour = "swordgate"
    healer._setSwordDmgWin = 100
    prove(drv, false, "门剑池不抢在六秒释放前判败")
    healer._setSwordDmgWin = nil
    healer.attrs._setFour = nil
    prove(drv, true, "移除额外机制恢复可判断")
end
local function pending()
    local drv = fixture()
    local healer, enemy = drv.allies[1], drv.enemies[1]
    local states = drv.psState.projectiles
    local hits = 0
    local function callback() hits = hits + 1 end
    local function projectile(kind, side, source)
        return { onArrive = callback, arrived = false, hitResolved = false,
            offenseKind = kind, offenseSide = side, offenseSource = source, offenseOrigin = "normal_attack" }
    end
    states[1] = projectile("heal", "ally", healer)
    prove(drv, true, "已审计治疗在途不让自疗永久重置")
    states[2] = projectile("damage", "enemy", enemy)
    prove(drv, true, "普通敌方攻击在途不让裸奶永久重置")
    states[3] = projectile("damage", "ally", healer)
    prove(drv, false, "友方伤害在途保留翻盘")
    states[3].hitResolved = true
    states[3].arrived = true
    prove(drv, true, "已命中淡出不当仍在伤害")
    states[3] = { onArrive = callback, arrived = false }
    prove(drv, false, "未知回调不猜语义")
    states[3] = { pierceEvents = { { onHit = callback } }, nextEventIdx = 1 }
    prove(drv, false, "穿透未命中事件保留")
    states[3] = nil
    check(hits == 0, "能力查询不消费任何回调")
    drv.semState.effects[enemy] = { burning = { remaining = 10, data = { dps = 50 }, source = healer } }
    prove(drv, false, "来源死亡仍可运行的敌方燃烧保留")
    drv.semState.effects[enemy] = nil
    drv.combatState.comboQueue[1] = { attacker = healer, isAlly = true, targetIsAlly = false }
    prove(drv, false, "友方排队连击保留")
    drv.combatState.comboQueue = {}
    prove(drv, true, "在途结束后可重新开始完整宽限")
end
local function special()
    local drv = fixture({ 19, 20 })
    local gate = drv.allies[2]
    gate.hp = 0
    gate.awakeningNodes = { _awk3Migrated = true, true, true }
    local state = drv.talUnitStates[gate]
    state.starGateSummoned, state.starGateCount = true, 1
    prove(drv, false, "死后仍在发射的觉醒星门保留翻盘")
    state.starGateSummoned, state.starGateCount = false, 0
    prove(drv, false, "持续星门尚未召唤也不能抢在后续召门前判败")
    gate.awakeningNodes = { _awk3Migrated = true }
    gate._etsDisabled = true
    prove(drv, true, "明确取消持续星门能力后不永久阻挡")
    drv.etsState.iceStatues[1] = { target = drv.enemies[1], source = gate, hp = 1 }
    prove(drv, false, "死亡来源留下的冰雕仍保留")
    drv.etsState.iceStatues = {}
    prove(drv, true, "冰雕移除后重新可判断")

    local core = fixture({ 15 })
    local lover = core.allies[1]
    lover.awakeningNodes = { _awk3Migrated = true, true, true, true }
    lover._etsDisabled = false
    local CP = require("ui.character.panel.CharacterPanel")
    local original = CP.getOwnedHero
    local owned = { extraTalent = { issuedCards = 0 } }
    CP.getOwnedHero = function(id) if id == 15 then return owned end end
    local ok, err = xpcall(function()
        prove(core, true, "单奶无卡时圣核无伤害来源")
        core.etsState.pendingGrowth[15] = { issuedCards = 1 }
        prove(core, false, "圣核包含本场尚未提交的发卡成长")
        core.etsState.pendingGrowth = {}
        owned.extraTalent.issuedCards = 1
        prove(core, false, "圣核包含内存已提交卡数")
        lover.awakeningNodes = { _awk3Migrated = true }
        owned.awakening = { _awk3Migrated = true, true, true, true }
        prove(core, false, "实例尚未同步觉醒时遵循真实ETS账号回退圣核")
        lover._etsDisabled = true
        prove(core, true, "显式禁用不借账号圣核能力")
        gate._etsDisabled = false
        CP.getOwnedHero = function(id)
            if id == 20 then return { awakening = { _awk3Migrated = true, true, true } } end
            if id == 15 then return owned end
        end
        prove(drv, false, "未召门的死20仍遵循真实ETS账号持续觉醒回退")
    end, debug.traceback)
    CP.getOwnedHero = original
    check(ok, "圣核真实查询且恢复内存边界 " .. tostring(err))

    local a, b, c = fixture(), fixture(), fixture()
    local Raid = require("ui.battle.tri.TerminalRaid")
    local drivers = { a, b, c }
    local raid = Raid.new(102, drivers)
    for _, driver in ipairs(drivers) do
        driver.terminalRaid = raid
        driver._offenseEligible = true
    end
    check(not raid:updateOffense(100, true), "真实raid首次观察不倒算大dt")
    for _ = 1, 4 do check(not raid:updateOffense(1, true), "真实raid三队聚合不足5秒") end
    check(raid:updateOffense(1, true), "真实raid与真实能力查询完整5秒失败")
    check(raid.finished and not raid.won and raid.failureReason == "no_offense", "真实raid原因与终态")
    raid:release()

    local lifecycle = require("ui.battle.scene.BattleAllyLifecycle")
    local tower = require("config.TowerConfig")
    check(lifecycle.isTowerOffenseRegistryKnown(), "正式塔强化注册表均在纯治疗审计范围")
    local future = { effectType = "mechanic", mechanicId = "future_auto_damage" }
    tower.BUFFS[#tower.BUFFS + 1] = future
    local known = lifecycle.isTowerOffenseRegistryKnown()
    tower.BUFFS[#tower.BUFFS] = nil
    check(not known, "未来未知塔伤害机制保守禁用早败")
    check(lifecycle.isTowerOffenseRegistryKnown(), "测试恢复真实塔注册表")
end
local function production()
    for _, id in ipairs({ 9, 15, 19, 23 }) do
        local drv = fixture({ id })
        local healer = drv.allies[1] ---@type table
        healer.attrs:setBase(AD.MAX_HP, 100000000)
        healer.attrs:fillHp(); BC.syncUnitHp(healer)
        -- 真实普通战斗逻辑；仅隔离失败最终换关/保存边界。
        drv.battleLab = false
        local retreats, reports = 0, 0
        drv.retreatStage = function(self) retreats = retreats + 1; self.active = false end
        drv.onAllDead = function(_, _, reason)
            reports = reports + 1
            check(reason == "no_offense", "真实回调携带独立失败原因")
        end
        for _ = 1, 480 do
            if not drv.active then break end
            drv:activate(); drv:tick(1 / 60)
        end
        check(retreats == 1 and reports == 1, "持续真实自疗与敌人攻击仍在约5秒失败 id=" .. id
            .. " retreats=" .. retreats .. " reports=" .. reports)
        check(healer.hp > 0, "真实提前失败不把奶妈写成死亡 id=" .. id)
    end
    local drv = fixture()
    local ETS = require("systems.ExtraTalentSystem")
    local flush = ETS.flush
    local starts = 0
    drv.start = function() starts = starts + 1 end
    ETS.flush = function()
        drv.allies = { hero(19) }
        drv.stageId = 103
    end
    local ok, err = xpcall(function() drv:retreatStage("no_offense") end, debug.traceback)
    ETS.flush = flush
    check(ok, "成长结账同步换场不异常 " .. tostring(err))
    check(starts == 0 and drv.stageId == 103, "旧场无进攻失败不退回同步重开的新场")
end
function Start()
    print("[no_offense_test] START；只跑独立测试，不加载main/玩家档")
    local originalFile, originalFS, originalGetFS = File, fileSystem, GetFileSystem
    local deniedIo = 0
    local function denyIo()
        deniedIo = deniedIo + 1
        error("测试禁止原生玩家档读写")
    end
    rawset(_G, "File", denyIo)
    rawset(_G, "GetFileSystem", denyIo)
    rawset(_G, "fileSystem", setmetatable({}, { __index = denyIo, __newindex = denyIo }))
    for _, item in ipairs({ { "裸治疗与5秒", basic }, { "时钟与三队", clock },
        { "额外进攻与未知", potential }, { "在途与DOT", pending },
        { "星门圣核冰雕与真实终焉", special }, { "真实普通驱动", production } }) do
        case(item[1], item[2])
    end
    check(deniedIo == 0, "原生File/FS调用为零")
    rawset(_G, "File", originalFile)
    rawset(_G, "GetFileSystem", originalGetFS)
    rawset(_G, "fileSystem", originalFS)
    print(string.format("[no_offense_test] RESULT cases=%d checks=%d failures=%d %s",
        cases, checks, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
