-- ============================================================================
-- TalentEffect - 天赋星图效果解析器
-- 解析 effect 描述字符串为属性加成条目，并应用到 UnitAttributes
-- ============================================================================

local AD = require("systems.AttributeDef")

local TE = {}

-- ======================== 属性名 → Key 映射 ========================
-- 从 AD.META 动态构建（中文显示名 → AD key）

local NAME_TO_KEY = {}
local SORTED_NAMES = {}   -- 按字节长度降序（贪心匹配）

for key, meta in pairs(AD.META) do
    if meta.name then
        NAME_TO_KEY[meta.name] = key
    end
end

for name, _ in pairs(NAME_TO_KEY) do
    SORTED_NAMES[#SORTED_NAMES + 1] = name
end
table.sort(SORTED_NAMES, function(a, b) return #a > #b end)

-- ======================== 职业名 → classId ========================

local CLASS_NAME_TO_ID = {
    ["骑士"] = "knight",
    ["战士"] = "warrior",
    ["法师"] = "mage",
    ["射手"] = "ranger",
    ["刺客"] = "assassin",
    ["牧师"] = "priest",
}

-- ======================== 纯运行时节点（完全跳过） ========================

local RUNTIME_ONLY = {
    [0]   = true,   -- 起始节点，无属性效果
    [113] = true,   -- 魔法伤害概率触发 debuff
    [115] = true,   -- 暴击时基于目标已损失 HP 的伤害加成
    [125] = true,   -- 免疫致命伤害
    [126] = true,   -- 击杀后攻速 buff
    [128] = true,   -- 概率全队伤害加成 buff
}

-- 混合节点：既有静态属性段，也有运行时特殊效果；静态属性需要解析，运行时效果仍计固定战力
local RUNTIME_POWER_ONLY = {
    [124] = true,   -- 溢出治疗转能量护盾（TalentManager 运行时处理）
}

-- RUNTIME_ONLY 节点的固定战力估值（按节点尺寸 sizeType）
-- 这些节点不提供静态属性加成，但仍应贡献战力
local RUNTIME_COMBAT_POWER = {
    small  = 4,
    medium = 8,
    large  = 15,
}

-- ======================== 运行时描述标记 ========================
-- 用于检测 "；" 分隔后的子段落是否为运行时效果

local NARRATIVE_PATTERNS = {
    "当前生命值",     -- 117: 生命值低于50%时...
    "连续攻击",       -- 120: 连续攻击同一目标时...
    "溢出的治疗",     -- 124: 溢出的治疗量转化为...
}

--- 检查文本是否为运行时描述（非静态属性加成）
local function isNarrativeText(text)
    for _, pat in ipairs(NARRATIVE_PATTERNS) do
        if text:find(pat, 1, true) then return true end
    end
    return false
end

-- ======================== UTF-8 安全的字符串分割 ========================

--- 按多个分隔符做纯文本分割（不使用 Lua 字符类，避免多字节 UTF-8 被拆断）
---@param str string 待分割的字符串
---@param delimiters string[] 分隔符列表（纯文本，如 {"；"} 或 {"，", ",", " "}）
---@return string[] 分割后的非空片段列表
local function splitByDelimiters(str, delimiters)
    local results = {}
    local pos = 1
    local len = #str
    while pos <= len do
        -- 在当前位置查找最早出现的分隔符
        local earliestStart, earliestEnd = nil, nil
        for _, delim in ipairs(delimiters) do
            local s, e = str:find(delim, pos, true)  -- plain text find
            if s and (not earliestStart or s < earliestStart) then
                earliestStart, earliestEnd = s, e
            end
        end
        if earliestStart then
            local segment = str:sub(pos, earliestStart - 1)
            if #segment > 0 then
                results[#results + 1] = segment
            end
            pos = earliestEnd + 1
        else
            local segment = str:sub(pos)
            if #segment > 0 then
                results[#results + 1] = segment
            end
            break
        end
    end
    return results
end

-- ======================== 单原子解析 ========================

--- 解析单个属性原子，如 "敏捷+1"、"暴击率+2.5%"、"生命值-20"
---@param atom string 去除前缀后的原子文本
---@return table|nil {key=string, flat=number} 或 {key=string, pct=number}
local function parseAtom(atom)
    -- 贪心匹配：遍历按长度降序排列的属性名
    local matchedName = nil
    local matchedKey = nil
    for _, name in ipairs(SORTED_NAMES) do
        if atom:find(name, 1, true) == 1 then
            matchedName = name
            matchedKey = NAME_TO_KEY[name]
            break
        end
    end
    if not matchedKey then return nil end

    -- 提取数值：属性名之后的 [+-]数字[.数字][%]
    local rest = atom:sub(#matchedName + 1)
    local sign, numStr, pctSign = rest:match("^([+-])([%d%.]+)(%%?)$")
    if not numStr then return nil end

    local value = tonumber(numStr)
    if not value then return nil end
    if sign == "-" then value = -value end

    local meta = AD.getMeta(matchedKey)
    if not meta then return nil end

    if pctSign == "%" then
        if meta.dataType == AD.TYPE_PCT then
            -- 百分比属性 + %：加百分点（flat）
            -- 例: 暴击率+2.5% → critRate 是 TYPE_PCT → flat=2.5
            return { key = matchedKey, flat = value }
        else
            -- 非百分比属性 + %：百分比乘算（pct）
            -- 例: 仇恨值+15% → threat 是 TYPE_INT → pct=15
            return { key = matchedKey, pct = value }
        end
    else
        -- 无 %：直接数值加成（flat）
        return { key = matchedKey, flat = value }
    end
end

-- ======================== 效果字符串解析 ========================

--- 解析单个节点的 effect 字符串
---@param effectStr string 效果描述
---@param classId string|nil 英雄职业 ID（用于职业限定效果）
---@return table[] entries 属性条目列表 { {key, flat/pct}, ... }
function TE.parseEffect(effectStr, classId)
    if not effectStr or effectStr == "" then return {} end

    local entries = {}

    -- 按 "；" 分段（大段落：全体加成 vs 职业/条件效果）
    -- 注意：不能用 gmatch("[^；]+")，因为 Lua 按字节匹配会拆断 UTF-8 字符
    local segments = splitByDelimiters(effectStr, {"；"})

    for _, seg in ipairs(segments) do
        local trimmed = seg:match("^%s*(.-)%s*$") or seg

        -- 跳过运行时描述
        if isNarrativeText(trimmed) then
            goto continue_seg
        end

        -- 检测职业限定：[职业名]职业额外获得...
        local className, bonus = trimmed:match("^%[(.-)%]职业额外获得(.+)$")
        if className then
            local classReq = CLASS_NAME_TO_ID[className]
            if classReq and classId == classReq and bonus then
                local bonusAtoms = splitByDelimiters(bonus, {"，", ",", " "})
                for _, atom in ipairs(bonusAtoms) do
                    local stripped = atom:gsub("^全体", ""):gsub("^冒险家", "")
                    local entry = parseAtom(stripped)
                    if entry then entries[#entries + 1] = entry end
                end
            end
            goto continue_seg
        end

        -- 普通段落：按 "，"、英文逗号、空格分隔
        local atoms = splitByDelimiters(trimmed, {"，", ",", " "})
        for _, atom in ipairs(atoms) do
            -- 去除常见前缀
            local stripped = atom:gsub("^全体", ""):gsub("^冒险家", ""):gsub("^但", "")
            local entry = parseAtom(stripped)
            if entry then
                entries[#entries + 1] = entry
            end
        end

        ::continue_seg::
    end

    return entries
end

-- ======================== 聚合与应用 ========================

--- 收集所有已点亮节点的属性加成条目
---@param litNodes table 已点亮节点 ID 列表（数组形式，如 {0, 1, 2, 5}）
---@param classId string|nil 英雄职业 ID
---@return table[] 聚合后的属性条目列表
function TE.collectEntries(litNodes, classId)
    if not litNodes then return {} end

    -- 延迟加载 TalentStarMap（避免循环依赖）
    local TSM = require("ui.TalentStarMap")

    local entries = {}
    for _, nodeId in ipairs(litNodes) do
        if not RUNTIME_ONLY[nodeId] then
            local node = TSM.getNode(nodeId)
            if node and node.effect then
                local nodeEntries = TE.parseEffect(node.effect, classId)
                for _, e in ipairs(nodeEntries) do
                    entries[#entries + 1] = e
                end
            end
        end
    end
    return entries
end

--- 将天赋星图加成应用到 UnitAttributes
---@param attrs table UnitAttributes 实例
---@param litNodes table 已点亮节点 ID 列表
---@param classId string|nil 英雄职业 ID
function TE.applyToUnit(attrs, litNodes, classId)
    local entries = TE.collectEntries(litNodes, classId)
    if #entries > 0 then
        attrs:addModifier("talent_starmap", entries)
    end
end

--- 计算已点亮的 RUNTIME_ONLY 节点的固定战力总和（单个角色的份额）
--- 这些节点不提供静态属性加成，无法通过 valueModel 计算，需额外累加
---@param litNodes table 已点亮节点 ID 列表（数组形式）
---@return number 固定战力总和
function TE.calcRuntimeOnlyPower(litNodes)
    if not litNodes then return 0 end

    local TSM = require("ui.TalentStarMap")
    local total = 0
    for _, nodeId in ipairs(litNodes) do
        if RUNTIME_ONLY[nodeId] or RUNTIME_POWER_ONLY[nodeId] then
            local node = TSM.getNode(nodeId)
            if node then
                local cp = RUNTIME_COMBAT_POWER[node.st] or 0
                total = total + cp
            end
        end
    end
    return total
end

--- 格式化聚合后的属性条目
---@param key string
---@param vals table { flat=number, pct=number }
---@return string|nil label
---@return string|nil text
local function formatAggregatedStat(key, vals)
    local meta = AD.getMeta(key)
    if not meta then return nil, nil end

    local flat = vals.flat or 0
    local pct = vals.pct or 0
    if flat == 0 and pct == 0 then return nil, nil end

    if pct ~= 0 then
        return meta.name, string.format("%+.1f%%", pct)
    end
    if meta.dataType == AD.TYPE_PCT then
        return meta.name, string.format("%+.1f%%", flat)
    end
    if meta.dataType == AD.TYPE_INT then
        return meta.name, string.format("%+.0f", flat)
    end
    return meta.name, string.format("%+.2f", flat)
end

--- 构建已点亮天赋的效果总览（属性聚合 + 职业专属 + 特殊效果）
---@param litNodes table|nil 已点亮节点 ID 列表
---@return table { stats={label,text,sortKey}[], classBonuses={className,text}[], specials={name,text}[] }
function TE.buildOverview(litNodes)
    local TSM = require("ui.TalentStarMap")
    local statsAgg = {}
    local classBonuses = {}
    local specials = {}
    local seenSpecial = {}

    local function addSpecial(name, text)
        if not text or text == "" then return end
        local dedupeKey = tostring(name) .. "|" .. text
        if seenSpecial[dedupeKey] then return end
        seenSpecial[dedupeKey] = true
        specials[#specials + 1] = { name = name, text = text }
    end

    for _, nodeId in ipairs(litNodes or {}) do
        if nodeId ~= 0 then
            local node = TSM.getNode(nodeId)
            if node and node.effect then
                local effectStr = node.effect

                if RUNTIME_ONLY[nodeId] then
                    addSpecial(node.name, effectStr)
                else
                    local segments = splitByDelimiters(effectStr, {"；"})
                    for si, seg in ipairs(segments) do
                        local trimmed = seg:match("^%s*(.-)%s*$") or seg
                        local className, bonus = trimmed:match("^%[(.-)%]职业额外获得(.+)$")
                        if className and bonus then
                            classBonuses[#classBonuses + 1] = {
                                className = className,
                                text = bonus,
                            }
                        elseif si > 1 then
                            addSpecial(node.name, trimmed)
                        end
                    end
                end
            end
        end
    end

    for _, entry in ipairs(TE.collectEntries(litNodes, nil)) do
        local key = entry.key
        if not statsAgg[key] then
            statsAgg[key] = { flat = 0, pct = 0 }
        end
        if entry.pct then
            statsAgg[key].pct = statsAgg[key].pct + entry.pct
        else
            statsAgg[key].flat = statsAgg[key].flat + (entry.flat or 0)
        end
    end

    local stats = {}
    for key, vals in pairs(statsAgg) do
        local label, text = formatAggregatedStat(key, vals)
        if label and text then
            stats[#stats + 1] = { label = label, text = text, sortKey = key }
        end
    end
    table.sort(stats, function(a, b)
        return (a.sortKey or "") < (b.sortKey or "")
    end)

    return {
        stats = stats,
        classBonuses = classBonuses,
        specials = specials,
    }
end

return TE
