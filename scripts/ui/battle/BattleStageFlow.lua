-- ============================================================================
-- BattleStageFlow - 关卡流程辅助：补位、天赋启动、卡牌分帧加载
-- 从 BattleScene 抽出；卡牌句柄表由调用方持有
-- ============================================================================

local TM  = require("systems.ThreatManager")
local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local RCH = require("systems.RelicConditionHandler")
local ART = require("systems.ArtifactRuntime")
local HeroAssetUtil = require("config.HeroAssetUtil")
local ProjectileSystem = require("ui.battle.ProjectileSystem")

local M = {}

---@param enemies table[]
---@param enemyQueue table[]
---@param maxField number
---@return table[] aliveEnemies, table[] remainingQueue
function M.refillEnemies(enemies, enemyQueue, maxField)
    local alive = {}
    for _, u in ipairs(enemies) do
        if u.hp > 0 then
            alive[#alive + 1] = u
        else
            TM.removeUnit(u)
            SEM.removeUnit(u)
        end
    end

    local slotsAvail = maxField - #alive
    local toAdd = math.min(slotsAvail, #enemyQueue)

    for _ = 1, toAdd do
        local unit = table.remove(enemyQueue, 1)
        alive[#alive + 1] = unit
    end

    return alive, enemyQueue
end

---@param allies table[]
---@param enemies table[]
function M.startBattleTalents(allies, enemies)
    RCH.reset()
    RCH.initBattle(allies)
    ART.reset()
    ART.initBattle(allies)
    TAL.reset()
    for _, u in ipairs(allies) do
        TAL.initUnit(u)
    end
    for _, u in ipairs(enemies) do
        TAL.initUnit(u)
    end
    TM.onBattleStart(allies, enemies)
    TAL.onBattleStart(allies, enemies)
end

---@class BattleCardLoadCtx
---@field imgHeroCards table
---@field imgMonsterCards table
---@field vg userdata|nil

--- 构建分帧加载队列（只构建一次）
---@param ctx BattleCardLoadCtx
---@param queue table[]|nil
---@return table[] queue
function M.ensureBattleCards(ctx, queue)
    if queue then return queue end
    local q = {}
    local imgHeroCards = ctx.imgHeroCards
    local imgMonsterCards = ctx.imgMonsterCards
    for _, id in ipairs(HeroAssetUtil.getAssetIds()) do
        if imgHeroCards[id] == nil then imgHeroCards[id] = -1 end
    end
    for _, id in ipairs({1001, 1002, 1003, 1004, 1005, 1006, 1007, 201, 202, 203, 204, 205, 206}) do
        if imgMonsterCards[id] == nil then imgMonsterCards[id] = -1 end
    end
    for id = 1, 54 do
        if imgMonsterCards[id] == nil then imgMonsterCards[id] = -1 end
    end
    for _, id in ipairs(HeroAssetUtil.getAssetIds()) do
        q[#q + 1] = {
            path = HeroAssetUtil.getCardPath(id),
            apply = function(h)
                if h and h >= 0 then imgHeroCards[id] = h end
            end,
        }
    end
    local monsterIds = {}
    for id = 1, 54 do monsterIds[#monsterIds + 1] = id end
    for _, id in ipairs({1001, 1002, 1003, 1004, 1005, 1006, 1007}) do
        monsterIds[#monsterIds + 1] = id
    end
    for id = 201, 206 do monsterIds[#monsterIds + 1] = id end
    for _, id in ipairs(monsterIds) do
        q[#q + 1] = {
            path = string.format("image/怪物卡牌/KP_GW_%d.png", id),
            apply = function(h) imgMonsterCards[id] = h end,
        }
    end
    for _, key in ipairs(ProjectileSystem.getImageKeys()) do
        q[#q + 1] = {
            path = "image/特效投射物/" .. key .. ".png",
            fn = function() ProjectileSystem.prewarmOne(key) end,
        }
    end
    print("[BattleStageFlow] 战斗卡牌分帧加载启动: " .. #q .. " 项")
    return q
end

--- 每帧消化加载队列
---@param queue table[]|nil
---@param vg userdata|nil
---@return table[]|nil remaining
function M.pumpBattleCards(queue, vg)
    if not queue then return nil end
    local cache = GetCache()
    local t0 = time.elapsedTime
    local i = 1
    while i <= #queue and time.elapsedTime - t0 < 0.008 do
        local job = queue[i]
        local st = cache:GetDownloadState(job.path)
        if st == DOWNLOAD_COMPLETED or st == DOWNLOAD_FAILED or job.downloadSkip then
            if st == DOWNLOAD_FAILED and not job.downloadSkip then
                job.downloadSkip = true
                i = i + 1
            else
                table.remove(queue, i)
                if job.fn then
                    job.fn()
                else
                    local h = nvgCreateImage(vg, job.path, 0)
                    if job.apply then job.apply(h) end
                end
            end
        else
            i = i + 1
        end
    end
    if #queue == 0 then
        print("[BattleStageFlow] 战斗卡牌分帧加载完成")
        return nil
    end
    return queue
end

return M
