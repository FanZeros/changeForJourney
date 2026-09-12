-- ============================================================================
-- AdvancementService - 转职业务逻辑
-- 职责: 英雄转职校验与修改（纯业务，禁止网络 IO）
-- 层级: server/advancement  |  通过 PDM 读写数据
-- ============================================================================

local PDM         = require("server.character.PlayerDataManager")
local AVC         = require("config.AdvancementConfig")
local HeroConfig  = require("config.HeroConfig")
local HeroService = require("server.hero.HeroService")
local TaskService = require("server.task.TaskService")

local AdvancementService = {}

--- 英雄转职（一转/二转）
---@param uid number
---@param heroId number
---@param branchId number
---@param advLevel number 1 或 2
---@return boolean ok
---@return string|nil errReason
---@return table|nil result { heroId, branchId, advLevel, branchName }
function AdvancementService.AdvanceClass(uid, heroId, branchId, advLevel)
    local heroes   = PDM.GetModule(uid, "heroes")
    local currency = PDM.GetModule(uid, "currency")
    if not heroes or not currency then
        return false, "数据未加载"
    end

    if not heroId or not branchId or not advLevel then
        return false, "参数缺失"
    end

    local hero = heroes.roster[heroId]
    if not hero then
        return false, "未拥有该英雄"
    end

    local heroCfg = HeroConfig.get(heroId)
    if not heroCfg then
        return false, "英雄配置不存在"
    end

    -- 转职门槛与战斗/角色页一致：使用 hero.level
    local heroLevel = HeroService.GetHeroEffectiveLevel(uid, heroId)
    local gold = currency.gold or 0
    local advBranch = hero.advBranch

    local canDo, reason = AVC.canAdvance(heroLevel, gold, advLevel, heroCfg.classId, branchId, advBranch)
    if not canDo then
        return false, reason
    end

    -- === 原子修改 ===
    local cost = AVC.COST[advLevel]
    currency.gold = currency.gold - cost.gold

    if not hero.advBranch then
        hero.advBranch = {}
    end

    if advLevel == 1 then
        hero.advBranch.first = branchId
    elseif advLevel == 2 then
        hero.advBranch.second = branchId
    end

    -- === 持久化（MarkDirty 是同步内存操作，不会抛异常） ===
    PDM.MarkDirty(uid, "heroes")
    PDM.MarkDirty(uid, "currency")

    -- 任务进度：刷新转职成就（adv1_count, adv2_count）
    TaskService.RefreshAchievements(uid)

    local branchCfg = AVC.get(branchId)
    local branchName = branchCfg and branchCfg.name or "未知"

    print("[AdvancementService] AdvanceClass uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " branch=" .. tostring(branchId)
        .. " name=" .. branchName
        .. " advLevel=" .. tostring(advLevel))

    return true, nil, {
        heroId    = heroId,
        branchId  = branchId,
        advLevel  = advLevel,
        branchName = branchName,
    }
end

--- 重置英雄转职（清除 advBranch，返还50%金币消耗）
---@param uid number
---@param heroId number
---@return boolean ok
---@return string|nil errReason
---@return table|nil result { heroId, refundGold }
function AdvancementService.ResetClass(uid, heroId)
    local heroes   = PDM.GetModule(uid, "heroes")
    local currency = PDM.GetModule(uid, "currency")
    if not heroes or not currency then
        return false, "数据未加载"
    end

    if not heroId then
        return false, "参数缺失"
    end

    local hero = heroes.roster[heroId]
    if not hero then
        return false, "未拥有该英雄"
    end

    -- 计算返还金币：已消耗的50%
    local refundGold = 0
    local advBranch = hero.advBranch
    if advBranch then
        if advBranch.first then
            refundGold = refundGold + math.floor(AVC.COST[1].gold * 0.5)
        end
        if advBranch.second then
            refundGold = refundGold + math.floor(AVC.COST[2].gold * 0.5)
        end
    end

    -- === 副手武器卸下（双持职业重置时） ===
    local removedOffhandSeq = nil
    local dualMode = AVC.getDualWieldMode(advBranch)
    if dualMode then
        local equipData = PDM.GetModule(uid, "equipment")
        if equipData and equipData.equipped and equipData.equipped[heroId] then
            local offhandSeq = equipData.equipped[heroId]["offhand"]
            if offhandSeq then
                local seqStr = tostring(offhandSeq)
                local item = equipData.inventory and equipData.inventory[seqStr]
                if item and item.slot == "weapon" then
                    -- 副手槽位装的是武器（通过双持天赋装入），必须卸下
                    equipData.equipped[heroId]["offhand"] = nil
                    removedOffhandSeq = offhandSeq
                    PDM.MarkDirty(uid, "equipment")
                    print("[AdvancementService] ResetClass UNEQUIP offhand weapon uid=" .. tostring(uid)
                        .. " heroId=" .. tostring(heroId) .. " seq=" .. tostring(offhandSeq))
                end
            end
        end
    end

    -- === 原子修改 ===
    hero.advBranch = nil
    if refundGold > 0 then
        currency.gold = (currency.gold or 0) + refundGold
    end

    PDM.MarkDirty(uid, "heroes")
    if refundGold > 0 then
        PDM.MarkDirty(uid, "currency")
    end

    print("[AdvancementService] ResetClass uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " refundGold=" .. tostring(refundGold)
        .. " removedOffhand=" .. tostring(removedOffhandSeq))

    return true, nil, { heroId = heroId, refundGold = refundGold, removedOffhandSeq = removedOffhandSeq }
end

return AdvancementService
