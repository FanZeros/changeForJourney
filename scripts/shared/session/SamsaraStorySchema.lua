-- SamsaraStorySchema.lua — 只规范 session.samsaraStory，不迁移旧领奖/教程账本。
-- 未知字段、未知节点及未来版本原样保留，规范化可重复调用。

---@class SamsaraStoryNode
---@field eligible boolean?
---@field eligibilitySource string?
---@field contentVersion number?
---@field resolution string?
---@field legacyContext string?

---@class SamsaraStoryEvidenceState
---@field unlocked boolean?
---@field source string?

---@class SamsaraStoryState
---@field schemaVersion number
---@field historyCaptured boolean
---@field nodes table<string, SamsaraStoryNode>
---@field evidence table<string, SamsaraStoryEvidenceState>

local Schema = {}
local NODE_KEY = "samsara.log_leaf"

---@return SamsaraStoryState
function Schema.new()
    return { schemaVersion = 1, historyCaptured = false, nodes = {}, evidence = {} }
end

--- 不对字符串布尔值做宽松转换，尤其不能把 "false" 当作资格或已捕获。
---@param session table
---@return SamsaraStoryState story
---@return boolean supported
function Schema.normalize(session)
    local story = session.samsaraStory
    if type(story) ~= "table" then
        story = Schema.new()
        session.samsaraStory = story
    end
    -- 未来版本在任何修复之前退出；连缺省字段也不补，保全其原始结构。
    local version = tonumber(story.schemaVersion)
    if version and version > 1 then return story, false end
    story.schemaVersion = 1
    story.historyCaptured = story.historyCaptured == true
    if type(story.nodes) ~= "table" then story.nodes = {} end
    if type(story.evidence) ~= "table" then story.evidence = {} end

    local node = story.nodes[NODE_KEY] --[[@as SamsaraStoryNode?]]
    if node ~= nil and type(node) ~= "table" then
        story.nodes[NODE_KEY] = nil
    elseif node then
        local contentVersion = tonumber(node.contentVersion)
        -- 未来内容版本同样不可被当前字段修复抹掉。
        if not contentVersion or contentVersion <= 1 then
            node.contentVersion = 1
            if node.eligible ~= nil then node.eligible = node.eligible == true end
            if node.resolution ~= "finished" and node.resolution ~= "skipped" then node.resolution = nil end
            if type(node.eligibilitySource) ~= "string" then node.eligibilitySource = nil end
            if type(node.legacyContext) ~= "string" then node.legacyContext = nil end
        end
    end
    local evidence = story.evidence.E01 --[[@as SamsaraStoryEvidenceState?]]
    if evidence ~= nil and type(evidence) ~= "table" then
        story.evidence.E01 = nil
    elseif evidence then
        if evidence.unlocked ~= nil then evidence.unlocked = evidence.unlocked == true end
        if type(evidence.source) ~= "string" then evidence.source = nil end
    end
    return story, true
end

return Schema
