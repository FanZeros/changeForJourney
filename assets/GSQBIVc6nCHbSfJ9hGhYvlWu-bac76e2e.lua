-- ============================================================================
-- EquipLevelCompat - 装备等级版本兼容模块
-- 职责: 玩家登录时检查所有装备等级及战利品种子等级，若高于当前关卡怪物等级则降级
-- 场景: 旧版本关卡等级膨胀，新版本大幅降低后，老玩家数据需修正
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local StageProvider   = require("shared.StageProvider")
local LootBoxSystem   = require("systems.LootBoxSystem")
local AffixConfig     = require("config.AffixConfig")
local EquipmentConfig = require("config.EquipmentConfig")

local EquipLevelCompat = {}

--- 获取当前关卡怪物等级上限
---@param uid number
---@return number maxLevel (0 表示无法确定，不做处理)
local function getMaxLevel(uid)
    local battleData = PDM.GetModule(uid, "battle")
    if not battleData then return 0 end

    local stageId = battleData.maxStageId or battleData.currentStageId or 0
    if stageId <= 0 then return 0 end

    local stageConfig = StageProvider.GetForServer(PDM.GetServerId(uid))
    local stageEntry = stageConfig.getStage(stageId)
    if not stageEntry then return 0 end

    local maxLevel = stageEntry.monsterLevel
    if not maxLevel or maxLevel <= 0 then return 0 end

    return maxLevel
end

--- 执行装备等级兼容检查（主入口）
--- 遍历背包 + 已穿戴装备 + 战利品种子，将超过当前关卡怪物等级的数据降级
---@param uid number 玩家 UID
---@return number downgradeCount 降级的装备数量
function EquipLevelCompat.Check(uid)
    local ok, result = pcall(EquipLevelCompat._doCheck, uid)
    if not ok then
        -- 兼容检查不应阻塞登录流程，出错时仅打印警告
        print("[EquipLevelCompat] ERROR (不影响登录): " .. tostring(result))
        return 0
    end
    return result or 0
end

--- 内部实现（被 pcall 包裹，任何异常不会阻塞登录）
---@param uid number
---@return number
function EquipLevelCompat._doCheck(uid)
    local totalFixed = 0

    -- ⓪ 修正关卡进度：currentStageId 落后于 maxStageId 时同步
    EquipLevelCompat._fixStageProgress(uid)

    -- ① 修正旧版格挡词缀（不依赖 maxLevel，优先执行）
    totalFixed = totalFixed + EquipLevelCompat._fixLegacyBlockAffixes(uid)

    local maxLevel = getMaxLevel(uid)
    if maxLevel <= 0 then return totalFixed end

    -- 注意：不在此处设置 LootBoxSystem.levelCap（多玩家服务器会互相覆盖）
    -- 多人模式下由 LootService.applyPlayerLevelCap 在每次领取时实时设置

    -- ② 修正背包 + 穿戴装备等级
    totalFixed = totalFixed + EquipLevelCompat._fixEquipments(uid, maxLevel)

    -- ③ 修正战利品箱子种子等级
    totalFixed = totalFixed + EquipLevelCompat._fixLootboxSeeds(uid, maxLevel)

    return totalFixed
end

--- 修正关卡进度：currentStageId 落后于 maxStageId 时同步到 maxStageId
---@param uid number
function EquipLevelCompat._fixStageProgress(uid)
    local battleData = PDM.GetModule(uid, "battle")
    if not battleData then return end

    local currentId = battleData.currentStageId or 0
    local maxId = battleData.maxStageId or 0

    if maxId > 0 and currentId < maxId then
        print(string.format("[EquipLevelCompat] 修正关卡进度 uid=%s: currentStageId %d → %d (maxStageId)",
            tostring(uid), currentId, maxId))
        battleData.currentStageId = maxId
        PDM.MarkDirty(uid, "battle")
    end
end

--- 修正背包和穿戴装备
---@param uid number
---@param maxLevel number
---@return number downgradeCount
function EquipLevelCompat._fixEquipments(uid, maxLevel)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData then return 0 end

    local downgradeCount = 0

    -- 遍历背包装备
    if equipData.inventory then
        for seq, equip in pairs(equipData.inventory) do
            if type(equip) == "table" and equip.level and equip.level > maxLevel then
                print(string.format("[EquipLevelCompat] 降级装备 seq=%s: Lv.%d → Lv.%d (%s)",
                    tostring(seq), equip.level, maxLevel, equip.name or equip.templateId or "?"))
                equip.level = maxLevel
                equip.baseStats = nil  -- 清空缓存，hydrate 时按新等级重算
                downgradeCount = downgradeCount + 1
            end
        end
    end

    if downgradeCount > 0 then
        PDM.MarkDirty(uid, "equipment")
        print(string.format("[EquipLevelCompat] uid=%s 装备降级 %d 件至 Lv.%d",
            tostring(uid), downgradeCount, maxLevel))
    end

    return downgradeCount
end

--- 修正旧版随机词缀：物理/魔法格挡率旧基础值 6%，新版基础值 2%
--- 旧档中已生成的词缀 value 需要按 2/6 降档；新版本生成的 2% 词缀不会再处理。
---@param uid number
---@return number fixedCount
function EquipLevelCompat._fixLegacyBlockAffixes(uid)
    local equipData = PDM.GetModule(uid, "equipment")
    if not equipData or not equipData.inventory then return 0 end

    -- 不使用一次性标志：阈值判断 (newMax * 1.05) 已防止重复修复
    -- 这样后续获得的旧装备也能被正确降档

    local physTpl = AffixConfig.BY_KEY and AffixConfig.BY_KEY["physBlockRate"]
    local magTpl  = AffixConfig.BY_KEY and AffixConfig.BY_KEY["magBlockRate"]
    local blockAffixIds = {}
    if physTpl then blockAffixIds[physTpl.id] = true end
    if magTpl then blockAffixIds[magTpl.id] = true end

    local fixedCount = 0
    for seq, equip in pairs(equipData.inventory) do
        if type(equip) == "table" and type(equip.affixes) == "table" then
            local level = tonumber(equip.level) or 1
            local levelMult = 1 + (level - 1) * EquipmentConfig.LEVEL_SCALE
            local qDef = equip.quality and EquipmentConfig.QUALITY[equip.quality]
            local randomStrength = qDef and qDef.randomStrength or 1.0
            local gripMult = (equip.grip == "twohand") and 2 or 1

            for _, affix in ipairs(equip.affixes) do
                local isBlockAffix = blockAffixIds[affix.affixId] == true
                    or affix.key == "physBlockRate"
                    or affix.key == "magBlockRate"
                local affixQ = AffixConfig.QUALITY[affix.quality or 1]
                if isBlockAffix and affixQ and type(affix.value) == "number" and affix.value > 0 then
                    -- 新版基础值为 2%，旧版为 6%。只处理超过新版可能上限的旧值，避免误伤已按新版生成的词缀。
                    local newMax = 2.0 * affixQ.maxMult * levelMult * randomStrength * gripMult
                    if affix.value > newMax * 1.05 then
                        local oldValue = affix.value
                        affix.value = oldValue / 3
                        fixedCount = fixedCount + 1
                        print(string.format(
                            "[EquipLevelCompat] 格挡词缀降档 seq=%s affixId=%s q=%s Lv.%d %.3f%% → %.3f%%",
                            tostring(seq), tostring(affix.affixId), tostring(affix.quality), level, oldValue, affix.value))
                    end
                end
            end
        end
    end

    if fixedCount > 0 then
        PDM.MarkDirty(uid, "equipment")
        print(string.format("[EquipLevelCompat] uid=%s 旧版格挡词缀降档 %d 条", tostring(uid), fixedCount))
    end
    return fixedCount
end

--- 修正战利品箱子种子等级
---@param uid number
---@param maxLevel number
---@return number fixedCount
function EquipLevelCompat._fixLootboxSeeds(uid, maxLevel)
    local lootboxData = PDM.GetModule(uid, "lootbox")
    if not lootboxData or not lootboxData.seeds then return 0 end

    local fixedCount = 0

    for i, seed in ipairs(lootboxData.seeds) do
        if type(seed) == "table" and seed.level and seed.level > maxLevel then
            print(string.format("[EquipLevelCompat] 降级战利品种子 #%d: Lv.%d → Lv.%d (count=%d)",
                i, seed.level, maxLevel, seed.count or 1))
            seed.level = maxLevel
            fixedCount = fixedCount + 1
        end
    end

    if fixedCount > 0 then
        -- 降级后可能产生重复的 quality+level 组合，合并它们
        EquipLevelCompat._consolidateSeeds(lootboxData)
        PDM.MarkDirty(uid, "lootbox")
        print(string.format("[EquipLevelCompat] uid=%s 战利品种子降级 %d 条至 Lv.%d",
            tostring(uid), fixedCount, maxLevel))
    end

    return fixedCount
end

--- 合并同 quality+level 的种子条目
---@param lootboxData table
function EquipLevelCompat._consolidateSeeds(lootboxData)
    if not lootboxData or not lootboxData.seeds then return end

    local merged = {}
    local keyMap = {}  -- "quality_level" → merged index

    for _, seed in ipairs(lootboxData.seeds) do
        if type(seed) == "table" and seed.count and seed.count > 0 then
            local key = tostring(seed.quality or 0) .. "_" .. tostring(seed.level or 0)
            local idx = keyMap[key]
            if idx then
                merged[idx].count = merged[idx].count + seed.count
            else
                merged[#merged + 1] = { quality = seed.quality, level = seed.level, count = seed.count }
                keyMap[key] = #merged
            end
        end
    end

    lootboxData.seeds = merged
end

return EquipLevelCompat
