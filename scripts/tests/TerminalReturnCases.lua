-- 按终焉前各队来源分流；只经真实入口/Driver/Scene/Nav/Boot闭包，复用主专项恢复栈。
local SC = require("config.StageConfig")
local DC = require("config.DungeonConfig")
local Raid = require("ui.battle.tri.TerminalRaid")
local M = {}

function M.run(hooks)
    local check, case, fixture = hooks.check, hooks.case, hooks.fixture
    local terminal = SC.TERMINAL_NORMAL
    local previous = SC.getTerminalPrevStageId(terminal)
    local target = SC.getReincarnationTarget(SC.getDifficulty(terminal))
    -- 第三个真实章节锚点不同于首层，能抓到错误地退回资源第一层/主线源关的实现。
    local choices = { previous } ---@type number[]
    for _, id in ipairs(DC.RESOURCE_IDS) do
        choices[#choices + 1] = assert(DC.getChapterStageIds(id)[3])
    end
    local function destinations(sources, won)
        local expected = {}
        for row = 1, 3 do
            expected[row] = SC.isResourceStage(sources[row]) and sources[row] or (won and target or previous)
        end
        return expected
    end
    local function snapshot(f, expected, label)
        local ids = f.page.getTeamStageIds()
        local captured = f.save.CaptureBattleProgress(f.battle)
        for row = 1, 3 do
            check(ids[row] == expected[row] and captured.teamStageIds[tostring(row)] == expected[row],
                label .. " 真实getTeamStageIds/Capture保留队" .. row)
        end
        check(captured.currentStageId == expected[1] and not SC.isResourceStage(captured.maxStageId),
            label .. " 队1允许资源、max只含主线")
        check(captured.terminalOrigins == nil and captured.returnStageIds == nil,
            label .. " 不把运行态返回计划写入存档")
    end
    local function arrivals(f, expected, label)
        local seen, total = {}, 0
        for row = 1, 3 do
            if not SC.isResourceStage(expected[row]) then total = total + 1 end
        end
        for _, arrival in ipairs(f.state.arrivals) do
            check(not seen[arrival.team] and not SC.isResourceStage(arrival.id)
                and arrival.id == expected[arrival.team], label .. " 通知仅实际主线且每队一次")
            seen[arrival.team] = true
        end
        check(#f.state.arrivals == total, label .. " 资源队不伪发新主线入场")
    end
    local function resumed(f, expected, label)
        for row = 1, 3 do
            local drv = f.drivers[row]
            check(drv.stageId == expected[row] and drv.pendingStageId == nil and drv.terminalRaid == nil,
                label .. " 队" .. row .. "实际落地且无旧raid/预约")
            if SC.isResourceStage(expected[row]) then
                check(drv.active and #drv.enemies + #drv.enemyQueue > 0,
                    label .. " 队" .. row .. "资源首波与候补真实重建")
                drv.introTimer = 0
                drv:update(0.01, 0.01)
                check(drv.active and drv.stageId == expected[row] and #drv.enemies + #drv.enemyQueue > 0,
                    label .. " 队" .. row .. "继续真实update资源战斗不被主线拉走")
            end
        end
        check(f.scene.getStageId() == expected[1], label .. " 兼容Scene加载队1实际目的地")
        snapshot(f, expected, label)
    end
    local function releaseStory(f)
        f.state.reward, f.state.pendingReward = false, false
        while f.story.hasPending("battle") do
            local item = assert(f.story.take("battle"))
            f.session.claimedScenarios[tostring(item.scenarioId)] = true
        end
    end
    local function win(f, sources, label)
        local expected = destinations(sources, true)
        f.finishRaid()
        check(f.battle.maxStageId == target and f.scene.getMaxStageId() == target,
            label .. " 胜利共享最高关只解锁新难度首关")
        snapshot(f, destinations(sources, false), label .. " 待轮回")
        for row = 1, 3 do check(f.drivers[row].stageId == terminal, label .. " 待奖励仍停终焉队" .. row) end
        releaseStory(f)
        f.page.update(2.1)
        check(f.state.starts == 1 and f.intro.isActive(), label .. " 真Boot只启动一次过场")
        local kills, exp = #f.state.kills, f.state.values.Exp
        f.intro.skip()
        resumed(f, expected, label .. " 胜利")
        arrivals(f, expected, label .. " 胜利")
        check(not f.page.isTerminalRaidActive() and f.battle.maxStageId == target,
            label .. " 资源大ID不污染主线max")
        local savedCount, arrived = #f.state.snapshots, #f.state.arrivals
        f.intro.skip()
        check(#f.state.snapshots == savedCount and #f.state.arrivals == arrived
            and #f.state.kills == kills and f.state.values.Exp == exp,
            label .. " 重复skip不保存/通知/发奖第二次")
    end
    local function lose(f, sources, label)
        local raid = assert(f.drivers[1].terminalRaid)
        raid:finish(false)
        f.page.update(20)
        for row = 1, 3 do check(f.drivers[row].stageId == terminal, label .. " 大dt首次观察失败不立即退场队" .. row) end
        check(not f.page.gotoTeamStage(1, terminal), label .. " 失败等待期间禁止重入")
        snapshot(f, destinations(sources, false), label .. " 失败等待")
        f.page.update(Raid.FAILURE_HOLD_SEC - 0.01)
        check(f.page.isTerminalRaidActive(), label .. " 未满一秒仍保留终焉")
        f.page.update(0.01)
        resumed(f, destinations(sources, false), label .. " 失败")
        arrivals(f, destinations(sources, false), label .. " 失败")
        check(#f.state.kills == 0 and f.state.values.Exp == nil and f.state.starts == 0,
            label .. " 失败不结算Boss/首通/过场")
        check(f.battle.maxStageId == previous and not f.battle.clearedStages[tostring(terminal)],
            label .. " 失败不提前解锁下一难度")
    end

    -- 原test保留纯主线完整case；此处64-1组合逐一实跑胜与败，不以资源分类排列代替真实ID。
    for a = 1, #choices do
        for b = 1, #choices do
            for c = 1, #choices do
                if a ~= 1 or b ~= 1 or c ~= 1 then
                    local sources = { choices[a], choices[b], choices[c] }
                    local label = table.concat(sources, "/")
                    case("来源胜利 " .. label, function()
                        win(fixture(terminal, { sources = sources, entry = "page" }), sources, label)
                    end)
                    case("来源失败 " .. label, function()
                        lose(fixture(terminal, { sources = sources, entry = "page" }), sources, label)
                    end)
                end
            end
        end
    end
    -- 兼容Nav的冷/热驱动与Scene真实确认路由。确认框打开后改资源预约，必须在真正进入时冻结。
    for _, entry in ipairs({ "nav", "coldNav", "confirm" }) do
        case("兼容入口来源 " .. entry, function()
            local sources = { choices[2], choices[3], previous }
            local options = { sources = sources, entry = entry }
            if entry == "confirm" then
                local changed = choices[4]
                options.beforeConfirm = function(page)
                    check(page.gotoTeamStage(2, changed), "确认框打开后来源可变更，open不是冻结时点")
                    sources[2] = changed
                end
            end
            local f = fixture(terminal, options)
            win(f, sources, entry)
        end)
    end
    case("Scene已终焉隐式接管使用saved资源", function()
        local sources = { choices[2], choices[3], choices[4] }
        local f = fixture(terminal, { sources = sources, sceneSource = terminal, entry = "implicit" })
        win(f, sources, "Scene终焉隐式接管")
    end)
    for _, inverse in ipairs({ false, true }) do
        for _, won in ipairs({ false, true }) do
            case("冷Nav忽略旧saved队1 inverse=" .. tostring(inverse) .. " won=" .. tostring(won), function()
                local saved = { inverse and choices[2] or previous, previous, choices[3] }
                local sceneSource = inverse and previous or choices[4]
                local expected = { sceneSource, previous, choices[3] }
                local f = fixture(terminal, { sources = saved, sceneSource = sceneSource, entry = "coldNav" })
                if won then win(f, expected, "冷Scene权威") else lose(f, expected, "冷Scene权威") end
            end)
        end
    end
    -- 每种资源×每队，真实已清波预约优先于旧stage；胜/败均回预约，不回旧资源锚点。
    for _, id in ipairs(DC.RESOURCE_IDS) do
        local ids = DC.getChapterStageIds(id)
        for row = 1, 3 do
            for _, won in ipairs({ false, true }) do
                case("资源预约 " .. id .. " 队" .. row .. " won=" .. tostring(won), function()
                    local sources, pending, expected = { previous, previous, previous }, {}, { previous, previous, previous }
                    sources[row], pending[row], expected[row] = ids[2], ids[3], ids[3]
                    local f = fixture(terminal, { sources = sources, pendingSources = pending, entry = "page" })
                    if won then win(f, expected, id .. row) else lose(f, expected, id .. row) end
                end)
            end
        end
    end
    case("返回数组只读隔离与失败再入不残留", function()
        local sources = { choices[2], previous, choices[3] }
        local f = fixture(terminal, { sources = sources, entry = "page" })
        local returned = f.page.getTerminalReturnStageIds(terminal, target)
        returned[1], returned[2], returned[3] = previous, choices[4], target
        local again = f.page.getTerminalReturnStageIds(terminal, target)
        check(again[1] == sources[1] and again[2] == target and again[3] == sources[3],
            "外写get返回数组不污染冻结来源")
        lose(f, sources, "第一次失败")
        local nextSources = { previous, choices[4], previous }
        for row = 1, 3 do check(f.page.gotoTeamStage(row, nextSources[row]), "失败后重新选择新来源队" .. row) end
        f.enter("page")
        win(f, nextSources, "失败后再入")
    end)
    case("资源待轮回读档取消旧动画token", function()
        local sources = { choices[2], choices[3], previous }
        local f = fixture(terminal, { sources = sources, entry = "page" })
        f.finishRaid()
        releaseStory(f)
        f.page.update(2.1)
        check(f.intro.isActive(), "读档前旧过场实际启动")
        local restored = { previous, choices[4], choices[2] }
        f.page.setTeamStageIds(restored)
        f.scene.adoptStageProgress(previous)
        local saved, arrived, kills = #f.state.snapshots, #f.state.arrivals, #f.state.kills
        f.intro.skip()
        check(f.scene.getStageId() == previous and not f.page.isTerminalRaidActive(), "旧token不能将读档后的来源推入目标")
        check(#f.state.snapshots == saved and #f.state.arrivals == arrived and #f.state.kills == kills,
            "旧token不保存、不通知、不重发Boss")
        for row = 1, 3 do check(f.page.getTeamStageIds()[row] == restored[row], "读档取消后保留新来源队" .. row) end
    end)
    case("未进入capture/reset不得残留资源", function()
        local sources = { choices[2], choices[3], choices[4] }
        local f = fixture(terminal, { sources = sources, entry = "page", deferTerminal = true })
        check(f.page.captureTerminalOrigins(terminal) == true, "进入前显式capture返回boolean不暴露来源表")
        f.page.resetToDefault()
        f.scene.adoptStageProgress(previous)
        f.page.setTeamStageIds({ previous, previous, previous })
        f.page.setBattleReady(true) -- 与真实宿主清档后完成重新准备的门禁一致。
        f.page.open()
        for row = 1, 3 do check(f.page.gotoTeamStage(row, previous), "reset后重新选纯主线队" .. row) end
        f.enter("page")
        win(f, { previous, previous, previous }, "capture后reset")
    end)
end

return M
