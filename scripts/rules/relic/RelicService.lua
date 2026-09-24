-- ============================================================================
-- RelicService - 遗物管理业务逻辑
-- 职责: GM给遗物
-- 层级: server/relic  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM         = require("rules.character.PlayerDataManager")
local RelicAffix  = require("systems.RelicAffix")
local RelicDefs   = require("shared.relic.RelicDefs")
local RelicSchema = require("shared.relic.RelicSchema")
local RelicAltar  = require("systems.RelicAltar")

local RelicService = {}

--- 遗物背包容量上限（200 件 × ~81B/件 ≈ 16KB，远低于 50KB 网络分片阈值）
RelicService.MAX_BAG = 200

--- 确保遗物模块结构合法（稀疏 bag/grid 会导致 ipairs 漏项，UI 表现为「遗物被吞」）
---@param relicData table|nil
local function ensureRelicData(relicData)
    if relicData then
        RelicSchema.normalizeModule(relicData)
    end
    return relicData
end

--- 旧档迁移补偿粉尘（normalize 时记在 pendingAltarDust）
---@param uid number
---@param relicData table
local function grantPendingAltarDust(uid, relicData)
    local dust = tonumber(relicData and relicData.pendingAltarDust) or 0
    if dust <= 0 then return end
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return end
    currency.arcaneDust = (currency.arcaneDust or 0) + dust
    relicData.pendingAltarDust = nil
    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "mod_relics")
    print("[RelicService] altar migrate dust +" .. dust .. " uid=" .. tostring(uid))
end

local function getMaxStageId(uid)
    local battle = PDM.GetModule(uid, "battle")
    if not battle then return 0 end
    return tonumber(battle.maxStageId or battle.currentStageId) or 0
end

local function findRelicIn(list, relicId)
    if type(list) ~= "table" then return nil, nil end
    relicId = tostring(relicId)
    for i, r in ipairs(list) do
        if r and tostring(r.id) == relicId then
            return r, i
        end
    end
    return nil, nil
end

--- GM 生成遗物（指定类型/品质）
---@param uid number
---@param relicType number 1~5
---@param quality number 1~6
---@return boolean ok, string? err, table? result
function RelicService.GmGiveRelic(uid, relicType, quality)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    -- 背包容量检查
    if #relicData.bag >= RelicService.MAX_BAG then
        return false, "遗物背包已满（上限 " .. RelicService.MAX_BAG .. " 件）"
    end

    relicType = tonumber(relicType) or 1
    quality   = tonumber(quality)   or 1

    -- 校验类型范围
    if relicType < 1 or relicType > 5 then
        return false, "无效的遗物类型: " .. tostring(relicType)
    end
    if quality < 1 or quality > 6 then
        return false, "无效的品质: " .. tostring(quality)
    end

    -- 验证类型定义存在
    local typeDef = RelicDefs.TYPES[relicType]
    if not typeDef then
        return false, "遗物类型定义不存在: " .. tostring(relicType)
    end

    -- 随机词缀
    local level = 1
    local affixId = RelicAffix.rollAffix(relicType, quality, level)
    if not affixId then
        return false, "词缀池为空 type=" .. relicType .. " q=" .. quality
    end

    -- 生成遗物对象
    local id = relicData.nextId
    relicData.nextId = id + 1

    local relic = {
        id      = tostring(id),
        type    = relicType,
        quality = quality,
        affixId = affixId,
        -- level 省略时默认为 1，locked 省略时默认为 false（减少持久化体积）
    }

    -- 加入背包
    relicData.bag[#relicData.bag + 1] = relic

    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] GM_GIVE_RELIC uid=" .. tostring(uid)
        .. " id=" .. relic.id
        .. " type=" .. typeDef.name
        .. " q=" .. quality
        .. " affix=" .. affixId)

    return true, nil, { relic = relic }
end

--- 遗物洗练（消耗奥术粉尘，重随词缀）
---@param uid number
---@param relicId string 遗物ID
---@return boolean ok, string? err, table? result
function RelicService.Reforge(uid, relicId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    relicId = tostring(relicId or "")
    if relicId == "" then return false, "缺少 relicId" end

    -- 在背包和装备栏中查找遗物
    local relic = nil
    for _, r in ipairs(relicData.bag) do
        if tostring(r.id) == relicId then relic = r; break end
    end
    if not relic then
        -- 尝试装备栏
        for _, r in pairs(relicData.grid or {}) do
            if tostring(r.id) == relicId then relic = r; break end
        end
    end
    if not relic then return false, "遗物不存在: " .. relicId end

    -- 品质检查（3品及以上才可洗练）
    if (relic.quality or 0) < 3 then
        return false, "品质不足，需要3品及以上"
    end

    -- 计算消耗
    local qualityDef = RelicDefs.QUALITIES[relic.quality]
    if not qualityDef then return false, "品质定义不存在: " .. tostring(relic.quality) end
    local cost = qualityDef.reforgeCost or 0

    -- 检查并扣除奥术粉尘
    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "货币数据未加载" end

    local owned = currency.arcaneDust or 0
    if owned < cost then
        return false, "奥术粉尘不足: 拥有" .. owned .. " 需要" .. cost
    end
    currency.arcaneDust = owned - cost
    PDM.MarkDirty(uid, "currency")

    -- 随机新词缀（排除当前词缀）
    local newAffixId = RelicAffix.rollAffix(relic.type, relic.quality, relic.level or 1, relic.affixId)
    if not newAffixId then
        -- 回滚奥术粉尘
        currency.arcaneDust = owned
        PDM.MarkDirty(uid, "currency")
        return false, "词缀池耗尽，无法洗练"
    end

    -- 记录旧词缀（日志用）
    local oldAffixId = relic.affixId

    -- 洗练只生成候选，不立即替换；点击"替换"时再提交
    relic.pendingReforgeAffixId = newAffixId

    -- 递增洗练计数
    relicData.reforgeCount = (relicData.reforgeCount or 0) + 1

    PDM.MarkDirty(uid, "mod_relics")
    PDM.FlushImmediate(uid)

    print("[RelicService] REFORGE uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " oldAffix=" .. tostring(oldAffixId)
        .. " pendingAffix=" .. tostring(newAffixId)
        .. " cost=" .. cost
        .. " remaining=" .. tostring(currency.arcaneDust))

    return true, nil, { newAffixId = newAffixId }
end

--- 确认替换洗练候选词缀
---@param uid number
---@param relicId string 遗物ID
---@param newAffixId number 候选词缀ID
---@return boolean ok, string? err, table? result
function RelicService.ConfirmReforge(uid, relicId, newAffixId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    relicId = tostring(relicId or "")
    newAffixId = tonumber(newAffixId)
    if relicId == "" or not newAffixId then return false, "参数错误" end

    local relic = nil
    for _, r in ipairs(relicData.bag or {}) do
        if tostring(r.id) == relicId then relic = r; break end
    end
    if not relic then
        for _, r in pairs(relicData.grid or {}) do
            if tostring(r.id) == relicId then relic = r; break end
        end
    end
    if not relic then return false, "遗物不存在: " .. relicId end
    if tonumber(relic.pendingReforgeAffixId) ~= newAffixId then
        return false, "洗练结果已失效，请重新洗练"
    end

    local oldAffixId = relic.affixId
    relic.affixId = newAffixId
    relic.pendingReforgeAffixId = nil
    PDM.MarkDirty(uid, "mod_relics")
    PDM.FlushImmediate(uid)

    print("[RelicService] REFORGE_CONFIRM uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " oldAffix=" .. tostring(oldAffixId)
        .. " newAffix=" .. tostring(newAffixId))

    return true, nil, { relicId = relicId, newAffixId = newAffixId }
end

--- 遗物合成（3个同类型同品质 → 1个高一级品质）
---@param uid number
---@param relicIds string[] 3个遗物ID
---@return boolean ok, string? err, table? result
function RelicService.Merge(uid, relicIds, keepAffixId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    if not relicIds or #relicIds ~= 3 then
        return false, "需要提供3个遗物ID"
    end

    -- 查找并验证3个遗物（必须都在背包中）
    local relics = {}
    local bagIndices = {}
    for _, rid in ipairs(relicIds) do
        rid = tostring(rid)
        local found = false
        for i, r in ipairs(relicData.bag) do
            if tostring(r.id) == rid then
                relics[#relics + 1] = r
                bagIndices[#bagIndices + 1] = i
                found = true
                break
            end
        end
        if not found then
            return false, "遗物不在背包中: " .. rid
        end
    end

    -- 检查ID不重复
    if relicIds[1] == relicIds[2] or relicIds[1] == relicIds[3] or relicIds[2] == relicIds[3] then
        return false, "不能使用重复的遗物"
    end

    -- 验证同类型
    local baseType = relics[1].type
    for i = 2, 3 do
        if relics[i].type ~= baseType then
            return false, "合成需要相同类型的遗物"
        end
    end

    -- 验证同品质
    local baseQuality = relics[1].quality
    for i = 2, 3 do
        if relics[i].quality ~= baseQuality then
            return false, "合成需要相同品质的遗物"
        end
    end

    -- 品质上限检查
    if baseQuality >= 6 then
        return false, "至臻品质无法继续合成"
    end

    -- 检查锁定
    for i = 1, 3 do
        if relics[i].locked == true then
            return false, "遗物已锁定: " .. tostring(relics[i].id)
        end
    end

    -- 背包容量检查（消耗3个 产出1个，净减少2个，不会溢出）

    -- 验证类型定义存在
    local typeDef = RelicDefs.TYPES[baseType]
    if not typeDef then
        return false, "遗物类型定义不存在: " .. tostring(baseType)
    end

    -- 生成新遗物：优先保留玩家指定词缀（该词须属于 3 件之一）
    local newQuality = baseQuality + 1
    keepAffixId = tonumber(keepAffixId)
    local keepOk = false
    if keepAffixId then
        for i = 1, 3 do
            if tonumber(relics[i].affixId) == keepAffixId then
                keepOk = RelicDefs.getAffixText(keepAffixId, newQuality) ~= nil
                break
            end
        end
    end
    local maxKeepLevel = 1
    for i = 1, 3 do
        local lv = tonumber(relics[i].level) or 1
        if lv > maxKeepLevel then maxKeepLevel = lv end
    end
    local level = math.max(1, math.min(RelicDefs.MAX_LEVEL or 5, maxKeepLevel))
    local affixId = keepOk and keepAffixId or RelicAffix.rollAffix(baseType, newQuality, level)
    if not affixId then
        return false, "词缀池为空 type=" .. baseType .. " q=" .. newQuality
    end

    local id = relicData.nextId
    relicData.nextId = id + 1

    local newRelic = {
        id      = tostring(id),
        type    = baseType,
        quality = newQuality,
        affixId = affixId,
        level   = level > 1 and level or nil,
    }

    -- 从背包中移除3个素材遗物（从后往前删，避免索引偏移）
    table.sort(bagIndices, function(a, b) return a > b end)
    for _, idx in ipairs(bagIndices) do
        table.remove(relicData.bag, idx)
    end

    -- 加入新遗物
    relicData.bag[#relicData.bag + 1] = newRelic

    -- 递增合成计数
    relicData.mergeCount = (relicData.mergeCount or 0) + 1

    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] MERGE uid=" .. tostring(uid)
        .. " consumed=" .. relicIds[1] .. "," .. relicIds[2] .. "," .. relicIds[3]
        .. " type=" .. typeDef.name
        .. " " .. baseQuality .. "→" .. newQuality
        .. " newId=" .. newRelic.id
        .. " affix=" .. affixId)

    return true, nil, { relic = newRelic }
end

--- 将遗物从背包镶嵌到祭阵座位
---@param uid number
---@param relicId string
---@param slotId string gui/she/lu/lang/ying/core
---@return boolean ok, string? err, table? result
function RelicService.PlaceOnGrid(uid, relicId, slotId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    relicId = tostring(relicId or "")
    slotId = tostring(slotId or "")
    if relicId == "" then return false, "缺少 relicId" end
    local slotDef = RelicAltar.SLOTS[slotId]
    if not slotDef then return false, "无效祭位: " .. slotId end
    if not RelicAltar.isSlotUnlocked(slotId, getMaxStageId(uid)) then
        return false, RelicAltar.unlockHint(slotId)
    end

    local relic, bagIndex = findRelicIn(relicData.bag, relicId)
    if not relic then
        return false, "遗物不在背包中"
    end

    relicData.grid = relicData.grid or {}
    for _, gr in ipairs(relicData.grid) do
        if gr and tostring(gr.slot) == slotId then
            return false, "该祭位已有遗物"
        end
    end
    if #relicData.grid >= RelicAltar.MAX_SLOTS then
        return false, "祭阵已满"
    end

    table.remove(relicData.bag, bagIndex)
    relic.slot = slotId
    relic.row = nil
    relic.col = nil
    relic.rotation = nil
    relic.gridPos = nil
    relicData.grid[#relicData.grid + 1] = relic
    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] PLACE uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " type=" .. tostring(relic.type)
        .. " slot=" .. slotId
        .. " native=" .. tostring(RelicAltar.isNative(relic, slotId)))

    return true, nil, { relicId = relicId, slot = slotId }
end

--- 调整模式批量移动：把已上阵遗物改到新座位
---@param uid number
---@param moves table[] { {relicId, slot}, ... }
---@return boolean ok, string? err, table? result
function RelicService.BatchAdjust(uid, moves)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)
    if not moves or #moves == 0 then return false, "无移动数据" end
    if #moves > RelicAltar.MAX_SLOTS then return false, "单次移动过多" end

    local maxStage = getMaxStageId(uid)
    local gridRelics = relicData.grid or {}
    local byId = {}
    for _, gr in ipairs(gridRelics) do
        byId[tostring(gr.id)] = gr
    end

    local assigned = {}
    for _, m in ipairs(moves) do
        local rid = tostring(m.relicId or "")
        local slotId = tostring(m.slot or m.slotId or "")
        if rid == "" or not RelicAltar.SLOTS[slotId] then
            return false, "移动参数无效"
        end
        if not RelicAltar.isSlotUnlocked(slotId, maxStage) then
            return false, RelicAltar.unlockHint(slotId)
        end
        if assigned[slotId] then
            return false, "座位冲突: " .. slotId
        end
        assigned[slotId] = rid
        if not byId[rid] then
            return false, "遗物不在祭阵上: " .. rid
        end
    end

    for _, m in ipairs(moves) do
        local relic = byId[tostring(m.relicId)]
        relic.slot = tostring(m.slot or m.slotId)
        relic.row = nil
        relic.col = nil
        relic.rotation = nil
        relic.gridPos = nil
    end
    PDM.MarkDirty(uid, "mod_relics")
    print("[RelicService] BATCH_ADJUST uid=" .. tostring(uid) .. " moved=" .. #moves)
    return true, nil, { moved = #moves }
end

--- 从祭阵取下遗物，放回背包
---@param uid number
---@param relicId string
---@return boolean ok, string? err, table? result
function RelicService.RemoveFromGrid(uid, relicId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    relicId = tostring(relicId or "")
    if relicId == "" then return false, "缺少 relicId" end

    local relic, gridIndex = findRelicIn(relicData.grid or {}, relicId)
    if not relic then return false, "遗物不在祭阵上" end
    if #relicData.bag >= RelicService.MAX_BAG then
        return false, "背包已满，无法取下"
    end

    table.remove(relicData.grid, gridIndex)
    relic.slot = nil
    relic.row = nil
    relic.col = nil
    relic.rotation = nil
    relic.gridPos = nil
    relicData.bag[#relicData.bag + 1] = relic
    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] REMOVE uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " type=" .. tostring(relic.type))
    return true, nil, { relicId = relicId }
end

--- 原子替换：背包新遗物替换祭阵旧遗物（可指定新座位，默认沿用旧座位）
---@param uid number
---@param oldRelicId string
---@param newRelicId string
---@param slotId string|nil
---@return boolean ok, string? err, table? result
function RelicService.ReplaceOnGrid(uid, oldRelicId, newRelicId, slotId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    oldRelicId = tostring(oldRelicId or "")
    newRelicId = tostring(newRelicId or "")
    if oldRelicId == "" or newRelicId == "" then return false, "缺失遗物ID" end

    local oldRelic, oldIndex = findRelicIn(relicData.grid or {}, oldRelicId)
    if not oldRelic then return false, "旧遗物不在祭阵上" end
    local newRelic, newIndex = findRelicIn(relicData.bag or {}, newRelicId)
    if not newRelic then return false, "新遗物不在背包中" end

    slotId = tostring(slotId or oldRelic.slot or "")
    local slotDef = RelicAltar.SLOTS[slotId]
    if not slotDef then return false, "无效祭位" end
    if not RelicAltar.isSlotUnlocked(slotId, getMaxStageId(uid)) then
        return false, RelicAltar.unlockHint(slotId)
    end
    for i, gr in ipairs(relicData.grid or {}) do
        if gr ~= oldRelic and tostring(gr.slot) == slotId then
            return false, "该祭位已有遗物"
        end
    end

    table.remove(relicData.grid, oldIndex)
    oldRelic.slot = nil
    oldRelic.row = nil
    oldRelic.col = nil
    oldRelic.rotation = nil
    oldRelic.gridPos = nil
    relicData.bag[#relicData.bag + 1] = oldRelic

    -- 旧遗物入包后，新遗物下标可能偏移，重新查找
    newRelic, newIndex = findRelicIn(relicData.bag, newRelicId)
    if not newRelic or not newIndex then return false, "新遗物不在背包中" end
    table.remove(relicData.bag, newIndex)
    newRelic.slot = slotId
    newRelic.row = nil
    newRelic.col = nil
    newRelic.rotation = nil
    newRelic.gridPos = nil
    relicData.grid[#relicData.grid + 1] = newRelic
    PDM.MarkDirty(uid, "mod_relics")

    print("[RelicService] REPLACE uid=" .. tostring(uid)
        .. " old=" .. oldRelicId .. " new=" .. newRelicId .. " slot=" .. slotId)
    return true, nil, { slot = slotId }
end

--- 遗物升级（消耗奥术粉尘，提升等级以解锁高 minLevel 词缀池）
---@param uid number
---@param relicId string
---@return boolean ok, string? err, table? result
function RelicService.Upgrade(uid, relicId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    relicId = tostring(relicId or "")
    if relicId == "" then return false, "缺少 relicId" end
    local relic = select(1, findRelicIn(relicData.bag, relicId))
        or select(1, findRelicIn(relicData.grid, relicId))
    if not relic then return false, "遗物不存在" end

    local level = tonumber(relic.level) or 1
    if level >= (RelicDefs.MAX_LEVEL or 5) then
        return false, "已达最高等级"
    end
    local cost = RelicDefs.getUpgradeCost(relic.quality, level)
    if cost <= 0 then return false, "无法升级" end

    local currency = PDM.GetModule(uid, "currency")
    if not currency then return false, "货币数据未加载" end
    local owned = currency.arcaneDust or 0
    if owned < cost then
        return false, "奥术粉尘不足: 拥有" .. owned .. " 需要" .. cost
    end
    currency.arcaneDust = owned - cost
    relic.level = level + 1
    PDM.MarkDirty(uid, "currency")
    PDM.MarkDirty(uid, "mod_relics")
    PDM.FlushImmediate(uid)

    print("[RelicService] UPGRADE uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " " .. level .. "→" .. relic.level
        .. " cost=" .. cost)
    return true, nil, { relicId = relicId, level = relic.level, cost = cost }
end

--- 切换遗物锁定状态（锁定后无法参与合成）
---@param uid number
---@param relicId string
---@return boolean ok, string|nil err, table|nil result { relicId, locked }
function RelicService.ToggleLock(uid, relicId)
    local relicData = ensureRelicData(PDM.GetModule(uid, "mod_relics"))
    if not relicData then return false, "数据未加载" end
    grantPendingAltarDust(uid, relicData)

    relicId = tostring(relicId or "")
    if relicId == "" then return false, "缺少 relicId" end

    local relic = nil
    for _, r in ipairs(relicData.bag or {}) do
        if tostring(r.id) == relicId then relic = r; break end
    end
    if not relic then
        for _, r in ipairs(relicData.grid or {}) do
            if tostring(r.id) == relicId then relic = r; break end
        end
    end
    if not relic then return false, "遗物不存在: " .. relicId end

    if relic.locked then
        relic.locked = nil
    else
        relic.locked = true
    end
    PDM.MarkDirty(uid, "mod_relics")
    PDM.FlushImmediate(uid)

    print("[RelicService] ToggleLock uid=" .. tostring(uid)
        .. " relicId=" .. relicId
        .. " locked=" .. tostring(relic.locked == true))
    return true, nil, { relicId = relicId, locked = relic.locked == true }
end

return RelicService
