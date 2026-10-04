-- SamsaraSlicePlayer.lua — 七段无奖切片数据层；由主仲裁器决定何时开始展示。
-- 不show、不订阅无ID完成广播、不调用任何领奖/教程/经济协议。
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
---@field evidences table[]
---@field unlockText string?
---@field legacyContext string?
---@field referenceOnly boolean?
---@field referenceSteps SamsaraSliceStep[]?
---@field manualOnly boolean?
---@field eligibilitySource string?
---@field eventTrusted boolean?

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
---@type string?
local takenKey_ = nil
local epoch_, token_ = 0, 0
local savePending_ = false
---@type number
local retryElapsed_ = 0
local FIRST_READ, REPLAY = "samsara_first_read", "samsara_replay"
local CARGO, ORDER, PEOPLE = "samsara.cargo_match", "samsara.gray_order", "samsara.people_record"
local MANIFEST = "samsara.returned_manifest"
local DOG_MIRROR, BELL_MIRROR = "samsara.dog_mirror", "samsara.bell_mirror"
local MIRRORS = {
    [DOG_MIRROR] = { stage = 2505, legacyId = 64, source = "live_clear_2505", evidenceId = "E03-A" },
    [BELL_MIRROR] = { stage = 2905, legacyId = 67, source = "live_clear_2905", evidenceId = "E03-C" },
}

local function mirrorHistorySupported(story)
    local version = tonumber(story.mirrorHistoryVersion)
    return not version or version <= 1
end

-- CLEAR与带ID的遭遇结果分开保存；preclaim/raw历史不能替代这两份来源。
local function mirrorEventTrusted(node, key)
    local spec = MIRRORS[key]
    return spec ~= nil and node ~= nil and node.eligible == true and node.eligibilitySource == spec.source
        and (node.legacyContext == "live_finished" or node.legacyContext == "live_skipped"
            or node.legacyContext == "live_interrupted")
end

local function keys()
    return Config.KEYS or { Config.NODE_KEY }
end

--- 取消只失效进程租约，不清待存结果、不标完成、不递归播放。
function Player.cancel()
    epoch_ = epoch_ + 1
    lease_, request_, takenKey_ = nil, nil, nil
end

--- 旧结果桥捕获当前进程代次，清档/Stop后的迟到遭遇不能污染新档。
---@return number
function Player.getContextEpoch()
    return epoch_
end

---@param key string?
---@return SamsaraSliceDefinition?
local function definition(key)
    local ok, cfg = pcall(Config.get, key or Config.NODE_KEY)
    if not ok or type(cfg) ~= "table" or cfg.mode ~= "small"
        or type(cfg.title) ~= "string" or type(cfg.steps) ~= "table" or #cfg.steps == 0
        or type(cfg.evidence) ~= "table" or type(cfg.evidence.id) ~= "string"
        or type(cfg.evidence.title) ~= "string" or type(cfg.evidence.text) ~= "string" then
        return nil
    end
    for _, step in ipairs(cfg.steps) do
        if type(step) ~= "table" or type(step.text) ~= "string" or step.text == "" then return nil end
    end
    return cfg
end

--- getter意外换表时拒绝迟到结果；只有显式onSessionUpdated允许同游戏重新附着。
---@return SamsaraStoryState?
local function currentStory()
    if not options_ or not session_ or not story_ then return nil end
    local ok, current = pcall(options_.getSession)
    if not ok or current ~= session_ or session_.samsaraStory ~= story_ then
        Player.cancel()
        return nil
    end
    if tonumber(story_.schemaVersion) ~= 1 then return nil end
    if type(story_.nodes) ~= "table" or type(story_.evidence) ~= "table" then return nil end
    return story_
end

---@param story SamsaraStoryState
---@param key string?
---@return SamsaraStoryNode?
---@return boolean supported
local function nodeState(story, key)
    if MIRRORS[key] and not mirrorHistorySupported(story) then return nil, false end
    local node = story.nodes[key or Config.NODE_KEY] --[[@as SamsaraStoryNode?]]
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

local function dependencyReady(story, key)
    local previous = key == ORDER and CARGO or (key == PEOPLE and ORDER or nil)
    if not previous then return true end
    local node, supported = nodeState(story, previous)
    return supported and node and node.eligible == true and processed(node)
        and dependencyReady(story, previous)
end

--- 只改新嵌套表，真实Flush返回true才算保存成功。
---@return boolean
local function flushPending()
    local current = session_
    if not savePending_ or not options_ or not current then return false end
    retryElapsed_ = 0
    if not currentStory() then return false end
    local setOk, setErr = pcall(options_.setSession, current)
    if not setOk then
        print("[SamsaraSlicePlayer] session通知失败，保留待保存: " .. tostring(setErr))
        return false
    end
    if not currentStory() then return false end
    local ok, saved = pcall(options_.flush)
    if ok and saved == true then
        savePending_ = false
        return true
    end
    print("[SamsaraSlicePlayer] Flush失败，保留内存结果并等待节流重试")
    return false
end

local function persist()
    savePending_ = true
    flushPending()
end

local function selectedLegacyId(key)
    if MIRRORS[key] then return MIRRORS[key].legacyId end
    local initialId = session_ and tonumber(session_.initialHeroId)
    local firstId = key == MANIFEST and 44 or 17
    return firstId + ((initialId == 2 and 1) or (initialId == 3 and 2) or 0)
end

local function legacyConfigAvailable(key)
    local cfg = LegacyConfig["SCENARIO_" .. tostring(selectedLegacyId(key))]
    return type(cfg) == "table" and type(cfg.steps) == "table" and #cfg.steps > 0
end

local function legacyClaimed(key)
    local claimed = session_ and session_.claimedScenarios
    local id = selectedLegacyId(key)
    return type(claimed) == "table" and (claimed[id] == true or claimed[tostring(id)] == true)
end

local function captureLegacyContext(node, key)
    if node.legacyContext == "live_finished" or node.legacyContext == "live_skipped"
        or ((key == MANIFEST or MIRRORS[key]) and node.legacyContext == "live_interrupted") then return false end
    local context = legacyClaimed(key) and "legacy_claimed_unknown" or (not legacyConfigAvailable(key) and "unavailable" or nil)
    if node.legacyContext == context then return false end
    node.legacyContext = context
    if context == "unavailable" then
        print("[SamsaraSlicePlayer] 旧剧情配置不可用，允许独立无奖补读: " .. tostring(selectedLegacyId(key)))
    end
    return true
end

local function legacyReady(node, key)
    if MIRRORS[key] then
        return mirrorEventTrusted(node, key) and node.legacyContext ~= "live_interrupted"
    end
    if key == MANIFEST and node.legacyContext == "live_interrupted" then return false end
    return node.legacyContext == "live_finished" or node.legacyContext == "live_skipped"
        or legacyClaimed(key) or not legacyConfigAvailable(key)
end

local function unlockEvidence(story, id, source)
    local evidence = story.evidence[id] --[[@as SamsaraStoryEvidenceState?]]
    if type(evidence) == "table" and evidence.unlocked == true then return false end
    if not evidence then evidence = {}; story.evidence[id] = evidence end
    evidence.unlocked, evidence.source = true, source
    return true
end

local function makeEligible(story, key, source)
    local node, supported = nodeState(story, key)
    if not supported or (node and node.eligible == true) then return false end
    if not node then
        node = { contentVersion = Config.CONTENT_VERSION }
        story.nodes[key] = node
    end
    node.eligible, node.eligibilitySource, node.contentVersion = true, source, Config.CONTENT_VERSION
    if key == Config.NODE_KEY then unlockEvidence(story, "E01", source) end
    print("[SamsaraSlicePlayer] 待阅资格 key=" .. key .. " source=" .. source)
    return true
end

-- 只由已处理的前段补齐后段，不从旧claimed或最高关推断新剧情结果。
local function releaseChain(story)
    local changed = false
    for _, pair in ipairs({ { CARGO, ORDER }, { ORDER, PEOPLE } }) do
        local previous, supported = nodeState(story, pair[1])
        if supported and previous and previous.eligible == true and processed(previous)
            and dependencyReady(story, pair[1]) then
            if makeEligible(story, pair[2], "previous_processed") then changed = true end
        end
    end
    return changed
end

local function prepareManifest(story, source)
    if not definition(MANIFEST) then return false end
    local changed = makeEligible(story, MANIFEST, source)
    local node, supported = nodeState(story, MANIFEST)
    if not supported or not node or node.eligible ~= true then return changed end
    if changed or (source ~= "live_clear_204" and not processed(node)) then
        local cargo = nodeState(story, CARGO)
        if processed(cargo) and node.manualOnly ~= true then
            node.manualOnly = true
            changed = true
        end
    end
    if captureLegacyContext(node, MANIFEST) then changed = true end
    return changed
end

local function strictClear(rawBattle, id)
    local cleared = type(rawBattle) == "table" and rawBattle.clearedStages or nil
    return type(cleared) == "table" and (cleared[id] == true or cleared[tostring(id)] == true)
end

--- RestoreData后、battle恢复/max补齐前调用；两个捕获标记分别保持阴性结果。
---@param options SamsaraSliceOptions
---@param rawBattle table?
---@return boolean supported
function Player.init(options, rawBattle)
    assert(type(options) == "table" and type(options.getSession) == "function"
        and type(options.setSession) == "function" and type(options.flush) == "function",
        "SamsaraSlicePlayer.init需要getSession/setSession/flush")
    local session = options.getSession()
    assert(type(session) == "table", "SamsaraSlicePlayer.init需要共享session表")
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
        if nodeSupported and strictClear(rawBattle, 104) then
            if makeEligible(story, Config.NODE_KEY, "clear_104_legacy") then changed = true end
            node = story.nodes[Config.NODE_KEY]
        end
        story.historyCaptured, changed = true, true
        print("[SamsaraSlicePlayer] N02历史捕获完成，104资格=" .. tostring(node and node.eligible == true))
    end
    -- N02存量档已捕获104，不代表捕获过204/4905；单独迁移且绝不重置旧标记。
    if not story.cargoHistoryCaptured then
        if strictClear(rawBattle, 204) then
            if unlockEvidence(story, "E02", "player_record") then changed = true end
            if prepareManifest(story, "clear_204_legacy") then changed = true end
        end
        if strictClear(rawBattle, 4905) and makeEligible(story, CARGO, "clear_4905_legacy") then changed = true end
        story.cargoHistoryCaptured, changed = true, true
        print("[SamsaraSlicePlayer] 征用案件历史捕获完成")
    end
    -- 镜像旧raw精确true可能已被旧版本max补齐，只记参考，不制造战斗/凭片。
    if mirrorHistorySupported(story) and story.mirrorHistoryCaptured ~= true then
        for _, key in ipairs({ DOG_MIRROR, BELL_MIRROR }) do
            local mirror, mirrorSupported = nodeState(story, key)
            if mirrorSupported and strictClear(rawBattle, MIRRORS[key].stage) then
                if not mirror then
                    mirror = { contentVersion = Config.CONTENT_VERSION, eligibilitySource = "legacy_raw_clear_unknown" }
                    story.nodes[key] = mirror
                elseif not mirror.eligibilitySource then
                    mirror.eligibilitySource = "legacy_raw_clear_unknown"
                end
            end
        end
        story.mirrorHistoryCaptured, story.mirrorHistoryVersion, changed = true, 1, true
        print("[SamsaraSlicePlayer] 镜像历史一次性捕获完成，raw仅作亲历未知参考")
    end
    for _, key in ipairs({ DOG_MIRROR, BELL_MIRROR }) do
        local mirror, mirrorSupported = nodeState(story, key)
        if mirrorSupported and mirror and captureLegacyContext(mirror, key) then changed = true end
    end
    local manifestNode, manifestSupported = nodeState(story, MANIFEST)
    if not sameSession and manifestSupported and manifestNode and manifestNode.legacyContext == "live_interrupted" then
        -- 重启不能把旧preclaim称为已读，仅恢复“历史阅读未知”的独立补读政策。
        manifestNode.legacyContext = nil
        changed = true
    end
    local manifestEvidence = story.evidence.E02
    if type(manifestEvidence) == "table" and manifestEvidence.unlocked == true
        and manifestEvidence.source == "player_record" then
        if prepareManifest(story, "e02_history") then changed = true end
    elseif manifestSupported and manifestNode and manifestNode.eligible == true
        and prepareManifest(story, "e02_history") then
        changed = true
    end
    if nodeSupported and node and node.eligible == true and captureLegacyContext(node) then changed = true end
    if releaseChain(story) then changed = true end
    if changed then persist() end
    return nodeSupported
end

---@param session table
function Player.onSessionUpdated(session)
    if not options_ or type(session) ~= "table" then return end
    local story, supported = Schema.normalize(session)
    if not supported or story.historyCaptured ~= true then Player.cancel() end
    session_, story_ = session, story
end

--- 只由真实首通通知调用，不在这里启动展示或改旧队列。
---@param id number|string
---@return boolean changed
function Player.onStageCleared(id)
    local mirrorKey = (id == 2505 or id == "2505") and DOG_MIRROR
        or ((id == 2905 or id == "2905") and BELL_MIRROR or nil)
    if mirrorKey then
        local story = currentStory()
        if not story or not definition(mirrorKey) then return false end
        local node, supported = nodeState(story, mirrorKey)
        if not supported then return false end
        if node and node.eligible == true and node.eligibilitySource == MIRRORS[mirrorKey].source then return false end
        if not node then node = { contentVersion = Config.CONTENT_VERSION }; story.nodes[mirrorKey] = node end
        node.eligible, node.eligibilitySource = true, MIRRORS[mirrorKey].source
        -- 旧未知参考不能留下伪处理结果；只保留独立记录的遭遇结果。
        node.resolution = nil
        captureLegacyContext(node, mirrorKey)
        print("[SamsaraSlicePlayer] 镜像正式首通待阅 key=" .. mirrorKey .. " context=" .. tostring(node.legacyContext))
        persist()
        return true
    end
    if id ~= 104 and id ~= "104" and id ~= 204 and id ~= "204" and id ~= 4905 and id ~= "4905" then return false end
    local story = currentStory()
    if not story then return false end
    local changed
    if id == 204 or id == "204" then
        changed = unlockEvidence(story, "E02", "player_record")
        -- E02案件副本已存在时仍记录本次真实首通，不覆盖旧N12资料来源。
        if prepareManifest(story, "live_clear_204") then changed = true end
    else
        local key = (id == 104 or id == "104") and Config.NODE_KEY or CARGO
        changed = makeEligible(story, key, "live_clear")
        if changed and key == Config.NODE_KEY then captureLegacyContext(story.nodes[key]) end
    end
    if changed then persist() end
    return changed == true
end

--- N02与N03分别保留旧日志/铁匠道歉依赖；征用三段仍独立于它们。
---@param id number|string
---@param reason string
---@param contextEpoch number? 宿主捕获的代次；测试/同步调用可省略
---@return boolean changed
function Player.noteLegacyResult(id, reason, contextEpoch)
    if contextEpoch ~= nil and contextEpoch ~= epoch_ then return false end
    local mirrorKey = (id == 64 or id == "64") and DOG_MIRROR or ((id == 67 or id == "67") and BELL_MIRROR or nil)
    if mirrorKey then
        local context = (reason == "finished" or reason == "dismissed") and "live_finished"
            or (reason == "skipped" and "live_skipped"
                or ((reason == "reset" or reason == "replaced" or reason == "failed") and "live_interrupted" or nil))
        if not context then return false end
        local story = currentStory()
        if not story or not definition(mirrorKey) then return false end
        local node, supported = nodeState(story, mirrorKey)
        if not supported then return false end
        -- ENTER对白一般先于CLEAR结束，不能因尚无资格而丢失带ID处理来源。
        if not node then node = { contentVersion = Config.CONTENT_VERSION }; story.nodes[mirrorKey] = node end
        if node.legacyContext == context then return false end
        node.legacyContext = context
        print("[SamsaraSlicePlayer] 镜像遭遇结果 key=" .. mirrorKey .. " context=" .. context)
        persist()
        return true
    end
    local key = Config.NODE_KEY
    if id == selectedLegacyId(MANIFEST) or id == tostring(selectedLegacyId(MANIFEST)) then
        key = MANIFEST
    elseif id ~= selectedLegacyId() and id ~= tostring(selectedLegacyId()) then
        return false
    end
    local context = (reason == "finished" or reason == "dismissed") and "live_finished"
        or (reason == "skipped" and "live_skipped" or nil)
    if key == MANIFEST and (reason == "reset" or reason == "replaced" or reason == "failed") then
        context = "live_interrupted"
    end
    if not context then return false end
    local story = currentStory()
    if not story then return false end
    local node, supported = nodeState(story, key)
    if not supported or not node or node.eligible ~= true or node.legacyContext == context then return false end
    node.legacyContext = context
    persist()
    return true
end

local function readyFor(story, key, node)
    local requiresLegacy = key == Config.NODE_KEY or key == MANIFEST or MIRRORS[key] ~= nil
    return dependencyReady(story, key) and (not requiresLegacy or legacyReady(node, key))
end

---@return string?
function Player.peekReady()
    if lease_ then return nil end
    local story = currentStory()
    if not story then return nil end
    local autoKeys = { Config.NODE_KEY, MANIFEST, DOG_MIRROR, BELL_MIRROR, CARGO, ORDER, PEOPLE }
    for _, key in ipairs(autoKeys) do
        local node, supported = nodeState(story, key)
        if supported and node and node.eligible == true and not processed(node) and node.manualOnly ~= true
            and definition(key) and readyFor(story, key, node) then return key end
    end
    return nil
end

local function allowed(kind, key)
    local known = false
    for _, registered in ipairs(keys()) do if key == registered then known = true; break end end
    if not known or lease_ or not definition(key) then return false end
    local story = currentStory()
    if not story then return false end
    local node, supported = nodeState(story, key)
    if not supported or not node or node.eligible ~= true then return false end
    if MIRRORS[key] and not mirrorEventTrusted(node, key) then return false end
    if kind == FIRST_READ then return not processed(node) and dependencyReady(story, key) end
    if kind == REPLAY then return processed(node) and dependencyReady(story, key) end
    return false
end

--- N12首次准备才挂案件副本；资格或记录查询不得提前公开核验和E05。
---@param kind string
---@param key string
---@return SamsaraSliceLease?
function Player.begin(kind, key)
    if not allowed(kind, key) then return nil end
    local story = currentStory()
    if not story then return nil end
    local node = nodeState(story, key)
    if kind == FIRST_READ and (not node or not readyFor(story, key, node)) then
        -- 显式记录页补读可处理已知旧道歉中断，但不伪装其完整结束，也不自动抢播。
        local explicitInterrupted = (key == MANIFEST or MIRRORS[key]) and node and node.legacyContext == "live_interrupted"
            and takenKey_ == key
        if not explicitInterrupted then return nil end
    end
    if key == CARGO and unlockEvidence(story, "E02", "case_archive") then
        local epoch = epoch_
        persist()
        if currentStory() ~= story or epoch_ ~= epoch or not allowed(kind, key) then return nil end
    end
    token_ = token_ + 1
    lease_ = { playToken = token_, contextEpoch = epoch_, nodeKey = key, kind = kind, contentVersion = Config.CONTENT_VERSION }
    request_, takenKey_ = nil, nil
    return { playToken = token_, contextEpoch = epoch_, nodeKey = key, kind = kind, contentVersion = Config.CONTENT_VERSION }
end

local function revealEvidence(story, key)
    if MIRRORS[key] then
        local node = nodeState(story, key)
        if mirrorEventTrusted(node, key) then
            unlockEvidence(story, MIRRORS[key].evidenceId, MIRRORS[key].source)
        end
    elseif key == CARGO then
        unlockEvidence(story, "E02", "case_archive")
        story.evidence.E02.annotationUnlocked = true
    elseif key == ORDER then
        unlockEvidence(story, "E05", "order_archive")
    elseif key == PEOPLE then
        unlockEvidence(story, "E05", "order_archive")
        story.evidence.E05.continuationUnlocked, story.evidence.E05.peopleUnlocked = true, true
    end
end

---@param result SamsaraSliceResult
---@return boolean accepted
function Player.onResult(result)
    local story = currentStory()
    if not story or not lease_ or type(result) ~= "table" then return false end
    if result.playToken ~= lease_.playToken or result.contextEpoch ~= lease_.contextEpoch
        or result.nodeKey ~= lease_.nodeKey then return false end
    local node, supported = nodeState(story, lease_.nodeKey)
    if not supported or not node or node.eligible ~= true or not dependencyReady(story, lease_.nodeKey) then return false end
    if MIRRORS[lease_.nodeKey] and not mirrorEventTrusted(node, lease_.nodeKey) then return false end
    local reason = result.reason
    if reason == "reset" or reason == "replaced" or reason == "failed" then Player.cancel(); return true end
    if reason ~= "finished" and reason ~= "dismissed" and reason ~= "skipped" then return false end
    local kind, key = lease_.kind, lease_.nodeKey
    lease_, request_, takenKey_ = nil, nil, nil
    if kind == FIRST_READ and not processed(node) then
        node.resolution = reason == "skipped" and "skipped" or "finished"
        node.contentVersion = Config.CONTENT_VERSION
        revealEvidence(story, key)
        releaseChain(story)
        persist()
    end
    return true
end

---@param key string
---@return boolean queued
function Player.requestRead(key)
    local story = currentStory()
    if not story then return false end
    local node, supported = nodeState(story, key)
    if not supported then return false end
    local kind = processed(node) and REPLAY or FIRST_READ
    if not allowed(kind, key) then return false end
    request_ = { key = key, kind = kind }
    takenKey_ = nil
    return true
end

---@return SamsaraSliceRequest?
function Player.takeRequest()
    if not request_ or lease_ then return nil end
    local requested = request_
    if not allowed(requested.kind, requested.key) then request_ = nil; return nil end
    request_, takenKey_ = nil, requested.key
    return { key = requested.key, kind = requested.kind }
end

local function evidenceFor(story, id)
    local mirrorKey = id == "E03-A" and DOG_MIRROR or (id == "E03-C" and BELL_MIRROR or nil)
    if mirrorKey then
        local node, supported = nodeState(story, mirrorKey)
        local saved = story.evidence[id] --[[@as SamsaraStoryEvidenceState?]]
        if not supported or not mirrorEventTrusted(node, mirrorKey) or not processed(node)
            or type(saved) ~= "table" or saved.unlocked ~= true or saved.source ~= MIRRORS[mirrorKey].source then return nil end
        local cfg = Config.getEvidence(id)
        if not cfg then return nil end
        -- 不返回任何后续核验，即使未知档案含有提前置true的批注标记。
        return { id = id, title = cfg.title, text = cfg.text, source = saved.source }
    end
    local saved = story.evidence[id] --[[@as SamsaraStoryEvidenceState?]]
    if not saved or saved.unlocked ~= true or not Config.getEvidence then return nil end
    local cfg = Config.getEvidence(id)
    if not cfg then return nil end
    local cargo, cargoSupported = nodeState(story, CARGO)
    local order, orderSupported = nodeState(story, ORDER)
    local people, peopleSupported = nodeState(story, PEOPLE)
    if id == "E05" and not (orderSupported and order and order.eligible == true
        and processed(order) and dependencyReady(story, ORDER)) then return nil end
    return { id = id, title = cfg.title, text = cfg.text, source = saved.source,
        annotation = id == "E02" and cargoSupported and cargo and cargo.eligible == true and processed(cargo) and saved.annotationUnlocked == true and cfg.annotation or nil,
        continuation = id == "E05" and peopleSupported and people and people.eligible == true and processed(people) and dependencyReady(story, PEOPLE) and saved.continuationUnlocked == true and cfg.continuation or nil,
        people = id == "E05" and peopleSupported and people and people.eligible == true and processed(people) and dependencyReady(story, PEOPLE) and saved.peopleUnlocked == true and cfg.people or nil }
end

---@param key string?
---@return SamsaraSliceRecord
function Player.getRecord(key)
    key = key or Config.NODE_KEY
    local cfg = definition(key)
    local record = { key = key, title = cfg and cfg.title or "夹在日志里的回程页",
        status = "unsupported", evidenceVisible = false, evidences = {}, unlockText = cfg and cfg.unlockText }
    local story = currentStory()
    if not cfg or not story then return record end
    local node, supported = nodeState(story, key)
    if not supported then return record end
    record.status = "locked"
    if node then
        record.eligibilitySource = node.eligibilitySource
        record.legacyContext = node.legacyContext
        record.manualOnly = node.manualOnly
        if node.eligible == true and dependencyReady(story, key) then
            record.status = processed(node) and node.resolution or "pending"
        end
    end
    if MIRRORS[key] then
        record.eventTrusted = mirrorEventTrusted(node, key) == true
        if not record.eventTrusted then
            record.referenceOnly, record.referenceSteps = true, cfg.steps
        end
        local evidence = evidenceFor(story, MIRRORS[key].evidenceId)
        if evidence then
            record.evidence, record.evidences[1], record.evidenceVisible = evidence, evidence, true
        end
        return record
    end
    if key == Config.NODE_KEY then
        local saved = story.evidence.E01 --[[@as SamsaraStoryEvidenceState?]]
        record.evidenceVisible = processed(node) and type(saved) == "table" and saved.unlocked == true
        if record.evidenceVisible then
            record.evidence = cfg.evidence
            record.evidences[1] = { id = "E01", title = cfg.evidence.title, text = cfg.evidence.text, source = saved.source }
        end
    else
        local evidenceIds = key == MANIFEST and { "E02" } or { "E02", "E05" }
        for _, id in ipairs(evidenceIds) do
            local evidence = evidenceFor(story, id)
            if evidence then record.evidences[#record.evidences + 1] = evidence end
        end
        record.evidenceVisible = #record.evidences > 0
        if processed(node) then record.evidence = evidenceFor(story, cfg.evidence.id) end
    end
    if key == MANIFEST and record.status == "locked" and (not node or node.eligible ~= true) then
        record.referenceOnly = true
        record.referenceSteps = cfg.steps
    end
    return record
end

---@return SamsaraSliceRecord[]
function Player.getRecords()
    local records = {}
    for _, key in ipairs(keys()) do records[#records + 1] = Player.getRecord(key) end
    return records
end

---@return boolean
function Player.hasPendingRecords()
    for _, record in ipairs(Player.getRecords()) do
        if record.status == "pending" and not record.referenceOnly then return true end
    end
    return false
end

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
