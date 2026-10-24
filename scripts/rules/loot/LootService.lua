-- ============================================================================
-- LootService - 战利品领取业务逻辑
-- 职责: 领取/一键领取/分解战利品（纯逻辑，禁止网络 IO）
-- 层级: server/loot  |  通过 PDM 读写数据
-- ============================================================================

local PDM             = require("rules.character.PlayerDataManager")
local CurrencyService = require("rules.currency.CurrencyService")
local TaskService     = require("rules.task.TaskService")
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
    local stageConfig = StageProvider.Get()
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

--- 仅修正旧分组；已确定的装备原表、等级与随机结果都不能改写。
---@param seed table
---@param cap number
---@return boolean changed
local function capLegacySeed(seed, cap)
    if not seed.equip and seed.level and seed.level > cap then
        seed.level = cap
        return true
    end
    return false
end

--- 批领在任一旧分组改级后才合并；单领必须保留原索引，不走合并。
---@param lootboxData table
local function prepareAllSeeds(lootboxData)
    local cap = LootBoxSystem.levelCap
    if cap > 0 then
        local seedFixed = false
        for _, seed in ipairs(lootboxData.seeds) do
            if capLegacySeed(seed, cap) then
                seedFixed = true
            end
        end
        if seedFixed then
            LootBoxSystem.consolidateSeeds(lootboxData)
        end
    end
end

--- 两次推送不能合批或延后：每一次 MarkDirty 都可能同步重入。
---@param uid number
local function notifyClaim(uid)
    PDM.MarkDirty(uid, "lootbox")
    PDM.MarkDirty(uid, "equipment")
end

--- MarkDirty 可同步重入：先推两模块，再统计和打印，最后取摘要。
--- 不提前复制 claimed 或重取 lootboxData，回调对原表的修改仍按原时序可见。
---@param uid number
---@param operation string
---@param lootboxData table
---@param claimed table[]
---@param bagFull boolean
---@return table
local function publishClaim(uid, operation, lootboxData, claimed, bagFull)
    local remaining = LootBoxSystem.getTotalCount(lootboxData)
    print("[LootService] " .. operation .. " uid=" .. tostring(uid)
        .. " claimed=" .. #claimed .. " bagFull=" .. tostring(bagFull)
        .. " remaining=" .. remaining)

    return {
        claimedCount = #claimed,
        claimed      = buildClaimedSummary(claimed),
        bagFull      = bagFull,
        remaining    = remaining,
    }
end

--- 分解交付顺序独立于领取：加精粹（含同步推送）→ 遗匣 → 任务进度。
--- Add 必须在交付时从导出表读取，不能缓存函数；返回值仍不参与业务判定。
---@param uid number
---@param totalEssence number
---@param totalPieces number
local function deliverDecomposition(uid, totalEssence, totalPieces)
    if totalPieces > 0 then
        CurrencyService.Add(uid, "essence", totalEssence)
        PDM.MarkDirty(uid, "lootbox")
        TaskService.UpdateProgress(uid, "decompose", totalPieces)
    end
end

--- 两入口日志保留各自格式，且发生在所有同步交付完成之后。
---@param uid number
---@param operation string
---@param totalEssence number
---@param totalPieces number
---@param index number|nil
---@return table
local function publishDecomposition(uid, operation, totalEssence, totalPieces, index)
    print("[LootService] " .. operation .. " uid=" .. tostring(uid)
        .. (operation == "DecomposeOne" and (" index=" .. tostring(index)) or "")
        .. " pieces=" .. totalPieces
        .. " essence=+" .. totalEssence)

    return {
        decomposeCount = totalPieces,
        essenceReward  = totalEssence,
    }
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
        return false, "无效的遗匣索引"
    end

    if EquipmentSystem.isInventoryFull(equipData) then
        return false, "背包已满", { bagFull = true }
    end

    -- 领取前修正该条种子等级
    local cap = LootBoxSystem.levelCap
    if cap > 0 then
        local seed = lootboxData.seeds[index]
        if seed then capLegacySeed(seed, cap) end
    end

    local claimed, bagFull = LootBoxSystem.claimGroup(lootboxData, index, equipData)

    if #claimed == 0 then
        return false, "领取失败"
    end

    notifyClaim(uid)
    return true, nil, publishClaim(uid, "ClaimGroup", lootboxData, claimed, bagFull)
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
        return false, "遗匣为空"
    end

    if EquipmentSystem.isInventoryFull(equipData) then
        return false, "背包已满", { bagFull = true }
    end

    -- 领取前修正种子等级（确保客户端显示与实际生成一致）
    prepareAllSeeds(lootboxData)

    local claimed, bagFull = LootBoxSystem.claimAll(lootboxData, equipData)

    if #claimed > 0 then notifyClaim(uid) end
    return true, nil, publishClaim(uid, "ClaimAll", lootboxData, claimed, bagFull)
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
        return false, "遗匣为空"
    end

    local totalEssence, totalPieces = LootBoxSystem.decomposeAll(lootboxData)

    deliverDecomposition(uid, totalEssence, totalPieces)
    return true, nil, publishDecomposition(uid, "DecomposeAll", totalEssence, totalPieces)
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
        return false, "遗匣为空"
    end

    if not index or index < 1 or index > #lootboxData.seeds then
        return false, "无效的索引"
    end

    local totalEssence, totalPieces = LootBoxSystem.decomposeOne(lootboxData, index)

    deliverDecomposition(uid, totalEssence, totalPieces)
    return true, nil, publishDecomposition(uid, "DecomposeOne", totalEssence, totalPieces, index)
end

return LootService
