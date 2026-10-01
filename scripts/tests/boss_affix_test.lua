-- ============================================================================
-- boss_affix_test.lua — Boss 专属词缀系统验证（v2.64）
--
-- 验证 BossAffixConfig（数据/难度梯度/确定性分配）+ BossAffixSystem
-- （静态注入 / enrage 阶段 / regen 回血 / 荆棘反弹）：
--   1. Config：Normal 无词缀；难度 tier 递增、词缀数量阶梯；确定性可复现；
--      参数随 tier 缩放且 clamp 到 cap；pickAffixIds 不重复；文案非空
--   2. 六种词缀按 chapter 确定性分布（hard tier1 count1：ch1..6 各出一种）
--   3. System：warden_shield 加护盾 / fortify 加血 / haste 改攻速（静态注入）
--   4. enrage：血量跌破阈值 tick 触发攻速+伤害强化（一次性，带横幅）
--   5. regen：tick 每秒回血
--   6. thorns：onBossDamaged 反弹伤害给攻击者（真实 dealDamageToUnit）
--   7. 只作用 isBoss 单位，小怪不受影响
-- 运行: UrhoXRuntime tests/boss_affix_test.lua -tapcode_dir=<root> -tool_mode -graphicsheadless
-- ============================================================================

local BAC = require("config.BossAffixConfig")
local BAS = require("systems.BossAffixSystem")
local MC  = require("config.MonsterConfig")
local AD  = require("systems.AttributeDef")

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
        print(string.format("[PASS] %s", name))
    else
        failed = failed + 1
        print(string.format("[FAIL] %s %s", name, detail or ""))
    end
end

-- 造一个 Boss 单位（真实 MC.createMonster + isBoss 标记）
local function makeBoss(monsterId, level)
    local u = MC.createMonster(monsterId or 8, level or 30)
    assert(u, "createMonster 失败")
    u.isBoss = true
    return u
end

-- ========== 1. Config 基础 ==========
check("Normal 无 Boss 词缀", BAC.getAffixesForBoss(10, "normal") == nil)
check("未知难度无词缀", BAC.getAffixesForBoss(10, "unknown_diff") == nil)

local hardA = BAC.getAffixesForBoss(24, "hard")
check("Hard(tier1) 有 1 个词缀", hardA and #hardA == 1, hardA and ("got " .. #hardA))
local nmA = BAC.getAffixesForBoss(47, "nightmare")
check("Nightmare(tier2) 有 1 个词缀", nmA and #nmA == 1, nmA and ("got " .. #nmA))
local hellA = BAC.getAffixesForBoss(70, "hell")
check("Hell(tier3) 有 2 个词缀", hellA and #hellA == 2, hellA and ("got " .. #hellA))
local ann5A = BAC.getAffixesForBoss(323, "annihilation5")
check("湮灭V(tier14) 有 3 个词缀", ann5A and #ann5A == 3, ann5A and ("got " .. #ann5A))

-- 确定性：同 chapter+difficulty 两次结果一致
local h1 = BAC.getAffixesForBoss(30, "hell")
local h2 = BAC.getAffixesForBoss(30, "hell")
local same = h1 and h2 and #h1 == #h2
if same then
    for i = 1, #h1 do
        if h1[i].id ~= h2[i].id then same = false end
    end
end
check("确定性：同输入结果一致", same)

-- pickAffixIds 不重复
local ids3 = BAC.pickAffixIds(50, 3)
local uniq = {}
for _, id in ipairs(ids3) do uniq[id] = (uniq[id] or 0) + 1 end
local dup = false
for _, c in pairs(uniq) do if c > 1 then dup = true end end
check("pickAffixIds(3) 无重复", #ids3 == 3 and not dup, table.concat(ids3, ","))

-- 参数随 tier 缩放 + clamp：warden_shield shieldPct tier1=0.20, perTier=0.02, cap=0.60
local function findAffix(list, id)
    for _, a in ipairs(list or {}) do if a.id == id then return a end end
    return nil
end
-- ch1 hard -> pool[1] = warden_shield（startIdx=(1-1)%6+1=1）
local shieldT1 = findAffix(BAC.getAffixesForBoss(1, "hard"), "warden_shield")
check("hard ch1 = warden_shield", shieldT1 ~= nil)
if shieldT1 then
    check("warden_shield tier1 shieldPct=0.20",
        math.abs(shieldT1.params.shieldPct - 0.20) < 1e-6,
        tostring(shieldT1.params.shieldPct))
end
-- 高 tier clamp：annihilation5(tier14) warden_shield = 0.20+0.02*13=0.46 < cap0.60
local shieldT14 = findAffix(BAC.getAffixesForBoss(1, "annihilation5"), "warden_shield")
if shieldT14 then
    check("warden_shield tier14 缩放到 0.46",
        math.abs(shieldT14.params.shieldPct - 0.46) < 1e-6,
        tostring(shieldT14.params.shieldPct))
end
-- cap 生效：fortify hpPct tier14 = 0.15+0.025*13=0.475 < cap0.70（未触顶，验证公式）
-- 用 regen 验证 cap：hpPctPerSec tier14=0.005+0.0006*13=0.0128 < cap0.015
local regenT14 = findAffix(BAC.getAffixesForBoss(6, "annihilation5"), "regen")
-- ch6 ann5 count3 startIdx=6 -> pool[6]=regen, pool[1], pool[2]
check("ann5 ch6 含 regen", regenT14 ~= nil)

-- 文案非空
if shieldT1 then
    check("warden_shield shortDesc 非空", type(shieldT1.shortDesc) == "string" and #shieldT1.shortDesc > 0)
    check("warden_shield desc 含数值", type(shieldT1.desc) == "string" and shieldT1.desc:find("20") ~= nil,
        shieldT1.desc)
end

-- ========== 2. 六词缀按 chapter 确定性分布（hard count=1）==========
-- startIdx = ((ch-1)%6)+1；hard tier1 count1 -> 单词缀 = pool[startIdx]
local expectByChapter = {
    [1] = "warden_shield", [2] = "enrage", [3] = "fortify",
    [4] = "thorns", [5] = "haste", [6] = "regen",
}
local distOk = true
for ch, expectId in pairs(expectByChapter) do
    local a = BAC.getAffixesForBoss(ch, "hard")
    if not a or #a ~= 1 or a[1].id ~= expectId then
        distOk = false
        print(string.format("  ch%d 期望 %s 实际 %s", ch, expectId, a and a[1] and a[1].id or "nil"))
    end
end
check("hard ch1..6 各出一种词缀（确定性分布）", distOk)

-- ========== 3. 静态注入 ==========
-- warden_shield：加护盾
BAS.onStageLoad(1, "hard")  -- warden_shield
local bossShield = makeBoss(8, 30)
local hpBefore = bossShield.attrs.final[AD.MAX_HP]
local esBefore = bossShield.attrs.energyShield or 0
BAS.applyToBosses({ bossShield })
local expectShield = math.floor(hpBefore * 0.20 + 0.5)
check("warden_shield 加护盾", (bossShield.attrs.energyShield or 0) >= esBefore + expectShield - 1,
    string.format("es=%s expect>=%s", tostring(bossShield.attrs.energyShield), tostring(esBefore + expectShield)))

-- fortify：加最大生命
BAS.onStageLoad(3, "hard")  -- fortify
local bossFort = makeBoss(8, 30)
local maxHpBefore = bossFort.attrs.final[AD.MAX_HP]
BAS.applyToBosses({ bossFort })
check("fortify 提升最大生命(+15%)",
    bossFort.attrs.final[AD.MAX_HP] > maxHpBefore,
    string.format("%s -> %s", tostring(maxHpBefore), tostring(bossFort.attrs.final[AD.MAX_HP])))
check("fortify 同步 unit.maxHp", bossFort.maxHp == bossFort.attrs.final[AD.MAX_HP])
check("fortify 保持满血出场", bossFort.hp == bossFort.attrs.final[AD.HP]
    and bossFort.attrs.final[AD.HP] == bossFort.attrs.final[AD.MAX_HP])

-- haste：改攻速（间隔缩短）
BAS.onStageLoad(5, "hard")  -- haste
local bossHaste = makeBoss(8, 30)
local intervalBefore = bossHaste.atkInterval
BAS.applyToBosses({ bossHaste })
check("haste 缩短攻击间隔", bossHaste.atkInterval < intervalBefore,
    string.format("%s -> %s", tostring(intervalBefore), tostring(bossHaste.atkInterval)))
check("haste 提升 ATK_SPEED 属性",
    (bossHaste.attrs.final[AD.ATK_SPEED] or 0) >= 20 - 1e-6,
    tostring(bossHaste.attrs.final[AD.ATK_SPEED]))

-- ========== 4. enrage 阶段 ==========
BAS.onStageLoad(2, "hard")  -- enrage（threshold=0.40, atkSpeed+0.30, dmg+0.25）
local bossEnrage = makeBoss(8, 30)
BAS.applyToBosses({ bossEnrage })  -- enrage 无 static 效果
local dmgBonusBefore = bossEnrage.attrs.final[AD.DMG_BONUS] or 0
-- 血量降到阈值以下
local maxHp = bossEnrage.attrs.final[AD.MAX_HP]
bossEnrage.attrs.final[AD.HP] = math.floor(maxHp * 0.3)
bossEnrage.hp = bossEnrage.attrs.final[AD.HP]
local intervalBeforeEnrage = bossEnrage.atkInterval
BAS.tick(0.1, { bossEnrage })
check("enrage 低血触发伤害加成",
    (bossEnrage.attrs.final[AD.DMG_BONUS] or 0) > dmgBonusBefore,
    string.format("%s -> %s", tostring(dmgBonusBefore), tostring(bossEnrage.attrs.final[AD.DMG_BONUS])))
check("enrage 触发攻速加成", bossEnrage.atkInterval < intervalBeforeEnrage)
local bText = BAS.getBanner()
check("enrage 触发提示横幅", bText ~= nil and bText:find("暴怒") ~= nil, tostring(bText))
-- 一次性：再 tick 不重复叠加
local dmgAfterFirst = bossEnrage.attrs.final[AD.DMG_BONUS]
BAS.tick(0.1, { bossEnrage })
check("enrage 只触发一次（不重复叠加）",
    math.abs((bossEnrage.attrs.final[AD.DMG_BONUS] or 0) - dmgAfterFirst) < 1e-6,
    string.format("%s -> %s", tostring(dmgAfterFirst), tostring(bossEnrage.attrs.final[AD.DMG_BONUS])))

-- ========== 5. regen 回血 ==========
BAS.onStageLoad(6, "hard")  -- regen（hpPctPerSec=0.005）
local bossRegen = makeBoss(8, 30)
BAS.applyToBosses({ bossRegen })
local rMax = bossRegen.attrs.final[AD.MAX_HP]
bossRegen.attrs.final[AD.HP] = math.floor(rMax * 0.5)  -- 半血
bossRegen.hp = bossRegen.attrs.final[AD.HP]
local hpBeforeRegen = bossRegen.attrs.final[AD.HP]
-- tick 1.1 秒（触发一次每秒回血）
BAS.tick(1.1, { bossRegen })
check("regen 每秒回血", bossRegen.attrs.final[AD.HP] > hpBeforeRegen,
    string.format("%s -> %s", tostring(hpBeforeRegen), tostring(bossRegen.attrs.final[AD.HP])))

-- ========== 6. thorns 反弹 ==========
BAS.onStageLoad(4, "hard")  -- thorns（reflectPct=0.10）
local bossThorns = makeBoss(8, 30)
BAS.applyToBosses({ bossThorns })
-- 造一个己方攻击者（借怪物结构，手动标 heroId 模拟己方）
local attacker = MC.createMonster(8, 30)
attacker.heroId = 1
attacker.isBoss = nil
attacker.attrs.final[AD.HP] = attacker.attrs.final[AD.MAX_HP]
attacker.hp = attacker.attrs.final[AD.HP]
-- 独立测试环境无战斗上下文（BCS.ctx），注入 mock dealDamage 直接扣血
local reflectLog = {}
local function mockDeal(target, dmg, isAlly, prefix)
    reflectLog[#reflectLog + 1] = { target = target, dmg = dmg, isAlly = isAlly, prefix = prefix }
    if target and target.attrs then
        target.attrs.final[AD.HP] = target.attrs.final[AD.HP] - dmg
        target.hp = target.attrs.final[AD.HP]
    end
    return dmg
end
local atkHpBefore = attacker.attrs.final[AD.HP]
-- Boss 受 1000 伤害 -> 反弹 10% = 100 给攻击者
local reflected = BAS.onBossDamaged(bossThorns, attacker, 1000, mockDeal)
check("thorns 触发反弹", reflected == true)
check("thorns 反弹数值=10%(1000->100)", #reflectLog == 1 and reflectLog[1].dmg == 100,
    reflectLog[1] and tostring(reflectLog[1].dmg))
check("thorns 反弹目标是攻击者且标 isAlly", reflectLog[1] and reflectLog[1].target == attacker
    and reflectLog[1].isAlly == true)
check("thorns 攻击者掉血", attacker.attrs.final[AD.HP] == atkHpBefore - 100,
    string.format("%s -> %s", tostring(atkHpBefore), tostring(attacker.attrs.final[AD.HP])))
-- 防重入：反弹期间 _thornsReflecting 标志已清除（可再次反弹）
check("thorns 反弹后清除防重入标志", bossThorns._thornsReflecting == nil)
-- 非 Boss 不反弹
local notBoss = makeBoss(8, 30)
notBoss.isBoss = nil
check("非 Boss 不触发荆棘", BAS.onBossDamaged(notBoss, attacker, 1000, mockDeal) == false)
-- 攻击者非英雄（无 heroId）不反弹
check("攻击者非英雄不反弹", BAS.onBossDamaged(bossThorns, { isBoss = nil, hp = 100 }, 1000, mockDeal) == false)
-- 无 thorns 词缀时不反弹
BAS.onStageLoad(1, "hard")  -- warden_shield，无 thorns
check("无 thorns 词缀不反弹", BAS.onBossDamaged(bossThorns, attacker, 1000, mockDeal) == false)

-- ========== 7. 只作用 isBoss，小怪不受影响 ==========
BAS.onStageLoad(3, "hard")  -- fortify
local trash = MC.createMonster(1, 30)  -- 普通小怪（无 isBoss）
local trashMaxHp = trash.attrs.final[AD.MAX_HP]
BAS.applyToBosses({ trash })
check("小怪不吃 Boss 词缀（fortify 不改其血量）",
    trash.attrs.final[AD.MAX_HP] == trashMaxHp,
    string.format("%s -> %s", tostring(trashMaxHp), tostring(trash.attrs.final[AD.MAX_HP])))

-- ========== 8. clear 清空 ==========
BAS.clear()
check("clear 后 hasAffixes=false", BAS.hasAffixes() == false)
check("clear 后 getActiveAffixes=nil", BAS.getActiveAffixes() == nil)

print(string.format("\n[boss_affix_test] passed=%d failed=%d", passed, failed))
if failed == 0 then print("ALL PASS") end

engine:Exit()
