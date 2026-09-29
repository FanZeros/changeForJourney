-- ============================================================================
-- projectile_arc_test.lua — 投掷物抛物线/蓝色小鸟 冒烟回归（无渲染层）
-- 覆盖 2026-09-28 改动：
--   1) 英雄8（愤怒的小雀）配置改为 fly + EF_ATK_8_BLUE + lob 弧 + 蓝色拖尾 + sfxKey 回退
--   2) fly/shake/pierce 均有 arcLift（抛物线），melee 保持直线（斩击不是投掷物）
--   3) spawn/update 全流程无异常（含 sfxKey 音效键回退路径）
-- 跑法: ./.cli/UrhoXRuntime scripts/tests/projectile_arc_test.lua \
--        -tapcode_dir=/workspace -tool_mode -graphicssurfaceless
-- ============================================================================

local failures = {}

local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        print("[FAIL] " .. msg)
        failures[#failures + 1] = msg
    end
end

local PS = require("ui.battle.combat.ProjectileSystem")

-- ── 1) 英雄8 配置：蓝色小鸟 + 抛投弧 ──
local function spawnAndInspect(heroId, dist)
    PS.reset()
    PS.spawn(heroId, 0, 0, dist, 0, function() end, nil)
    check(PS.getActiveCount() == 1, "hero" .. heroId .. " 生成了 1 个投射物")
    local proj = PS.mountedState().projectiles[1]
    return proj
end

local p8 = spawnAndInspect(8, 400)
check(p8 and p8.cfg.type == "fly", "英雄8 类型为 fly（投掷而非斩击）")
check(p8 and p8.cfg.imgKey == "EF_ATK_8_BLUE", "英雄8 使用蓝色小鸟贴图 EF_ATK_8_BLUE")
check(p8 and p8.cfg.sfxKey == "EF_ATK_8", "英雄8 音效回退键为 EF_ATK_8")
check(p8 and (p8.cfg.trail and p8.cfg.trail[3] == 255 and p8.cfg.trail[1] < 120),
    "英雄8 拖尾为蓝色系")
check(p8 and (p8.arcLift or 0) > 30, "英雄8 抛投弧高 > 30（lob），实得 " .. tostring(p8 and p8.arcLift))

-- ── 2) 其他投掷物类型都有弧；melee 保持直线 ──
local p2 = spawnAndInspect(2, 400)   -- 火球 fly shallow
check(p2 and (p2.arcLift or 0) > 0, "英雄2（fly）有抛物线弧高，实得 " .. tostring(p2 and p2.arcLift))

local p1 = spawnAndInspect(1, 400)   -- 大狗嚼 melee 斩击
check(p1 and (p1.arcLift or 0) == 0, "英雄1（melee 斩击）保持直线，arcLift=0")

PS.reset()
PS.spawnByKey("EF_MS_7", 0, 0, 400, 0, function() end, false, nil)  -- shake
local ps = PS.mountedState().projectiles[1]
check(ps and (ps.arcLift or 0) > 0, "怪物 shake 弹有抛物线弧高，实得 " .. tostring(ps and ps.arcLift))

PS.reset()
local okPierce = PS.spawnPierce({ heroId = 2 }, 0, 0, 500, 0,
    { { atT = 0.5, onHit = function() end } }, nil)
local pp = PS.mountedState().projectiles[1]
check(okPierce == true and pp and (pp.arcLift or 0) > 0,
    "穿透弹 spawnPierce 有抛物线弧高，实得 " .. tostring(pp and pp.arcLift))

-- ── 3) update 全流程（含命中回调与移除）不抛异常 ──
PS.reset()
local hitCount = 0
PS.spawn(8, 0, 0, 400, 0, function() hitCount = hitCount + 1 end, nil)
for _ = 1, 90 do PS.update(1 / 60) end
check(hitCount == 1, "英雄8 投射物命中回调恰好触发 1 次，实得 " .. tostring(hitCount))
check(PS.getActiveCount() == 0, "投射物生命周期结束后被移除")

if #failures > 0 then
    print(string.format("[projectile_arc_test] FAILURES=%d", #failures))
    for _, f in ipairs(failures) do print("  - " .. f) end
else
    print("[projectile_arc_test] ALL PASS")
end
