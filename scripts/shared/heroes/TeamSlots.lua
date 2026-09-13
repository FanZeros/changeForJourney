-- ============================================================================
-- TeamSlots.lua — 三队并行编队纯数据工具（服务端/Schema/单机路径共用）
-- 职责: heroes.teams[1..3] 的归一化、校验、写入与队1镜像同步
-- 约束: 纯函数模块，不做 IO、不打改动性日志（只读辅助除外）
--
-- 数据形态:
--   heroes.deployed = { heroId, ... }          -- 队1 兼容镜像（老代码全读它）
--   heroes.teams    = {                        -- 权威三队结构
--     [1] = { slots = { heroId, ... } },       -- 恒等于 deployed（不变式）
--     [2] = { slots = { ... } },               -- 可为空
--     [3] = { slots = { ... } },
--   }
-- 不变式（normalize 强制）:
--   1. teams[1].slots == deployed（双向镜像）
--   2. 每队 slots ≤ TEAM_MAX_SLOTS（4），元素为数字 heroId
--   3. 同一 heroId 全局只出现在一个队（队1 优先保留）
-- ============================================================================

local ExpTable = require("config.ExpTable")

local TeamSlots = {}

local TEAM_COUNT     = ExpTable.TEAM_COUNT      -- 3
local TEAM_MAX_SLOTS = ExpTable.TEAM_MAX_SLOTS  -- 4

--- 把任意值整理成"数字 heroId 数组"（去非数字、去重、截断到上限）
---@param slots any
---@return table
local function sanitizeSlots(slots)
    local out, seen = {}, {}
    if type(slots) ~= "table" then return out end
    for _, v in ipairs(slots) do
        local num = tonumber(v)
        if num and not seen[num] then
            seen[num] = true
            out[#out + 1] = num
            if #out >= TEAM_MAX_SLOTS then break end
        end
    end
    return out
end

--- 归一化 heroes.teams，并执行旧档迁移（deployed → teams[1]）
--- 幂等：任意旧/新/半迁移存档跑一遍后都满足三不变式
---@param heroes table heroes 模块数据（含 roster/deployed/teams）
---@return table heroes.teams 归一化后的 teams
function TeamSlots.normalize(heroes)
    if type(heroes) ~= "table" then return {} end
    if type(heroes.deployed) ~= "table" then heroes.deployed = {} end

    local teams = heroes.teams
    if type(teams) ~= "table" then teams = {} end

    for i = 1, TEAM_COUNT do
        local t = teams[i]
        if type(t) ~= "table" then t = {} end
        t.slots = sanitizeSlots(t.slots)
        teams[i] = t
    end

    -- 旧档迁移: teams 缺失或全空 且 deployed 非空 → deployed 前 4 人迁入队1
    local teamsEmpty = true
    for i = 1, TEAM_COUNT do
        if #teams[i].slots > 0 then teamsEmpty = false break end
    end
    if teamsEmpty and #heroes.deployed > 0 then
        teams[1].slots = sanitizeSlots(heroes.deployed)
    end

    -- 跨队去重（队1 优先保留，后出现的队让位）
    local owned = {}
    for _, id in ipairs(teams[1].slots) do owned[id] = 1 end
    for i = 2, TEAM_COUNT do
        local kept = {}
        for _, id in ipairs(teams[i].slots) do
            if not owned[id] then
                owned[id] = i
                kept[#kept + 1] = id
            end
        end
        teams[i].slots = kept
    end

    -- 不变式 1: 队1 与 deployed 双向镜像（deployed 截断到 TEAM_MAX_SLOTS）
    if #teams[1].slots > 0 then
        heroes.deployed = teams[1].slots
    else
        teams[1].slots = sanitizeSlots(heroes.deployed)
        heroes.deployed = teams[1].slots
    end

    heroes.teams = teams
    return teams
end

--- 校验一次队伍写入请求
---@param heroes table heroes 模块数据
---@param teamIdx number 目标队伍（1~3）
---@param heroIds table|nil 目标槽位（允许 nil/空 = 清空队2/3；队1 不允许空）
---@param playerLevel number 冒险等级（用于解锁校验）
---@return boolean ok
---@return string? err
function TeamSlots.validate(heroes, teamIdx, heroIds, playerLevel)
    teamIdx = tonumber(teamIdx)
    if not teamIdx or teamIdx < 1 or teamIdx > TEAM_COUNT then
        return false, "无效的队伍编号: " .. tostring(teamIdx)
    end

    local unlockedTeams = ExpTable.getUnlockedTeamCount(playerLevel or 1)
    if teamIdx > unlockedTeams then
        local needLv = ExpTable.getTeamUnlockLevel(teamIdx)
        return false, string.format("队伍%d尚未解锁（需要冒险等级%d）", teamIdx, needLv or 0)
    end

    if type(heroIds) ~= "table" or #heroIds == 0 then
        if teamIdx == 1 then
            return false, "阵容不能为空"
        end
        return true  -- 队2/3 允许清空
    end

    if #heroIds > TEAM_MAX_SLOTS then
        return false, "每队最多上阵 " .. TEAM_MAX_SLOTS .. " 人"
    end

    local seen = {}
    for _, id in ipairs(heroIds) do
        local numId = tonumber(id)
        if not numId then
            return false, "无效的 heroId"
        end
        if not heroes.roster or not heroes.roster[numId] then
            return false, "未拥有英雄: " .. tostring(numId)
        end
        if seen[numId] then
            return false, "重复的英雄: " .. tostring(numId)
        end
        seen[numId] = true
    end

    -- 跨队唯一性: 目标队之外不得出现这些英雄
    local teams = TeamSlots.normalize(heroes)
    for i = 1, TEAM_COUNT do
        if i ~= teamIdx then
            for _, id in ipairs(teams[i].slots) do
                if seen[id] then
                    return false, string.format("英雄%d已在队伍%d中", id, i)
                end
            end
        end
    end

    return true
end

--- 写入队伍槽位（写入前请先 validate）；队1 同步 deployed 镜像
---@param heroes table
---@param teamIdx number
---@param heroIds table
---@return table 写入后的 slots
function TeamSlots.setTeam(heroes, teamIdx, heroIds)
    TeamSlots.normalize(heroes)
    local slots = sanitizeSlots(heroIds)
    heroes.teams[teamIdx].slots = slots
    if teamIdx == 1 then
        heroes.deployed = slots
    end
    return slots
end

--- 查询英雄当前所在队伍
---@param heroes table
---@param heroId number
---@return number|nil teamIdx
function TeamSlots.findHeroTeam(heroes, heroId)
    local teams = heroes and heroes.teams
    if type(teams) ~= "table" then return nil end
    for i = 1, TEAM_COUNT do
        local t = teams[i]
        if type(t) == "table" and type(t.slots) == "table" then
            for _, id in ipairs(t.slots) do
                if tonumber(id) == tonumber(heroId) then
                    return i
                end
            end
        end
    end
    return nil
end

return TeamSlots
