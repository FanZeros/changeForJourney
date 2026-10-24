-- ============================================================================
-- AdvancementService - 转职业务逻辑
-- 职责: 英雄转职校验与修改（纯业务，禁止网络 IO）
-- 层级: server/advancement  |  通过 PDM 读写数据
-- ============================================================================

local PDM         = require("rules.character.PlayerDataManager")
local AVC         = require("config.AdvancementConfig")
local HeroConfig  = require("config.HeroConfig")
local HeroService = require("rules.hero.HeroService")
local TaskService = require("rules.task.TaskService")

local AdvancementService = {}

-- 执行阶段只使用已校验的英雄/货币引用；消耗仍在校验返回后读取，
-- 不预先缓存配置，也不把同步通知包装成事务或延迟队列。
local function applyClassAdvance(hero, currency, branchId, advLevel)
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

end

-- 转职通知具有顺序：英雄 -> 货币 -> 成就。每步仍动态查找依赖方法，
-- 允许订阅者同步重入；异常时保留已经写入/已经发布的状态。
local function publishClassAdvance(uid)
    PDM.MarkDirty(uid, "heroes")
    PDM.MarkDirty(uid, "currency")

    -- 任务进度：刷新转职成就（adv1_count, adv2_count）
    TaskService.RefreshAchievements(uid)

end

-- 返还按已存在的分支分别向下取整，不按分支有效性重新校验，
-- 不合并两笔消耗后取整；两次 COST 读取仍发生在副手处理之前。
local function calculateResetRefund(advBranch)
    local refundGold = 0
    if advBranch then
        if advBranch.first then
            refundGold = refundGold + math.floor(AVC.COST[1].gold * 0.5)
        end
        if advBranch.second then
            refundGold = refundGold + math.floor(AVC.COST[2].gold * 0.5)
        end
    end

    return refundGold
end

-- 只卸下双持天赋放入副手的武器，不删除库存/替换装备表。
-- equipment 的同步发布与卸装日志必须先于清除转职、返金。
local function removeDualWieldOffhand(uid, heroId, advBranch)
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

    return removedOffhandSeq
end

-- 重置不刷新成就；即便返还为零仍发布 heroes，currency 则仅在
-- 正返还时发布。保留原引用及同步发布中途可观察到的部分状态。
local function applyAndPublishClassReset(uid, hero, currency, refundGold)
    hero.advBranch = nil
    if refundGold > 0 then
        currency.gold = (currency.gold or 0) + refundGold
    end

    PDM.MarkDirty(uid, "heroes")
    if refundGold > 0 then
        PDM.MarkDirty(uid, "currency")
    end

end

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

    applyClassAdvance(hero, currency, branchId, advLevel)
    publishClassAdvance(uid)

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

    local advBranch = hero.advBranch
    local refundGold = calculateResetRefund(advBranch)
    local removedOffhandSeq = removeDualWieldOffhand(uid, heroId, advBranch)
    applyAndPublishClassReset(uid, hero, currency, refundGold)

    print("[AdvancementService] ResetClass uid=" .. tostring(uid)
        .. " heroId=" .. tostring(heroId)
        .. " refundGold=" .. tostring(refundGold)
        .. " removedOffhand=" .. tostring(removedOffhandSeq))

    return true, nil, { heroId = heroId, refundGold = refundGold, removedOffhandSeq = removedOffhandSeq }
end

return AdvancementService
