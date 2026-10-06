-- ============================================================================
-- EquipmentService - 装备管理业务逻辑
-- 职责: GM给装备、穿戴/卸下装备、双持互斥
-- 层级: server/equipment  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM             = require("rules.character.PlayerDataManager")
local EquipmentSystem = require("systems.EquipmentSystem")
local EquipmentPower  = require("systems.EquipmentPower")
local EquipmentConfig = require("config.EquipmentConfig")
local AVC             = require("config.AdvancementConfig")
local HC              = require("config.HeroConfig")

local EquipmentService = {}

-- ======================== GM 给装备 ========================

--- GM 给装备（指定模板）
---@param uid number
---@param templateId string|nil
---@param level number|nil
---@param quality number|nil
---@return boolean ok, string? err, table? result
function EquipmentService.GmGiveEquip(uid, templateId, level, quality)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return false, "数据未加载" end

    templateId = templateId and tostring(templateId) or nil
    if not templateId or templateId == "" then
        return false, "缺少 templateId"
    end

    level   = level   and tonumber(level)   or nil
    quality = quality and tonumber(quality) or nil
    if level then
        level = math.max(1, math.min(9999, math.floor(level)))
    end

    if EquipmentSystem.isInventoryFull(equipData) then
        return false, "背包已满（上限 " .. EquipmentSystem.MAX_INVENTORY .. " 件）"
    end

    local equip = EquipmentSystem.generate(templateId, level, quality)
    if not equip then
        return false, "模板不存在: " .. tostring(templateId)
    end

    local seq = EquipmentSystem.addToInventory(equipData, equip)
    PDM.MarkDirty(uid, "equipment")

    print("[EquipmentService] GM_GIVE_EQUIP uid=" .. tostring(uid)
        .. " seq=" .. seq .. " " .. EquipmentSystem.summary(equip))

    return true, nil, { seq = seq, equip = equip }
end

--- GM 随机给装备
---@param uid number
---@param level number|nil
---@param quality number|nil
---@param count number|nil
---@return boolean ok, string? err, table? result
function EquipmentService.GmGiveRandom(uid, level, quality, count)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return false, "数据未加载" end

    level   = tonumber(level)   or 1
    quality = tonumber(quality) or nil
    count   = tonumber(count)   or 1
    count   = math.max(1, math.min(10, count))
    level   = math.max(1, math.min(9999, math.floor(level)))

    local results = {}
    local bagFull = false
    for _ = 1, count do
        if EquipmentSystem.isInventoryFull(equipData) then
            bagFull = true
            print("[EquipmentService] GM_GIVE_RANDOM SKIP (bag full) uid=" .. tostring(uid))
            break
        end
        local equip = EquipmentSystem.generateRandom(level, quality)
        if equip then
            local seq = EquipmentSystem.addToInventory(equipData, equip)
            results[#results + 1] = { seq = seq, equip = equip }
            print("[EquipmentService] GM_GIVE_RANDOM uid=" .. tostring(uid)
                .. " seq=" .. seq .. " " .. EquipmentSystem.summary(equip))
        end
    end

    if #results > 0 then
        PDM.MarkDirty(uid, "equipment")
    end

    return true, nil, { count = #results, items = results, bagFull = bagFull or nil }
end

-- ======================== 穿戴 / 卸下 ========================

--- 穿戴/更换装备
---@param uid number
---@param seq number|nil
---@param heroId number|nil
---@param slot string|nil
---@return boolean ok, string? err, table? result
function EquipmentService.EquipItem(uid, seq, heroId, slot)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return false, "数据未加载" end

    local heroesData = PDM.GetModule(uid, "heroes")
    local seqN = tonumber(seq)
    local heroN = tonumber(heroId)
    if not seqN or not heroN or not slot then
        return false, "参数缺失"
    end
    local ok, err, result = EquipmentSystem.applyEquip(equipData, seqN, heroN, slot, heroesData)
    if not ok then
        return false, err
    end
    PDM.MarkDirty(uid, "equipment")
    print("[EquipmentService] EQUIP uid=" .. tostring(uid)
        .. " heroId=" .. tostring(result.heroId) .. " slot=" .. tostring(result.slot)
        .. " seq=" .. tostring(result.seq)
        .. (result.oldSeq and (" replaced=" .. tostring(result.oldSeq)) or ""))
    return true, nil, result
end

--- 卸下装备
---@param uid number
---@param heroId number|nil
---@param slot string|nil
---@return boolean ok, string? err, table? result
function EquipmentService.UnequipItem(uid, heroId, slot)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return false, "数据未加载" end

    local heroN = tonumber(heroId)
    if heroN == nil or not slot then
        return false, "参数缺失"
    end
    ---@cast heroN number
    local ok, err, result = EquipmentSystem.applyUnequip(equipData, heroN, slot)
    if not ok then
        return false, err
    end
    PDM.MarkDirty(uid, "equipment")
    print("[EquipmentService] UNEQUIP uid=" .. tostring(uid)
        .. " heroId=" .. tostring(result.heroId) .. " slot=" .. tostring(result.slot)
        .. " seq=" .. tostring(result.removedSeq))
    return true, nil, result
end

-- ======================== 批量穿戴 / 卸下 ========================

--- 一键卸下：移除指定英雄所有已装备的装备
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err, table? result
function EquipmentService.UnequipAll(uid, heroId)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "参数缺失" end

    local ok, err, result = EquipmentSystem.applyUnequipAll(equipData, heroId)
    if not ok then
        return false, err
    end
    if (result.removed or 0) > 0 then
        PDM.MarkDirty(uid, "equipment")
    end

    print("[EquipmentService] UNEQUIP_ALL uid=" .. tostring(uid)
        .. " heroId=" .. tostring(result.heroId) .. " removed=" .. tostring(result.removed))

    return true, nil, result
end

--- 仅在一键装备开始时复制数据，水合/候选试穿均不修改 PDM 的活表。
---@param value any
---@return any
local function copyEquipData(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = copyEquipData(entry)
    end
    return copy
end

--- 一键装备：按真实整套战力的正向净收益选择合法候选。
--- 普通槽逐槽优化；主副手联合枚举，避免双手/双持转换被单槽基准阻塞。
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err, table? result
function EquipmentService.EquipAllBest(uid, heroId)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "参数缺失" end
    if not HC.get(heroId) then return false, "英雄不存在" end

    local heroesData = PDM.GetModule(uid, "heroes")
    local artifactsData = PDM.GetModule(uid, "artifacts")
    local talentsData = PDM.GetModule(uid, "talents")
    local hd = heroesData and heroesData.roster
        and (heroesData.roster[heroId] or heroesData.roster[tostring(heroId)])
    local dualMode = AVC.getDualWieldMode(hd and hd.advBranch)
    local heroLevel = EquipmentSystem.getHeroLevel(heroesData, heroId)

    if not equipData.inventory then
        return true, nil, { heroId = heroId, equipped = 0, changes = 0 }
    end

    ---@type table
    local workingEquip = copyEquipData(equipData)
    local inventory = workingEquip.inventory
    EquipmentSystem.ensureHeroSlots(workingEquip, heroId)
    for _, equip in pairs(inventory) do
        if type(equip) == "table" then
            EquipmentSystem.hydrate(equip)
        end
    end

    -- 只排除其他英雄的物品；本英雄主副手必须能作为组合候选（含互换）。
    local occupiedByOthers = {}
    for hid, slots in pairs(equipData.equipped or {}) do
        if tonumber(hid) ~= heroId and type(slots) == "table" then
            for _, seq in pairs(slots) do
                local seqNum = tonumber(seq)
                if seqNum then occupiedByOthers[seqNum] = true end
            end
        end
    end

    local wearableSets = {}
    local candidates = {}
    for _, slotName in ipairs(EquipmentConfig.SLOTS) do
        wearableSets[slotName] = EquipmentSystem.getWearableTypeSet(heroId, slotName)
        candidates[slotName] = {}
    end

    -- 水合、等级和类型先过滤，不按静态分数截断；最终合法性仍由试穿验证。
    local seen = {}
    for seq in pairs(inventory) do
        local seqNum = tonumber(seq)
        if seqNum and seqNum > 0 and seqNum < math.huge
            and seqNum == math.floor(seqNum) and not seen[seqNum]
            and not occupiedByOthers[seqNum] then
            seen[seqNum] = true
            local equip = EquipmentSystem.getFromInventory(workingEquip, seqNum)
            if type(equip) == "table" and EquipmentSystem.checkLevelGate(heroLevel, equip) then
                for _, slotName in ipairs(EquipmentConfig.SLOTS) do
                    local wearable = wearableSets[slotName]
                    local matches = equip.slot == slotName
                    if slotName == "offhand" and dualMode then
                        matches = equip.slot == "weapon" and equip.grip == "onehand"
                        -- 双持副手沿用武器类型，不是常规盾牌/法器的副手类型集合。
                        wearable = wearableSets.weapon
                    end
                    if matches and (not wearable or wearable[equip.type]) then
                        local pool = candidates[slotName]
                        pool[#pool + 1] = seqNum
                    end
                end
            end
        end
    end
    for _, pool in pairs(candidates) do
        table.sort(pool)
    end
    -- false 为卸下该槽，允许双手 → 单手+副手和双持类型整体切换。
    table.insert(candidates.weapon, 1, false)
    table.insert(candidates.offhand, 1, false)

    ---@param equipment table
    local function buildContext(equipment)
        return EquipmentPower.buildContext(heroId, {
            heroes = heroesData,
            equipment = equipment,
            artifacts = artifactsData,
            talents = talentsData,
        })
    end

    ---@param ctx table
    ---@param slotName string
    ---@return table|nil
    local function bestForSlot(ctx, slotName)
        ---@type table|nil
        local best = nil
        local bestGain = 0
        for _, seq in ipairs(candidates[slotName]) do
            local evaluated = EquipmentPower.evaluate(ctx, seq, slotName)
            if evaluated.valid and evaluated.gain > bestGain then
                best = evaluated
                bestGain = evaluated.gain
            end
        end
        return best
    end

    ---@param ctx table
    ---@return table|nil
    local function bestWeaponPair(ctx)
        ---@type table|nil
        local best = nil
        local bestGain = 0
        for _, weaponSeq in ipairs(candidates.weapon) do
            ---@type table|nil
            local weapon = nil
            if weaponSeq then
                weapon = EquipmentSystem.getFromInventory(workingEquip, weaponSeq)
            end
            for _, offhandSeq in ipairs(candidates.offhand) do
                -- 一件装备不能同时占主副手；双手武器的唯一副手候选为空。
                local legalPair = not weaponSeq or not offhandSeq or weaponSeq ~= offhandSeq
                if weapon and weapon.grip == "twohand" and offhandSeq then
                    legalPair = false
                end
                if legalPair and offhandSeq and dualMode then
                    local offhand = EquipmentSystem.getFromInventory(workingEquip, offhandSeq)
                    if dualMode == "same" then
                        legalPair = weapon ~= nil and offhand ~= nil
                            and weapon.type == offhand.type
                    elseif dualMode == "different" and weapon and offhand then
                        legalPair = weapon.type ~= offhand.type
                    end
                end
                if legalPair then
                    -- evaluateLoadout 在隔离表上先清副手、再主手、最后副手。
                    -- 因而旧双持类型不会误拒绝最终合法的整体换装。
                    local evaluated = EquipmentPower.evaluateLoadout(ctx, {
                        weapon = weaponSeq,
                        offhand = offhandSeq,
                    })
                    if evaluated.valid and evaluated.gain > bestGain then
                        best = evaluated
                        bestGain = evaluated.gain
                    end
                end
            end
        end
        return best
    end

    local ordinaryChanged = false
    local order = { "weaponPair", "armor", "helmet", "shoes", "accessory", "weaponPair" }
    for index, slotName in ipairs(order) do
        -- 普通装备可能影响套装、倍率与上限，再基于新整套属性优化一次武器对。
        if index < #order or ordinaryChanged then
            local ctx = buildContext(workingEquip)
            if not ctx then return false, "角色属性数据不可用" end
            ---@type table|nil
            local best = nil
            if slotName == "weaponPair" then
                best = bestWeaponPair(ctx)
            else
                best = bestForSlot(ctx, slotName)
            end
            if best then
                workingEquip = best.equipment
                if slotName ~= "weaponPair" then ordinaryChanged = true end
                print("[EquipmentService] EQUIP_ALL_BEST preview uid=" .. tostring(uid)
                    .. " heroId=" .. tostring(heroId) .. " slot=" .. slotName
                    .. " gain=" .. tostring(best.gain)
                    .. " power=" .. tostring(best.previewPower))
            end
        end
    end

    -- 只提交本英雄已验证的最终槽位，不把试穿的其他英雄/背包表覆盖回活表。
    -- changed 统计最终真实不同的槽位（含双手换装卸掉副手），不统计中间试换次数。
    local initialSlots = EquipmentSystem.getHeroSlots(equipData, heroId) or {}
    local finalSlots = EquipmentSystem.getHeroSlots(workingEquip, heroId) or {}
    local changed = 0
    for _, slotName in ipairs(EquipmentConfig.SLOTS) do
        local oldSeq = initialSlots[slotName]
        local newSeq = finalSlots[slotName]
        if (tonumber(oldSeq) or oldSeq or nil) ~= (tonumber(newSeq) or newSeq or nil) then
            changed = changed + 1
        end
    end
    if changed > 0 then
        local liveSlots = EquipmentSystem.ensureHeroSlots(equipData, heroId)
        for _, slotName in ipairs(EquipmentConfig.SLOTS) do
            liveSlots[slotName] = finalSlots[slotName] or nil
        end
        PDM.MarkDirty(uid, "equipment")
    end

    print("[EquipmentService] EQUIP_ALL_BEST uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId) .. " total_changed=" .. changed)

    return true, nil, { heroId = heroId, equipped = changed, changes = changed }
end

-- ======================== 自动分解设置 ========================

---@param uid number
---@param autoQuality number  品质阈值 (0=关闭, 1~6=该品质及以下自动分解；6=至臻)
---@param autoLevel   number  等级阈值  (0=关闭, 1~60=N级及以下自动分解)
---@return boolean ok
---@return string|nil reason
---@return integer|nil clampedQuality 钳制后的品质阈值
---@return integer|nil clampedLevel 钳制后的等级阈值
function EquipmentService.SetAutoDecompose(uid, autoQuality, autoLevel)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then
        return false, "数据未加载"
    end

    -- 品质 6 档（至臻）、等级 0-60，与 UI/共享判定一致；此前钳 5/100 会导致至臻永不分解
    autoQuality = math.max(0, math.min(6, math.floor(tonumber(autoQuality) or 0)))
    autoLevel   = math.max(0, math.min(60, math.floor(tonumber(autoLevel) or 0)))

    if not equipData.settings then
        equipData.settings = {}
    end
    equipData.settings.autoQuality = autoQuality
    equipData.settings.autoLevel   = autoLevel
    PDM.MarkDirty(uid, "equipment")

    print("[EquipmentService] SetAutoDecompose uid=" .. tostring(uid)
        .. " autoQuality=" .. autoQuality .. " autoLevel=" .. autoLevel)
    return true, nil, autoQuality, autoLevel
end

--- 切换装备锁定状态（锁定后无法被分解）
---@param uid number
---@param seq number 装备序列号
---@return boolean ok
---@return string|nil err
---@return table|nil result { seq, locked }
function EquipmentService.ToggleEquipLock(uid, seq)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then
        return false, "数据未加载"
    end

    seq = tonumber(seq)
    if not seq then
        return false, "无效的装备序列号"
    end

    local equip = EquipmentSystem.getFromInventory(equipData, seq)
    if not equip then
        return false, "装备不存在"
    end

    equip.locked = not equip.locked or nil  -- 切换；解锁时置 nil 保持数据精简
    PDM.MarkDirty(uid, "equipment")

    print("[EquipmentService] ToggleEquipLock uid=" .. tostring(uid)
        .. " seq=" .. seq .. " locked=" .. tostring(equip.locked == true))
    return true, nil, { seq = seq, locked = equip.locked == true }
end

--- 读取自动分解设置（供 BattleService 调用）
---@param uid number
---@return number autoQuality
---@return number autoLevel
function EquipmentService.GetAutoDecomposeSettings(uid)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData or not equipData.settings then
        return 0, 0
    end
    return equipData.settings.autoQuality or 0, equipData.settings.autoLevel or 0
end

return EquipmentService
