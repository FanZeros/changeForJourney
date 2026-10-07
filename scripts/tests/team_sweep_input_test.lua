-- T10：真实 Page 输入 -> SweepDialog 确认 -> SweepService 结算。
-- 无像素/设备事件/网络回执/磁盘存档验收；内存数据入口、Driver 启动和音频为最小替身。
local assertions = 0
local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

function Start()
    local restores, failures = {}, {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local Dispatcher = require("runtime.ClientDispatcher")
        local Store = require("core.PlayerStore")
        local GameState = require("core.GameState")
        local PDM = require("rules.character.PlayerDataManager")
        local ExpTable = require("config.ExpTable")
        local Spawn = require("ui.battle.stage.BattleEnemySpawn")
        local StageConfig = require("config.StageConfig")
        local DropSystem = require("systems.DropSystem")
        local Transaction = require("rules.dungeon.DungeonService")
        local Registry = require("shared.ModuleRegistry")
        local Schema = require("shared.schemas.CharacterSchema")
        local CharacterPanel = require("ui.character.panel.CharacterPanel")
        local Driver = require("ui.battle.tri.BattleTriDriver")
        local Scene = require("ui.battle.scene.BattleScene")
        local Dialog = require("ui.battle.stage.SweepDialog")
        local Page = require("ui.battle.tri.BattleTriPage")
        local Service = require("rules.sweep.SweepService")
        local EquipmentBag = require("ui.character.equip.EquipmentBag")
        local RewardPopup = require("ui.hud.popup.RewardPopup")
        local StatsDialog = require("ui.battle.popup.DamageStatsPanel")
        local StageDialog = require("ui.battle.stage.StageSelectDialog")
        local TerminalDialog = require("ui.battle.popup.TerminalConfirmDialog")
        local SFX = require("systems.GameSFX")

        -- 真实模块仍负责队伍门禁、输入映射、扣券、经验/升级/共鸣与装备掉落。
        -- 仅替换数据边界，避免测试读写玩家真实存档或要求启动完整战场。
        local modules = {}
        local activeTeam = 1
        local request = {}
        local dirty, persists, committed = 0, 0, false
        local persisted, wallet = {}, {}
        local function copy(value)
            if type(value) ~= "table" then return value end
            local result = {}
            for key, child in pairs(value) do result[key] = copy(child) end
            return result
        end
        local uid = 991010
        replace(Dispatcher, "get", function(name) return modules[name] end)
        replace(Store, "Get", function(name) return modules[name] end)
        replace(PDM, "GetModule", function(_, name) return modules[name] end)
        replace(PDM, "MarkDirty", function()
            eq(committed, true, "持久化成功之前不得推送候选模块")
            dirty = dirty + 1
        end)
        replace(GameState, "exportSave", function() return copy(wallet) end)
        replace(GameState, "syncFromCurrency", function(value) wallet = copy(value) end)
        -- 仅数据保存/双onLoad边界mock，不跑Boot，不读取任何玩家存档。
        -- 新规则必须真实执行CommitRewardTransaction，不能用FlushImmediate日志替代保存。
        for _, name in ipairs({ "currency", "heroes", "player", "equipment", "lootbox" }) do
            local registered = Registry.find(name)
            if registered then replace(registered, "onLoad", function() end) end
            local schema = Schema.Fields[name]
            if schema then replace(schema, "onLoad", function() end) end
        end
        Transaction.SetPersistCallback(function()
            eq(dirty, 0, "mock持久化边界前零通知")
            persists = persists + 1
            persisted, committed = copy(modules), true
            return true
        end, { begin = function() committed = false end, finish = function() end })
        restores[#restores + 1] = function() Transaction.SetPersistCallback(nil) end
        replace(GameState, "getSweepTicket", function() return modules.currency.sweepTicket end)
        replace(CharacterPanel, "getActiveTeamIdx", function() return activeTeam end)
        replace(SFX, "playUIClick", function() end)
        replace(Scene, "pumpBattleCards", function() end)
        replace(Scene, "getStageId", function() return 1905 end)
        replace(Scene, "isSpeedButtonVisible", function() return false end)
        replace(Driver, "new", function(teamIdx)
            return {
                teamIdx = teamIdx, allies = {}, enemies = {},
                start = function(self, stageId) self.stageId = stageId end,
            }
        end)
        replace(EquipmentBag, "shouldBattleOverlay", function() return false end)
        replace(RewardPopup, "currentRowTag", function() return nil end)
        replace(StatsDialog, "isOpen", function() return false end)
        replace(StageDialog, "isOpen", function() return false end)
        replace(TerminalDialog, "isOpen", function() return false end)
        -- 用确定逐杀掉落保证容量/实际批数断言有意义；装备生成与交付仍走真实实现。
        replace(DropSystem, "rollKillDrop", function() return 2 end)
        replace(DropSystem, "rollScrollDrop", function() return "weaponScroll" end)
        replace(DropSystem, "rollSweepTicket", function() error("扫荡不允许返券") end)
        replace(Dialog, "onSweep", function(count, teamIdx, stageId)
            request.calls = (request.calls or 0) + 1
            request.count, request.teamIdx, request.stageId = count, teamIdx, stageId
            request.ok, request.err, request.result = Service.Sweep(uid, count, teamIdx, stageId)
        end)

        local function reset(active, progress)
            Dialog.close()
            Page.close()
            activeTeam = active
            modules = {
                battle = progress or { maxStageId = 1905, currentStageId = 1905,
                    clearedStages = { [905] = true, ["1905"] = true } },
                heroes = {
                    roster = {}, deployed = { 1, 0, 0, 0 },
                    teams = { { slots = { 1, 0, 0, 0 } },
                        { slots = { 2, 0, 3, 0 } }, { slots = { 4, 5, 0, 6 } } },
                },
                currency = { gold = 40, sweepTicket = 5 },
                player = { level = 100, exp = 17 },
                equipment = { inventory = {}, equipped = {}, nextSeq = 1 },
                lootbox = { seeds = {} }, dungeon = {}, session = {},
            }
            for heroId = 1, 6 do modules.heroes.roster[heroId] = { level = 100, exp = 0 } end
            modules.heroes.roster[25] = { level = 100, exp = 0 }
            request, dirty, persists, committed = {}, 0, 0, false
            persisted, wallet = {}, copy(modules.currency)
            Page.open()
            eq(Page.isOpen(), true, "真实Page已打开")
        end

        -- Page 未绘制时采用真实默认 region=948×1080，getInteriorRect 同源取按钮位置。
        -- 窗口坐标 -> Page 对话框 fit -> Dialog 内部0.8缩放，禁止直接绕过输入执行确认。
        local function clickRow(row)
            local ix, iy, iw = Page.getInteriorRect(row)
            eq(Page.handleInput(ix + iw - 4 - 29 - 17, iy + 29 + 2), true, "战线入口消费")
            eq(Dialog.isOpen(), true, "战线入口打开真实Dialog")
        end
        local function dialogPoint(designX, designY)
            local outerX = 540 + (designX - 540) * 0.8
            local outerY = 1195 + (designY - 1195) * 0.8
            local fit = math.min(948 / 1080, 1080 / 2400) * 2
            return 948 * 0.5 + (outerX - 540) * fit,
                1080 * 0.5 + (outerY - 1195) * fit
        end
        local function clickDialog(designX, designY)
            local wx, wy = dialogPoint(designX, designY)
            eq(Page.handleInput(wx, wy), true, "Page弹窗输入消费")
        end
        local function confirm() clickDialog(540, 1700) end
        local function switchTeam(teamIdx) clickDialog(438 + (teamIdx - 1) * (170 + 24), 968) end
        local function verifyAward(targetTeam)
            eq(request.calls, 1, "确认只调用一次Service")
            eq(request.ok, true, "真实SweepService成功: " .. tostring(request.err))
            eq(request.count, 1, "默认一次扫荡")
            eq(request.teamIdx, targetTeam, "Dialog默认目标队")
            eq(request.result.teamIdx, targetTeam, "Service结算目标队")
            eq(modules.currency.sweepTicket, 4, "仅扣一张账户扫荡券")
            local entry = assert(StageConfig.getStage(request.stageId))
            local enemies = Spawn.generateEnemyList(entry, false)
            local gold, playerExp = 0, 0
            for _, enemy in ipairs(enemies) do
                gold, playerExp = gold + enemy.goldReward, playerExp + enemy.expReward
            end
            eq(request.stageId, 1905, "真实目标stageId从Dialog透传")
            eq(request.result.stageId, request.stageId, "Service结算原目标而不是当前前进关")
            local targetCount = targetTeam -- 夹具队1/2/3分别1/2/3人，含空槽。
            local expTotal = math.floor(playerExp * ExpTable.heroCountExpMult[targetCount])
            local perHero = math.floor(playerExp * ExpTable.heroCountExpMult[targetCount] / targetCount + 0.5)
            eq(perHero > 0 and perHero < ExpTable.getHeroExpForLevel(100), true, "经验真实且不触发跨队共鸣")
            eq(request.result.heroExp, perHero, "每人经验遵守真实单场怪物奖励公式")
            eq(request.result.heroExpTotal, expTotal, "报告英雄经验池遵守真实公式")
            eq(modules.currency.gold, 40 + gold, "金币账户仅发单场怪物奖励一次")
            eq(modules.player.exp, 17 + playerExp, "扫荡追加准确单场远征经验")
            eq(persists, 1, "确认只提交一次持久化")
            eq(persisted.currency.sweepTicket, 4, "扣券与奖励在同一保存快照")
            eq(persisted.player.exp, 17 + playerExp, "经验在通知前完整保存")
            local targetIds = {}
            for _, heroId in ipairs(modules.heroes.teams[targetTeam].slots) do
                if heroId > 0 then targetIds[heroId] = true end
            end
            for heroId, hero in pairs(modules.heroes.roster) do
                eq(hero.exp, targetIds[heroId] and perHero or 0, "目标/旁队/队外英雄经验hero" .. heroId)
                eq(hero.level, 100, "旁队等级保持hero" .. heroId)
            end
            eq(require("systems.EquipmentSystem").getInventoryCount(modules.equipment),
                #enemies, "确定逐杀每怪掉一件，单场仅一批")
            eq(request.result.equipCount, #enemies, "装备数来自真实逐杀次数")
            eq(modules.currency.weaponScroll, #enemies, "逐杀卷轴仅一批")
        end
        local function verifyBlocked(label)
            confirm()
            eq(request.calls or 0, 0, label .. "不提交规则层")
            eq(modules.currency.sweepTicket, 5, label .. "不扣券")
            eq(modules.currency.gold, 40, label .. "不发账户金币")
            eq(dirty, 0, label .. "不脏写")
            eq(persists, 0, label .. "不持久化")
            for heroId, hero in pairs(modules.heroes.roster) do eq(hero.exp, 0, label .. "不误发hero" .. heroId) end
        end
        local cases = 0
        local function case(label, callback)
            cases = cases + 1
            local passed, caseErr = pcall(callback)
            if passed then print("[team_sweep_input_test] PASS " .. label)
            else
                failures[#failures + 1] = label .. " => " .. tostring(caseErr)
                print("[team_sweep_input_test] FAIL " .. failures[#failures])
            end
            Dialog.close()
        end

        for active = 1, 3 do
            for row = 1, 3 do
                case("active" .. active .. "/row" .. row, function()
                    reset(active)
                    clickRow(row)
                    eq(request.calls or 0, 0, "入口不提前结算")
                    -- 弹窗打开后改变右栏队，也不能改变已选战线。
                    activeTeam = active % 3 + 1
                    confirm()
                    verifyAward(row)
                end)
            end
        end
        for active = 1, 3 do
            case("generic active" .. active, function()
                reset(active)
                Dialog.open()
                confirm()
                verifyAward(active)
            end)
            case("generic button active" .. active, function()
                reset(active)
                eq(Dialog.handleButtonInput(971, 2115), true, "泛按钮入口消费")
                confirm()
                verifyAward(active)
            end)
            case("explicit open team" .. active, function()
                reset(active % 3 + 1)
                Dialog.open(active)
                confirm()
                verifyAward(active)
            end)
        end
        for origin = 1, 3 do
            case("manual switch from row" .. origin, function()
                reset(1)
                clickRow(origin)
                local target = origin % 3 + 1
                switchTeam(target)
                confirm()
                verifyAward(target)
            end)
        end
        for team = 2, 3 do
            case("explicit locked team" .. team, function()
                reset(1, { maxStageId = 905, clearedStages = {} })
                Dialog.open(team)
                verifyBlocked("显式锁队" .. team)
            end)
        end
        for team = 1, 3 do
            case("explicit empty team" .. team, function()
                reset(team % 3 + 1)
                modules.heroes.teams[team].slots = { 0, 0, 0, 0 }
                if team == 1 then modules.heroes.deployed = { 0, 0, 0, 0 } end
                eq(Dialog.handleButtonInput(971, 2115, team), true, "显式空队入口消费")
                verifyBlocked("显式空队" .. team)
            end)
        end
        case("lock while dialog open", function()
            reset(1)
            Dialog.open(3)
            modules.battle = { maxStageId = 905, clearedStages = {} }
            verifyBlocked("打开后锁队")
        end)
        case("locked manual switch preserves selection", function()
            reset(1, { maxStageId = 905, clearedStages = { [905] = true } })
            Dialog.open(2)
            switchTeam(3)
            confirm()
            eq(request.calls, 1, "锁队手动选择不导致额外请求")
            eq(request.teamIdx, 2, "拒绝锁队后仍保持队2")
            eq(request.ok, true, "原合法队仍可确认")
            eq(modules.currency.sweepTicket, 4, "原合法队仅扣一券")
            eq(modules.heroes.roster[1].exp, 0, "拒绝锁队不改扫队1")
            eq(modules.heroes.roster[4].exp, 0, "锁队英雄无经验")
        end)
        case("exhausted ticket blocks second confirmation", function()
            reset(1)
            modules.currency.sweepTicket = 1
            clickRow(2)
            confirm()
            eq(request.calls, 1, "首次确认一次结算")
            eq(request.teamIdx, 2, "首次确认队2")
            eq(request.ok, true, "首次确认成功")
            eq(modules.currency.sweepTicket, 0, "唯一券只扣一次")
            confirm()
            eq(request.calls, 1, "券用尽后再次确认不提交")
            eq(modules.currency.sweepTicket, 0, "券用尽后不得再扣")
        end)
        Page.close()
        print("[team_sweep_input_test] SUMMARY cases=" .. cases .. " failures=" .. #failures
            .. " assertions=" .. assertions)
        assert(#failures == 0, table.concat(failures, "\n"))
    end)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then
        log:Write(LOG_ERROR, "[team_sweep_input_test] " .. tostring(err))
    else
        print("[team_sweep_input_test] ALL PASS: " .. assertions .. " assertions")
    end
    engine:Exit()
end
