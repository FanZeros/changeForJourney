-- ============================================================================
-- DungeonService - 资源副本挑战、首通与每日扫荡
-- 奖励在规则层一次结算；副本不推进主线，旧遗迹仅保留兼容。
-- ============================================================================
local PDM = require("rules.character.PlayerDataManager")
local DC = require("config.DungeonConfig")
local EquipmentSystem = require("systems.EquipmentSystem")
local LootBoxSystem = require("systems.LootBoxSystem")
local ExpTable = require("config.ExpTable")
local TeamSlots = require("shared.heroes.TeamSlots")
local GameState = require("core.GameState")
local ModuleRegistry = require("shared.ModuleRegistry")
local CharacterSchema = require("shared.schemas.CharacterSchema")

local DungeonService = {}

---@type (fun(uid: number): boolean|nil)|nil
local persist_ = nil
local persistHooks_ = {} ---@type table
---@type table<string, table>
local transactions = {}
-- Flush 会推进在线边界；它异常时 session 也属于本次候选快照。
local TRANSACTION_MODULES = { "dungeon", "currency", "equipment", "lootbox", "session" }

--- 单机桥注入唯一写档入口的布尔结果；PDM.FlushImmediate 只是日志，不能代替。
--- hooks 延后 Save 内 MarkOnline 的 session 通知，不承担奖励发放。
---@param callback (fun(uid: number): boolean|nil)|nil
---@param hooks table|nil { begin=function(uid), finish=function(uid,success) }
function DungeonService.SetPersistCallback(callback, hooks)
    persist_ = callback
    persistHooks_ = hooks or {}
end

--- 快照保存原 table 的边，不以 JSON/重建表替换；onLoad 换子表也能恢复外部别名。
local function captureTables(value, records, seen)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    local fields = {}
    records[#records + 1] = { target = value, fields = fields }
    for key, child in pairs(value) do
        fields[key] = child
        captureTables(child, records, seen)
    end
end

local function restoreTables(records)
    for _, record in ipairs(records) do
        for key in pairs(record.target) do record.target[key] = nil end
        for key, value in pairs(record.fields) do record.target[key] = value end
    end
end

local function markDirty(uid, name)
    local transaction = transactions[tostring(uid)]
    if transaction then transaction.dirty[name] = true
    else PDM.MarkDirty(uid, name) end
end

--- 奖励、计数、积累一起提交；异常/false/nil 均回滚，成功后才通知和消费挑战。
---@param uid number
---@param operation fun(): boolean, string|nil, table|nil
---@param onCommitted function|nil 仅用于消费本事务的运行时挑战，不承担发奖
---@return boolean, string|nil, table|nil
function DungeonService.CommitRewardTransaction(uid, operation, onCommitted)
    local key = tostring(uid)
    if transactions[key] then return false, "副本结算处理中" end
    if type(persist_) ~= "function" then return false, "副本持久化未接线" end
    local records, seen = {}, {}
    for _, name in ipairs(TRANSACTION_MODULES) do
        captureTables(PDM.GetModule(uid, name), records, seen)
    end
    local stateBefore = GameState.exportSave()
    local transaction = { dirty = {} }
    transactions[key] = transaction
    local reason = "奖励发放失败"
    local called, success, err, result = pcall(function()
        if persistHooks_.begin then persistHooks_.begin(uid) end
        local ok, operationErr, rewards = operation()
        if ok ~= true then return false, operationErr end
        -- 与正式 Dispatcher 同一双 onLoad 顺序，先规范化候选，再写入完整快照。
        -- 错误不吞掉，否则会把半规范化的候选当成成功提交。
        for _, name in ipairs(TRANSACTION_MODULES) do
            if transaction.dirty[name] then
                local data = PDM.GetModule(uid, name)
                local registered = ModuleRegistry.find(name)
                if registered and registered.onLoad then registered.onLoad(data) end
                local schema = CharacterSchema.Fields[name]
                if schema and schema.onLoad then schema.onLoad(data) end
            end
        end
        if transaction.dirty.currency then
            GameState.syncFromCurrency(PDM.GetModule(uid, "currency"), { silent = true })
        end
        reason = "副本存档失败，可重试"
        if persist_(uid) ~= true then return false, reason end
        return true, nil, rewards
    end)
    if not called or success ~= true then
        restoreTables(records)
        GameState.syncFromCurrency(stateBefore, { silent = true })
        if persistHooks_.finish then
            local finished, finishErr = pcall(persistHooks_.finish, uid, false)
            if not finished then print("[DungeonService] 回滚通知清理失败: " .. tostring(finishErr)) end
        end
        transactions[key] = nil
        print("[DungeonService] 事务回滚 uid=" .. key .. " reason=" .. tostring(called and err or success))
        return false, called and (err or reason) or reason
    end
    -- 在任何订阅者执行前消费；尤其末层不推进时不能被同步回调重复结算。
    if onCommitted then onCommitted() end
    for _, name in ipairs(TRANSACTION_MODULES) do
        if transaction.dirty[name] then
            local notified, notifyErr = pcall(PDM.MarkDirty, uid, name)
            if not notified then print("[DungeonService] 已提交，通知失败 " .. name .. ": " .. tostring(notifyErr)) end
        end
    end
    if persistHooks_.finish then
        local finished, finishErr = pcall(persistHooks_.finish, uid, true)
        if not finished then print("[DungeonService] 已提交，通知释放失败: " .. tostring(finishErr)) end
    end
    if transaction.dirty.currency and not persistHooks_.finish then
        local notified, notifyErr = pcall(GameState.syncFromCurrency, PDM.GetModule(uid, "currency"))
        if not notified then print("[DungeonService] 已提交，余额通知失败: " .. tostring(notifyErr)) end
    end
    transactions[key] = nil
    return true, nil, result
end

--- 挂机货币只允许已有三类资源，不走会立即通知的 CurrencyService.GrantReward。
---@return boolean
function DungeonService.GrantIdleCurrency(uid, rewardType, amount)
    local field = ({ gold = "gold", diamond = "gems", arcane_dust = "arcaneDust" })[rewardType]
    local currency = PDM.GetModule(uid, "currency")
    if not field or not currency or type(amount) ~= "number" or amount ~= amount
        or amount <= 0 or amount == math.huge or amount ~= math.floor(amount) then return false end
    currency[field] = (currency[field] or 0) + amount
    markDirty(uid, "currency")
    return true
end

--- 挂机扣时也参加同一事务的延后通知。
function DungeonService.MarkRewardDirty(uid, name)
    markDirty(uid, name)
end

-- 单机每位玩家只持有一场资源战斗；不写进存档，重启/退出后必须重新 Challenge。
local pendingChallenges = {} ---@type table<string, table>
local nextChallengeId = 0

function DungeonService.Cleanup(uid)
    pendingChallenges[tostring(uid)] = nil
end

local function isKnown(id)
    return DC.isResourceDungeon(id) or id == "ancient_ruin"
end

local function getSub(dungeon, id)
    if not dungeon[id] then
        dungeon[id] = { floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0, idleAccumSec = 0 }
    end
    return dungeon[id]
end

local function getUnlockedData(uid, id)
    if not isKnown(id) then return nil, nil, "未知副本" end
    local dungeon = PDM.GetModule(uid, "dungeon")
    local battle = PDM.GetModule(uid, "battle")
    if not dungeon or not battle then return nil, nil, "数据未加载" end
    if (tonumber(battle.maxStageId or battle.currentStageId) or 0) < (DC.UNLOCK_CONDITIONS[id] or 0) then
        return nil, nil, "副本未解锁"
    end
    return getSub(dungeon, id), battle, nil
end

local function checkTeam(uid, battle, teamIdx, legacy)
    -- 旧遗迹未传队号保留原 API；资源缺省队1必须照常校验，不能用 nil 绕过。
    if teamIdx == nil and legacy then return true, nil, nil, nil end
    local team = math.tointeger(tonumber(teamIdx == nil and 1 or teamIdx) or 0)
    if not team or team < 1 or team > ExpTable.TEAM_COUNT then return false, "无效的队伍编号" end
    if team > ExpTable.getUnlockedTeamCount(battle) then return false, "该队伍尚未解锁" end
    local heroes = PDM.GetModule(uid, "heroes")
    if type(heroes) ~= "table" then return false, "队伍数据未加载" end
    -- 校验只读：在副本里不能顺带改写主线编队/镜像。
    local snapshot = { deployed = heroes.deployed, teams = {} }
    for i = 1, ExpTable.TEAM_COUNT do
        local source = type(heroes.teams) == "table" and heroes.teams[i]
        snapshot.teams[i] = { slots = type(source) == "table" and type(source.slots) == "table" and source.slots or {} }
    end
    local rawSlots = snapshot.teams[team].slots
    if team == 1 and #rawSlots == 0 and type(heroes.deployed) == "table" then rawSlots = heroes.deployed end
    if type(rawSlots) ~= "table" or #rawSlots > ExpTable.TEAM_MAX_SLOTS then
        return false, "无效的队伍槽位"
    end
    local seen = {}
    for _, heroId in ipairs(rawSlots) do
        local id = math.tointeger(tonumber(heroId) or -1)
        if not id or id < 0 then return false, "无效的出战英雄" end
        if id > 0 then
            if seen[id] then return false, "重复的出战英雄" end
            seen[id] = true
        end
    end
    TeamSlots.normalize(snapshot)
    local slots = snapshot.teams[team].slots
    local owned = 0
    for _, heroId in ipairs(slots) do
        local id = math.tointeger(tonumber(heroId) or 0)
        if not id or id < 0 then return false, "无效的出战英雄" end
        if id > 0 then
            local roster = heroes.roster
            if type(roster) ~= "table" or not (roster[id] or roster[tostring(id)]) then
                return false, "未拥有出战英雄"
            end
            owned = owned + 1
        end
    end
    if owned == 0 then return false, "该队伍未出战英雄" end
    return true, nil, team, table.concat(slots, ":")
end

--- 批量先生成、检查安全容器，再交付；失败不消耗日次或首通记录。
---@return boolean, string|nil, table|nil
function DungeonService.GrantEquipment(uid, dungeonId, floor, count)
    if dungeonId ~= "equipment_vault" then return false, "非装备副本" end
    count = math.tointeger(tonumber(count) or 0)
    local floorData = DC.getFloor(dungeonId, floor)
    local equipment = PDM.GetModule(uid, "equipment")
    local lootbox = PDM.GetModule(uid, "lootbox")
    if not count or count < 0 or not floorData then return false, "装备奖励配置无效" end
    if not equipment then return false, "装备数据未加载" end
    if EquipmentSystem.getInventoryCount(equipment) + count > EquipmentSystem.MAX_INVENTORY and not lootbox then
        return false, "遗匣数据未加载"
    end
    local generated = {}
    for i = 1, count do
        local quality = math.random(floorData.equipMinQuality, floorData.equipMaxQuality)
        local equip = EquipmentSystem.generateRandom(floorData.equipLevel, quality)
        if not equip then return false, "装备生成失败" end
        generated[i] = equip
    end
    local result = { equips = {}, inventoryCount = 0, lootboxCount = 0 }
    for _, equip in ipairs(generated) do
        local destination = LootBoxSystem.deliverEquipment(lootbox, equipment, equip)
        if destination == "lootbox" then result.lootboxCount = result.lootboxCount + 1
        else result.inventoryCount = result.inventoryCount + 1 end
        result.equips[#result.equips + 1] = {
            type = "equip", templateId = equip.templateId, quality = equip.quality,
            level = equip.level, slot = equip.slot, equip = equip, destination = destination,
        }
    end
    if result.inventoryCount > 0 then markDirty(uid, "equipment") end
    if result.lootboxCount > 0 then markDirty(uid, "lootbox") end
    return true, nil, result
end

--- 一次扫荡当量对应的卷轴与扫荡券：与挂机同口径（24h 挂机 = 两次扫荡）。
---@param floor number
---@return number scrollPerSweep, number ticketPerSweep
local function equipScrollPerSweep(floor)
    local scrollRate, ticketRate = DC.getEquipDropRates(floor)
    local idle = require("config.DungeonIdleConfig")
    local fullMinutes = idle.MAX_ACCUM_MIN
    local fullSeconds = idle.FULL_RATE_SEC
    local function perSweep(rate)
        return math.max(1, math.floor(rate * fullSeconds / fullMinutes))
    end
    return perSweep(scrollRate), perSweep(ticketRate)
end

--- 把卷轴/扫荡券写入货币；只发配置里存在的字段。
---@param uid number
---@param floor number
---@param sweepCount number 本次发奖的扫荡当量数（首通=2，扫荡/挂机=1）
---@return table scrollDrops
local function grantEquipScrolls(uid, floor, sweepCount)
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return {} end
    local scrollPerSweep, ticketPerSweep = equipScrollPerSweep(floor)
    local scrollTotal = scrollPerSweep * sweepCount
    local ticketTotal = ticketPerSweep * sweepCount
    local scrollTypes = { "weaponScroll", "offhandScroll", "armorScroll", "helmetScroll", "shoesScroll", "accessoryScroll" }
    local drops = {}
    for _ = 1, scrollTotal do
        local st = scrollTypes[math.random(1, #scrollTypes)]
        drops[st] = (drops[st] or 0) + 1
    end
    for field, count in pairs(drops) do
        currency[field] = (currency[field] or 0) + count
    end
    if ticketTotal > 0 then
        currency.sweepTicket = (currency.sweepTicket or 0) + ticketTotal
        drops.sweepTicket = ticketTotal
    end
    markDirty(uid, "currency")
    return drops
end

--- 公开入口：装备副本卷轴/扫荡券发放（供挂机领取在同一事务内调用）。
---@param uid number
---@param floor number
---@param sweepCount number
---@return table scrollDrops
function DungeonService.GrantEquipScrolls(uid, floor, sweepCount)
    return grantEquipScrolls(uid, floor, sweepCount)
end

local function grantRewards(uid, id, floorData, firstClear)
    if id == "equipment_vault" then
        local sweep = floorData.sweepEquip or 0
        local count = firstClear and (floorData.firstEquip or sweep * 2) or sweep
        local ok, err, result = DungeonService.GrantEquipment(uid, id, floorData.floor, count)
        if not ok then return false, err end
        result = result or {}
        -- 首通=两次扫荡当量，扫荡=一次；与挂机同口径补卷轴与扫荡券。
        result.scrollDrops = grantEquipScrolls(uid, floorData.floor, firstClear and 2 or 1)
        return true, nil, result
    end
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "数据未加载" end
    local gold = id == "gold_mine" and (firstClear and floorData.firstGold or floorData.sweepGold) or 0
    local diamond = id == "black_diamond" and (firstClear and floorData.firstDiamond or floorData.sweepDiamond) or 0
    local dust = id == "ancient_ruin" and (firstClear and floorData.firstDust or floorData.sweepDust) or 0
    if gold > 0 then currency.gold = (currency.gold or 0) + gold end
    if diamond > 0 then currency.gems = (currency.gems or 0) + diamond end
    if dust > 0 then currency.arcaneDust = (currency.arcaneDust or 0) + dust end
    if gold > 0 or diamond > 0 or dust > 0 then markDirty(uid, "currency") end
    return true, nil, { gold = gold, diamond = diamond, dust = dust }
end

function DungeonService.Sweep(uid, dungeonId)
    local sub, _, err = getUnlockedData(uid, dungeonId)
    if not sub then return false, err end
    local today = math.floor((os.time() + 28800) / 86400)
    local used = sub.dailyDay == today and (sub.dailyUsed or 0) or 0
    local limit = DC.DAILY_SWEEP_LIMIT[dungeonId] or 2
    if used >= limit then return false, "今日扫荡次数已用完" end
    local floor = DC.getHighestClearedFloor(sub, dungeonId)
    if floor < 1 then return false, "暂无可扫荡层" end
    local floorData = DC.getFloor(dungeonId, floor)
    if not floorData then return false, "层配置不存在" end
    local ok, grantErr, result = DungeonService.CommitRewardTransaction(uid, function()
        local granted, rewardErr, rewards = grantRewards(uid, dungeonId, floorData, false)
        if not granted then return false, rewardErr end
        sub.dailyUsed, sub.dailyDay = used + 1, today
        markDirty(uid, "dungeon")
        rewards.dungeonId, rewards.sweepFloor = dungeonId, floor
        rewards.dailyUsed, rewards.dailyMax = sub.dailyUsed, limit
        return true, nil, rewards
    end)
    if not ok then return false, grantErr end
    print(string.format("[DungeonService] 扫荡 %s 层=%d 次数=%d/%d", dungeonId, floor, sub.dailyUsed, limit))
    return true, nil, result
end

function DungeonService.Challenge(uid, dungeonId, floor, teamIdx)
    local sub, battle, err = getUnlockedData(uid, dungeonId)
    if not sub then return false, err end
    floor = math.tointeger(tonumber(floor) or 0)
    if not floor or floor ~= sub.floor then return false, "只能挑战当前层" end
    local floorData = DC.getFloor(dungeonId, floor)
    if not floorData then return false, "层配置不存在" end
    local teamOk, teamErr, team, teamSignature = checkTeam(uid, battle, teamIdx, dungeonId == "ancient_ruin")
    if not teamOk then return false, teamErr end
    local entry = DC.getCombatEntry(dungeonId, floor)
    local challengeId
    if entry then
        local key = tostring(uid)
        local pending = pendingChallenges[key]
        -- 相同请求幂等复用；重新选层/队伍会替换旧战斗，旧回执不能结算新挑战。
        if not pending or pending.dungeonId ~= dungeonId or pending.floor ~= floor
            or pending.teamIdx ~= team or pending.teamSignature ~= teamSignature then
            nextChallengeId = nextChallengeId + 1
            pending = { dungeonId = dungeonId, floor = floor, teamIdx = team,
                teamSignature = teamSignature, challengeId = nextChallengeId }
            pendingChallenges[key] = pending
        end
        challengeId = pending.challengeId
    end
    local result = {
        dungeonId = dungeonId, floor = floor, teamIdx = team, challengeId = challengeId,
        monsterLevel = floorData.monsterLevel, monsters = floorData.monsters,
        resourceCombat = entry ~= nil, stageEntry = entry,
        maxFieldEnemies = entry and entry.maxFieldEnemies or 5,
        firstGold = floorData.firstGold, firstDust = floorData.firstDust,
        firstDiamond = floorData.firstDiamond, firstEquip = floorData.firstEquip,
        classBonus = entry and "" or DC.getClassBonus(floor),
        classBonusValue = entry and 0 or DC.CLASS_BONUS_VALUE,
        rageTime = entry and 120 or DC.RAGE_TIME,
        rageAtkBonus = DC.RAGE_ATK_BONUS,
        superRageTime = entry and 210 or DC.SUPER_RAGE_TIME,
        superRageAtkBonus = DC.SUPER_RAGE_ATK_BONUS,
        superRageDmgBonus = DC.SUPER_RAGE_DMG_BONUS,
        allyRageDmgBonus = DC.ALLY_RAGE_DMG_BONUS,
        allySuperRageDmgBonus = DC.ALLY_SUPER_RAGE_DMG_BONUS,
    }
    print(string.format("[DungeonService] 挑战 %s 层=%d 队伍=%s 主线复用=%s", dungeonId, floor, tostring(team), tostring(entry ~= nil)))
    return true, nil, result
end

function DungeonService.Win(uid, dungeonId, floor, teamIdx, challengeId)
    local sub, battle, err = getUnlockedData(uid, dungeonId)
    if not sub then return false, err end
    floor = math.tointeger(tonumber(floor) or 0)
    if not floor or floor ~= sub.floor then return false, "楼层不匹配" end
    local floorData = DC.getFloor(dungeonId, floor)
    if not floorData then return false, "层配置不存在" end
    local teamOk, teamErr, team, teamSignature = checkTeam(uid, battle, teamIdx, dungeonId == "ancient_ruin")
    if not teamOk then return false, teamErr end
    local key = tostring(uid)
    if DC.isResourceDungeon(dungeonId) then
        local pending = pendingChallenges[key]
        if not pending or pending.dungeonId ~= dungeonId or pending.floor ~= floor then
            return false, "没有匹配的副本挑战"
        end
        if pending.teamIdx ~= team or pending.teamSignature ~= teamSignature then
            return false, "挑战队伍已变更"
        end
        -- 新入口传 challengeId 防过期回执；老调用省略时仍必须匹配当前 pending。
        if challengeId ~= nil and math.tointeger(tonumber(challengeId) or 0) ~= pending.challengeId then
            return false, "副本挑战已过期"
        end
    end
    local cleared = sub.cleared or {}
    local firstClear = cleared[floor] ~= true and cleared[tostring(floor)] ~= true
    local ok, commitErr, result = DungeonService.CommitRewardTransaction(uid, function()
        local rewards = { gold = 0, diamond = 0, dust = 0, equips = {} } ---@type table
        if firstClear then
            local granted, grantErr, generated = grantRewards(uid, dungeonId, floorData, true)
            if not granted or not generated then return false, grantErr end
            rewards = generated
            cleared[floor] = true
            sub.cleared = cleared
        end
        if sub.floor < DC.MAX_FLOOR[dungeonId] then sub.floor = sub.floor + 1 end
        markDirty(uid, "dungeon")
        rewards.dungeonId, rewards.floor, rewards.teamIdx = dungeonId, floor, team
        rewards.challengeId = challengeId
        rewards.firstClear, rewards.nextFloor = firstClear, sub.floor
        return true, nil, rewards
    end, function()
        if DC.isResourceDungeon(dungeonId) then pendingChallenges[key] = nil end
    end)
    if not ok then return false, commitErr end
    print(string.format("[DungeonService] 通关 %s 层=%d 首通=%s 下一层=%d", dungeonId, floor, tostring(firstClear), sub.floor))
    return true, nil, result
end

return DungeonService
