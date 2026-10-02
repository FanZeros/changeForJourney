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
    if options and options[key] ~= nil then return deepCopy(options[key]) end
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

--- 构建只读装备预览；不传 seq 时只返回当前属性。
---@param heroId number|string
---@param level number
---@param seqOrNil? number|string
---@param targetSlotOrNil? string 默认候选装备自身槽位；副手双持需显式指定 offhand
---@param optionsOrNil? table 测试可显式提供 heroes/equipment/artifacts
---@return table { current, preview, rows, currentSets, previewSets, candidate, error }
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
    local heroLevel = tonumber(level) or Eq.getHeroLevel(heroes, heroN)
    -- 参数等级与属性构建/穿戴校验必须同源，仅写副本。
    heroes.roster = heroes.roster or {}
    local hd = heroes.roster[heroN] or heroes.roster[tostring(heroN)] or {}
    hd.level = heroLevel
    heroes.roster[heroN] = hd
    local options = { heroes = heroes, equipment = equipment, artifacts = artifacts }
    result.current = Attrs.collectAttributes(heroN, heroCfg, heroLevel, options)
    result.currentSets = setSummary(equipment, heroN)
    result.rows = mergeRows(result.current, nil)
    if seqOrNil == nil then return result end

    local previewEq = deepCopy(equipment)
    local seq = tonumber(seqOrNil)
    local candidate = seq and Eq.getFromInventory(previewEq, seq)
    if not seq or not candidate then result.error = "装备不存在"; return result end
    ---@cast seq number
    Eq.hydrate(candidate)
    local slot = targetSlotOrNil or candidate.slot
    result.candidate = { seq = seq, slot = slot, name = candidate.name or "未知装备" }
    ---@cast heroN number
    local ok, err = Eq.applyEquip(previewEq, seq, heroN, slot, heroes)
    if not ok then result.error = err or "无法穿戴"; return result end

    result.preview = Attrs.collectAttributes(heroN, heroCfg, heroLevel,
        { heroes = heroes, equipment = previewEq, artifacts = artifacts })
    result.previewSets = setSummary(previewEq, heroN)
    result.rows = mergeRows(result.current, result.preview)
    return result
end

return M
