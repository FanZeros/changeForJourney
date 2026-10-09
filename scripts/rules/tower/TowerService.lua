---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- TowerService - 112 真实层；每层一波，五层一局，逐层事务结算。
-- 当局暗契/开奖/回执仅在内存；存档继续保留旧 floor/cleared 语义。
-- ============================================================================
local PDM = require("rules.character.PlayerDataManager")
local TowerConfig = require("config.TowerConfig")
local ExpTable = require("config.ExpTable")
local DungeonService = require("rules.dungeon.DungeonService")
local ArtifactDefs = require("shared.artifact.ArtifactDefs")
local ArtifactSchema = require("shared.artifact.ArtifactSchema")

local TowerService = {}
---@type table<number, table>
local runs = {}
---@type table<number, table>
local sweeps = {}
-- 退出整理背包后可重挑本组，但同一未提交楼层的开奖不能被替换。
---@type table<number, table>
local pendingRewards = {}
local runSerial = 0

local function setOfflineTowerSource(uid, floor)
    for teamIdx = 1, ExpTable.TEAM_COUNT do
        DungeonService.SetOfflineChallengeSource(uid, teamIdx, {
            sourceKind = "tower", stageId = 400000 + floor, resourceFloor = floor,
            paused = true, sourceName = "通天塔 第" .. floor .. "层",
        })
    end
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function getTodayNum()
    return math.floor((os.time() + 28800) / 86400)
end

local function ensureBT(dungeon, uid)
    if not dungeon.babel_tower then
        dungeon.babel_tower = { floor = 1, cleared = {}, dailyUsed = 0, dailyDay = 0, buffs = {} }
        PDM.MarkDirty(uid, "dungeon")
    end
    return dungeon.babel_tower
end

local function checkTeamUnlocks(uid)
    if ExpTable.getUnlockedTeamCount(PDM.GetModule(uid, "battle")) < ExpTable.TEAM_COUNT then
        return false, "三军攻坚需三队解锁（" .. ExpTable.getTeamUnlockText(3) .. "队伍3）"
    end
    return true, nil
end

local function validFloor(floor)
    return type(floor) == "number" and floor == math.floor(floor)
        and floor >= 1 and floor <= TowerConfig.MAX_FLOOR
end

local function matchesRun(run, request)
    return type(request) ~= "table" or request.runId == nil or request.runId == run.id
end

-- 退出/失败只清本局；清档使用 ResetToDefault，不能把旧成功回执带进新档。
-- 未提交奖品独立保留，退出整理后重挑同组仍复用原楼层开奖。
function TowerService.Cleanup(uid, runId)
    local run = runs[uid]
    if not run or (runId ~= nil and run.id ~= runId) then return false end
    run.pendingSelections, run.selections, run.requests = {}, {}, {}
    run.bt.buffs = {}
    runs[uid] = nil
    DungeonService.ClearOfflineChallengeSources(uid, "tower")
    DungeonService.PersistOfflineChallengeSources(uid)
    PDM.MarkDirty(uid, "dungeon")
    return true
end

function TowerService.ResetToDefault(uid)
    if uid == nil then
        for key in pairs(runs) do
            DungeonService.ClearOfflineChallengeSources(key, "tower")
            runs[key] = nil
        end
        for key in pairs(sweeps) do sweeps[key] = nil end
        for key in pairs(pendingRewards) do pendingRewards[key] = nil end
    else
        if runs[uid] then DungeonService.ClearOfflineChallengeSources(uid, "tower") end
        runs[uid], sweeps[uid], pendingRewards[uid] = nil, nil, nil
    end
end

--- 挑战已解锁组起点；默认取旧 bt.floor 所在组，不改写历史进度。
function TowerService.Challenge(uid, requestedFloor)
    local unlocked, unlockErr = checkTeamUnlocks(uid)
    if not unlocked then return false, unlockErr end
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then return false, "数据未加载" end
    local bt = ensureBT(dungeon, uid)
    local previous = runs[uid]
    if previous and previous.bt == bt and previous.rewardPlan then
        return false, "上一层奖励尚未提交，请重试结算"
    end
    local floor = requestedFloor
    if floor == nil then floor = TowerConfig.getCheckpointFloor(tonumber(bt.floor) or 1) end
    if not validFloor(floor) then return false, "无效的层数" end
    if not TowerConfig.isCheckpointFloor(floor) then return false, "只能从五层组起点挑战" end
    if floor > TowerConfig.getMaxUnlockedCheckpoint(bt) then return false, "层数未解锁" end
    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then return false, "层配置不存在" end
    local monsters = TowerConfig.generateWaveMonsters(1, floor)
    bt.buffs = {}
    runSerial = runSerial + 1
    local run = { id = tostring(uid) .. ":" .. runSerial, bt = bt, floor = floor,
        startFloor = floor, endFloor = TowerConfig.getRunEndFloor(floor), wave = 1,
        phase = "battle", selections = {}, waveResults = {}, floorResults = {},
        requests = {}, pendingSelections = {} }
    runs[uid] = run
    setOfflineTowerSource(uid, floor)
    PDM.MarkDirty(uid, "dungeon")
    DungeonService.PersistOfflineChallengeSources(uid)
    print(string.format("[TowerService] Challenge run=%s floors=%d-%d", run.id, floor, run.endFloor))
    return true, nil, { success = true, floor = floor, wave = 1, runId = run.id,
        startFloor = run.startFloor, endFloor = run.endFloor,
        monsterLevel = floorCfg.monsterLevel, monsters = monsters,
        rageTime = TowerConfig.RAGE_TIME, superRageTime = TowerConfig.SUPER_RAGE_TIME,
        buffs = copy(bt.buffs), battleBg = TowerConfig.BATTLE_BG }
end

--- WaveWin 只消费单波，不发奖、不提前开下一层。
function TowerService.WaveWin(uid, floor, wave, request)
    local unlocked, unlockErr = checkTeamUnlocks(uid)
    if not unlocked then return false, unlockErr end
    if not validFloor(floor) then return false, "无效的层数" end
    if wave ~= 1 then return false, "无效的波次" end
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then return false, "数据未加载" end
    local bt = ensureBT(dungeon, uid)
    local run = runs[uid]
    if not run or run.bt ~= bt or not matchesRun(run, request) then return false, "挑战已过期" end
    if run.waveResults[floor] then return true, nil, copy(run.waveResults[floor]) end
    if run.floor ~= floor or run.phase ~= "battle" then return false, "层数不匹配" end
    local result = { success = true, runId = run.id, floor = floor, wave = 1, floorCleared = true }
    run.waveResults[floor] = result
    run.phase = "floor_win"
    print(string.format("[TowerService] WaveWin run=%s floor=%d → floor_win", run.id, floor))
    return true, nil, copy(result)
end

-- 每层经验旧值 /10：首通2分钟、重打1分钟；扫荡保留原10分钟。
local function grantTowerExp(uid, monsterLevel, isFirstClear, minutes)
    local StageExpHelper = require("config.StageExpHelper")
    local heroes = PDM.GetModule(uid, "heroes")
    local playerData = PDM.GetModule(uid, "player")
    if type(heroes) ~= "table" or type(playerData) ~= "table" then return 0, 0 end
    local expPerMin = StageExpHelper.getExpPerMin(monsterLevel)
    if expPerMin <= 0 then return 0, 0 end
    local mins = minutes or (isFirstClear and TowerConfig.FIRST_EXP_MINUTES or TowerConfig.REPEAT_EXP_MINUTES)
    local playerExp = math.floor(expPerMin * mins)
    if playerExp <= 0 then return 0, 0 end
    local deployed, seen = {}, {}
    for team = 1, ExpTable.TEAM_COUNT do
        local slots = type(heroes.teams) == "table" and heroes.teams[team]
            and heroes.teams[team].slots or nil
        if type(slots) == "table" then
            for _, heroId in ipairs(slots) do
                local id = math.tointeger(tonumber(heroId) or 0)
                if id and id > 0 and not seen[id] then
                    seen[id] = true
                    deployed[#deployed + 1] = id
                end
            end
        end
    end
    if #deployed == 0 and type(heroes.deployed) == "table" then
        for _, heroId in ipairs(heroes.deployed) do
            local id = math.tointeger(tonumber(heroId) or 0)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                deployed[#deployed + 1] = id
            end
        end
    end
    local heroExpTotal = 0
    if #deployed > 0 then
        heroExpTotal = math.floor(playerExp * ExpTable.getHeroCountExpMult(#deployed))
        local perHero = math.floor(heroExpTotal / #deployed + 0.5)
        if perHero > 0 then
            local roster = heroes.roster
            for _, heroId in ipairs(deployed) do
                local heroData = type(roster) == "table" and (roster[heroId] or roster[tostring(heroId)])
                if type(heroData) == "table" then
                    heroData.exp = (heroData.exp or 0) + perHero
                    ExpTable.autoLevelUpHero(heroData)
                end
            end
            DungeonService.MarkRewardDirty(uid, "heroes")
        end
    end
    playerData.exp = (playerData.exp or 0) + playerExp
    ExpTable.autoLevelUpPlayer(playerData)
    DungeonService.MarkRewardDirty(uid, "player")
    return playerExp, heroExpTotal
end

-- 非抽卡免费掉落：绝不调用 ArtifactService.Draw/任务/保底计数。
-- 连未命中也缓存，写档失败不能重新随机；实例ID交付时从当前nextId分配。
local function rollArtifact()
    if math.random() >= TowerConfig.ARTIFACT_DROP_RATE then return false end
    local weights = TowerConfig.ARTIFACT_QUALITY_WEIGHTS
    local total = weights[1] + weights[2] + weights[3]
    local rolled = math.random() * total
    local quality = rolled < weights[1] and 1 or (rolled < weights[1] + weights[2] and 2 or 3)
    local artifactId = ArtifactDefs.rollArtifactId(quality)
    if not artifactId then error("通天塔神器定义不存在") end
    local artifact = { artifactId = artifactId, quality = quality, valueRatio = ArtifactDefs.rollValueRatio() }
    local threatClearRatio = ArtifactDefs.rollThreatClearValueRatio(artifactId, quality)
    if threatClearRatio ~= nil then artifact.threatClearRatio = threatClearRatio end
    ArtifactDefs.normalizeInstanceValue(artifact)
    return artifact
end

local function grantArtifact(uid, rolled)
    if rolled == false then return true, nil, nil end
    local data = PDM.GetModule(uid, "artifacts")
    if type(data) ~= "table" then return false, "神器数据未加载，可重试结算" end
    -- 规范化在事务内，旧bag别名/nextId会跟其他奖励一起回滚。
    ArtifactSchema.normalizeModule(data)
    if #data.bag >= ArtifactDefs.MAX_BAG then return false, "神器背包已满，请整理后重试结算" end
    local nextId = data.nextId
    for _, existing in ipairs(data.bag) do
        nextId = math.max(nextId, (tonumber(existing.id) or 0) + 1)
    end
    local artifact = copy(rolled)
    artifact.id = tostring(nextId)
    data.nextId = nextId + 1
    data.bag[#data.bag + 1] = artifact
    DungeonService.MarkRewardDirty(uid, "artifacts")
    return true, nil, artifact
end

local function artifactReward(artifact)
    -- 与ArtifactAssetUtil.getIconPath一致，只构建展示数据，不引入绘图库。
    return { type = "artifact", amount = 1, artifact = copy(artifact),
        artifactId = artifact.artifactId, quality = artifact.quality,
        name = ArtifactDefs.getName(artifact),
        iconPath = "image/神器图标/UI_icon_SQ_A" .. artifact.artifactId .. ".png" }
end

local function buildFloorPlan(uid, run, floorCfg)
    local floor = run.floor
    local cache = pendingRewards[uid]
    if not cache or cache.bt ~= run.bt then
        cache = { bt = run.bt, floors = {} }
        pendingRewards[uid] = cache
    end
    local prize = cache.floors[floor]
    if not prize then
        local cleared = run.bt.cleared or {}
        local oldFloor = tonumber(run.bt.floor) or 1
        local firstClear = not (oldFloor > floor or cleared[floor] or cleared[tostring(floor)])
        prize = { firstClear = firstClear,
            diamondReward = firstClear and (floorCfg.firstDiamond or 0) or 0, artifact = false }
        -- 命中/不命中均先缓存；重挑可重建run身份，但绝不重抽本层奖品。
        cache.floors[floor] = prize
        local called, rolled = pcall(rollArtifact)
        if called then prize.artifact = rolled
        else prize.error = "通天塔奖励生成失败，请联系反馈"; print("[TowerService] roll failed " .. tostring(rolled)) end
    end
    local plan = { floor = floor, firstClear = prize.firstClear, diamondReward = prize.diamondReward,
        artifact = copy(prize.artifact), continueRun = floor < run.endFloor, error = prize.error }
    run.rewardPlan = plan
    local called, err = pcall(function()
        if plan.continueRun then
            plan.monsters = TowerConfig.generateWaveMonsters(1, floor + 1)
            plan.monsterLevel = assert(TowerConfig.getFloor(floor + 1)).monsterLevel
            plan.buffChoices = {}
            for _, buff in ipairs(TowerConfig.rollBuffs(3, run.bt.buffs)) do
                plan.buffChoices[#plan.buffChoices + 1] = {
                    id = buff.id, quality = buff.quality, name = buff.name, desc = buff.desc }
            end
            plan.selectionId = run.id .. ":floor:" .. floor
        end
    end)
    if not called then plan.error = "通天塔续层生成失败，请联系反馈"; print("[TowerService] continuation failed " .. tostring(err)) end
    return plan
end

--- 逐层首通/经验/神器/进度一起落盘，成功后才消费楼层并开放下一层。
function TowerService.FloorWin(uid, floor, request)
    local unlocked, unlockErr = checkTeamUnlocks(uid)
    if not unlocked then return false, unlockErr end
    if not validFloor(floor) then return false, "无效的层数" end
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon or not PDM.GetModule(uid, "currency") then return false, "数据未加载" end
    local bt = ensureBT(dungeon, uid)
    local run = runs[uid]
    if not run or run.bt ~= bt or not matchesRun(run, request) then return false, "挑战已过期" end
    if run.floorResults[floor] then return true, nil, copy(run.floorResults[floor]) end
    if run.floor ~= floor or run.phase ~= "floor_win" or not run.waveResults[floor] then
        return false, "本层尚未通关"
    end
    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then return false, "层配置不存在" end
    run.phase = "settling"
    local plan = run.rewardPlan or buildFloorPlan(uid, run, floorCfg)
    if plan.error then run.phase = "floor_win"; return false, plan.error end
    local result = {}
    local ok, err = DungeonService.CommitRewardTransaction(uid, function()
        local granted, grantErr, artifact = grantArtifact(uid, plan.artifact)
        if not granted then return false, grantErr end
        if plan.diamondReward > 0
            and not DungeonService.GrantIdleCurrency(uid, "diamond", plan.diamondReward) then
            return false, "首通黑钻发放失败，可重试结算"
        end
        bt.cleared = bt.cleared or {}
        bt.cleared[floor] = true
        -- 不删除其他历史键，也不因为重打倒退旧floor。
        bt.floor = math.max(tonumber(bt.floor) or 1, math.min(floor + 1, TowerConfig.MAX_FLOOR + 1))
        if not plan.continueRun or run.abandoned then bt.buffs = {} end
        DungeonService.MarkRewardDirty(uid, "dungeon")
        local playerExp, heroExpTotal = grantTowerExp(uid, floorCfg.monsterLevel, plan.firstClear)
        local rewards = {}
        if plan.diamondReward > 0 then rewards[#rewards + 1] = { type = "diamond", amount = plan.diamondReward } end
        if artifact then rewards[#rewards + 1] = artifactReward(artifact) end
        result = { success = true, runId = run.id, floor = floor, wave = 1,
            firstClear = plan.firstClear, diamondReward = plan.diamondReward,
            playerExp = playerExp, heroExpTotal = heroExpTotal, rewards = rewards,
            artifacts = artifact and { copy(artifact) } or {},
            continueRun = plan.continueRun and not run.abandoned,
            nextFloor = plan.continueRun and not run.abandoned and floor + 1 or bt.floor,
            progressFloor = bt.floor, startFloor = run.startFloor, endFloor = run.endFloor,
            buffs = copy(bt.buffs), selectionId = plan.selectionId,
            buffChoices = copy(plan.buffChoices), monsters = copy(plan.monsters), monsterLevel = plan.monsterLevel }
        if result.continueRun then setOfflineTowerSource(uid, floor + 1)
        else DungeonService.ClearOfflineChallengeSources(uid, "tower") end
        return true, nil, result
    end, function()
        -- 通知可同步重入：必须在MarkDirty/finish前建立按floor回执并消费开奖。
        run.floorResults[floor] = copy(result)
        pendingRewards[uid].floors[floor] = nil
        run.rewardPlan = nil
        if result.continueRun then
            if plan.selectionId and #plan.buffChoices > 0 then
                run.pendingSelections[#run.pendingSelections + 1] = {
                    id = plan.selectionId, floor = floor, wave = 1, result = copy(result) }
            end
            run.floor, run.wave, run.phase = floor + 1, 1, "battle"
        else
            run.phase = "settled"
            run.pendingSelections, run.selections, run.requests = {}, {}, {}
        end
    end)
    if not ok then
        run.phase = "floor_win"
        print(string.format("[TowerService] FloorWin retry run=%s floor=%d reason=%s", run.id, floor, tostring(err)))
        return false, err
    end
    print(string.format("[TowerService] FloorWin committed run=%s floor=%d diamond=%d continue=%s",
        run.id, floor, result.diamondReward, tostring(result.continueRun)))
    return true, nil, copy(run.floorResults[floor])
end

--- FIFO身份是生成选择的已清层，不是run.floor；接受迟到与幂等重试。
function TowerService.PickBuff(uid, buffId, request)
    local unlocked, unlockErr = checkTeamUnlocks(uid)
    if not unlocked then return false, unlockErr end
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon then return false, "数据未加载" end
    local bt = ensureBT(dungeon, uid)
    local buff = TowerConfig.BUFFS_BY_ID[buffId]
    if not buff then return false, "无效的强化ID" end
    local run = runs[uid]
    if not run or run.bt ~= bt then return false, "挑战未开始" end
    request = request or {}
    if not matchesRun(run, request) then return false, "挑战已过期" end
    if run.phase ~= "battle" and run.phase ~= "floor_win" then return false, "强化选择已过期" end
    local pending = run.pendingSelections[1]
    local selectionId = request.selectionId or (pending and pending.id)
    local requestId = request.requestId
    local previous = requestId and run.requests[requestId]
    if previous and (previous.selectionId ~= selectionId or previous.buffId ~= buffId
        or (request.wave ~= nil and request.wave ~= previous.wave)
        or (request.floor ~= nil and request.floor ~= previous.floor)) then return false, "请求编号已使用" end
    local accepted = selectionId and run.selections[selectionId]
    if accepted then
        if accepted.buffId ~= buffId or (request.wave ~= nil and request.wave ~= accepted.wave)
            or (request.floor ~= nil and request.floor ~= accepted.floor) then return false, "本次强化已选择" end
        if requestId then run.requests[requestId] = accepted end
        local result = copy(accepted)
        result.requestId = requestId
        return true, nil, result
    end
    if not pending or selectionId ~= pending.id
        or (request.wave ~= nil and request.wave ~= pending.wave)
        or (request.floor ~= nil and request.floor ~= pending.floor) then return false, "强化选择已过期" end
    local offered = false
    for _, choice in ipairs(pending.result.buffChoices) do
        if choice.id == buffId then offered = true; break end
    end
    if not offered then return false, "强化不在本次选项中" end
    bt.buffs[#bt.buffs + 1] = buffId
    local result = { success = true, runId = run.id, selectionId = selectionId,
        floor = pending.floor, wave = pending.wave, nextWave = 1,
        nextFloor = pending.result.nextFloor, buffId = buffId, buffName = buff.name,
        totalBuffs = #bt.buffs, buffs = copy(bt.buffs) }
    run.selections[selectionId] = result
    if requestId then run.requests[requestId] = result end
    table.remove(run.pendingSelections, 1)
    PDM.MarkDirty(uid, "dungeon")
    print(string.format("[TowerService] PickBuff run=%s sourceFloor=%d currentFloor=%d buff=%d",
        run.id, pending.floor, run.floor, buffId))
    local receipt = copy(result)
    receipt.requestId = requestId
    return true, nil, receipt
end

--- 扫荡原经验+独立神器概率，无黑钻；日次与奖励同一事务，失败固定开奖。
function TowerService.Sweep(uid)
    local dungeon = PDM.GetModule(uid, "dungeon")
    if not dungeon or not PDM.GetModule(uid, "currency") then return false, "数据未加载" end
    local bt = ensureBT(dungeon, uid)
    local today = getTodayNum()
    local used = bt.dailyDay == today and (tonumber(bt.dailyUsed) or 0) or 0
    if used >= TowerConfig.DAILY_SWEEP_LIMIT then return false, "今日扫荡次数已用完" end
    local floor = TowerConfig.getHighestClearedFloor(bt)
    if floor < 1 then return false, "至少通关1层后才能扫荡" end
    local floorCfg = TowerConfig.getFloor(floor)
    if not floorCfg then return false, "扫荡层配置不存在" end
    local plan = sweeps[uid]
    if plan and (plan.bt ~= bt or plan.day ~= today or plan.used ~= used) then plan = nil end
    if not plan then
        plan = { bt = bt, day = today, used = used, floor = floor, artifact = false }
        sweeps[uid] = plan
        local called, rolled = pcall(rollArtifact)
        if not called then plan.error = "通天塔奖励生成失败，请联系反馈"
        else plan.artifact = rolled end
    end
    if plan.error then return false, plan.error end
    floor, floorCfg = plan.floor, TowerConfig.getFloor(plan.floor)
    local result = {}
    local ok, err = DungeonService.CommitRewardTransaction(uid, function()
        local granted, grantErr, artifact = grantArtifact(uid, plan.artifact)
        if not granted then return false, grantErr end
        bt.dailyUsed, bt.dailyDay = used + 1, today
        DungeonService.MarkRewardDirty(uid, "dungeon")
        local playerExp, heroExpTotal = grantTowerExp(uid, floorCfg.monsterLevel, false, 10)
        result = { success = true, sweepFloor = floor, diamondReward = 0,
            playerExp = playerExp, heroExpTotal = heroExpTotal,
            artifacts = artifact and { copy(artifact) } or {}, rewards = {},
            dailyUsed = bt.dailyUsed, dailyMax = TowerConfig.DAILY_SWEEP_LIMIT }
        if artifact then result.rewards[1] = artifactReward(artifact) end
        return true, nil, result
    end, function() sweeps[uid] = nil end)
    if not ok then return false, err end
    print(string.format("[TowerService] Sweep committed uid=%s floor=%d used=%d diamond=0", tostring(uid), floor, result.dailyUsed))
    return true, nil, copy(result)
end

return TowerService
