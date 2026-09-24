-- ============================================================================
-- GMService - GM 命令业务逻辑（单机）
-- 职责: GM 资源发放、等级修改、存档重置、踢人、邮件、服务器状态（纯逻辑，禁止网络 IO）
-- 层级: server/gm  |  通过 PDM 读写数据
-- ============================================================================

local PDM             = require("rules.character.PlayerDataManager")
local CharacterSchema = require("shared.schemas.CharacterSchema")
local CurrencyService = require("rules.currency.CurrencyService")
local MailService     = require("rules.mail.MailService")
local ResourceDefs    = require("config.ResourceDefs")
local HeroConfig      = require("config.HeroConfig")
local ExpTable        = require("config.ExpTable")
local HeroService     = require("rules.hero.HeroService")

local GMService = {}

-- ======================== 资源白名单 ========================

local VALID_RESOURCE_KEYS = {
    gold = true, gems = true, essence = true,
    recruitTicket = true, stellarRecruitTicket = true, goldenKey = true, enhanceStone = true,
    degradeStone = true, destroyStone = true,
    sweepTicket = true, tavernCoin = true,
    weaponScroll = true, offhandScroll = true,
    armorScroll = true, accessoryScroll = true,
    helmetScroll = true, shoesScroll = true,
    arcaneDust = true, corruptStone = true, sacredStone = true,
    speedCardExpireAt = true,
}

-- ======================== GM: 给资源 ========================

---@param uid number
---@param key string    currency 字段名
---@param amount number 数量（正整数）
---@return boolean ok
---@return string|nil reason
---@return table|nil result { key, newValue }
function GMService.GiveResource(uid, key, amount)
    if not key or not VALID_RESOURCE_KEYS[key] then
        return false, "无效的资源类型: " .. tostring(key)
    end
    if not amount or amount <= 0 then
        return false, "参数无效"
    end

    local newBalance
    if key == "speedCardExpireAt" then
        local currency = PDM.GetModule(uid, "currency")
        if not currency then return false, "数据未加载" end
        local now = os.time()
        currency[key] = math.max(now, tonumber(currency[key]) or 0) + amount
        PDM.MarkDirty(uid, "currency")
        newBalance = currency[key]
    else
        newBalance = CurrencyService.Add(uid, key, amount)
        if newBalance == 0 then
            return false, "数据未加载"
        end
    end

    print("[GMService] GiveResource uid=" .. tostring(uid)
        .. " " .. key .. " +" .. amount .. " → " .. newBalance)
    return true, nil, { key = key, newValue = newBalance }
end

-- ======================== GM: 英雄升级 ========================

---@param uid number
---@param heroId number
---@return boolean ok
---@return string|nil reason
---@return table|nil result { heroId, newLevel }
function GMService.LevelUpHero(uid, heroId)
    if not heroId then
        return false, "缺少 heroId"
    end

    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then
        return false, "数据未加载"
    end

    local hero = heroes.roster and heroes.roster[heroId]
    if not hero then
        return false, "未拥有该英雄"
    end

    local oldLevel = hero.level or 1
    hero.level = oldLevel + 1
    hero.exp = 0

    PDM.MarkDirty(uid, "heroes")
    HeroService.ApplyResonanceSync(uid)
    print("[GMService] LevelUpHero uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " Lv" .. oldLevel .. " → Lv" .. hero.level)
    return true, nil, { heroId = heroId, newLevel = hero.level }
end

-- ======================== GM: 提升觉醒等级 ========================

---@param uid number
---@param heroId number
---@return boolean ok
---@return string|nil reason
---@return table|nil result { heroId, nodeIndex, awakeLevel }
function GMService.ActivateAwakening(uid, heroId)
    if not heroId then
        return false, "缺少 heroId"
    end

    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then
        return false, "数据未加载"
    end

    local hero = heroes.roster and heroes.roster[heroId]
    if not hero then
        return false, "未拥有该英雄"
    end

    local AC = require("config.AwakeningConfig")
    hero.awakening = AC.migrateAwakening(hero.awakening)

    local nodeIndex = nil
    for i = 1, AC.NODE_COUNT do
        if not hero.awakening[i] then
            nodeIndex = i
            break
        end
    end
    if not nodeIndex then
        return false, "已满觉醒"
    end

    hero.awakening[nodeIndex] = true
    hero.awakening._awk3Migrated = true
    hero._awk3Migrated = true
    PDM.MarkDirty(uid, "heroes")

    print("[GMService] ActivateAwakening uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " node=" .. tostring(nodeIndex))
    return true, nil, { heroId = heroId, nodeIndex = nodeIndex, awakeLevel = nodeIndex }
end

-- ======================== GM: 获得远征队员 ========================

---@param uid number
---@param heroId number
---@param level number|nil
---@return boolean ok
---@return string|nil reason
---@return table|nil result { heroId, level }
function GMService.GiveHero(uid, heroId, level)
    heroId = tonumber(heroId)
    if not heroId then
        return false, "缺少 heroId"
    end

    local cfg = HeroConfig.get(heroId)
    if not cfg then
        return false, "无效的英雄 ID: " .. tostring(heroId)
    end

    local heroes = PDM.GetModule(uid, "heroes")
    if not heroes then
        return false, "数据未加载"
    end
    if not heroes.roster then
        heroes.roster = {}
    end

    local entry = heroes.roster[heroId]
    if entry and entry.level then
        return false, "已拥有该英雄"
    end

    level = tonumber(level) or HeroService.GetNewHeroStartLevel(uid)
    local existingShards = entry and entry.shards or 0
    heroes.roster[heroId] = {
        level = level,
        exp = 0,
        maxExp = ExpTable.getHeroExpForLevel(level) or 0,
        classId = cfg.classId or 1,
        dupeCount = 0,
        shards = existingShards,
        awakening = { _awk3Migrated = true },
        extraTalent = require("systems.ExtraTalentSystem").normalize(nil),
        _shardMigrated = true,
        _awk3Migrated = true,
    }

    PDM.MarkDirty(uid, "heroes")
    PDM.FlushImmediate(uid)

    print("[GMService] GiveHero uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " level=" .. tostring(level))
    return true, nil, { heroId = heroId, level = level }
end

-- ======================== GM: 远征等级提升 ========================

---@param uid number
---@return boolean ok
---@return string|nil reason
---@return table|nil result { newLevel }
function GMService.PlayerLevelUp(uid)
    local ExpTable = require("config.ExpTable")
    local player = PDM.GetModule(uid, "player")
    if not player then
        return false, "数据未加载"
    end

    local oldLevel = player.level or 1
    if ExpTable.isPlayerMaxLevel(oldLevel) then
        return false, "已满级"
    end

    player.level = oldLevel + 1
    player.exp = 0
    local nextNeeded = ExpTable.getPlayerExpForLevel(player.level)
    player.maxExp = nextNeeded or 0

    PDM.MarkDirty(uid, "player")
    print("[GMService] PlayerLevelUp uid=" .. tostring(uid)
        .. " Lv" .. oldLevel .. " → Lv" .. player.level)
    return true, nil, { newLevel = player.level }
end

-- ======================== GM: 重置存档 ========================

---@param uid number
---@return boolean ok
---@return string|nil reason
function GMService.ResetSave(uid)
    local resetClock = os.clock()
    local TAG = "[GMService][DIAG-RESET]"
    print(string.format("%s ===== ResetSave START uid=%s clock=%.4f =====", TAG, tostring(uid), resetClock))
    print(string.format("%s caller traceback:\n%s", TAG, debug.traceback("", 2)))

    -- 1. 遍历 CharacterSchema.Fields，将所有区服模块重置为默认值
    local resetCount = 0
    local skippedCount = 0
    local fieldKeys = {}
    for fieldKey, def in pairs(CharacterSchema.Fields) do
        if def.scope == "server" and def.getDefault then
            local defaultData = def.getDefault()
            local tbl = PDM.GetModule(uid, fieldKey)
            if tbl then
                local oldKeyCount = 0
                for _ in pairs(tbl) do oldKeyCount = oldKeyCount + 1 end
                -- 清空原表
                for k in pairs(tbl) do
                    tbl[k] = nil
                end
                -- 写入默认值
                local newKeyCount = 0
                for k, v in pairs(defaultData) do
                    tbl[k] = v
                    newKeyCount = newKeyCount + 1
                end
                PDM.MarkDirty(uid, fieldKey)
                resetCount = resetCount + 1
                fieldKeys[#fieldKeys + 1] = fieldKey
                print(string.format("%s   reset module [%s] oldKeys=%d newKeys=%d → MarkDirty called",
                    TAG, fieldKey, oldKeyCount, newKeyCount))
            else
                skippedCount = skippedCount + 1
                print(string.format("%s   SKIP module [%s] — PDM.GetModule returned nil", TAG, fieldKey))
            end
        end
    end
    print(string.format("%s Phase1 done: reset %d modules, skipped %d. Fields: [%s]",
        TAG, resetCount, skippedCount, table.concat(fieldKeys, ", ")))

    -- 2. 从 global_profile 中移除当前区服的创角记录和进度
    local serverId = PDM.GetServerId(uid)
    print(string.format("%s Phase2: serverId=%s", TAG, tostring(serverId)))
    if serverId then
        local gp = PDM.GetModule(uid, "global_profile")
        if gp then
            local hadServer = gp.servers and gp.servers[serverId] ~= nil
            local hadProgress = gp.serverProgress and gp.serverProgress[tostring(serverId)] ~= nil
            -- 移除 servers 中的创角标记
            if gp.servers then
                gp.servers[serverId] = nil
            end
            -- 移除 serverProgress 中的进度记录
            if gp.serverProgress then
                gp.serverProgress[tostring(serverId)] = nil
            end
            PDM.MarkDirty(uid, "global_profile")
            print(string.format("%s   global_profile: removed serverId=%s hadServer=%s hadProgress=%s → MarkDirty",
                TAG, tostring(serverId), tostring(hadServer), tostring(hadProgress)))
        else
            print(string.format("%s   WARNING: global_profile is nil!", TAG))
        end
    else
        print(string.format("%s   WARNING: serverId is nil, skip global_profile cleanup", TAG))
    end

    local elapsed = os.clock() - resetClock
    print(string.format("%s ===== ResetSave END uid=%s elapsed=%.4fs totalModulesReset=%d =====",
        TAG, tostring(uid), elapsed, resetCount))
    return true
end

-- ======================== GM: 踢出玩家 ========================

-- 单机没有联机会话，踢人已删除。

-- ======================== GM: 向指定玩家发送邮件 ========================

--- 向本地已加载存档发送动态邮件。
---@param targetUid number
---@param title string
---@param body string
---@param rewards table[]|nil
---@return boolean ok
---@return string|nil reason
---@return table|nil result { mailId, delivered }
function GMService.SendMailToPlayer(targetUid, title, body, rewards)
    if not targetUid then
        return false, "缺少 targetUid"
    end
    if not title or title == "" then
        return false, "邮件标题不能为空"
    end
    if not PDM.IsLoaded(targetUid) then
        return false, "单机只能给已加载的本地存档发邮件"
    end

    local mailRewards = ResourceDefs.normalizeMailRewardList(rewards)
    if ResourceDefs.hasDroppedMailRewards(rewards, mailRewards) then
        return false, "奖励格式无效（碎片请用 101*数量、shard_16*数量 或 h16*数量）"
    end

    local dmId = MailService.SendDynamicMail(targetUid, {
        title   = title,
        body    = body or "",
        rewards = mailRewards,
        source  = "gm_console",
        date    = os.date("%Y/%m/%d"),
        sentAt  = os.time(),
    })
    if not dmId then
        return false, "本地投递失败"
    end

    print("[GMService] SendMailToPlayer targetUid=" .. tostring(targetUid)
        .. " delivered=local")
    return true, nil, { mailId = dmId, delivered = "local" }
end

-- ======================== GM: 查询服务器状态 ========================

local function localStatus()
    local now = os.time()
    local onlineUIDs = {}
    if PDM.IsLoaded(1) then
        onlineUIDs[1] = 1
    end
    return {
        serverTime = now,
        startTime = now,
        uptimeSeconds = 0,
        onlineCount = #onlineUIDs,
        onlineUIDs = onlineUIDs,
        onlinePlayers = {},
        allOnlinePlayers = {},
        maintenanceMode = false,
    }
end

--- 单机状态：没有联机在线列表。
---@return table status
function GMService.GetServerStatus()
    return localStatus()
end

--- 单机状态，保持异步回调形态。
---@param callback fun(status: table)
function GMService.GetServerStatusAsync(callback)
    if callback then
        callback(localStatus())
    end
end

-- ======================== GM: 重置指定模块 ========================

--- 重置指定玩家的指定数据模块为默认值
--- 比 ResetSave 更精细：只重置一个模块，不影响其他数据
---@param targetUid number
---@param moduleName string  CharacterSchema 中的 fieldKey
---@return boolean ok
---@return string|nil reason
function GMService.ResetModule(targetUid, moduleName)
    if not targetUid then
        return false, "缺少 targetUid"
    end
    if not moduleName or moduleName == "" then
        return false, "缺少 moduleName"
    end

    -- 校验模块是否存在于 Schema 中
    local def = CharacterSchema.Fields[moduleName]
    if not def then
        return false, "无效的模块名: " .. tostring(moduleName)
    end
    if def.scope ~= "server" then
        return false, "只能重置 server 作用域模块"
    end
    if not def.getDefault then
        return false, "该模块无默认值定义"
    end

    -- 检查目标玩家数据是否已加载
    if not PDM.IsLoaded(targetUid) then
        return false, "目标玩家数据未加载（不在线）"
    end

    -- 获取模块表并重置
    local tbl = PDM.GetModule(targetUid, moduleName)
    if not tbl then
        return false, "无法获取模块数据"
    end

    local defaultData = def.getDefault()

    -- 清空原表
    for k in pairs(tbl) do
        tbl[k] = nil
    end
    -- 写入默认值
    for k, v in pairs(defaultData) do
        tbl[k] = v
    end

    PDM.MarkDirty(targetUid, moduleName)

    print("[GMService] ResetModule targetUid=" .. tostring(targetUid)
        .. " module=" .. moduleName .. " → reset to default")
    return true
end

-- 单机不封禁、不维护。查询本地已加载存档仍可用。

--- 查询指定在线玩家的基本信息
---@param targetUid number
---@return boolean ok
---@return string|nil reason
---@return table|nil result 玩家信息摘要
function GMService.QueryPlayer(targetUid)
    if not targetUid then
        return false, "缺少 targetUid"
    end

    -- 检查玩家数据是否已加载
    if not PDM.IsLoaded(targetUid) then
        return false, "目标玩家数据未加载（不在线）"
    end

    -- 收集各模块的摘要信息
    local player   = PDM.GetModule(targetUid, "player")
    local currency = PDM.GetModule(targetUid, "currency")
    local heroes   = PDM.GetModule(targetUid, "heroes")
    local battle   = PDM.GetModule(targetUid, "battle")
    local gp       = PDM.GetModule(targetUid, "global_profile")

    local StageConfig = require("config.StageConfig")
    local currentStageId = battle and battle.currentStageId or 0
    local maxStageId     = battle and battle.maxStageId or 0
    local function fmtStage(sid)
        if not sid or sid == 0 then return "未开始" end
        return StageConfig.formatProgressDisplay(sid)
    end

    local info = {
        uid            = targetUid,
        level          = player and player.level or 0,
        exp            = player and player.exp or 0,
        stage          = fmtStage(currentStageId),
        maxStage       = fmtStage(maxStageId),
        gold           = currency and currency.gold or 0,
        gems           = currency and currency.gems or 0,
        heroCount      = 0,
        createTime     = gp and gp.createTime or 0,
        banned         = false,
        banReason      = "",
    }

    -- 英雄数量
    if heroes and heroes.roster then
        for _ in pairs(heroes.roster) do
            info.heroCount = info.heroCount + 1
        end
    end

    -- 封禁信息
    if gp and gp.banInfo and gp.banInfo.banned then
        info.banned = true
        info.banReason = gp.banInfo.banReason or ""
    end

    return true, nil, info
end

-- ======================== GM: 公告管理 ========================

--- 动态公告管理（运行时增删改，修改 AnnouncementConfig 内存表）
--- action: "add" | "remove" | "list"
---@param action string
---@param data table|nil  add 时需要 { id, title, content, type }
---@return boolean ok
---@return string|nil reason
---@return table|nil result
function GMService.ManageAnnouncement(action, data)
    local AnnouncementConfig = require("shared.AnnouncementConfig")
    local announcements = AnnouncementConfig.ANNOUNCEMENTS

    if action == "list" then
        -- 返回当前所有公告
        return true, nil, { announcements = announcements }

    elseif action == "add" then
        if not data then return false, "缺少公告数据" end
        if not data.id or data.id == "" then return false, "缺少公告 id" end
        if not data.title or data.title == "" then return false, "缺少公告标题" end
        if not data.content then return false, "缺少公告内容" end

        -- 检查 id 是否重复
        for _, ann in ipairs(announcements) do
            if ann.id == data.id then
                return false, "公告 id 已存在: " .. data.id
            end
        end

        -- 添加公告
        local newAnn = {
            id         = data.id,
            title      = data.title,
            content    = data.content,
            type       = data.type or "permanent",
            dateOffset = data.dateOffset or 0,
            date       = os.date("%Y/%m/%d"),  -- GM 手动添加的公告用当前日期
            gmAdded    = true,                 -- 标记为 GM 动态添加
        }
        announcements[#announcements + 1] = newAnn

        print("[GMService] ManageAnnouncement ADD id=" .. data.id)
        return true, nil, { announcement = newAnn }

    elseif action == "remove" then
        if not data or not data.id then return false, "缺少公告 id" end

        -- 查找并移除
        for i, ann in ipairs(announcements) do
            if ann.id == data.id then
                table.remove(announcements, i)
                print("[GMService] ManageAnnouncement REMOVE id=" .. data.id)
                return true, nil, { removedId = data.id }
            end
        end
        return false, "未找到公告: " .. data.id

    else
        return false, "无效的操作: " .. tostring(action) .. " (支持: add/remove/list)"
    end
end

-- ======================== 全服邮件 ========================

--- 发送全服广播邮件
---@param title string
---@param content string
---@param rewards table[]|nil
---@param expireDays number|nil
---@param operatorUid number GM 操作者 UID
---@param serverIds number[]|nil 目标区服列表（nil=全服）
---@return boolean ok
---@return string|nil errMsg
---@return table|nil result
function GMService.BroadcastMail(title, content, rewards, expireDays, operatorUid, serverIds)
    if not title or title == "" then
        return false, "标题不能为空"
    end
    if not content or content == "" then
        return false, "内容不能为空"
    end

    local BroadcastMailService = require("rules.mail.BroadcastMailService")

    -- 确保服务已初始化
    if not BroadcastMailService.IsInitialized() then
        -- Init 是异步的（serverCloud:Get 回调），调用后不能立即使用
        -- 正常情况下 Server.Start() 已经提前调用了 Init，这里是防御性兜底
        BroadcastMailService.Init(nil)
        return false, "全服邮件服务正在初始化，请稍后重试（约1-2秒）"
    end

    local ok, errMsg, result = BroadcastMailService.SendBroadcastMail(title, content, rewards, expireDays, serverIds)
    if ok then
        local serverStr = serverIds and table.concat(serverIds, ",") or "全服"
        print("[GMService] BroadcastMail SUCCESS operator=" .. tostring(operatorUid)
            .. " title=" .. title .. " servers=" .. serverStr
            .. " mailId=" .. (result and result.mailId or "?"))
    else
        print("[GMService] BroadcastMail FAILED operator=" .. tostring(operatorUid)
            .. " reason=" .. tostring(errMsg))
    end
    return ok, errMsg, result
end

-- ======================== GM: 修复玩家丢档（迁移恢复） ========================

--- 诊断并修复玩家存档丢失问题（roster 为空但其他模块有数据）
--- 核心逻辑与 Server.lua 中 loadAndPushFullState 安全网一致，但作为 GM 命令可以：
--- 1. 先做只读诊断，输出详细报告
--- 2. 确认后执行修复
--- 3. 修复后推送更新到客户端
---@param targetUid number
---@param dryRun boolean|nil  true=仅诊断不修复，nil/false=执行修复
---@return boolean ok
---@return string|nil reason
---@return table|nil result 诊断/修复报告
function GMService.RepairPlayerSave(targetUid, dryRun, operatorUid)
    if not targetUid then
        return false, "缺少 targetUid"
    end

    -- 检查目标玩家数据是否已加载
    if not PDM.IsLoaded(targetUid) then
        return false, "目标存档未加载"
    end

    -- ── 收集诊断信息 ──
    local heroes   = PDM.GetModule(targetUid, "heroes")
    local player   = PDM.GetModule(targetUid, "player")
    local equip    = PDM.GetModule(targetUid, "equipment")
    local battle   = PDM.GetModule(targetUid, "battle")
    local currency = PDM.GetModule(targetUid, "currency")
    local gp       = PDM.GetModule(targetUid, "global_profile")

    local serverId = PDM.GetServerId(targetUid)
    local serverKey = tostring(serverId)

    -- 计算 roster 数量
    local rosterCount = 0
    if heroes and heroes.roster then
        for _ in pairs(heroes.roster) do
            rosterCount = rosterCount + 1
        end
    end

    local playerLevel = player and player.level or 1
    local equipNextSeq = equip and equip.nextSeq or 1
    local maxStageId = battle and battle.maxStageId or 0
    local gold = currency and currency.gold or 0
    local avatarHeroId = player and player.avatarHeroId or 0

    -- serverProgress 信息
    local spEntry = gp and gp.serverProgress and gp.serverProgress[serverKey]
    local spLevel = spEntry and spEntry.level or 0
    local gpServers = gp and gp.servers and gp.servers[serverKey]

    -- 构建诊断报告
    local diag = {
        targetUid = targetUid,
        serverId = serverId,
        rosterCount = rosterCount,
        playerLevel = playerLevel,
        equipNextSeq = equipNextSeq,
        maxStageId = maxStageId,
        gold = gold,
        avatarHeroId = avatarHeroId,
        spLevel = spLevel,
        gpServers = gpServers and true or false,
        needsRepair = false,
        repairReason = "",
        recoveredHeroIds = {},
    }

    -- ── 判断是否需要修复（多信号检测）──
    local rosterEmpty = (rosterCount == 0)
    local isProvenNonNewPlayer = (playerLevel > 1) or (equipNextSeq > 1)

    -- 收集所有损坏信号
    local corruptionSignals = {}

    -- 信号1: roster 为空但确认非新玩家
    if rosterEmpty and isProvenNonNewPlayer then
        corruptionSignals[#corruptionSignals + 1] = "roster为空但level="
            .. playerLevel .. "/equipSeq=" .. equipNextSeq
    end

    -- 信号2: heroes 中存在 _recovered 标记（曾被安全网自动恢复）
    local recoveredCount = 0
    if heroes and heroes.roster then
        for _, heroData in pairs(heroes.roster) do
            if type(heroData) == "table" and heroData._recovered then
                recoveredCount = recoveredCount + 1
            end
        end
    end
    if recoveredCount > 0 then
        corruptionSignals[#corruptionSignals + 1] = "存在" .. recoveredCount
            .. "个被安全网自动恢复的英雄(_recovered标记)"
    end
    diag.recoveredHeroCount = recoveredCount

    -- 信号3: battle.maxStageId 与 player.level 严重不一致
    -- level>5 但 maxStageId 仍是默认值0101 或 0，说明战斗数据丢失/未迁移
    local battleDefault = (maxStageId == 0 or maxStageId == 101)  -- 0101 八进制=65，十进制写法=101
    if playerLevel > 5 and battleDefault then
        corruptionSignals[#corruptionSignals + 1] = "player.level=" .. playerLevel
            .. "但maxStageId=" .. maxStageId .. "(默认值)，战斗进度数据异常"
    end

    -- 信号4: deployed 为空但 roster 非空（出战列表丢失）
    local deployedCount = 0
    if heroes and heroes.deployed then
        for _ in pairs(heroes.deployed) do
            deployedCount = deployedCount + 1
        end
    end
    if not rosterEmpty and deployedCount == 0 then
        corruptionSignals[#corruptionSignals + 1] = "roster有" .. rosterCount
            .. "英雄但deployed为空(出战列表丢失)"
    end
    diag.deployedCount = deployedCount

    -- 信号5: serverProgress.level 与 player.level 严重偏离（被降级）
    if spLevel > 0 and playerLevel > 1 and math.abs(spLevel - playerLevel) > 10 then
        corruptionSignals[#corruptionSignals + 1] = "serverProgress.level=" .. spLevel
            .. " vs player.level=" .. playerLevel .. " 偏差>" .. math.abs(spLevel - playerLevel)
    end

    -- 信号6: 所有英雄 exp=0 且 level 相同（批量占位符数据）
    local allSameLevel = true
    local allZeroExp = true
    local firstHeroLevel = nil
    if heroes and heroes.roster and not rosterEmpty then
        for _, heroData in pairs(heroes.roster) do
            if type(heroData) == "table" then
                if firstHeroLevel == nil then
                    firstHeroLevel = heroData.level
                elseif heroData.level ~= firstHeroLevel then
                    allSameLevel = false
                end
                if heroData.exp and heroData.exp > 0 then
                    allZeroExp = false
                end
            end
        end
    end
    if not rosterEmpty and rosterCount > 3 and allSameLevel and allZeroExp and recoveredCount > 0 then
        corruptionSignals[#corruptionSignals + 1] = "所有" .. rosterCount
            .. "个英雄level=" .. (firstHeroLevel or "?") .. "/exp=0(批量恢复的占位符数据)"
    end

    diag.corruptionSignals = corruptionSignals

    -- 最终判定
    if #corruptionSignals == 0 then
        diag.repairReason = "未检测到损坏信号 (roster=" .. rosterCount
            .. ", level=" .. playerLevel .. ", maxStage=" .. maxStageId .. ")"
        return true, nil, diag
    end

    -- 如果只有 "roster为空" 信号但不是非新玩家，无法修复
    if rosterEmpty and not isProvenNonNewPlayer then
        diag.repairReason = "roster为空但无法证明非新玩家(level=" .. playerLevel
            .. ", equipSeq=" .. equipNextSeq .. ")，无法自动修复"
        return true, nil, diag
    end

    -- 确认需要修复
    diag.needsRepair = true
    diag.repairReason = table.concat(corruptionSignals, "; ")

    -- ── 收集可恢复的 heroId ──
    local recoveredHeroIds = {}

    -- 来源1：player.avatarHeroId
    if avatarHeroId and avatarHeroId > 0 then
        recoveredHeroIds[avatarHeroId] = "avatarHeroId"
    end

    -- 来源2：equipment.equipped 中绑定的 heroId
    if equip and equip.equipped then
        for heroIdKey, _ in pairs(equip.equipped) do
            local hid = tonumber(heroIdKey)
            if hid and hid > 0 then
                recoveredHeroIds[hid] = (recoveredHeroIds[hid] or "") .. "+equipped"
            end
        end
    end

    -- 来源3：battle.deployed（如果战斗模块还有出战信息）
    if battle and battle.deployed then
        for _, heroId in pairs(battle.deployed) do
            local hid = tonumber(heroId)
            if hid and hid > 0 then
                recoveredHeroIds[hid] = (recoveredHeroIds[hid] or "") .. "+battleDeployed"
            end
        end
    end

    -- 兜底：至少用 avatarHeroId 或默认 heroId=1
    if not next(recoveredHeroIds) then
        local fallbackId = (avatarHeroId and avatarHeroId > 0) and avatarHeroId or 1
        recoveredHeroIds[fallbackId] = "fallback"
    end

    -- 记录到诊断报告
    local heroIdList = {}
    for hid, source in pairs(recoveredHeroIds) do
        heroIdList[#heroIdList + 1] = { heroId = hid, source = source }
    end
    diag.recoveredHeroIds = heroIdList

    -- ── 如果是 dryRun，到此为止 ──
    if dryRun then
        diag.repairReason = diag.repairReason .. " [DRY RUN - 未执行修复]"
        return true, nil, diag
    end

    -- ── 执行修复 ──
    local heroLevel = math.max(1, playerLevel)

    -- 1. 重建 roster
    local newRoster = {}
    local newDeployed = {}
    local first = true
    for heroId, _ in pairs(recoveredHeroIds) do
        newRoster[heroId] = {
            level = heroLevel,
            exp = 0,
            maxExp = 0,
            classId = 1,
            dupeCount = 0,
            shards = 0,
            _shardMigrated = true,
            _recovered = true,      -- 标记为 GM 恢复数据
            _repairedAt = os.time(),
        }
        if first then
            newDeployed[1] = heroId
            first = false
        end
    end

    heroes.roster = newRoster
    heroes.deployed = newDeployed
    PDM.MarkDirty(targetUid, "heroes")

    -- 2. 修复 serverProgress（防止自毁循环继续）
    if gp then
        if not gp.serverProgress then gp.serverProgress = {} end
        local sp = gp.serverProgress[serverKey]
        if sp then
            -- 只升不降
            if not sp.level or sp.level < playerLevel then
                sp.level = playerLevel
            end
        else
            gp.serverProgress[serverKey] = { level = playerLevel, stage = "" }
        end

        -- 修复 gp.servers 标记
        if not gp.servers then gp.servers = {} end
        if not gp.servers[serverKey] then
            gp.servers[serverKey] = true
        end

        PDM.MarkDirty(targetUid, "global_profile")
    end

    diag.repairReason = diag.repairReason .. " [已修复]"
    diag.repairExecuted = true
    diag.repairedRosterCount = 0
    for _ in pairs(newRoster) do
        diag.repairedRosterCount = diag.repairedRosterCount + 1
    end

    print(string.format(
        "[GMService][REPAIR] uid=%s serverId=%s — Repaired roster: %d heroes recovered, " ..
        "player.level=%d, equip.nextSeq=%d, serverProgress.level→%d",
        tostring(targetUid), tostring(serverId),
        diag.repairedRosterCount, playerLevel, equipNextSeq, playerLevel))

    return true, nil, diag
end

return GMService
