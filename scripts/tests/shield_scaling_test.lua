-- ============================================================================
-- shield_scaling_test.lua — 护盾成长层（AD.SHIELD_SCALING）回归测试
-- 验证：
--   1) 有盾敌人：护盾/HP 比例在高等级稳定 ≈ hpRatio（不再塌到 0）
--   2) 无盾敌人：仍然 0 护盾（不凭空加盾）
--   3) 英雄：护盾随等级单调上升，占比不再塌陷
--   4) enabled=false：完全恢复旧行为（护盾 = 成长层前数值）
--   5) 向后兼容：Lv1 + hpRatio=0 + derivedLevelFactor=0 时与旧公式一致
--   6) clone 保留 unitLevel 与护盾值
--   7) 战斗吸收：护盾先于 HP 扣减（takeDamage 路径不回归）
-- 跑法: ./.cli/UrhoXRuntime tests/shield_scaling_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local failures = {}
local function check(cond, msg)
    if cond then print("[PASS] " .. msg)
    else print("[FAIL] " .. msg); failures[#failures + 1] = msg end
end

local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local MC = require("config.MonsterConfig")
local UnitAttributes = require("systems.UnitAttributes")

function Start()
    print("[shield_scaling_test] start")
    local ok, err = pcall(function()
        local ss = AD.SHIELD_SCALING
        check(type(ss) == "table" and ss.enabled == true, "SHIELD_SCALING 配置存在且默认启用")
        local hpRatio = ss.hpRatio
        local lvFactor = ss.derivedLevelFactor

        -- 1) 有盾敌人（雷神 id=8, MAG_ARMOR=2.0）：高等级护盾/HP ≈ hpRatio
        local eLv1 = MC.createMonster(8, 1)
        local eHigh = MC.createMonster(8, 345)
        local ratioHigh = eHigh.attrs:get(AD.ENERGY_SHIELD) / eHigh.attrs:get(AD.MAX_HP)
        check(ratioHigh > hpRatio * 0.9 and ratioHigh < hpRatio * 1.35,
            string.format("雷神 Lv345 护盾/HP=%.2f%% 锚定在 hpRatio=%.0f%% 附近", ratioHigh * 100, hpRatio * 100))
        local esLv1 = eLv1.attrs:get(AD.ENERGY_SHIELD)
        check(esLv1 > 0, string.format("雷神 Lv1 护盾 > 0（实得 %.1f）", esLv1))
        -- 成长层后高等级护盾绝对值必须远大于旧公式的线性值（旧公式 Lv345 只有 ~821）
        check(eHigh.attrs:get(AD.ENERGY_SHIELD) > 1e9,
            "雷神 Lv345 护盾绝对值 > 1e9（旧公式仅 ~821，已跟随指数 HP）")

        -- 2) 无盾敌人（天狗 id=1，attrs={}）：任何等级都无护盾
        local eNoShield1 = MC.createMonster(1, 1)
        local eNoShieldHigh = MC.createMonster(1, 345)
        check(eNoShield1.attrs:get(AD.ENERGY_SHIELD) == 0
            and eNoShieldHigh.attrs:get(AD.ENERGY_SHIELD) == 0,
            "无盾敌人（天狗）Lv1/Lv345 护盾均为 0，未被凭空加盾")

        -- 3) 英雄护盾随等级单调上升且占比不塌陷
        local prevES = -1
        local monotonic = true
        for _, lv in ipairs({ 1, 20, 50, 100, 150, 200 }) do
            local h = HC.createHero(2, lv, nil, nil, false)
            local es = h.attrs:get(AD.ENERGY_SHIELD)
            if es <= prevES then monotonic = false end
            prevES = es
        end
        check(monotonic, "法师英雄 Lv1→200 护盾严格单调上升")
        local h200 = HC.createHero(2, 200, nil, nil, false)
        local ratio200 = h200.attrs:get(AD.ENERGY_SHIELD) / h200.attrs:get(AD.MAX_HP)
        check(ratio200 >= hpRatio,
            string.format("法师 Lv200 护盾/HP=%.1f%% ≥ hpRatio=%.0f%%（旧公式仅 2.8%%）", ratio200 * 100, hpRatio * 100))

        -- 4) enabled=false：完全恢复旧行为
        ss.enabled = false
        local eOff = MC.createMonster(8, 345)
        local esOff = eOff.attrs:get(AD.ENERGY_SHIELD)
        check(esOff < 1e6, string.format("enabled=false 时雷神 Lv345 护盾恢复旧线性值（%.1f < 1e6）", esOff))
        ss.enabled = true

        -- 5) 向后兼容：Lv1 + 两旋钮归零 → 与旧公式一致（成长层 extra=0）
        local savedRatio, savedFactor = ss.hpRatio, ss.derivedLevelFactor
        ss.hpRatio, ss.derivedLevelFactor = 0, 0
        local eCompat = MC.createMonster(8, 1)
        local esCompat = eCompat.attrs:get(AD.ENERGY_SHIELD)
        ss.enabled = false
        local eOld = MC.createMonster(8, 1)
        local esOld = eOld.attrs:get(AD.ENERGY_SHIELD)
        ss.enabled = true
        ss.hpRatio, ss.derivedLevelFactor = savedRatio, savedFactor
        check(math.abs(esCompat - esOld) < 0.01,
            string.format("旋钮归零时与旧公式一致（%.4f ≈ %.4f）", esCompat, esOld))

        -- 6) clone 保留 unitLevel 与护盾
        local eCloneSrc = MC.createMonster(8, 100)
        local cloned = eCloneSrc.attrs:clone()
        check(cloned.unitLevel == 100, "clone 保留 unitLevel=100")
        check(math.abs(cloned:get(AD.ENERGY_SHIELD) - eCloneSrc.attrs:get(AD.ENERGY_SHIELD)) < 0.01,
            "clone 保留护盾值")
        -- clone 后 recalc 应复现同一护盾（等级因子不丢）
        cloned:recalc()
        check(math.abs(cloned:get(AD.ENERGY_SHIELD) - eCloneSrc.attrs:get(AD.ENERGY_SHIELD)) < 0.01,
            "clone 后 recalc 护盾可复现（unitLevel 未丢失）")

        -- 7) 战斗吸收路径：护盾先于 HP 扣减
        local eTank = MC.createMonster(8, 50)
        eTank.attrs:fillHp()
        local hpBefore = eTank.attrs:get(AD.HP)
        local esBefore = eTank.attrs:get(AD.ENERGY_SHIELD)
        local dmg = math.floor(esBefore * 0.5)
        eTank.attrs:takeDamage(dmg, 0)
        check(eTank.attrs:get(AD.HP) == hpBefore,
            "小于护盾值的伤害不打 HP（护盾优先吸收）")
        check(eTank.attrs.energyShield < esBefore, "护盾被扣减")

        -- 8) 直接构造（不走 HC/MC）默认 unitLevel=1，不崩
        local raw = UnitAttributes.create({
            [AD.MAX_HP] = 1000, [AD.INT] = 10,
        })
        check(raw.unitLevel == 1 and raw:get(AD.ENERGY_SHIELD) >= 30,
            "UnitAttributes.create 缺省 unitLevel=1，INT 派生护盾正常（含 HP 锚定）")

        print(string.format("[summary] hpRatio=%.2f derivedLevelFactor=%.2f | 雷神Lv345护盾/HP=%.2f%% | 法师Lv200护盾/HP=%.1f%%",
            hpRatio, lvFactor, ratioHigh * 100, ratio200 * 100))
    end)
    if not ok then
        print("[FAIL] 测试抛异常: " .. tostring(err))
        failures[#failures + 1] = "exception"
    end
    if #failures == 0 then
        print("[shield_scaling_test] ALL PASS")
    else
        print("[shield_scaling_test] FAILURES=" .. #failures)
        for _, m in ipairs(failures) do print("  - " .. m) end
    end
    engine:Exit()
end
