-- ============================================================================
-- TalentService - 天赋业务逻辑
-- 职责: 天赋节点激活/重置校验与修改（纯业务，禁止网络 IO）
-- 层级: server/talent  |  通过 PDM 读写数据
-- 说明: 使用 shared/talent/TalentNodeDefs 做邻接校验（不再依赖 ui/TalentStarMap）
-- ============================================================================

local PDM            = require("rules.character.PlayerDataManager")
local TalentNodeDefs = require("shared.talent.TalentNodeDefs")
local TalentsSchema  = require("shared.talents.TalentsSchema")
local SuccessContext = require("shared.SuccessNotificationContext")

local TalentService = {}

--- 确保天赋模块结构合法
---@param talents table|nil
---@return table|nil
local function ensureTalents(talents)
    if talents then
        TalentsSchema.normalizeModule(talents)
    end
    return talents
end

--- 节点 ID 相等比较（兼容 string/number）
---@param a any
---@param b any
---@return boolean
local function sameNodeId(a, b)
    return tonumber(a) == tonumber(b)
end

-- 计划阶段只决定本次操作；不缓存 PDM 函数或节点表的动态字段。
-- normalizeModule 仍在入口执行（包括拒绝请求），不属于可回滚的计划。
---@param talents table
---@param player table
---@param nodeId any
---@return table|nil plan
---@return string|nil reason
local function planActivation(talents, player, nodeId)
    nodeId = tonumber(nodeId)
    if nodeId == nil then
        return nil, "参数缺失: nodeId"
    end

    -- 校验节点存在（使用 shared 层纯数据定义）
    local nodeCfg = TalentNodeDefs.getNode(nodeId)
    if not nodeCfg then
        return nil, "无效的天赋节点: " .. tostring(nodeId)
    end

    -- 校验未被点亮
    local litSet = {}
    for _, id in ipairs(talents.litNodes) do
        litSet[tonumber(id) or id] = true
    end
    if litSet[nodeId] then
        return nil, "该天赋已激活"
    end

    -- 邻接校验：至少有一个相邻节点已点亮
    local hasAdjacentLit = false
    for _, adjId in ipairs(nodeCfg.adj) do
        if litSet[adjId] then
            hasAdjacentLit = true
            break
        end
    end
    if not hasAdjacentLit then
        return nil, "需要先激活相邻天赋"
    end

    -- 天赋点校验：剩余点数 = 远征等级 - 已用点数（node 0 不消耗）
    local usedPoints = #talents.litNodes - 1
    local maxPoints  = player.level or 1
    local remaining  = maxPoints - usedPoints
    if remaining <= 0 then
        return nil, "远征点不足"
    end

    return { nodeId = nodeId, nodeCfg = nodeCfg, usedPoints = usedPoints, maxPoints = maxPoints }
end

--- 检查移除后的连通性；逐次现读 getNode，保留原 BFS 的遍历顺序。
---@param litSet table
---@param nodeId number
---@return boolean
local function remainsConnected(litSet, nodeId)
    -- BFS：移除后从起始点 0 出发，其余已点亮节点仍可达
    local remainSet = {}
    for id, _ in pairs(litSet) do
        if not sameNodeId(id, nodeId) then remainSet[id] = true end
    end
    local visited = {}
    local queue = { 0 }
    visited[0] = true
    while #queue > 0 do
        local cur = table.remove(queue, 1)
        local curCfg = TalentNodeDefs.getNode(cur)
        if curCfg then
            for _, adjId in ipairs(curCfg.adj) do
                local aid = tonumber(adjId) or adjId
                if remainSet[aid] and not visited[aid] then
                    visited[aid] = true
                    queue[#queue + 1] = aid
                end
            end
        end
    end
    for id, _ in pairs(remainSet) do
        if not visited[id] then
            return false
        end
    end

    return true
end

---@param talents table
---@param nodeId any
---@return table|nil plan
---@return string|nil reason
local function planDeactivation(talents, nodeId)
    nodeId = tonumber(nodeId)
    if nodeId == nil then
        return nil, "参数缺失: nodeId"
    end

    -- 起始点不允许重置
    if nodeId == 0 then
        return nil, "起始点不允许重置"
    end

    -- 校验节点存在
    local nodeCfg = TalentNodeDefs.getNode(nodeId)
    if not nodeCfg then
        return nil, "无效的天赋节点: " .. tostring(nodeId)
    end

    -- 构建已点亮集合
    local litSet = {}
    local litIndex = nil
    for i, id in ipairs(talents.litNodes) do
        local nid = tonumber(id) or id
        litSet[nid] = true
        if sameNodeId(id, nodeId) then
            litIndex = i
        end
    end

    -- 校验该节点已点亮
    if not litIndex then
        return nil, "该天赋未激活，无法重置"
    end

    -- 校验是末尾节点（叶子）：只有 1 个已点亮邻居
    local litAdjCount = 0
    for _, adjId in ipairs(nodeCfg.adj) do
        if litSet[tonumber(adjId) or adjId] then
            litAdjCount = litAdjCount + 1
        end
    end
    if litAdjCount > 1 then
        return nil, "该天赋不是末尾节点，无法单独重置"
    end

    if not remainsConnected(litSet, nodeId) then
        return nil, "移除该节点会断开天赋树连通性"
    end

    return { nodeId = nodeId, nodeCfg = nodeCfg, litIndex = litIndex }
end

--- 发布已经发生的修改。MarkDirty 可同步重入，FlushImmediate 必须在其后现读；
--- 不捕获异常、不回滚，也不把 flush 的返回值改成业务成功条件。
---@param uid number
local function publishTalents(uid)
    PDM.MarkDirty(uid, "talents")
    PDM.FlushImmediate(uid)
end

--- 激活成功的通知上下文只包围首次权威 MarkDirty；失败仍原样抛出。
---@param talents table
---@param uid number
local function publishActivation(talents, uid)
    SuccessContext.withNotification(talents, "talents", "talent_activate", function()
        PDM.MarkDirty(uid, "talents")
    end)
    PDM.FlushImmediate(uid)
end

--- 激活天赋节点（消耗 1 天赋点）
---@param uid number
---@param nodeId number
---@return boolean ok
---@return string|nil errReason
---@return table|nil result { nodeId }
function TalentService.Activate(uid, nodeId)
    local talents = ensureTalents(PDM.GetModule(uid, "talents"))
    local player  = PDM.GetModule(uid, "player")
    if not talents or not player then
        return false, "数据未加载"
    end

    local plan, reason = planActivation(talents, player, nodeId)
    if not plan then return false, reason end

    -- 只在全部校验通过后修改，沿用当时 talents.litNodes 的引用。
    table.insert(talents.litNodes, plan.nodeId)
    publishActivation(talents, uid)

    print("[TalentService] Activate uid=" .. tostring(uid)
        .. " nodeId=" .. tostring(plan.nodeId)
        .. " name=" .. (plan.nodeCfg.name or "?")
        .. " used=" .. (plan.usedPoints + 1) .. "/" .. plan.maxPoints)

    return true, nil, { nodeId = plan.nodeId }
end

--- 重置单个末尾天赋节点（恢复 1 天赋点）
--- 末尾节点定义：已点亮子图的叶子节点（只有 1 个已点亮邻居），移除后不会断开连通性
---@param uid number
---@param nodeId number
---@return boolean ok
---@return string|nil errReason
function TalentService.DeactivateSingle(uid, nodeId)
    local talents = ensureTalents(PDM.GetModule(uid, "talents"))
    if not talents then
        return false, "数据未加载"
    end

    local plan, reason = planDeactivation(talents, nodeId)
    if not plan then return false, reason end

    table.remove(talents.litNodes, plan.litIndex)
    publishTalents(uid)

    print("[TalentService] DeactivateSingle uid=" .. tostring(uid)
        .. " nodeId=" .. tostring(plan.nodeId)
        .. " name=" .. (plan.nodeCfg.name or "?"))

    return true
end

--- 重置全部天赋（恢复天赋点）
---@param uid number
---@return boolean ok
---@return string|nil errReason
function TalentService.ResetAll(uid)
    local talents = ensureTalents(PDM.GetModule(uid, "talents"))
    if not talents then
        return false, "数据未加载"
    end

    local oldCount = #talents.litNodes
    -- 重置与增删不同：必须替换数组，不能原位清空外部持有的旧引用。
    talents.litNodes = { 0 }
    publishTalents(uid)

    print("[TalentService] ResetAll uid=" .. tostring(uid)
        .. " cleared " .. oldCount .. " nodes")

    return true
end

return TalentService
