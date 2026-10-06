-- 宿主特效接线专项：执行真实模块/带唯一锚点的生产源码段，不复制玩法逻辑。
-- 独立Runtime入口；不加载main/存档，不构建，不修改生产模块或共享全局。
local TAG = "[dark_effects_host_integration_test]"
local checks, failures = 0, 0
local function check(value, label)
    checks = checks + 1
    if not value then failures = failures + 1 end
    print(TAG .. (value and " PASS " or " FAIL ") .. label)
end
local function near(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.000001
end
local function noop() end

function Start()
    local ok, err = pcall(function()
        local nativeRequire = require
        local Layout = nativeRequire("core.BattleLayout")
        local HC = nativeRequire("config.HeroConfig")
        local clock = { elapsedTime = 100 }
        local sources = {}
        local function source(path)
            if sources[path] then return sources[path] end
            local file = assert(cache:GetFile(path), "missing production source " .. path)
            local lines = {}
            while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
            file:Dispose()
            local text = table.concat(lines, "\n")
            sources[path] = text
            return text
        end
        local function segment(path, first, last)
            local text = source(path)
            local a = assert(text:find(first, 1, true), "missing start anchor " .. first)
            assert(not text:find(first, a + #first, true), "ambiguous start anchor " .. first)
            local b = assert(text:find(last, a + #first, true), "missing end anchor " .. last)
            return text:sub(a, b - 1)
        end
        local function environment(mocks, fields)
            local env = setmetatable(fields or {}, { __index = _G })
            env.time = clock
            env.File = function() error("host integration forbids player File access") end
            env.require = function(name)
                if mocks and mocks[name] then return mocks[name] end
                assert(not name:match("^boot%.") and not name:match("^rules%."), "unexpected business import " .. name)
                return nativeRequire(name)
            end
            return env
        end
        local function compile(path, mocks, fields)
            return assert(load(source(path), "@host-real/" .. path, "t", environment(mocks, fields)))()
        end
        local plays, draws, cancels = {}, {}, {}
        local Card = {}
        local function playback(kind, cx, cy, cb, scope, width, height)
            plays[#plays + 1] = { kind = kind, cx = cx, cy = cy, callback = cb,
                scope = scope, width = width, height = height }
        end
        Card.playLevelUp = function(...) playback("level", ...) end
        Card.playRevive = function(...) playback("revive", ...) end
        Card.playJobChange = function(...) playback("job", ...) end
        Card.draw = function(vg, scope) draws[#draws + 1] = { vg = vg, scope = scope } end
        Card.stopAll = function(scope) cancels[#cancels + 1] = scope end
        local effectsEnabled = true
        local Settings = { isEffectsEnabled = function() return effectsEnabled end }
        local function stripSize(entry, label)
            check(near(entry.width, Layout.CARD_W * Layout.CARD_SCALE)
                and near(entry.height, Layout.CARD_H * Layout.CARD_SCALE), label .. " unmultiplied strip size")
            check(near(entry.cy, Layout.STRIP_CY), label .. " real strip center")
            check(entry.callback == nil, label .. " no business callback added")
        end

        -- 真实BattleAllyLifecycle.bind+refresh；属性构造用真实HC，外围拥有/神器输入隔离。
        local owned, created, equipmentArgs, artifactArgs = {}, {}, {}, {}
        local Panel = { getOwnedHero = function(id) return owned[id] end,
            getEffectiveLevel = function(id) return owned[id].level end,
            applyEquippedItems = function(attrs, id, slot)
                equipmentArgs[#equipmentArgs + 1] = { attrs = attrs, id = id, slot = slot }
                return 2
            end }
        local heroFactory = { createHero = function(...)
            local unit = HC.createHero(...)
            created[#created + 1] = unit
            return unit
        end }
        local BC = { getCardCX = function(list, index)
            return Layout.posForList(list, index)
        end }
        local bridge = { applyToUnit = function(attrs, slot, unused, team)
            artifactArgs[#artifactArgs + 1] = { attrs = attrs, slot = slot, team = team }
            return {}
        end }
        local lifeMocks = { ["config.HeroConfig"] = heroFactory,
            ["ui.character.panel.CharacterPanel"] = Panel,
            ["systems.ArtifactBridge"] = bridge,
            ["ui.battle.combat.BattleCombat"] = BC,
            ["ui.fx.SpineCardEffect"] = Card }
        local Lifecycle = compile("ui/battle/scene/BattleAllyLifecycle.lua", lifeMocks)
        local function hero(id, level, team, slot)
            local unit = assert(HC.createHero(id, level))
            unit.partySlot, unit.artifactTeamIdx = slot or 1, team or 1
            unit._baseSnapshot = unit.attrs:clone()
            unit.atkProgress, unit.reviveTimer = 0.37, nil
            owned[id] = { level = level + 1 }
            return unit
        end
        local function lifeFor(list, scope, cy, scale)
            local calls = { income = 0, set = 0 }
            local life = Lifecycle.bind({ getAllies = function() return list end,
                getEnemies = function() return {} end, getEnemyQueue = function() return {} end,
                recalcIdleIncome = function() calls.income = calls.income + 1 end,
                -- 真实Scene.get是封闭键表；新增视觉字段不得通过get读取。
                get = function(key) error("refresh must not query closed get: " .. tostring(key)) end,
                set = function() calls.set = calls.set + 1 end,
                ALLY_CARD_CY = 1760, effectScope = scope, effectCardCY = cy, effectCardScale = scale })
            return life, calls
        end
        local live, dead = hero(1, 10, 2, 3), hero(2, 10, 2, 4)
        dead.hp, dead.reviveTimer = 0, 0.23
        local allies = { live, dead }
        local liveAttrs, liveBase, liveHP = live.attrs, live._baseSnapshot, live.hp
        local deadAttrs, deadBase = dead.attrs, dead._baseSnapshot
        local life, counts = lifeFor(allies, "tri2", Layout.STRIP_CY, Layout.CARD_SCALE)
        local before = #plays
        life.refreshAllyStats()
        check(#plays == before + 1 and plays[#plays].scope == "tri2", "refresh level only living unit and own scope")
        stripSize(plays[#plays], "tri2 refresh")
        check(near(plays[#plays].cx, Layout.STRIP_ALLY_X0), "refresh uses actual first slot center")
        check(live.attrs == liveAttrs and live._baseSnapshot == liveBase and live.hp == liveHP
            and live.atkProgress == 0.37, "refresh preserves living current wave attrs/hp/progress")
        check(dead.attrs == deadAttrs and dead._baseSnapshot == deadBase and dead.hp == 0
            and dead.reviveTimer == 0.23, "refresh preserves dead wave/death timer")
        check(live._pendingSnapshot == created[#created - 1].attrs and dead._pendingSnapshot == created[#created].attrs,
            "both real rebuilt attrs stored pending")
        check(live._pendingLevel == 11 and dead._pendingLevel == 11 and live._pendingArmorType == 2,
            "pending level/armor contract retained")
        check(#live._pendingArtifactEffects == 0 and #dead._pendingArtifactEffects == 0
            and artifactArgs[#artifactArgs].team == 2 and artifactArgs[#artifactArgs].slot == 4,
            "pending artifact removal uses actual team/slot")
        check(equipmentArgs[#equipmentArgs].slot == 4 and counts.income == 1 and counts.set == 0,
            "refresh no reset/setter and retains income call")
        before = #plays
        life.refreshAllyStats()
        check(#plays == before, "unchanged pending level does not restart effect")
        owned[1].level = 9
        life.refreshAllyStats()
        check(#plays == before and live._pendingLevel == 9 and live.hp == liveHP,
            "level decrease only replaces pending without visual or heal")
        local classicLayout = setmetatable({ MODE = "classic" }, { __index = Layout })
        lifeMocks["core.BattleLayout"] = classicLayout
        local ClassicLifecycle = compile("ui/battle/scene/BattleAllyLifecycle.lua", lifeMocks)
        local classicUnit = hero(3, 10)
        local classicLife = ClassicLifecycle.bind({ getAllies = function() return { classicUnit } end,
            recalcIdleIncome = noop, ALLY_CARD_CY = 1760 })
        classicLife.refreshAllyStats()
        check(plays[#plays].scope == "battle" and plays[#plays].cy == 1760
            and near(plays[#plays].width, Layout.CARD_W) and near(plays[#plays].height, Layout.CARD_H),
            "classic default retains original battle center and full card size")
        lifeMocks["core.BattleLayout"] = nil

        -- 精确抽取真实Page成长方法，保留原mount/过滤/bind，不复制其分流逻辑。
        local refreshCode = segment("ui/battle/tri/BattleTriPage.lua",
            "function BattleTriPage.refreshHeroProgressTeams(teamIndices, classTeams)", "-- [终焉协同] 前向声明")
        local fixtureDrivers, mounts, invalidations, bound = {}, {}, {}, {}
        for team = 1, 3 do
            local unit = hero(team, 20, team, team)
            fixtureDrivers[team] = { allies = { unit }, enemies = {}, enemyQueue = {},
                mount = function() mounts[#mounts + 1] = team end }
        end
        local pageMocks = { ["ui.battle.scene.BattleAllyLifecycle"] = { bind = function(deps)
            bound[#bound + 1] = deps
            return Lifecycle.bind(deps)
        end } }
        local pageEnv = environment(pageMocks, { BattleLayout = Layout, COL_COUNT = 3,
            drivers = fixtureDrivers, isOpen_ = true,
            BattleMountScope = { run = function(body) return body() end },
            BattleTriPage = { invalidateTeams = function(teams) invalidations[#invalidations + 1] = teams end } })
        local refresh = assert(load(refreshCode .. "\nreturn BattleTriPage.refreshHeroProgressTeams",
            "@host-real/Page.refreshHeroProgressTeams", "t", pageEnv))()
        before = #plays
        refresh({ 1, 2, 3 })
        check(#plays == before + 3 and #mounts == 3 and #bound == 3, "real Page refresh routes all changed drivers")
        for team = 1, 3 do
            check(bound[team].effectScope == "tri" .. team and bound[team].effectCardCY == Layout.STRIP_CY
                and bound[team].effectCardScale == Layout.CARD_SCALE, "Page explicit visual deps team " .. team)
            check(plays[before + team].scope == "tri" .. team, "real lifecycle own scope team " .. team)
        end
        before = #plays
        refresh({ 2 }, { [2] = true })
        check(#plays == before and #invalidations == 1 and invalidations[1][2],
            "class rebuild keeps existing invalidation instead of fake level refresh")

        -- 精确抽取真实Tri内容缩放+三行循环，NanoVG recorder校验同一矩阵和裁剪。
        local triCode = segment("ui/battle/tri/BattleTriPage.lua",
            "    -- 统一战斗缩放: 取三个内矩形中最小可容缩放", "    -- ===== UI 层（窗口坐标）=====")
        local matrix = { sx = 1, sy = 1, tx = 0, ty = 0 }
        local stack, clip, views = {}, nil, {}
        local function snap()
            return { sx = matrix.sx, sy = matrix.sy, tx = matrix.tx, ty = matrix.ty,
                clip = clip, depth = #stack }
        end
        local triFields = { BattleLayout = Layout, COL_COUNT = 3, drivers = fixtureDrivers,
            terminalRaid = nil, unlocked = 3, logicalW = 474, logicalH = 540,
            interiorRect = function(row) return 10, 20 + (row - 1) * 190, 474, 180 end,
            nvgSave = function()
                stack[#stack + 1] = { sx = matrix.sx, sy = matrix.sy, tx = matrix.tx, ty = matrix.ty, clip = clip }
            end,
            nvgRestore = function()
                local old = assert(table.remove(stack), "unbalanced tri restore")
                matrix = { sx = old.sx, sy = old.sy, tx = old.tx, ty = old.ty }; clip = old.clip
            end,
            nvgScissor = function(_, x, y, w, h) clip = { x = x, y = y, w = w, h = h } end,
            nvgTranslate = function(_, x, y) matrix.tx = matrix.tx + x * matrix.sx; matrix.ty = matrix.ty + y * matrix.sy end,
            nvgScale = function(_, x, y) matrix.sx = matrix.sx * x; matrix.sy = matrix.sy * y end,
            BattleView = { draw = function(_, data) views[#views + 1] = { transform = snap(), allies = data.allies } end }, vg = {} }
        for team = 1, 3 do fixtureDrivers[team].activate = noop end
        local originalDraw = Card.draw
        Card.draw = function(vg, scope) draws[#draws + 1] = { vg = vg, scope = scope, transform = snap() } end
        local triEnv = environment({ ["ui.hud.popup.SettingsPanel"] = Settings, ["ui.fx.SpineCardEffect"] = Card }, triFields)
        local triDraw = assert(load("return function()\n" .. triCode .. "\nend", "@host-real/Tri.draw.content", "t", triEnv))()
        local drawBefore = #draws
        triDraw()
        check(#draws == drawBefore + 3 and #views == 3, "Tri draws exactly one scope per visible driver")
        for row = 1, 3 do
            local v, d = views[row].transform, draws[drawBefore + row]
            check(d.scope == "tri" .. row and d.transform.clip == v.clip and d.transform.depth == v.depth
                and near(d.transform.sx, v.sx) and near(d.transform.tx, v.tx) and near(d.transform.ty, v.ty),
                "Tri row " .. row .. " effect retains card transform/scissor")
            check(near(v.sx, 0.5) and near(v.ty, 30.8 + (row - 1) * 190), "Tri row " .. row .. " actual content fit")
        end
        check(#stack == 0 and matrix.sx == 1 and matrix.tx == 0, "Tri restores caller state")
        effectsEnabled = false
        drawBefore = #draws; triDraw()
        check(#draws == drawBefore, "Tri Settings off omits card effects")
        effectsEnabled = true; triEnv.unlocked = 1
        drawBefore = #draws; triDraw()
        check(#draws == drawBefore + 1 and draws[#draws].scope == "tri1", "locked rows never draw other scope")
        Card.draw = originalDraw

        -- Driver/Dungeon只抽取完整死亡拦截区域；ART/TAL为可控结果spy，不模拟复活规则。
        local reviveMode, artifactCalls, talentCalls, deathAnims, towerDeaths = "artifact", 0, 0, 0, 0
        local ART = { onAllyDeath = function(unit)
            artifactCalls = artifactCalls + 1
            if reviveMode == "artifact" then unit.hp = 7; return true end
            if reviveMode == "ghost" then return true end
            return false
        end }
        local TAL = { onAllyDeath = function(unit)
            talentCalls = talentCalls + 1
            if reviveMode == "talent" then unit.hp = 8; return true end
            return false
        end }
        local combatSpy = { getCardPos = function(list, index) return Layout.posForList(list, index) end,
            getCardCX = function(list, index) return Layout.posForList(list, index) end,
            syncUnitHp = noop, addFloatingText = noop,
            setCardAnim = function() deathAnims = deathAnims + 1 end }
        local removal = { removeUnit = noop }
        local reset = { compactFallen = noop }
        local deathMocks = { ["ui.fx.SpineCardEffect"] = Card, ["ui.battle.scene.BattleAllyReset"] = reset }
        local driverCode = segment("ui/battle/tri/BattleTriDriver.lua",
            "        -- 倒下的人先试瞬时拦截复活", "        -- 存活统计")
        local driverEnv = environment(deathMocks, { BattleLayout = Layout, BattleCombat = combatSpy,
            ART = ART, TAL = TAL, TM = removal, SEM = removal })
        local driverDeath = assert(load("return function(self, allies)\n" .. driverCode .. "\nend",
            "@host-real/Driver.tick.death", "t", driverEnv))()
        for _, mode in ipairs({ "artifact", "talent", "ghost", "none" }) do
            reviveMode = mode
            local list = { { heroId = 1, hp = 9 }, { heroId = 2, hp = 0, atkProgress = 0.5 } }
            before = #plays; artifactCalls, talentCalls, deathAnims = 0, 0, 0
            driverDeath({ teamIdx = 3, battleLab = false }, list)
            local successful = mode == "artifact" or mode == "talent"
            check(#plays == before + (successful and 1 or 0), "Driver visual only positive hp revive " .. mode)
            check(artifactCalls == 1 and talentCalls == ((mode == "artifact" or mode == "ghost") and 0 or 1),
                "Driver retains artifact-first calls " .. mode)
            if successful then
                stripSize(plays[#plays], "Driver " .. mode)
                check(plays[#plays].scope == "tri3" and near(plays[#plays].cx, Layout.STRIP_ALLY_X0 - Layout.STRIP_PITCH),
                    "Driver effect follows revived second unit")
                check(not list[2]._triDeathHandled and deathAnims == 0, "Driver revive never starts death branch")
            elseif mode == "none" then
                check(list[2]._triDeathHandled and list[2]._fallenPending and deathAnims == 1,
                    "Driver failed revive retains original death processing")
            else
                check(list[2].hp == 0 and not list[2]._triDeathHandled and deathAnims == 0,
                    "Driver ghost interception remains business success without false revive visual")
            end
        end
        local dungeonCode = segment("ui/dungeon/DungeonBattleScene.lua",
            "    local function notifyTowerAllyDeath(unit)", "    -- [阵亡紧凑] 退场完成 → 移队尾")
        local dungeonEnv = environment(deathMocks, { BattleLayout = Layout, BattleCombat = combatSpy,
            SpineCardEffect = Card, ART = ART, TAL = TAL, TM = removal, SEM = removal,
            getCardCX = combatSpy.getCardCX, syncUnitHp = noop, isTowerMode = true,
            DungeonBattle = { onAllyDeath = function() towerDeaths = towerDeaths + 1 end } })
        local dungeonDeath = assert(load("return function(state)\n" .. dungeonCode .. "\nend",
            "@host-real/Dungeon.update.death", "t", dungeonEnv))()
        for _, mode in ipairs({ "artifact", "talent", "ghost", "none" }) do
            reviveMode = mode
            local unit = { heroId = 1, hp = 0, atkProgress = 0.5 }
            before = #plays; towerDeaths = 0
            dungeonDeath({ allies = { unit } })
            local successful = mode == "artifact" or mode == "talent"
            check(#plays == before + (successful and 1 or 0) and towerDeaths == 1,
                "Dungeon original tower death before guarded visual " .. mode)
            if successful then
                stripSize(plays[#plays], "Dungeon " .. mode)
                check(plays[#plays].scope == "dungeon", "Dungeon scope isolated")
            end
            before = #plays; dungeonDeath({ allies = { unit } })
            check(#plays == before and towerDeaths == 1, "Dungeon death handled once " .. mode)
        end

        -- 完整真实BattleCasualty.process，不抽helper；活敌人避免奖励/胜利出口。
        local casualtyTAL = { onAllyDeath = TAL.onAllyDeath, resetEnemyDeath = noop, onEnemyDeath = noop }
        local Casualty = compile("ui/battle/combat/BattleCasualty.lua", {
            ["systems.ArtifactRuntime"] = ART, ["systems.TalentManager"] = casualtyTAL,
            ["systems.ThreatManager"] = removal, ["systems.StatusEffectManager"] = removal,
            ["ui.battle.combat.BattleCombat"] = combatSpy, ["ui.fx.SpineCardEffect"] = Card,
            ["ui.battle.scene.BattleAllyReset"] = reset,
            ["ui.widget.SpeechBubble"] = { trigger = noop }, ["ui.battle.stage.StageBerserk"] = { exit = noop } })
        local function living(list)
            local result = {}; for _, unit in ipairs(list) do if unit.hp > 0 then result[#result + 1] = unit end end
            return result
        end
        for _, mode in ipairs({ "artifact", "talent", "ghost", "none" }) do
            reviveMode = mode
            local list, enemies = { { heroId = 1, hp = 0 } }, { { monsterId = 1, hp = 9 } }
            local ctx = { allies = list, enemies = enemies, enemyQueue = {}, getCardCX = combatSpy.getCardCX,
                getAliveUnits = living, syncUnitHp = noop, reinforceCdByList = {}, RESPAWN_DELAY = 1,
                ALLY_CARD_CY = 1760, ENEMY_CARD_CY = 804, currentStageId = 101,
                getStageConfig = function() return { isTerminalTemple = function() return false end } end,
                settleWaveEfficiency = noop, resetWaveTimers = noop }
            before = #plays
            Casualty.process(ctx, 0)
            local successful = mode == "artifact" or mode == "talent"
            check(#plays == before + (successful and 1 or 0), "real Casualty positive hp guard " .. mode)
            if successful then stripSize(plays[#plays], "Casualty " .. mode)
                check(plays[#plays].scope == "battle", "Casualty default battle scope") end
        end

        -- 真实CharacterDetailDraw公开API+真实draw入口取消，不进入GPU正文。
        -- 若执行越过取消区域，首次nvgBeginPath用哨兵中断，明确不冒称完整像素绘制。
        ---@type table<string, any>
        local detailState = { open = true, closing = false, heroId = 1, tab = "class", openTime = 90, closeTime = 90,
            cardDragVisual = 0, attrScrollVel = 0, attrDragging = false, attrScrollY = 0 }
        local Draw = compile("ui/character/detail/CharacterDetailDraw.lua", {
            ["ui.fx.SpineCardEffect"] = Card, ["ui.hud.popup.SettingsPanel"] = Settings },
            { nvgBeginPath = function() error("HOST_PROLOGUE_END") end, H_SEAM_BACK = true })
        Draw.setContext({ detailState = detailState, getOwnedData = function() return { level = 10 } end })
        before = #plays
        check(Draw.playJobChangeForHero(1) == true and #plays == before + 1, "real Draw stable matching class card plays job")
        local job = plays[#plays]
        check(job.scope == "detail-class" and near(job.cx, 540) and near(job.cy, 544)
            and near(job.width, Layout.CARD_W * 1.18) and near(job.height, Layout.CARD_H * 1.18),
            "job uses actual center card geometry in detail design space")
        for _, case in ipairs({ { key = "open", value = false }, { key = "closing", value = true },
            { key = "heroId", value = 2 }, { key = "tab", value = "attr" },
            { key = "switchDir", value = 1 }, { key = "cardDragVisual", value = 0.2 },
            { key = "openTime", value = 99.9 } }) do
            local saved = detailState[case.key]; detailState[case.key] = case.value
            before = #plays
            check(Draw.playJobChangeForHero(1) == false and #plays == before, "job rejects " .. case.key)
            detailState[case.key] = saved
        end
        before = #plays; effectsEnabled = false
        check(Draw.playJobChangeForHero(1) == false and #plays == before, "job rejects Settings off")
        effectsEnabled = true
        check(Draw.playJobChangeForHero("1") == false and Draw.playJobChangeForHero(nil) == false,
            "job rejects nonnumeric hero identity without coercion")
        for _, case in ipairs({ { key = "open", value = false }, { key = "closing", value = true },
            { key = "heroId", value = 2 }, { key = "tab", value = "attr" },
            { key = "switchDir", value = 1 }, { key = "cardDragVisual", value = 0.2 },
            { key = "openTime", value = 89 } }) do
            detailState.open, detailState.closing, detailState.heroId, detailState.tab = true, false, 1, "class"
            detailState.switchDir, detailState.cardDragVisual, detailState.openTime = nil, 0, 90
            assert(Draw.playJobChangeForHero(1))
            detailState[case.key] = case.value
            local cancelBefore = #cancels
            local drawOk, drawErr = pcall(Draw.draw, {})
            check(drawOk or tostring(drawErr):find("HOST_PROLOGUE_END", 1, true), "real Draw prologue reaches deterministic boundary " .. case.key)
            check(#cancels == cancelBefore + 1 and cancels[#cancels] == "detail-class",
                "playback canceled on " .. case.key)
        end

        -- 精确执行真实class尾层draw，确认与旧礼拜堂scope严格分离且开关生效。
        local classDrawCode = segment("ui/character/detail/CharacterDetailDraw.lua",
            "    -- === 转职确认/重置弹窗、飘字与程序化转职特效", "    -- === 装备背包覆盖层 ===")
        detailState.tab = "class"
        local classVG = {}
        local classEnv = environment({ ["ui.fx.SpineCardEffect"] = Card,
            ["ui.hud.popup.SettingsPanel"] = Settings,
            ["ui.church.ChurchClassChange"] = { drawConfirmPopup = noop,
                drawResetConfirmPopup = noop, drawFloatText = noop } }, { detailState = detailState, vg = classVG })
        local classDraw = assert(load("return function()\n" .. classDrawCode .. "\nend",
            "@host-real/Detail.class.tail", "t", classEnv))()
        drawBefore = #draws; classDraw()
        check(#draws == drawBefore + 1 and draws[#draws].scope == "detail-class" and draws[#draws].vg == classVG,
            "real detail class tail only draws isolated detail-class scope")
        effectsEnabled = false; drawBefore = #draws; classDraw()
        check(#draws == drawBefore, "real detail class tail respects effects setting")
        effectsEnabled = true

        -- 完整真实ChurchResults回执，成功/当前英雄/open门控接到上述真实Draw方法。
        detailState.open, detailState.closing, detailState.heroId, detailState.tab = true, false, 1, "class"
        detailState.switchDir, detailState.cardDragVisual, detailState.openTime = nil, 0, 90
        local protocol = nativeRequire("shared.Protocol")
        local matching, detailOpen, branchCalls, clearCalls = 1, true, 0, 0
        local Results = compile("ui/church/ChurchResults.lua", {
            ["ui.character.detail.CharacterDetail"] = { getHeroId = function() return matching end,
                isOpen = function() return detailOpen end, markPowerDirty = noop },
            ["ui.character.detail.CharacterDetailDraw"] = Draw,
            ["ui.church.ChurchClassChange"] = { showFloat = noop },
            ["ui.hud.BottomNav"] = { refreshTownBadge = noop } })
        local receipt = Results.bind({ state = { open = false }, getProtocol = function() return protocol end,
            CharacterPanel = { setHeroAdvBranch = function() branchCalls = branchCalls + 1 end, resetHeroAdvBranch = noop },
            ArtifactPanel = {}, ArtifactDrawPanel = {}, clearPowerCache = function() clearCalls = clearCalls + 1 end })
        local function result(success)
            receipt.onActionResult({ success = success, action = protocol.ACTION_TYPES.ADVANCE_CLASS,
                heroId = 1, branchId = 101, advLevel = 1, branchName = "fixture" })
        end
        before = #plays; result(true)
        check(#plays == before + 1 and branchCalls == 1 and clearCalls == 1, "real successful Church receipt uses real Draw API and retains rules refresh")
        before = #plays; result(false)
        check(#plays == before, "failed Church receipt never plays job")
        matching = 2; before = #plays; result(true)
        check(#plays == before, "late Church receipt wrong current hero never plays")
        matching, detailOpen = 1, false; before = #plays; result(true)
        check(#plays == before, "closed Church detail never plays")
        detailOpen, detailState.tab = true, "attr"; before = #plays; result(true)
        check(#plays == before, "Church matched open nonclass detail rejected by real Draw")
        -- 完整真实BlacksmithDraw.bind/draw，工作台尺寸来自BlacksmithPage实际常量段。
        local workbenchCode = segment("ui/blacksmith/BlacksmithPage.lua",
            "local WORKBENCH_CX, WORKBENCH_CY =", "-- 7. 下方背景板")
        local geometry = assert(load(workbenchCode .. "\nreturn BlacksmithPage.WORKBENCH",
            "@host-real/Blacksmith.WORKBENCH", "t", { BlacksmithPage = {} }))()
        local resultPlaying, resultDraws, workbenchDraws = true, {}, 0
        local Result = { isPlaying = function() return resultPlaying end,
            draw = function(vg, cx, cy, size) resultDraws[#resultDraws + 1] = { vg = vg, cx = cx, cy = cy, size = size } end }
        local SmithDraw = compile("ui/blacksmith/BlacksmithDraw.lua", {}, {
            nvgBeginPath = noop, nvgRect = noop, nvgFillColor = noop, nvgFill = noop,
            nvgRGBA = function() return {} end, nvgSave = noop, nvgRestore = noop,
            nvgIntersectScissor = noop, nvgResetScissor = noop })
        local smithState = { open = true, closing = false, openTime = 90,
            tab = "xilian", tabFrom = "xilian", tabSwitchTime = 90 }
        local smithDeps = { state = smithState, ANIM_DURATION = 0.45, CLOSE_ANIM_DURATION = 0.38,
            DESIGN_W = 1080, DESIGN_H = 2400, LOWER_BG_CY = 1565, LOWER_BG_H = 1670,
            TAB_BG_CY = 2308, TAB_BG_H = 143, TAB_ANIM_DURATION = 0.2, TAB_MAP = { xilian = 2 },
            BlacksmithPage = { WORKBENCH = geometry }, SpineResultEffect = Result,
            WORKBENCH_CX = geometry.cx, WORKBENCH_CY = geometry.cy,
            DrawUtil = { drawImageCentered = noop }, I18n = { t = function(key) return key end },
            TownPageChrome = { drawNamePlate = noop, drawTabBar = noop },
            drawWorkbenchSlot = function() workbenchDraws = workbenchDraws + 1 end,
            drawTabContent = noop, easeInOutCubic = function(value) return value end }
        local smith = SmithDraw.bind(smithDeps)
        local smithVG = {}
        smith.drawPageImpl(smithVG)
        check(#resultDraws == 1 and workbenchDraws == 1, "real Blacksmith draw layers one result over actual workbench")
        check(resultDraws[1].vg == smithVG and resultDraws[1].cx == 562 and resultDraws[1].cy == 479
            and resultDraws[1].size == 220, "real Blacksmith result uses actual 562/479 center and 220 size")
        resultPlaying = false; smith.drawPageImpl(smithVG)
        check(#resultDraws == 1, "Blacksmith idle result does not draw")
        smithState.open = false; resultPlaying = true; smith.drawPageImpl(smithVG)
        check(#resultDraws == 1, "Blacksmith closed page does not draw")

        check(sources["ui/battle/tri/BattleTriDriver.lua"] and sources["ui/dungeon/DungeonBattleScene.lua"]
            and sources["ui/battle/combat/BattleCasualty.lua"] and sources["ui/church/ChurchResults.lua"],
            "all seven host production sources actually loaded")
    end)
    if not ok then failures = failures + 1; print(TAG .. " HARNESS_ERROR " .. tostring(err)) end
    print(string.format("%s RESULT %d checks, %d failures %s", TAG, checks, failures, failures == 0 and "ALL PASS" or "FAILED"))
    if engine then engine:Exit() end
end
