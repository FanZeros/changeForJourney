-- 护盾生命周期隔离回归：执行真实出战创建、普攻、连击队列、投射物、通用伤害、UA/TAL/神器。
-- 独立入口，不 require main、不读写玩家档；仅展示/声音为边界替身。
-- /workspace/.cli/UrhoXRuntime tests/shield_battle_lifecycle_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
local checks, failures = 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then failures = failures + 1; print("[shield_lifecycle][FAIL] " .. label) end
end
local function near(a, b)
    return type(a) == "number" and math.abs(a - b) < 1e-7
end

-- 所有业务模块都在同一私有 _G 内加载，未知依赖立即报错，不回退真实存档/启动器。
local ALLOWED = {}
for name in string.gmatch([[
config.AdvancementConfig config.AffixConfig config.AwakeningConfig
config.StageConfig config.StageConfig_Normal config.StageConfig_Hard config.StageConfig_Nightmare
config.StageConfig_Hell config.StageConfig_Purgatory config.StageConfig_Torment
config.StageConfig_Torment2 config.StageConfig_Torment3 config.StageConfig_Torment4 config.StageConfig_Torment5
config.StageConfig_Annihilation config.StageConfig_Annihilation2 config.StageConfig_Annihilation3
config.StageConfig_Annihilation4 config.StageConfig_Annihilation5 config.StageExpHelper
config.TavernConfig config.DungeonIdleConfig config.IdleIncomeConfig
config.BlacksmithConfig config.ClassConfig config.EquipmentConfig config.EquipmentSetConfig
config.ExpTable config.GameConfig config.GameEvents config.HeroConfig config.MonsterConfig
config.DungeonConfig config.TowerConfig config.MapAffixConfig
core.BattleLayout core.EventBus core.GameState core.NumberUtil core.PlayerStore core.PerformanceMonitor
runtime.ClientDispatcher shared.ModuleRegistry shared.Protocol shared.SuccessNotificationContext
shared.heroes.HeroResonance shared.heroes.TeamSlots shared.schemas.CharacterSchema
shared.artifact.ArtifactDefs shared.artifact.ArtifactSchema shared.battle.BattleSchema
shared.currency.CurrencySchema shared.dungeon.DungeonSchema shared.dungeon.DungeonCompat
shared.equipment.EquipmentSchema shared.heroes.HeroesSchema shared.lootbox.LootboxSchema
shared.player.PlayerSchema shared.profile.ProfileSchema shared.quota.QuotaSchema
shared.redeem.RedeemSchema shared.session.SessionSchema shared.signin.SigninSchema
shared.slotenhance.SlotEnhanceSchema shared.talents.TalentsSchema shared.task.TaskSchema
shared.task.TaskCompat shared.tavern.TavernSchema
systems.ArtifactBridge systems.ArtifactRuntime systems.AttributeDef systems.AwakeningGrowth
systems.BattleDiag systems.BattleStats systems.ClassGateRuntime systems.CombatFormula
systems.BattleOffenseGuard systems.BattleOffenseCapabilities
systems.CombatPower systems.CombatPowerEstimate systems.DropSystem systems.EquipmentPower
systems.EquipmentQuery systems.EquipmentSecondaryStats systems.EquipmentSetRuntime
systems.EquipmentSetSystem systems.EquipmentSystem systems.EquipmentStatGrowth systems.ExtraTalentSystem
systems.LootBoxSystem systems.MapAffixSystem systems.RelicConditionHandler systems.StatusEffectManager
systems.TalentEffect systems.TalentManager systems.ThreatManager systems.UnitAttributes
systems.talents.TalentAfterAttack systems.talents.TalentAlex systems.talents.TalentAllyDeath
systems.talents.TalentAyane systems.talents.TalentBeforeAttack systems.talents.TalentComboAttack
systems.talents.TalentDamageTaken systems.talents.TalentElwyn systems.talents.TalentEnemyDeath
systems.talents.TalentFatFish systems.talents.TalentFourNew systems.talents.TalentLuoxing
systems.talents.TalentMelissa systems.talents.TalentModifyDamage systems.talents.TalentRosa
systems.talents.TalentSera systems.talents.TalentSuhua systems.talents.TalentUpdate systems.talents.TalentXin
ui.battle.combat.BattleAttackChain ui.battle.combat.BattleClock ui.battle.combat.BattleCombat
ui.battle.combat.BattleCombatAnim ui.battle.combat.BattleCombatCombo ui.battle.combat.BattleCombatFx
ui.battle.combat.BattleMotionPolish ui.battle.combat.ProjectileSystem
ui.battle.scene.DamageTypeIcon ui.battle.stage.BattleEnemySpawn
ui.character.panel.CharacterPanel ui.character.panel.CharacterDeploy ui.character.panel.CharacterInput
ui.character.panel.CharacterHeroSync ui.character.panel.CharacterPower ui.character.panel.CharacterProgress
config.DialogueConfig config.HeroAssetUtil config.BossAffixConfig
systems.BattleTimeout systems.BossAffixSystem
ui.battle.combat.BattleEffects ui.battle.scene.BattleMountScope ui.battle.scene.BattleAllyLifecycle
ui.battle.scene.BattleAllyReset ui.battle.stage.BattleStageFlow ui.battle.stage.StageBerserk
ui.battle.tri.BattleTriDriver ui.widget.SpeechBubble
ui.character.panel.CharacterRosterSort ui.dungeon.DungeonBattle ui.dungeon.DungeonCombatRuntime
]], "%S+") do ALLOWED[name] = true end

local function fixture()
    local loaded = {}
    -- 私有确定性RNG：真实公式仍roll命中/暴击/连击，不消费或改写宿主math.random种子。
    local privateMath = {} ---@type table<string, any>
    local seed = 93201
    for key, value in pairs(math) do privateMath[key] = value end
    privateMath.random = function(lo, hi)
        seed = (seed * 48271) % 2147483647
        local roll = seed / 2147483647
        if lo == nil then return roll end
        if hi == nil then hi, lo = lo, 1 end
        return lo + math.floor(roll * (hi - lo + 1))
    end
    privateMath.randomseed = function(value) seed = value end
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
        math = privateMath, table = table, string = string, print = print, unpack = table.unpack,
        os = { clock = os.clock }, time = { elapsedTime = 0 },
    }
    env._G = env
    local display = {
        MAX_SLOTS = 4, MAX_PER_ROW = 5, CARD_W = 198, CARD_H = 350,
        CARD_SPACING = 7, CARD_CY = 544, ROW1_CY = 900, ROW_SPACING = 300,
        NAME_BG_DY = 0, NAME_BG_H = 40, SCROLL_TOP = 700, SCROLL_BOTTOM = 2300,
        SCROLL_LEFT = 0, SCROLL_RIGHT = 1080, DESIGN_W = 1080, ROSTER_BOTTOM_DY = 150,
    }
    local boundaries = {
        ["systems.GameSFX"] = { play = function() end, preload = function() end },
        ["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return true end },
        ["ui.character.detail.CharacterDetail"] = {},
        ["ui.character.panel.CharacterPanelDraw2"] = display,
        ["ui.hud.BottomNav"] = {},
    }
    local function import(name)
        if boundaries[name] then return boundaries[name] end
        if loaded[name] then return loaded[name] end
        assert(ALLOWED[name], "shield sandbox: unexpected require " .. tostring(name))
        local path = name:gsub("%.", "/") .. ".lua"
        local file = assert(cache:GetFile(path), "missing source " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local value = assert(load(table.concat(lines, "\n"), "@shield-private/" .. path, "t", env))()
        loaded[name] = value
        return value
    end
    env.require = import
    return { import = import, env = env }
end

local function testDeployment(f)
    local AD, HC = f.import("systems.AttributeDef"), f.import("config.HeroConfig")
    local CP = f.import("ui.character.panel.CharacterPanel")
    local CD, Store = f.import("runtime.ClientDispatcher"), f.import("core.PlayerStore")
    local ES, AB = f.import("systems.EquipmentSystem"), f.import("systems.ArtifactBridge")
    -- 真实装备与神器属性管线；只在私有 PlayerStore 提供明确的内存数据。
    local item = assert(ES.generate("O13", 1, 1))
    item.baseStats = { { AD.ENERGY_SHIELD, 100 }, { AD.FINAL_ENERGY_SHIELD_BONUS, 30 } }
    item.affixes = {}
    local equipment = { inventory = { ["1"] = item }, equipped = { ["2"] = { offhand = 1 } } }
    local artifacts = { bag = { { id = "shield-test", artifactId = 2, value = 50,
        threatClearValue = 50, quality = 1 } }, equippedByTeam = { [1] = { [2] = { [1] = "shield-test" } } } }
    CD.set("equipment", equipment, { normalized = true })
    Store.Get = function(key) if key == "equipment" then return equipment
        elseif key == "artifacts" then return artifacts end end
    local raw = assert(HC.createHero(2, 1, nil, nil, false))
    local beforeFill = {}
    local originalApply = AB.applyToUnit
    AB.applyToUnit = function(attrs, slot, data, team)
        local result = originalApply(attrs, slot, data, team)
        -- 观测真实属性结算后的缺口，并模拟已有临时盾/恢复CD，不能被入场补盾抹掉。
        beforeFill[slot] = { current = attrs.energyShield, maximum = attrs:get(AD.ENERGY_SHIELD) }
        attrs.tempEnergyShield, attrs.esRegenCooldown = 37, 9
        return result
    end
    local team = CP.getDeployedTeam(1)
    AB.applyToUnit = originalApply
    local mage = assert(team[2])
    check(#team == 3 and mage.heroId == 2, "真实getDeployedTeam创建默认出战队伍")
    check(beforeFill[2].maximum > raw.attrs:get(AD.ENERGY_SHIELD)
        and beforeFill[2].current < beforeFill[2].maximum, "装备/神器实际增加盾上限，补盾前存在缺口")
    check(near(mage.attrs.energyShield, mage.attrs:get(AD.ENERGY_SHIELD)), "最终装备/神器结算后入场满常规盾")
    check(mage.attrs.esRegenCooldown == 0 and mage.attrs.tempEnergyShield == 37, "入场清恢复CD但保留临时盾")
    check(mage.hp == mage.maxHp and mage.hp == mage.attrs:get(AD.HP), "入场HP及flat字段保持同步")
    mage.attrs:takeDamage(50)
    local spent, cooldown = mage.attrs.energyShield, mage.attrs.esRegenCooldown
    mage.attrs:fillHp()
    mage.attrs:addModifier("runtime_shield_capacity", { { key = AD.ENERGY_SHIELD, flat = 100 } })
    check(mage.attrs.energyShield == spent and mage.attrs.esRegenCooldown == cooldown,
        "运行中fillHp与属性recalc不刷当前盾/清CD")
    local fresh = assert(CP.getDeployedTeam(1)[2])
    check(fresh ~= mage and fresh.attrs ~= mage.attrs
        and near(fresh.attrs.energyShield, fresh.attrs:get(AD.ENERGY_SHIELD)), "再次新出战创建独立满盾实例")
    check(mage.attrs.energyShield == spent, "新出战构建不补旧战斗实例的盾")
    Store.Get = function() return nil end
    CD.set("equipment", {}, { normalized = true })
end

local function battle(f, targetIsAlly)
    local AD, UA = f.import("systems.AttributeDef"), f.import("systems.UnitAttributes")
    local BC, PS = f.import("ui.battle.combat.BattleCombat"), f.import("ui.battle.combat.ProjectileSystem")
    local TAL, TM = f.import("systems.TalentManager"), f.import("systems.ThreatManager")
    local ART, SEM = f.import("systems.ArtifactRuntime"), f.import("systems.StatusEffectManager")
    local RCH, ETS = f.import("systems.RelicConditionHandler"), f.import("systems.ExtraTalentSystem")
    BC.mount(BC.newState("shield-test")); PS.mount(PS.newState())
    TAL.mount(TAL.newBattleRefs()); TAL.mountUnitStates(TAL.newUnitStates())
    TM.mount(TM.newState()); SEM.mount(SEM.newSemState())
    RCH.mount(RCH.newState()); ETS.mount(ETS.newState())
    f.import("systems.BattleStats").mount(932)
    local function unit(name, id)
        local attrs = UA.create({ [AD.MAX_HP] = 100000, [AD.ENERGY_SHIELD] = 1000,
            [AD.PHYS_ATK] = 1000, [AD.HIT_VALUE] = 100000,
            [AD.CRIT_RATE] = 0, [AD.PHYS_CRIT_RATE] = 0, [AD.COMBO_RATE] = 0,
            [AD.PHYS_BLOCK_RATE] = 0, [AD.MAG_BLOCK_RATE] = 0 })
        attrs:fillHp(); attrs.atkCoeff = 1
        local u = attrs:toBattleUnit(name, 1)
        u.instanceId, u.atkTargets = id, 1
        return u
    end
    local attacker, target = unit("护盾攻击者", 9301), unit("护盾受击者", 9302)
    target.litNodeSet = { [203] = true }
    target.artifactEffects = { { effectType = "shield_threat_clear", threatClearValue = 50 } }
    local allies = targetIsAlly and { target } or { attacker }
    local enemies = targetIsAlly and { attacker } or { target }
    TAL.initUnit(attacker); TAL.initUnit(target)
    ART.initBattle({ target })
    TM.setThreat(target, 1000)
    local projectiles, landings = 0, 0
    BC.setContext({ getAllies = function() return allies end, getEnemies = function() return enemies end,
        onAttackHit = function(a, t, ax, ay, tx, ty, result, applyHit)
            projectiles = projectiles + 1
            -- 使用正式投射物update调用真实伤害闭包，而非测试直接调用闭包。
            PS.spawn(1, ax, ay, tx, ty, function()
                landings = landings + 1
                applyHit()
            end)
        end,
    })
    local b = { AD = AD, BC = BC, PS = PS, TAL = TAL, TM = TM, ART = ART,
        attacker = attacker, target = target, allies = allies, enemies = enemies,
        targetIsAlly = targetIsAlly, starCalls = 0, damageCalls = 0 }
    local takeDamage = target.attrs.takeDamage
    target.attrs.takeDamage = function(self, ...)
        b.damageCalls = b.damageCalls + 1
        return takeDamage(self, ...)
    end
    f.originalStar = f.originalStar or TAL.onStarShieldBreak
    TAL.onStarShieldBreak = function(u)
        b.starCalls = b.starCalls + 1
        return f.originalStar(u)
    end
    function b:setShield(regular, temporary)
        target.attrs.energyShield, target.attrs.tempEnergyShield = regular, temporary
    end
    function b:flushProjectile()
        for _ = 1, 90 do PS.update(1 / 60) end
    end
    function b:hit(kind)
        local oldDamage, oldLandings = self.damageCalls, landings
        if kind == "generic" then
            BC.dealDamageToUnit(target, 1000, targetIsAlly, "", {}, attacker)
        elseif kind == "normal" then
            BC.performAttack(attacker, targetIsAlly and allies or enemies, not targetIsAlly)
            check(self.damageCalls == oldDamage, "普攻未落地前不扣血/破盾")
            self:flushProjectile()
            check(landings == oldLandings + 1, "普攻投射物实际落地一次")
        else
            -- 先经真实普攻roll并创建连击队列，再单独布置待测连击命中边界。
            local savedES, savedTemp = target.attrs.energyShield, target.attrs.tempEnergyShield
            target.attrs.energyShield, target.attrs.tempEnergyShield = 1000000, 0
            attacker.attrs:setBase(AD.COMBO_RATE, 100)
            BC.performAttack(attacker, targetIsAlly and allies or enemies, not targetIsAlly)
            self:flushProjectile()
            check(#BC.mountedState().comboQueue == 1, "真实普攻100%连击只排一个额外攻击")
            attacker.attrs:setBase(AD.COMBO_RATE, 0)
            self:setShield(savedES, savedTemp)
            self.starCalls, self.damageCalls = 0, oldDamage
            BC.updateComboQueue(0.5)
            check(self.damageCalls == oldDamage and #BC.mountedState().comboQueue == 0,
                "连击队列已消费，投射物未落地不扣血/破盾")
            self:flushProjectile()
            check(landings == oldLandings + 2, "主击与连击各自仅一次真实投射物落地")
        end
        check(self.damageCalls == oldDamage + 1, kind .. "待测命中真实takeDamage只调用一次")
    end
    return b
end

local function testDamageEntries(f)
    for _, kind in ipairs({ "generic", "normal", "combo" }) do
        for _, targetIsAlly in ipairs({ false, true }) do
            local label = kind .. (targetIsAlly and "打己方" or "打敌方")
            local b = battle(f, targetIsAlly)
            local t = b.target
            b:setShield(100, 50)
            b:hit(kind)
            local maxES = math.floor(t.attrs:get(b.AD.ENERGY_SHIELD) + 0.5)
            local gain = math.max(1, math.floor(maxES * 0.15 + 0.5))
            check(b.starCalls == 1 and t.attrs.energyShield == gain and t.attrs.tempEnergyShield == 0,
                label .. "总盾真正归零只恢复一次15%常规盾")
            check(b.TM.getThreat(t) == 500, label .. "神器先看到破盾清50%仇恨，未被回复盾掩盖")
            check(b.TAL.mountedUnitStates()[t].wardBreakCd == 8, label .. "真实星图state置8秒CD")
            check(t.hp > 0 and t.hp == t.attrs:get(b.AD.HP), label .. "打穿盾后真实HP同步且仍存活")

            -- 同一目标8秒内再打穿：仍有破盾通知，但星图不重复回复。
            b:setShield(100, 0)
            b:hit(kind)
            check(t.attrs.energyShield == 0 and b.TAL.mountedUnitStates()[t].wardBreakCd == 8,
                label .. "CD内再次真实破盾不回复也不重置CD")
            b.TAL.update(7.99, b.allies, b.enemies, {})
            check(near(b.TAL.mountedUnitStates()[t].wardBreakCd, 0.01), label .. "真实update7.99秒CD未到期")
            b:setShield(100, 0); b:hit(kind)
            check(t.attrs.energyShield == 0, label .. "7.99秒时再次破盾仍不回复")
            b.TAL.update(0.011, b.allies, b.enemies, {})
            b:setShield(100, 0); b:hit(kind)
            check(t.attrs.energyShield == gain and b.TAL.mountedUnitStates()[t].wardBreakCd == 8,
                label .. "累计超过8秒真实命中再次回复并重启8秒")
            check(b.TM.getThreat(t) == 500, label .. "神器一次性破盾效果不随星图CD重新清仇恨")
        end
    end
end

local function testShieldContract(f)
    for _, kind in ipairs({ "generic", "normal", "combo" }) do
        -- 临时盾外层先被打空，但常规盾还在：不是总盾破碎。
        local b = battle(f, true)
        b:setShield(100000, 1); b:hit(kind)
        check(b.starCalls == 0 and b.target.attrs.energyShield > 0 and b.target.attrs.tempEnergyShield == 0,
            kind .. "只破临时盾、常规盾尚存不触发203")
        check(b.TM.getThreat(b.target) == 1000, kind .. "总盾尚存神器也不触发")

        -- 纯临时盾、无常规容量：遵守通用通知口径，但203不凭空制造常规盾或消费CD。
        b = battle(f, true)
        b.target.attrs:setBase(b.AD.ENERGY_SHIELD, 0)
        b:setShield(0, 100); b:hit(kind)
        check(b.starCalls == 1 and b.target.attrs:get(b.AD.ENERGY_SHIELD) == 0
            and b.target.attrs.energyShield == 0 and b.TAL.mountedUnitStates()[b.target].wardBreakCd == 0,
            kind .. "无常规容量的纯临时盾破碎不获203回复/不消费CD")
        check(b.TM.getThreat(b.target) == 500, kind .. "纯临时盾总量破碎仍保留神器契约")

        -- 有常规容量、当前仅临时盾：原通用契约将合计归零视为破盾，保留该语义。
        b = battle(f, true); b:setShield(0, 100); b:hit(kind)
        check(b.starCalls == 1 and b.target.attrs.energyShield > 0,
            kind .. "有常规容量、当前仅临时盾总量破碎沿用通用203契约")

        b = battle(f, true); b:setShield(0, 0); b:hit(kind)
        check(b.starCalls == 0 and b.target.attrs.energyShield == 0,
            kind .. "起初无盾不触发破盾恢复")
        b = battle(f, true); b.target.litNodeSet = {}; b:setShield(100, 0); b:hit(kind)
        check(b.target.attrs.energyShield == 0 and b.TAL.mountedUnitStates()[b.target].wardBreakCd == 0,
            kind .. "未点亮203不回复/不消费CD")

        b = battle(f, true); b:setShield(100, 0)
        b.target.attrs.final[b.AD.HP] = 1; b.BC.syncUnitHp(b.target)
        b:hit(kind)
        check(b.target.hp == 0 and b.target.attrs:get(b.AD.HP) == 0
            and b.target.attrs.energyShield == 0 and b.TAL.mountedUnitStates()[b.target].wardBreakCd == 0,
            kind .. "破盾同时致死不被203复活、不回复死者盾/消费CD")
        local hits = b.damageCalls
        b.BC.dealDamageToUnit(b.target, 1000, true, "", {}, b.attacker)
        check(b.damageCalls == hits and b.target.hp == 0, kind .. "死亡后通用入口拒绝再结算/复活")
    end
end

local function testElwynBreak(f)
    local HC = f.import("config.HeroConfig")
    for _, kind in ipairs({ "generic", "normal", "combo" }) do
        for _, star in ipairs({ false, true }) do
            local b = battle(f, true)
            local elwyn = assert(HC.createHero(23, 1, nil,
                { [1] = true, [2] = true, [3] = true, _awk3Migrated = true }, false))
            b.allies[#b.allies + 1] = elwyn
            -- 固定选敌为唯一受击者；Elwyn本人不可被普攻/连击随机转火。
            elwyn.artifactUntargetable = true
            b.TAL.initUnit(elwyn)
            b.target.litNodeSet = star and { [203] = true } or {}
            b:setShield(100, 0)
            b.TAL.update(0, b.allies, b.enemies, {})
            b:hit(kind)
            check((b.target.attrs.energyShield > 0) == star,
                kind .. "Elwyn组合中203仍按是否点亮独立回复")
            b.TAL.update(0.01, b.allies, b.enemies, {})
            local s = b.TAL.mountedUnitStates()[elwyn]
            check(b.target._elwynInvulnTimer == 2 and near(s.elwynInvulnProcChance, 0.5),
                kind .. "203=" .. tostring(star) .. "破盾后真实Elwyn7只触发一次2秒无敌")
            b.TAL.update(0.01, b.allies, b.enemies, {})
            check(near(b.target._elwynInvulnTimer, 1.99) and near(s.elwynInvulnProcChance, 0.5),
                kind .. "pending破盾已消费，下一tick不重复触发/延长无敌")
        end
    end
end

local function testFinalBattleEntry(f)
    local AD, HC = f.import("systems.AttributeDef"), f.import("config.HeroConfig")
    local CP, Stage = f.import("ui.character.panel.CharacterPanel"), f.import("ui.battle.stage.BattleStageFlow")
    local function elwyn()
        return assert(HC.createHero(23, 1, nil,
            { [1] = true, [2] = true, [3] = true, _awk3Migrated = true }, false))
    end
    local b = battle(f, true)
    local team = CP.getDeployedTeam(1)
    local mage = assert(team[2])
    check(mage._needsInitialShieldFill == true, "getDeployedTeam新实例携带一次最终补盾标记")
    local oldMax = mage.attrs:get(AD.ENERGY_SHIELD)
    team[#team + 1] = elwyn()
    -- Elwyn也来自新实例，但此处只验真正getDeployed创建的mage消费边界。
    Stage.startBattleTalents(team, {})
    check(mage.attrs:get(AD.ENERGY_SHIELD) > oldMax,
        "真实开战Elwyn觉醒提高已有常规盾上限")
    check(near(mage.attrs.energyShield, mage.attrs:get(AD.ENERGY_SHIELD))
        and not mage._needsInitialShieldFill, "StageFlow仅新实例在全部开战modifier后补满并消费标记")
    mage.attrs:takeDamage(50)
    local spent, cd = mage.attrs.energyShield, mage.attrs.esRegenCooldown
    Stage.startBattleTalents(team, {})
    check(mage.attrs.energyShield == spent and mage.attrs.esRegenCooldown == cd,
        "同一实例重复StageFlow开战/换波不刷盾或清恢复CD")

    local Driver = f.import("ui.battle.tri.BattleTriDriver")
    local created = {}
    local driver = Driver.new(933, { battleLab = true, allyFactory = function()
        local fresh = CP.getDeployedTeam(1)
        fresh[#fresh + 1] = elwyn()
        created[#created + 1] = fresh
        return fresh
    end })
    driver:start(101)
    local first = driver.allies[2]
    check(near(first.attrs.energyShield, first.attrs:get(AD.ENERGY_SHIELD))
        and first.attrs:get(AD.ENERGY_SHIELD) > oldMax and not first._needsInitialShieldFill,
        "真实TriDriver:start开战天赋及狂暴初始化后新实例满盾且清标记")
    first.attrs:takeDamage(50)
    local oldShield = first.attrs.energyShield
    driver:start(101)
    local second = driver.allies[2]
    check(second ~= first and second.attrs ~= first.attrs and #created == 2
        and near(second.attrs.energyShield, second.attrs:get(AD.ENERGY_SHIELD)),
        "TriDriver真实重开重新创建满盾实例")
    check(first.attrs.energyShield == oldShield, "TriDriver重开不补旧实例消耗的盾")
    check(b.target.hp > 0, "另一场战斗的单位未被新场补盾流程改死")
end

function Start()
    print("[shield_battle_lifecycle_test] 开始，真实业务模块、私有加载环境")
    local ok, err = xpcall(function()
        local f = fixture()
        testDeployment(f)
        testDamageEntries(f)
        testShieldContract(f)
        testElwynBreak(f)
        testFinalBattleEntry(f)
        check(f.env.File == nil and f.env.io == nil and f.env.network == nil,
            "业务环境不暴露存档File/io/网络")
        check(f.env.math ~= math and f.env.math.random ~= math.random,
            "私有RNG不污染宿主全局随机种子")
    end, debug.traceback)
    if not ok then check(false, tostring(err)) end
    print(string.format("[shield_battle_lifecycle_test] assertions=%d failures=%d %s",
        checks, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
