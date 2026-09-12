-- ============================================================================
-- BattleLayout - 战斗布阵（单一事实源）
-- [左4vs右4] 我方左列竖排 4 张 vs 敌方右列竖排 4 张，中央为弹道/特效带
-- 收编原 BattleDraw.drawCardGroup 与 BattleCombat.getCardCX 两份重复公式
--
-- 坐标契约（相对 1080x2400 设计稿）:
--   X 按阵营:  己方 = ALLY_COL_X（左列），敌方 = ENEMY_COL_X（右列）
--   Y 按索引:  cardPos(group, idx) 从上往下排
-- 动画偏移约定:
--   战斗系统输出的 animOffsetY 沿"朝向敌方"轴（行阵时代为 Y 轴），
--   列阵渲染时转置到 X 轴：screenDX = -offset（两阵营统一成立，见 drawCardGroup）
-- ============================================================================

local BattleLayout = {}

-- ---- 卡片尺寸（与 BattleDraw/BattleScene 副本保持一致）----
BattleLayout.CARD_W = 198
BattleLayout.CARD_H = 438

-- ---- 列阵参数（可调）----
BattleLayout.MAX_PER_SIDE = 4                  -- 每侧最多上场数量
BattleLayout.ALLY_COL_X   = 300                -- 己方列中心 X（左）
BattleLayout.ENEMY_COL_X  = 780                -- 敌方列中心 X（右）
BattleLayout.FIELD_TOP    = 300                -- 首张卡上边缘 Y
BattleLayout.PITCH_Y      = BattleLayout.CARD_H + 26   -- 竖排卡间距（中心距）

-- 战场中心（阴影/兜底锚点用）
BattleLayout.FIELD_CY = BattleLayout.FIELD_TOP
    + (BattleLayout.MAX_PER_SIDE * BattleLayout.CARD_H
       + (BattleLayout.MAX_PER_SIDE - 1) * (BattleLayout.PITCH_Y - BattleLayout.CARD_H)) * 0.5

--- 阵营列中心 X
---@param group string "ally" | "enemy"
---@return number
function BattleLayout.columnX(group)
    return (group == "ally") and BattleLayout.ALLY_COL_X or BattleLayout.ENEMY_COL_X
end

--- 阵营内第 idx 张卡的竖排中心 Y（从上往下）
---@param group string "ally" | "enemy"
---@param idx number 1..MAX_PER_SIDE
---@return number
function BattleLayout.columnY(group, idx)
    idx = math.max(1, math.min(BattleLayout.MAX_PER_SIDE, math.floor(tonumber(idx) or 1)))
    return BattleLayout.FIELD_TOP + BattleLayout.CARD_H * 0.5 + (idx - 1) * BattleLayout.PITCH_Y
end

--- 卡片中心坐标
---@param group string "ally" | "enemy"
---@param idx number
---@return number cx
---@return number cy
function BattleLayout.cardPos(group, idx)
    return BattleLayout.columnX(group), BattleLayout.columnY(group, idx)
end

--- 通过单位列表推断阵营（己方卡带 heroId，敌方卡带 monsterId；
--- 过滤副本（存活列表/治疗候选等）与原列表非同一引用也能正确判定）
---@param units table[]|nil
---@return string|nil "ally" | "enemy" | nil
function BattleLayout.detectGroup(units)
    local first = units and units[1]
    if not first then return nil end
    if first.heroId ~= nil then return "ally" end
    if first.monsterId ~= nil then return "enemy" end
    return nil
end

--- 按单位列表取卡片坐标（列表推断阵营；空列表走战场中心兜底）
---@param units table[]|nil
---@param idx number|nil
---@param fallbackCY number|nil 空列表时 Y 兜底
---@return number cx
---@return number cy
function BattleLayout.posForList(units, idx, fallbackCY)
    local group = BattleLayout.detectGroup(units)
    if not group then
        return 540, fallbackCY or BattleLayout.FIELD_CY
    end
    return BattleLayout.cardPos(group, idx or 1)
end

return BattleLayout
