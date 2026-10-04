-- T06/T07/T09 三队展示专项：真实 HC/装备/神器/面板/属性/资料 draw，UI 与存档仅内存替身。
-- Runtime: .cli/UrhoXRuntime tests/team_attribute_display_test.lua -tapcode_dir=/workspace
--          -tool_mode -graphicsheadless -nosound
-- 保留全部既有测试；断言失败逐项打印并汇总，Start 最终 engine:Exit()。
local failures, assertions = {}, 0
local function check(ok, message)
    assertions = assertions + 1
    if ok then print("[PASS] " .. message)
    else failures[#failures + 1] = message; print("[FAIL] " .. message) end
end
local function close(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.000001
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function row(data, key)
    for _, column in ipairs({ data.left, data.right }) do
        for _, entry in ipairs(column) do if entry.key == key then return entry end end
    end
    return nil
end
local function noop() end

function Start()
    print("[team_attribute_display_test] START")
    local originalRequire = require
    local savedGlobals, savedModules = {}, {}
    local restorers = {}
    local function replaceGlobal(key, value)
        savedGlobals[key] = { value = rawget(_G, key) }
        _G[key] = value
    end
    local function replaceField(object, key, value)
        local old = object[key]
        restorers[#restorers + 1] = function() object[key] = old end
        object[key] = value
    end
    local ok, err = pcall(function()
        local AD = originalRequire("systems.AttributeDef")
        local HC = originalRequire("config.HeroConfig")
        local Awakening = originalRequire("config.AwakeningConfig")
        local TE = originalRequire("systems.TalentEffect")
        local CPE = originalRequire("systems.CombatPowerEstimate")
        local Dispatcher = originalRequire("runtime.ClientDispatcher")
        local Store = originalRequire("core.PlayerStore")
        local GameState = originalRequire("core.GameState")
        local savedLit = HC._getSavedLitNodes()
        restorers[#restorers + 1] = function() HC.setDefaultLitNodes(savedLit) end
        local state = {
            heroes = { roster = {}, deployed = {}, teams = {} },
            equipment = { inventory = {}, equipped = {} },
            artifacts = { bag = {}, equippedByTeam = { {}, {}, {} } },
            talents = { litNodes = {} },
            battle = { maxStageId = 1905, currentStageId = 101,
                clearedStages = { ["905"] = true, ["1905"] = true } },
        }
        replaceField(Dispatcher, "get", function(key) return state[key] end)
        replaceField(Dispatcher, "subscribe", noop)
        replaceField(Store, "Get", function(key) return state[key] end)
        replaceField(Store, "Subscribe", noop)
        replaceField(GameState, "getLevel", function() return 70 end)
        local gamePower = 0
        replaceField(GameState, "setPower", function(value) gamePower = value end)
        local drawContext, cardContext = {}, {}
        local invalidations, teamChanges, dirtyCount = 0, 0, 0
        local captured = {}
        local function record(_, x, y, text)
            captured[#captured + 1] = { x = x, y = y, text = text }
        end
        local detailMock = { init = noop, setContext = function(ctx) cardContext = ctx end,
            markPowerDirty = function() dirtyCount = dirtyCount + 1 end,
            isOpen = function() return false end, hasAnyUpgradeForHero = function() return false end,
            hasAwakeningUpgrade = function() return false end }
        local drawMock = { MAX_SLOTS = 4, MAX_PER_ROW = 5, ROW1_CY = 1186, ROW_SPACING = 238,
            SCROLL_BOTTOM = 2256, ROSTER_BOTTOM_DY = 144,
            setContext = function(ctx) drawContext = ctx end, initImages = noop,
            getSharedImages = function() return {} end }
        local closed = { isOpen = function() return false end, draw = noop, init = noop,
            update = noop, drawEmbedded = noop }
        local mocks = {
            ["ui.character.detail.CharacterDetail"] = detailMock,
            ["ui.character.panel.CharacterPanelDraw2"] = drawMock,
            ["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop },
            ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
            ["ui.battle.tri.BattleTriPage"] = { invalidateTeams = function() invalidations = invalidations + 1 end },
            ["ui.hud.popup.OfflineRewardPanel"] = closed,
            ["core.DrawUtil"] = { drawTextStroke = record, drawImageCentered = noop,
                drawNineSlice = noop, easeOutBack = function(v) return v end },
            ["core.DarkIcon"] = { drawNine = noop },
            ["ui.widget.HeroFrame"] = { draw = noop },
            ["systems.ButtonFeedback"] = { begin = noop, finish = noop },
            ["ui.character.hero.AvatarSelectPanel"] = closed,
            ["ui.hud.popup.SettingsPanel"] = closed,
            ["ui.dev.GMConsolePanel"] = closed,
            ["ui.hud.TopBar"] = {},
            ["runtime.GameAction"] = { isGM = function() return false end },
        }
        -- 屏蔽绘制/战斗宿主，而非替换待测属性和经济公式；退出前原样恢复。
        for name in pairs(mocks) do savedModules[name] = { value = package.loaded[name] } end
        for _, name in ipairs({ "ui.character.panel.CharacterPanel", "ui.character.detail.CharacterDetailAttrs",
            "ui.character.detail.EquipmentPreview", "ui.hud.popup.PlayerInfoPanel" }) do
            savedModules[name] = { value = package.loaded[name] }
            package.loaded[name] = nil
        end
        replaceGlobal("require", function(name) return mocks[name] or originalRequire(name) end)
        for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgTranslate", "nvgScale", "nvgFontFace",
            "nvgFontSize", "nvgTextAlign", "nvgFillColor", "nvgBeginPath", "nvgRoundedRect", "nvgFill" }) do
            replaceGlobal(name, noop)
        end
        replaceGlobal("nvgRGBA", function() return 0 end)
        replaceGlobal("nvgTextBounds", function(_, _, _, text) return (utf8.len(text) or #text) * 10 end)
        replaceGlobal("nvgText", record)
        local CP = require("ui.character.panel.CharacterPanel")
        CP.init(nil)
        CP.setOnTeamChanged(function() teamChanges = teamChanges + 1 end)
        local Attrs = require("ui.character.detail.CharacterDetailAttrs")
        local Preview = require("ui.character.detail.EquipmentPreview")
        local PIP = require("ui.hud.popup.PlayerInfoPanel")
        PIP.open() -- 不调用 init/update/close，避免图片或游玩时间落档。

        local skip = { [AD.STR] = true, [AD.AGI] = true, [AD.INT] = true,
            [AD.VIT] = true, [AD.LUK] = true, [AD.SPI] = true, [AD.HP] = true,
            [AD.ATK_INTERVAL] = true, [AD.PHYS_RES] = true, [AD.MAG_RES] = true }
        -- 独立真值：直接读取正式 getDeployedTeam 的真实属性，按原 valueModel 计价。
        local function officialPower(unit)
            local total = 0
            for key, meta in pairs(AD.META) do
                if not skip[key] and meta.valueModel and meta.valueModel > 0 then
                    local divisor = meta.dataType == AD.TYPE_PCT and 100 or 1
                    total = total + unit.attrs:get(key) * meta.valueModel / divisor
                end
            end
            return math.floor(total + Awakening.calcTotalCombatPower(unit.heroId, unit.awakeningNodes)
                + (unit.attrs.artifactPowerBonus or 0) + 0.5)
        end
        local function officialEstimate(unit)
            local base = CPE.estimate(unit.attrs, unit.attrs.atkType)
            return math.floor(base + Awakening.calcTotalCombatPower(unit.heroId, unit.awakeningNodes)
                + (unit.attrs.artifactPowerBonus or 0) + 0.5)
        end
        local function fixture(layouts, lit)
            state.heroes = { roster = {}, deployed = copy(layouts[1]), teams = {} }
            state.equipment = { inventory = {}, equipped = {} }
            state.artifacts = { bag = {}, equippedByTeam = { {}, {}, {} } }
            state.talents = { litNodes = lit or {} }
            for id = 1, 25 do
                state.heroes.roster[id] = { level = 70, exp = 0, maxExp = 100,
                    awakening = {}, extraTalent = {} }
            end
            for t = 1, 3 do state.heroes.teams[t] = { slots = copy(layouts[t]) } end
        end
        local function apply() CP.setHeroesData(state.heroes); CP.refreshPower() end
        local function rosterPower(heroId)
            for i, entry in ipairs(drawContext.getHeroRoster()) do
                if entry.heroId == heroId then return drawContext.getRosterPowerCache()[i] end
            end
            return nil
        end
        local function artifact(t, slot, id, value, subSlot)
            local instance = "T" .. t .. "S" .. slot .. "A" .. id
            state.artifacts.bag[#state.artifacts.bag + 1] = { id = instance, artifactId = id, value = value }
            local rowData = state.artifacts.equippedByTeam[t][slot] or {}
            rowData[subSlot or 1] = instance
            state.artifacts.equippedByTeam[t][slot] = rowData
        end
        local function captureProfile()
            captured = {}
            PIP.draw(nil)
            local displayed, label = nil, false
            local teamIdx = CP.getActiveTeamIdx()
            for _, entry in ipairs(captured) do
                if entry.y == 560 then
                    local text = tostring(entry.text)
                    local prefix = require("core.I18n").format("【小队%d】%s", teamIdx, "")
                    if text:sub(1, #prefix) == prefix then
                        label = true
                        displayed = tonumber(text:sub(#prefix + 1))
                    elseif tonumber(text) then
                        displayed = tonumber(text)
                    end
                end
            end
            return displayed, label
        end

        -- T06：3个真实所属队 × 3个编辑队；特意使用槽2/3/4而非全部槽1。
        fixture({ { 0, 1, 0, 0 }, { 0, 0, 2, 0 }, { 0, 0, 0, 9 } })
        for t = 1, 3 do
            for slot = 1, 4 do artifact(t, slot, 14, t * 5 + slot) end
        end
        artifact(1, 2, 9, 50, 2)
        artifact(2, 2, 8, 12, 2) -- 相邻槽3魔攻；不得因压缩空槽而丢失。
        artifact(3, 4, 12, 220, 2)
        apply()
        local expected, estimates, units = {}, {}, {}
        local heroIds = { 1, 2, 9 }
        for t = 1, 3 do
            local unit = CP.getDeployedTeam(t)[1]
            units[t], expected[t], estimates[t] = unit, officialPower(unit), officialEstimate(unit)
        end
        local resetsBefore, changesBefore = invalidations, teamChanges
        for active = 1, 3 do
            check(CP.setActiveTeam(active), "T06编辑队切换" .. active .. "成功")
            for realTeam, heroId in ipairs(heroIds) do
                local tag = "T06 real=" .. realTeam .. " edit=" .. active .. " hero=" .. heroId
                check(cardContext.calcHeroPower(heroId) == expected[realTeam], tag .. " 卡面战力=正式属性真值")
                check(cardContext.calcHeroEstimate(heroId) == estimates[realTeam], tag .. " 预估同源且不借编辑队")
                check(rosterPower(heroId) == expected[realTeam], tag .. " 名册缓存=正式属性真值")
                local details = Attrs.collectAttributes(heroId, HC.get(heroId), 70)
                local same = true
                for key in pairs(AD.META) do
                    if key ~= AD.HP and not close(details.attrs:get(key), units[realTeam].attrs:get(key)) then same = false end
                end
                check(same and details.attrs.artifactPowerBonus == units[realTeam].attrs.artifactPowerBonus,
                    tag .. " 普通属性页神器/相邻槽与正式构造一致")
            end
            local bench = HC.createHero(3, 70, nil, {}, {})
            check(cardContext.calcHeroPower(3) == officialPower(bench)
                and rosterPower(3) == officialPower(bench), "T06 edit=" .. active .. " 未上阵英雄不借任何队神器")
        end
        check(invalidations == resetsBefore and teamChanges == changesBefore,
            "T06查看/切编辑队不重置任何真实战斗或提交编队")

        -- T07：每队分别放 hero20，普通入口不传 options；实际战斗共鸣为独立真值。
        local Melissa = require("systems.talents.TalentMelissa").bind({ AD = AD,
            hasAwaken = function(unit, index) return Awakening.hasNode(unit.awakeningNodes, index) end })
        for targetTeam = 1, 3 do
            for _, awakened7 in ipairs({ false, true }) do
                local layouts = { { 2, 0, 0, 0 }, { 4, 0, 0, 0 }, { 1, 0, 0, 0 } }
                layouts[targetTeam][3] = 20
                fixture(layouts)
                state.heroes.roster[20].awakening = awakened7 and { [7] = true } or {}
                for _, id in ipairs({ 1, 2, 4 }) do
                    state.equipment.inventory[tostring(id)] = { templateId = "C1", quality = 1, level = 1,
                        baseStats = { { AD.MAG_DMG_BONUS, id * 7 }, { AD.MAG_PEN, id * 3 } }, affixes = {} }
                    state.equipment.equipped[tostring(id)] = { accessory = id }
                end
                apply()
                local team, melissa = CP.getDeployedTeam(targetTeam), nil
                for _, unit in ipairs(team) do if unit.heroId == 20 then melissa = unit end end
                local resonance = Melissa.calcMelissaTeamResonance(melissa, team)
                for active = 1, 3 do
                    CP.setActiveTeam(active)
                    local plain = Attrs.collectAttributes(20, HC.get(20), 70)
                    local current = Preview.build(20, 70).current
                    local isolated = Attrs.collectAttributes(20, HC.get(20), 70, copy(state))
                    local tag = "T07 real=" .. targetTeam .. " edit=" .. active .. " awaken7=" .. tostring(awakened7)
                    check(close(row(plain, "_melissaStarGateResonance").numericValue, resonance.independentMult)
                        and close(row(plain, "_melissaStarGatePen").numericValue, resonance.magPen),
                        tag .. " 无options星门=本队战斗共鸣")
                    check(close(row(current, "_melissaStarGateResonance").numericValue, resonance.independentMult)
                        and close(row(isolated, "_melissaStarGatePen").numericValue, resonance.magPen),
                        tag .. " 无候选配装/显式快照仍同真实队")
                end
            end
        end
        -- 英雄已移出所有队，旧 deployed 镜像故意脏：显式teams完整时不得恢复旧队身份。
        fixture({ { 2, 0, 0, 0 }, { 4, 0, 0, 0 }, { 1, 0, 0, 0 } })
        state.heroes.deployed = { 20, 2, 0, 0 }
        state.equipment.inventory["2"] = { templateId = "C1", quality = 1, level = 1,
            baseStats = { { AD.MAG_DMG_BONUS, 40 }, { AD.MAG_PEN, 20 } }, affixes = {} }
        state.equipment.equipped["2"] = { accessory = 2 }
        -- 面板队一仍遵循现有deployed兼容语义；该项只验显式快照来源的归属契约。
        local absent = Attrs.collectAttributes(20, HC.get(20), 70, copy(state))
        check(row(absent, "_melissaStarGateResonance").numericValue == 1
            and row(absent, "_melissaStarGatePen").numericValue == 0,
            "T07完整teams中未上阵hero20不从脏deployed/队外魔法角色继承")

        -- T09：3队 × 0..4 人 × 有/无 runtime 天赋 × 所有编辑队，显式队号不能被active覆盖。
        check(TE.calcRuntimeOnlyPower({ 125 }) == 15, "T09真实runtime节点125每英雄固定战力15")
        for targetTeam = 1, 3 do
            for count = 0, 4 do
                for _, lit in ipairs({ {}, { 125 } }) do
                    local layouts = { { 1, 2, 3, 0 }, { 4, 5, 0, 0 }, { 6, 0, 0, 0 } }
                    layouts[targetTeam] = { 0, 0, 0, 0 }
                    for slot = 1, count do layouts[targetTeam][slot] = 9 + slot end
                    fixture(layouts, lit)
                    apply()
                    local total = TE.calcRuntimeOnlyPower(lit) * count
                    for _, unit in ipairs(CP.getDeployedTeam(targetTeam)) do total = total + officialPower(unit) end
                    local tag = "T09 team=" .. targetTeam .. " count=" .. count .. " runtime=" .. #lit
                    for active = 1, 3 do
                        CP.setActiveTeam(active)
                        check(CP.getTotalPower(targetTeam) == total, tag .. " edit=" .. active .. " 显式总战力只按目标队人数")
                    end
                    CP.setActiveTeam(targetTeam)
                    local displayed, labeled = captureProfile()
                    check(CP.getTotalPower() == total and displayed == total, tag .. " 资料保留当前编辑队且数值真实")
                    check(labeled, tag .. " 资料明确显示当前队伍编号")
                    local mainTotal = TE.calcRuntimeOnlyPower(lit) * #CP.getDeployedTeam(1)
                    for _, unit in ipairs(CP.getDeployedTeam(1)) do mainTotal = mainTotal + officialPower(unit) end
                    check(gamePower == mainTotal, tag .. " GameState/顶栏原队一口径未改")
                end
            end
        end
        -- 统一归属查询的独立边界：字符串队/槽键、0/空槽、旧档和脏兼容镜像。
        local find = CP.findHeroDeployment
        check(type(find) == "function", "统一英雄真实队/槽查询已公开")
        if find then
            local lookup = { teams = { ["1"] = { slots = {} },
                ["2"] = { slots = { ["1"] = 0, ["4"] = "20" } },
                ["3"] = { slots = { [2] = { state = "occupied", heroId = 9 } } } },
                deployed = { 20, 9 } }
            local slot, team = find("20", lookup)
            check(slot == 4 and team == 2, "归属字符串键保留真实空槽位置，不借脏deployed")
            slot, team = find(9, lookup)
            check(slot == 2 and team == 3, "归属查询兼容真实面板槽对象")
            slot, team = find(3, lookup)
            check(slot == nil and team == nil, "已拥有但未上阵查询返回nil,nil")
            slot, team = find(20, { deployed = { 0, 20, 0, 0 } })
            check(slot == 2 and team == 1, "旧档没有teams仍支持队一deployed真实位置")
            slot, team = find(0, lookup)
            check(slot == nil and team == nil, "0空槽不是有效英雄")
        end

        -- 五语资料真实draw仍明确当前队号，复用现有译文，数值与队伍语义不变。
        local I18n = require("core.I18n")
        local oldLanguage = I18n.get()
        restorers[#restorers + 1] = function() I18n.set(oldLanguage) end
        for _, language in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
            I18n.set(language)
            for teamIdx = 1, 3 do
                CP.setActiveTeam(teamIdx)
                local displayed, labeled = captureProfile()
                check(labeled and displayed == CP.getTotalPower(teamIdx),
                    "资料" .. language .. "明确当前小队" .. teamIdx .. "且战力同源")
            end
        end
        I18n.set(oldLanguage)
        check(dirtyCount > 0, "刷新继续通知详情卡面缓存脏标记")
        -- 显式来源不得回读真实存档，不允许构建过程中写原数据。
        local before = copy(state)
        local getBefore, storeBefore = Dispatcher.get, Store.Get
        Dispatcher.get = function() error("显式options不得回读Dispatcher") end
        Store.Get = function() error("显式options不得回读PlayerStore") end
        local isolatedOk, isolatedErr = pcall(function()
            Attrs.collectAttributes(20, HC.get(20), 70, copy(before))
        end)
        Dispatcher.get, Store.Get = getBefore, storeBefore
        check(isolatedOk and equal(state, before), "显式快照隔离真档且不水合原数据 " .. tostring(isolatedErr or ""))
    end)
    if not ok then check(false, "HARNESS_EXCEPTION " .. tostring(err)) end
    for i = #restorers, 1, -1 do restorers[i]() end
    for name, old in pairs(savedModules) do package.loaded[name] = old.value end
    for name, old in pairs(savedGlobals) do _G[name] = old.value end
    if #failures == 0 then
        print("[team_attribute_display_test] ALL PASS assertions=" .. assertions)
    else
        print("[team_attribute_display_test] FAILURES=" .. #failures .. " assertions=" .. assertions)
        for i, message in ipairs(failures) do print("[failure " .. i .. "] " .. message) end
    end
    engine:Exit()
end
