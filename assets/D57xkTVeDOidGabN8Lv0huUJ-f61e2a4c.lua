-- ============================================================================
-- HeroService - 英雄管理业务逻辑
-- 职责: 英雄上阵/下阵、升级、初始选择、头像设置
-- 层级: server/hero  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local SaveManager     = require("server.SaveManager")
local CurrencyService = require("server.currency.CurrencyService")
local ExpTable        = require("config.ExpTable")
local HeroConfig        = require("config.HeroConfig")
local AvatarFrameConfig = require("config.AvatarFrameConfig")
local UrGachaConfig   = require("config.UrGachaConfig")
local TaskService     = require("server.task.TaskService")
local HeroResonance   = require("shared.heroes.HeroResonance")
local TeamSlots       = require("shared.heroes.TeamSlots")

local HeroService = {}

local UR_SHARD_CONVERT_DAILY_LIMIT = 30
local UR_SHARD_CONVERT_RESTORE_COST = 2

local function getTodayDayId()
    return math.floor((os.time() + 28800) / 86400)
end

local function resetUrShardConvertDailyIfNeeded(heroes)
    local today = getTodayDayId()
    heroes.urShardConvertDayId = math.floor(tonumber(heroes.urShardConvertDayId) or 0)
    heroes.urShardConvertCount = math.max(0, math.floor(tonumber(heroes.urShardConvertCount) or 0))
    if heroes.urShardConvertDayId ~= today then
        heroes.urShardConvertDayId = today
        heroes.urShardConvertCount = 0
    end
    return today, heroes.urShardConvertCount
end

local function isUrHero(heroId)
    local cfg = HeroConfig.get(heroId)
    return cfg and tonumber(cfg.quality) == HeroConfig.QUALITY_UR
end

local function getServerDictValue(t, serverId)
    if type(t) ~= "table" then return nil end
    return t[tostring(serverId)] or t[serverId]
end

local function hasRealServerProgress(progress)
    if type(progress) ~= "table" then return false end
    local level = tonumber(progress.level or 0) or 0
    local stage = progress.stage or ""
    return level > 1 or stage ~= ""
end

-- ======================== 上阵 / 下阵 / 批量设置 ========================

--- 上阵英雄（队1；保持旧接口语义，供 HeroHandler DEPLOY_HERO 使用）
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err
function HeroService.DeployHero(uid, heroId)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "缺少 heroId" end

    if not heroes.roster[heroId] then
        return false, "未拥有该英雄"
    end

    TeamSlots.normalize(heroes)

    for _, id in ipairs(heroes.deployed) do
        if id == heroId then
            return false, "英雄已在阵容中"
        end
    end

    -- 跨队唯一性: 该英雄已在队2/3 → 拒绝
    local otherTeam = TeamSlots.findHeroTeam(heroes, heroId)
    if otherTeam then
        return false, "英雄已在队伍" .. otherTeam .. "中"
    end

    if #heroes.deployed >= ExpTable.TEAM_MAX_SLOTS then
        return false, "每队最多上阵 " .. ExpTable.TEAM_MAX_SLOTS .. " 人"
    end

    heroes.deployed[#heroes.deployed + 1] = heroId
    TeamSlots.setTeam(heroes, 1, heroes.deployed)
    PDM.MarkDirty(uid, "heroes")
    return true
end

--- 下阵英雄（队1）
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err
function HeroService.UndeployHero(uid, heroId)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "缺少 heroId" end

    -- 阵容不能为空：至少保留1个英雄
    if #heroes.deployed <= 1 then
        return false, "阵容至少需要1个英雄"
    end

    local found = false
    for i = #heroes.deployed, 1, -1 do
        if heroes.deployed[i] == heroId then
            table.remove(heroes.deployed, i)
            found = true
            break
        end
    end

    if not found then
        return false, "英雄不在阵容中"
    end

    TeamSlots.setTeam(heroes, 1, heroes.deployed)
    PDM.MarkDirty(uid, "heroes")
    return true
end

--- 批量设置指定队伍的出战阵容
--- 队1 = 旧 SET_DEPLOYED 语义（不允许为空，写 deployed 镜像）
--- 队2/3 = 三队并行编队（允许为空 = 清空该队）
---@param uid number
---@param teamIdx number 队伍索引 1~3
---@param heroIds table|nil
---@return boolean ok, string? err, table? result
function HeroService.SetTeam(uid, teamIdx, heroIds)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end

    local player = PDM.GetModule(uid, "player")
    local playerLevel = player and (player.level or 1) or 1

    local ok, err = TeamSlots.validate(heroes, teamIdx, heroIds, playerLevel)
    if not ok then return false, err end

    local slots = TeamSlots.setTeam(heroes, teamIdx, heroIds or {})
    PDM.MarkDirty(uid, "heroes")
    print(string.format("[HeroService] SET_TEAM uid=%s team=%d slots=%s",
        tostring(uid), teamIdx, table.concat(slots, ",")))
    return true, nil, { teamIdx = teamIdx, slots = slots, deployed = heroes.deployed }
end

--- 批量设置出战阵容（队1，兼容旧协议 SET_DEPLOYED）
---@param uid number
---@param heroIds table|nil
---@return boolean ok, string? err, table? result
function HeroService.SetDeployed(uid, heroIds)
    local ok, err, result = HeroService.SetTeam(uid, 1, heroIds)
    if not ok then return false, err end
    return true, nil, { deployed = result.deployed }
end

-- ======================== 英雄升级 ========================

--- 英雄升级（消耗金币）
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err, table? result
function HeroService.LevelUpHero(uid, heroId)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "缺少 heroId" end

    local hero = heroes.roster[heroId]
    if not hero then return false, "未拥有该英雄" end

    local currentLevel = hero.level or 1
    if ExpTable.isHeroMaxLevel(currentLevel) then
        return false, "已满级"
    end

    local needed = ExpTable.getHeroExpForLevel(currentLevel)
    if not needed then return false, "经验表配置错误" end

    -- 计算升级费用
    local heroCfg = HeroConfig.get(heroId)
    local rarity = heroCfg and heroCfg.rarity or 1
    local baseCost = 50 + (rarity - 1) * 20
    local goldCost = math.floor(baseCost * (1 + currentLevel * 0.15))

    -- 检查并扣除金币
    local canPay = CurrencyService.CheckBalance(uid, "gold", goldCost)
    if not canPay then
        return false, "金币不足（需要 " .. goldCost .. "）"
    end

    -- === 快照（回滚用） ===
    local oldLevel = currentLevel
    local oldExp   = hero.exp or 0

    -- === 原子修改 ===
    local deductOk = CurrencyService.Deduct(uid, "gold", goldCost)
    if not deductOk then
        return false, "金币扣除失败"
    end

    hero.exp = (hero.exp or 0) + needed
    ExpTable.autoLevelUpHero(hero)
    HeroService.ApplyResonanceSync(uid)
    PDM.MarkDirty(uid, "heroes")

    local newLevel = hero.level or 1
    print("[HeroService] LEVEL_UP uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " Lv" .. oldLevel .. " → Lv" .. newLevel
        .. " gold -" .. goldCost)

    -- 任务进度：刷新等级成就
    TaskService.RefreshAchievements(uid)

    return true, nil, {
        heroId   = heroId,
        newLevel = hero.level,
        goldCost = goldCost,
    }
end

-- ======================== 初始英雄选择 ========================

--- 新玩家选择初始英雄（替换默认大狗嚼）
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err, table? result
function HeroService.SelectInitialHero(uid, heroId)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "缺少 heroId" end

    -- 🔍 [DIAG] SelectInitialHero 入口诊断
    do
        local rosterDiag = "nil"
        local rc = 0
        if heroes and heroes.roster then
            for hid, _ in pairs(heroes.roster) do
                rc = rc + 1
                if rc <= 5 then
                    rosterDiag = (rosterDiag == "nil" and "" or rosterDiag .. ",") .. tostring(hid)
                end
            end
            rosterDiag = string.format("{count=%d,ids=[%s]}", rc, rosterDiag == "nil" and "" or rosterDiag)
        end
        local gp = PDM.GetModule(uid, "global_profile")
        local sid = SaveManager.getServerId(uid)
        local spDiag = "N/A"
        if gp and gp.serverProgress and sid then
            local sp = getServerDictValue(gp.serverProgress, sid)
            if sp then
                spDiag = string.format("{level=%s,stage=%s}", tostring(sp.level), tostring(sp.stage or ""))
            else
                spDiag = "NIL_FOR_KEY_" .. tostring(sid)
            end
        end
        local playerMod = PDM.GetModule(uid, "player")
        local playerLevel = playerMod and tostring(playerMod.level) or "nil"
        print(string.format(
            "[HeroService][DIAG-INIT] SelectInitialHero CALLED uid=%s heroId=%s serverId=%s " ..
            "roster=%s serverProgress=%s player.level=%s",
            tostring(uid), tostring(heroId), tostring(sid),
            rosterDiag, spDiag, playerLevel))
    end

    -- 仅限初始三选一的英雄 ID
    if heroId ~= 1 and heroId ~= 2 and heroId ~= 3 then
        return false, "无效的初始英雄 ID: " .. tostring(heroId)
    end

    -- 防止重复选择：roster 已有英雄说明不是新玩家
    local rosterCount = 0
    for _ in pairs(heroes.roster) do
        rosterCount = rosterCount + 1
    end
    if rosterCount > 1 then
        return false, "已非新玩家状态，无法选择初始英雄"
    end

    -- 🔴 防丢档二重校验：即使 roster 为空（可能因数据丢失），
    -- 如果 serverProgress 表明该玩家有区服进度，则阻止选初始英雄
    -- （防止丢档后客户端进入新手流程，覆盖 roster 为仅 1 级英雄）
    -- 铁律 #18 强化：不仅检查 level > 1，还检查 stage 非空（防止 level 被降级覆盖为 1 的情况）
    local gp = PDM.GetModule(uid, "global_profile")
    local serverId = SaveManager.getServerId(uid)
    if gp and gp.serverProgress and serverId then
        local sp = getServerDictValue(gp.serverProgress, serverId)
        if sp then
            if hasRealServerProgress(sp) then
                print(string.format(
                    "[HeroService][CRITICAL] SelectInitialHero BLOCKED — roster empty but serverProgress exists " ..
                    "uid=%s serverId=%s progressLevel=%s stage=%s. Possible data loss detected!",
                    tostring(uid), tostring(serverId), tostring(sp.level), tostring(sp.stage)))
                return false, "存档异常，请联系客服"
            end
        end
    end

    -- 🔴 铁律 #18 增强：gp.servers 辅助检测（防 serverProgress 自毁死循环）
    -- 即使 serverProgress.level=1（被降级），gp.servers[serverId] 仍能证明玩家曾使用过此区服
    -- 🔴 修复：仅当 spEntry 有实质进度时才触发阻断（level>1 OR stage 非空）
    -- 清档后 updateServerProgress 会写入 {level=1, stage=""}，这是合法新玩家状态，不应阻断
    if gp and gp.servers and serverId then
        local hasCreatedOnThisServer = getServerDictValue(gp.servers, serverId)
        if hasCreatedOnThisServer then
            local spEntry = gp.serverProgress and getServerDictValue(gp.serverProgress, serverId)
            if spEntry and rosterCount == 0 then
                -- 验证 spEntry 是否包含有意义的游戏进度（与一级安全网一致的判定标准）
                if hasRealServerProgress(spEntry) then
                    print(string.format(
                        "[HeroService][CRITICAL] SelectInitialHero BLOCKED (SECONDARY) — " ..
                        "gp.servers[%s]=true, serverProgress has real progress (level=%s stage=%s) " ..
                        "but roster is empty. Self-destruct scenario detected! uid=%s",
                        tostring(serverId), tostring(spEntry.level), tostring(spEntry.stage or ""),
                        tostring(uid)))
                    return false, "存档异常，请联系客服"
                else
                    print(string.format(
                        "[HeroService] SelectInitialHero SECONDARY check PASSED — " ..
                        "gp.servers[%s]=true but spEntry has no real progress (level=%s stage=%s). " ..
                        "Treating as legitimate new/reset player. uid=%s",
                        tostring(serverId), tostring(spEntry.level), tostring(spEntry.stage or ""),
                        tostring(uid)))
                end
            end
        end
    end

    -- 替换 roster：只保留选中的英雄（起始等级 = 冒险等级）
    local cfg = HeroConfig.get(heroId)
    local startLv = HeroService.GetNewHeroStartLevel(uid)
    heroes.roster = {
        [heroId] = {
            level = startLv, exp = 0,
            maxExp = ExpTable.getHeroExpForLevel(startLv) or 0,
            classId = cfg and cfg.classId or 1,
            dupeCount = 0,
            shards = 0,
            awakening = {},
            _shardMigrated = true,
        },
    }
    heroes.deployed = { heroId }
    TeamSlots.setTeam(heroes, 1, heroes.deployed)
    PDM.MarkDirty(uid, "heroes")

    -- 同步设置头像
    local player = PDM.GetModule(uid, "player")
    if player then
        player.avatarHeroId = heroId
        PDM.MarkDirty(uid, "player")
    end

    -- 标记开场剧情已完成 + 保存初始英雄 ID
    local sessionData = PDM.GetModule(uid, "session")
    if sessionData then
        if not sessionData.introCompleted then
            sessionData.introCompleted = true
        end
        sessionData.initialHeroId = heroId
        PDM.MarkDirty(uid, "session")
    end

    print("[HeroService] SELECT_INITIAL uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId) .. " avatar+introCompleted set")

    PDM.FlushImmediate(uid)

    return true, nil, { heroId = heroId }
end

-- ======================== 头像设置 ========================

--- 设置头像
---@param uid number
---@param avatarHeroId number|nil
---@return boolean ok, string? err, table? result
function HeroService.SetAvatar(uid, avatarHeroId)
    local player = PDM.GetModule(uid, "player")
    if not player then return false, "数据未加载" end

    avatarHeroId = tonumber(avatarHeroId)
    if not HeroConfig.get(avatarHeroId) then
        return false, "无效的头像 ID"
    end

    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes or not heroes.roster or not heroes.roster[avatarHeroId] then
        return false, "未拥有该英雄，无法设为头像"
    end

    player.avatarHeroId = avatarHeroId
    PDM.MarkDirty(uid, "player")

    print("[HeroService] SET_AVATAR uid=" .. tostring(uid)
        .. " avatarHeroId=" .. tostring(avatarHeroId))

    return true, nil, { avatarHeroId = avatarHeroId }
end

--- 设置头像框
---@param uid number
---@param avatarFrameId number|nil
---@return boolean ok, string? err, table? result
function HeroService.SetAvatarFrame(uid, avatarFrameId)
    local player = PDM.GetModule(uid, "player")
    if not player then return false, "数据未加载" end

    avatarFrameId = tonumber(avatarFrameId)
    if not AvatarFrameConfig.get(avatarFrameId) then
        return false, "无效的头像框 ID"
    end

    local challenger = PDM.GetModule(uid, "challenger")
    local unlockedFrames = challenger and challenger.unlockedAvatarFrames
    if not AvatarFrameConfig.isUnlocked(avatarFrameId, unlockedFrames) then
        return false, "尚未解锁该头像框"
    end

    player.avatarFrameId = avatarFrameId
    PDM.MarkDirty(uid, "player")

    print("[HeroService] SET_AVATAR_FRAME uid=" .. tostring(uid)
        .. " avatarFrameId=" .. tostring(avatarFrameId))

    return true, nil, { avatarFrameId = avatarFrameId }
end

-- ======================== 碎片合成英雄 ========================

--- 消耗碎片合成（解锁）未拥有的英雄
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err, table? result
function HeroService.SynthesizeHero(uid, heroId)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "缺少 heroId" end

    local cfg = HeroConfig.get(heroId)
    if not cfg then return false, "无效的英雄 ID: " .. tostring(heroId) end

    local roster = heroes.roster[heroId]

    -- 已拥有（有 level 字段 = 已解锁）
    if roster and roster.level then
        return false, "已拥有该英雄，无需合成"
    end

    -- 检查碎片是否足够
    local currentShards = roster and roster.shards or 0
    local cost = HeroConfig.SHARD_SYNTHESIZE_COST
    if currentShards < cost then
        return false, "碎片不足（需要 " .. cost .. " 个，当前 " .. currentShards .. " 个）"
    end

    -- === 原子修改 ===
    if not roster then
        heroes.roster[heroId] = {
            shards = currentShards,
            _shardMigrated = true,
        }
        roster = heroes.roster[heroId]
    end

    roster.shards = currentShards - cost
    local startLv = HeroService.GetNewHeroStartLevel(uid)
    roster.level = startLv
    roster.exp = 0
    roster.maxExp = ExpTable.getHeroExpForLevel(startLv) or 0
    roster.classId = cfg.classId or 1
    roster.dupeCount = 0
    if not roster.awakening then
        roster.awakening = {}
    end

    PDM.MarkDirty(uid, "heroes")

    HeroService.ApplyResonanceSync(uid)

    print("[HeroService] SYNTHESIZE uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " shards " .. currentShards .. " → " .. roster.shards)

    return true, nil, {
        heroId = heroId,
        remainingShards = roster.shards,
    }
end

-- ======================== 满觉醒碎片转酒馆币 ========================

--- 获取英雄单枚碎片对应的酒馆币转化数量
---@param heroId number
---@return number
local function getStardustValue(heroId)
    return UrGachaConfig.getShardStardustValue(heroId)
end

--- 消耗1个满觉醒英雄的碎片，转化为酒馆币
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err, table? result
function HeroService.ConvertShardToCoin(uid, heroId)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "缺少 heroId" end

    local cfg = HeroConfig.get(heroId)
    if not cfg then return false, "无效的英雄 ID: " .. tostring(heroId) end
    if tonumber(cfg.quality) == HeroConfig.QUALITY_UR then
        return false, "UR碎片不能转化为酒馆币"
    end

    local roster = heroes.roster[heroId]
    if not roster or not roster.level then
        return false, "未拥有该英雄"
    end

    -- 检查是否满觉醒（7个觉醒节点全开启）
    local awakeCount = 0
    if roster.awakening then
        for _ in pairs(roster.awakening) do awakeCount = awakeCount + 1 end
    end
    if awakeCount < 7 then
        return false, "该英雄未满觉醒"
    end

    -- 检查碎片数量
    local currentShards = roster.shards or 0
    if currentShards < 1 then
        return false, "碎片不足"
    end

    -- 获取单片转化数量
    local coinPerShard = getStardustValue(heroId)
    if coinPerShard <= 0 then
        return false, "未配置转化比例"
    end

    -- === 原子修改：一次性转化所有碎片 ===
    local totalCoin = coinPerShard * currentShards
    roster.shards = 0

    local currency = PDM.GetModule(uid, "currency")
    currency.tavernCoin = (currency.tavernCoin or 0) + totalCoin

    PDM.MarkDirty(uid, "heroes")
    PDM.MarkDirty(uid, "currency")

    print("[HeroService] CONVERT_SHARD_TO_COIN uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " shards " .. currentShards .. " → 0"
        .. " tavernCoin +" .. totalCoin .. " (" .. coinPerShard .. " x " .. currentShards .. ")")

    return true, nil, {
        heroId = heroId,
        remainingShards = 0,
        coinGained = totalCoin,
        totalTavernCoin = currency.tavernCoin,
    }
end

-- ======================== UR碎片转化 ========================

--- 消耗UR英雄碎片，1:1转化为其他英雄碎片，每日最多30个
---@param uid number
---@param fromHeroId number|nil
---@param toHeroId number|nil
---@param amount number|nil
---@return boolean ok, string? err, table? result
function HeroService.ConvertUrShard(uid, fromHeroId, toHeroId, amount)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end
    if type(heroes.roster) ~= "table" then heroes.roster = {} end

    fromHeroId = tonumber(fromHeroId)
    toHeroId = tonumber(toHeroId)
    amount = math.floor(tonumber(amount) or 0)
    if not fromHeroId then return false, "缺少来源英雄" end
    if not toHeroId then return false, "缺少目标英雄" end
    if fromHeroId == toHeroId then return false, "不能转化为相同碎片" end
    if amount < 1 then return false, "转化数量无效" end

    local fromCfg = HeroConfig.get(fromHeroId)
    if not fromCfg then return false, "来源英雄不存在" end
    if not isUrHero(fromHeroId) then return false, "只能使用UR碎片转化" end

    local toCfg = HeroConfig.get(toHeroId)
    if not toCfg then return false, "目标英雄不存在" end
    if not isUrHero(toHeroId) then return false, "只能转化为UR碎片" end

    local _today, usedCount = resetUrShardConvertDailyIfNeeded(heroes)
    local remain = UR_SHARD_CONVERT_DAILY_LIMIT - usedCount
    if remain <= 0 then
        return false, "今日UR碎片转化次数已用完"
    end
    if amount > remain then
        return false, "今日最多还能转化" .. tostring(remain) .. "个"
    end

    local fromRoster = heroes.roster[fromHeroId]
    local currentShards = fromRoster and math.floor(tonumber(fromRoster.shards) or 0) or 0
    if currentShards < amount then
        return false, "UR碎片不足"
    end

    local toRoster = heroes.roster[toHeroId]
    if not toRoster then
        toRoster = { shards = 0, _shardMigrated = true }
        heroes.roster[toHeroId] = toRoster
    end

    fromRoster.shards = currentShards - amount
    toRoster.shards = math.max(0, math.floor(tonumber(toRoster.shards) or 0)) + amount
    heroes.urShardConvertCount = usedCount + amount

    PDM.MarkDirty(uid, "heroes")

    print("[HeroService] CONVERT_UR_SHARD uid=" .. tostring(uid)
        .. " from=" .. tostring(fromHeroId)
        .. " to=" .. tostring(toHeroId)
        .. " amount=" .. tostring(amount)
        .. " used=" .. tostring(heroes.urShardConvertCount)
        .. "/" .. tostring(UR_SHARD_CONVERT_DAILY_LIMIT))

    return true, nil, {
        fromHeroId = fromHeroId,
        toHeroId = toHeroId,
        amount = amount,
        remainingFromShards = fromRoster.shards,
        targetShards = toRoster.shards,
        dailyUsed = heroes.urShardConvertCount,
        dailyLimit = UR_SHARD_CONVERT_DAILY_LIMIT,
    }
end

--- 消耗特权点恢复当天UR碎片转化次数，可重复恢复
---@param uid number
---@return boolean ok, string? err, table? result
function HeroService.RestoreUrShardConvertLimit(uid)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then return false, "数据未加载" end

    local _today, usedCount = resetUrShardConvertDailyIfNeeded(heroes)
    if usedCount < UR_SHARD_CONVERT_DAILY_LIMIT then
        return false, "今日仍有可用转化次数"
    end

    local ok = CurrencyService.Deduct(uid, "privilegePoint", UR_SHARD_CONVERT_RESTORE_COST)
    if not ok then
        return false, "特权点不足（需要" .. tostring(UR_SHARD_CONVERT_RESTORE_COST) .. "点）"
    end

    heroes.urShardConvertDayId = getTodayDayId()
    heroes.urShardConvertCount = 0
    PDM.MarkDirty(uid, "heroes")

    print("[HeroService] RESTORE_UR_SHARD_CONVERT uid=" .. tostring(uid)
        .. " cost=" .. tostring(UR_SHARD_CONVERT_RESTORE_COST)
        .. " limit=" .. tostring(UR_SHARD_CONVERT_DAILY_LIMIT))

    return true, nil, {
        dailyUsed = 0,
        dailyLimit = UR_SHARD_CONVERT_DAILY_LIMIT,
        cost = UR_SHARD_CONVERT_RESTORE_COST,
    }
end

-- ======================== 冒险等级同步英雄最低等级 ========================

--- 当冒险等级提升后，将所有低于该等级的英雄自动拉升到冒险等级
--- 用于：战斗/扫荡/离线经验导致玩家升级时调用
---@param uid number
---@param newPlayerLevel number 提升后的冒险等级
---@return number boostedCount 被提升的英雄数量
function HeroService.SyncHeroLevelsToPlayerLevel(uid, newPlayerLevel)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes or not heroes.roster then return 0 end

    local targetLevel = math.min(newPlayerLevel, ExpTable.HERO_MAX_LEVEL)
    local boostedCount = 0

    for heroId, hero in pairs(heroes.roster) do
        -- 只处理已解锁的英雄（有 level 字段）
        if hero.level and hero.level < targetLevel then
            hero.level = targetLevel
            hero.exp = 0
            hero.maxExp = ExpTable.getHeroExpForLevel(targetLevel) or 0
            boostedCount = boostedCount + 1
        end
    end

    if boostedCount > 0 then
        PDM.MarkDirty(uid, "heroes")
        print("[HeroService] SYNC_HERO_LEVELS uid=" .. tostring(uid)
            .. " playerLv=" .. tostring(newPlayerLevel)
            .. " boosted=" .. tostring(boostedCount))
        HeroService.ApplyResonanceSync(uid)
    end

    return boostedCount
end

--- 共鸣同步：将低于共鸣地板的英雄 level 提升到共鸣等级
---@param uid number
---@return number boostedCount
---@return number resonanceLevel
function HeroService.ApplyResonanceSync(uid)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes or not heroes.roster then return 0, 1 end

    local resonance, boosted = HeroResonance.syncRosterToResonance(heroes.roster)
    if boosted > 0 then
        PDM.MarkDirty(uid, "heroes")
        print("[HeroService] RESONANCE_SYNC uid=" .. tostring(uid)
            .. " resonance=" .. tostring(resonance)
            .. " boosted=" .. tostring(boosted))
    end
    return boosted, resonance
end

--- 获取新英雄的起始等级（取冒险等级和 1 的较大值）
---@param uid number
---@return number startLevel
function HeroService.GetNewHeroStartLevel(uid)
    local player = PDM.GetModule(uid, "player")
    if not player then return 1 end
    return math.max(1, player.level or 1)
end

--- 获取共鸣等级（全队前 5 高等级中的最低值）
---@param uid number
---@return number
function HeroService.GetResonanceLevel(uid)
    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes or not heroes.roster then return 1 end
    return HeroResonance.computeResonanceLevel(heroes.roster)
end

--- 获取英雄等级（与 roster.level 一致，保留接口供战斗/转职等调用）
---@param uid number
---@param heroId number
---@return number
function HeroService.GetHeroEffectiveLevel(uid, heroId)
    local heroes = PDM.GetModule(uid, "heroes")
    heroId = tonumber(heroId)
    if not heroId or not heroes or not heroes.roster then return 1 end
    local hero = heroes.roster[heroId] or heroes.roster[tostring(heroId)]
    return hero and hero.level or 1
end

return HeroService
