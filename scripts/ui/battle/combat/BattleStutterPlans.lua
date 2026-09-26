-- ============================================================================
-- BattleStutterPlans - 战斗卡顿对比方案
-- 1 平稳：一帧最多 1 次攻击，积压留到后面几帧
-- 2 当前：一帧最多补 8 次，卡顿帧会集中结算
-- 3 分帧：一帧最多 2 次，天赋和状态每两帧算一次
-- 按键 1 / 2 / 3 切换，左上角显示当前方案
-- ============================================================================

local BattleStutterPlans = {
    mode = 2,
    names = {
        [1] = "1 平稳",
        [2] = "2 当前",
        [3] = "3 分帧",
    },
}

function BattleStutterPlans.maxHits()
    if BattleStutterPlans.mode == 1 then return 1 end
    if BattleStutterPlans.mode == 3 then return 2 end
    return 8
end

function BattleStutterPlans.heavyThisFrame(frame)
    if BattleStutterPlans.mode ~= 3 then return true end
    return (frame % 2) == 0
end

function BattleStutterPlans.poll()
    if input:GetKeyPress(KEY_1) then
        BattleStutterPlans.mode = 1
        print("[BattleStutter] plan 1")
    elseif input:GetKeyPress(KEY_2) then
        BattleStutterPlans.mode = 2
        print("[BattleStutter] plan 2")
    elseif input:GetKeyPress(KEY_3) then
        BattleStutterPlans.mode = 3
        print("[BattleStutter] plan 3")
    end
end

return BattleStutterPlans
