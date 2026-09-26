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

BattleStutterPlans.showFloat = true
BattleStutterPlans.showAnim = true
BattleStutterPlans.showProj = true
-- 死亡是否结算经验、金币和掉落。关掉只用来看死亡卡顿是不是结算造成的。
BattleStutterPlans.settleKills = true

function BattleStutterPlans.label()
    local s = BattleStutterPlans.names[BattleStutterPlans.mode] or "?"
    s = s .. (BattleStutterPlans.showFloat and " 飘字开" or " 飘字关")
    s = s .. (BattleStutterPlans.showAnim and " 动画开" or " 动画关")
    s = s .. (BattleStutterPlans.showProj and " 弹道开" or " 弹道关")
    s = s .. (BattleStutterPlans.settleKills and " 结算开" or " 结算关")
    return s
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
    elseif input:GetKeyPress(KEY_4) then
        BattleStutterPlans.showFloat = not BattleStutterPlans.showFloat
    elseif input:GetKeyPress(KEY_5) then
        BattleStutterPlans.showAnim = not BattleStutterPlans.showAnim
    elseif input:GetKeyPress(KEY_6) then
        BattleStutterPlans.showProj = not BattleStutterPlans.showProj
    elseif input:GetKeyPress(KEY_7) then
        BattleStutterPlans.settleKills = not BattleStutterPlans.settleKills
        print("[BattleStutter] settle " .. (BattleStutterPlans.settleKills and "on" or "off"))
    end
end

return BattleStutterPlans
