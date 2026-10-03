-- SamsaraStorySchema.lua — 只规范session.samsaraStory，不迁移旧领奖/教程账本。
-- 未知字段、未知节点及未来版本原样保留，规范化可重复调用。

---@class SamsaraStoryNode
---@field eligible boolean?
---@field eligibilitySource string?
---@field contentVersion number?
---@field resolution string?
---@field legacyContext string?
---@field manualOnly boolean?

---@class SamsaraStoryEvidenceState
---@field unlocked boolean?
---@field source string?
---@field annotationUnlocked boolean?
---@field continuationUnlocked boolean?
---@field peopleUnlocked boolean?

---@class SamsaraStoryState
---@field schemaVersion number
---@field historyCaptured boolean
---@field cargoHistoryCaptured boolean
---@field nodes table<string, SamsaraStoryNode>
---@field evidence table<string, SamsaraStoryEvidenceState>

local Schema = {}
local NODE_KEYS = { "samsara.log_leaf", "samsara.cargo_match", "samsara.gray_order", "samsara.people_record", "samsara.returned_manifest" }

---@return SamsaraStoryState
function Schema.new()
    return { schemaVersion = 1, historyCaptured = false, cargoHistoryCaptured = false, nodes = {}, evidence = {} }
end

--- 不对字符串布尔值做宽松转换；既有N02捕获标记不因新增节点而重置。
---@param session table
---@return SamsaraStoryState story
---@return boolean supported
function Schema.normalize(session)
    local story = session.samsaraStory
    if type(story) ~= "table" then
        story = Schema.new()
        session.samsaraStory = story
    end
    local version = tonumber(story.schemaVersion)
    if version and version > 1 then return story, false end
    story.schemaVersion = 1
    story.historyCaptured = story.historyCaptured == true
    story.cargoHistoryCaptured = story.cargoHistoryCaptured == true
    if type(story.nodes) ~= "table" then story.nodes = {} end
    if type(story.evidence) ~= "table" then story.evidence = {} end

    for _, key in ipairs(NODE_KEYS) do
        local node = story.nodes[key] --[[@as SamsaraStoryNode?]]
        if node ~= nil and type(node) ~= "table" then
            story.nodes[key] = nil
        elseif node then
            local contentVersion = tonumber(node.contentVersion)
            if not contentVersion or contentVersion <= 1 then
                node.contentVersion = 1
                if node.eligible ~= nil then node.eligible = node.eligible == true end
                if node.manualOnly ~= nil then node.manualOnly = node.manualOnly == true end
                if node.resolution ~= "finished" and node.resolution ~= "skipped" then node.resolution = nil end
                if type(node.eligibilitySource) ~= "string" then node.eligibilitySource = nil end
                if type(node.legacyContext) ~= "string" then node.legacyContext = nil end
            end
        end
    end
    for _, id in ipairs({ "E01", "E02", "E05" }) do
        local evidence = story.evidence[id] --[[@as SamsaraStoryEvidenceState?]]
        if evidence ~= nil and type(evidence) ~= "table" then
            story.evidence[id] = nil
        elseif evidence then
            for _, flag in ipairs({ "unlocked", "annotationUnlocked", "continuationUnlocked", "peopleUnlocked" }) do
                if evidence[flag] ~= nil then evidence[flag] = evidence[flag] == true end
            end
            if type(evidence.source) ~= "string" then evidence.source = nil end
        end
    end
    return story, true
end

return Schema
