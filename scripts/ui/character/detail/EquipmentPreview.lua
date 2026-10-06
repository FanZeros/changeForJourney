------------------------------------------------------------------------
-- EquipmentPreview.lua —— 只读配装预览
-- 两份完整属性重建；穿戴校验/双手互斥复用 EquipmentSystem.applyEquip。
-- 不改 PlayerStore、HC 或真实背包；缓存和雷达尺度由 UI 管理。
------------------------------------------------------------------------
local HC = require("config.HeroConfig")
local AD = require("systems.AttributeDef")
local Eq = require("systems.EquipmentSystem")
local Sets = require("systems.EquipmentSetSystem")
local Attrs = require("ui.character.detail.CharacterDetailAttrs")
local Dispatcher = require("runtime.ClientDispatcher")
local PlayerStore = require("core.PlayerStore")

local M = {}

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do copy[deepCopy(key, seen)] = deepCopy(item, seen) end
    return copy
end

local function snapshot(options, key)
    if options ~= nil then return deepCopy(options[key] or {}) end
    return deepCopy(Dispatcher.get(key) or PlayerStore.Get(key) or {})
end

local function setSummary(eqData, heroId)
    local counts = Sets.countSets(eqData, heroId, Eq.getFromInventory, Eq.getHeroSlots)
    return deepCopy(Sets.summarize(counts))
end

local MULT_KEYS = {
    _melissaStarGateResonance = true,
    _artifactCritRateMult = true, _artifactCritDmgMult = true, _artifactExtraDamage = true,
}
local PCT_KEYS = { _effCritRate = true, _effCritDmg = true, _artifactChaosDamage = true, _artifactBlockCap = true }

-- 没显示的数值行可能等于默认值而非0（例如格挡比例默认60%）。
local function numericValue(data, key, row)
    if row and row.numericValue ~= nil then return row.numericValue end
    if AD.getMeta(key) and data.attrs then return data.attrs:getUncapped(key) end
    if MULT_KEYS[key] then return 1 end
    return 0
end

local function formatValue(key, value)
    if key == AD.ATK_INTERVAL then return string.format("%.1fs", value) end
    if MULT_KEYS[key] then return string.format("×%.2f", value) end
    if PCT_KEYS[key] then return string.format("%.1f%%", value) end
    if key == "_melissaStarGatePen" then return string.format("+%.1f", value) end
    return AD.formatAttrDisplayValue(key, value)
end

local function deltaText(key, delta)
    local sign = delta < 0 and "-" or "+"
    local amount = math.abs(delta)
    if key == AD.ATK_INTERVAL then return sign .. string.format("%.2fs", amount) end
    if MULT_KEYS[key] then return sign .. string.format("%.2f", amount) end
    if key == "_melissaStarGatePen" then return sign .. string.format("%.1f", amount) end
    local meta = AD.getMeta(key)
    if PCT_KEYS[key] or (meta and meta.dataType == AD.TYPE_PCT) then
        -- 百分数直接相减，单位是百分点，不是相对变化率。
        return sign .. string.format("%.1f%%", amount)
    end
    if meta and meta.dataType == AD.TYPE_FLOAT then return sign .. string.format("%.1f", amount) end
    return sign .. tostring(math.floor(amount + 0.5))
end

local function mergeRows(current, preview)
    local rows, indices, currentRows, previewRows = {}, {}, {}, {}
    local function append(data, target)
        for _, column in ipairs({ data.left, data.right }) do
            for _, row in ipairs(column) do
                target[row.key] = row
                if not indices[row.key] then
                    rows[#rows + 1] = { key = row.key, name = row.name, value = row.value, desc = row.desc }
                    indices[row.key] = #rows
                end
            end
        end
    end
    append(current, currentRows)
    if preview then append(preview, previewRows) end
    for _, row in ipairs(rows) do
        local before, after = currentRows[row.key], previewRows[row.key]
        local source = after or before
        row.name, row.desc = source.name, source.desc
        row.value = (before or after).value
        if (before and before.numericValue ~= nil) or (after and after.numericValue ~= nil) then
            row.currentValue = numericValue(current, row.key, before)
            if not before then row.value = formatValue(row.key, row.currentValue) end
            if preview then
                row.previewValue = numericValue(preview, row.key, after)
                local delta = row.previewValue - row.currentValue
                if math.abs(delta) < 0.0000001 then delta = 0 end
                row.delta = delta
                row.deltaText = deltaText(row.key, delta)
                if delta ~= 0 then
                    row.beneficial = row.key == AD.ATK_INTERVAL and delta < 0
                        or row.key ~= AD.ATK_INTERVAL and delta > 0
                end
            end
        else
            row.value = before and before.value or "—"
            row.currentValue = row.value
            if preview then row.previewValue = after and after.value or "—" end
        end
    end
    local order = Attrs.displayOrderIndex()
    table.sort(rows, function(a, b)
        local ia, ib = order[a.key] or math.huge, order[b.key] or math.huge
        if ia ~= ib then return ia < ib end
        return indices[a.key] < indices[b.key]
    end)
    return rows
end

-- 装备加成独立重建：同一人物底板相减，两侧都不带神器。
-- 保留职业/养成对装备的真实派生和乘区；不把人物固有值当成装备来源。
local function collectBonusSource(heroId, heroCfg, level, heroes, equipment, talents)
    local source = Attrs.collectAttributes(heroId, heroCfg, level,
        { heroes = heroes, equipment = equipment, artifacts = {}, talents = talents })
    -- 现有总属性页未列护盾减伤，装备模式仍须覆盖这个装备来源。
    local key = AD.ES_DMG_REDUCE
    local meta = AD.getMeta(key)
    if meta and source.attrs then
        source.left[#source.left + 1] = { key = key, name = meta.name,
            numericValue = source.attrs:getUncapped(key), value = "", desc = AD.getDesc(key) }
    end
    return source
end

local function positiveBonus(key, value)
    return key == AD.ATK_INTERVAL and value < -0.0000001
        or key ~= AD.ATK_INTERVAL and value > 0.0000001
end

local function bonusText(key, value)
    local formatted = deltaText(key, value)
    if value ~= 0 and not formatted:find("[1-9]") then
        local amount = string.format("%.6f", math.abs(value)):gsub("0+$", ""):gsub("%.$", "")
        local meta = AD.getMeta(key)
        local suffix = key == AD.ATK_INTERVAL and "s"
            or (PCT_KEYS[key] or (meta and meta.dataType == AD.TYPE_PCT)) and "%" or ""
        return (value < 0 and "-" or "+") .. amount .. suffix
    end
    return formatted
end

local function bonusStats(source, baseline)
    local stats = {}
    for _, key in ipairs(AD.BASE_STATS) do
        stats[key] = math.max(0, (source.stats[key] or 0) - (baseline.stats[key] or 0))
    end
    return stats
end

local function equipmentBonuses(heroId, heroCfg, level, heroes, equipment, previewEq, talents)
    local function bareSource(eqData)
        local bareEq = deepCopy(eqData)
        bareEq.equipped = bareEq.equipped or {}
        bareEq.equipped[heroId] = nil
        bareEq.equipped[tostring(heroId)] = nil
        return collectBonusSource(heroId, heroCfg, level, heroes, bareEq, talents)
    end
    local baseline = bareSource(equipment)
    local current = collectBonusSource(heroId, heroCfg, level, heroes, equipment, talents)
    local preview = previewEq and collectBonusSource(heroId, heroCfg, level, heroes, previewEq, talents) or nil
    -- 候选可来自同队其它角色；试穿会卸下原持有者装备，裸装底板也必须在试穿世界重建。
    local previewBaseline = previewEq and bareSource(previewEq) or baseline
    local currentDiff = mergeRows(baseline, current)
    local previewDiff = preview and mergeRows(previewBaseline, preview) or {}
    local nextByKey = {}
    for _, row in ipairs(previewDiff) do nextByKey[row.key] = row end
    local rows = {}
    for _, row in ipairs(currentDiff) do
        local after = nextByKey[row.key]
        local beforeValue, afterValue = row.delta, after and after.delta or nil
        if type(beforeValue) == "number" and
            (positiveBonus(row.key, beforeValue) or (afterValue and positiveBonus(row.key, afterValue))) then
            local entry = { key = row.key, name = row.name,
                currentValue = beforeValue, value = bonusText(row.key, beforeValue),
                desc = "仅显示装备引起的增益：同一角色穿戴装备后减去无装备时的数值，两侧均不计神器。百分比为百分点差值，攻击间隔缩短属于增益。\n"
                    .. (AD.getDesc(row.key) ~= "" and AD.getDesc(row.key) or row.desc or "") }
            if afterValue ~= nil then
                entry.previewValue = afterValue
                entry.delta = afterValue - beforeValue
                if math.abs(entry.delta) < 0.0000001 then entry.delta = 0 end
                entry.deltaText = bonusText(row.key, entry.delta)
                entry.beneficial = positiveBonus(row.key, entry.delta)
            end
            rows[#rows + 1] = entry
        end
    end
    return { rows = rows, current = { stats = bonusStats(current, baseline) },
        preview = preview and { stats = bonusStats(preview, previewBaseline) } or nil }
end

--- 构建只读装备预览；不传 seq 时只返回当前属性。
---@param heroId number|string
---@param level number
---@param seqOrNil? number|string
---@param targetSlotOrNil? string 默认候选装备自身槽位；副手双持需显式指定 offhand
---@param optionsOrNil? table 测试可显式提供 heroes/equipment/artifacts；includeEquipmentBonuses 按需启用装备净增益
---@return table { current, preview, rows, equipmentBonuses, currentSets, previewSets, candidate, error }
function M.build(heroId, level, seqOrNil, targetSlotOrNil, optionsOrNil)
    local result = {
        current = { left = {}, right = {}, stats = {} }, preview = nil,
        rows = {}, currentSets = {}, previewSets = {}, candidate = nil, error = nil,
    }
    local heroN = tonumber(heroId)
    local heroCfg = heroN and HC.get(heroN)
    if not heroN or not heroCfg then result.error = "英雄不存在"; return result end
    ---@cast heroN number
    local heroes = snapshot(optionsOrNil, "heroes")
    local equipment = snapshot(optionsOrNil, "equipment")
    local artifacts = snapshot(optionsOrNil, "artifacts")
    local talents = snapshot(optionsOrNil, "talents")
    local heroLevel = tonumber(level) or Eq.getHeroLevel(heroes, heroN)
    -- 参数等级与属性构建/穿戴校验必须同源，仅写副本。
    heroes.roster = heroes.roster or {}
    local hd = heroes.roster[heroN] or heroes.roster[tostring(heroN)] or {}
    hd.level = heroLevel
    heroes.roster[heroN] = hd
    local options = { heroes = heroes, equipment = equipment, artifacts = artifacts, talents = talents }
    result.current = Attrs.collectAttributes(heroN, heroCfg, heroLevel, options)
    result.currentSets = setSummary(equipment, heroN)
    result.rows = mergeRows(result.current, nil)
    local function finish(previewEq)
        if optionsOrNil and optionsOrNil.includeEquipmentBonuses then
            result.equipmentBonuses = equipmentBonuses(heroN, heroCfg, heroLevel, heroes, equipment, previewEq, talents)
        end
        return result
    end
    if seqOrNil == nil then return finish() end

    local previewEq = deepCopy(equipment)
    local seq = tonumber(seqOrNil)
    local candidate = seq and Eq.getFromInventory(previewEq, seq)
    if not seq or not candidate then result.error = "装备不存在"; return finish() end
    ---@cast seq number
    Eq.hydrate(candidate)
    local slot = targetSlotOrNil or candidate.slot
    result.candidate = { seq = seq, slot = slot, name = candidate.name or "未知装备" }
    ---@cast heroN number
    local ok, err = Eq.applyEquip(previewEq, seq, heroN, slot, heroes)
    if not ok then result.error = err or "无法穿戴"; return finish() end

    result.preview = Attrs.collectAttributes(heroN, heroCfg, heroLevel,
        { heroes = heroes, equipment = previewEq, artifacts = artifacts, talents = talents })
    result.previewSets = setSummary(previewEq, heroN)
    result.rows = mergeRows(result.current, result.preview)
    return finish(previewEq)
end

return M
