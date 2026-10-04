-- 三队挂载隔离：真实 Page 绘制及 Scene 切关，像素出口使用替身。
local checks, failures = 0, 0
local function check(value, label)
    checks = checks + 1
    if not value then failures = failures + 1 end
    print("[team_state_isolation] " .. (value and "PASS " or "FAIL ") .. label)
end

function Start()
    local nativeRequire = require
    local restores = {}
    local function replace(owner, key, value)
        local old = owner[key]
        restores[#restores + 1] = function() owner[key] = old end
        owner[key] = value
    end
    local ok, err = pcall(function()
        local Scene = nativeRequire("ui.battle.scene.BattleScene")
        local Driver = nativeRequire("ui.battle.tri.BattleTriDriver")
        local SC = nativeRequire("config.StageConfig")
        local Dispatcher = nativeRequire("runtime.ClientDispatcher")
        local BC = nativeRequire("ui.battle.combat.BattleCombat")
        local PS = nativeRequire("ui.battle.combat.ProjectileSystem")
        local BE = nativeRequire("ui.battle.combat.BattleEffects")
        local TM = nativeRequire("systems.ThreatManager")
        local TAL = nativeRequire("systems.TalentManager")
        local SEM = nativeRequire("systems.StatusEffectManager")
        local Stats = nativeRequire("systems.BattleStats")
        local conditions = nativeRequire("systems.RelicConditionHandler")
        local states = { BC, PS, BE, TM, TAL, SEM, conditions }
        local defaults = {}
        for i, module in ipairs(states) do
            module.mount(nil)
            defaults[i] = module.mountedState()
        end
        Stats.mount(0)
        local battle = { currentStageId = 101, maxStageId = 2001,
            clearedStages = { ["905"] = true, ["1905"] = true }, battleMode = "idle" }
        replace(Dispatcher, "get", function(key) if key == "battle" then return battle end end)
        Scene.setBattleData(battle)
        local function noop() end
        local function stub(fields)
            return setmetatable(fields or {}, { __index = function() return noop end })
        end
        local drivers, drawOrder = {}, {}
        local failDraw = false
        local mocks = {
            ["ui.battle.scene.BattleScene"] = Scene,
            ["ui.battle.tri.BattleTriDriver"] = Driver,
            ["config.StageConfig"] = SC,
            ["config.ExpTable"] = nativeRequire("config.ExpTable"),
            ["ui.battle.stage.BattleSpeed"] = nativeRequire("ui.battle.stage.BattleSpeed"),
            ["core.BattleLayout"] = nativeRequire("core.BattleLayout"),
            ["runtime.ClientDispatcher"] = Dispatcher,
            ["ui.battle.combat.BattleCombat"] = BC,
            ["ui.battle.combat.ProjectileSystem"] = PS,
            ["ui.battle.combat.BattleEffects"] = BE,
            ["systems.ThreatManager"] = TM,
            ["systems.TalentManager"] = TAL,
            ["systems.StatusEffectManager"] = SEM,
            ["systems.BattleStats"] = Stats,
            ["systems.RelicConditionHandler"] = nativeRequire("systems.RelicConditionHandler"),
            ["shared.StageProvider"] = { Get = function() return SC end },
            ["core.I18n"] = nativeRequire("core.I18n"),
            ["config.GameConfig"] = nativeRequire("config.GameConfig"),
            ["shared.StageUtils"] = nativeRequire("shared.StageUtils"),
            ["ui.character.panel.CharacterPanel"] = stub({ getDeployedTeam = function() return {} end,
                getTeamSignature = function(team) return "队" .. team end }),
            ["ui.battle.scene.BattleView"] = stub({ draw = function()
                local team = Stats.mountedTeam()
                drawOrder[#drawOrder + 1] = team
                check(team and BC.mountedState() == drivers[team].combatState,
                    "绘制使用当前行自己的战斗状态")
                if failDraw then error("测试绘制异常") end
            end }),
        }
        replace(_G, "require", function(name)
            if mocks[name] then return mocks[name] end
            if name == "ui.battle.scene.BattleMountScope" then return nativeRequire(name) end
            mocks[name] = stub()
            return mocks[name]
        end)
        for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScissor", "nvgIntersectScissor",
            "nvgTranslate", "nvgScale", "nvgFontFace", "nvgFontSize", "nvgTextAlign",
            "nvgFillColor", "nvgText", "nvgTextBox", "nvgBeginPath", "nvgRoundedRect", "nvgFill" }) do
            replace(_G, name, noop)
        end
        replace(_G, "nvgCreateImage", function() return 1 end)
        replace(_G, "nvgRGBA", function() return {} end)
        replace(_G, "nvgTextBounds", function() return 10 end)
        replace(Scene, "pumpBattleCards", noop)
        local makeDriver = Driver.new
        replace(Driver, "new", function(team)
            local drv = makeDriver(team)
            drv.start = function(self, id)
                self.stageId, self.active = id, true
                self.pendingStageId = nil
                self.allies, self.enemies = { { heroId = team, hp = 100 } }, {}
                self.stageTotal = 0
                self.teamSignature = "队" .. team
                self.marchTimer = 0
                if self.onStageChanged then self.onStageChanged(team, id) end
            end
            drivers[team] = drv
            return drv
        end)
        local file = assert(cache:GetFile("ui/battle/tri/BattleTriPage.lua"))
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local Page = assert(load(table.concat(lines, "\n"), "@BattleTriPage", "t", _G))()
        mocks["ui.battle.tri.BattleTriPage"] = Page
        check(Page.getTeamStageIds() == nil, "页面未初始化不返回101覆盖旧档")
        local savedBeforeBoot = battle.currentStageId
        Page.setBattleReady(false)
        Page.open()
        Page.update(1)
        check(not Page.isOpen() and not next(drivers) and battle.currentStageId == savedBeforeBoot,
            "firstStage前提前open不创建驱动或覆盖已恢复关卡")
        Page.setBattleReady(true)
        Scene.adoptStageProgress(1001)
        Page.setTeamStageIds({ 1001, 1501, 1901 })
        Page.open()
        check(drivers[1] and drivers[2] and drivers[3], "三队驱动全部创建")
        check(table.concat(Page.getTeamStageIds(), ",") == "1001,1501,1901", "真实Page按三队独立关卡创建驱动")
        check(battle.currentStageId == 1001 and battle.teamCurrentStageIds[2] == 1501,
            "开机不把队二三存档冲成101")
        local function seed(drv)
            drv.combatState.comboQueue = { { marker = "连击", timer = 0.7 } }
            drv.combatState.floatingTexts = { { marker = "浮字" } }
            drv.psState.projectiles = { { marker = "投射物", onHit = noop } }
            drv.tmState.marker = "仇恨"
            drv.semState.marker = "冻结"
            drv.beState.marker = "特效"
        end
        for _, drv in ipairs(drivers) do seed(drv) end
        Page.draw({}, 948, 1080)
        check(#drawOrder == 3 and drawOrder[1] == 1 and drawOrder[3] == 3, "真实三行绘制顺序完整")
        for i, module in ipairs(states) do
            check(module.mountedState() == defaults[i], "绘制完成恢复默认状态模块" .. i)
        end
        check(Stats.mountedTeam() == nil, "绘制完成恢复默认统计桶")
        -- 复现关键输入窗口：最后一行激活后，旧 Scene 的切关不能清旁队。
        for team = 2, 3 do
            local drv = drivers[team]
            seed(drv)
            drv:activate()
            local combo, floating = drv.combatState.comboQueue, drv.combatState.floatingTexts
            local ps, sem, tm = drv.psState.projectiles, drv.semState.effects, drv.tmState.threatTable
            check(Scene.gotoStage(101 + team), "队一旧入口可切合法关")
            check(drv.combatState.comboQueue == combo and combo[1].timer == 0.7,
                "队一切关保留队" .. team .. "连击队列")
            check(drv.combatState.floatingTexts == floating, "队一切关保留队" .. team .. "浮字")
            check(drv.psState.projectiles == ps and ps[1].onHit == noop
                and drv.semState.effects == sem and drv.tmState.threatTable == tm,
                "队一切关保留队" .. team .. "投射物回调、冻结与仇恨")
            check(BC.mountedState() == defaults[1] and Stats.mountedTeam() == nil,
                "Scene切关明确挂载默认战场")
        end
        -- 每个点击队号只写自己的选择，旁队队列和统计桶保持不变。
        for target = 1, 3 do
            for other = 1, 3 do seed(drivers[other]) end
            local oldQueues = { drivers[1].combatState.comboQueue, drivers[2].combatState.comboQueue,
                drivers[3].combatState.comboQueue }
            local selectedId = 201 + target
            check(Page.gotoTeamStage(target, selectedId), "队" .. target .. "统一选关入口成功")
            check(battle.teamCurrentStageIds[target] == selectedId and drivers[target].stageId == selectedId,
                "队" .. target .. "即时写入独立当前关")
            for other = 1, 3 do
                if target ~= other then
                    check(drivers[other].combatState.comboQueue == oldQueues[other], "选队" .. target .. "不清队" .. other)
                end
            end
        end
        check(battle.currentStageId == 202 and battle.teamCurrentStageIds[1] == 202,
            "二三队选择不覆盖队一兼容字段")
        check(not Page.gotoTeamStage(2, 9901) and not Page.gotoTeamStage(4, 101)
            and not Page.gotoTeamStage(2.5, 101), "拒绝越权关卡与非法队号")
        local flushStages = nil ---@type number[]|nil
        mocks["boot.StandaloneSave"] = { Flush = function() flushStages = Page.getTeamStageIds() end }
        for team = 1, 3 do
            check(Page.gotoTeamStage(team, 301 + team), "准备队" .. team .. "首通落盘窗口")
            local oldStage = drivers[team].stageId
            drivers[team].onStageCleared(team, oldStage)
            check(drivers[team].stageId == oldStage and flushStages[team] == oldStage + 1,
                "队" .. team .. "首通落盘保存预约下一关且行军仍在旧关")
            check(Page.gotoTeamStage(team, 401 + team), "手选覆盖队" .. team .. "旧行军预约")
            check(Page.getTeamStageIds()[team] == 401 + team, "手选后不残留首通预约")
            drivers[team]:retreatStage()
            check(flushStages[team] == 400 + team and drivers[team].stageId == 400 + team,
                "队" .. team .. "退关落盘使用新关")
        end
        -- 异常仍必须恢复挂载，不能吞掉原绘制错误。
        failDraw = true
        for _, module in ipairs(states) do module.mount(nil) end
        Stats.mount(0)
        local drawOk, drawErr = pcall(Page.draw, {}, 948, 1080)
        check(not drawOk and tostring(drawErr):find("测试绘制异常", 1, true), "原绘制错误继续报告")
        for i, module in ipairs(states) do
            check(module.mountedState() == defaults[i], "异常后恢复默认状态模块" .. i)
        end
        check(Stats.mountedTeam() == nil, "异常后恢复统计桶")
        Page.close()
        failDraw = false
        check(Scene.gotoStage(1001), "关闭三行页后旧Scene可重新选关")
        check(Page.getTeamStageIds()[1] == 1001, "关闭三行页后不以旧驱动覆盖队一新选择")
        check(Page.getTeamStageIds()[2] == drivers[2].stageId, "关闭时仍保留二三队的独立进度")
    end)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then failures = failures + 1; log:Write(LOG_ERROR, tostring(err)) end
    print(string.format("[team_state_isolation] %s checks=%d failures=%d", failures == 0 and "ALL PASS" or "FAILED", checks, failures))
    if failures > 0 then log:Write(LOG_ERROR, "[team_state_isolation] 回归失败") end
    engine:Exit()
end
