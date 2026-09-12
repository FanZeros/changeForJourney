-- ============================================================================
-- LootService - 战利品领取业务逻辑
-- 职责: 领取/一键领取/分解战利品（纯逻辑，禁止网络 IO）
-- 层级: server/loot  |  通过 PDM 读写数据
-- ============================================================================

local PDM             = require("server.character.PlayerDataManager")
local CurrencyService = require("server.currency.CurrencyService")
local TaskService     = require("server.task.TaskService")
local EquipmentSystem = require("systems.EquipmentSystem")
local LootBoxSystem   = require("systems.LootBoxSystem")
local StageProvider   = require("shared.StageProvider")

local LootService = {}

-- ======================== 内部工具 ========================

--- 设置当前玩家的装备等级上限（每次领取前调用，避免多玩家全局冲突）
---@param uid number
local function applyPlayerLevelCap(uid)
    local battleData = PDM.GetModule(uid, "battle")
    if not battleData then
        LootBoxSystem.levelCap = 0
        return
    end
    local stageId = battleData.maxStageId or battleData.currentStageId or 0
    if stageId <= 0 then
        LootBoxSystem.levelCap = 0
        return
    end
    local stageConfig = StageProvider.GetForServer(PDM.GetServerId(uid))
    local entry = stageConfig.getStage(stageId)
    if entry and entry.monsterLevel and entry.monsterLevel > 0 then
        LootBoxSystem.levelCap = entry.monsterLevel
    else
        LootBoxSystem.levelCap = 0
    end
end

--- 构建装备摘要（避免传输完整装备数据）
---@param claimed table[] 装备列表
---@return table[] summary
local function buildClaimedSummary(claimed)
    local summary = {}
    for _, equip in ipairs(claimed) do
        summary[#summary + 1] = {
            seq        = equip.seq,
            templateId = equip.templateId,
            quality    = equip.quality,
            level      = equip.level,
            name       = equip.name,
        }
    end
    return summary
end

-- ======================== 领取指定组战利品 ========================

---@param uid number
---@param index number 种子条目索引（1-based）
---@return boolean ok
---@return string|nil reason
---@return table|nil result { claimedCount, claimed, bagFull, remaining }
function LootService.ClaimGroup(uid, index)
    local lootboxData = PDM.GetModule(uid, "lootbox")
    local equipData   = PDM.GetModule(uid, "equipment")
    if not lootboxData or not equipData then
        return false, "数据未加载"
    end

    -- 每次领取前按玩家实时设置等级上限
    applyPlayerLevelCap(uid)

    if not index or index < 1 or index > #(lootboxData.seeds or {}) then
        return false, "无效的战利品索引"
    end

    if EquipmentSystem.isInventoryFull(equipData) then
        return false, "背包已满", { bagFull = true }
    end

    -- 领取前修正该条种子等级
    local cap = LootBoxSystem.levelCap
    if cap > 0 then
        local seed = lootboxData.seeds[index]
        if seed and seed.level and seed.level > cap then
            seed.level = cap
        end
    end

    local claimed, bagFull = LootBoxSystem.claimGroup(lootboxData, index, equipData)

    if #claimed == 0 then
        return false, "领取失败"
    end

    PDM.MarkDirty(uid, "lootbox")
    PDM.MarkDirty(uid, "equipment")

    local remaining = LootBoxSystem.getTotalCount(lootboxData)
    print("[LootService] ClaimGroup uid=" .. tostring(uid)
        .. " claimed=" .. #claimed .. " bagFull=" .. tostring(bagFull)
        .. " remaining=" .. remaining)

    return true, nil, {
        claimedCount = #claimed,
        claimed      = buildClaimedSummary(claimed),
        bagFull      = bagFull,
        remaining    = remaining,
    }
end

-- ======================== 一键领取全部战利品 ========================

---@param uid number
---@return boolean ok
---@return string|nil reason
---@return table|nil result { claimedCount, claimed, bagFull, remaining }
function LootService.ClaimAll(uid)
    local lootboxData = PDM.GetModule(uid, "lootbox")
    local equipData   = PDM.GetModule(uid, "equipment")
    if not lootboxData or not equipData then
        return false, "数据未加载"
    end

    -- 每次领取前按玩家实时设置等级上限
    applyPlayerLevelCap(uid)

    if not lootboxData.seeds or #lootboxData.seeds == 0 then
        return false, "战利品为空"
    end

    if EquipmentSystem.isInventoryFull(equipData) then
        return false, "背包已满", { bagFull = true }
    end

    -- 领取前修正种子等级（确保客户端显示与实际生成一致）
    local cap = LootBoxSystem.levelCap
    if cap > 0 then
        local seedFixed = false
        for _, seed in ipairs(lootboxData.seeds) do
            if seed.level and seed.level > cap then
                seed.level = cap
                seedFixed = true
            end
        end
        if seedFixed then
            LootBoxSystem.consolidateSeeds(lootboxData)
        end
    end

    local claimed, bagFull = LootBoxSystem.claimAll(lootboxData, equipData)

    if #claimed > 0 then
        PDM.MarkDirty(uid, "lootbox")
        PDM.MarkDirty(uid, "equipment")
    end

    local remaining = LootBoxSystem.getTotalCount(lootboxData)
    print("[LootService] ClaimAll uid=" .. tostring(uid)
        .. " claimed=" .. #claimed .. " bagFull=" .. tostring(bagFull)
        .. " remaining=" .. remaining)

    return true, nil, {
        claimedCount = #claimed,
        claimed      = buildClaimedSummary(claimed),
        bagFull      = bagFull,
        remaining    = remaining,
    }
end

-- ======================== 一键分解全部战利品 ========================

---@param uid number
---@return boolean ok
---@return string|nil reason
---@return table|nil result { decomposeCount, essenceReward }
function LootService.DecomposeAll(uid)
    local lootboxData = PDM.GetModule(uid, "lootbox")
    if not lootboxData then
        return false, "数据未加载"
    end

    if not lootboxData.seeds or #lootboxData.seeds == 0 then
        return false, "战利品为空"
    end

    local totalEssence, totalPieces = LootBoxSystem.decomposeAll(lootboxData)

    if totalPieces > 0 then
        CurrencyService.Add(uid, "essence", totalEssence)
        PDM.MarkDirty(uid, "lootbox")
        -- 任务进度：分解装备
        TaskService.UpdateProgress(uid, "decompose", totalPieces)
    end

    print("[LootService] DecomposeAll uid=" .. tostring(uid)
        .. " pieces=" .. totalPieces
        .. " essence=+" .. totalEssence)

    return true, nil, {
        decomposeCount = totalPieces,
        essenceReward  = totalEssence,
    }
end

-- ======================== 分解指定组战利品 ========================

---@param uid number
---@param index number 1-based seed group index
---@return boolean ok
---@return string|nil reason
---@return table|nil result { decomposeCount, essenceReward }
function LootService.DecomposeOne(uid, index)
    local lootboxData = PDM.GetModule(uid, "lootbox")
    if not lootboxData then
        return false, "数据未加载"
    end

    if not lootboxData.seeds or #lootboxData.seeds == 0 then
        return false, "战利品为空"
    end

    if not index or index < 1 or index > #lootboxData.seeds then
        return false, "无效的索引"
    end

    local totalEssence, totalPieces = LootBoxSystem.decomposeOne(lootboxData, index)

    if totalPieces > 0 then
        CurrencyService.Add(uid, "essence", totalEssence)
        PDM.MarkDirty(uid, "lootbox")
        TaskService.UpdateProgress(uid, "decompose", totalPieces)
    end

    print("[LootService] DecomposeOne uid=" .. tostring(uid)
        .. " index=" .. tostring(index)
        .. " pieces=" .. totalPieces
        .. " essence=+" .. totalEssence)

    return true, nil, {
        decomposeCount = totalPieces,
        essenceReward  = totalEssence,
    }
end

return LootService
