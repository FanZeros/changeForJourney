-- ============================================================================
-- shield_ab_lab.lua — 护盾成长层 A/B 实测（离线，跑完即退）
-- 同种子同关卡同阵容：A臂=SHIELD_SCALING.enabled(false)（旧公式），B臂=true（新公式）。
-- 对比胜率/场均耗时/承伤/输出。config 由命令行参数或内置默认。
-- 跑法: ./.cli/UrhoXRuntime _proc/shield_ab_lab.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================
function Start()
    local ok, err = xpcall(function()
        local AD = require("systems.AttributeDef")
        local Lab = require("tests.BattleLab")
        local ss = AD.SHIELD_SCALING

        -- 代表性用例（2026-09-28 E档 8%/5% A/B 实测结论，种子926/20局）：
        --   ① 饱和胜局带 S0105/S0205（普通含盾关，裸装能赢）：B臂胜率仍 100% 不翻盘，
        --      场均耗时仅 +0.4~2.1s（敌人盾厚一点，玩家照样赢只是多花几秒）→ 敌人加盾未破坏平衡。
        --   ② 全败带 S2405-Lv36（裸装打困难关，两臂都输）：B臂存活时间 +20~26%、总承伤更高
        --      → 护盾层确实让队伍多顶一段，护盾在劣势局真正发挥作用。
        --   非饱和临界带在「裸装英雄」约束下不存在（要么碾压要么全败），属 BattleLab 无装备采样固有局限。
        local cases = {
            { tag = "S0105-Lv4", stageId = 105,  heroLv = 4,  heroes = { { id = 1 }, { id = 3 }, { id = 2 } } },
            { tag = "S0205-Lv4", stageId = 205,  heroLv = 4,  heroes = { { id = 1 }, { id = 3 }, { id = 2 } } },
            { tag = "S2405-Lv36", stageId = 2405, heroLv = 36, heroes = { { id = 1 }, { id = 3 }, { id = 2 } } },
        }
        local RUNS = 20
        local SEED = 926

        local function buildHeroes(c)
            local list = {}
            for _, h in ipairs(c.heroes) do
                list[#list + 1] = { id = h.id, level = c.heroLv }
            end
            return list
        end

        local function runArm(c, enabled)
            ss.enabled = enabled
            local cfg = {
                stageId = c.stageId, mode = "firstClear", runs = RUNS, seed = SEED,
                timeLimit = 300, heroes = buildHeroes(c),
            }
            local report, msg = Lab.run(cfg, nil)
            if not report then
                return nil, msg
            end
            return report
        end

        print("==== 护盾成长层 A/B（A=旧公式off, B=新公式on; 20局/种子926）====")
        for _, c in ipairs(cases) do
            local ra, ea = runArm(c, false)
            local rb, eb = runArm(c, true)
            if ra and rb then
                print(string.format("%-10s A: 胜率%5.1f%% 耗时%6.1fs 承伤%10.0f 输出%10.0f | B: 胜率%5.1f%% 耗时%6.1fs 承伤%10.0f 输出%10.0f | Δ胜率%+.1f Δ耗时%+.1f",
                    c.tag,
                    ra.winRate, ra.avgSeconds, ra.avgTaken, ra.avgDamage,
                    rb.winRate, rb.avgSeconds, rb.avgTaken, rb.avgDamage,
                    rb.winRate - ra.winRate, rb.avgSeconds - ra.avgSeconds))
            else
                print(string.format("%-10s 跑失败: A=%s B=%s", c.tag, tostring(ea), tostring(eb)))
            end
        end
        ss.enabled = true
        print("==== 扫描完成（ss.enabled 已还原 true）====")
    end, debug.traceback)
    if not ok then print("[shield_ab_lab] ERROR: " .. tostring(err)) end
    engine:Exit()
end
