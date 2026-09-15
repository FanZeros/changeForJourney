-- ============================================================================
-- RelicBridge.lua — 遗物属性桥接模块
--
-- 职责:
--   将遗物词条解析结果转换为 UnitAttributes:addModifier() 格式
--   在 CharacterPanel.getDeployedTeam() 中调用，于装备后、fillHp() 前注入
--
-- 分类:
--   A类: 无条件常驻属性（直接 addModifier）
--   B类: 条件触发属性（满血时、生命低于X%时等 → 战斗运行时处理）
--   C类: 特殊机制（概率终结、免疫次数等 → 由 BattleScene 特殊逻辑处理）
-- ============================================================================

local RelicDefs  = require("data.RelicDefs")
local RelicAffix = require("systems.RelicAffix")
local AD         = require("systems.AttributeDef")

---@class RelicBridge
local RelicBridge = {}

-- ======================== 中文属性名 → AD Key 映射 ========================

local ATTR_NAME_MAP = {
    -- 防御属性
    ["生命值"]       = AD.MAX_HP,
    ["护甲"]         = AD.PHYS_ARMOR,
    ["能量护盾"]     = AD.MAG_ARMOR,
    ["物理护甲"]     = AD.PHYS_ARMOR,   -- [兼容旧文本]
    ["魔法护甲"]     = AD.MAG_ARMOR,    -- [兼容旧文本]
    ["每秒回血"]     = AD.HP_REGEN,
    ["攻击回血"]     = AD.ATK_HEAL,
    ["闪避值"]       = AD.DODGE,
    ["闪避"]         = AD.DODGE,
    ["仇恨值"]       = AD.THREAT,
    ["物理格挡概率"] = AD.PHYS_BLOCK_RATE,
    ["魔法格挡概率"] = AD.MAG_BLOCK_RATE,
    ["物理格挡比例"] = AD.PHYS_BLOCK_RATIO,
    ["魔法格挡比例"] = AD.MAG_BLOCK_RATIO,
    ["生命加成"]     = AD.HP_BONUS,
    ["护甲加成"]     = AD.ARMOR_BONUS,
    ["能量护盾加成"] = AD.ES_BONUS,
    -- 攻击属性
    ["物理攻击力"]   = AD.PHYS_ATK,
    ["魔法攻击力"]   = AD.MAG_ATK,
    ["攻击速度"]     = AD.ATK_SPEED,
    ["暴击率"]       = AD.CRIT_RATE,
    ["暴击伤害"]     = AD.CRIT_DMG,
    ["物理暴击率"]   = AD.PHYS_CRIT_RATE,
    ["物理暴击伤害"] = AD.PHYS_CRIT_DMG,
    ["魔法暴击率"]   = AD.MAG_CRIT_RATE,
    ["魔法暴击伤害"] = AD.MAG_CRIT_DMG,
    ["物理穿透"]     = AD.PHYS_PEN,
    ["魔法穿透"]     = AD.MAG_PEN,
    ["伤害加成"]     = AD.DMG_BONUS,
    ["物理伤害加成"] = AD.PHYS_DMG_BONUS,
    ["魔法伤害加成"] = AD.MAG_DMG_BONUS,
    ["连击概率"]     = AD.COMBO_RATE,
    ["连击增伤"]     = AD.COMBO_DMG_UP,
    ["最大伤害加成"] = AD.MAX_DMG_BONUS,
    ["最小伤害加成"] = AD.MIN_DMG_BONUS,
    ["命中值"]       = AD.HIT_VALUE,
    ["物理攻击加成"] = AD.PHYS_ATK_BONUS,
    ["魔法攻击加成"] = AD.MAG_ATK_BONUS,
    -- 治疗属性
    ["治疗量"]       = AD.HEAL_AMOUNT,
    ["治疗加成"]     = AD.HEAL_BONUS,
    ["治疗增幅"]     = AD.HEAL_BONUS,  -- "牧师治疗增幅" 映射到同一个key
    ["治疗暴击率"]   = AD.HEAL_CRIT_RATE,
    ["治疗暴击加成"] = AD.HEAL_CRIT_DMG,
    -- 六围
    ["力量"]         = AD.STR,
    ["敏捷"]         = AD.AGI,
    ["智慧"]         = AD.INT,
    ["体质"]         = AD.VIT,
    ["运气"]         = AD.LUK,
    ["精神"]         = AD.SPI,
    -- 复合简称（从词缀文本中可能出现的）
    ["最大伤害"]     = AD.MAX_DMG_BONUS,
    ["最小伤害"]     = AD.MIN_DMG_BONUS,
    ["闪避加成"]     = AD.DODGE,  -- "生命值低于50%时闪避加成+210" → flat
}

-- ======================== 职业名 → classId 映射 ========================

local CLASS_NAME_MAP = {
    ["骑士"] = "knight",
    ["战士"] = "warrior",
    ["法师"] = "mage",
    ["射手"] = "ranger",
    ["刺客"] = "assassin",
    ["牧师"] = "priest",
    ["冒险家"] = "adventurer",  -- 特殊：所有英雄都属于冒险家
}

-- ======================== 特殊机制词缀ID（C类，需战斗运行时处理） ========================
-- 这些词缀无法通过简单的 addModifier 实现，需要 BattleScene 特殊逻辑

local SPECIAL_MECHANIC_AFFIXES = {
    [66] = true,   -- 攻击与造成伤害有X%概率不获得仇恨
    [67] = true,   -- 战斗开始时免疫伤害次数
    [70] = true,   -- 冒险家触发闪避时仇恨值-N
    [75] = true,   -- 造成的攻击伤害将在80%-140%之间浮动
    [78] = true,   -- 受到治疗时仇恨值-N
    [79] = true,   -- 对非[骑士]职业进行治疗时，使其仇恨值-N
    [87] = true,   -- 战斗开始时初次攻击伤害加成
    [88] = true,   -- 前N次攻击无法获得仇恨值
    [89] = true,   -- 有X%概率终结血量低于Y%的敌人
    [92] = true,   -- 在生命值首次低于30%时，在3秒内闪避值+N
}

-- ======================== 增强版词缀解析 ========================

--- 解析单条词缀，支持多属性("且"/"与"分隔)、复合词缀
--- 返回一个或多个属性条目
---@param affixId number 词缀ID
---@param quality number 品质 1~6
---@return table[] entries 解析结果列表，每项 {adKey, value, isPercent, target, condition}
function RelicBridge.parseAffix(affixId, quality)
    local text = RelicAffix.getAffixText(affixId, quality)
    if not text or text == "" then return {} end

    -- 特殊机制类直接返回特殊标记
    if SPECIAL_MECHANIC_AFFIXES[affixId] then
        return { { special = true, affixId = affixId, raw = text } }
    end

    local entries = {}

    -- 提取前缀目标: [骑士], [战士], [刺客与法师] 等
    local classTarget = text:match("^%[([^%]]+)%]")
    local targetClasses = nil  -- nil = 全体
    if classTarget then
        targetClasses = {}
        -- 处理 "刺客与法师" 这种多职业
        for className in classTarget:gmatch("[^与]+") do
            className = className:match("^%s*(.-)%s*$")  -- trim
            if CLASS_NAME_MAP[className] then
                targetClasses[#targetClasses + 1] = CLASS_NAME_MAP[className]
            end
        end
    end

    -- 检查无括号前缀的职业定向词缀（affix 5-10）
    -- 格式: "骑士伤害加成+15%", "牧师治疗增幅+24%"
    if not classTarget then
        local prefixClass = text:match("^(骑士)") or text:match("^(战士)") or
                            text:match("^(法师)") or text:match("^(射手)") or
                            text:match("^(刺客)") or text:match("^(牧师)") or
                            text:match("^(冒险家)")
        if prefixClass then
            targetClasses = { CLASS_NAME_MAP[prefixClass] }
        end
    end

    -- 提取条件
    local condition = nil
    local condPatterns = {
        "满血时",
        "生命低于(%d+)%%时",
        "生命值低于(%d+)%%时",
        "生命值首次低于(%d+)%%时",
        "血量高于(%d+)%%",
        "战斗开始时",
    }
    for _, pat in ipairs(condPatterns) do
        if text:match(pat) then
            condition = text:match("([^，,]*" .. pat .. "[^，,]*)")
            if not condition then condition = pat end
            break
        end
    end

    -- 用"且"分割多属性词缀 (affix 17: "物理格挡概率+7%且魔法格挡概率+7%")
    -- 或用中文逗号分割 (affix 71: "全体伤害最小伤害-21%，最大伤害+39%")
    -- 或用"但"分割 (affix 77: "伤害加成-5%，但生命加成+24%")
    local segments = {}
    local workText = text
    -- 移除前缀 [xxx]
    workText = workText:gsub("^%[[^%]]+%]", "")
    -- 移除条件前缀（保留后面的属性部分）
    if condition then
        local escapedCond = condition:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        workText = workText:gsub(escapedCond .. "，?", "")
    end
    -- 移除无括号的职业前缀
    workText = workText:gsub("^骑士", ""):gsub("^战士", ""):gsub("^法师", "")
                       :gsub("^射手", ""):gsub("^刺客", ""):gsub("^牧师", "")
                       :gsub("^冒险家", "")

    -- 分割
    -- 先尝试"且"分割
    if workText:find("且") then
        for seg in workText:gmatch("[^且]+") do
            segments[#segments + 1] = seg
        end
    -- 再尝试"但"分割
    elseif workText:find("但") then
        for seg in workText:gmatch("[^但]+") do
            -- 移除前导逗号
            seg = seg:gsub("^，", ""):gsub("^,", "")
            segments[#segments + 1] = seg
        end
    -- 特殊: "与"在属性名中间的情况 (affix 57: "护甲与能量护盾+8")
    elseif workText:match("(.-)与(.-)([%+%-]%d+)") then
        local attr1, attr2, valPart = workText:match("(.-)与(.-)([%+%-]%d+%%?)")
        if attr1 and attr2 then
            segments[#segments + 1] = attr1 .. valPart
            segments[#segments + 1] = attr2 .. valPart
        else
            segments[#segments + 1] = workText
        end
    -- 逗号分割多值 (affix 71: "伤害最小伤害-21%，最大伤害+39%")
    elseif workText:find("，") and workText:find("[%+%-]%d+%%?.*，.*[%+%-]%d+") then
        for seg in workText:gmatch("[^，]+") do
            segments[#segments + 1] = seg
        end
    else
        segments[#segments + 1] = workText
    end

    -- 解析每个段
    for _, seg in ipairs(segments) do
        local entry = RelicBridge._parseSegment(seg, targetClasses, condition)
        if entry then
            entries[#entries + 1] = entry
        end
    end

    return entries
end

--- 解析单个属性段（内部方法）
---@param seg string 如 "护甲+8" 或 "生命加成+29%"
---@param targetClasses string[]|nil 目标职业列表
---@param condition string|nil 触发条件
---@return table|nil {adKey, value, isPercent, targetClasses, condition}
function RelicBridge._parseSegment(seg, targetClasses, condition)
    -- 提取数值和百分比
    local sign, numStr, pct = seg:match("([%+%-])(%d+)(%%?)%s*$")
    if not numStr then
        sign, numStr, pct = seg:match("([%+%-])(%d+)(%%?)")
    end
    if not numStr then return nil end

    local value = tonumber(numStr) or 0
    if sign == "-" then value = -value end
    local isPercent = (pct == "%")

    -- 提取属性名: 数值前的文本
    local attrText = seg:match("^(.-)%s*[%+%-]%d")
    if not attrText or attrText == "" then
        -- 可能整段就是 "+8" 这种，从上下文推断
        return nil
    end
    -- 清理前后空格和前导关键词
    attrText = attrText:match("^%s*(.-)%s*$") or attrText
    -- 移除"全体"前缀（不影响目标匹配，目标由 targetClasses 控制）
    attrText = attrText:gsub("^全体", "")

    -- 映射到 AD key（先尝试完整匹配）
    local adKey = ATTR_NAME_MAP[attrText]
    -- 仅当完整匹配失败时，尝试移除"伤害"前缀（affix 71: "伤害最小伤害" → "最小伤害"）
    if not adKey and attrText:find("^伤害") then
        local stripped = attrText:gsub("^伤害", "")
        adKey = ATTR_NAME_MAP[stripped]
        if adKey then attrText = stripped end
    end
    if not adKey then
        -- 尝试部分匹配（如 "物理格挡与魔法格挡概率" 拆分后可能是 "物理格挡概率"）
        -- 此处尝试在映射表中找最长匹配
        for name, key in pairs(ATTR_NAME_MAP) do
            if attrText:find(name, 1, true) then
                adKey = key
                break
            end
        end
    end

    if not adKey then
        -- 未知属性，跳过但打印警告
        print("[RelicBridge] WARN: 未知属性名 '" .. attrText .. "' (段: " .. seg .. ")")
        return nil
    end

    return {
        adKey = adKey,
        value = value,
        isPercent = isPercent,
        targetClasses = targetClasses,
        condition = condition,
    }
end

-- ======================== 核心接口: 应用遗物到单位 ========================

--- 将已镶嵌遗物的无条件常驻属性应用到单位属性中
--- 在 CharacterPanel.getDeployedTeam() 中调用
---@param attrs table 单位属性对象（含 addModifier 方法）
---@param classId string 英雄职业ID (如 "knight", "warrior")
---@return table[] conditionalEntries 条件/特殊词条（供战斗运行时使用）
function RelicBridge.applyToUnit(attrs, classId)
    local RelicSystem = require("systems.RelicSystem")
    local grid = RelicSystem.getGrid()
    if not grid or #grid == 0 then return {} end

    local modEntries = {}      -- 无条件常驻属性 → addModifier
    local conditionalEntries = {} -- 条件类/特殊机制 → 返回给战斗系统

    for _, relic in ipairs(grid) do
        if relic.affixId then
            local parsed = RelicBridge.parseAffix(relic.affixId, relic.quality)
            for _, entry in ipairs(parsed) do
                if entry.special then
                    -- C类特殊机制
                    conditionalEntries[#conditionalEntries + 1] = entry
                elseif entry.condition then
                    -- B类条件触发
                    conditionalEntries[#conditionalEntries + 1] = entry
                else
                    -- A类无条件常驻 → 检查职业匹配
                    local classMatch = true
                    if entry.targetClasses then
                        classMatch = false
                        for _, tc in ipairs(entry.targetClasses) do
                            if tc == classId or tc == "adventurer" then
                                classMatch = true
                                break
                            end
                        end
                    end

                    if classMatch and entry.adKey and entry.value ~= 0 then
                        modEntries[#modEntries + 1] = { key = entry.adKey, flat = entry.value }
                    end
                end
            end
        end
    end

    -- 应用无条件常驻加成
    if #modEntries > 0 then
        attrs:addModifier("relic_affix", modEntries)
    end

    return conditionalEntries
end

--- 从外部提供的 grid 数据应用遗物效果到单位（竞技场对手快照用）
--- 与 applyToUnit 逻辑相同，但不依赖本地 PlayerStore
---@param attrs table @单位属性对象（含 addModifier 方法）
---@param classId string
---@param grid table[] 遗物 grid 数组 { {affixId, quality, ...}, ... }
---@return table[] conditionalEntries B/C类条件词条
function RelicBridge.applyFromGrid(attrs, classId, grid)
    if not grid or #grid == 0 then return {} end

    local modEntries = {}
    local conditionalEntries = {}

    for _, relic in ipairs(grid) do
        if relic.affixId then
            local parsed = RelicBridge.parseAffix(relic.affixId, relic.quality)
            for _, entry in ipairs(parsed) do
                if entry.special then
                    conditionalEntries[#conditionalEntries + 1] = entry
                elseif entry.condition then
                    conditionalEntries[#conditionalEntries + 1] = entry
                else
                    local classMatch = true
                    if entry.targetClasses then
                        classMatch = false
                        for _, tc in ipairs(entry.targetClasses) do
                            if tc == classId or tc == "adventurer" then
                                classMatch = true
                                break
                            end
                        end
                    end

                    if classMatch and entry.adKey and entry.value ~= 0 then
                        modEntries[#modEntries + 1] = { key = entry.adKey, flat = entry.value }
                    end
                end
            end
        end
    end

    if #modEntries > 0 then
        attrs:addModifier("relic_affix", modEntries)
    end

    return conditionalEntries
end

--- 获取所有已镶嵌遗物的条件/特殊词条（供战斗运行时初始化用）
--- 不区分职业，返回全部，由战斗系统根据单位职业做二次筛选
---@return table[] 条件/特殊词条列表
function RelicBridge.getConditionalAffixes()
    local RelicSystem = require("systems.RelicSystem")
    local grid = RelicSystem.getGrid()
    if not grid or #grid == 0 then return {} end

    local result = {}
    for _, relic in ipairs(grid) do
        if relic.affixId then
            local parsed = RelicBridge.parseAffix(relic.affixId, relic.quality)
            for _, entry in ipairs(parsed) do
                if entry.special or entry.condition then
                    result[#result + 1] = entry
                end
            end
        end
    end
    return result
end

return RelicBridge
