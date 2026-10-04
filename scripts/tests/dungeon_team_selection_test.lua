-- 副本入口/选队回归：真实页面、Entry门槛/绘制、编队、英雄属性、神器桥和GameAction。
-- 仅在存档读取、动作传输、绘图终端和场景出口隔离；不初始化存档、不落盘、不运行随机战斗。
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
        local clock = { elapsedTime = 100 }
        env.time = clock
        -- 绘图终端记录器只隔离GPU：Page/Entry/DrawUtil的布局和文字选择仍执行真代码。
        local drawnTexts, drawnPanels = {}, {}
        local renderState = { fontSize = 30 }
        for _, name in ipairs({
            "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFill", "nvgFillColor",
            "nvgFillPaint", "nvgSave", "nvgRestore", "nvgScissor", "nvgIntersectScissor",
            "nvgTranslate", "nvgScale", "nvgSkewX", "nvgFontFace", "nvgTextAlign", "nvgGlobalAlpha",
        }) do env[name] = noop end
        env.nvgCreateImage = function() return -1 end
        env.nvgFontSize = function(_, size) renderState.fontSize = size end
        env.nvgTextBounds = function(_, _, _, text)
            return (utf8.len(text) or #text) * renderState.fontSize * 0.7
        end
        env.nvgText = function(_, x, y, text)
            drawnTexts[#drawnTexts + 1] = { x = x, y = y, text = text, size = renderState.fontSize }
            return x
        end
        local modules = {
            player = { level = 100 },
            battle = { currentStageId = 101, maxStageId = 2501, clearedStages = {} },
            dungeon = {
                gold_mine = { floor = 7, dailyUsed = 0 },
                ancient_ruin = { floor = 11, dailyUsed = 0 },
                babel_tower = { floor = 7, dailyUsed = 0 },
            },
            artifacts = { bag = {}, equipped = {}, equippedByTeam = {} },
        }
        local toasts, sends, opens, towerOpens, navChanges = {}, {}, {}, {}, {}
        local transport = { mode = "deferred" }
        local navState = { tab = 5, allLocked = false }
        local tutorialState = { active = false }
        local sceneState = { dungeon = false, tower = false }
        local sceneExit = {
            init = noop,
            isOpen = function() return sceneState.dungeon end,
            open = function(options)
                sceneState.dungeon = true
                opens[#opens + 1] = options
            end,
        }
        local mocks = {
            ["core.PlayerStore"] = { Get = function(key) return modules[key] end },
            ["runtime.ClientDispatcher"] = { get = function(key) return modules[key] end },
            ["core.GameState"] = { getLevel = function() return modules.player.level end, setPower = noop },
            ["core.I18n"] = {
                lookup = function(text) return text end,
                format = function(text, ...) return string.format(text, ...) end,
                t = function(key) return key == "tab_dungeon" and "副本" or key end,
            },
            ["systems.ButtonFeedback"] = { trigger = noop, begin = noop, finish = noop },
            ["core.DarkIcon"] = {
                drawNine = function(_, kind, x, y, w, h, options)
                    drawnPanels[#drawnPanels + 1] = { kind = kind, x = x, y = y, w = w, h = h, options = options }
                end,
                drawQualityBg = noop,
            },
            ["ui.character.detail.CharacterDetail"] = {
                markPowerDirty = noop,
                hasAnyUpgradeForHero = function() return false end,
                hasAwakeningUpgrade = function() return false end,
            },
            ["ui.hud.BottomNav"] = {
                state = navState,
                setBadge = noop, refreshTownBadge = noop,
                getSelectedIndex = function() return navState.tab end,
                isAllLocked = function() return navState.allLocked end,
                setSelectedIndex = function(tab)
                    navState.tab = tab
                    navChanges[#navChanges + 1] = tab
                end,
            },
            ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
            ["systems.TutorialManager"] = { isActive = function() return tutorialState.active end },
            ["ui.widget.HeroFrame"] = {},
            ["ui.battle.tri.BattleTriPage"] = { invalidateTeams = noop },
            ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end },
            ["ui.loot.LootBoxPage"] = { showToast = function(message) toasts[#toasts + 1] = message end },
            ["ui.dungeon.DungeonBattleScene"] = sceneExit,
            ["ui.tower.TowerBattleScene"] = {
                isActive = function() return sceneState.tower end,
                open = function(options)
                    sceneState.tower = true
                    towerOpens[#towerOpens + 1] = options
                end,
            },
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
            ["ui.dungeon.DungeonPage"] = true, ["ui.dungeon.DungeonEntry"] = true,
            ["runtime.GameAction"] = true,
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
        local Entry = require("ui.dungeon.DungeonEntry")
        local TowerConfig = require("config.TowerConfig")
        local nativeShowMessage = Entry.showMessage
        replace(Entry, "showMessage", function(message)
            toasts[#toasts + 1] = message
            nativeShowMessage(message)
        end)
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
        local loadingDisabled, loadingReason = Entry.getTowerChallengeState(7)
        eq(loadingDisabled, true, "真实Entry未水合编队不可挑战")
        eq(loadingReason, "编队数据加载中", "真实Entry显示加载提示")
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
            eq(upvalue(Page.update, "pendingChallengeId"), nil, label .. "清除请求编号")
        end
        local function waiting(request, label)
            eq(upvalue(Page.update, "pendingChallenge"), true, label .. "仍在等待")
            eq(upvalue(Page.update, "pendingChallengeId"), request.params.requestId, label .. "保留当前请求编号")
            eq(upvalue(Page.update, "pendingChallengeTeam"), request.capturedTeam, label .. "保留当前队伍快照")
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
            return {
                action = request.action, success = success, reason = success and nil or "测试拒绝",
                requestId = request.params.requestId,
                dungeonId = request.params.dungeonId, floor = request.params.floor or modules.dungeon.babel_tower.floor,
                wave = 1, monsterLevel = 25, monsters = {},
            }
        end
        -- 保留真实 GameAction.sendAction；替身只占据传输边界，不走规则层或玩家存档。
        mocks["runtime.LocalActionBridge"] = {
            dispatch = function(action, params)
                check(action == ACTION or action == Protocol.ACTION_TYPES.TOWER_CHALLENGE,
                    "真实GameAction只转发声明的普通/塔挑战")
                eq(upvalue(Page.update, "pendingChallenge"), true, "发送前等待标志已写入")
                check(type(params.requestId) == "number" and params.requestId > 0, "动作附带正请求编号")
                eq(params.requestId, upvalue(Page.update, "pendingChallengeId"), "发送编号与页面等待一致")
                for _, previous in ipairs(sends) do
                    check(previous.params.requestId ~= params.requestId, "每次挑战使用新请求编号")
                end
                local request = {
                    action = action, params = params,
                    capturedTeam = upvalue(Page.update, "pendingChallengeTeam"),
                    settled = false,
                }
                if action == ACTION then
                    eq(request.capturedTeam, CP.getActiveTeamIdx(), "发送前锁定所选队伍")
                    eq(params.teamIdx, nil, "保持现有普通副本协议参数")
                end
                sends[#sends + 1] = request
                if transport.mode == "sync_success" or transport.mode == "sync_failure" then
                    request.settled = true
                    Page.onActionResult(response(request, transport.mode == "sync_success"))
                end
                if transport.mode == "send_false" then return false end
                return true
            end,
        }
        local dungeonCases = {
            { id = "gold_mine", y = 504, floor = 7, title = "矿洞" },
            { id = "ancient_ruin", y = 932, floor = 11, title = "遗迹" },
        }
        local function detail(case)
            sceneState.dungeon, sceneState.tower = false, false
            navState.tab = 5
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
                local wrongAction = response(request, true)
                wrongAction.action = Protocol.ACTION_TYPES.TOWER_CHALLENGE
                local towerBefore = #towerOpens
                Page.onActionResult(wrongAction)
                waiting(request, "相同编号塔动作不消费普通挑战")
                eq(#towerOpens, towerBefore, "动作错配不可打开塔")
                eq(#opens, before, "动作错配不可打开普通副本")
                navState.tab = 3
                Page.onActionResult(response(request, true))
                waiting(request, "非副本tab不消费挑战")
                eq(#opens, before, "非副本tab收到成功不open")
                navState.tab = 5
                local data = resolve(request, true)
                opened(case, team, before, data, case.title .. "延迟队" .. team)
                Page.onActionResult(data)
                eq(#opens, before + 1, "重复成功回包不重复打开场景")
                cleared("重复成功回包")
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
            local retry = challenge(case)
            eq(retry.capturedTeam, 3, "超时重试重新捕获队3")
            check(timedOut.params.requestId ~= retry.params.requestId, "同副本同楼层重试使用不同编号")
            local elapsed = upvalue(Page.update, "pendingChallengeTime")
            resolve(timedOut, true)
            eq(#opens, before, "A超时迟到成功不可提前开B战斗")
            waiting(retry, "A迟到不消费B")
            eq(upvalue(Page.update, "pendingChallengeTime"), elapsed, "A迟到不重置B计时")
            Page.onActionResult(response(timedOut, false))
            waiting(retry, "A迟到失败不消费B")
            local noId = response(retry, true)
            noId.requestId = nil
            Page.onActionResult(noId)
            waiting(retry, "无编号成功回包不消费B")
            eq(#opens, before, "旧无编号回包不打开战斗")
            opened(case, 3, before, resolve(retry, true), case.title .. "超时B成功重试")
            print(TAG .. " PASS " .. case.title .. "超时A/重试B/迟到隔离")
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

        -- 返回是授权撤销：详情先退列表，列表再退tab3，不调用战斗关闭/发奖接口。
        transport.mode = "deferred"
        for _, case in ipairs(dungeonCases) do
            selected(2)
            detail(case)
            local before, navBefore = #opens, #navChanges
            Entry.showMessage("返回测试")
            eq(Page.handleBack(), true, "真实handleBack消费详情返回")
            eq(upvalue(Page.handleInput, "detailOpen"), false, "详情返回列表")
            eq(upvalue(Page.handleInput, "detailDungeon"), nil, "详情副本引用清理")
            eq(navState.tab, 5, "详情返回仍留副本tab5")
            eq(#navChanges, navBefore, "详情返回不跳页")
            cleared("详情返回")
            eq(Page.handleBack(), true, "真实handleBack消费列表返回")
            eq(navState.tab, 3, "列表返回主界面tab3")
            eq(#navChanges, navBefore + 1, "列表只跳页一次")
            eq(Entry.getMessage(), "", "列表返回清理页面反馈")
            eq(#opens, before, "返回不打开战斗")

            detail(case)
            local cancelled = challenge(case)
            eq(Page.handleInput(540, 225), true, "真实Entry按钮触发pending返回")
            eq(upvalue(Page.handleInput, "detailOpen"), false, "pending返回也退出详情")
            cleared("pending返回")
            resolve(cancelled, true)
            eq(#opens, before, "详情返回后的迟到成功包不open")
            cleared("返回迟到包")
            Page.handleBack()
            eq(navState.tab, 3, "pending撤销后列表仍可返回tab3")
            Page.onActionResult(response(cancelled, true))
            eq(#opens, before, "主界面收到重复迟到包不open")

            -- 同tuple返页重试，旧请求编号不能消费新授权。
            detail(case)
            local retry = challenge(case)
            Page.onActionResult(response(cancelled, true))
            waiting(retry, "返页旧包不消费新请求")
            eq(#opens, before, "返页旧包不open")
            opened(case, 2, before, resolve(retry, true), case.title .. "返页新授权")
            print(TAG .. " PASS " .. case.title .. "真实返回与撤销迟到隔离")
        end

        -- 发送false必须释放所有等待字段，下一次真实点击即可重试。
        for _, case in ipairs(dungeonCases) do
            selected(3)
            detail(case)
            transport.mode = "send_false"
            local before, toastBefore = #opens, #toasts
            local rejected = challenge(case)
            eq(#opens, before, "传输返回false不打开战斗")
            cleared("发送false")
            eq(#toasts, toastBefore + 1, "发送false产生真实Entry反馈")
            eq(Entry.getMessage(), "挑战发送失败，请重试", "发送false页面提示正确")
            transport.mode = "deferred"
            local retry = challenge(case)
            Page.onActionResult(response(rejected, true))
            waiting(retry, "发送false旧包不消费重试")
            opened(case, 3, before, resolve(retry, true), case.title .. "发送false重试")
        end

        -- 独占门禁消费返回但不得取消pending、退出详情或切tab。
        local guardCases = {
            { state = navState, key = "allLocked", label = "全局锁" },
            { state = tutorialState, key = "active", label = "教程独占" },
            { state = sceneState, key = "tower", label = "塔战斗独占" },
            { state = sceneState, key = "dungeon", label = "副本战斗独占" },
        }
        for _, guard in ipairs(guardCases) do
            selected(2)
            detail(dungeonCases[1])
            local request = challenge(dungeonCases[1])
            local before, navBefore = #opens, #navChanges
            guard.state[guard.key] = true
            eq(Page.handleBack(), true, guard.label .. "消费直接返回")
            eq(Page.handleInput(540, 225), true, guard.label .. "消费按钮返回")
            eq(Page.handleInput(0, 0), true, guard.label .. "消费背景返回")
            eq(upvalue(Page.handleInput, "detailOpen"), true, guard.label .. "不退出详情")
            eq(navState.tab, 5, guard.label .. "不切tab")
            eq(#navChanges, navBefore, guard.label .. "无导航副作用")
            eq(#opens, before, guard.label .. "无场景副作用")
            waiting(request, guard.label .. "不撤销等待")
            guard.state[guard.key] = false
            Page.handleBack()
            cleared(guard.label .. "释放后返回")
            resolve(request, true)
            eq(#opens, before, guard.label .. "释放后已撤销回包不open")
        end
        print(TAG .. " PASS 返回独占门禁与发送失败恢复")

        -- 真实Entry门槛及绘图选择；配置只读，不用假Entry绕过页面逻辑。
        local towerCase = { id = "babel_tower", y = 1360, floor = 7, title = "通天塔" }
        local function hasText(text, y)
            for _, draw in ipairs(drawnTexts) do
                if draw.text == text and (not y or draw.y == y) then return true end
            end
            return false
        end
        local function render()
            drawnTexts, drawnPanels = {}, {}
            Page.update(0.2)
            Page.draw({})
        end
        local exportCalls = 0
        local nativeExport = CP.getDeployedTeam
        replace(CP, "getDeployedTeam", function(...)
            exportCalls = exportCalls + 1
            return nativeExport(...)
        end)
        allUnlocked()
        detail(towerCase)
        local readyDisabled, readyReason = Entry.getTowerChallengeState(7)
        eq(readyDisabled, false, "真实Entry三队就绪放行")
        render()
        check(hasText("副本", 110), "真实Page调用Entry标题绘制")
        check(hasText("返回列表", 225), "真实详情返回文案")
        check(hasText(readyReason, 1710), "真实塔详情三队规则提示")
        local first, sweep = Entry.getTowerRewards(7)
        eq(first, 550, "配置第7层首通钻石")
        eq(sweep, 250, "配置第6层扫荡钻石")
        check(hasText("本层首通 550 · 上层扫荡 250", 1465), "真实塔奖励绘图")
        eq(exportCalls, 0, "逐帧门槛绘制不创建战斗英雄")
        check(Entry.hitBack(540, 225), "真实返回按钮中心命中")
        check(not Entry.hitBack(359, 225), "返回按钮左外缘不命中")
        check(not Entry.hitBack(721, 225), "返回按钮右外缘不命中")
        check(not Entry.hitBack(540, 179), "返回按钮上外缘不命中")
        check(not Entry.hitBack(540, 271), "返回按钮下外缘不命中")
        local beforeTower, sentBefore = #towerOpens, #sends
        eq(Page.handleInput(750, 1633), true, "真实塔挑战按钮")
        eq(#sends, sentBefore + 1, "塔三队就绪只发送一次")
        local towerRequest = sends[#sends]
        eq(towerRequest.action, Protocol.ACTION_TYPES.TOWER_CHALLENGE, "真实塔动作类型")
        local wrongTowerAction = response(towerRequest, true)
        wrongTowerAction.action = ACTION
        local ordinaryBefore = #opens
        Page.onActionResult(wrongTowerAction)
        waiting(towerRequest, "相同编号普通动作不消费塔挑战")
        eq(#opens, ordinaryBefore, "塔动作错配不可打开普通副本")
        Page.handleBack()
        cleared("塔pending返回")
        resolve(towerRequest, true)
        eq(#towerOpens, beforeTower, "塔返回后迟到回包不open")

        local function towerRejected(reason, label)
            detail(towerCase)
            render()
            check(hasText(reason, 1710), label .. "详情绘制真实拒绝提示")
            local sent, openedCount = #sends, #towerOpens
            eq(Page.handleInput(750, 1633), true, label .. "拒绝点击被消费")
            eq(#sends, sent, label .. "不发送动作")
            eq(#towerOpens, openedCount, label .. "不打开塔")
            eq(Entry.getMessage(), reason, label .. "真实Entry页面反馈")
            cleared(label)
        end
        modules.battle = { currentStageId = 101, maxStageId = 1905, clearedStages = {} }
        local lockedDisabled, lockedReason = Entry.getTowerChallengeState(7)
        eq(lockedDisabled, true, "真实配置三队锁定门槛")
        towerRejected(lockedReason, "三队未解锁")
        allUnlocked()
        for team = 1, 3 do
            modules.heroes = heroData(team)
            CP.setHeroesData(modules.heroes)
            local disabled, reason = Entry.getTowerChallengeState(7)
            eq(disabled, true, "真实Entry拒绝空队" .. team)
            eq(reason, "队伍" .. team .. "为空，请在右侧部署队员", "空队编号准确")
            towerRejected(reason, "塔空队" .. team)
        end
        modules.heroes = heroData()
        CP.setHeroesData(modules.heroes)
        modules.dungeon.babel_tower.floor = TowerConfig.MAX_FLOOR + 1
        local completeDisabled, completeReason = Entry.getTowerChallengeState(TowerConfig.MAX_FLOOR + 1)
        eq(completeDisabled, true, "完成全部塔层禁用挑战")
        towerRejected(completeReason, "全部塔层已完成")
        modules.dungeon.babel_tower.floor = towerCase.floor
        Page.handleBack()
        render()
        check(hasText("返回主界面", 225), "真实列表返回文案")
        check(hasText("三队就绪，可挑战"), "真实塔卡片就绪提示")
        local beforeMessagePanels = #drawnPanels
        Entry.showMessage(string.rep("反馈", 80))
        Entry.drawMessage({})
        eq(#drawnPanels, beforeMessagePanels + 1, "真实反馈绘制面板")
        local lastText = drawnTexts[#drawnTexts]
        check(lastText.size < 36, "长反馈真实缩字号避免溢出")
        clock.elapsedTime = 103
        eq(Entry.getMessage(), "", "真实反馈三秒到期消失")
        local expiredDraws = #drawnTexts
        Entry.drawMessage({})
        eq(#drawnTexts, expiredDraws, "到期反馈不绘制")
        eq(exportCalls > 0, true, "实际挑战仍使用真实英雄导出")
        print(TAG .. " PASS 真实Entry门槛/绘制/只读配置")

        -- 主线旧调用不带队号必须仍是队1；绝不能为修副本而改变CP的默认值。
        selected(3)
        verifyTeam(CP.getDeployedTeam(), 1, "主线缺省队1")
        verifyTeam(CP.getDeployedTeam(nil), 1, "主线显式nil仍队1")
        eq(CP.getActiveTeamIdx(), 3, "主线取队不会改变正在编辑的队3")
        -- 授权返页抑制的新契约：无pending旧成功包一律忽略，不再兼容打开队1。
        detail(dungeonCases[1])
        eq(upvalue(Page.handleBack, "pageClosed"), false, "重新进入副本页而非借已关闭标志拒包")
        local beforeFallback = #opens
        local legacy = { action = ACTION, success = true, dungeonId = "gold_mine", floor = 7, monsters = {} }
        Page.onActionResult(legacy)
        eq(#opens, beforeFallback, "无等待旧成功回包忽略")
        Page.onActionResult(response(sends[1], true))
        eq(#opens, beforeFallback, "无等待有编号旧成功回包也忽略")
        cleared("无等待旧成功回包")
        print(TAG .. " PASS 主线默认队1与无授权旧回包拒绝")

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
