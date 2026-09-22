-- ============================================================================
-- EquipmentSetSystem - 套装计数与 2 件属性注入
-- 规则：
--   · 按 template.setId 计件，品质/强化无关
--   · 双手武器占用副手：副手不计件；twoHandCountsAsSix 的套 5 槽按 6
--   · 两套 2 件可同时亮；4/6 件互斥（件数最多者，并列取 setId 字典序）
--   · P1 只落地 2 件纯属性；4/6 件只在 summary 里标记
-- ============================================================================

local EquipmentConfig = require("config.EquipmentConfig")
local EquipmentSetConfig = require("config.EquipmentSetConfig")

local EquipmentSetSystem = {}

local MOD_PREFIX = "set2_"

---@param equip table|nil 已 hydrate 的装备实例
---@return string|nil
local function setIdOfEquip(equip)
    if not equip then return nil end
    local tpl = EquipmentConfig.ITEMS[equip.templateId]
        or EquipmentConfig.ITEMS[tostring(equip.templateId)]
    return EquipmentSetConfig.getSetIdForTemplate(tpl)
end

--- 统计英雄已穿套装件数
---@param eqData table|nil equipment 模块数据
---@param heroId number
---@param getFromInventory fun(eqData: table, seq: any): table|nil
---@param getHeroSlots fun(eqData: table, heroId: number|string): table|nil
---@return table counts { [setId] = number }
---@return boolean twoHandWorn
function EquipmentSetSystem.countSets(eqData, heroId, getFromInventory, getHeroSlots)
    local counts = {}
    local twoHandWorn = false
    if not eqData or not heroId then
        return counts, twoHandWorn
    end
    local slots = getHeroSlots(eqData, heroId)
    if not slots then
        return counts, twoHandWorn
    end

    local seenSeq = {}
    for _, slotKey in ipairs(EquipmentConfig.SLOTS) do
        local seq = slots[slotKey]
        if seq and not seenSeq[seq] then
            seenSeq[seq] = true
            local equip = getFromInventory(eqData, seq)
            if equip then
                if slotKey == "weapon" and equip.grip == "twohand" then
                    twoHandWorn = true
                end
                -- 双手占用的副手槽：seq 不会出现（被卸空），无需额外跳过
                local setId = setIdOfEquip(equip)
                if setId then
                    counts[setId] = (counts[setId] or 0) + 1
                end
            end
        end
    end

    if twoHandWorn then
        for setId, n in pairs(counts) do
            local def = EquipmentSetConfig.get(setId)
            if def and def.twoHandCountsAsSix and n >= 5 then
                counts[setId] = 6
            end
        end
    end
    return counts, twoHandWorn
end

--- 4/6 件互斥：选出件数最多的一套（并列取 setId 字典序）
---@param counts table
---@return string|nil
local function pickExclusiveHighSet(counts)
    local bestId = nil
    local bestN = 0
    for setId, n in pairs(counts) do
        if n >= 4 then
            if n > bestN or (n == bestN and (bestId == nil or setId < bestId)) then
                bestN = n
                bestId = setId
            end
        end
    end
    return bestId
end

--- 生成展示用摘要（详情 UI / 调试）
---@param counts table
---@return table[] rows { setId, name, count, twoActive, fourActive, sixActive, color }
function EquipmentSetSystem.summarize(counts)
    local exclusive = pickExclusiveHighSet(counts)
    local rows = {}
    for setId, n in pairs(counts) do
        local def = EquipmentSetConfig.get(setId)
        if def and n > 0 then
            local fourOk = (n >= 4) and (exclusive == setId)
            rows[#rows + 1] = {
                setId = setId,
                name = def.name,
                count = n,
                twoActive = n >= 2,
                fourActive = fourOk,
                sixActive = fourOk and n >= 6,
                color = def.color,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.setId < b.setId
    end)
    return rows
end

--- 把 2 件属性打进 UnitAttributes；先清掉旧 set2_* 再写入
---@param unitAttrs table
---@param counts table
function EquipmentSetSystem.applyTwoPieceToUnit(unitAttrs, counts)
    if not unitAttrs then return end
    if unitAttrs.modifiers then
        local toRemove = {}
        for id, _ in pairs(unitAttrs.modifiers) do
            if type(id) == "string" and string.sub(id, 1, #MOD_PREFIX) == MOD_PREFIX then
                toRemove[#toRemove + 1] = id
            end
        end
        for i = 1, #toRemove do
            unitAttrs:removeModifier(toRemove[i])
        end
    end

    for setId, n in pairs(counts) do
        if n >= 2 then
            local def = EquipmentSetConfig.get(setId)
            local piece = def and def.twoPiece
            if piece and #piece > 0 then
                local entries = {}
                for i = 1, #piece do
                    local e = piece[i]
                    entries[#entries + 1] = {
                        key = e.key,
                        flat = e.flat,
                        pct = e.pct,
                    }
                end
                unitAttrs:addModifier(MOD_PREFIX .. setId, entries)
            end
        end
    end
end

--- 一站式：计数 + 注入 2 件，并把 4/6 件标记写到 unitAttrs 上供战斗读取
---@param unitAttrs table
---@param eqData table|nil
---@param heroId number
---@param getFromInventory fun(eqData: table, seq: any): table|nil
---@param getHeroSlots fun(eqData: table, heroId: number|string): table|nil
---@return table rows
function EquipmentSetSystem.applyToUnit(unitAttrs, eqData, heroId, getFromInventory, getHeroSlots)
    local counts = EquipmentSetSystem.countSets(eqData, heroId, getFromInventory, getHeroSlots)
    EquipmentSetSystem.applyTwoPieceToUnit(unitAttrs, counts)
    local rows = EquipmentSetSystem.summarize(counts)
    if unitAttrs then
        unitAttrs._setRows = rows
        unitAttrs._setFour = nil
        unitAttrs._setSix = nil
        for i = 1, #rows do
            local r = rows[i]
            if r.fourActive then unitAttrs._setFour = r.setId end
            if r.sixActive then unitAttrs._setSix = r.setId end
        end
    end
    return rows
end

--- 战斗单位上读取 4/6 件套 id
---@param unit table
---@return string|nil fourId
---@return string|nil sixId
function EquipmentSetSystem.activeHighSets(unit)
    local attrs = unit and unit.attrs
    if not attrs then return nil, nil end
    return attrs._setFour, attrs._setSix
end

return EquipmentSetSystem
