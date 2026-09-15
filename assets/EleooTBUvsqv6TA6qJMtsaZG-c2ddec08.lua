-- ============================================================================
-- RelicAffix.lua — 遗物词缀计算逻辑
-- 负责：候选池筛选、加权随机、文本解析、数值提取
-- ============================================================================

local RelicDefs = require("data.RelicDefs")

---@class RelicAffix
local RelicAffix = {}

-- ======================== 候选池筛选 ========================

--- 获取符合条件的候选词缀池
--- 筛选规则：
---   1. 词缀所属分类包含当前遗物类型
---   2. 词缀最低等级 <= 遗物等级
---   3. 词缀在当前品质有值（非nil）
---@param relicType number 遗物类型 1~5
---@param quality number 品质 1~6
---@param level number 遗物等级
---@return {id:number, weight:number}[] 候选列表（id+权重）
function RelicAffix.getCandidatePool(relicType, quality, level)
    local pool = {}
    for id, affix in pairs(RelicDefs.AFFIXES) do
        -- 条件1: 类型匹配
        local typeMatch = false
        for _, t in ipairs(affix.types) do
            if t == relicType then
                typeMatch = true
                break
            end
        end
        if not typeMatch then goto continue end

        -- 条件2: 等级门槛
        if affix.minLevel > level then goto continue end

        -- 条件3: 该品质有值
        if affix.values[quality] == nil then goto continue end

        pool[#pool + 1] = { id = id, weight = affix.weight }

        ::continue::
    end
    return pool
end

-- ======================== 加权随机 ========================

--- 从候选池中按权重随机抽取一条词缀ID
---@param pool {id:number, weight:number}[] 候选池
---@return number|nil 词缀ID，池为空返回nil
function RelicAffix.weightedRandom(pool)
    if #pool == 0 then return nil end

    local totalWeight = 0
    for _, entry in ipairs(pool) do
        totalWeight = totalWeight + entry.weight
    end

    if totalWeight <= 0 then return nil end

    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, entry in ipairs(pool) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            return entry.id
        end
    end

    -- 浮点精度兜底：返回最后一个
    return pool[#pool].id
end

-- ======================== 核心接口 ========================

--- 随机生成一条合法词缀
--- 用于新获取遗物、洗练、合成后的词缀分配
---@param relicType number 遗物类型 1~5
---@param quality number 品质 1~6
---@param level number 遗物等级
---@param excludeAffixId number|nil 需排除的词缀ID（洗练时排除当前词缀）
---@param maxRetries number|nil 去重最大重试次数（默认10）
---@return number|nil 词缀ID，无合法候选返回nil
function RelicAffix.rollAffix(relicType, quality, level, excludeAffixId, maxRetries)
    local pool = RelicAffix.getCandidatePool(relicType, quality, level)
    if #pool == 0 then return nil end

    maxRetries = maxRetries or 10

    -- 如果需要排除，且候选池只有1个且就是被排除的，直接返回nil
    if excludeAffixId and #pool == 1 and pool[1].id == excludeAffixId then
        return nil
    end

    for _ = 1, maxRetries do
        local affixId = RelicAffix.weightedRandom(pool)
        if affixId == nil then return nil end
        if affixId ~= excludeAffixId then
            return affixId
        end
    end

    -- 重试耗尽，从池中移除被排除的词缀后再抽一次
    local filteredPool = {}
    for _, entry in ipairs(pool) do
        if entry.id ~= excludeAffixId then
            filteredPool[#filteredPool + 1] = entry
        end
    end
    return RelicAffix.weightedRandom(filteredPool)
end

--- 获取词缀显示文本
---@param affixId number|nil 词缀ID
---@param quality number 品质 1~6
---@return string 词缀文本，无效返回空串
function RelicAffix.getAffixText(affixId, quality)
    if not affixId then return "" end
    return RelicDefs.getAffixText(affixId, quality) or ""
end

--- 获取洗练可能出现的词缀显示文本（不含权重/概率）
---@param relicType number 遗物类型 1~5
---@param quality number 品质 1~6
---@param level number 遗物等级
---@param excludeAffixId number|nil 洗练时排除当前词缀
---@return string[] 按文本排序的词缀列表
function RelicAffix.getReforgeAffixTexts(relicType, quality, level, excludeAffixId)
    local pool = RelicAffix.getCandidatePool(relicType, quality, level)
    local texts = {}
    for _, entry in ipairs(pool) do
        if not excludeAffixId or entry.id ~= excludeAffixId then
            local text = RelicAffix.getAffixText(entry.id, quality)
            if text ~= "" then
                texts[#texts + 1] = text
            end
        end
    end
    table.sort(texts)
    return texts
end

-- ======================== 数值解析 ========================

--- 从词缀文本中提取数值和类型信息
--- 用于属性计算系统消费
--- 返回结构:
---   { raw=原始文本, value=数值, isPercent=是否百分比,
---     attr=属性名, target=作用目标, condition=触发条件 }
---@param affixId number 词缀ID
---@param quality number 品质 1~6
---@return table|nil 解析结果
function RelicAffix.parseAffixValue(affixId, quality)
    local text = RelicAffix.getAffixText(affixId, quality)
    if text == "" then return nil end

    local result = { raw = text, value = 0, isPercent = false, attr = "", target = "全体", condition = nil }

    -- 提取职业限定目标: [骑士], [战士], [刺客与法师] 等
    local classTarget = text:match("^%[([^%]]+)%]")
    if classTarget then
        result.target = classTarget
    end

    -- 提取条件类词缀: "xxx时，" "xxx，" 前置条件
    local condPattern = "([^，,]+时)，"
    local cond = text:match(condPattern)
    if cond then
        result.condition = cond
    end

    -- 提取数值: 匹配最后一个 +数字 或 -数字 (含百分比)
    -- 支持格式: +80, +6%, -5%, +15
    local sign, numStr, pct = text:match("([%+%-])(%d+)(%%?)%s*$")
    if not numStr then
        -- 兜底：匹配文本中最后出现的数字+百分号模式
        sign, numStr, pct = text:match("([%+%-])(%d+)(%%?)")
    end

    if numStr then
        result.value = tonumber(numStr) or 0
        if sign == "-" then
            result.value = -result.value
        end
        result.isPercent = (pct == "%")
    end

    -- 提取属性名: 介于目标/条件 和 +/- 之间的文本
    -- 例: "全体护甲+3" → attr="护甲"
    -- 例: "[骑士]生命加成+29%" → attr="生命加成"
    local attrText = text
    -- 移除前缀 [xxx]
    attrText = attrText:gsub("^%[[^%]]+%]", "")
    -- 移除条件部分
    if result.condition then
        local escapedCond = result.condition:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        attrText = attrText:gsub(escapedCond .. "，?", "")
    end
    -- 提取属性名（到 +/- 之前）
    local attrName = attrText:match("^(.-)%s*[%+%-]%d")
    if attrName and attrName ~= "" then
        result.attr = attrName
    else
        result.attr = attrText
    end

    return result
end

-- ======================== 批量属性汇总 ========================

--- 解析多个遗物的词缀并按属性分类汇总
--- 用于 RelicSystem.calcStats() 调用
---@param relics {affixId:number|nil, quality:number}[] 遗物列表
---@return {flat:table<string,number>, percent:table<string,number>, conditional:table[]}
function RelicAffix.summarizeStats(relics)
    local flat = {}      -- 固定值加成: attr → 累计值
    local percent = {}   -- 百分比加成: attr → 累计值
    local conditional = {} -- 条件类加成列表

    for _, relic in ipairs(relics) do
        if relic.affixId then
            local parsed = RelicAffix.parseAffixValue(relic.affixId, relic.quality)
            if parsed and parsed.value ~= 0 then
                if parsed.condition then
                    -- 条件类词缀存完整信息，供战斗系统动态判断
                    conditional[#conditional + 1] = parsed
                elseif parsed.isPercent then
                    local key = (parsed.target or "全体") .. parsed.attr
                    percent[key] = (percent[key] or 0) + parsed.value
                else
                    local key = (parsed.target or "全体") .. parsed.attr
                    flat[key] = (flat[key] or 0) + parsed.value
                end
            end
        end
    end

    return { flat = flat, percent = percent, conditional = conditional }
end

-- ======================== 升级箭头判断 ========================

--- 判断是否应显示"词缀可升级"箭头
--- 当玩家在同类型更高品质遗物上有相同affixId时，提示低品质遗物的词缀有升级空间
---@param affixId number 当前遗物的词缀ID
---@param quality number 当前遗物的品质
---@param allRelics {affixId:number|nil, quality:number, type:number}[] 玩家所有遗物
---@return boolean 是否有更高品质同词缀存在
function RelicAffix.canUpgrade(affixId, quality, allRelics)
    if not affixId then return false end
    for _, r in ipairs(allRelics) do
        if r.affixId == affixId and r.quality > quality then
            return true
        end
    end
    return false
end

return RelicAffix
