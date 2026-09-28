-- ============================================================================
-- shield_sweep.lua — 护盾成长层系数扫描（离线，跑完即退）
-- 扫描多组 hpRatio × derivedLevelFactor，输出敌人与玩家在各等级的护盾/HP占比，
-- 供调平衡选档。跑法: ./.cli/UrhoXRuntime _proc/shield_sweep.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================
function Start()
    local ok, err = pcall(function()
        local AD = require("systems.AttributeDef")
        local HC = require("config.HeroConfig")
        local MC = require("config.MonsterConfig")
        local ss = AD.SHIELD_SCALING

        local function pct(a)
            local hp = a:get(AD.MAX_HP)
            local es = a:get(AD.ENERGY_SHIELD)
            return hp > 0 and (es / hp * 100) or 0
        end
        local function esVal(a) return a:get(AD.ENERGY_SHIELD) end
        local function fmt(n)
            if n >= 1e12 then return string.format("%.2e", n) end
            if n >= 1000 then return string.format("%.0f", n) end
            return string.format("%.1f", n)
        end

        -- 扫描网格
        local hpRatios = { 0.03, 0.05, 0.08, 0.12, 0.20 }
        local lvFactors = { 0.00, 0.02, 0.05 }

        print("==== 敌人占比（雷神id8 普通级；护盾源 MAG_ARMOR=2.0）====")
        print("  hpRatio \\ 等级        Lv1      Lv50     Lv100    Lv200    Lv345")
        for _, hr in ipairs(hpRatios) do
            ss.hpRatio, ss.derivedLevelFactor = hr, 0.02
            local row = string.format("  %5.0f%%              ", hr * 100)
            for _, lv in ipairs({ 1, 50, 100, 200, 345 }) do
                local u = MC.createMonster(8, lv)
                row = row .. string.format("%7.2f%% ", pct(u.attrs))
            end
            print(row)
        end

        print("")
        print("==== 玩家占比（裸装；战士id1 / 法师id2 / 牧师id9 @ Lv200）====")
        print("  hpRatio  lvFactor   战士Lv200  法师Lv200  牧师Lv200   战士Lv1  法师Lv1")
        for _, hr in ipairs(hpRatios) do
            for _, lf in ipairs(lvFactors) do
                ss.hpRatio, ss.derivedLevelFactor = hr, lf
                local w200 = pct(HC.createHero(1, 200, nil, nil, false).attrs)
                local m200 = pct(HC.createHero(2, 200, nil, nil, false).attrs)
                local p200 = pct(HC.createHero(9, 200, nil, nil, false).attrs)
                local w1   = pct(HC.createHero(1, 1, nil, nil, false).attrs)
                local m1   = pct(HC.createHero(2, 1, nil, nil, false).attrs)
                print(string.format("  %5.0f%%    %4.0f%%     %6.1f%%   %6.1f%%   %6.1f%%    %5.1f%%  %5.1f%%",
                    hr * 100, lf * 100, w200, m200, p200, w1, m1))
            end
        end

        print("")
        print("==== 敌人护盾绝对值（雷神 Lv345，普通级 vs 传说级 statMult=22.5）====")
        for _, hr in ipairs(hpRatios) do
            ss.hpRatio, ss.derivedLevelFactor = hr, 0.02
            local n = esVal(MC.createMonster(8, 345).attrs)
            local lg = esVal(MC.createMonster(8, 345, { statMult = 22.5 }).attrs)
            print(string.format("  hpRatio=%3.0f%%   普通=%-10s  传说=%-10s", hr * 100, fmt(n), fmt(lg)))
        end

        -- 还原默认
        ss.hpRatio, ss.derivedLevelFactor = 0.05, 0.02
    end)
    if not ok then print("[shield_sweep] ERROR: " .. tostring(err)) end
    engine:Exit()
end
