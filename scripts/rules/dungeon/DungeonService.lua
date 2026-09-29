-- ============================================================================
-- DungeonService - 副本业务逻辑
-- 职责: 副本扫荡/挑战/胜利结算，通过 PDM 读写数据
-- 层级: server/dungeon  |  禁止网络 IO
-- ============================================================================

local PDM           = require("rules.character.PlayerDataManager")
local DungeonConfig = require("config.DungeonConfig")

local DungeonService = {}

-- ======================== 工具函数 ========================

--- 获取今天的日期标识（用于每日重置，UTC+8）
---@return number 日序号 ((os.time() + 28800) / 86400 取整)
local function getTodaySeq()
    return math.floor((os.time() + 28800) / 86400)
end

--- 检查并重置每日次数（如果跨天了）
---@param subData table 副本子结构（gold_mine 或 ancient_ruin）
local function checkDailyReset(subData)
    local today = getTodaySeq()
    if (subData.dailyDay or 0) ~= today then
        subData.dailyUsed = 0
        subData.dailyDay  = today
    end
end

-- ======================== 获取副本子数据 ========================

--- 获取指定副本的子结构（兼容初始化）
---@param dungeon table dungeon 模块
---@param dungeonId string
---@return table|nil subData
local function getDungeonSubData(dungeon, dungeonId)
    if not dungeon[dungeonId] then
        dungeon[dungeonId] = {
            floor     = 1,
            dailyUsed = 0,
            dailyDay  = 0,
            cleared   = {},
        }
    end
    return dungeon[dungeonId]
end

-- ======================== 扫荡 ========================

--- 执行副本扫荡（扫荡上一层）
---@param uid number
---@param dungeonId string "gold_mine" | "ancient_ruin"
---@return boolean ok
---@return string|nil err
---@return table|nil result
function DungeonService.Sweep(uid, dungeonId)
    if dungeonId ~= "gold_mine" and dungeonId ~= "ancient_ruin" then
        return false, "未知副本"
    end

    local dungeon  = PDM.GetModule(uid, "dungeon")
    local currency = PDM.GetModule(uid, "currency")
    local battleData = PDM.GetModule(uid, "battle")

    if not dungeon or not currency or not battleData then
        return false, "数据未加载"
    end

    -- 解锁检查
    local maxStageId = battleData.maxStageId or battleData.currentStageId or 0
    local unlockReq = DungeonConfig.UNLOCK_CONDITIONS[dungeonId] or 0
    if maxStageId < unlockReq then
        return false, "副本未解锁"
    end

    local subData = getDungeonSubData(dungeon, dungeonId)

    -- 每日重置检查
    checkDailyReset(subData)

    -- 每日次数检查
    local dailyLimit = DungeonConfig.DAILY_SWEEP_LIMIT[dungeonId] or 2
    if subData.dailyUsed >= dailyLimit then
        return false, "今日扫荡次数已用完"
    end

    -- 扫荡层 = 当前层 - 1（必须有已通关的层才能扫荡）
    local sweepFloor = (subData.floor or 1) - 1
    if sweepFloor < 1 then
        return false, "暂无可扫荡层"
    end

    -- 扣除每日次数
    subData.dailyUsed = (subData.dailyUsed or 0) + 1
    PDM.MarkDirty(uid, "dungeon")

    -- ── 分副本奖励逻辑 ──
    if dungeonId == "gold_mine" then
        local floorData = DungeonConfig.getGoldMineFloor(sweepFloor)
        if not floorData then
            return false, "层配置不存在"
        end

        local goldReward = floorData.sweepGold or 0
        if goldReward > 0 then
            currency.gold = (currency.gold or 0) + goldReward
            PDM.MarkDirty(uid, "currency")
        end

        print(string.format("[DungeonService] uid=%s sweep gold_mine floor=%d gold=%d dailyUsed=%d/%d",
            tostring(uid), sweepFloor, goldReward, subData.dailyUsed, dailyLimit))

        return true, nil, {
            dungeonId  = dungeonId,
            sweepFloor = sweepFloor,
            gold       = goldReward,
            dailyUsed  = subData.dailyUsed,
            dailyMax   = dailyLimit,
        }

    else -- ancient_ruin
        local floorData = DungeonConfig.getAncientRuinFloor(sweepFloor)
        if not floorData then
            return false, "层配置不存在"
        end

        -- 奥术粉尘奖励
        local dustReward = floorData.sweepDust or 0
        if dustReward > 0 then
            currency.arcaneDust = (currency.arcaneDust or 0) + dustReward
            PDM.MarkDirty(uid, "currency")
        end

        print(string.format("[DungeonService] uid=%s sweep ancient_ruin floor=%d dust=%d dailyUsed=%d/%d",
            tostring(uid), sweepFloor, dustReward, subData.dailyUsed, dailyLimit))

        return true, nil, {
            dungeonId  = dungeonId,
            sweepFloor = sweepFloor,
            dust       = dustReward,
            dailyUsed  = subData.dailyUsed,
            dailyMax   = dailyLimit,
        }
    end
end

-- ======================== 挑战（进入战斗） ========================

--- 验证挑战请求，返回战斗所需配置
---@param uid number
---@param dungeonId string
---@param floor number
---@return boolean ok
---@return string|nil err
---@return table|nil result  { floor, monsterLevel, monsters, classBonus, ... }
function DungeonService.Challenge(uid, dungeonId, floor)
    if dungeonId ~= "gold_mine" and dungeonId ~= "ancient_ruin" then
        return false, "未知副本"
    end

    local dungeon    = PDM.GetModule(uid, "dungeon")
    local battleData = PDM.GetModule(uid, "battle")

    if not dungeon or not battleData then
        return false, "数据未加载"
    end

    -- 解锁检查
    local maxStageId = battleData.maxStageId or battleData.currentStageId or 0
    local unlockReq = DungeonConfig.UNLOCK_CONDITIONS[dungeonId] or 0
    if maxStageId < unlockReq then
        return false, "副本未解锁"
    end

    local subData = getDungeonSubData(dungeon, dungeonId)

    -- 只能挑战当前层
    local currentFloor = subData.floor or 1
    if floor ~= currentFloor then
        return false, "只能挑战当前层(" .. currentFloor .. ")"
    end

    -- 检查层上限
    local maxFloor = DungeonConfig.MAX_FLOOR[dungeonId] or 35
    if floor > maxFloor then
        return false, "已通关所有层"
    end

    -- 获取层配置
    local floorData
    if dungeonId == "gold_mine" then
        floorData = DungeonConfig.getGoldMineFloor(floor)
    else
        floorData = DungeonConfig.getAncientRuinFloor(floor)
    end
    if not floorData then
        return false, "层配置不存在"
    end

    -- 职业增益
    local classBonus = DungeonConfig.getClassBonus(floor)

    print(string.format("[DungeonService] uid=%s challenge %s floor=%d monsterLv=%d classBonus=%s",
        tostring(uid), dungeonId, floor, floorData.monsterLevel, classBonus))

    local result = {
        dungeonId    = dungeonId,
        floor        = floor,
        monsterLevel = floorData.monsterLevel,
        monsters     = floorData.monsters,
        classBonus   = classBonus,
        classBonusValue  = DungeonConfig.CLASS_BONUS_VALUE,
        rageTime         = DungeonConfig.RAGE_TIME,
        rageAtkBonus     = DungeonConfig.RAGE_ATK_BONUS,
        superRageTime    = DungeonConfig.SUPER_RAGE_TIME,
        superRageAtkBonus = DungeonConfig.SUPER_RAGE_ATK_BONUS,
        superRageDmgBonus = DungeonConfig.SUPER_RAGE_DMG_BONUS,
        allyRageDmgBonus  = DungeonConfig.ALLY_RAGE_DMG_BONUS,
        allySuperRageDmgBonus = DungeonConfig.ALLY_SUPER_RAGE_DMG_BONUS,
    }

    -- 副本特定字段
    if dungeonId == "gold_mine" then
        result.firstGold = floorData.firstGold
    else
        result.firstDust       = floorData.firstDust
    end

    return true, nil, result
end

-- ======================== 胜利结算 ========================

--- 挑战胜利后结算奖励、推进楼层
---@param uid number
---@param dungeonId string
---@param floor number
---@return boolean ok
---@return string|nil err
---@return table|nil result
function DungeonService.Win(uid, dungeonId, floor)
    if dungeonId ~= "gold_mine" and dungeonId ~= "ancient_ruin" then
        return false, "未知副本"
    end

    local dungeon  = PDM.GetModule(uid, "dungeon")
    local currency = PDM.GetModule(uid, "currency")

    if not dungeon or not currency then
        return false, "数据未加载"
    end

    local subData = getDungeonSubData(dungeon, dungeonId)

    local currentFloor = subData.floor or 1
    if floor ~= currentFloor then
        return false, "楼层不匹配"
    end

    -- 判断是否首次通关
    local cleared = subData.cleared or {}
    local isFirstClear = not cleared[floor]

    -- 推进楼层
    local maxFloor = DungeonConfig.MAX_FLOOR[dungeonId] or 35
    if currentFloor < maxFloor then
        subData.floor = currentFloor + 1
    end

    if isFirstClear then
        cleared[floor] = true
        subData.cleared = cleared
    end

    PDM.MarkDirty(uid, "dungeon")

    -- ── 分副本奖励逻辑 ──
    if dungeonId == "gold_mine" then
        local floorData = DungeonConfig.getGoldMineFloor(floor)
        if not floorData then
            return false, "层配置不存在"
        end

        local goldReward = 0
        if isFirstClear then
            goldReward = floorData.firstGold
            currency.gold = (currency.gold or 0) + goldReward
            PDM.MarkDirty(uid, "currency")
        end

        print(string.format("[DungeonService] uid=%s win gold_mine floor=%d firstClear=%s gold=%d nextFloor=%d",
            tostring(uid), floor, tostring(isFirstClear), goldReward, subData.floor))

        return true, nil, {
            dungeonId  = dungeonId,
            floor      = floor,
            firstClear = isFirstClear,
            gold       = goldReward,
            nextFloor  = subData.floor,
        }

    else -- ancient_ruin
        local floorData = DungeonConfig.getAncientRuinFloor(floor)
        if not floorData then
            return false, "层配置不存在"
        end

        local dustReward = 0

        if isFirstClear then
            dustReward = floorData.firstDust
            currency.arcaneDust = (currency.arcaneDust or 0) + dustReward
            PDM.MarkDirty(uid, "currency")
        end

        print(string.format("[DungeonService] uid=%s win ancient_ruin floor=%d firstClear=%s dust=%d nextFloor=%d",
            tostring(uid), floor, tostring(isFirstClear), dustReward, subData.floor))

        return true, nil, {
            dungeonId  = dungeonId,
            floor      = floor,
            firstClear = isFirstClear,
            dust       = dustReward,
            nextFloor  = subData.floor,
        }
    end
end

return DungeonService
