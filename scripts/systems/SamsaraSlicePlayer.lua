-- SamsaraSlicePlayer.lua — N02 单例数据层；由主仲裁器决定何时取请求、开始展示。
-- 本模块不 show、不订阅无 ID 完成广播、不调用任何领奖/教程/经济协议。
local Config = require("config.SamsaraSliceConfig")
local Schema = require("shared.session.SamsaraStorySchema")
local LegacyConfig = require("config.ScenarioDialogueConfig")
local Player = {}

---@class SamsaraSliceOptions
---@field getSession fun(): table
---@field setSession fun(session: table)
---@field flush fun(): boolean

---@class SamsaraSliceLease
---@field playToken number
---@field contextEpoch number
---@field nodeKey string
---@field kind string
---@field contentVersion number

---@class SamsaraSliceRequest
---@field key string
---@field kind string

---@class SamsaraSliceResult
---@field playToken number
---@field contextEpoch number
---@field nodeKey string
---@field reason string

---@class SamsaraSliceRecord
---@field key string
---@field title string
---@field status string
---@field evidenceVisible boolean
---@field evidence SamsaraSliceEvidence?
---@field legacyContext string?

---@type SamsaraSliceOptions?
local options_ = nil
---@type table?
local session_ = nil
---@type SamsaraStoryState?
local story_ = nil
---@type SamsaraSliceLease?
local lease_ = nil
---@type SamsaraSliceRequest?
local request_ = nil
local epoch_, token_ = 0, 0
local savePending_ = false
---@type number
local retryElapsed_ = 0
local FIRST_READ, REPLAY = "samsara_first_read", "samsara_replay"

--- 取消仅失效进程租约，不清待存结果，不标完成，不在回调里重新播放。
function Player.cancel()
    epoch_ = epoch_ + 1
    lease_, request_ = nil, nil
end

---@return SamsaraSliceDefinition?
local function definition()
    local ok, cfg = pcall(Config.get, Config.NODE_KEY)
    if not ok or type(cfg) ~= "table" or cfg.mode ~= "small"
        or type(cfg.title) ~= "string" or type(cfg.steps) ~= "table" or #cfg.steps == 0
        or type(cfg.evidence) ~= "table" or cfg.evidence.id ~= "E01"
        or type(cfg.evidence.title) ~= "string" or type(cfg.evidence.text) ~= "string" then
        return nil
    end
    for _, step in ipairs(cfg.steps) do
        if type(step) ~= "table" or type(step.text) ~= "string" or step.text == "" then return nil end
    end
    return cfg
end

--- 必须显式 init 新 session；getSession 意外换表时拒绝迟到结果，不能写回新档。
---@return SamsaraStoryState?
local function currentStory()
    if not options_ or not session_ or not story_ then return nil end
    local ok, current = pcall(options_.getSession)
    if not ok or current ~= session_ or session_.samsaraStory ~= story_ then
        Player.cancel()
        return nil
    end
    local version = tonumber(story_.schemaVersion)
    if not version or version ~= 1 then return nil end
    if type(story_.nodes) ~= "table" or type(story_.evidence) ~= "table" then return nil end
    return story_
end

---@param story SamsaraStoryState
---@return SamsaraStoryNode?
---@return boolean supported
local function nodeState(story)
    local node = story.nodes[Config.NODE_KEY] --[[@as SamsaraStoryNode?]]
    if node == nil then return nil, true end
    if type(node) ~= "table" then return nil, false end
    local version = tonumber(node.contentVersion)
    if version and version > Config.CONTENT_VERSION then return nil, false end
    return node, true
end

---@param node SamsaraStoryNode?
---@return boolean
local function processed(node)
    return node ~= nil and (node.resolution == "finished" or node.resolution == "skipped")
end

--- 只改新嵌套表后，将共享 session 同一张表交回；真实 Flush 返回 true 才算保存成功。
---@return boolean
local function flushPending()
    local current = session_
    if not savePending_ or not options_ or not current then return false end
    retryElapsed_ = 0
    if not currentStory() then return false end
    local setOk, setErr = pcall(options_.setSession, current)
    if not setOk then
        print("[SamsaraSlicePlayer] session 通知失败，保留待保存: " .. tostring(setErr))
        return false
    end
    -- 通知可能触发同步宿主回调；若其已切换存档，不再请求为另一份档写入。
    if not currentStory() then return false end
    local ok, saved = pcall(options_.flush)
    if ok and saved == true then
        savePending_ = false
        return true
    end
    print("[SamsaraSlicePlayer] Flush 失败，保留内存结果并等待节流重试")
    return false
end

local function persist()
    savePending_ = true
    flushPending()
end

---@return number
local function selectedLegacyId()
    local initialId = session_ and tonumber(session_.initialHeroId)
    return (initialId == 2 and 18) or (initialId == 3 and 19) or 17
end

---@return boolean
local function legacyConfigAvailable()
    local cfg = LegacyConfig["SCENARIO_" .. tostring(selectedLegacyId())]
    return type(cfg) == "table" and type(cfg.steps) == "table" and #cfg.steps > 0
end

---@return boolean
local function legacyClaimed()
    local claimed = session_ and session_.claimedScenarios
    local id = selectedLegacyId()
    return type(claimed) == "table" and (claimed[id] == true or claimed[tostring(id)] == true)
end

---@param node SamsaraStoryNode
---@return boolean changed
local function captureLegacyContext(node)
    if node.legacyContext == "live_finished" or node.legacyContext == "live_skipped" then return false end
    local context = legacyClaimed() and "legacy_claimed_unknown" or (not legacyConfigAvailable() and "unavailable" or nil)
    if node.legacyContext == context then return false end
    node.legacyContext = context
    if context == "unavailable" then
        print("[SamsaraSlicePlayer] 旧日志配置不可用，允许独立无奖补读: " .. tostring(selectedLegacyId()))
    end
    return true
end

---@param node SamsaraStoryNode
---@return boolean
local function legacyReady(node)
    return node.legacyContext == "live_finished" or node.legacyContext == "live_skipped"
        or legacyClaimed() or not legacyConfigAvailable()
end

---@param story SamsaraStoryState
---@param source string
local function makeEligible(story, source)
    local node = story.nodes[Config.NODE_KEY] --[[@as SamsaraStoryNode?]]
    if not node then
        node = { contentVersion = Config.CONTENT_VERSION }
        story.nodes[Config.NODE_KEY] = node
    end
    node.eligible = true
    node.eligibilitySource = source
    node.contentVersion = Config.CONTENT_VERSION
    local evidence = story.evidence.E01 --[[@as SamsaraStoryEvidenceState?]]
    if not evidence then
        evidence = {}
        story.evidence.E01 = evidence
    end
    evidence.unlocked = true
    evidence.source = source
end

--- 调用点必须在任何 battle 恢复/按 max 补齐之前，传未经恢复的原始快照。
--- historyCaptured 即使未取得资格也落盘；后续 init 永不重新扫描原始通关表。
---@param options SamsaraSliceOptions
---@param rawBattle table?
---@return boolean supported
function Player.init(options, rawBattle)
    assert(type(options) == "table" and type(options.getSession) == "function"
        and type(options.setSession) == "function" and type(options.flush) == "function",
        "SamsaraSlicePlayer.init 需要 getSession/setSession/flush")
    local session = options.getSession()
    assert(type(session) == "table", "SamsaraSlicePlayer.init 需要共享 session 表")
    local sameSession = session_ == session and session.samsaraStory == story_
    Player.cancel()
    options_, session_ = options, session
    if not sameSession then savePending_, retryElapsed_ = false, 0 end
    local story, supported = Schema.normalize(session)
    story_ = story
    if not supported then return false end
    local node, nodeSupported = nodeState(story)
    local changed = false
    if not story.historyCaptured then
        -- 只认精确 true；当前档已有 true 无法追溯是否曾被旧恢复推断，标历史来源未知。
        local cleared = type(rawBattle) == "table" and rawBattle.clearedStages or nil
        if nodeSupported and type(cleared) == "table" and (cleared[104] == true or cleared["104"] == true) then
            if not node or node.eligible ~= true then
                makeEligible(story, "clear_104_legacy")
                node = story.nodes[Config.NODE_KEY]
            end
        end
        story.historyCaptured = true
        changed = true
        print("[SamsaraSlicePlayer] 首次历史捕获完成，104资格=" .. tostring(node and node.eligible == true))
    end
    if nodeSupported and node and node.eligible == true and captureLegacyContext(node) then changed = true end
    if changed then persist() end
    return nodeSupported
end

--- 同一游戏的 session 推送会经过 JSON 整表替换；显式通知重新附着，不能当成清档。
--- 清档/未知版本先取消租约，且绝不扫描已经被战斗恢复推断的通关表。
---@param session table
function Player.onSessionUpdated(session)
    if not options_ or type(session) ~= "table" then return end
    local story, supported = Schema.normalize(session)
    if not supported or story.historyCaptured ~= true then Player.cancel() end
    session_, story_ = session, story
end

--- 仅由已确认的真实首通回调调用；其他关卡不改变状态，不在这里启动展示。
---@param id number|string
---@return boolean changed
function Player.onStageCleared(id)
    if id ~= 104 and id ~= "104" then return false end
    local story = currentStory()
    if not story then return false end
    local node, supported = nodeState(story)
    if not supported or (node and node.eligible == true) then return false end
    makeEligible(story, "live_clear")
    captureLegacyContext(story.nodes[Config.NODE_KEY])
    persist()
    return true
end

--- 旧日志仍由原链完成奖励；这里只记对应初始分支的真实阅读来源，不伪造 claimed。
---@param id number|string
---@param reason string
---@return boolean changed
function Player.noteLegacyResult(id, reason)
    if id ~= selectedLegacyId() and id ~= tostring(selectedLegacyId()) then return false end
    local context = (reason == "finished" or reason == "dismissed") and "live_finished"
        or (reason == "skipped" and "live_skipped" or nil)
    if not context then return false end
    local story = currentStory()
    if not story then return false end
    local node, supported = nodeState(story)
    if not supported or not node or node.eligible ~= true or node.legacyContext == context then return false end
    node.legacyContext = context
    persist()
    return true
end

--- 非破坏性待阅查询；播放中不提供另一项，取消后交由主仲裁下一帧重新评估。
---@return string?
function Player.peekReady()
    if lease_ or not definition() then return nil end
    local story = currentStory()
    if not story then return nil end
    local node, supported = nodeState(story)
    if supported and node and node.eligible == true and not processed(node) and legacyReady(node) then
        return Config.NODE_KEY
    end
    return nil
end

---@param kind string
---@param key string
---@return boolean
local function allowed(kind, key)
    if key ~= Config.NODE_KEY or lease_ or not definition() then return false end
    local story = currentStory()
    if not story then return false end
    local node, supported = nodeState(story)
    if not supported or not node or node.eligible ~= true then return false end
    if kind == FIRST_READ then return not processed(node) end
    if kind == REPLAY then return processed(node) end
    return false
end

--- 仅仲裁器门禁全部通过后调用；租约返回副本，展示方不能篡改内部身份。
---@param kind string
---@param key string
---@return SamsaraSliceLease?
function Player.begin(kind, key)
    if not allowed(kind, key) then return nil end
    if kind == FIRST_READ then
        local story = currentStory()
        if not story then return nil end
        local node = nodeState(story)
        if not node or not legacyReady(node) then return nil end
    end
    token_ = token_ + 1
    lease_ = { playToken = token_, contextEpoch = epoch_, nodeKey = key, kind = kind, contentVersion = Config.CONTENT_VERSION }
    request_ = nil
    return { playToken = token_, contextEpoch = epoch_, nodeKey = key, kind = kind, contentVersion = Config.CONTENT_VERSION }
end

--- 只接受当前租约精确身份；回看所有结果都不改首次 resolution 或任何持久账本。
---@param result SamsaraSliceResult
---@return boolean accepted
function Player.onResult(result)
    local story = currentStory()
    if not story or not lease_ or type(result) ~= "table" then return false end
    if result.playToken ~= lease_.playToken or result.contextEpoch ~= lease_.contextEpoch
        or result.nodeKey ~= lease_.nodeKey then return false end
    local node, supported = nodeState(story)
    if not supported or not node or node.eligible ~= true then return false end
    local reason = result.reason
    if reason == "reset" or reason == "replaced" or reason == "failed" then
        Player.cancel()
        return true
    end
    if reason ~= "finished" and reason ~= "dismissed" and reason ~= "skipped" then return false end
    local kind = lease_.kind
    lease_, request_ = nil, nil
    if kind == FIRST_READ and not processed(node) then
        node.resolution = reason == "skipped" and "skipped" or "finished"
        node.contentVersion = Config.CONTENT_VERSION
        persist()
    end
    return true
end

--- 单槽显式请求：待阅只能首读，已处理只能回看，锁定或不兼容不能排队。
---@param key string
---@return boolean queued
function Player.requestRead(key)
    local kind = FIRST_READ
    local story = currentStory()
    if not story then return false end
    local node, supported = nodeState(story)
    if not supported then return false end
    if processed(node) then kind = REPLAY end
    if not allowed(kind, key) then return false end
    request_ = { key = key, kind = kind }
    return true
end

--- 无门禁参数：调用方必须先验证所有展示门禁，不能以此方法试探是否有请求。
---@return SamsaraSliceRequest?
function Player.takeRequest()
    if not request_ or lease_ then return nil end
    local requested = request_
    if not allowed(requested.kind, requested.key) then
        request_ = nil
        return nil
    end
    request_ = nil
    return { key = requested.key, kind = requested.kind }
end

---@return SamsaraSliceRecord
function Player.getRecord()
    local cfg = definition()
    local record = {
        key = Config.NODE_KEY, title = cfg and cfg.title or "夹在日志里的回程页",
        status = "unsupported", evidenceVisible = false,
    }
    local story = currentStory()
    if not cfg or not story then return record end
    local node, supported = nodeState(story)
    if not supported then return record end
    record.status = "locked"
    if node then
        record.legacyContext = node.legacyContext
        if node.eligible == true then
            record.status = processed(node) and node.resolution or "pending"
            local evidence = story.evidence.E01 --[[@as SamsaraStoryEvidenceState?]]
            record.evidenceVisible = processed(node) and type(evidence) == "table" and evidence.unlocked == true
            if record.evidenceVisible then record.evidence = cfg.evidence end
        end
    end
    return record
end

--- Flush 失败仅每累计两秒重试一次；大 dt 也不循环补发，取消播放不清待存结果。
---@param dt number
function Player.update(dt)
    if not savePending_ or type(dt) ~= "number" or dt ~= dt or dt < 0 or dt == math.huge then return end
    retryElapsed_ = retryElapsed_ + dt
    if retryElapsed_ >= 2 then flushPending() end
end

---@return boolean
function Player.isSavePending()
    return savePending_
end

return Player
