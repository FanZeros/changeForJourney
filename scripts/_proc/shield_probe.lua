-- ============================================================================
-- shield_probe.lua — 护盾上限数值探针（离线，跑完即退）
-- 打印玩家英雄与敌人在多个等级下的：HP / 护盾 / 护盾占HP比例 / 护盾派生分解
-- 用于护盾缩放改动的 before/after 对照。
-- 跑法: ./.cli/UrhoXRuntime _proc/shield_probe.lua -tapcode_dir=. -tool_mode
-- ============================================================================
function Start()
    local ok, err = pcall(function()
        local AD = require("systems.AttributeDef")
        local HC = require("config.HeroConfig")
        local MC = require("config.MonsterConfig")

        local function fmt(n)
            if n == nil then return "nil" end
            if n >= 1e12 then return string.format("%.3e", n) end
            if n >= 1000 then return string.format("%.0f", n) end
            return string.format("%.1f", n)
        end

        print("======== 玩家英雄（裸装，无装备/天赋/觉醒）========")
        -- 英雄1=战士(力量/体质系), 英雄2=法师(秘识系), 英雄15≈牧师(魂火系)
        local heroIds = { 1, 2, 9 }
        local levels  = { 1, 20, 50, 100, 150, 200 }
        for _, hid in ipairs(heroIds) do
            for _, lv in ipairs(levels) do
                local u = HC.createHero(hid, lv, nil, nil, false)
                if u and u.attrs then
                    local a = u.attrs
                    local hp = a:get(AD.MAX_HP)
                    local es = a:get(AD.ENERGY_SHIELD)
                    local esBonus = a:get(AD.ES_BONUS)
                    local ratio = hp > 0 and (es / hp * 100) or 0
                    print(string.format("  英雄%-2d Lv%-3d  HP=%-12s 护盾=%-10s 护盾/HP=%5.1f%%  esBonus=%.0f%%",
                        hid, lv, fmt(hp), fmt(es), ratio, esBonus))
                end
            end
            print("  ----")
        end

        print("======== 敌人（普通级模板）========")
        -- 选几个代表性敌人: 1=天狗(无盾), 8=雷神(护盾2.0), 17=毕方(护盾2.44), 21=泰逢(护盾1.54)
        local monIds = { 1, 8, 17, 21 }
        local mlevels = { 1, 20, 50, 100, 200, 345 }
        for _, mid in ipairs(monIds) do
            for _, lv in ipairs(mlevels) do
                local u = MC.createMonster(mid, lv)
                if u and u.attrs then
                    local a = u.attrs
                    local hp = a:get(AD.MAX_HP)
                    local es = a:get(AD.ENERGY_SHIELD)
                    local ratio = hp > 0 and (es / hp * 100) or 0
                    print(string.format("  敌人%-3d Lv%-3d  HP=%-12s 护盾=%-10s 护盾/HP=%5.2f%%",
                        mid, lv, fmt(hp), fmt(es), ratio))
                end
            end
            print("  ----")
        end

        print("======== 敌人（高品质：传说级 statMult 放大）========")
        for _, lv in ipairs({ 50, 150, 345 }) do
            local u = MC.createMonster(8, lv, { statMult = 22.5 })
            if u and u.attrs then
                local a = u.attrs
                local hp = a:get(AD.MAX_HP)
                local es = a:get(AD.ENERGY_SHIELD)
                local ratio = hp > 0 and (es / hp * 100) or 0
                print(string.format("  雷神(传说) Lv%-3d  HP=%-12s 护盾=%-10s 护盾/HP=%5.3f%%",
                    lv, fmt(hp), fmt(es), ratio))
            end
        end
    end)
    if not ok then print("[shield_probe] ERROR: " .. tostring(err)) end
    engine:Exit()
end
