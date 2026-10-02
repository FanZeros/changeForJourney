-- 角色/觉醒/套装只读审计探针：复用正式模块，不修改玩法数值。
-- 跑法：./.cli/UrhoXRuntime tests/skill_balance_audit_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- CONFIRMED 表示已复现偏离健康行为；不是正常回归测试通过。
local AD = require("systems.AttributeDef")
local UA = require("systems.UnitAttributes")
local HC = require("config.HeroConfig")
local AC = require("config.AwakeningConfig")
local ETS = require("systems.ExtraTalentSystem")
local TAL = require("systems.TalentManager")
local SEM = require("systems.StatusEffectManager")
local CF = require("systems.CombatFormula")
local ESR = require("systems.EquipmentSetRuntime")
local BC = require("ui.battle.combat.BattleCombat")
local Driver = require("ui.battle.tri.BattleTriDriver")
local Reset = require("ui.battle.scene.BattleAllyReset")

local confirmed, healthy, errors = 0, 0, 0

local function observe(id, condition, details)
    if condition then
        healthy = healthy + 1
        print("[Audit][HEALTHY] " .. id .. " " .. details)
    else
        confirmed = confirmed + 1
        print("[Audit][CONFIRMED] " .. id .. " " .. details)
    end
end

local function probe(id, fn)
    local ok, err = pcall(fn)
    if not ok then
        errors = errors + 1
        print("[Audit][HARNESS_ERROR] " .. id .. " " .. tostring(err))
    end
end

local function unit(config, four, six)
    local attrs = UA.create(config)
    attrs:fillHp()
    attrs:recalc()
    local u = attrs:toBattleUnit("审计单位", 1)
    u.atkInterval = attrs:getActualInterval()
    attrs._setFour, attrs._setSix = four, six
    return u
end

local function hero(id, awakening)
    return assert(HC.createHero(id, 1, nil, awakening, false))
end

local function awakening(first, second, third)
    return { [1] = first, [2] = second, [3] = third, _awk3Migrated = true }
end

function Start()
    print("[Audit] 开始；只复现行为，不修复或宣称平衡已验证")

    probe("小雀开战", function()
        TAL.reset()
        local a, e = hero(8), hero(1)
        TAL.initUnit(a)
        TAL.initUnit(e)
        local ok, err = pcall(TAL.onBattleStart, { a }, { e })
        observe("小雀开战依赖", ok, tostring(err))
    end)

    probe("新三阶映射", function()
        local aw = awakening(true)
        local second, third = AC.hasNode(aw, 2), AC.hasNode(aw, 3)
        observe("原生三阶不可使用旧节点查询", not second and not third,
            "仅I：hasNode(2)=" .. tostring(second) .. " hasNode(3)=" .. tostring(third))
        TAL.reset()
        local a, e = hero(18, aw), hero(1)
        TAL.onBattleStart({ a }, { e })
        observe("老六I不应提前延长隐身", a._laoliuStealthLeft == 4,
            "仅I隐身=" .. tostring(a._laoliuStealthLeft) .. "秒，文案延长属于II")
    end)

    probe("成长夹血", function()
        local attrs = UA.create({ [AD.MAX_HP] = 100 })
        ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 100 }), awakening(true))
        attrs:fillHp()
        attrs:recalc()
        local before = attrs:get(AD.HP)
        ETS.applyToAttrs(1, attrs, ETS.normalize({ stacks = 101 }), awakening(true))
        local after = attrs:get(AD.HP)
        observe("永久成长更新不应降低当前HP", after >= before,
            "旧HP=" .. before .. " 新HP=" .. after .. " 新上限=" .. attrs:get(AD.MAX_HP))
    end)

    probe("分摊致死成长", function()
        local u = unit({ [AD.MAX_HP] = 100 })
        u.heroId = 10
        u.awakeningNodes = awakening(true)
        u.attrs.final[AD.HP], u.hp = 0, 0
        ETS.onShareFatal(u)
        observe("永久生命成长不得自行复活", u.hp == 0,
            "分摊致死后HP=" .. tostring(u.hp) .. " 上限=" .. tostring(u.maxHp))
    end)

    probe("复活共鸣概率", function()
        TAL.reset()
        local lover, dying, enemy = hero(15, awakening(true, true)), hero(1), hero(2)
        TAL.onBattleStart({ lover, dying }, { enemy })
        dying.attrs.final[AD.HP], dying.hp = 0, 0
        local oldRandom = math.random
        math.random = function() return 0.99 end
        local ok, revived = pcall(TAL.onAllyDeath, dying, { lover, dying }, BC.syncUnitHp)
        math.random = oldRandom
        assert(ok, revived)
        observe("共鸣60%不应通过0.99概率值", not revived,
            "随机值0.99，实际复活=" .. tostring(revived) .. " HP=" .. tostring(dying.hp))
    end)

    probe("感电暴击易伤", function()
        SEM.reset()
        local a, e = hero(6), hero(1)
        SEM.apply(e, SEM.SHOCKED, 3, a, { critVuln = 10 })
        local oldRoll = CF.rollCrit
        ---@type number
        local captured = 0
        CF.rollCrit = function(rate)
            captured = rate
            return false, 1
        end
        local expected = a.attrs:get(AD.CRIT_RATE) + a.attrs:get(AD.MAG_CRIT_RATE) + 10
        local ok, err = pcall(CF.calcAttack, a.attrs, e.attrs, AD.ATK_LIGHTNING)
        CF.rollCrit = oldRoll
        assert(ok, err)
        observe("感电10暴击率进入公式", math.abs(captured - expected) < 0.0001,
            "实际暴击率=" .. captured .. " 含易伤应为=" .. expected)
    end)

    probe("飞剑护盾", function()
        local a, e = hero(16), hero(1)
        BC.setContext({ getAllies = function() return { a } end,
            getEnemies = function() return { e } end })
        e.attrs.energyShield = 10000
        local ok, err = pcall(BC.dealTalentDamage, a, e, 1, false, "灵月飞剑")
        observe("飞剑全额吸盾不得报错", ok,
            "剩盾=" .. tostring(e.attrs.energyShield) .. " 结果=" .. tostring(err))
    end)

    probe("三行死亡钩子", function()
        TAL.reset()
        local drv = Driver.new(926, { battleLab = true, timeLimit = 20,
            allyFactory = function()
                local u = hero(1)
                u.attrs._setFour, u.attrs._setSix = "faceless", "faceless"
                return { u }
            end })
        drv:start(101)
        local calls = 0
        local oldHook = TAL.onEnemyDeath
        TAL.onEnemyDeath = function() calls = calls + 1 end
        local enemy = drv.enemies[1]
        enemy.hp = 0
        enemy._killedBy = drv.allies[1]
        local ok, err = pcall(drv.reportDefeatedEnemies, drv)
        TAL.onEnemyDeath = oldHook
        assert(ok, err)
        observe("三行实际死亡分发", calls == 1,
            "已阵亡1名敌人，onEnemyDeath调用=" .. tostring(calls))
    end)

    probe("裂隙四件", function()
        local a = unit({ [AD.MAX_HP] = 100 }, "riftcrystal")
        local e = unit({ [AD.MAX_HP] = 100 })
        local oldRandom = math.random
        math.random = function() return 0 end
        local ok, err = pcall(function()
            for _ = 1, 5 do ESR.onAfterAttack(a, e, { totalDamage = 10 }, true, nil, { e }) end
        end)
        math.random = oldRandom
        assert(ok, err)
        local damage = ESR.onIncoming(e, 100)
        observe("晶蚀四件独立战斗收益缺口", damage > 100,
            "晶蚀=" .. tostring(e._crystal) .. " 受击仍=" .. tostring(damage)
                .. "；当前文案只承诺积层，本观察是设计缺口而非易伤承诺违约")
        ESR.onBattleStart(e, { e })
        observe("晶蚀实际字段开战清理", (e._crystal or 0) == 0,
            "_crystal=" .. tostring(e._crystal) .. " _setCrystal=" .. tostring(e._setCrystal))
    end)

    probe("余烬计时和治疗过滤", function()
        local a = unit({ [AD.MAX_HP] = 100 }, "emberscout")
        local e = unit({ [AD.MAX_HP] = 100 })
        ESR.onAfterAttack(a, e, { category = "physical", totalDamage = 10 }, true, nil, { e })
        ESR.update(10, { a }, { e }, {})
        observe("敌方余烬2秒应到期", e._setEmber == nil,
            "10秒后余烬=" .. tostring(e._setEmber) .. " 追加受击=" .. ESR.onIncoming(e, 100))
        local ally = unit({ [AD.MAX_HP] = 100 })
        ESR.onAfterAttack(a, ally, { category = "healing", totalDamage = -100 }, true, nil, { e })
        observe("治疗不应给队友余烬", ally._setEmber == nil,
            "治疗后队友余烬=" .. tostring(ally._setEmber))
    end)

    probe("套装死亡和残留", function()
        local u = hero(1)
        u.attrs._setFour = "swordgate"
        u._setSwordDmgWin, u._setNitroT, u._crystal = 1000, 1.25, 4
        Reset.createSnapshot(u)
        Reset.resetAllyUnit(u, { u }, BC.syncUnitHp)
        ESR.onBattleStart(u, { u })
        observe("开战清理全部套装临时池", u._setSwordDmgWin == 0 and u._crystal == 0,
            "飞剑池=" .. tostring(u._setSwordDmgWin) .. " 晶蚀=" .. tostring(u._crystal))
        u.hp, u._setSwordWin = 0, 6
        local calls = 0
        ESR.update(0, { u }, { { hp = 100, maxHp = 100 } }, {
            dealDamage = function() calls = calls + 1 end })
        observe("阵亡门剑无继续攻击授权", calls == 0, "阵亡后回调次数=" .. calls)
    end)

    probe("司仪袍溢出盾", function()
        local a = unit({ [AD.MAX_HP] = 10000, [AD.ENERGY_SHIELD] = 100 }, "last_rite", "last_rite")
        local e = unit({ [AD.MAX_HP] = 10000, [AD.ENERGY_SHIELD] = 100 })
        ESR.onBattleStart(a, { a, e })
        local cap = e.attrs:get(AD.ENERGY_SHIELD)
        ESR.onOverheal(a, e, 1000)
        local before = e.attrs.energyShield
        e.attrs:addModifier("audit_unrelated", { { key = AD.HIT_VALUE, flat = 1 } })
        observe("套装转盾不能被无关重算吞掉", e.attrs.energyShield >= before,
            "上限=" .. cap .. " 转盾后=" .. before .. " 无关重算后=" .. e.attrs.energyShield)
    end)

    probe("连打成长小数门槛", function()
        local helper = require("systems.talents.TalentSera").bind({
            hasAwaken = function() return true end,
            talentLog = function() end,
            AD = AD,
        })
        local a = hero(22, awakening(true, true))
        local oldCut = ETS.getGatlingCut
        local baseState, grownState = {}, {}
        local ok, err = pcall(function()
            ETS.getGatlingCut = function() return 0 end
            for _ = 1, 60 do helper.tickSeraMachineGunCount(a, baseState) end
            ETS.getGatlingCut = function() return 0.05 end
            for _ = 1, 60 do helper.tickSeraMachineGunCount(a, grownState) end
        end)
        ETS.getGatlingCut = oldCut
        assert(ok, err)
        assert((baseState.machineGunShotsLeft or 0) > 0, "零成长对照必须正常启动连射")
        observe("正向成长不能关闭正常连射", (grownState.machineGunShotsLeft or 0) > 0,
            "60次计数，cut0弹数=" .. tostring(baseState.machineGunShotsLeft)
                .. " cut0.05弹数=" .. tostring(grownState.machineGunShotsLeft or 0))
    end)

    print(string.format("[Audit][SUMMARY] confirmed=%d healthy=%d harnessErrors=%d", confirmed, healthy, errors))
    print("[Audit] 完成；发现是当前基线问题，不代表已经修复")
    engine:Exit()
end
