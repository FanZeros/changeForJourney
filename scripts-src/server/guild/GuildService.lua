-- ============================================================================
-- GuildService - 冒险者公会排行榜查询服务
-- 职责: 读取区服内关卡进度排行榜，返回 top-N + 自己排名
-- 运行端: 服务端
-- ============================================================================

local PDM          = require("server.character.PlayerDataManager")
local GuildConfig  = require("config.GuildConfig")
local StageConfig  = require("config.StageConfig")
local Protocol     = require("shared.Protocol")

local GuildService = {}

local TOP_N = 50

--- 获取带区服前缀的 cloud key（内部快捷方法）
---@param keyName string
---@param uid number
---@return string
local function ck(keyName, uid)
    local serverId = PDM.GetServerId(uid)
    return GuildConfig.getCloudKey(keyName, serverId)
end

--- 根据 stageId 生成简短显示名（如 "普通1-5"、"地狱10-3"）
---@param stageId number
---@return string
local function buildProgressName(stageId)
    return StageConfig.formatProgressDisplay(stageId)
end

--- 取玩家设置的展示头像（与 TopBar/竞技场一致）
---@param uid number
---@return number
local function getAvatarHeroId(uid)
    local player = PDM.GetModule(uid, "player")
    if player and player.avatarHeroId then
        return player.avatarHeroId
    end
    return 1
end

local function getAvatarFrameId(uid)
    local player = PDM.GetModule(uid, "player")
    if player and player.avatarFrameId then
        return player.avatarFrameId
    end
    return 1
end

--- 异步拉取区服关卡进度排行榜
---@param uid number
---@param onDone function(rankData: table[], myRankData: table|nil)
local function fetchStageRankings(uid, onDone)
    local key = ck("STAGE_RANK", uid)

    serverCloud:GetRankList(key, 1, TOP_N, {
        ok = function(rankList)
            local userIds = {}
            local results = {}

            local liveAvatarHeroId = getAvatarHeroId(uid)  -- 当前玩家 live 头像（用于覆盖自己的过时编码）
            local liveAvatarFrameId = getAvatarFrameId(uid)

            for i, item in ipairs(rankList) do
                local rawScore = item.iscore[key] or 0
                -- 分数编码: score = stageId * 100 + avatarHeroId
                local stageId      = math.floor(rawScore / 100)
                local avatarHeroId = rawScore % 100
                if avatarHeroId < 1 then avatarHeroId = 1 end
                -- 如果是当前玩家自己的条目，用 live 头像覆盖（cloud 编码可能过时）
                if item.userId == uid then
                    avatarHeroId = liveAvatarHeroId
                end
                local avatarFrameId = 1
                if item.userId == uid then
                    avatarFrameId = liveAvatarFrameId
                end
                -- 优先从排行榜持久化的 score 字段读取名字（离线玩家也有）
                local persistedName = item.score and item.score[key]
                if type(persistedName) ~= "string" or persistedName == "" then
                    persistedName = nil
                end
                userIds[#userIds + 1] = item.userId
                results[#results + 1] = {
                    rank           = i,
                    uid            = item.userId,
                    name           = persistedName or "",
                    _persistedName = persistedName or "",  -- 用于对比是否需要回写
                    progressName   = buildProgressName(stageId),
                    avatarHeroId   = avatarHeroId,
                    avatarFrameId  = avatarFrameId,
                }
            end

            local pendingCount = 2  -- GetUserNickname + GetUserRank
            local myDataResult = nil

            local function tryFinish()
                pendingCount = pendingCount - 1
                if pendingCount == 0 then
                    onDone(results, myDataResult)
                end
            end

            -- 服务端批量解析昵称
            if #userIds > 0 then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            local nick = info.nickname
                            if nick and nick ~= "" then
                                map[info.userId] = nick
                            end
                        end
                        -- 第一轮：用在线昵称覆盖
                        for _, entry in ipairs(results) do
                            if map[entry.uid] then
                                entry.name = map[entry.uid]
                                -- 顺便持久化到 cloud score + player_nickname
                                if entry.name ~= (entry._persistedName or "") then
                                    serverCloud:Set(entry.uid, key, entry.name)
                                end
                                serverCloud:Set(entry.uid, "player_nickname", entry.name)
                            end
                        end
                        -- 收集仍然缺名字的离线玩家 uid
                        local missingUids = {}
                        for _, entry in ipairs(results) do
                            if not entry.name or entry.name == "" then
                                missingUids[#missingUids + 1] = entry.uid
                            end
                        end
                        -- 第二轮：BatchGet player_nickname 兜底
                        if #missingUids > 0 then
                            local batch = serverCloud:BatchGet()
                            for _, mUid in ipairs(missingUids) do
                                batch:Player(mUid)
                            end
                            batch:Key("player_nickname")
                            batch:Fetch({
                                ok = function(batchResults)
                                    local nickMap = {}
                                    for _, r in ipairs(batchResults) do
                                        local storedNick = r.score and r.score.player_nickname
                                        if type(storedNick) == "string" and storedNick ~= "" then
                                            nickMap[r.userId] = storedNick
                                        end
                                    end
                                    for _, entry in ipairs(results) do
                                        if (not entry.name or entry.name == "") and nickMap[entry.uid] then
                                            entry.name = nickMap[entry.uid]
                                        end
                                    end
                                    for _, entry in ipairs(results) do
                                        if not entry.name or entry.name == "" then
                                            entry.name = "玩家" .. tostring(entry.uid)
                                        end
                                    end
                                    tryFinish()
                                end,
                                error = function(code, reason)
                                    print("[GuildService] BatchGet player_nickname error code=" .. tostring(code))
                                    for _, entry in ipairs(results) do
                                        if not entry.name or entry.name == "" then
                                            entry.name = "玩家" .. tostring(entry.uid)
                                        end
                                    end
                                    tryFinish()
                                end,
                            })
                        else
                            tryFinish()
                        end
                    end,
                    onError = function()
                        -- GetUserNickname 失败：尝试 BatchGet player_nickname 兜底
                        local allUids = {}
                        for _, entry in ipairs(results) do
                            if not entry.name or entry.name == "" then
                                allUids[#allUids + 1] = entry.uid
                            end
                        end
                        if #allUids > 0 then
                            local batch = serverCloud:BatchGet()
                            for _, mUid in ipairs(allUids) do
                                batch:Player(mUid)
                            end
                            batch:Key("player_nickname")
                            batch:Fetch({
                                ok = function(batchResults)
                                    local nickMap = {}
                                    for _, r in ipairs(batchResults) do
                                        local storedNick = r.score and r.score.player_nickname
                                        if type(storedNick) == "string" and storedNick ~= "" then
                                            nickMap[r.userId] = storedNick
                                        end
                                    end
                                    for _, entry in ipairs(results) do
                                        if (not entry.name or entry.name == "") and nickMap[entry.uid] then
                                            entry.name = nickMap[entry.uid]
                                        end
                                    end
                                    for _, entry in ipairs(results) do
                                        if not entry.name or entry.name == "" then
                                            entry.name = "玩家" .. tostring(entry.uid)
                                        end
                                    end
                                    tryFinish()
                                end,
                                error = function(code, reason)
                                    print("[GuildService] BatchGet player_nickname fallback error code=" .. tostring(code))
                                    for _, entry in ipairs(results) do
                                        if not entry.name or entry.name == "" then
                                            entry.name = "玩家" .. tostring(entry.uid)
                                        end
                                    end
                                    tryFinish()
                                end,
                            })
                        else
                            for _, entry in ipairs(results) do
                                if not entry.name or entry.name == "" then
                                    entry.name = "玩家" .. tostring(entry.uid)
                                end
                            end
                            tryFinish()
                        end
                    end,
                })
            else
                pendingCount = pendingCount - 1
            end

            -- 查询自己的排名
            serverCloud:GetUserRank(uid, key, {
                ok = function(myRank, myScore)
                    -- 优先使用 live PDM 数据（cloud score 可能因编码方案变更而过时）
                    local myBattle    = PDM.GetModule(uid, "battle")
                    local liveStageId = (myBattle and myBattle.maxStageId) or 0
                    -- cloud score 解码仅作兜底（live 数据不可用时）
                    local rawScore    = myScore or 0
                    local cloudStageId = math.floor(rawScore / 100)
                    local myStageId   = (liveStageId > 0) and liveStageId or cloudStageId
                    myDataResult = {
                        rank         = myRank,
                        name         = "",  -- 客户端自己填充
                        progressName = buildProgressName(myStageId),
                        avatarHeroId  = getAvatarHeroId(uid),
                        avatarFrameId = getAvatarFrameId(uid),
                    }
                    print("[GuildService] rankings fetched: top=" .. #results
                        .. " myRank=" .. tostring(myRank)
                        .. " liveStageId=" .. tostring(liveStageId)
                        .. " cloudStageId=" .. tostring(cloudStageId))
                    tryFinish()
                end,
                error = function(code, reason)
                    print("[GuildService] GetUserRank error code=" .. tostring(code))
                    -- myDataResult 保持 nil，tryFinish 仍需触发
                    tryFinish()
                end,
            })
        end,
        error = function(code, reason)
            print("[GuildService] GetRankList error code=" .. tostring(code))
            onDone({}, nil)
        end,
    })
end

--- 进入公会（异步）：拉排行榜 → 回调结果
---@param uid number
---@param params table|nil
---@param callback function(result: table)
function GuildService.Enter(uid, params, callback)
    fetchStageRankings(uid, function(rankData, myRankData)
        callback({
            success    = true,
            action     = Protocol.ACTION_TYPES.GUILD_ENTER,
            rankData   = rankData,
            myRankData = myRankData,
        })
    end)
end

return GuildService
