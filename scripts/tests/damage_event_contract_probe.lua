-- C批契约失败探针：真实公式／Driver／伤害结算，只观察参数与账量，不修生产。
-- CONFIRMED为契约偏差，HEALTHY为正常；待决保护路径不在本入口判定。
local AD = require("systems.AttributeDef")
local UA = require("systems.UnitAttributes")
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local TAL = require("systems.TalentManager")
local ESR = require("systems.EquipmentSetRuntime")
local ETS = require("systems.ExtraTalentSystem")
local ART = require("systems.ArtifactRuntime")
local SEM = require("systems.StatusEffectManager")
local TM = require("systems.ThreatManager")
local Driver = require("ui.battle.tri.BattleTriDriver")

local healthy, confirmed, harnessErrors = 0, 0, 0
local function observe(condition, name, details)
    if condition then healthy = healthy + 1 else confirmed = confirmed + 1 end
    print("[伤害契约][" .. (condition and "HEALTHY" or "CONFIRMED") .. "] " .. name .. " " .. details)
end

local function unit(name)
    local attrs = UA.create({ [AD.MAX_HP] = 10000, [AD.PHYS_ATK] = 1000,
        [AD.MAG_ATK] = 1000, [AD.HIT_VALUE] = 100000,
        atkType = AD.ATK_SLASH, armorType = AD.ARMOR_LEATHER })
    attrs:fillHp()
    local u = attrs:toBattleUnit(name, 1)
    u.awakeningNodes = { _awk3Migrated = true }
    u.advTalentIds, u.litNodeSet = {}, {}
    u._etsDisabled = true
    return u
end

local function rig(setId)
    local defender, attacker = unit("格挡者"), unit("攻击者")
    defender.heroId = 4
    attacker.monsterId, attacker.instanceId = 1, 93501
    local drv = Driver.new(935, { battleLab = true, timeLimit = 60,
        allyFactory = function() return { defender } end })
    drv:start(101)
    drv.enemies, drv.enemyQueue = { attacker }, {}
    drv.mount()
    TAL.initUnit(attacker)
    TM.onBattleStart(drv.allies, drv.enemies)
    TAL.onBattleStart(drv.allies, drv.enemies)
    defender.attrs._setFour, defender.attrs._setSix = setId, setId
    defender.attrs:setBases({ [AD.PHYS_BLOCK_RATE] = 100, [AD.PHYS_BLOCK_RATIO] = 60 })
    defender.attrs:fillHp()
    BC.syncUnitHp(defender)
    drv.introTimer = 0
    drv.bindContext()
    return drv, defender, attacker
end

local function spy(specs, body)
    local originals = {}
    for i, spec in ipairs(specs) do
        local original = spec[1][spec[2]]
        originals[i] = original
        spec[1][spec[2]] = function(...)
            spec[3](...)
            return original(...)
        end
    end
    local ok, err = pcall(body)
    for i, spec in ipairs(specs) do spec[1][spec[2]] = originals[i] end
    assert(ok, err)
end

local function settle()
    for _ = 1, 90 do PS.update(1 / 60) end
end

local function testBlockAmount()
    for _, shield in ipairs({ 0, 1000 }) do
        local _, defender, attacker = rig("ironwall")
        defender.attrs.energyShield = shield
        local seen = {}
        spy({
            { ESR, "onBlocked", function(target, _, amount)
                if target == defender then seen.block = amount end
            end },
            { TAL, "onDamageTaken", function(target, _, _, _, _, _, result)
                if target == defender then seen.result = result end
            end },
            { ETS, "onBlock", function(target, amount)
                if target == defender then seen.bank = amount end
            end },
        }, function()
            BC.performAttack(attacker, { defender }, false)
            settle()
        end)
        assert(seen.result, "必须走正式格挡和受击后处理")
        observe(seen.result.totalDamage == 440, "正式公式格挡后量", "expected=440 actual=" .. tostring(seen.result.totalDamage))
        observe(seen.block == 660, "铁壁挡量与盾吸收分开",
            "shield=" .. shield .. " expected=660 actual=" .. tostring(seen.block))
        observe(seen.bank == 660, "化劲使用真实挡量",
            "shield=" .. shield .. " expected=660 actual=" .. tostring(seen.bank))
    end
end

local function testCounterArgs()
    local _, defender, attacker = rig("ironwall")
    local args, actual = {}, 0
    local beforeCalls = 0
    spy({ { ART, "onBeforeTakeDamage", function(target)
        if target == attacker then beforeCalls = beforeCalls + 1 end
    end } }, function()
        ESR.onBlocked(defender, attacker, 660, function(target, damage, isTargetAlly, prefix, color, source, meta)
            args = table.pack(target, damage, isTargetAlly, prefix, color, source, meta)
            actual = BC.dealDamageToUnit(target, damage, isTargetAlly, prefix, color, source, meta)
            return actual
        end)
    end)
    observe(actual == 198, "铁壁反击仍实际结算一次", "expected=198 actual=" .. tostring(actual))
    observe(args[1] == attacker and args[3] == false, "友方格挡者反击敌方",
        "expectedTargetAlly=false actual=" .. tostring(args[3]))
    observe(args[6] == defender, "反击真实来源不是opts表",
        "sourceIsDefender=" .. tostring(args[6] == defender) .. " metaPresent=" .. tostring(args[7] ~= nil))
    observe(beforeCalls == 0, "反击noCounter到达结算入口", "expected=0 actual=" .. beforeCalls)
end

local function testPeriodicAndMetadata()
    local drv, defender, attacker = rig("starless")
    defender._setStarCd = 0
    for _, list in ipairs({ drv.allies, drv.enemies }) do
        for _, u in ipairs(list) do SEM.apply(u, SEM.FROZEN, 100, defender, {}) end
    end
    local calls, beforeCalls = {}, 0
    spy({
        { BC, "dealDamageToUnit", function(...) calls[#calls + 1] = table.pack(...) end },
        { ART, "onBeforeTakeDamage", function(target)
            if target == attacker then beforeCalls = beforeCalls + 1 end
        end },
    }, function()
        drv.mount()
        drv.bindContext()
        drv:tick(0.01)
    end)
    observe(#calls == 1 and attacker.hp == 8800, "真实周期无光落地一次",
        "calls=" .. #calls .. " hp=" .. attacker.hp)
    observe(beforeCalls == 0, "周期opts的noCounter保留", "expected=0 actual=" .. beforeCalls)
    observe(calls[1] and calls[1][7] and calls[1][7].noCounter == true,
        "周期opts进入第七参而非来源", "argc=" .. tostring(calls[1] and calls[1].n))
    for index, opts in ipairs({
        { instantDamage = true, noCounter = true },
        { instantDamage = true, noCounter = true, statCategory = "physical", critEligible = false },
    }) do
        local count, before = 0, attacker.hp
        spy({ { ART, "onBeforeTakeDamage", function(target)
            if target == attacker then count = count + 1 end
        end } }, function()
            BC.dealTalentDamage(defender, attacker, 100, false, "契约 ", nil, opts)
        end)
        observe(attacker.hp == before - 100, "天赋伤害真实落地一次", "variant=" .. index)
        observe(count == 0, "天赋opts投影保留noCounter", "variant=" .. index .. " actual=" .. count)
    end
end

function Start()
    print("[伤害契约] 开始；准备失败回归，不统一尚未确认的保护范围")
    for _, case in ipairs({ { "格挡账量", testBlockAmount }, { "铁壁参数", testCounterArgs },
        { "周期与天赋投影", testPeriodicAndMetadata } }) do
        local ok, err = pcall(case[2])
        if not ok then
            harnessErrors = harnessErrors + 1
            print("[伤害契约][HARNESS_ERROR] " .. case[1] .. " " .. tostring(err))
        end
    end
    print(string.format("[damage_event_contract_probe][SUMMARY] confirmed=%d healthy=%d harnessErrors=%d",
        confirmed, healthy, harnessErrors))
    print("[伤害契约] 完成；退出0仅表示探针完成，不代表契约已修")
    engine:Exit()
end
