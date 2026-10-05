-- 普通副本选队回归：真实页面、编队、英雄属性、神器桥和 GameAction 门面。
-- 仅以 require 替身隔离存档、动作传输和场景出口；不初始化存档，不运行随机战斗。
local assertions = 0
local TAG = "[dungeon_team_selection_test]"

local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " / " .. tostring(expected))
end

local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end

function Start()
    local nativeRequire, nativeTime = require, time
    local restores = {}
    local function replace(owner, key, value)
        local previous = owner[key]
        restores[#restores + 1] = function() owner[key] = previous end
        owner[key] = value
    end
    local function upvalue(fn, wanted)
        for index = 1, 100 do
            local name, value = debug.getupvalue(fn, index)
            if not name then break end
            if name == wanted then return value, index end
        end
        for index = 1, 100 do
            local name, value = debug.getupvalue(fn, index)
            if not name then break end
            if type(value) == "function" and name == "clearPendingChallenge" then
                return upvalue(value, wanted)
            end
        end
        error("缺少真实函数状态: " .. wanted)
    end
    local ok, err = pcall(function()
        local packageSnapshot = {}
        for name, value in pairs(package.loaded) do packageSnapshot[name] = value end
        local function noop() end
        -- 与现有专项测试一致，读取正式 Lua 源码并在隔离环境编译。
        -- 读取的只有脚本资源；禁止加载 StandaloneSave/PDM 等存档模块。
        local env = setmetatable({}, { __index = _G })
        local function compile(name)
            local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少脚本 " .. name)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            return assert(load(table.concat(lines, "\n"), "@" .. name, "t", env))()
        end
        local modules = {
            player = { level = 100 },
            battle = { currentStageId = 101, maxStageId = 2501, clearedStages = {} },
            dungeon = {
                gold_mine = { floor = 7, dailyUsed = 0 },
                equipment_vault = { floor = 11, dailyUsed = 0 },
                black_diamond = { floor = 5, dailyUsed = 0 },
                ancient_ruin = { floor = 79, idleAccumSec = 99 }, -- 隐藏旧档不能挪用
            },
            artifacts = { bag = {}, equipped = {}, equippedByTeam = {} },
        }
        local toasts, sends, opens = {}, {}, {}
        local transport = { mode = "deferred" }
        local sceneExit = {
            init = noop,
            open = function(options) opens[#opens + 1] = options end,
        }
        local mocks = {
            ["core.PlayerStore"] = { Get = function(key) return modules[key] end },
            ["runtime.ClientDispatcher"] = { get = function(key) return modules[key] end },
            ["core.GameState"] = { getLevel = function() return modules.player.level end, setPower = noop },
            ["systems.ButtonFeedback"] = { trigger = noop },
            ["core.DarkIcon"] = {},
            ["ui.character.detail.CharacterDetail"] = {
                markPowerDirty = noop,
                hasAnyUpgradeForHero = function() return false end,
                hasAwakeningUpgrade = function() return false end,
            },
            ["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop },
            ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
            ["systems.TutorialManager"] = {},
            ["ui.widget.HeroFrame"] = {},
            ["ui.battle.tri.BattleTriPage"] = { invalidateTeams = noop },
            ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end },
            ["ui.loot.LootBoxPage"] = { showToast = function(message) toasts[#toasts + 1] = message end },
            ["ui.dungeon.DungeonBattleScene"] = sceneExit,
            ["rules.dungeon.DungeonService"] = { Challenge = function() return false, "测试拒绝", nil end },
            ["rules.dungeon.DungeonIdleService"] = {},
        }
        local realNames = {
            ["core.DrawUtil"] = true, ["core.BattleLayout"] = true,
            ["core.NumberUtil"] = true, ["shared.Protocol"] = true,
            ["shared.heroes.HeroResonance"] = true,
            ["shared.artifact.ArtifactDefs"] = true, ["shared.artifact.ArtifactSchema"] = true,
            ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true,
            ["systems.TalentEffect"] = true, ["systems.ArtifactBridge"] = true,
            ["systems.EquipmentSystem"] = true, ["systems.EquipmentSetSystem"] = true,
            ["systems.CombatPowerEstimate"] = true, ["systems.ExtraTalentSystem"] = true,
            ["systems.AwakeningGrowth"] = true, ["systems.StatusEffectManager"] = true,
            ["systems.CombatFormula"] = true, ["systems.BattleDiag"] = true,
            ["ui.character.panel.CharacterPanel"] = true,
            ["ui.character.panel.CharacterPanelDraw2"] = true,
            ["ui.character.panel.CharacterDeploy"] = true,
            ["ui.character.panel.CharacterInput"] = true,
            ["ui.character.panel.CharacterHeroSync"] = true,
            ["ui.character.panel.CharacterPower"] = true,
            ["ui.character.panel.CharacterProgress"] = true,
            ["ui.dungeon.DungeonPage"] = true, ["runtime.GameAction"] = true,
            ["ui.dungeon.DungeonRewards"] = true,
            ["rules.dungeon.DungeonHandler"] = true,
        }
        local real, loading = {}, {}
        replace(_G, "require", function(name)
            if mocks[name] then return mocks[name] end
            if real[name] then return real[name] end
            assert(realNames[name] or name:match("^config%."), "禁止未声明依赖或存档入口: " .. name)
            assert(not loading[name], "意外循环依赖: " .. name)
            loading[name] = true
            local value = compile(name)
            loading[name] = nil
            real[name] = value
            return value
        end)

        local CP = require("ui.character.panel.CharacterPanel")
        local Page = require("ui.dungeon.DungeonPage")
        local Protocol = require("shared.Protocol")
        local HC = require("config.HeroConfig")
        local AD = require("systems.AttributeDef")
        local Schema = require("shared.artifact.ArtifactSchema")
        local ACTION = Protocol.ACTION_TYPES.DUNGEON_CHALLENGE
        -- 不创建 GPU 图片；只打开真实 handleInput 的初始化门禁。
        local previousInit, initIndex = upvalue(Page.handleInput, "dungeonInited_")
        restores[#restores + 1] = function() debug.setupvalue(Page.handleInput, initIndex, previousInit) end
        debug.setupvalue(Page.handleInput, initIndex, true)

        local fixtures = {
            { slots = { 1, 0, 0, 4 }, occupied = { 1, 4 } },
            { slots = { 0, 2, 0, 5 }, occupied = { 2, 4 } },
            { slots = { 3, 0, 6, 0 }, occupied = { 1, 3 } },
        }
        local function heroData(emptyTeam)
            local data = { roster = {}, deployed = {}, teams = {} }
            for team = 1, 3 do
                local ids = {}
                for slot = 1, 4 do
                    local id = fixtures[team].slots[slot]
                    ids[slot] = team == emptyTeam and 0 or id
                    if id ~= 0 then
                        data.roster[id] = { level = 20 + id, exp = 0, awakening = {}, extraTalent = {} }
                    end
                end
                data.teams[team] = { slots = ids }
                if team == 1 then data.deployed = ids end
            end
            return data
        end
        local function allUnlocked()
            modules.battle = { currentStageId = 101, maxStageId = 2501, clearedStages = {} }
        end
        for team = 1, 3 do
            for _, slot in ipairs(fixtures[team].occupied) do
                local artifactId = tostring(team * 100 + slot)
                modules.artifacts.bag[#modules.artifacts.bag + 1] = {
                    id = artifactId, artifactId = 2, quality = 4, value = 10 * team + slot,
                    threatClearValue = 30 + team,
                }
                Schema.setEquippedId(modules.artifacts, slot, 1, artifactId, team)
            end
        end
        modules.heroes = heroData()
        CP.setHeroesData(modules.heroes)
        eq(CP.isHeroesDataApplied(), true, "真实英雄同步完成")
        eq(CP.getUnlockedTeamCount(), 3, "真实进度解锁三队")
        local stableHeroes = cjson.encode(modules.heroes)
        local stableArtifacts = cjson.encode(modules.artifacts)
        local stableDungeon = cjson.encode(modules.dungeon)

        local function cleared(label)
            eq(upvalue(Page.update, "pendingChallenge"), false, label .. "解除等待")
            eq(upvalue(Page.update, "pendingChallengeTeam"), nil, label .. "清除队伍快照")
            eq(upvalue(Page.update, "pendingChallengeTime"), 0, label .. "清除等待计时")
        end
        local function verifyTeam(allies, team, label)
            eq(#allies, #fixtures[team].occupied, label .. "人数")
            for index, slot in ipairs(fixtures[team].occupied) do
                local unit = allies[index]
                local id = fixtures[team].slots[slot]
                eq(unit.heroId, id, label .. "英雄顺序" .. index)
                eq(unit.level, 20 + id, label .. "真实英雄等级" .. index)
                eq(unit.artifactTeamIdx, team, label .. "神器队伍标识" .. index)
                eq(#unit.artifactEffects, 1, label .. "神器仅本号位" .. index)
                local effect = unit.artifactEffects[1]
                eq(effect.artifactInstanceId, tostring(team * 100 + slot), label .. "神器实例" .. index)
                eq(effect.effectType, "shield_threat_clear", label .. "真实神器效果" .. index)
                eq(effect.value, 10 * team + slot, label .. "神器数值" .. index)
                eq(effect.threatClearValue, 30 + team, label .. "神器仇恨清除" .. index)
                local base = assert(HC.createHero(id, 20 + id, nil, {}, {}))
                check(math.abs(unit.attrs:get(AD.ES_BONUS) - base.attrs:get(AD.ES_BONUS)
                    - (10 * team + slot)) < 0.0001, label .. "神器实际注入属性" .. index)
                eq(unit.hp, unit.maxHp, label .. "出战满血" .. index)
            end
        end
        local function selected(team)
            eq(CP.setActiveTeam(team), true, "真实选队" .. team)
            eq(CP.getActiveTeamIdx(), team, "选队读回" .. team)
        end
        local function response(request, success)
            if not success then
                local handler = require("rules.dungeon.DungeonHandler")
                local failure = handler.actionHandlers[ACTION](1, request.params)
                failure.action = ACTION -- LocalActionBridge实际加action的传输边界
                eq(failure.dungeonId, request.params.dungeonId, "真实Handler失败副本上下文")
                eq(failure.floor, request.params.floor, "真实Handler失败楼层上下文")
                eq(failure.teamIdx, request.params.teamIdx, "真实Handler失败队号上下文")
                return failure
            end
            return {
                action = ACTION, success = success, reason = success and nil or "测试拒绝",
                dungeonId = request.params.dungeonId, floor = request.params.floor,
                teamIdx = request.params.teamIdx, challengeId = "challenge" .. tostring(request.serial),
                monsterLevel = 25, monsters = {},
                stageEntry = require("config.DungeonConfig").getCombatEntry(request.params.dungeonId, request.params.floor),
            }
        end
        -- 保留真实 GameAction.sendAction；替身只占据传输边界，不走规则层或玩家存档。
        mocks["runtime.LocalActionBridge"] = {
            dispatch = function(action, params)
                eq(action, ACTION, "真实 GameAction 转发普通副本动作")
                eq(upvalue(Page.update, "pendingChallenge"), true, "发送前等待标志已写入")
                local request = {
                    action = action, params = params,
                    capturedTeam = upvalue(Page.update, "pendingChallengeTeam"),
                    settled = false, serial = #sends + 1,
                }
                local explicitTeam = upvalue(Page.handleInput, "detailTeamIdx")
                eq(request.capturedTeam, explicitTeam or CP.getActiveTeamIdx(), "发送前锁定行队号或旧列表所选队伍")
                eq(params.teamIdx, request.capturedTeam, "普通资源副本协议显式携带队号")
                sends[#sends + 1] = request
                if transport.mode == "sync_success" or transport.mode == "sync_failure" then
                    request.settled = true
                    Page.onActionResult(response(request, transport.mode == "sync_success"))
                end
                return true
            end,
        }
        local dungeonCases = {
            { id = "gold_mine", y = 484, floor = 7, title = "金币" },
            { id = "equipment_vault", y = 875, floor = 11, title = "装备" },
            { id = "black_diamond", y = 1266, floor = 5, title = "黑钻" },
        }
        local function detail(case)
            Page.handleInput(0, 0)
            Page.refreshFromStore()
            eq(Page.handleInput(540, case.y), true, case.title .. "真实卡片点击")
            eq(upvalue(Page.handleInput, "detailDungeon").id, case.id, case.title .. "打开详情")
        end
        local function challenge(case)
            local before = #sends
            eq(Page.handleInput(750, 1633), true, case.title .. "真实挑战点击")
            eq(#sends, before + 1, case.title .. "只发送一次")
            local request = sends[#sends]
            eq(request.params.dungeonId, case.id, case.title .. "动作副本正确")
            eq(request.params.floor, case.floor, case.title .. "动作楼层正确")
            return request
        end
        local function resolve(request, success)
            check(not request.settled, "延迟动作尚未结算")
            request.settled = true
            local data = response(request, success)
            Page.onActionResult(data)
            return data
        end
        local function opened(case, team, before, data, label)
            eq(#opens, before + 1, label .. "打开场景一次")
            local options = opens[#opens]
            eq(options.dungeonId, case.id, label .. "场景副本")
            eq(options.data.floor, case.floor, label .. "场景楼层")
            eq(options.teamIdx, team, label .. "场景显式队号")
            eq(options.data.teamIdx, team, label .. "回执队号")
            if data then eq(options.data, data, label .. "回包原样传递") end
            eq(type(options.onClose), "function", label .. "关闭回调存在")
            verifyTeam(options.allies, team, label)
            cleared(label)
        end

        -- 同步本地回调：若锁队快照在 sendAction 之后赋值，队2/3会在此处失败。
        transport.mode = "sync_success"
        for _, case in ipairs(dungeonCases) do
            for team = 1, 3 do
                selected(team)
                detail(case)
                local before = #opens
                challenge(case)
                opened(case, team, before, nil, case.title .. "同步队" .. team)
                print(TAG .. " PASS " .. case.title .. "同步队" .. team)
            end
        end

        -- 延迟回包期间切换正在编辑的队伍，挑战仍使用点击时的队伍及神器。
        transport.mode = "deferred"
        for _, case in ipairs(dungeonCases) do
            for team = 1, 3 do
                selected(team)
                detail(case)
                local before = #opens
                local request = challenge(case)
                selected(team % 3 + 1)
                eq(upvalue(Page.update, "pendingChallengeTeam"), team, "切队不改挑战快照")
                local count = #sends
                Page.handleInput(750, 1633)
                Page.handleInput(750, 1633)
                eq(#sends, count, "等待期间连点不重复发送")
                eq(#opens, before, "未回包不提前打开战斗")
                local data = resolve(request, true)
                opened(case, team, before, data, case.title .. "延迟队" .. team)
                print(TAG .. " PASS " .. case.title .. "延迟切队" .. team)
            end
        end

        -- 异步失败不进入战斗；重试重新读取选择，而不是复用失败动作的队伍。
        for _, case in ipairs(dungeonCases) do
            selected(2)
            detail(case)
            local before = #opens
            local failed = challenge(case)
            selected(3)
            resolve(failed, false)
            eq(#opens, before, "失败不打开场景")
            cleared(case.title .. "失败")
            local retry = challenge(case)
            eq(retry.capturedTeam, 3, "失败重试使用新队3")
            opened(case, 3, before, resolve(retry, true), case.title .. "失败重试")
            print(TAG .. " PASS " .. case.title .. "失败重试")
        end
        -- 同步失败也应释放等待锁，不能在 sendAction 返回之后复活旧快照。
        transport.mode = "sync_failure"
        selected(3)
        detail(dungeonCases[1])
        local beforeSyncFailure = #opens
        challenge(dungeonCases[1])
        eq(#opens, beforeSyncFailure, "同步失败不打开场景")
        cleared("同步失败")
        transport.mode = "sync_success"
        selected(2)
        challenge(dungeonCases[1])
        opened(dungeonCases[1], 2, beforeSyncFailure, nil, "同步失败重试")

        -- 五秒超时边界：此前不可重发，达到门槛后可用新选择重试。
        transport.mode = "deferred"
        for _, case in ipairs(dungeonCases) do
            selected(2)
            detail(case)
            local before = #opens
            local timedOut = challenge(case)
            Page.update(4)
            local count = #sends
            Page.handleInput(750, 1633)
            eq(#sends, count, "四秒仍禁止重发")
            eq(upvalue(Page.update, "pendingChallengeTeam"), 2, "超时前保留队2快照")
            selected(3)
            Page.update(1)
            cleared(case.title .. "五秒超时")
            eq(#opens, before, "超时不打开场景")
            -- 真实迟到回包必须拒绝，不打开场景、不解锁新队请求。
            local late = response(timedOut, true)
            Page.onActionResult(late)
            eq(#opens, before, "超时后迟到Challenge不打开战斗")
            timedOut.settled = true
            local retry = challenge(case)
            Page.onActionResult(late)
            eq(upvalue(Page.update, "pendingChallengeTeam"), 3, "旧队回包不消费新队等待")
            eq(retry.capturedTeam, 3, "超时重试重新捕获队3")
            opened(case, 3, before, resolve(retry, true), case.title .. "超时重试")
            print(TAG .. " PASS " .. case.title .. "超时重试")
        end

        -- 选队之后进度退回锁定态：不允许陈旧 activeTeamIdx 绕过资格校验。
        local lockCases = {
            { team = 2, maxStageId = 905, case = dungeonCases[1] },
            { team = 3, maxStageId = 1905, case = dungeonCases[2] },
        }
        transport.mode = "sync_success"
        for _, lockCase in ipairs(lockCases) do
            allUnlocked()
            selected(lockCase.team)
            modules.battle = { currentStageId = 101, maxStageId = lockCase.maxStageId, clearedStages = {} }
            detail(lockCase.case)
            local sent, openedCount, toastCount = #sends, #opens, #toasts
            Page.handleInput(750, 1633)
            eq(#sends, sent, "锁队拒绝发送队" .. lockCase.team)
            eq(#opens, openedCount, "锁队不打开战斗")
            eq(#toasts, toastCount + 1, "锁队显示拒绝提示")
            cleared("锁队拒绝")
            allUnlocked()
            local before = #opens
            challenge(lockCase.case)
            opened(lockCase.case, lockCase.team, before, nil, "解锁后重试队" .. lockCase.team)
        end

        -- 两类副本和三队的空队均拒绝，随后填回英雄即可重试。
        for _, case in ipairs(dungeonCases) do
            for team = 1, 3 do
                allUnlocked()
                modules.heroes = heroData(team)
                CP.setHeroesData(modules.heroes)
                selected(team)
                eq(#CP.getDeployedTeam(team), 0, "真实空队导出为空")
                detail(case)
                local sent, openedCount, toastCount = #sends, #opens, #toasts
                Page.handleInput(750, 1633)
                eq(#sends, sent, case.title .. "空队" .. team .. "拒绝发送")
                eq(#opens, openedCount, "空队不打开战斗")
                eq(#toasts, toastCount + 1, "空队显示拒绝提示")
                cleared("空队拒绝")
                modules.heroes = heroData()
                CP.setHeroesData(modules.heroes)
                local before = #opens
                challenge(case)
                opened(case, team, before, nil, case.title .. "空队恢复" .. team)
            end
        end

        -- 选关公开API固定行队号，与activeTeam解耦，不发挑战。
        transport.mode = "deferred"
        for _, case in ipairs(dungeonCases) do
            Page.close()
            selected(1)
            local sent = #sends
            eq(Page.openResource(case.id, 3), true, "选关打开资源详情")
            eq(#sends, sent, "openResource不直接发动作")
            eq(CP.getActiveTeamIdx(), 1, "公开API不修改activeTeam")
            selected(2) -- 编辑队2，仍必须发选关行队3
            local before = #opens
            local req = challenge(case)
            selected(2)
            eq(req.params.teamIdx, 3, "选关显式行队号写协议")
            local wrong = response(req, true)
            wrong.teamIdx = nil
            Page.onActionResult(wrong)
            eq(#opens, before, "无team回包不打开场景")
            eq(upvalue(Page.update, "pendingChallengeTeam"), 3, "无team回包不消费pending")
            wrong = response(req, true)
            wrong.dungeonId = "ancient_ruin"
            Page.onActionResult(wrong)
            eq(#opens, before, "错副本回包不打开场景")
            wrong = response(req, true)
            wrong.floor = case.floor + 1
            Page.onActionResult(wrong)
            eq(#opens, before, "错层回包不打开场景")
            opened(case, 3, before, resolve(req, true), "选关显式队3")
            Page.close()
            eq(Page.openResource(case.id, 2), true, "再打开显式队2")
            selected(2)
            req = challenge(case)
            before = #opens
            Page.close()
            resolve(req, true)
            eq(#opens, before, "关闭详情后迟到回包拒绝")
            cleared("关闭详情")
        end
        eq(Page.openResource("ancient_ruin", 1), false, "隐藏旧遗迹没有资源入口")
        eq(Page.openResource("gold_mine", 0), false, "显式队号0拒绝")
        eq(Page.openResource("gold_mine", 4), false, "显式队号4拒绝")
        eq(Page.openResource("gold_mine", 1.5), false, "非整数队号拒绝")
        Page.close()
        eq(Page.openTower(), true, "独立塔公开详情")
        eq(upvalue(Page.handleInput, "detailDungeon").id, "babel_tower", "独立塔不是黑钻副本")
        Page.close()
        local towerLate = { action = Protocol.ACTION_TYPES.TOWER_CHALLENGE, success = true, floor = 1, wave = 1 }
        Page.onActionResult(towerLate) -- 若重新打开塔会触发禁止未声明require并令测试失败。
        cleared("关闭后塔迟到回包")

        -- 规则抛异常的合法失败仍需携带身份，不能被UI当作迟到包永久忽略。
        local serviceMock = mocks["rules.dungeon.DungeonService"]
        local oldChallenge = serviceMock.Challenge
        local oldWin = serviceMock.Win
        serviceMock.Challenge = function() error("expected-challenge-error", 0) end
        serviceMock.Win = function() error("expected-win-error", 0) end
        local ruleHandlers = require("rules.dungeon.DungeonHandler").actionHandlers
        local failedRequest = { dungeonId = "equipment_vault", floor = 11, teamIdx = 3,
            challengeId = "current-error-token" }
        for _, action in ipairs({ ACTION, Protocol.ACTION_TYPES.DUNGEON_WIN }) do
            local failed = ruleHandlers[action](1, failedRequest)
            eq(failed.success, false, "异常失败返回false")
            eq(failed.reason, "本地处理失败", "异常失败不暴露内部堆栈")
            for _, key in ipairs({ "dungeonId", "floor", "teamIdx", "challengeId" }) do
                eq(failed[key], failedRequest[key], "异常失败保留 " .. key)
            end
        end
        serviceMock.Challenge, serviceMock.Win = oldChallenge, oldWin

        -- 主线旧调用不带队号必须仍是队1；绝不能为修副本而改变 CP 的默认值。
        selected(3)
        verifyTeam(CP.getDeployedTeam(), 1, "主线缺省队1")
        verifyTeam(CP.getDeployedTeam(nil), 1, "主线显式nil仍队1")
        eq(CP.getActiveTeamIdx(), 3, "主线取队不会改变正在编辑的队3")
        -- 没有pending的旧回包现在必须拒绝，不能伪造队一战斗。
        local beforeFallback = #opens
        local legacy = { action = ACTION, success = true, dungeonId = "gold_mine", floor = 7, monsters = {} }
        Page.onActionResult(legacy)
        eq(#opens, beforeFallback, "无等待旧回包拒绝")
        cleared("无等待旧回包")
        print(TAG .. " PASS 主线缺省队1与副本严格回执")

        eq(cjson.encode(modules.heroes), stableHeroes, "测试未改输入英雄数据")
        eq(cjson.encode(modules.artifacts), stableArtifacts, "真实神器桥未改装配数据")
        eq(cjson.encode(modules.dungeon), stableDungeon, "挑战页面未修改副本存档数据")
        eq(modules.battle.currentStageId, 101, "副本选队不改主线当前关")
        for name, value in pairs(package.loaded) do
            eq(value, packageSnapshot[name], "require替身不污染模块缓存 " .. name)
        end
        for name, value in pairs(packageSnapshot) do
            eq(package.loaded[name], value, "原模块缓存保留 " .. name)
        end
        print(TAG .. " PASS 输入数据与模块缓存隔离")
    end)
    -- 无论断言是否失败均逆序还原替身，不留全局 require 或状态门禁修改。
    for index = #restores, 1, -1 do
        local restored, restoreError = pcall(restores[index])
        if not restored then
            ok = false
            err = tostring(err or "") .. "; 还原失败: " .. tostring(restoreError)
        end
    end
    rawset(_G, "require", nativeRequire)
    if require ~= nativeRequire or time ~= nativeTime then
        ok, err = false, "require/time 全局替身未还原"
    end
    if not ok then
        log:Write(LOG_ERROR, TAG .. " FAIL after " .. assertions .. " assertions: " .. tostring(err))
    else
        print(TAG .. " ALL PASS: " .. assertions .. " assertions")
    end
    engine:Exit()
end
