-- B批套装生命周期回归：真实三行tick和旧单场reload，保持套装数值与星门授权。
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local TAL = require("systems.TalentManager")
local SEM = require("systems.StatusEffectManager")
local BC = require("ui.battle.combat.BattleCombat")
local PS = require("ui.battle.combat.ProjectileSystem")
local Driver = require("ui.battle.tri.BattleTriDriver")
local Scene = require("ui.battle.scene.BattleScene")
local Reset = require("ui.battle.scene.BattleAllyReset")

local assertions, failures = 0, 0
local function check(condition, message)
    assertions = assertions + 1
    print("[套装生命周期][" .. (condition and "PASS" or "FAIL") .. "] " .. message)
    if not condition then failures = failures + 1 end
end

local function runCase(name, fn)
    local ok, err = pcall(fn)
    if not ok then check(false, name .. "执行异常：" .. tostring(err)) end
end

local function awake()
    return { [1] = true, [2] = true, [3] = true, _awk3Migrated = true }
end

local function hero(id, nodes)
    return assert(HC.createHero(id, 1, nil, nodes, false))
end

local function setHp(unit, value)
    unit.attrs.final[AD.HP] = value
    BC.syncUnitHp(unit)
end

local function fixture(setId, heroId)
    local wearer, friend = hero(heroId or 24), hero(1)
    wearer.attrs._setFour, wearer.attrs._setSix = setId, setId
    local drv = Driver.new(932, { battleLab = true, timeLimit = 60,
        allyFactory = function() return { wearer, friend } end })
    drv:start(101)
    drv.introTimer = 0
    for _, unit in ipairs(drv.allies) do
        unit.attrs:setBase(AD.MAX_HP, 1000000)
        unit.attrs:fillHp()
        BC.syncUnitHp(unit)
    end
    for _, unit in ipairs(drv.enemies) do
        unit.attrs:setBase(AD.MAX_HP, 1000000)
        unit.attrs:fillHp()
        unit.attrs.energyShield, unit.attrs.tempEnergyShield = 0, 0
        BC.syncUnitHp(unit)
    end
    return drv, wearer, friend, drv.enemies[1]
end

local function freeze(drv)
    for _, list in ipairs({ drv.allies, drv.enemies }) do
        for _, unit in ipairs(list) do SEM.apply(unit, SEM.FROZEN, 100, nil, {}) end
    end
end

local function tick(drv, dt)
    drv.mount()
    drv.bindContext()
    drv:tick(dt)
end

local function attack(drv, attacker, target)
    drv.mount()
    drv.bindContext()
    attacker.atkTargets = 1
    attacker.attrs:setBase(AD.HIT_VALUE, 100000)
    BC.performAttack(attacker, { target }, true)
    for _ = 1, 90 do PS.update(1 / 60) end
end

local function testEmber()
    local drv, wearer, _, target = fixture("emberscout", 3)
    attack(drv, wearer, target)
    check(target._setEmber == 2 and target._setEmberSrc == wearer, "正式攻击写入余烬及真实来源")
    freeze(drv)
    tick(drv, 1.99)
    check(target._setEmber and math.abs(target._setEmber - 0.01) < 1e-7,
        "敌方余烬由真实宿主计时到2秒前")
    local before = target.hp
    BC.dealDamageToUnit(target, 100, false, "边界 ", { 255, 255, 255 }, wearer)
    check(before - target.hp == 108, "到期前现有8%余烬受击增幅保留")
    tick(drv, 0.02)
    check(target._setEmber == nil and target._setEmberSrc == nil, "到期同时移除敌方余烬与来源")
    before = target.hp
    BC.dealDamageToUnit(target, 100, false, "边界 ", { 255, 255, 255 }, wearer)
    check(before - target.hp == 100, "到期后正式额伤不再吃过期余烬")
    local nextEnemy = drv.enemies[2]
    setHp(target, 0)
    target._killedBy = wearer
    drv:reportDefeatedEnemies()
    check(nextEnemy._setEmber == nil and nextEnemy._setEmberSrc == nil, "过期余烬死亡不再传播")

    local otherDrv, _, friend = fixture("emberscout", 3)
    friend._setEmber, friend._setEmberSrc = 0.1, otherDrv.enemies[1]
    freeze(otherDrv)
    tick(otherDrv, 0.11)
    check(friend._setEmber == nil and friend._setEmberSrc == nil, "友方余烬也到期清来源")

    local spreadDrv, spreadWearer, _, spreadEnemy = fixture("emberscout", 3)
    attack(spreadDrv, spreadWearer, spreadEnemy)
    local recipient = spreadDrv.enemies[2]
    setHp(spreadEnemy, 0)
    spreadEnemy._killedBy = spreadWearer
    spreadDrv:reportDefeatedEnemies()
    check(recipient._setEmber == 2 and recipient._setEmberSrc == spreadWearer,
        "未到期六件余烬仍按原规则传播一次")
    check(spreadEnemy._setEmber == nil and spreadEnemy._setEmberSrc == nil,
        "完成死亡传播后死目标标记和来源均清理")
    recipient._setEmber = 0.5
    attack(spreadDrv, spreadWearer, recipient)
    check(recipient._setEmber == 2 and recipient._setEmberSrc == spreadWearer,
        "新的正式命中按原规则刷新2秒余烬")
end

local function testDeadPeriodic()
    for _, setId in ipairs({ "swordgate", "starless" }) do
        local drv, wearer, friend = fixture(setId)
        freeze(drv)
        wearer._setSwordWin, wearer._setSwordDmgWin = 6, 1000
        wearer._setStarCd = 0
        setHp(wearer, 0)
        local before = 0
        for _, enemy in ipairs(drv.enemies) do before = before + enemy.hp end
        tick(drv, 0.1)
        local after = 0
        for _, enemy in ipairs(drv.enemies) do after = after + enemy.hp end
        check(friend.hp > 0 and drv.active, "其他队友存活，宿主继续运行 set=" .. setId)
        check(after == before, "套装持有者阵亡不再周期攻击 set=" .. setId)
        check(wearer._setSwordDmgWin == 1000 and wearer._setSwordWin == 6 and wearer._setStarCd == 0,
            "死亡只暂停输出周期，不凭空消费本场存量 set=" .. setId)
        setHp(wearer, 100000)
        freeze(drv)
        tick(drv, 0.1)
        local dealt = 0
        for _, enemy in ipairs(drv.enemies) do
            dealt = dealt + (1000000 - enemy.hp)
        end
        check(dealt > 0, "存活后现有周期攻击仍有效 set=" .. setId)
    end
end

local function testDeadBuffExpiry()
    local drv, wearer, friend = fixture("nitros")
    wearer._setNitroT = 0.1
    wearer.attrs:addModifier("set6_nitros_spd", { { key = AD.ATK_SPEED, flat = 12 } })
    wearer._setFacelessT = 0.1
    wearer._setEmber, wearer._setEmberSrc = 0.1, drv.enemies[1]
    freeze(drv)
    setHp(wearer, 0)
    tick(drv, 0.11)
    check(friend.hp > 0 and wearer.attrs.modifiers.set6_nitros_spd == nil,
        "死人不输出但硝烟限时增益仍到期")
    check(wearer._setFacelessT <= 0 and wearer._setEmber == nil and wearer._setEmberSrc == nil,
        "死人限时无面与余烬仍按时间到期")
end

local function seed(unit, source)
    unit._setShell, unit._setFacelessT, unit._crystal = 8, 3, 4
    unit._setSwordWin, unit._setSwordDmgWin, unit._setStarCd = 5, 777, 0.5
    unit._setNitroT, unit._setGamble = 1.5, 3
    unit._setEmber, unit._setEmberSrc = 1.5, source
    unit.attrs:addModifier("set4_gamble", { { key = AD.CRIT_RATE, flat = 18 } })
    unit.attrs:addModifier("set6_nitros_spd", { { key = AD.ATK_SPEED, flat = 12 } })
    unit.attrs:addModifier("set4_bonehunger", { { key = AD.ATK_SPEED, flat = 8 } })
end

local function checkClean(unit, label)
    check(unit._setShell == 0 and unit._setFacelessT == 0 and unit._crystal == 0,
        label .. "虫壳／无面／实际晶蚀层清理")
    check(unit._setSwordWin == 0 and unit._setSwordDmgWin == 0 and unit._setStarCd == 8,
        label .. "门剑池／计时与无光周期重置")
    check((unit._setNitroT or 0) == 0 and unit._setGamble == 0
        and unit._setEmber == nil and unit._setEmberSrc == nil,
        label .. "硝烟／赌徒／余烬与来源清理")
    check(unit.attrs.modifiers.set4_gamble == nil and unit.attrs.modifiers.set6_nitros_spd == nil
        and unit.attrs.modifiers.set4_bonehunger == nil,
        label .. "套装临时属性修改器不残留")
end

local function testRealReload()
    local unit, friend = hero(24), hero(1)
    unit.attrs._setFour, unit.attrs._setSix = "swordgate", "swordgate"
    unit.attrs:addModifier("permanent_test", { { key = AD.MAX_HP, flat = 123 } })
    Scene.setAllies({ unit, friend })
    seed(unit, friend)
    unit._etsShadowStart = 2
    Scene.reloadStage()
    checkClean(unit, "旧单场真实reload：")
    check(unit.attrs._setFour == "swordgate" and unit.attrs._setSix == "swordgate",
        "reload保留装备高阶标记")
    check(unit.attrs.modifiers.permanent_test ~= nil and unit._etsShadowStart == 2,
        "reload不混清持久属性和非套装库存字段")

    local drv, wearer, _, enemy = fixture("swordgate")
    seed(wearer, enemy)
    seed(enemy, wearer)
    enemy.attrs._setFour, enemy.attrs._setSix = "starless", "starless"
    TAL.onBattleStart(drv.allies, drv.enemies)
    checkClean(wearer, "正式开战友方：")
    check(enemy._crystal == 0 and enemy._setEmber == nil and enemy._setEmberSrc == nil,
        "正式开战双方目标减益清理，不给敌人新增友方套装增益")
    check(enemy.attrs.modifiers.set4_starless == nil, "敌方纯清理不新增套装开战属性")

    local pending = unit.attrs:clone()
    pending._setFour, pending._setSix = "gambler", "gambler"
    unit._pendingSnapshot = pending
    seed(unit, friend)
    Scene.reloadStage()
    checkClean(unit, "待更新装备真实reload：")
    check(unit.attrs._setFour == "gambler" and unit._pendingSnapshot == nil,
        "真实reload消费待更新快照且不丢新套装标记")

    local noAttrs = { name = "无属性边界", hp = 0, maxHp = 100, _setSwordDmgWin = 9,
        _crystal = 3, _setEmber = 1, _setEmberSrc = friend }
    Reset.resetAllyUnit(noAttrs, { noAttrs }, function() end)
    check(noAttrs._setSwordDmgWin == 0 and noAttrs._crystal == 0
        and noAttrs._setEmber == nil and noAttrs._setEmberSrc == nil,
        "无属性兜底重置仍清理套装字段")
end

local function testStartBuffOrder()
    local owner, friend = hero(19), hero(1)
    owner.attrs._setFour, owner.attrs._setSix = "last_rite", "last_rite"
    TAL.onBattleStart({ owner, friend }, {})
    check(owner.attrs.modifiers.set6_last_rite ~= nil and friend.attrs.modifiers.set6_last_rite ~= nil,
        "司仪袍先初始化后，队友清理不抹掉刚施加的队伍增益")
end

local function testStarGateRetained()
    local melissa, friend = hero(20, awake()), hero(1)
    local drv = Driver.new(933, { battleLab = true, timeLimit = 60,
        allyFactory = function() return { melissa, friend } end })
    drv:start(101)
    drv.introTimer = 0
    for _, enemy in ipairs(drv.enemies) do
        enemy.attrs:setBase(AD.MAX_HP, 1000000)
        enemy.attrs:fillHp()
        enemy.attrs.energyShield, enemy.attrs.tempEnergyShield = 0, 0
        BC.syncUnitHp(enemy)
    end
    freeze(drv)
    setHp(melissa, 0)
    local before = 0
    for _, enemy in ipairs(drv.enemies) do before = before + enemy.hp end
    for _ = 1, 200 do tick(drv, 1 / 60) end
    local after = 0
    for _, enemy in ipairs(drv.enemies) do after = after + enemy.hp end
    check(melissa.hp == 0 and (melissa._starGateCount or 0) >= 2,
        "共鸣星门持有者死亡后仍保留授权门数")
    check(after < before, "真实宿主仍执行星门授权死后攻击，未被套装存活门控误伤")
end

function Start()
    print("[套装生命周期] 开始；真实tick／reload，先暴露失败不修改旧断言")
    runCase("余烬到期", testEmber)
    runCase("阵亡周期输出", testDeadPeriodic)
    runCase("死人限时增益", testDeadBuffExpiry)
    runCase("真实换波清理", testRealReload)
    runCase("队伍开战增益顺序", testStartBuffOrder)
    runCase("星门死后持续", testStarGateRetained)
    print(string.format("[equipment_set_lifecycle_test] assertions=%d failures=%d %s",
        assertions, failures, failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
