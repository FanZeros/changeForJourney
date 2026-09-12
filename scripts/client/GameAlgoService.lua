-- ============================================================================
-- GameAlgoService - 客户端 GameAlgo 接入封装
-- 职责：初始化 SDK、本地身份持久化、事件上报（实验不再改玩法）
-- ============================================================================

local GameAlgo       = require("sdk.gamealgo.GameAlgo")
local GameAlgoConfig = require("config.GameAlgoConfig")
local VersionConfig  = require("shared.VersionConfig")
local StageConfig    = require("config.StageConfig")

local GameAlgoService = {}

local STORAGE_FILE = "gamealgo_identity.json"
local FLUSH_INTERVAL = 30.0

local initialized_ = false
local configSynced_ = false
local flushTimer_ = 0
local cache_ = {}

local rewardedAdEnabled_ = true

local function loadCache()
    if not fileSystem:FileExists(STORAGE_FILE) then return end
    local file = File(STORAGE_FILE, FILE_READ)
    if not file:IsOpen() then return end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    if ok and type(data) == "table" then
        cache_ = data
    end
end

local function saveCache()
    local file = File(STORAGE_FILE, FILE_WRITE)
    if not file:IsOpen() then return end
    local ok, raw = pcall(cjson.encode, cache_)
    if ok then
        file:WriteString(raw)
    end
    file:Close()
end

local storageAdapter_ = {
    getItem = function(key)
        return cache_[key]
    end,
    setItem = function(key, value)
        cache_[key] = value
        saveCache()
    end,
}

local function isEnabled()
    return GameAlgoConfig.ENABLED == true
end

local function deriveStateFromRemote()
    rewardedAdEnabled_ = GameAlgo.ConfigValue("ads.rewarded.enabled", true, "gameplay.json") ~= false
    local snap = GameAlgo.Snapshot()
    print("[GameAlgoService] remote ready: configVersion="
        .. tostring(snap.config and snap.config.configVersion or "unknown")
        .. " rewardedAdEnabled=" .. tostring(rewardedAdEnabled_)
        .. " (experiments not applied to gameplay)")
    configSynced_ = true
end

function GameAlgoService.Init()
    if initialized_ or not isEnabled() then return end
    initialized_ = true
    loadCache()

    GameAlgo.Init({
        baseUrl = GameAlgoConfig.BASE_URL,
        appVersion = VersionConfig.CURRENT,
        platform = "rest",
        timezone = os.date("%z"),
        isDebug = GameAlgoConfig.IS_DEBUG == true,
        storage = storageAdapter_,
        device = {
            runtime = "taptap_mini_game",
            engine = "urhox",
            maker = "taptap_maker",
        },
        autoFetch = false,
    })

    GameAlgo.FetchConfig(function(err)
        if err then
            print("[GameAlgoService] remote config not ready: " .. tostring(err))
            return
        end
        deriveStateFromRemote()
    end)
    print("[GameAlgoService] initialized")
end

function GameAlgoService.SyncIfNeeded()
    if not initialized_ or configSynced_ then return configSynced_ end
    local snap = GameAlgo.Snapshot()
    if snap.config then
        deriveStateFromRemote()
    end
    return configSynced_
end

function GameAlgoService.Update(dt)
    if not initialized_ then return end
    GameAlgoService.SyncIfNeeded()
    GameAlgo.Update()
    flushTimer_ = flushTimer_ + dt
    if flushTimer_ >= FLUSH_INTERVAL then
        flushTimer_ = 0
        GameAlgo.Flush()
    end
end

function GameAlgoService.OnSessionEnd()
    if not initialized_ then return end
    GameAlgo.TrackSessionEnd()
    GameAlgo.Flush()
end

function GameAlgoService.IsRewardedAdEnabled()
    return rewardedAdEnabled_
end

local function buildStagePayload(stageId, extra)
    local sid = tonumber(stageId) or stageId
    local payload = {
        stage_id = sid,
        level = sid,
        mode = "main",
    }
    local entry = StageConfig.getStage(sid)
    if entry then
        if StageConfig.isTerminalTemple(sid) then
            -- 终焉神殿 chapter=0，报表按对应难度末章归类，与 StageConfig 流转链对齐
            payload.mode = "terminal"
            payload.difficulty = entry.difficulty or StageConfig.getDifficulty(sid)
            local prevId = StageConfig.getTerminalPrevStageId(sid)
            local prev = prevId and StageConfig.getStage(prevId)
            if prev then
                payload.chapter = prev.chapter
                payload.stage = prev.stage
                payload.level = prev.chapter * 100 + prev.stage
                payload.monster_level = prev.monsterLevel
            end
        else
            payload.chapter = entry.chapter
            payload.stage = entry.stage
            payload.level = entry.chapter * 100 + entry.stage
            payload.monster_level = entry.monsterLevel
            payload.difficulty = entry.difficulty or StageConfig.getDifficulty(sid)
        end
    end
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end
    return payload
end

function GameAlgoService.TrackLevelStart(stageId, extra)
    if not initialized_ then return end
    GameAlgo.TrackLevelStart(buildStagePayload(stageId, extra))
end

function GameAlgoService.TrackLevelEnd(stageId, result, extra)
    if not initialized_ then return end
    local payload = buildStagePayload(stageId, extra)
    payload.result = result or "unknown"
    GameAlgo.TrackLevelEnd(payload)
    GameAlgo.Flush()
end

function GameAlgoService.TrackAd(scene)
    if not initialized_ or not scene or scene == "" then return end
    if not rewardedAdEnabled_ then return end
    GameAlgo.TrackAd(scene, "reward", 0, "USD", "taptap")
    GameAlgo.Flush()
end

function GameAlgoService.Executor(key)
    if not initialized_ then return nil end
    return GameAlgo.Executor(key)
end

function GameAlgoService.ConfigValue(path, defaultValue, fileName)
    if not initialized_ then return defaultValue end
    return GameAlgo.ConfigValue(path, defaultValue, fileName)
end

function GameAlgoService.Flush()
    if not initialized_ then return end
    GameAlgo.Flush()
end

return GameAlgoService
