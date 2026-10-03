-- 小队普通通关解锁专项回归：统一接口、UI/编队/扫荡门禁、神器/通天塔与离线锁队防护。
local assertions = 0
local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

function Start()
    local restores = {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local ExpTable = require("config.ExpTable")
        local TeamSlots = require("shared.heroes.TeamSlots")
        local ArtifactSchema = require("shared.artifact.ArtifactSchema")
        eq(ExpTable.getTeamUnlockStage(1), nil, "队1无关卡门槛")
        eq(ExpTable.getTeamUnlockStage(2), 905, "队2普通9-5")
        eq(ExpTable.getTeamUnlockStage(3), 1905, "队3普通19-5")
        eq(ExpTable.getTeamUnlockText(1), "", "队1无锁定文案")
        eq(ExpTable.getTeamUnlockText(2), "通关9-5解锁", "队2统一文案")
        eq(ExpTable.getTeamUnlockText(3), "通关19-5解锁", "队3统一文案")
        eq(ExpTable.getUnlockedTeamCount(nil), 1, "进度未加载仅队1")
        ---@type any
        local oldLevel = 200
        eq(ExpTable.getUnlockedTeamCount(oldLevel), 1, "旧等级参数不能解锁队伍")
        local cases = {
            { progress = {}, count = 1, label = "空进度" },
            { progress = { level = 200 }, count = 1, label = "高等级无通关" },
            { progress = { maxStageId = 904 }, count = 1, label = "9-5之前" },
            { progress = { maxStageId = 905 }, count = 1, label = "刚抵达9-5" },
            { progress = { maxStageId = "905", clearedStages = { [905] = true } }, count = 2, label = "9-5数字键通关未推进" },
            { progress = { maxStageId = 905, clearedStages = { ["905"] = true } }, count = 2, label = "9-5字符串键" },
            { progress = { maxStageId = 906 }, count = 2, label = "旧档越过9-5" },
            { progress = { maxStageId = "1905" }, count = 2, label = "刚抵达19-5" },
            { progress = { maxStageId = 1905, clearedStages = { [1905] = true } }, count = 3, label = "19-5数字键" },
            { progress = { maxStageId = 1905, clearedStages = { ["1905"] = true } }, count = 3, label = "19-5字符串键" },
            { progress = { maxStageId = "1906" }, count = 3, label = "旧档越过19-5" },
            { progress = { currentStageId = 1906 }, count = 1, label = "当前关不替代最高进度" },
            { progress = { clearedStages = { [905] = false, ["905"] = true } }, count = 2, label = "混合键兼容" },
        }
        for _, case in ipairs(cases) do
            eq(ExpTable.getUnlockedTeamCount(case.progress), case.count, case.label)
        end
        -- 只改队伍数量，号位与神器子格继续使用原来的等级接口。
        eq(ExpTable.getUnlockedSlotCountForTeam(1), 3, "Lv1三个号位不变")
        eq(ExpTable.getUnlockedSlotCountForTeam(2), 4, "Lv2第四号位不变")
        eq(ExpTable.getSlotUnlockLevel(4), 2, "第四号位门槛不变")
        eq(ArtifactSchema.getUnlockedSubSlotCount(29), 0, "神器子格29级仍锁定")
        eq(ArtifactSchema.getUnlockedSubSlotCount(30), 1, "神器首格30级不变")
        eq(ArtifactSchema.getUnlockedSubSlotCount(59), 1, "神器次格59级仍锁定")
        eq(ArtifactSchema.getUnlockedSubSlotCount(60), 2, "神器次格60级不变")

        local dispatcher = require("runtime.ClientDispatcher")
        local bridge = require("runtime.LocalActionBridge")
        local pdm = require("rules.character.PlayerDataManager")
        local HeroService = require("rules.hero.HeroService")
        local SweepService = require("rules.sweep.SweepService")
        local ArtifactService = require("rules.artifact.ArtifactService")
        local TowerService = require("rules.tower.TowerService")
        local OfflineService = require("rules.offline.OfflineService")
        local OfflineCalc = require("systems.OfflineCalc")
        local StageProvider = require("shared.StageProvider")
        local EquipmentSystem = require("systems.EquipmentSystem")
        local CharacterPanel = require("ui.character.panel.CharacterPanel")
        bridge.init()
        local modules = {}
        local dirty = 0
        replace(dispatcher, "get", function(name) return modules[name] end)
        replace(pdm, "GetModule", function(_, name) return modules[name] end)
        replace(pdm, "MarkDirty", function() dirty = dirty + 1 end)
        replace(pdm, "FlushImmediate", function() end)
        replace(HeroService, "ApplyResonanceSync", function() return 0, 1 end)
        local function reset(progress)
            modules = {
                battle = progress,
                player = { level = 200, exp = 0 },
                heroes = {
                    roster = {
                        [1] = { level = 100, exp = 0 }, [2] = { level = 100, exp = 0 },
                        [3] = { level = 100, exp = 0 }, [25] = { level = 100, exp = 0 },
                    },
                    deployed = { 1, 0, 0, 0 },
                    teams = { { slots = { 1, 0, 0, 0 } }, { slots = { 2, 0, 0, 0 } }, { slots = { 3, 0, 0, 0 } } },
                },
                currency = { gold = 40, gems = 40, sweepTicket = 3 },
                equipment = { inventory = {} },
                dungeon = { babel_tower = { floor = 1, cleared = {}, buffs = { 1 }, dailyUsed = 0 } },
                session = { lastOnlineTime = 1000, firstLoginTime = 100 },
                lootbox = {},
            }
            dirty = 0
        end
        reset({ maxStageId = 905, clearedStages = {} })
        eq(CharacterPanel.getUnlockedTeamCount(), 1, "角色UI读取battle而非等级")
        eq(CharacterPanel.setActiveTeam(2), false, "角色UI拒绝刚抵达9-5切队")
        local valid, reason = TeamSlots.validate(modules.heroes, 2, { 25 }, modules.battle)
        eq(valid, false, "纯校验拒绝锁队")
        eq(tostring(reason):find("通关9-5解锁", 1, true) ~= nil, true, "纯校验使用统一文案")
        eq(HeroService.SetTeam(1, 2, { 25 }), false, "规则层高等级仍拒锁队")
        eq(bridge.setTeams({ [1] = { 2, 0, 0, 0 }, [2] = { 1, 0, 0, 0 } }), false, "原子交换不能绕过锁队")
        eq(modules.heroes.deployed[1], 1, "失败交换保留队1")
        eq(modules.heroes.teams[2].slots[1], 2, "失败交换保留队2")
        eq(dirty, 0, "锁队编队失败无改档")
        eq(SweepService.Sweep(1, 1, 2), false, "扫荡规则拒绝锁队")
        eq(modules.currency.sweepTicket, 3, "锁队扫荡不扣券")
        eq(modules.currency.gold, 40, "锁队扫荡不发金币")
        eq(modules.heroes.roster[2].exp, 0, "锁队扫荡不发经验")
        eq(dirty, 0, "锁队扫荡失败无改档")
        eq(SweepService.Sweep(1, 1, 2.5), false, "小数队伍不偷偷改扫队1")
        eq(SweepService.Sweep(1, 1, 0), false, "无效队伍不偷偷改扫队1")
        eq(ArtifactService.Equip(1, "test", 1, 1, 2), false, "神器规则拒绝锁队")
        eq(TowerService.Challenge(1), false, "塔挑战拒绝未解锁三队")
        eq(TowerService.WaveWin(1, 1, 1), false, "塔波次不能绕过门禁")
        eq(TowerService.FloorWin(1, 1), false, "塔结算不能绕过门禁")
        eq(TowerService.PickBuff(1, 1), false, "塔强化不能绕过门禁")
        eq(modules.dungeon.babel_tower.floor, 1, "锁定塔不推进层数")
        eq(#modules.dungeon.babel_tower.buffs, 1, "锁定塔不清空强化")
        eq(dirty, 0, "锁定塔与神器失败无改档")

        modules.battle.clearedStages["905"] = true
        modules.player.level = 1
        eq(CharacterPanel.getUnlockedTeamCount(), 2, "低等级通关即可解锁队2")
        eq(CharacterPanel.setActiveTeam(2), true, "角色UI允许通关切队2")
        eq(CharacterPanel.setActiveTeam(1), true, "恢复角色UI队1")
        eq(HeroService.SetTeam(1, 2, { 25 }), true, "通关编队不再依赖等级")
        eq(TeamSlots.validate(modules.heroes, 3, {}, modules.battle), false, "队3仍需19-5")
        local artifactOk, artifactErr = ArtifactService.Equip(1, "test", 1, 1, 2)
        eq(artifactOk, false, "低等级通关不绕过神器子格门槛")
        eq(tostring(artifactErr):find("30", 1, true) ~= nil, true, "神器子格继续提示30级")

        reset({ maxStageId = 905, clearedStages = { [905] = true } })
        local swept, _, sweepResult = SweepService.Sweep(1, 1, 2)
        eq(swept, true, "9-5通关后队2可扫荡")
        eq(sweepResult.teamIdx, 2, "扫荡经验目标队2")
        eq(modules.currency.sweepTicket, 2, "成功扫荡只扣一券")
        eq(modules.heroes.roster[2].exp > 0, true, "队2获得扫荡经验")
        eq(modules.heroes.roster[1].exp, 0, "扫荡不误发队1经验")
        eq(modules.heroes.roster[3].exp, 0, "扫荡不误发锁队3经验")
        modules.battle = { maxStageId = 1905, clearedStages = { ["1905"] = true } }
        modules.player.level = 1
        eq(TowerService.Challenge(1), true, "低等级19-5通关后塔挑战开放")

        -- 离线输入含全部三队旧档、空槽与过大的旧快照；只允许已解锁真实队员。
        local calcHeroCount = 0
        replace(os, "time", function() return 2000 end)
        replace(StageProvider, "Get", function() return {} end)
        replace(OfflineCalc, "resolveIdleStageAnchors", function() return 101, 101 end)
        replace(OfflineCalc, "calcOfflineIdleRewards", function(seconds, _, heroCount)
            calcHeroCount = heroCount
            return { seconds = seconds, kills = 0, gold = 7, adventureExp = 0,
                adventurerExp = 60, equipSeeds = {}, scrollDrops = {} }
        end)
        replace(OfflineCalc, "calcOnlineIdleRewards", function(seconds, _, heroCount)
            calcHeroCount = heroCount
            return { seconds = seconds, kills = 0, gold = 0, adventureExp = 0,
                adventurerExp = 60, equipSeeds = {}, scrollDrops = {} }
        end)
        replace(EquipmentSystem, "generateRandom", function() return nil end)
        -- 面板来源也可能包含锁队，和存档来源使用同一过滤。
        local liveTeams = {}
        local liveReady = true
        replace(CharacterPanel, "getTeamSlotIds", function()
            return next(liveTeams) and liveTeams or modules.heroes.teams
        end)
        replace(CharacterPanel, "isHeroesDataApplied", function() return liveReady end)
        local offlineCases = {
            { progress = { maxStageId = 905, clearedStages = {}, idleHeroCount = 12 }, count = 1 },
            { progress = { maxStageId = 905, clearedStages = { [905] = true }, idleHeroCount = 12 }, count = 2 },
            { progress = { maxStageId = 1905, clearedStages = { ["1905"] = true }, idleHeroCount = 12 }, count = 3 },
        }
        for i, case in ipairs(offlineCases) do
            local uid = 9900 + i
            reset(case.progress)
            OfflineService.Cleanup(uid)
            local panel = OfflineService.CalcOnEnter(uid)
            assert(panel, "必须产生离线面板")
            eq(calcHeroCount, case.count, "离线人数快照锁队/空槽过滤" .. i)
            eq(#panel.heroExpPreview, case.count, "离线预览仅解锁队伍" .. i)
            eq(panel.heroExpPreview[1].expGain, 60 / case.count, "离线预览按有效队员平分" .. i)
            local rebuilt = OfflineService.RebuildHeroPreview(uid)
            eq(#rebuilt, case.count, "重建预览不恢复锁队" .. i)
            if case.count < 3 then
                rebuilt[#rebuilt + 1] = { heroId = 3, teamIdx = 3 }
                rebuilt[#rebuilt + 1] = { heroId = 25, teamIdx = 1 }
            end
            local claimed, _, result = OfflineService.ClaimRewards(uid)
            eq(claimed, true, "离线可领取" .. i)
            eq(result.heroExp, 60 / case.count, "领取重新过滤伪造锁队/未编队预览" .. i)
            for t = 1, 3 do
                eq(modules.heroes.roster[t].exp, t <= case.count and 60 / case.count or 0,
                    "离线发奖队伍" .. t .. "解锁数" .. case.count)
            end
            eq(modules.heroes.roster[25].exp, 0, "离线不发未编队英雄" .. i)
            eq(modules.currency.gold, 47, "离线金币只发一次" .. i)
            eq(OfflineService.ClaimRewards(uid), false, "离线不可重复领取" .. i)
            OfflineService.Cleanup(uid)
        end
        -- 使用与存档不同的实时队1，证明引擎实际使用了单例方法替身。
        reset({ maxStageId = 905, clearedStages = {}, idleHeroCount = 12 })
        liveTeams = { { slots = { 25, 0, 0, 0 } }, { slots = { 2 } }, { slots = { 3 } } }
        local livePanel = OfflineService.CalcOnEnter(9997)
        eq(livePanel.heroExpPreview[1].heroId, 25, "已就绪面板实时队1优先于存档队1")
        eq(#livePanel.heroExpPreview, 1, "实时面板锁队同样过滤")
        eq(calcHeroCount, 1, "实时面板人数倍率不计锁队")
        eq(OfflineService.ClaimRewards(9997), true, "实时面板队伍可领取")
        eq(modules.heroes.roster[25].exp, 60, "实时队1收到经验")
        eq(modules.heroes.roster[1].exp, 0, "存档旧队1不误领实时阵容经验")
        reset({ maxStageId = 905, clearedStages = {}, idleHeroCount = 12 })
        liveReady = false
        local storedPanel = OfflineService.CalcOnEnter(9998)
        eq(storedPanel.heroExpPreview[1].heroId, 1, "面板未就绪时仍使用存档队1")
        eq(#storedPanel.heroExpPreview, 1, "存档队伍来源锁队同样过滤")
        OfflineService.Cleanup(9998)
        liveTeams, liveReady = {}, true
        reset({ maxStageId = 905, clearedStages = {}, idleAccumSec = 60 })
        OfflineService.OnPlayerDisconnect(9999)
        eq(calcHeroCount, 1, "断线最终结算不计锁队")
        eq(modules.battle.idleHeroCount, 1, "断线快照排除锁队与空槽")
        eq(modules.heroes.roster[1].exp, 60, "断线结算只发队1")
        eq(modules.heroes.roster[2].exp, 0, "断线不发锁队2")
        eq(modules.heroes.roster[3].exp, 0, "断线不发锁队3")
        OfflineService.Cleanup(9999)
    end)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then
        log:Write(LOG_ERROR, "[team_stage_unlock_test] " .. tostring(err))
    else
        print("[team_stage_unlock_test] ALL PASS: " .. assertions .. " assertions")
    end
    engine:Exit()
end
