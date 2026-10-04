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
        local IdleIncome = require("config.IdleIncomeConfig")
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
        local dirty = 0
        local uid = 991010
        replace(Dispatcher, "get", function(name) return modules[name] end)
        replace(Store, "Get", function(name) return modules[name] end)
        replace(PDM, "GetModule", function(_, name) return modules[name] end)
        replace(PDM, "MarkDirty", function() dirty = dirty + 1 end)
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
        replace(Dialog, "onSweep", function(count, teamIdx)
            request.calls = (request.calls or 0) + 1
            request.count, request.teamIdx = count, teamIdx
            request.ok, request.err, request.result = Service.Sweep(uid, count, teamIdx)
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
                equipment = { inventory = {} },
            }
            for heroId = 1, 6 do modules.heroes.roster[heroId] = { level = 100, exp = 0 } end
            modules.heroes.roster[25] = { level = 100, exp = 0 }
            request, dirty = {}, 0
            Page.setBattleReady(true)
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
            local goldPerMin, expPerMin = IdleIncome.get(1905)
            local targetCount = targetTeam -- 夹具队1/2/3分别1/2/3人，含空槽。
            local expTotal = math.floor(math.floor(expPerMin * Service.REWARD_MINUTES)
                * ExpTable.heroCountExpMult[targetCount])
            local perHero = math.floor(expTotal / targetCount + 0.5)
            eq(perHero > 0 and perHero < ExpTable.getHeroExpForLevel(100), true, "经验真实且不触发跨队共鸣")
            eq(request.result.heroExp, perHero, "每人经验遵守真实经济公式")
            eq(modules.currency.gold, 40 + math.floor(goldPerMin * Service.REWARD_MINUTES), "金币账户仅发一次")
            eq(modules.player.exp, 17, "扫荡不追加远征经验")
            local targetIds = {}
            for _, heroId in ipairs(modules.heroes.teams[targetTeam].slots) do
                if heroId > 0 then targetIds[heroId] = true end
            end
            for heroId, hero in pairs(modules.heroes.roster) do
                eq(hero.exp, targetIds[heroId] and perHero or 0, "目标/旁队/队外英雄经验hero" .. heroId)
                eq(hero.level, 100, "旁队等级保持hero" .. heroId)
            end
            eq(require("systems.EquipmentSystem").getInventoryCount(modules.equipment),
                Service.EQUIP_DROP_COUNT, "真实装备掉落仅一批")
        end
        local function verifyBlocked(label)
            confirm()
            eq(request.calls or 0, 0, label .. "不提交规则层")
            eq(modules.currency.sweepTicket, 5, label .. "不扣券")
            eq(modules.currency.gold, 40, label .. "不发账户金币")
            eq(dirty, 0, label .. "不脏写")
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
