-- SamsaraRescueLedger.lua — N10的实际恢复来源账本，不选择保单A/B、不发奖励。
-- 本批仅观察单场主战斗；三行尚未覆盖，缺回执始终unknown，绝不推断未获救。
local StageConfig = require("config.StageConfig")
local Ledger = {}

---@class SamsaraRescueOptions
---@field getSession fun(): table?
---@field setSession fun(session: table)
---@field flush fun(): boolean
---@class SamsaraRescueReceipt
---@field schemaVersion number
---@field source string
---@field scope string
---@field failedStageId number
---@field recoveredStageId number
---@field heroIds number[]
---@field recoveryComplete boolean
---@type SamsaraRescueOptions?
local options_ = nil
---@type table?
local session_ = nil
---@type table?
local story_ = nil
local tickets_ = setmetatable({}, { __mode = "k" })
local pendingSave_ = false
local retryElapsed_ = 0
local SOURCE = "live_nonterminal_wipe_recovery"

local function integer(value)
    return type(value) == "number" and value == value and value > 0
        and value < math.huge and value % 1 == 0
end

local function supportedStory(story)
    return type(story) == "table" and story.schemaVersion == 1
        and type(story.nodes) == "table" and type(story.evidence) == "table"
end

local function supportedDomain(domain)
    -- 已存在却无明确版本的域不可当作本版空账本覆盖。
    return domain == nil or (type(domain) == "table" and domain.schemaVersion == 1
        and domain.scope == "single_scene")
end

local function currentStory()
    if not options_ or not session_ or not story_ then return nil end
    local ok, current = pcall(options_.getSession)
    if not ok or current ~= session_ or session_.samsaraStory ~= story_
        or not supportedStory(story_) or not supportedDomain(story_.rescueLedger) then
        tickets_ = setmetatable({}, { __mode = "k" })
        return nil
    end
    return story_
end

--- 退出或重新附着时使所有进程票据失效；已提交的回执不删除。
function Ledger.cancel()
    tickets_ = setmetatable({}, { __mode = "k" })
end

---@param options SamsaraRescueOptions
function Ledger.init(options)
    assert(type(options) == "table" and type(options.getSession) == "function"
        and type(options.setSession) == "function" and type(options.flush) == "function",
        "SamsaraRescueLedger.init需要getSession/setSession/flush")
    local session = options.getSession()
    local story = type(session) == "table" and session.samsaraStory or nil
    local sameSession = session == session_ and story == story_
    Ledger.cancel()
    options_, session_, story_ = options, session, story
    if not sameSession then pendingSave_, retryElapsed_ = false, 0 end
    -- 初始化不补造新档标记、不迁移旧claimed、不建立阴性经历。
    return currentStory() ~= nil
end

---@param session table
function Ledger.onSessionUpdated(session)
    if not options_ or type(session) ~= "table" then Ledger.cancel(); return end
    if session ~= session_ or session.samsaraStory ~= story_ then
        Ledger.cancel()
        pendingSave_, retryElapsed_ = false, 0
    end
    session_, story_ = session, session.samsaraStory
end

local function flushPending()
    if not pendingSave_ or not options_ or not currentStory() then return false end
    retryElapsed_ = 0
    local current = session_
    local ok, notified = pcall(options_.setSession, current)
    if not ok or notified == false or currentStory() == nil or current ~= session_ then
        print("[SamsaraRescueLedger] session通知失败或换档，未宣称保存成功")
        return false
    end
    local savedOk, saved = pcall(options_.flush)
    if savedOk and saved == true and current == session_ and currentStory() then
        pendingSave_ = false
        return true
    end
    print("[SamsaraRescueLedger] 回执仍在内存，Flush失败，等待两秒重试")
    return false
end

local function validReceipt(receipt)
    if type(receipt) ~= "table" or receipt.schemaVersion ~= 1 or receipt.source ~= SOURCE
        or receipt.scope ~= "single_scene" or receipt.recoveryComplete ~= true
        or not integer(receipt.failedStageId) or not integer(receipt.recoveredStageId)
        or not StageConfig.getStage(receipt.failedStageId)
        or not StageConfig.getStage(receipt.recoveredStageId)
        or StageConfig.isTerminalTemple(receipt.failedStageId)
        or StageConfig.isTerminalTemple(receipt.recoveredStageId)
        or (receipt.recoveredStageId ~= receipt.failedStageId
            and receipt.recoveredStageId ~= StageConfig.getPrevStageId(receipt.failedStageId))
        or type(receipt.heroIds) ~= "table" then return false end
    local count, seen = 0, {}
    for index, id in pairs(receipt.heroIds) do
        if not integer(index) or index > 4 or not integer(id) or seen[id] then return false end
        count, seen[id] = count + 1, true
    end
    if count < 1 or count > 4 or count ~= #receipt.heroIds then return false end
    for index = 1, count do if receipt.heroIds[index] == nil then return false end end
    return true
end

local function copyReceipt(receipt)
    local heroes = {}; for index, id in ipairs(receipt.heroIds) do heroes[index] = id end
    return { schemaVersion = 1, source = SOURCE, scope = "single_scene",
        failedStageId = receipt.failedStageId, recoveredStageId = receipt.recoveredStageId,
        heroIds = heroes, recoveryComplete = true }
end

--- 仅宿主的真实失败瞬间取得进程票据，票据本身不进入存档。
---@return table?
function Ledger.capture()
    local story = currentStory()
    if not story then return nil end
    local ticket = {}
    tickets_[ticket] = { session = session_, story = story, domain = story.rescueLedger }
    return ticket
end

--- 必须与失败端的同一张票匹配；任意旧广播或复制票据都不能登记回执。
---@param ticket table?
---@param receipt SamsaraRescueReceipt
---@return boolean accepted
function Ledger.commit(ticket, receipt)
    if type(ticket) ~= "table" then return false end
    local captured = tickets_[ticket]
    tickets_[ticket] = nil
    local story = currentStory()
    if not captured or not story or captured.session ~= session_ or captured.story ~= story
        or captured.domain ~= story.rescueLedger or not validReceipt(receipt) then return false end
    local domain = story.rescueLedger
    if domain and domain.firstReceipt ~= nil then
        -- 首份实际经历冻结；异常或未来内容也不覆盖成另一份经历。
        return false
    end
    if not domain then
        domain = { schemaVersion = 1, coverage = "unknown", scope = "single_scene" }
        story.rescueLedger = domain
    end
    domain.firstReceipt = copyReceipt(receipt)
    pendingSave_ = true
    print("[SamsaraRescueLedger] 已确认非终焉全灭恢复完成，登记首份单场回执")
    flushPending()
    return true
end

---@return SamsaraRescueReceipt?
function Ledger.getReceipt()
    local story = currentStory()
    local domain = story and story.rescueLedger
    local receipt = domain and domain.firstReceipt
    if not validReceipt(receipt) then return nil end
    return copyReceipt(receipt)
end

--- 单场来源没有覆盖全部战斗路径；无回执不得返回可信阴性。
---@return string
function Ledger.getExperience()
    return Ledger.getReceipt() and "rescued" or "unknown"
end

---@param dt number
function Ledger.update(dt)
    if not pendingSave_ or type(dt) ~= "number" or dt ~= dt or dt < 0 or dt == math.huge then return end
    retryElapsed_ = retryElapsed_ + dt
    if retryElapsed_ >= 2 then flushPending() end
end

function Ledger.isSavePending() return pendingSave_ end

return Ledger
