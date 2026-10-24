-- 详情只读准备工具：只签名战斗字段；预览小世界保留所有人的已穿项与候选。
local M = {}

function M.copy(value, checkpoint, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[key] = M.copy(item, checkpoint, seen)
        if checkpoint then checkpoint() end
    end
    return out
end

function M.signature(value)
    local parts, seen = {}, {}
    local function append(v)
        if type(v) ~= "table" then
            local text = tostring(v)
            parts[#parts + 1] = type(v) .. #text .. ":" .. text
            return
        end
        if seen[v] then parts[#parts + 1] = "cycle"; return end
        seen[v] = true
        local keys = {}
        for key in pairs(v) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            if type(a) ~= type(b) then return type(a) < type(b) end
            return tostring(a) < tostring(b)
        end)
        parts[#parts + 1] = "{"
        for _, key in ipairs(keys) do append(key); append(v[key]) end
        parts[#parts + 1] = "}"
        seen[v] = nil
    end
    append(value)
    return table.concat(parts, "|")
end

function M.heroCombat(heroes, heroId)
    heroes = heroes or {}
    local result = { teams = {}, roster = {} }
    for team = 1, 3 do
        local row = heroes.teams and (heroes.teams[team] or heroes.teams[tostring(team)])
        local slots = heroes.teams and (row and row.slots or {})
            or (team == 1 and heroes.deployed or {}) or {}
        local ids = {}
        for slot = 1, 4 do
            local id = slots[slot] or slots[tostring(slot)]
            ids[slot] = tonumber(type(id) == "table" and id.heroId or id) or false
        end
        result.teams[team] = ids
    end
    -- 数值管线只读取目标及其首个所属队；其它队升级不能取消本页评分。
    -- 队结构仍完整保留，重复编队/跨队移位与神器位置变化会使签名失效。
    local relevant = heroId and { [tonumber(heroId) or heroId] = true } or nil
    if relevant then
        for _, ids in ipairs(result.teams) do
            local containsHero = false
            for _, id in ipairs(ids) do if id == tonumber(heroId) then containsHero = true end end
            if containsHero then
                for _, id in ipairs(ids) do if id then relevant[id] = true end end
                break
            end
        end
    end
    for id, hero in pairs(heroes.roster or {}) do
        if not relevant or relevant[tonumber(id) or id] then
            result.roster[id] = { level = hero.level, advBranch = hero.advBranch,
                awakening = hero.awakening, extraTalent = hero.extraTalent }
        end
    end
    return result
end

-- 不枚举inventory。保留完整equipped映射，试穿可正确卸下跨队原持有者的装备。
-- Attrs 内部仍复制输入以保持独立容器契约，但现在每轮只复制这个小世界。
function M.compactEquipment(equipment, candidate, checkpoint, referencesOnly)
    equipment = equipment or {}
    local result = { equipped = M.copy(equipment.equipped or {}, checkpoint), inventory = {} }
    local inventory, seen = equipment.inventory or {}, {}
    local function add(seq)
        if seq == nil then return end
        local key = tostring(seq)
        if seen[key] then return end
        seen[key] = true
        local sourceKey = inventory[key] and key or (tonumber(seq) or seq)
        local item = inventory[sourceKey]
        if item then result.inventory[sourceKey] = referencesOnly and item or M.copy(item, checkpoint) end
        if checkpoint then checkpoint() end
    end
    for _, slots in pairs(result.equipped) do
        if type(slots) == "table" then for _, seq in pairs(slots) do add(seq) end end
    end
    add(candidate)
    return result
end

-- 小规模内容依赖捕获支持已穿/候选洗练与养成原地patch；未穿全集遵循equipment版本契约。
function M.dependencies(sources, candidate, heroId)
    return M.signature({ heroes = M.heroCombat(sources.heroes, heroId),
        equipment = M.compactEquipment(sources.equipment, candidate, nil, true),
        artifacts = sources.artifacts, litNodes = sources.talents and sources.talents.litNodes })
end

return M
