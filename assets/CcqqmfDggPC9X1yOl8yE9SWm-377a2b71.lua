-- ============================================================================
-- EquipmentService - 装备管理业务逻辑
-- 职责: GM给装备、穿戴/卸下装备、双持互斥
-- 层级: server/equipment  |  通过 PDM 读写，禁止网络 IO
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local EquipmentSystem  = require("systems.EquipmentSystem")
local BlacksmithConfig = require("config.BlacksmithConfig")
local AVC             = require("config.AdvancementConfig")
local HC              = require("config.HeroConfig")
local CC              = require("config.ClassConfig")
local AD              = require("systems.AttributeDef")

local EquipmentService = {}

-- ======================== 战斗力计算（复刻客户端逻辑） ========================

local EXCLUDED_KEYS_BY_DMG_TYPE = {
    ["物理"] = {
        magAtk=true, magCritRate=true, magCritDmg=true, magPen=true,
        magDmgBonus=true, magAtkBonus=true,
        healAmount=true, healBonus=true, healCritRate=true, healCritDmg=true,
    },
    ["魔法"] = {
        physAtk=true, physCritRate=true, physCritDmg=true, physPen=true,
        physDmgBonus=true, physAtkBonus=true,
        healAmount=true, healBonus=true, healCritRate=true, healCritDmg=true,
    },
    ["治疗"] = {
        physAtk=true, physCritRate=true, physCritDmg=true, physPen=true,
        physDmgBonus=true, physAtkBonus=true,
        magAtk=true, magCritRate=true, magCritDmg=true, magPen=true,
        magDmgBonus=true, magAtkBonus=true,
    },
}

local BASE_STAT_SET = {}
for _, k in ipairs(AD.BASE_STATS) do BASE_STAT_SET[k] = true end

local function calcStatPower(key, value, excluded)
    if excluded and BASE_STAT_SET[key] then
        local derivatives = AD.DERIVATIVES and AD.DERIVATIVES[key]
        if derivatives then
            local effectiveVM = 0
            for _, d in ipairs(derivatives) do
                if not excluded[d.attr] then
                    local dMeta = AD.META[d.attr]
                    if dMeta and dMeta.valueModel and dMeta.valueModel > 0 then
                        if dMeta.dataType == AD.TYPE_PCT then
                            effectiveVM = effectiveVM + d.perPoint * dMeta.valueModel / 100
                        else
                            effectiveVM = effectiveVM + d.perPoint * dMeta.valueModel
                        end
                    end
                end
            end
            return value * effectiveVM
        end
    end
    if excluded and excluded[key] then return 0 end
    local meta = AD.META[key]
    if not meta or not meta.valueModel or meta.valueModel <= 0 then return 0 end
    if meta.dataType == AD.TYPE_PCT then
        return value * meta.valueModel / 100
    else
        return value * meta.valueModel
    end
end

local function calcEquipPower(equip, heroId)
    if not equip then return 0 end
    local excluded = nil
    if heroId then
        local hero = HC.HEROES and HC.HEROES[heroId]
        if hero and hero.dmgMainType then
            excluded = EXCLUDED_KEYS_BY_DMG_TYPE[hero.dmgMainType]
        end
    end
    local power = 0
    local enhBoost = BlacksmithConfig.getEnhanceBoost(equip.enhanceLevel or 0)
    for _, s in ipairs(equip.baseStats or {}) do
        power = power + calcStatPower(s[1], s[2] * (1 + enhBoost), excluded)
    end
    for _, affix in ipairs(equip.affixes or {}) do
        power = power + calcStatPower(affix.key, affix.value, excluded)
    end
    return math.floor(power)
end

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

    seq    = tonumber(seq)
    heroId = tonumber(heroId)
    if not seq or not heroId or not slot then
        return false, "参数缺失"
    end

    local seqStr = tostring(seq)

    -- 验证装备存在于背包
    if not equipData.inventory or not equipData.inventory[seqStr] then
        return false, "装备不存在"
    end

    -- 验证槽位匹配
    local equip = equipData.inventory[seqStr]
    local isDualWieldOffhand = false
    if equip.slot ~= slot then
        -- 特殊情况：207/220 天赋允许单手武器放入副手槽
        if slot == "offhand" and equip.slot == "weapon" and equip.grip == "onehand" then
            local heroesData = PDM.GetModule(uid, "heroes")
            local hd = heroesData and heroesData.roster and (heroesData.roster[heroId] or heroesData.roster[tostring(heroId)])
            local advBranch = hd and hd.advBranch
            local dualMode = AVC.getDualWieldMode(advBranch)
            if dualMode then
                local mainWeaponSeq = equipData.equipped and equipData.equipped[heroId] and equipData.equipped[heroId]["weapon"]
                local mainWeaponType = nil
                if mainWeaponSeq then
                    local mainWeapon = equipData.inventory[tostring(mainWeaponSeq)]
                    mainWeaponType = mainWeapon and mainWeapon.type
                end
                if dualMode == "different" and mainWeaponType and equip.type == mainWeaponType then
                    return false, "武器精通：副手必须装备不同类型的武器"
                elseif dualMode == "same" and mainWeaponType and equip.type ~= mainWeaponType then
                    return false, "双刃精通：副手必须装备相同类型的武器"
                end
                isDualWieldOffhand = true
                print("[EquipmentService] EQUIP 207/220 dual-wield: weapon→offhand, mode=" .. dualMode .. " type=" .. equip.type)
            else
                return false, "槽位不匹配"
            end
        else
            return false, "槽位不匹配"
        end
    end

    -- 初始化 equipped 结构
    if not equipData.equipped then
        equipData.equipped = {}
    end
    if not equipData.equipped[heroId] then
        equipData.equipped[heroId] = {}
    end

    -- 防止同一装备被多个英雄穿戴：自动从原英雄卸下
    if equipData.equipped then
        for hid, slots in pairs(equipData.equipped) do
            for s, eqSeq in pairs(slots) do
                if tostring(eqSeq) == seqStr then
                    if hid == heroId and s == slot then
                        -- 已经在目标位置
                    else
                        slots[s] = nil
                        print("[EquipmentService] EQUIP auto-unequip seq=" .. seqStr
                            .. " from hero=" .. tostring(hid) .. " slot=" .. s)
                    end
                end
            end
        end
    end

    -- 记录旧装备
    local oldSeq = equipData.equipped[heroId][slot]

    -- ====== 双手武器互斥逻辑 ======
    local unequippedSlots = {}

    if slot == "weapon" and equip.grip == "twohand" then
        if equipData.equipped[heroId]["offhand"] then
            local removedSeq = equipData.equipped[heroId]["offhand"]
            equipData.equipped[heroId]["offhand"] = nil
            unequippedSlots[#unequippedSlots + 1] = { slot = "offhand", seq = removedSeq }
            print("[EquipmentService] EQUIP twohand→remove offhand seq=" .. tostring(removedSeq))
        end
    elseif slot == "offhand" then
        local weaponSeq = equipData.equipped[heroId]["weapon"]
        if weaponSeq then
            local weaponEquip = equipData.inventory[tostring(weaponSeq)]
            if weaponEquip and weaponEquip.grip == "twohand" then
                equipData.equipped[heroId]["weapon"] = nil
                unequippedSlots[#unequippedSlots + 1] = { slot = "weapon", seq = weaponSeq }
                print("[EquipmentService] EQUIP offhand→remove twohand weapon seq=" .. tostring(weaponSeq))
            end
        end
    end

    -- 穿戴新装备
    equipData.equipped[heroId][slot] = seq
    PDM.MarkDirty(uid, "equipment")

    print("[EquipmentService] EQUIP uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId) .. " slot=" .. slot
        .. " seq=" .. seqStr
        .. (oldSeq and (" replaced=" .. tostring(oldSeq)) or ""))

    return true, nil, {
        seq     = seq,
        heroId  = heroId,
        slot    = slot,
        oldSeq  = oldSeq,
        unequippedSlots = #unequippedSlots > 0 and unequippedSlots or nil,
    }
end

--- 卸下装备
---@param uid number
---@param heroId number|nil
---@param slot string|nil
---@return boolean ok, string? err, table? result
function EquipmentService.UnequipItem(uid, heroId, slot)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId or not slot then
        return false, "参数缺失"
    end

    if not equipData.equipped or not equipData.equipped[heroId] then
        return false, "无已装备数据"
    end

    local curSeq = equipData.equipped[heroId][slot]
    if not curSeq then
        return false, "该槽位无装备"
    end

    equipData.equipped[heroId][slot] = nil
    PDM.MarkDirty(uid, "equipment")

    print("[EquipmentService] UNEQUIP uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId) .. " slot=" .. slot
        .. " seq=" .. tostring(curSeq))

    return true, nil, { heroId = heroId, slot = slot, removedSeq = curSeq }
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

    if not equipData.equipped or not equipData.equipped[heroId] then
        return true, nil, { heroId = heroId, removed = 0 }
    end

    local removed = 0
    for slot, _ in pairs(equipData.equipped[heroId]) do
        equipData.equipped[heroId][slot] = nil
        removed = removed + 1
    end

    if removed > 0 then
        PDM.MarkDirty(uid, "equipment")
    end

    print("[EquipmentService] UNEQUIP_ALL uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId) .. " removed=" .. removed)

    return true, nil, { heroId = heroId, removed = removed }
end

--- 一键装备：为指定英雄的每个槽位装备战斗力最高的可穿戴装备
--- 处理顺序：weapon → armor → accessory → offhand（武器先于副手，便于双手武器互斥判断）
---@param uid number
---@param heroId number|nil
---@return boolean ok, string? err, table? result
function EquipmentService.EquipAllBest(uid, heroId)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return false, "数据未加载" end

    heroId = tonumber(heroId)
    if not heroId then return false, "参数缺失" end

    local heroCfg = HC.get(heroId)
    if not heroCfg then return false, "英雄不存在" end

    if not equipData.equipped then equipData.equipped = {} end
    if not equipData.equipped[heroId] then equipData.equipped[heroId] = {} end

    local inventory = equipData.inventory
    if not inventory then return true, nil, { heroId = heroId, equipped = 0 } end

    -- 收集所有英雄已装备的 seq（不可用于装备）
    local equippedSeqNums = {}
    for _, heroSlots in pairs(equipData.equipped) do
        if type(heroSlots) == "table" then
            for _, eqSeq in pairs(heroSlots) do
                local n = tonumber(eqSeq)
                if n then equippedSeqNums[n] = true end
            end
        end
    end

    -- 构建各槽位的可穿戴子类型集合
    local wearableSets = {}

    -- weapon
    local weaponTypes = heroCfg.weaponTypes
    if weaponTypes and #weaponTypes > 0 then
        wearableSets["weapon"] = {}
        for _, t in ipairs(weaponTypes) do wearableSets["weapon"][t] = true end
    end

    -- offhand
    local offhandTypes = heroCfg.offhandTypes
    if offhandTypes and #offhandTypes > 0 then
        wearableSets["offhand"] = {}
        for _, t in ipairs(offhandTypes) do wearableSets["offhand"][t] = true end
    end

    -- armor
    local classCfg = CC.get(heroCfg.classId)
    if classCfg and classCfg.armorTypes and #classCfg.armorTypes > 0 then
        wearableSets["armor"] = {}
        for _, armorEnum in ipairs(classCfg.armorTypes) do
            local name = AD.ARMOR_TYPE_NAME[armorEnum]
            if name then wearableSets["armor"][name] = true end
        end
    end

    -- accessory: nil = 不限制

    -- 双持模式检测
    local heroesData = PDM.GetModule(uid, "heroes")
    local hd = heroesData and heroesData.roster and (heroesData.roster[heroId] or heroesData.roster[tostring(heroId)])
    local advBranch = hd and hd.advBranch
    local dualMode = AVC.getDualWieldMode(advBranch)

    -- 按顺序处理：weapon → armor → accessory → offhand
    local SLOT_ORDER = { "weapon", "armor", "accessory", "offhand" }
    local changed = 0

    for _, slotName in ipairs(SLOT_ORDER) do
        local ws = wearableSets[slotName]  -- nil = 不限制

        -- 当前已装备的战斗力
        local curSeq = equipData.equipped[heroId][slotName]
        local curPower = 0
        if curSeq then
            local curEquip = inventory[tostring(curSeq)]
            if curEquip then
                curPower = calcEquipPower(curEquip, heroId)
            end
        end

        -- 双手武器特殊处理：武器槽的双手武器基准 = 当前武器 + 当前副手
        -- 副手槽处理时，已装备双手武器则跳过
        local baseline = curPower
        if slotName == "weapon" then
            local ohSeq = equipData.equipped[heroId]["offhand"]
            if ohSeq then
                local ohEquip = inventory[tostring(ohSeq)]
                if ohEquip then
                    baseline = curPower  -- 单手武器只比自身；双手武器另行处理
                end
            end
        elseif slotName == "offhand" then
            -- 如果主手是双手武器，副手不可装备
            local wpnSeq = equipData.equipped[heroId]["weapon"]
            if wpnSeq then
                local wpnEquip = inventory[tostring(wpnSeq)]
                if wpnEquip and wpnEquip.grip == "twohand" then
                    goto continue_slot
                end
            end
        end

        -- 遍历背包找战力最高的可穿戴装备
        -- 策略：先找绝对战力最高的候选，循环结束后再判断是否优于当前
        local bestSeq      = nil
        local bestPower    = 0
        local bestBaseline = baseline  -- 记录最优候选对应的基准（双手武器基准不同）
        local bestGrip     = nil

        for seq, equip in pairs(inventory) do
            local seqNum = tonumber(seq)
            if not seqNum then goto continue_item end

            -- 跳过已被任何英雄装备的
            if equippedSeqNums[seqNum] then goto continue_item end

            -- 槽位匹配
            local matchSlot = false
            if equip.slot == slotName then
                matchSlot = true
            elseif slotName == "offhand" and equip.slot == "weapon" and equip.grip == "onehand" and dualMode then
                -- 双持天赋：单手武器可放副手
                local mainWeaponSeq = equipData.equipped[heroId]["weapon"]
                local mainWeaponType = nil
                if mainWeaponSeq then
                    local mw = inventory[tostring(mainWeaponSeq)]
                    mainWeaponType = mw and mw.type
                end
                if dualMode == "different" and mainWeaponType and equip.type == mainWeaponType then
                    goto continue_item
                elseif dualMode == "same" and mainWeaponType and equip.type ~= mainWeaponType then
                    goto continue_item
                end
                matchSlot = true
            end
            if not matchSlot then goto continue_item end

            -- 类型限制
            if ws and not ws[equip.type] then goto continue_item end

            -- 计算该装备战力（包含 baseStats + affixes 随机词缀）
            local itemPower = calcEquipPower(equip, heroId)

            -- 双手武器替换主手时，基准 = 当前主手 + 当前副手（卸副手的代价）
            local itemBaseline = baseline
            if slotName == "weapon" and equip.grip == "twohand" then
                local ohSeq2 = equipData.equipped[heroId]["offhand"]
                if ohSeq2 then
                    local ohEquip2 = inventory[tostring(ohSeq2)]
                    if ohEquip2 then
                        itemBaseline = curPower + calcEquipPower(ohEquip2, heroId)
                    end
                end
            end

            -- 选择净收益最大的候选（双手武器 baseline 已含副手代价）
            local itemGain = itemPower - itemBaseline
            local bestGain = bestPower - bestBaseline
            if itemGain > bestGain then
                bestSeq      = seqNum
                bestPower    = itemPower
                bestBaseline = itemBaseline
                bestGrip     = equip.grip
            end

            ::continue_item::
        end

        -- 循环结束后统一判断：最优候选必须真的优于当前才替换
        if bestSeq and bestPower > bestBaseline then
            -- 清除旧装备在 equippedSeqNums 中的占用
            if curSeq then
                equippedSeqNums[tonumber(curSeq)] = nil
            end

            -- 双手武器互斥处理
            if slotName == "weapon" and bestGrip == "twohand" then
                local ohSeq = equipData.equipped[heroId]["offhand"]
                if ohSeq then
                    equippedSeqNums[tonumber(ohSeq)] = nil
                    equipData.equipped[heroId]["offhand"] = nil
                end
            elseif slotName == "offhand" then
                local wpnSeq = equipData.equipped[heroId]["weapon"]
                if wpnSeq then
                    local wpnEquip = inventory[tostring(wpnSeq)]
                    if wpnEquip and wpnEquip.grip == "twohand" then
                        equippedSeqNums[tonumber(wpnSeq)] = nil
                        equipData.equipped[heroId]["weapon"] = nil
                    end
                end
            end

            -- 装备新物品
            equipData.equipped[heroId][slotName] = bestSeq
            equippedSeqNums[bestSeq] = true
            changed = changed + 1

            print("[EquipmentService] EQUIP_ALL_BEST uid=" .. tostring(uid)
                .. " heroId=" .. tostring(heroId) .. " slot=" .. slotName
                .. " seq=" .. tostring(bestSeq) .. " power=" .. bestPower)
        end

        ::continue_slot::
    end

    if changed > 0 then
        PDM.MarkDirty(uid, "equipment")
    end

    print("[EquipmentService] EQUIP_ALL_BEST uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId) .. " total_changed=" .. changed)

    return true, nil, { heroId = heroId, equipped = changed }
end

-- ======================== 自动分解设置 ========================

---@param uid number
---@param autoQuality number  品质阈值 (0=关闭, 1~5=该品质及以下自动分解)
---@param autoLevel   number  等级阈值  (0=关闭, N=N级及以下自动分解)
---@return boolean ok
---@return string|nil reason
function EquipmentService.SetAutoDecompose(uid, autoQuality, autoLevel)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then
        return false, "数据未加载"
    end

    autoQuality = math.max(0, math.min(5, math.floor(tonumber(autoQuality) or 0)))
    autoLevel   = math.max(0, math.min(100, math.floor(tonumber(autoLevel) or 0)))

    if not equipData.settings then
        equipData.settings = {}
    end
    equipData.settings.autoQuality = autoQuality
    equipData.settings.autoLevel   = autoLevel
    PDM.MarkDirty(uid, "equipment")

    print("[EquipmentService] SetAutoDecompose uid=" .. tostring(uid)
        .. " autoQuality=" .. autoQuality .. " autoLevel=" .. autoLevel)
    return true, nil
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
