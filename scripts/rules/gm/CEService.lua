-- ============================================================================
-- CEService - 单机测试用批量 GM
-- 走现有 PDM / GMService，方便横屏 CE 面板一键铺数据。
-- ============================================================================

local PDM = require("rules.character.PlayerDataManager")

local CEService = {}

local UID = 1

local RESOURCE_KEYS = {
    "gold", "gems", "essence",
    "recruitTicket", "stellarRecruitTicket", "goldenKey", "enhanceStone",
    "degradeStone", "destroyStone",
    "sweepTicket", "tavernCoin",
    "weaponScroll", "offhandScroll", "armorScroll", "accessoryScroll",
    "helmetScroll", "shoesScroll",
    "arcaneDust", "corruptStone", "sacredStone",
}

local function ensureReady()
    require("runtime.LocalActionBridge").init()
end

local function rosterEntry(roster, heroId)
    if not roster then return nil end
    return roster[heroId] or roster[tostring(heroId)]
end

local function toast(text)
    print("[CE] " .. text)
    local ok, UiToast = pcall(require, "core.UiToast")
    if ok and UiToast and UiToast.show then
        UiToast.show(text, 2.2)
    end
    return text
end

function CEService.giveAllResources()
    ensureReady()
    local GM = require("rules.gm.GMService")
    local given = 0
    for _, key in ipairs(RESOURCE_KEYS) do
        local ok = GM.GiveResource(UID, key, 1000000)
        if ok then given = given + 1 end
    end
    GM.GiveResource(UID, "speedCardExpireAt", 7 * 86400)
    return toast("全资源 +100万，加速卡 +7天（" .. given .. " 项）")
end

function CEService.unlockAllHeroes()
    ensureReady()
    local HeroConfig = require("config.HeroConfig")
    local ExpTable = require("config.ExpTable")
    local HeroService = require("rules.hero.HeroService")
    local heroes = PDM.GetModule(UID, "heroes")
    if not heroes then return toast("英雄数据未加载") end
    heroes.roster = heroes.roster or {}
    local added = 0
    for _, heroId in ipairs(HeroConfig.getAllIds()) do
        if not rosterEntry(heroes.roster, heroId) then
            local cfg = HeroConfig.get(heroId)
            local level = 1
            heroes.roster[heroId] = {
                level = level,
                exp = 0,
                maxExp = ExpTable.getHeroExpForLevel(level) or 0,
                classId = cfg and cfg.classId or 1,
                dupeCount = 0,
                shards = 0,
                awakening = { _awk3Migrated = true },
                extraTalent = require("systems.ExtraTalentSystem").normalize(nil),
                _shardMigrated = true,
                _awk3Migrated = true,
            }
            added = added + 1
        end
    end
    PDM.MarkDirty(UID, "heroes")
    HeroService.ApplyResonanceSync(UID)
    return toast("解锁英雄 +" .. added .. "，已拥有的未改等级")
end

function CEService.levelAllHeroes(steps)
    ensureReady()
    steps = math.floor(tonumber(steps) or 10)
    if steps < 1 then steps = 1 end
    local ExpTable = require("config.ExpTable")
    local HeroService = require("rules.hero.HeroService")
    local heroes = PDM.GetModule(UID, "heroes")
    if not heroes or not heroes.roster then return toast("英雄数据未加载") end
    local changed = 0
    for _, hero in pairs(heroes.roster) do
        if type(hero) == "table" and hero.level then
            local nextLv = math.min(ExpTable.HERO_MAX_LEVEL, (hero.level or 1) + steps)
            if nextLv ~= hero.level then
                hero.level = nextLv
                hero.exp = 0
                hero.maxExp = ExpTable.getHeroExpForLevel(nextLv) or 0
                changed = changed + 1
            end
        end
    end
    PDM.MarkDirty(UID, "heroes")
    HeroService.ApplyResonanceSync(UID)
    return toast("全员等级 +" .. steps .. "（" .. changed .. " 人）")
end

function CEService.awakenAllHeroes()
    ensureReady()
    local GM = require("rules.gm.GMService")
    local HeroConfig = require("config.HeroConfig")
    local raised = 0
    for _, heroId in ipairs(HeroConfig.getAllIds()) do
        local ok = GM.ActivateAwakening(UID, heroId)
        if ok then raised = raised + 1 end
    end
    return toast("全员觉醒 +1（成功 " .. raised .. "）")
end

function CEService.setPlayerLevel(target)
    ensureReady()
    target = math.floor(tonumber(target) or 30)
    local ExpTable = require("config.ExpTable")
    local player = PDM.GetModule(UID, "player")
    if not player then return toast("玩家数据未加载") end
    local oldLevel = player.level or 1
    if oldLevel >= target then
        return toast("远征等级已是 Lv." .. oldLevel .. "，未降低")
    end
    if target > ExpTable.PLAYER_MAX_LEVEL then target = ExpTable.PLAYER_MAX_LEVEL end
    player.level = target
    player.exp = 0
    player.maxExp = ExpTable.getPlayerExpForLevel(target) or 0
    PDM.MarkDirty(UID, "player")
    return toast("远征等级 Lv." .. oldLevel .. " → Lv." .. target)
end

local function jumpTo(stageId)
    local BattleService = require("rules.battle.BattleService")
    local ok, err = BattleService.DebugJumpToStage(UID, stageId)
    if not ok then
        return false, tostring(err)
    end
    local sceneOk, BattleScene = pcall(require, "ui.battle.BattleScene")
    if sceneOk and BattleScene and BattleScene.debugJumpToStage then
        BattleScene.debugJumpToStage(stageId)
    end
    return true, stageId
end

function CEService.jumpStages(count)
    ensureReady()
    count = math.floor(tonumber(count) or 10)
    local StageConfig = require("config.StageConfig")
    local BattleScene = require("ui.battle.BattleScene")
    local id = BattleScene.getCurrentStageId()
    local jumped = 0
    for _ = 1, count do
        local nextId = StageConfig.getNextStageId(id)
        if not nextId or StageConfig.isTerminalTemple(nextId) then break end
        id = nextId
        jumped = jumped + 1
    end
    if jumped == 0 then return toast("前面没有可跳的普通关") end
    local ok, err = jumpTo(id)
    if not ok then return toast("跳关失败: " .. tostring(err)) end
    return toast("主线跳了 " .. jumped .. " 关 → " .. tostring(id))
end

function CEService.jumpPreTerminal()
    ensureReady()
    local SC = require("config.StageConfig")
    local BattleScene = require("ui.battle.BattleScene")
    local stageId = BattleScene.getCurrentStageId()
    local curDiff = SC.getDifficulty(stageId)
    local preTerminalId = ({
        [SC.DIFFICULTY_NORMAL]        = SC.NORMAL_LAST_STAGE,
        [SC.DIFFICULTY_HARD]          = SC.HARD_LAST_STAGE,
        [SC.DIFFICULTY_NIGHTMARE]     = SC.NIGHTMARE_LAST_STAGE,
        [SC.DIFFICULTY_HELL]          = SC.HELL_LAST_STAGE,
        [SC.DIFFICULTY_PURGATORY]     = SC.PURGATORY_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT]       = SC.TORMENT_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT2]      = SC.TORMENT2_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT3]      = SC.TORMENT3_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT4]      = SC.TORMENT4_LAST_STAGE,
        [SC.DIFFICULTY_TORMENT5]      = SC.TORMENT5_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION]  = SC.ANNIHILATION_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION2] = SC.ANNIHILATION2_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION3] = SC.ANNIHILATION3_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION4] = SC.ANNIHILATION4_LAST_STAGE,
        [SC.DIFFICULTY_ANNIHILATION5] = SC.ANNIHILATION5_LAST_STAGE,
    })[curDiff] or SC.ANNIHILATION5_LAST_STAGE
    if stageId == preTerminalId then
        return toast("已在终焉前 " .. tostring(preTerminalId))
    end
    local ok, err = jumpTo(preTerminalId)
    if not ok then return toast("跳转失败: " .. tostring(err)) end
    return toast("已跳到终焉前 " .. tostring(preTerminalId))
end

function CEService.jumpToAtLeast(stageId)
    ensureReady()
    stageId = math.floor(tonumber(stageId) or 305)
    local BattleScene = require("ui.battle.BattleScene")
    local current = BattleScene.getCurrentStageId() or 0
    if current >= stageId then
        return toast("当前关卡 " .. tostring(current) .. " 已不低于 " .. tostring(stageId))
    end
    local ok, err = jumpTo(stageId)
    if not ok then return toast("跳转失败: " .. tostring(err)) end
    return toast("主线跳到 " .. tostring(stageId))
end

function CEService.instantClear()
    local BattleScene = require("ui.battle.BattleScene")
    local dungeonScene = require("ui.dungeon.DungeonBattleScene")
    local dungeonBattle = require("ui.dungeon.DungeonBattle")
    if dungeonScene.isOpen and dungeonScene.isOpen()
        and dungeonBattle.debugInstantWin and dungeonBattle.debugInstantWin() then
        return toast("已秒杀当前副本/塔小波")
    end
    if BattleScene.debugInstantClear then
        BattleScene.debugInstantClear()
        return toast("已清空当前主线敌人")
    end
    return toast("没有可秒杀的战斗")
end

function CEService.healAllies()
    local BattleScene = require("ui.battle.BattleScene")
    local AD = require("systems.AttributeDef")
    local allies = BattleScene.getAllies() or {}
    for _, ally in ipairs(allies) do
        if ally.attrs then
            ally.attrs:fillHp()
            ally.hp = ally.attrs:get(AD.MAX_HP)
            ally.maxHp = ally.hp
        elseif ally.maxHp then
            ally.hp = ally.maxHp
        end
    end
    return toast("己方满血")
end

function CEService.skipGuide()
    ensureReady()
    local session = PDM.GetModule(UID, "session")
    if not session then return toast("会话数据未加载") end
    session.claimedScenarios = session.claimedScenarios or {}
    local TutorialConfig = require("config.TutorialConfig")
    local marked = 0
    for _, group in pairs(TutorialConfig) do
        if type(group) == "table" and group.triggerScenarios then
            for _, sid in ipairs(group.triggerScenarios) do
                local key = tostring(sid)
                if session.claimedScenarios[key] ~= true then
                    session.claimedScenarios[key] = true
                    marked = marked + 1
                end
            end
        end
    end
    PDM.MarkDirty(UID, "session")
    local ok, TutorialManager = pcall(require, "systems.TutorialManager")
    if ok and TutorialManager and TutorialManager.skipCurrentGroup then
        TutorialManager.skipCurrentGroup()
    end
    return toast("引导情景已标记跳过 +" .. marked)
end

function CEService.boostDungeons(steps)
    ensureReady()
    steps = math.floor(tonumber(steps) or 5)
    local DungeonConfig = require("config.DungeonConfig")
    local TowerConfig = require("config.TowerConfig")
    local dungeon = PDM.GetModule(UID, "dungeon")
    if not dungeon then return toast("副本数据未加载") end
    local caps = {
        gold_mine = DungeonConfig.MAX_FLOOR.gold_mine,
        ancient_ruin = DungeonConfig.MAX_FLOOR.ancient_ruin,
        babel_tower = TowerConfig.MAX_FLOOR,
    }
    local parts = {}
    for key, cap in pairs(caps) do
        local sub = dungeon[key]
        if type(sub) == "table" then
            local floor = math.min(cap, (sub.floor or 1) + steps)
            sub.floor = floor
            parts[#parts + 1] = key .. "=" .. tostring(floor)
        end
    end
    PDM.MarkDirty(UID, "dungeon")
    return toast("副本/塔层 +" .. steps .. " " .. table.concat(parts, " "))
end

function CEService.fillLootbox()
    ensureReady()
    local lootbox = PDM.GetModule(UID, "lootbox")
    if not lootbox then return toast("遗匣数据未加载") end
    local LootBoxSystem = require("systems.LootBoxSystem")
    local EquipmentSystem = require("systems.EquipmentSystem")
    local added = 0
    for quality = 1, 6 do
        local equip = EquipmentSystem.generateRandom(20, quality)
        if equip then
            LootBoxSystem.addEquipment(lootbox, equip, "ce")
            added = added + 1
        end
    end
    PDM.MarkDirty(UID, "lootbox")
    return toast("遗匣塞入 " .. added .. " 件各品质装备")
end

function CEService.lightAllTalents()
    ensureReady()
    local talents = PDM.GetModule(UID, "talents")
    if not talents then return toast("天赋数据未加载") end
    local TalentNodeDefs = require("shared.talent.TalentNodeDefs")
    local TalentsSchema = require("shared.talents.TalentsSchema")
    local ids = {}
    for id in pairs(TalentNodeDefs.NODES) do
        ids[#ids + 1] = id
    end
    talents.litNodes = ids
    TalentsSchema.normalizeModule(talents)
    PDM.MarkDirty(UID, "talents")
    return toast("已点亮全部天赋，重开古树查看")
end

function CEService.giveRelicSet()
    ensureReady()
    local RelicService = require("rules.relic.RelicService")
    local given = 0
    for relicType = 1, 5 do
        local ok = RelicService.GmGiveRelic(UID, relicType, 4)
        if ok then given = given + 1 end
    end
    return toast("发放遗物 5 类品质4（成功 " .. given .. "）")
end

function CEService.testPack()
    CEService.giveAllResources()
    CEService.unlockAllHeroes()
    CEService.setPlayerLevel(30)
    CEService.jumpToAtLeast(305)
    return toast("测试包完成：资源、全英雄、远征30、主线至少3-5")
end

function CEService.resetSave()
    ensureReady()
    local GM = require("rules.gm.GMService")
    local ok, reason = GM.ResetSave(UID)
    if not ok then return toast("清档失败: " .. tostring(reason)) end
    local standalone = require("boot.Standalone")
    if standalone.requestResetToStartScreen then
        standalone.requestResetToStartScreen()
    end
    return toast("存档已重置")
end

return CEService
