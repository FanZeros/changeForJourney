-- ============================================================================
-- EquipmentPower - 角色有效战力与只读换装评估（客户端/服务共用）
-- power 是单件在整套装备中的有效贡献；gain 才是换装后的净提升。
-- ============================================================================
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local Eq = require("systems.EquipmentSystem")
local EC = require("config.EquipmentConfig")
local Sets = require("systems.EquipmentSetSystem")
local ArtifactBridge = require("systems.ArtifactBridge")
local CombatPower = require("systems.CombatPower")
local AVC = require("config.AdvancementConfig")

local M = {}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[key] = copy(item, seen) end
    return out
end

local function idsForTeam(heroes, team)
    if type(heroes.teams) == "table" then
        local row = heroes.teams[team] or heroes.teams[tostring(team)]
        return row and row.slots or {}
    end
    return team == 1 and heroes.deployed or {}
end

local function numericId(value)
    if type(value) == "table" then return tonumber(value.heroId) end
    return tonumber(value)
end

function M.findPosition(heroes, heroId)
    for team = 1, 3 do
        local ids = idsForTeam(heroes or {}, team) or {}
        for slot = 1, 4 do
            if numericId(ids[slot] or ids[tostring(slot)]) == tonumber(heroId) then
                return slot, team
            end
        end
    end
    return nil, nil
end

-- 计属性和计套装共用同一有效槽：双手的旧档副手不生效，序号去重。
function M.applyEquipment(attrs, equipment, heroId)
    local slots = Eq.getHeroSlots(equipment, heroId) or {}
    local weapon = slots.weapon and Eq.getFromInventory(equipment, slots.weapon)
    local seen = {}
    for _, slot in ipairs(EC.SLOTS) do
        local seq = slots[slot]
        if seq and not (slot == "offhand" and weapon and weapon.grip == "twohand") then
            local key = tostring(seq)
            local item = Eq.getFromInventory(equipment, seq)
            if item and not seen[key] then
                Eq.applyToUnit(attrs, item, seq, Eq.getAscendBoost(item))
                seen[key] = true
                if slot == "armor" and AD.ARMOR_TYPE_ENUM[item.type] then
                    attrs.armorType = AD.ARMOR_TYPE_ENUM[item.type]
                end
            end
        end
    end
    Sets.applyToUnit(attrs, equipment, heroId, Eq.getFromInventory, Eq.getHeroSlots)
end

local function buildUnit(ctx, heroId, equipment)
    local seed = ctx.seeds[heroId]
    if not seed then return nil end
    local unit = {}
    for key, value in pairs(seed) do unit[key] = value end
    unit.attrs = seed.attrs:clone()
    M.applyEquipment(unit.attrs, equipment, heroId)
    -- 只执行确定性的开战属性，不运行条件被动/计时器或写战斗状态。
    if unit.attrs._setFour == "nitros" then
        local extra = math.min(10, math.floor(unit.attrs:get(AD.HIT_VALUE) / 80) * 2)
        if extra > 0 then unit.attrs:addModifier("set4_nitros", { { key = AD.COMBO_RATE, flat = extra } }) end
    elseif unit.attrs._setFour == "starless" then
        unit.attrs:addModifier("set4_starless", { { key = AD.MAG_PEN, flat = 8 } })
    end
    local slot, team = M.findPosition(ctx.heroesData, heroId)
    unit.partySlot, unit.teamIdx = slot, team
    if slot then unit.artifactEffects = ArtifactBridge.applyToUnit(unit.attrs, slot, ctx.artifactsData, team) end
    return unit
end

local function applyTeamAura(units)
    local active = false
    for _, unit in ipairs(units) do
        if unit.attrs._setSix == "last_rite" then active = true break end
    end
    if active then
        for _, unit in ipairs(units) do
            -- 队友旧快照可能被复用：克隆后再挂光环，避免污染 current 基准。
            unit.attrs = unit.attrs:clone()
            unit.attrs:addModifier("set6_last_rite", { { key = AD.ES_BONUS, flat = 8 } })
        end
    end
end

local function powerFor(ctx, unit, units, equipment)
    return CombatPower.calculate(unit, {
        teamUnits = units,
        heroesData = ctx.heroesData,
        equipmentData = equipment,
        artifactsData = ctx.artifactsData,
        talentsData = ctx.talentsData,
    })
end

local function previewUnits(ctx, equipment)
    local units = {}
    for _, old in ipairs(ctx.teamUnits) do
        -- 同队光环/供给排名会随本人换装改变，整队始终从裸种子重建。
        units[#units + 1] = buildUnit(ctx, old.heroId, equipment)
    end
    local target
    for _, unit in ipairs(units) do
        if unit.heroId == ctx.heroId then target = unit break end
    end
    if not target then
        target = buildUnit(ctx, ctx.heroId, equipment)
        units[#units + 1] = target
    end
    applyTeamAura(units)
    return target, units
end

local function readSnapshot(options, key)
    if options ~= nil then return copy(options[key] or {}) end
    return copy(require("core.PlayerStore").Get(key) or {})
end

-- 两种上下文共用同一裸种子/有效装备/本队光环/神器与正式估值管线。
local function finishContext(ctx)
    local id = ctx.heroId
    local roster = ctx.heroesData.roster or {}
    local function seedFor(sourceId)
        if ctx.seeds[sourceId] then return end
        local data = roster[sourceId] or roster[tostring(sourceId)] or {}
        local seed = HC.createHero(sourceId, data.level or 1, data.advBranch,
            data.awakening or {}, data.extraTalent or {}, {
                litNodes = ctx.talentsData.litNodes or false, silent = true,
            })
        if seed then
            seed.awakening = data.awakening or {}
            ctx.seeds[sourceId] = seed
        end
    end
    seedFor(id)
    if not ctx.seeds[id] then return nil end
    local _, team = M.findPosition(ctx.heroesData, id)
    local ids = team and idsForTeam(ctx.heroesData, team) or { id }
    local seen = {}
    for slot = 1, 4 do
        local sourceId = numericId(ids[slot] or ids[tostring(slot)])
        if sourceId and sourceId > 0 and not seen[sourceId] then
            seedFor(sourceId)
            if ctx.seeds[sourceId] then
                ctx.teamUnits[#ctx.teamUnits + 1] = buildUnit(ctx, sourceId, ctx.equipmentData)
                seen[sourceId] = true
            end
        end
    end
    if not seen[id] then ctx.teamUnits[#ctx.teamUnits + 1] = buildUnit(ctx, id, ctx.equipmentData) end
    for _, unit in ipairs(ctx.teamUnits) do
        if unit.heroId == id then ctx.hero = unit break end
    end
    applyTeamAura(ctx.teamUnits)
    ctx.currentPower = powerFor(ctx, ctx.hero, ctx.teamUnits, ctx.equipmentData)
    return ctx
end

-- 隔离库存只在同一装备版本内共享：applyEquip 写 equipped，hydrate 会写库存及嵌套词条。
-- 必须先深拷贝/水合，不能把 PlayerStore 的 live inventory 交给任何试穿路径。
---@type table|nil
local sharedEquipmentSnapshot
---@type table|nil
local sharedEquipmentSource
local sharedEquipmentRevision = -1
local function equipmentSnapshot(options)
    if options ~= nil then return readSnapshot(options, "equipment") end
    local store = require("core.PlayerStore")
    local source = store.Get("equipment")
    local revision = store.GetRevision and store.GetRevision("equipment") or 0
    -- 无revision的旧宿主不能证明同引用仍是同版本：直接build必须保持逐调用新快照。
    if store.GetRevision and sharedEquipmentSnapshot and sharedEquipmentSource == source
        and sharedEquipmentRevision == revision then return sharedEquipmentSnapshot end
    sharedEquipmentSource, sharedEquipmentRevision = source, revision
    sharedEquipmentSnapshot = copy(source or {})
    sharedEquipmentSnapshot.inventory = sharedEquipmentSnapshot.inventory or {}
    sharedEquipmentSnapshot.equipped = sharedEquipmentSnapshot.equipped or {}
    for key, item in pairs(sharedEquipmentSnapshot.inventory) do
        if type(item) == "table" then
            Eq.hydrate(item)
            item.seq = tonumber(item.seq or key) or item.seq
        end
    end
    return sharedEquipmentSnapshot
end

-- 通用上下文保留完整隔离库存；显式 options 仍有独立副本，缺省来源按装备版本共享。
function M.buildContext(heroId, options)
    local id = tonumber(heroId)
    if not id or not HC.get(id) then return nil end
    local ctx = {
        heroId = id,
        heroesData = readSnapshot(options, "heroes"),
        equipmentData = equipmentSnapshot(options),
        artifactsData = readSnapshot(options, "artifacts"),
        talentsData = readSnapshot(options, "talents"),
        seeds = {}, teamUnits = {}, memo = {}, scores = {},
    }
    if options and options.heroData then
        ctx.heroesData.roster = ctx.heroesData.roster or {}
        ctx.heroesData.roster[id] = copy(options.heroData)
    end
    ctx.equipmentData.inventory = ctx.equipmentData.inventory or {}
    ctx.equipmentData.equipped = ctx.equipmentData.equipped or {}
    if options ~= nil then
        for key, item in pairs(ctx.equipmentData.inventory) do
            if type(item) == "table" then
                Eq.hydrate(item)
                item.seq = tonumber(item.seq or key) or item.seq
            end
        end
    end
    return finishContext(ctx)
end

-- 仅供当前穿戴战力批次：模块快照一次，库存源只读，按本队实际六槽取副本。
-- 不跨通知缓存，也不传给 evaluate/score；它不承诺包含未穿戴候选。
function M.createWornBatch(options)
    local equipment = options and options.equipment
    if options == nil then equipment = require("core.PlayerStore").Get("equipment") end
    return {
        heroesData = readSnapshot(options, "heroes"),
        artifactsData = readSnapshot(options, "artifacts"),
        talentsData = readSnapshot(options, "talents"),
        equipmentData = { inventory = {}, equipped = copy(equipment and equipment.equipped or {}) },
        sourceInventory = equipment and equipment.inventory or {},
        copiedKeys = {}, copySeen = {},
    }
end

local function copyWornItems(batch, heroId)
    local slots = Eq.getHeroSlots(batch.equipmentData, heroId) or {}
    for _, slot in ipairs(EC.SLOTS) do
        local seq = slots[slot]
        if seq then
            -- 与 getFromInventory 完全相同：字符串键优先，原 seq 键后备。
            -- 保留槽表（含无效副手），让旧双手/去重/五算六规则原样判断。
            local key = tostring(seq)
            local item = batch.sourceInventory[key]
            if not item then key, item = seq, batch.sourceInventory[seq] end
            if item and not batch.copiedKeys[key] then
                batch.copiedKeys[key] = true
                local snapshot = copy(item, batch.copySeen)
                if type(snapshot) == "table" then
                    Eq.hydrate(snapshot)
                    snapshot.seq = tonumber(snapshot.seq or key) or snapshot.seq
                end
                batch.equipmentData.inventory[key] = snapshot
            end
        end
    end
end

-- 与 buildContext 的 currentPower 同口径，但只水合目标及真实所属队穿戴项。
-- heroData 的覆盖仅属于本上下文，不污染批次里其他英雄的队友种子。
function M.buildWornContext(heroId, options, batch)
    local id = tonumber(heroId)
    if not id or not HC.get(id) then return nil end
    batch = batch or M.createWornBatch(options)
    local heroes = batch.heroesData
    if options and options.heroData then
        local overridden = {}
        for key, value in pairs(heroes) do overridden[key] = value end
        overridden.roster = {}
        for key, value in pairs(heroes.roster or {}) do overridden.roster[key] = value end
        overridden.roster[id] = copy(options.heroData)
        heroes = overridden
    end
    copyWornItems(batch, id)
    local _, team = M.findPosition(heroes, id)
    local ids = team and idsForTeam(heroes, team) or {}
    for slot = 1, 4 do
        local sourceId = numericId(ids[slot] or ids[tostring(slot)])
        if sourceId and sourceId > 0 and HC.get(sourceId) then copyWornItems(batch, sourceId) end
    end
    return finishContext({
        heroId = id, heroesData = heroes, equipmentData = batch.equipmentData,
        artifactsData = batch.artifactsData, talentsData = batch.talentsData,
        seeds = {}, teamUnits = {}, memo = {}, scores = {},
    })
end

local function equipmentCopy(ctx)
    return {
        inventory = ctx.equipmentData.inventory,
        equipped = copy(ctx.equipmentData.equipped),
    }
end

-- 试穿复用权威穿戴校验；silent 仅关闭日志，不绕过任何规则。
function M.evaluateLoadout(ctx, changes)
    if not ctx or type(changes) ~= "table" then return nil end
    local requested = {}
    for slot, seq in pairs(changes) do
        if seq ~= false then
            local key = tostring(seq)
            if requested[key] then
                return { valid = false, error = "同一件装备不能占两个槽位", power = 0, gain = 0,
                    currentPower = ctx.currentPower, previewPower = ctx.currentPower }
            end
            requested[key] = slot
        end
    end
    local equipment = equipmentCopy(ctx)
    local slots = Eq.ensureHeroSlots(equipment, ctx.heroId)
    if changes.offhand ~= nil then slots.offhand = nil end
    for _, slot in ipairs({ "weapon", "armor", "helmet", "shoes", "accessory", "offhand" }) do
        local seq = changes[slot]
        if seq ~= nil then
            if seq == false then
                slots[slot] = nil
            else
                local ok, err = Eq.applyEquip(equipment, seq, ctx.heroId, slot, ctx.heroesData, true)
                if not ok then
                    return { valid = false, error = err, power = 0, gain = 0,
                        currentPower = ctx.currentPower, previewPower = ctx.currentPower }
                end
            end
        end
    end
    -- 自动互斥卸槽不能把显式要求的组合悄悄变成另一套配置。
    for slot, seq in pairs(changes) do
        if seq ~= false and tostring(slots[slot]) ~= tostring(seq) then
            return { valid = false, error = "主副手组合冲突", power = 0, gain = 0,
                currentPower = ctx.currentPower, previewPower = ctx.currentPower }
        end
    end
    local unit, units = previewUnits(ctx, equipment)
    local previewPower = powerFor(ctx, unit, units, equipment)
    return {
        valid = true, power = 0, gain = previewPower - ctx.currentPower,
        currentPower = ctx.currentPower, previewPower = previewPower,
        equipment = equipment,
    }
end

local function withoutPiece(ctx, equipment, seq)
    local stripped = { inventory = equipment.inventory, equipped = copy(equipment.equipped) }
    local slots = Eq.getHeroSlots(stripped, ctx.heroId) or {}
    for slot, value in pairs(slots) do
        if tostring(value) == tostring(seq) then slots[slot] = nil end
    end
    local unit, units = previewUnits(ctx, stripped)
    return powerFor(ctx, unit, units, stripped)
end

-- 角标只需净提升；完整评分随后在同一 memo 结果上懒补单件贡献。
function M.evaluateGain(ctx, seq, targetSlot)
    if not ctx then return nil end
    local item = Eq.getFromInventory(ctx.equipmentData, seq)
    if not item then return nil end
    local currentSlots = Eq.getHeroSlots(ctx.equipmentData, ctx.heroId) or {}
    local slot = targetSlot
    if not slot then
        for _, currentSlot in ipairs(EC.SLOTS) do
            if tostring(currentSlots[currentSlot]) == tostring(seq) then slot = currentSlot break end
        end
    end
    slot = slot or item.slot
    if not slot then return nil end
    local key = tostring(seq) .. ":" .. slot
    if ctx.memo[key] then return ctx.memo[key] end
    local alreadyEquipped = tostring(currentSlots[slot]) == tostring(seq)
    -- 双手在副手的占位只是显示，不执行一次非法副手穿戴。
    if slot == "offhand" and item.grip == "twohand"
        and tostring(currentSlots.weapon) == tostring(seq) then alreadyEquipped = true end
    ---@type table|nil
    local result
    if alreadyEquipped then
        result = { valid = true, gain = 0, currentPower = ctx.currentPower,
            previewPower = ctx.currentPower, equipment = ctx.equipmentData }
    else
        result = M.evaluateLoadout(ctx, { [slot] = seq })
    end
    -- evaluateLoadout 的 power=0 是占位值，不能冒充已经求过 withoutPiece。
    if result and result.valid then result.power = nil end
    ctx.memo[key] = result
    return result
end

function M.evaluate(ctx, seq, targetSlot)
    local result = M.evaluateGain(ctx, seq, targetSlot)
    if result and result.valid and result.power == nil then
        ---@cast result table<string, any>
        result.power = result.previewPower - withoutPiece(ctx, result.equipment, seq)
    end
    return result
end

-- 转职详情只比较这一阶的增量：二转基准保留其前置一转；一转不混入二转。
-- 全程保留当前等级、装备、神器、觉醒和所属队快照，不写回真实分支。
function M.evaluateAdvancement(ctx, branchId)
    local branch = AVC.get(branchId)
    local definition = ctx and HC.get(ctx.heroId)
    if not definition or not branch or branch.baseClass ~= definition.classId then return nil end
    ctx.advancementMemo = ctx.advancementMemo or {}
    if ctx.advancementMemo[branchId] then return ctx.advancementMemo[branchId] end
    local roster = ctx.heroesData.roster or {}
    local data = roster[ctx.heroId] or roster[tostring(ctx.heroId)] or {}
    local beforeData = copy(data)
    local afterData = copy(data)
    if branch.advLevel == AVC.ADV_FIRST then
        beforeData.advBranch = nil
        afterData.advBranch = { first = branchId }
    else
        beforeData.advBranch = { first = branch.parentBranch }
        afterData.advBranch = { first = branch.parentBranch, second = branchId }
    end
    local options = {
        heroes = ctx.heroesData, equipment = ctx.equipmentData,
        artifacts = ctx.artifactsData, talents = ctx.talentsData,
        heroData = beforeData,
    }
    local before = M.buildContext(ctx.heroId, options)
    options.heroData = afterData
    local after = M.buildContext(ctx.heroId, options)
    if not before or not after then return nil end
    local result = {
        currentPower = before.currentPower, previewPower = after.currentPower,
        gain = after.currentPower - before.currentPower,
    }
    ctx.advancementMemo[branchId] = result
    return result
end

-- 无角色的通用物品价值仍用于遗匣/锻炉，不改变洗练投入价值模型。
local baseKeys = {}
for _, key in ipairs(AD.BASE_STATS) do baseKeys[key] = true end
local function statValue(key, value)
    if baseKeys[key] and AD.DERIVATIVES[key] then
        local total = 0
        for _, row in ipairs(AD.DERIVATIVES[key]) do
            total = total + statValue(row.attr, value * row.perPoint)
        end
        return total
    end
    local meta = AD.META[key]
    if not meta or (meta.valueModel or 0) <= 0 then return 0 end
    return value * meta.valueModel / (meta.dataType == AD.TYPE_PCT and 100 or 1)
end

function M.genericScore(equip)
    if not equip then return 0 end
    local total = 0
    local boost = Eq.getAscendBoost(equip)
    for index, stat in ipairs(equip.baseStats or {}) do
        total = total + statValue(stat[1], Eq.effectiveBaseStatValue(equip, index, boost))
    end
    for _, affix in ipairs(equip.affixes or {}) do
        total = total + statValue(affix.key, Eq.effectiveAffixValue(equip, affix))
    end
    return math.floor(total)
end

local cached = {}
local subscribed = false
function M.invalidate()
    cached = {}
    sharedEquipmentSnapshot, sharedEquipmentSource = nil, nil
    sharedEquipmentRevision = -1
end

function M.getContext(heroId)
    local store = require("core.PlayerStore")
    -- Store 在通知订阅者前递增 revision；晚注册的失效回调会误清本次刷新刚造的 ctx。
    -- 仅为无 revision 的旧夹具/调用方保留订阅兜底。
    if not store.GetRevision and not subscribed then
        for _, key in ipairs({ "heroes", "equipment", "artifacts", "talents" }) do
            store.Subscribe(key, M.invalidate)
        end
        subscribed = true
    end
    local id = tonumber(heroId)
    if not id then return nil end
    -- ClearCache/切区也不能继续借上个玩家的快照。
    local heroes, equipment = store.Get("heroes"), store.Get("equipment")
    local revisionParts = {}
    for _, key in ipairs({ "heroes", "equipment", "artifacts", "talents" }) do
        revisionParts[#revisionParts + 1] = tostring(store.GetRevision and store.GetRevision(key) or 0)
    end
    local revision = table.concat(revisionParts, ":")
    local entry = cached[id]
    if not entry or entry.sourceHeroes ~= heroes or entry.sourceEquipment ~= equipment
        or entry.revision ~= revision then
        entry = M.buildContext(id)
        if entry then
            entry.sourceHeroes, entry.sourceEquipment = heroes, equipment
            entry.revision = revision
        end
        cached[id] = entry
    end
    return entry
end

function M.score(equip, heroId, targetSlot)
    if not heroId then return M.genericScore(equip) end
    if not equip then return 0 end
    local ctx = M.getContext(heroId)
    if not ctx then return 0 end
    local seq = equip.seq
    if not seq then
        local source = ctx.sourceEquipment
        for key, item in pairs(source and source.inventory or {}) do
            if item == equip then seq = tonumber(key) or key break end
        end
    end
    if seq then
        local result = M.evaluate(ctx, seq, targetSlot)
        if result and result.valid then return math.floor(result.power + 0.5) end
    end
    -- 未到穿戴等级或无合法槽位时，仍显示该角色能利用的词条价值；不显示提升箭头。
    local key = tostring(equip) .. ":" .. tostring(targetSlot)
    if ctx.scores[key] ~= nil then return ctx.scores[key] end
    local unit = {}
    for field, value in pairs(ctx.hero) do unit[field] = value end
    unit.attrs = ctx.hero.attrs:clone()
    ---@type any modifierId支持字符串标签；此值不是库存序号。
    local previewSeq = "power_preview"
    Eq.applyToUnit(unit.attrs, equip, previewSeq, Eq.getAscendBoost(equip))
    local units = {}
    for _, old in ipairs(ctx.teamUnits) do units[#units + 1] = old.heroId == ctx.heroId and unit or old end
    local value = math.floor(powerFor(ctx, unit, units, ctx.equipmentData) - ctx.currentPower + 0.5)
    ctx.scores[key] = value
    return value
end

return M
