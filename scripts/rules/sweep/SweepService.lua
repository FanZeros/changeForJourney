-- SweepService：私有生成可分帧；奖励与扣券仍由原事务一次同步落盘。
local PDM = require("rules.character.PlayerDataManager")
local Rewards = require("shared.sweep.SweepRewards")
local Progress = require("shared.sweep.SweepProgress")
local EquipmentSystem = require("systems.EquipmentSystem")
local EquipmentPower = require("systems.EquipmentPower")
local LootBoxSystem = require("systems.LootBoxSystem")
local DropSystem = require("systems.DropSystem")
local BlacksmithConfig = require("config.BlacksmithConfig")
local Transaction = require("rules.dungeon.DungeonService")

local SweepService = { SWEEP_COST = Rewards.COST }
local GUARDED_MODULES = { "currency", "battle", "heroes", "player", "equipment", "dungeon", "lootbox", "artifacts", "talents" }
local RESOURCE_SOURCES = { currency = true, battle = true, heroes = true, player = true, dungeon = true }
-- token不暴露候选装备/快照；任何提交尝试都消费，失败不能重放带已分配seq的候选。
local prepared = setmetatable({}, { __mode = "k" }) ---@type table<table, table>

local function getLuck(ids, heroes, equipment, artifacts, talents)
    local ctx = EquipmentPower.buildWornContext(ids[1], {
        heroes = heroes, equipment = equipment, artifacts = artifacts or {}, talents = talents or {},
        -- 掉落幸运消费真实属性，不使用角色显示战力的无神器口径。
        includeArtifactEffects = true,
    })
    return ctx and DropSystem.captureTeamLuck(ctx.teamUnits) or 0
end

--- 预估不读取 PDM、不消费 RNG、不规范化/修改玩家表。
function SweepService.Preview(heroes, battle, dungeon, equipment, artifacts, talents, teamIdx, stageId, count, player)
    local ids, err, team = Rewards.getTeam(heroes, battle, teamIdx)
    if not ids then return nil, err end
    local entry, stageErr = Rewards.resolveStage(battle, dungeon, team, stageId)
    if not entry then return nil, stageErr end
    local times = math.tointeger(tonumber(count == nil and 1 or count) or 0)
    if not times or times < 1 then return nil, "无效的扫荡次数" end
    local luck = getLuck(ids, heroes, equipment, artifacts, talents)
    local result = Rewards.calculate(entry, #ids, times, false, luck, team)
    result.playerProgress, result.heroProgress = Progress.Preview(heroes, ids, player, result)
    result.heroExpBatch = nil
    result.stageId, result.teamIdx, result.count, result.dropLuck = entry.id, team, times, luck
    result.cost = times * Rewards.COST
    return result
end

-- check/isCancelled必须同步；checkpoint才允许yield，且只在进入live事务之前调用。
local function checkControl(control)
    if control and control.isCancelled then
        local called, cancelled = pcall(control.isCancelled)
        if not called then return false, tostring(cancelled) end
        if cancelled then return false, "sweep_cancelled" end
    end
    if control and control.check then
        local called, current, reason = pcall(control.check)
        if not called then return false, tostring(current) end
        if current ~= true then return false, reason or "sweep_stale" end
    end
    return true
end

local function makeCheckpoint(control)
    if not control then return nil end
    return function(phase, completed, total)
        local current, reason = checkControl(control)
        if not current then error(reason, 0) end
        if control.checkpoint then control.checkpoint(phase, completed, total) end
        current, reason = checkControl(control)
        if not current then error(reason, 0) end
    end
end

-- 保存每条原table边/值，包括共享引用和额外旧档字段；不遍历或输出玩家文件。
-- 逐字段检查点仅增长私有records。最终比较不yield，替换等值子表也视为过期。
local function capture(value, records, byTable, checkpoint, counter)
    if type(value) ~= "table" or byTable[value] then return end
    local record = { target = value, fields = {} }
    byTable[value] = record
    records[#records + 1] = record
    for key, child in pairs(value) do
        record.fields[key] = child
        capture(child, records, byTable, checkpoint, counter)
        counter.value = counter.value + 1
        if checkpoint then checkpoint("prepare", counter.value, 0) end
    end
end

local function copyCaptured(value, byTable, copies, checkpoint, counter)
    if type(value) ~= "table" then return value end
    if copies[value] then return copies[value] end
    local result = {}
    copies[value] = result
    for key, child in pairs(byTable[value].fields) do
        result[key] = copyCaptured(child, byTable, copies, checkpoint, counter)
        counter.value = counter.value + 1
        if checkpoint then checkpoint("prepare", counter.value, 0) end
    end
    return result
end

local function sameSources(uid, data)
    for _, name in ipairs(GUARDED_MODULES) do
        if PDM.GetModule(uid, name) ~= data.sources[name] then return false end
    end
    for _, record in ipairs(data.records) do
        for key, child in pairs(record.fields) do
            if record.target[key] ~= child then return false end
        end
        for key in pairs(record.target) do
            if record.fields[key] == nil then return false end
        end
    end
    return true
end

--- args={count,teamIdx,stageId}; control={checkpoint(phase,done,total),check,isCancelled,onCommitted,summaryLogs}。
--- 返回私有候选token，准备期间绝不扣券/写live/发通知。Bridge负责独占全局RNG、防ABA与生命周期。
---@param uid number
---@param args table
---@param control table|nil
---@return table|nil, string|nil
function SweepService.PrepareSweep(uid, args, control)
    args = args or {}
    local times = math.tointeger(tonumber(args.count == nil and 1 or args.count) or 0)
    if not times or times < 1 then return nil, "无效的扫荡次数" end
    local current, reason = checkControl(control)
    if not current then return nil, reason end
    local sources = {}
    for _, name in ipairs(GUARDED_MODULES) do sources[name] = PDM.GetModule(uid, name) end
    local currency, battle, heroes, player, equipment = sources.currency, sources.battle, sources.heroes, sources.player, sources.equipment
    if not currency or not battle or not heroes or not player or not equipment then return nil, "数据未加载" end
    local ids, teamErr, team = Rewards.getTeam(heroes, battle, args.teamIdx)
    if not ids then return nil, teamErr end
    local entry, stageErr = Rewards.resolveStage(battle, sources.dungeon, team, args.stageId)
    if not entry then return nil, stageErr end
    local resourceOnly = entry.resourceDungeonId == "gold_mine" or entry.resourceDungeonId == "black_diamond"
    local cost, owned = times * Rewards.COST, tonumber(currency.sweepTicket) or 0
    if owned ~= owned or owned == math.huge or owned < cost then return nil, "扫荡券不足" end
    local ready, readyErr = Transaction.CanCommitRewardTransaction(uid)
    if not ready then return nil, readyErr end
    local checkpoint = makeCheckpoint(control)
    local called, candidate, err = pcall(function()
        local records, byTable, counter = {}, {}, { value = 0 }
        if checkpoint then checkpoint("prepare", 0, 0) end
        -- 纯货币副本不读取装备/遗匣内容，也不受幸运或自动分解影响。
        -- 全部根引用仍校验；深层值只冻结本次结算实际读取/修改的模块。
        for _, name in ipairs(GUARDED_MODULES) do
            if not resourceOnly or RESOURCE_SOURCES[name] then
                capture(sources[name], records, byTable, checkpoint, counter)
            end
        end
        -- 主线/装备副本仍复制幸运与分解上下文；纯货币只需私有编队副本。
        local copies, snapshot = {}, {}
        local copiedModules = resourceOnly and { "heroes" } or { "heroes", "equipment", "artifacts", "talents" }
        for _, name in ipairs(copiedModules) do
            snapshot[name] = copyCaptured(sources[name], byTable, copies, checkpoint, counter)
        end
        local data = { uid = uid, control = control, sources = sources, records = records,
            ids = ids, team = team, entry = entry, times = times, owned = owned, cost = cost,
            keptEquips = {}, decomposedEquips = {}, autoEssence = 0 }
        if not sameSources(uid, data) then return nil, "sweep_stale" end
        -- 首个检查点之前已做快速拒绝；捕获尚未访问的字段可能被自定义宿主改动。
        -- 再验证所有前置推导量，绝不把旧队员/余额与后来捕获的快照拼接提交。
        -- 任意瞬时ABA仍由Bridge epoch/revision保证，不声称单靠最终值能检测历史。
        local capturedIds, _, capturedTeam = Rewards.getTeam(snapshot.heroes, sources.battle, args.teamIdx)
        local capturedEntry = capturedIds and Rewards.resolveStage(sources.battle, sources.dungeon, capturedTeam, args.stageId)
        if not capturedIds or capturedTeam ~= team or not capturedEntry or capturedEntry.id ~= entry.id
            or (tonumber(sources.currency.sweepTicket) or 0) ~= owned or #capturedIds ~= #ids then
            return nil, "sweep_stale"
        end
        for index, id in ipairs(ids) do
            if capturedIds[index] ~= id then return nil, "sweep_stale" end
        end
        local luck = resourceOnly and 0 or getLuck(ids, snapshot.heroes, snapshot.equipment, snapshot.artifacts, snapshot.talents)
        data.rewards = Rewards.calculate(entry, #ids, times, true, luck, team,
            control and { checkpoint = checkpoint, summaryLogs = control.summaryLogs } or nil)
        local equips = data.rewards.equips
        if checkpoint then checkpoint("classify", 0, #equips) end
        for index, equip in ipairs(equips) do
            if not equip.locked and BlacksmithConfig.shouldAutoDecompose(snapshot.equipment.settings, equip.quality, equip.level) then
                data.decomposedEquips[#data.decomposedEquips + 1] = equip
                data.autoEssence = data.autoEssence + BlacksmithConfig.calcAutoDecomposeEssence(equip.quality, equip.level)
            else
                data.keptEquips[#data.keptEquips + 1] = equip
            end
            if checkpoint then checkpoint("classify", index, #equips) end
        end
        if data.rewards.batchQualities then
            -- 大批掉落：结算时才逐件生成；准备阶段只保留品质序列。
            -- 装备等级全场一致，生成结果只由品质决定，因此序列足以精确重建奖励。
            local settings = snapshot.equipment.settings
            local level = entry.monsterLevel
            local sequences, autoCounts, autoCount, autoEssence = {}, {}, 0, 0
            for index, quality in ipairs(data.rewards.batchQualities) do
                if BlacksmithConfig.shouldAutoDecompose(settings, quality, level) then
                    autoCounts[quality] = (autoCounts[quality] or 0) + 1
                    autoCount = autoCount + 1
                    autoEssence = autoEssence + BlacksmithConfig.calcAutoDecomposeEssence(quality, level)
                else
                    sequences[#sequences + 1] = quality
                end
                if checkpoint and index % 1024 == 0 then
                    checkpoint("classify", index, #data.rewards.batchQualities)
                end
            end
            data.batchQualities, data.batchLevel = sequences, level
            data.batchAutoCounts = autoCounts
            data.batchAutoCount, data.batchAutoEssence = autoCount, autoEssence
            data.autoEssence = data.autoEssence + autoEssence
            -- 只有装不下的部分才需要遗匣；与原逐件路径的容量门禁同义。
            local free = math.max(0, EquipmentSystem.MAX_INVENTORY
                - EquipmentSystem.getInventoryCount(snapshot.equipment))
            if #sequences > free and not sources.lootbox then return nil, "遗匣数据未加载" end
            equips = {}
        end
        if #data.keptEquips > 0
            and EquipmentSystem.getInventoryCount(snapshot.equipment) + #data.keptEquips > EquipmentSystem.MAX_INVENTORY
            and not sources.lootbox then return nil, "遗匣数据未加载" end
        local valid, checkErr = checkControl(control)
        if not valid then return nil, checkErr end
        if not sameSources(uid, data) then return nil, "sweep_stale" end
        local token = {}
        prepared[token] = data
        return token
    end)
    if not called then return nil, tostring(candidate) end
    if type(candidate) ~= "table" then return nil, err end
    return candidate, nil
end

--- 最终校验→原事务之间没有yield；同步保存、规范化和通知仍可能出现大尾段。
---@param uid number
---@param token table
---@param control table|nil
---@return boolean, string|nil, table|nil
function SweepService.CommitSweep(uid, token, control)
    local data = type(token) == "table" and prepared[token] or nil
    if data then prepared[token] = nil end
    if not data or data.uid ~= uid or data.control ~= control then return false, "sweep_candidate_invalid" end
    local current, reason = checkControl(control)
    if not current then return false, reason end
    if not sameSources(uid, data) then return false, "sweep_stale" end
    local sources, rewards = data.sources, data.rewards
    local currency, equipment, lootbox = sources.currency, sources.equipment, sources.lootbox
    local keptEquips, decomposedEquips, autoEssence = data.keptEquips, data.decomposedEquips, data.autoEssence
    local ok, err, result = Transaction.CommitRewardTransaction(uid, function()
        currency.sweepTicket = data.owned - data.cost
        currency.gold = (currency.gold or 0) + rewards.gold
        currency.gems = (currency.gems or 0) + rewards.diamond
        if autoEssence > 0 then currency.essence = (currency.essence or 0) + autoEssence end
        for field, amount in pairs(rewards.scrollDrops) do currency[field] = (currency[field] or 0) + amount end
        Transaction.MarkRewardDirty(uid, "currency")
        local granted, byQuality = {}, {}
        local inventoryCount, lootboxCount = 0, 0
        local delivery = #keptEquips > 0
            and LootBoxSystem.createDeliveryContext(equipment, { summaryLogs = control and control.summaryLogs }) or nil
        for _, equip in ipairs(keptEquips) do
            local destination = LootBoxSystem.deliverEquipment(lootbox, equipment, equip, delivery)
            if destination == "lootbox" then lootboxCount = lootboxCount + 1
            else inventoryCount = inventoryCount + 1 end
            granted[#granted + 1] = { type = "equip", templateId = equip.templateId,
                quality = equip.quality, level = equip.level, slot = equip.slot,
                equip = equip, destination = destination }
            byQuality[equip.quality] = (byQuality[equip.quality] or 0) + 1
        end
        if data.batchQualities then
            -- 大批掉落：只为本就能装进背包的前 N 件生成实体装备，其余按品质聚合入遗匣。
            -- 品质序列已在准备阶段按原掉落顺序冻结，因此分配结果和逐件处理一致。
            local level = data.batchLevel
            local free = math.max(0, EquipmentSystem.MAX_INVENTORY - EquipmentSystem.getInventoryCount(equipment))
            local qualities = data.batchQualities
            local fitted = math.min(free, #qualities)
            for index = 1, fitted do
                local quality = qualities[index]
                local equip = EquipmentSystem.generateRandom(level, quality)
                if not equip then error("扫荡装备生成失败") end
                EquipmentSystem.addToInventory(equipment, equip)
                inventoryCount = inventoryCount + 1
                granted[#granted + 1] = { type = "equip", templateId = equip.templateId,
                    quality = equip.quality, level = equip.level, slot = equip.slot,
                    equip = equip, destination = "inventory" }
                byQuality[quality] = (byQuality[quality] or 0) + 1
            end
            if fitted < #qualities then
                -- 同一品质/等级合并为一条；遗匣不再为每件实体装备落盘。
                local counts, order = {}, {}
                for index = fitted + 1, #qualities do
                    local quality = qualities[index]
                    if not counts[quality] then
                        counts[quality] = 0
                        order[#order + 1] = quality
                    end
                    counts[quality] = counts[quality] + 1
                    byQuality[quality] = (byQuality[quality] or 0) + 1
                end
                for _, quality in ipairs(order) do
                    LootBoxSystem.addBatch(lootbox, quality, level, counts[quality], "overflow")
                    lootboxCount = lootboxCount + counts[quality]
                    granted[#granted + 1] = { type = "equipbatch", quality = quality,
                        level = level, amount = counts[quality], destination = "lootbox" }
                end
            end
        end
        if inventoryCount > 0 then Transaction.MarkRewardDirty(uid, "equipment") end
        if data.batchAutoCount and data.batchAutoCount > 0 and lootbox then
            -- 自动分解在准备阶段已按品质汇总，只写一次累计通知；
            -- 件数与精粹与逐件调用完全相同。
            for quality, count in pairs(data.batchAutoCounts or {}) do
                BlacksmithConfig.recordAutoDecomposeBatch(lootbox, quality, data.batchLevel, count,
                    BlacksmithConfig.calcAutoDecomposeEssence(quality, data.batchLevel))
            end
        end
        if autoEssence > 0 and lootbox then
            for _, equip in ipairs(decomposedEquips) do
                local essence = BlacksmithConfig.calcAutoDecomposeEssence(equip.quality, equip.level)
                BlacksmithConfig.recordAutoDecompose(lootbox, equip.quality, equip.level, essence)
            end
        end
        if lootboxCount > 0 or (autoEssence > 0 and lootbox) then Transaction.MarkRewardDirty(uid, "lootbox") end
        if autoEssence > 0 then
            rewards.autoDecomposeCount = #decomposedEquips + (data.batchAutoCount or 0)
            rewards.autoDecomposeEssence = autoEssence
        end
        rewards.playerProgress, rewards.heroProgress = Progress.Apply(sources.heroes, data.ids, sources.player, rewards)
        if rewards.heroExp > 0 then Transaction.MarkRewardDirty(uid, "heroes") end
        if rewards.playerExp > 0 then Transaction.MarkRewardDirty(uid, "player") end
        rewards.heroExpBatch = nil
        rewards.equips, rewards.equipByQuality = granted, byQuality
        rewards.count, rewards.teamIdx, rewards.stageId = data.times, data.team, data.entry.id
        rewards.sweepStages, rewards.ticketLeft = { data.entry.id }, currency.sweepTicket
        rewards.inventoryCount, rewards.lootboxCount = inventoryCount, lootboxCount
        return true, nil, rewards
    end, function()
        -- 原事务此回调在persist成功、所有订阅者之前；回调失败不能把真实到账说成未完成。
        if control and control.onCommitted then pcall(control.onCommitted, rewards) end
    end)
    if not ok then return false, err end
    pcall(function()
        print(string.format("[SweepService] 队%d 关卡%d %d场 金币=%d 黑晶=%d 经验=%d 装备=%d 卷轴=%d 剩余券=%s",
            data.team, data.entry.id, data.times, result.gold, result.diamond, result.playerExp,
            result.equipCount, result.scrollCount, tostring(result.ticketLeft)))
    end)
    return true, nil, result
end

--- 老API不传control仍同步完成；可选control供直接协程调用方使用同一私有准备链。
function SweepService.Sweep(uid, count, teamIdx, stageId, control)
    local candidate, err = SweepService.PrepareSweep(uid, { count = count, teamIdx = teamIdx, stageId = stageId }, control)
    if not candidate then return false, err end
    return SweepService.CommitSweep(uid, candidate, control)
end

return SweepService
