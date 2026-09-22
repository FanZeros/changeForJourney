-- ============================================================================
-- RelicAltar.lua — 封兽祭阵规则（双端共享）
--
-- 拼图网格已废弃。遗物镶嵌到 5 兽座位 + 1 阵眼。
--   本座：兽种=座位 → 词缀 100% + 该座阵法
--   错座：词缀 50%，无该座阵法
--   对位 / 邻接只认本座
--   成阵：本座 3=小成，5=大成，5+阵眼=圆满
-- ============================================================================

local RelicDefs = require("data.RelicDefs")
local AD        = require("systems.AttributeDef")

---@class RelicAltar
local RelicAltar = {}

RelicAltar.SLOT_GUI  = "gui"
RelicAltar.SLOT_SHE  = "she"
RelicAltar.SLOT_LU   = "lu"
RelicAltar.SLOT_LANG = "lang"
RelicAltar.SLOT_YING = "ying"
RelicAltar.SLOT_CORE = "core"

RelicAltar.SLOT_ORDER = { "ying", "she", "lang", "core", "lu", "gui" }

RelicAltar.SLOTS = {
    gui  = { id = "gui",  name = "地座·龟", type = 1, unlockStage = 1305 },
    she  = { id = "she",  name = "阴座·蛇", type = 2, unlockStage = 2305 },
    lu   = { id = "lu",   name = "生座·鹿", type = 3, unlockStage = 1305 },
    lang = { id = "lang", name = "阳座·狼", type = 4, unlockStage = 1805 },
    ying = { id = "ying", name = "天座·鹰", type = 5, unlockStage = 2805 },
    core = { id = "core", name = "阵眼",     type = 0, unlockStage = 3805 },
}

RelicAltar.TYPE_TO_SLOT = {
    [1] = "gui",
    [2] = "she",
    [3] = "lu",
    [4] = "lang",
    [5] = "ying",
}

RelicAltar.OPPOSITES = {
    { "ying", "gui" },
    { "she",  "lang" },
    { "lu",   "core" },
}

RelicAltar.NEIGHBORS = {
    { "gui",  "lu",   "守生" },
    { "lang", "ying", "攻天" },
    { "she",  "ying", "阴天" },
    { "she",  "lu",   "阴生" },
}

RelicAltar.AFFIX_SCALE = 0.34
RelicAltar.MISMATCH_SCALE = 0.5
RelicAltar.MAX_SLOTS = 6

local QUALITY_SCALE = {
    [1] = 0.70, [2] = 0.85, [3] = 1.00,
    [4] = 1.18, [5] = 1.38, [6] = 1.60,
}

local LEVEL_SCALE = {
    [1] = 1.00, [2] = 1.08, [3] = 1.16,
    [4] = 1.25, [5] = 1.35,
}

---@param quality number|nil
---@param level number|nil
---@return number
function RelicAltar.powerScale(quality, level)
    local q = QUALITY_SCALE[tonumber(quality) or 1] or 1.0
    local lv = math.max(1, math.min(5, math.floor(tonumber(level) or 1)))
    return q * (LEVEL_SCALE[lv] or 1.0)
end

---@param slotId string
---@param maxStageId number|nil
---@return boolean
function RelicAltar.isSlotUnlocked(slotId, maxStageId)
    local def = RelicAltar.SLOTS[slotId]
    if not def then return false end
    return (tonumber(maxStageId) or 0) >= (def.unlockStage or 0)
end

---@param slotId string
---@return string
function RelicAltar.unlockHint(slotId)
    local def = RelicAltar.SLOTS[slotId]
    if not def then return "未知座位" end
    local threshold = def.unlockStage or 0
    if threshold <= 0 then return "已解锁" end
    local chapter = math.floor(threshold / 100)
    local stage = threshold % 100
    local unlockText
    -- 祭阵座位最高只到 3805，按主线章关显示即可
    unlockText = "通关第" .. chapter .. "章第" .. stage .. "关"
    return unlockText .. "解锁"
end

---@param relic table
---@param slotId string
---@return boolean
function RelicAltar.isNative(relic, slotId)
    if not relic or not slotId then return false end
    if slotId == RelicAltar.SLOT_CORE then return false end
    local def = RelicAltar.SLOTS[slotId]
    return def ~= nil and tonumber(relic.type) == def.type
end

--- 从 grid 列表构建 slotId → relic
---@param grid table[]|nil
---@return table<string, table>
function RelicAltar.buildSlotMap(grid)
    local map = {}
    if type(grid) ~= "table" then return map end
    for _, relic in ipairs(grid) do
        local slotId = relic and relic.slot
        if slotId and RelicAltar.SLOTS[slotId] then
            map[slotId] = relic
        end
    end
    return map
end

---@param relic table
---@return number
function RelicAltar.affixScaleFor(relic)
    local base = RelicAltar.AFFIX_SCALE
    if not relic or not relic.slot then
        return base * RelicAltar.MISMATCH_SCALE
    end
    -- 本座与阵眼都拿满额词缀；错座腰斩
    if relic.slot == RelicAltar.SLOT_CORE or RelicAltar.isNative(relic, relic.slot) then
        return base
    end
    return base * RelicAltar.MISMATCH_SCALE
end

---@class RelicAltarState
---@field slotMap table<string, table>
---@field nativeCount number
---@field native table<string, boolean>
---@field small boolean
---@field great boolean
---@field perfect boolean
---@field opposites table[]
---@field neighbors table[]

---@param grid table[]|nil
---@return RelicAltarState
function RelicAltar.evaluate(grid)
    local slotMap = RelicAltar.buildSlotMap(grid)
    local native = {}
    local nativeCount = 0
    for _, slotId in ipairs(RelicAltar.SLOT_ORDER) do
        if slotId ~= RelicAltar.SLOT_CORE then
            local relic = slotMap[slotId]
            if relic and RelicAltar.isNative(relic, slotId) then
                native[slotId] = true
                nativeCount = nativeCount + 1
            end
        end
    end

    local opposites = {}
    for _, pair in ipairs(RelicAltar.OPPOSITES) do
        local a, b = pair[1], pair[2]
        if a == RelicAltar.SLOT_CORE or b == RelicAltar.SLOT_CORE then
            local other = (a == RelicAltar.SLOT_CORE) and b or a
            if native[other] and slotMap[RelicAltar.SLOT_CORE] then
                opposites[#opposites + 1] = { a, b, "生门" }
            end
        elseif native[a] and native[b] then
            opposites[#opposites + 1] = { a, b }
        end
    end

    local neighbors = {}
    for _, edge in ipairs(RelicAltar.NEIGHBORS) do
        if native[edge[1]] and native[edge[2]] then
            neighbors[#neighbors + 1] = { edge[1], edge[2], edge[3] }
        end
    end

    return {
        slotMap     = slotMap,
        nativeCount = nativeCount,
        native      = native,
        small       = nativeCount >= 3,
        great       = nativeCount >= 5,
        perfect     = nativeCount >= 5 and slotMap[RelicAltar.SLOT_CORE] ~= nil,
        opposites   = opposites,
        neighbors   = neighbors,
    }
end

local function scaleByRelic(value, relic)
    return math.floor(value * RelicAltar.powerScale(relic and relic.quality, relic and relic.level) + 0.5)
end

--- 生成祭阵机制条目（写入 relicConditions，由 RelicConditionHandler 消费）
---@param altar RelicAltarState
---@param classId string|nil
---@return table[]
function RelicAltar.buildFormationEntries(altar, classId)
    if not altar then return {} end
    local entries = {}
    local slotMap = altar.slotMap or {}
    local native = altar.native or {}

    local function push(entry)
        entries[#entries + 1] = entry
    end

    -- 本座阵法：仅小成后开启
    if altar.small then
        if native.gui and slotMap.gui then
            local relic = slotMap.gui
            local threat = scaleByRelic(180, relic)
            push({
                special = true, altar = true, kind = "gui_open_threat",
                targetClasses = { "knight", "warrior" },
                value = threat,
                raw = "龟阵：开战时封门人与拾骸者仇恨+" .. threat,
            })
            local block = scaleByRelic(8, relic)
            push({
                special = true, altar = true, kind = "gui_block",
                adKey = AD.PHYS_BLOCK_RATE,
                value = block,
                isPercent = true,
                raw = "龟阵：物理/魔法格挡概率提升",
            })
            push({
                special = true, altar = true, kind = "gui_block_mag",
                adKey = AD.MAG_BLOCK_RATE,
                value = block,
                isPercent = true,
                raw = "龟阵：魔法格挡概率提升",
            })
        end
        if native.she and slotMap.she then
            push({
                special = true, altar = true, kind = "she_stealth",
                targetClasses = { "assassin", "mage" },
                value = 30,
                raw = "蛇阵：换面人/裂隙使造成伤害 30% 不加仇恨",
            })
        end
        if native.lu and slotMap.lu then
            local relic = slotMap.lu
            push({
                special = true, altar = true, kind = "lu_overheal_shield",
                targetClasses = { "priest" },
                value = scaleByRelic(40, relic),
                raw = "鹿阵：司仪过量治疗的一部分转为护盾",
            })
        end
        if native.lang and slotMap.lang then
            local relic = slotMap.lang
            push({
                special = true, altar = true, kind = "lang_lifesteal",
                targetClasses = { "warrior", "ranger" },
                adKey = AD.ATK_SPEED,
                value = scaleByRelic(8, relic),
                isPercent = true,
                raw = "狼阵：战士/射手攻速与攻击回血",
            })
            push({
                special = true, altar = true, kind = "lang_atk_heal",
                targetClasses = { "warrior", "ranger" },
                adKey = AD.ATK_HEAL,
                value = scaleByRelic(12, relic),
                raw = "狼阵：战士/射手攻击回血",
            })
        end
        if native.ying and slotMap.ying then
            local relic = slotMap.ying
            local threshold = 12 + math.floor((relic.quality or 1) * 0.8)
            push({
                special = true, altar = true, kind = "execute",
                executeThreshold = threshold / 100,
                executeChance = 0.45,
                targetClasses = { "assassin", "ranger" },
                raw = "鹰阵：对血量低于" .. threshold .. "% 的敌人有概率终结",
            })
        end
    end

    -- 对位
    for _, pair in ipairs(altar.opposites or {}) do
        local a, b, tag = pair[1], pair[2], pair[3]
        if tag == "生门" then
            push({
                special = true, altar = true, kind = "life_gate",
                adKey = AD.HEAL_BONUS,
                value = 10,
                isPercent = true,
                raw = "对位·生门：治疗加成提升，过量治疗转全队护盾",
            })
        elseif (a == "ying" and b == "gui") or (a == "gui" and b == "ying") then
            push({
                special = true, altar = true, kind = "heaven_earth",
                adKey = AD.DMG_BONUS,
                value = 6,
                isPercent = true,
                raw = "对位·天地：开场减伤并保留斩杀线",
            })
            push({
                special = true, altar = true, kind = "heaven_earth_guard",
                adKey = AD.HP_BONUS,
                value = 6,
                isPercent = true,
                raw = "对位·天地：生命加成",
            })
        elseif (a == "she" and b == "lang") or (a == "lang" and b == "she") then
            push({
                special = true, altar = true, kind = "yin_yang",
                raw = "对位·阴阳：输出不抢嘲讽（狼打、蛇隐）",
            })
        end
    end

    -- 邻接共鸣
    for _, edge in ipairs(altar.neighbors or {}) do
        local tag = edge[3]
        if tag == "守生" then
            push({
                special = true, altar = true, kind = "guard_life",
                adKey = AD.HP_BONUS,
                value = 8,
                isPercent = true,
                targetClasses = { "knight", "priest" },
                raw = "邻接·守生：骑士/牧师生命加成",
            })
        elseif tag == "攻天" then
            push({
                special = true, altar = true, kind = "raid_sky",
                adKey = AD.ATK_SPEED,
                value = 8,
                isPercent = true,
                targetClasses = { "warrior", "ranger" },
                raw = "邻接·攻天：战士/射手攻速",
            })
        elseif tag == "阴天" then
            push({
                special = true, altar = true, kind = "shade_sky",
                adKey = AD.CRIT_RATE,
                value = 6,
                isPercent = true,
                targetClasses = { "assassin" },
                raw = "邻接·阴天：刺客暴击率",
            })
        elseif tag == "阴生" then
            push({
                special = true, altar = true, kind = "shade_life",
                adKey = AD.MAG_DMG_BONUS,
                value = 8,
                isPercent = true,
                targetClasses = { "mage" },
                raw = "邻接·阴生：法师魔法伤害加成",
            })
        end
    end

    if altar.great then
        push({
            special = true, altar = true, kind = "great_aegis",
            value = 1,
            raw = "大成·五兽齐聚：受到致命伤害时免死一次",
        })
    end
    if altar.perfect then
        push({
            special = true, altar = true, kind = "perfect_shield",
            adKey = AD.HP_BONUS,
            value = 6,
            isPercent = true,
            raw = "圆满：开战全队护盾",
        })
    end

    -- 职业过滤：无 targetClasses 的条目全队生效
    if classId then
        local filtered = {}
        for _, entry in ipairs(entries) do
            local match = true
            if entry.targetClasses then
                match = false
                for _, tc in ipairs(entry.targetClasses) do
                    if tc == classId or tc == "adventurer" then
                        match = true
                        break
                    end
                end
            end
            if match then
                filtered[#filtered + 1] = entry
            end
        end
        return filtered
    end
    return entries
end

--- 总览文本
---@param altar RelicAltarState
---@return string[]
function RelicAltar.describe(altar)
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end
    add(string.format("本座 %d/5  %s", altar.nativeCount or 0,
        altar.perfect and "圆满" or (altar.great and "大成" or (altar.small and "小成" or "散祭"))))
    for _, pair in ipairs(altar.opposites or {}) do
        local a = RelicAltar.SLOTS[pair[1]]
        local b = RelicAltar.SLOTS[pair[2]]
        add("对位：" .. (a and a.name or pair[1]) .. " ↔ " .. (b and b.name or pair[2])
            .. (pair[3] and ("（" .. pair[3] .. "）") or ""))
    end
    for _, edge in ipairs(altar.neighbors or {}) do
        add("邻接：" .. (edge[3] or "") .. " · "
            .. RelicAltar.SLOTS[edge[1]].name .. " / " .. RelicAltar.SLOTS[edge[2]].name)
    end
    if #(altar.opposites or {}) == 0 and #(altar.neighbors or {}) == 0 and not altar.small then
        add("本座不足 3 件，阵法未开。错座仅 50% 词缀。")
    end
    return lines
end

--- 旧档 8×10 拼图 → 祭阵座位
---@param relicData table
---@return table result { placed=number, dust=number }
function RelicAltar.migrateLegacyGrid(relicData)
    if type(relicData) ~= "table" then
        return { placed = 0, dust = 0 }
    end
    relicData.bag = relicData.bag or {}
    relicData.grid = relicData.grid or {}

    local alreadySlotted = true
    for _, r in ipairs(relicData.grid) do
        if r and not r.slot then
            alreadySlotted = false
            break
        end
    end
    if alreadySlotted and #relicData.grid > 0 then
        -- 已是祭阵格式，只清残留坐标
        for _, r in ipairs(relicData.grid) do
            r.row = nil
            r.col = nil
            r.rotation = nil
            r.gridPos = nil
        end
        relicData.altarMigrated = true
        return { placed = #relicData.grid, dust = 0 }
    end
    if relicData.altarMigrated and #relicData.grid <= RelicAltar.MAX_SLOTS then
        return { placed = #relicData.grid, dust = 0 }
    end

    local pool = {}
    for _, r in ipairs(relicData.grid) do
        if type(r) == "table" then pool[#pool + 1] = r end
    end
    relicData.grid = {}

    table.sort(pool, function(a, b)
        local qa, qb = tonumber(a.quality) or 0, tonumber(b.quality) or 0
        if qa ~= qb then return qa > qb end
        local la, lb = tonumber(a.level) or 1, tonumber(b.level) or 1
        if la ~= lb then return la > lb end
        return tostring(a.id) < tostring(b.id)
    end)

    local used = {}
    local placed = 0
    -- 先尽量本座
    for _, slotId in ipairs({ "gui", "lu", "lang", "she", "ying" }) do
        local wantType = RelicAltar.SLOTS[slotId].type
        for i, relic in ipairs(pool) do
            if not used[i] and tonumber(relic.type) == wantType then
                used[i] = true
                relic.slot = slotId
                relic.row = nil
                relic.col = nil
                relic.rotation = nil
                relic.gridPos = nil
                relicData.grid[#relicData.grid + 1] = relic
                placed = placed + 1
                break
            end
        end
    end
    -- 阵眼：剩余最高品质
    if not RelicAltar.buildSlotMap(relicData.grid)[RelicAltar.SLOT_CORE] then
        for i, relic in ipairs(pool) do
            if not used[i] then
                used[i] = true
                relic.slot = RelicAltar.SLOT_CORE
                relic.row = nil
                relic.col = nil
                relic.rotation = nil
                relic.gridPos = nil
                relicData.grid[#relicData.grid + 1] = relic
                placed = placed + 1
                break
            end
        end
    end

    local dust = 0
    for i, relic in ipairs(pool) do
        if not used[i] then
            relic.slot = nil
            relic.row = nil
            relic.col = nil
            relic.rotation = nil
            relic.gridPos = nil
            relicData.bag[#relicData.bag + 1] = relic
            local qDef = RelicDefs.QUALITIES[tonumber(relic.quality) or 1]
            local cost = qDef and qDef.reforgeCost or 0
            if cost <= 0 then cost = 20 * (tonumber(relic.quality) or 1) end
            dust = dust + math.floor(cost * 0.5)
        end
    end

    relicData.altarMigrated = true
    if dust > 0 then
        relicData.pendingAltarDust = (tonumber(relicData.pendingAltarDust) or 0) + dust
    end
    print(string.format("[RelicAltar] migrate placed=%d leftoverDust=%d bag=%d",
        placed, dust, #relicData.bag))
    return { placed = placed, dust = dust }
end

return RelicAltar
