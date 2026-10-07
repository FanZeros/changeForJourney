-- 经验刷新热点专项：真实 Panel/Progress/Power/EquipmentPower/共鸣源码隔离加载。
-- 不加载 main/真实 PlayerStore/PDM，不访问玩家档，不修改全局 require/File。
-- -exp-refresh-baseline 在冻结旧源码树记录旧次数；玩法、字段patch与通知断言保持相同。
-- -exp-refresh-no-persist 删除 bind 的持久化出口，仍须识别全名册共鸣等级变化。
local TAG = "[startup_exp_refresh_test]"
local assertions, failures = 0, 0
local baseline, noPersist = false, false
for _, argument in ipairs(GetArguments()) do
    if argument == "-exp-refresh-baseline" then baseline = true end
    if argument == "-exp-refresh-no-persist" then noPersist = true end
end
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1 end
    print(TAG .. (value and " PASS " or " FAIL ") .. label)
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function noop() end

local function fixture()
    local counts = { rebuild = 0, refresh = 0, nav = 0, light = 0, slots = 0,
        context = 0, createHero = 0, rosterSort = 0, rawSort = 0, persist = 0, powerInvalidations = 0 }
    local modules, loaded, loading, allowedPaths = {}, {}, {}, {}
    local patches, events, progress, layouts = {}, {}, {}, {}
    local subscriptions = {}
    local gamePower = 0
    local networkMode = false
    ---@type table
    local panel
    ---@type table
    local drawContext
    ---@type table
    local detailContext
    local mocks = {
        ["runtime.ClientDispatcher"] = {
            get = function(key) return modules[key] end,
            subscribe = function(key, callback)
                subscriptions[key] = subscriptions[key] or {}
                subscriptions[key][#subscriptions[key] + 1] = callback
            end,
        },
        ["core.PlayerStore"] = { Get = function() return nil end, Subscribe = noop },
        ["core.GameState"] = {
            getLevel = function() return 100 end,
            setPower = function(value) gamePower = value end,
        },
        ["ui.character.detail.CharacterDetail"] = {
            init = noop, markPowerDirty = noop,
            setContext = function(value) detailContext = value end,
            hasAnyUpgradeForHero = function() return false end,
            hasAwakeningUpgrade = function() return false end,
        },
        ["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop },
        ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
        ["ui.character.panel.CharacterPanelDraw2"] = {
            MAX_SLOTS = 4, MAX_PER_ROW = 5, CARD_W = 198, CARD_H = 351,
            CARD_SPACING = 205, CARD_CY = 300, ROW1_CY = 600, ROW_SPACING = 200,
            NAME_BG_DY = 100, NAME_BG_H = 40, SCROLL_TOP = 450, SCROLL_BOTTOM = 2200,
            SCROLL_LEFT = 0, SCROLL_RIGHT = 1080, DESIGN_W = 1080, ROSTER_BOTTOM_DY = 130,
            getSlotCX = function(index) return index * 205 end,
            setContext = function(value) drawContext = value end,
            initImages = noop, getSharedImages = function() return {} end,
        },
        ["ui.character.panel.CharacterDeploy"] = { bind = function() return {} end },
        ["ui.character.panel.CharacterInput"] = { bind = function() return {} end },
        ["ui.church.talent.TalentStarMap"] = {},
        ["ui.battle.tri.BattleTriPage"] = {
            invalidateTeams = function(selected) layouts[#layouts + 1] = copy(selected) end,
            refreshHeroProgressTeams = function(selected, classes)
                progress[#progress + 1] = { teams = copy(selected), classes = copy(classes) }
            end,
        },
        ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end },
    }
    local realNames = {
        ["ui.character.panel.CharacterPanel"] = true,
        ["ui.character.panel.CharacterProgress"] = true,
        ["ui.character.panel.CharacterHeroSync"] = true,
        ["ui.character.panel.CharacterRosterSort"] = true,
        ["ui.character.panel.CharacterPower"] = true,
        ["core.EventBus"] = true, ["core.BattleLayout"] = true, ["core.NumberUtil"] = true,
        ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true,
        ["systems.EquipmentSystem"] = true, ["systems.EquipmentSetSystem"] = true,
        ["systems.EquipmentSetRuntime"] = true, ["systems.EquipmentPower"] = true,
        ["systems.CombatPower"] = true, ["systems.CombatFormula"] = true,
        ["systems.TalentEffect"] = true, ["systems.AwakeningGrowth"] = true,
        ["systems.CombatPowerEstimate"] = true, ["systems.ArtifactBridge"] = true,
        ["systems.ArtifactRuntime"] = true, ["systems.ExtraTalentSystem"] = true,
        ["systems.StatusEffectManager"] = true, ["systems.LootBoxSystem"] = true,
        ["systems.BattleDiag"] = true, ["systems.ThreatManager"] = true,
        ["systems.ClassGateRuntime"] = true, ["systems.MapAffixSystem"] = true,
    }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.File = function() error("禁止访问真实玩家档") end
    env.IsNetworkMode = function() return networkMode end
    -- 新排序入口先检查已排序视图，正确顺序不再强制table.sort；旧baseline仍用原底层计数。
    -- 新版精确统计真实RosterSort.rebuild，独立保留rawSort防纯exp落入排序热点。
    env.table = setmetatable({ sort = function(list, compare)
        if list[1] and type(list[1]) == "table" and list[1].heroId then
            counts.rawSort = counts.rawSort + 1
            if baseline then counts.rosterSort = counts.rosterSort + 1 end
        end
        return table.sort(list, compare)
    end }, { __index = table })
    env.require = function(name)
        if mocks[name] then return mocks[name] end
        if loaded[name] then return loaded[name] end
        assert(realNames[name] or name:match("^config%.") or name:match("^shared%."),
            "未声明依赖/真实存档入口: " .. name)
        assert(not loading[name], "unexpected cycle: " .. name)
        loading[name] = true
        local path = name:gsub("%.", "/") .. ".lua"
        allowedPaths[path] = true
        local file = assert(cache:GetFile(path), "missing source " .. path)
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local value = assert(load(table.concat(lines, "\n"), "@exp-refresh-isolated/" .. path, "t", env))()
        loading[name] = nil
        loaded[name] = value
        if name == "ui.character.panel.CharacterProgress" then
            local bind = value.bind
            value.bind = function(deps)
                for key, countKey in pairs({ rebuildRoster = "rebuild", refreshPowerCache = "refresh",
                    refreshNavBadge = "nav", syncTeamSlotsFromOwned = "slots",
                    syncRosterExpFromOwned = "light" }) do
                    local original = deps[key]
                    if original then
                        deps[key] = function(...)
                            counts[countKey] = counts[countKey] + 1
                            return original(...)
                        end
                    end
                end
                local persist = deps.persistHeroExp
                if noPersist then deps.persistHeroExp = nil
                elseif persist then
                    deps.persistHeroExp = function(changed)
                        counts.persist = counts.persist + 1
                        patches[#patches + 1] = copy(changed)
                        return persist(changed)
                    end
                end
                return bind(deps)
            end
        elseif name == "ui.character.panel.CharacterRosterSort" then
            local bind = value.bind
            value.bind = function(deps)
                local api = bind(deps)
                local rebuild = api.rebuild
                api.rebuild = function(...)
                    if not baseline then counts.rosterSort = counts.rosterSort + 1 end
                    return rebuild(...)
                end
                return api
            end
        elseif name == "systems.EquipmentPower" then
            for _, key in ipairs({ "buildContext", "buildWornContext" }) do
                local original = value[key]
                if original then value[key] = function(...)
                    counts.context = counts.context + 1
                    return original(...)
                end end
            end
            local invalidate = value.invalidate
            value.invalidate = function(...)
                counts.powerInvalidations = counts.powerInvalidations + 1
                return invalidate(...)
            end
        elseif name == "config.HeroConfig" then
            local create = value.createHero
            value.createHero = function(...)
                counts.createHero = counts.createHero + 1
                return create(...)
            end
        end
        return value
    end
    env.cache = { GetFile = function(_, path)
        assert(allowedPaths[path], "禁止未声明资源/存档读取: " .. tostring(path))
        return cache:GetFile(path)
    end }
    panel = env.require("ui.character.panel.CharacterPanel")
    env.require("core.EventBus").on(env.require("config.GameEvents").TEAM_POWER_CHANGED,
        function(value) events[#events + 1] = copy(value) end)
    panel.init(nil)
    local function reset()
        for key in pairs(counts) do counts[key] = 0 end
        patches, events, progress, layouts = {}, {}, {}, {}
    end
    local function data()
        return { roster = drawContext.getHeroRoster(), rosterPower = drawContext.getRosterPowerCache(),
            detail = detailContext, patches = patches, events = events, progress = progress,
            layouts = layouts, gamePower = gamePower }
    end
    local function apply(heroes)
        modules.heroes = heroes
        panel.setHeroesData(heroes)
        reset()
    end
    reset()
    return { panel = panel, load = env.require, counts = counts, reset = reset, apply = apply,
        modules = modules, data = data, network = function(value) networkMode = value end }
end

local OWNED_IDS = { 1, 2, 3, 4, 5, 6, 25 }
local function heroes(expTable, levels)
    local roster = {}
    for index, id in ipairs(OWNED_IDS) do
        local level = levels and levels[id] or 10
        roster[index % 2 == 0 and tostring(id) or id] = {
            level = level, exp = 0, maxExp = expTable.getHeroExpForLevel(level) or 0,
            shards = id * 2, awakening = {}, extraTalent = {}, dupeCount = 3,
            advBranch = nil, customSaveField = { marker = tostring(id) },
        }
    end
    roster["8"] = { shards = 9, customSaveField = { marker = "shard-only" } }
    return { roster = roster, deployed = { 1, 0, 2, 0 }, teams = {
        { slots = { 1, 0, 2, 0 } }, { slots = { 0, 3, 0, 5 } }, { slots = { 25, 0, 0, 0 } },
    }, customModuleField = { marker = "keep" } }
end
local function savedHero(data, id) return data.roster[id] or data.roster[tostring(id)] end
local function snapshot(f)
    local state = f.data()
    local result = { roster = copy(state.roster), rosterPower = copy(state.rosterPower),
        rowRefs = {}, slots = {}, slotRefs = {}, powers = {}, layouts = {}, owned = {},
        saved = copy(f.modules.heroes), gamePower = state.gamePower }
    for index, row in ipairs(state.roster) do result.rowRefs[index] = row end
    for _, id in ipairs(OWNED_IDS) do result.owned[id] = copy(f.panel.getOwnedHero(id)) end
    for team = 1, 3 do
        local slots, powers = f.panel.getTeamSlotsData(team)
        result.slots[team], result.powers[team] = copy(slots), copy(powers)
        result.slotRefs[team] = slots
        result.layouts[team] = f.panel.getTeamSlotLayout(team)
    end
    return result
end
local function consistent(f, label)
    local cp, state = f.panel, f.data()
    local byId = {}
    for _, row in ipairs(state.roster) do byId[row.heroId] = row end
    check(#state.roster == #f.load("config.HeroConfig").getAllIds(), label .. " 全部名册项保留")
    for _, id in ipairs(OWNED_IDS) do
        local own, row = cp.getOwnedHero(id), byId[id]
        check(row and row.owned and row.level == own.level and row.exp == own.exp and row.maxExp == own.maxExp,
            label .. " owned/roster等级经验立即一致 hero=" .. id)
    end
    check(not byId[8].owned and byId[8].shards == 9, label .. " 仅碎片英雄不变成owned")
    for team = 1, 3 do
        local slots = cp.getTeamSlotsData(team)
        for index = 1, 4 do
            local slot = slots[index]
            if slot.state == "occupied" then
                local own = cp.getOwnedHero(slot.heroId)
                check(slot.level == own.level and slot.exp == own.exp and slot.maxExp == own.maxExp,
                    label .. " 所有队slots立即一致 " .. team .. ":" .. index)
            end
        end
    end
end
local function preserve(f, prior, label)
    local cp, state = f.panel, f.data()
    for team = 1, 3 do
        check(same(cp.getTeamSlotLayout(team), prior.layouts[team]), label .. " 编队孔位/顺序不变 T" .. team)
        check(cp.getTeamSlotsData(team) == prior.slotRefs[team], label .. " 槽位数组身份保留 T" .. team)
    end
    check(#state.layouts == 0, label .. " 不重开战斗/不失效编队")
    check(same(f.modules.heroes.teams, prior.saved.teams) and same(f.modules.heroes.deployed, prior.saved.deployed)
        and same(f.modules.heroes.customModuleField, prior.saved.customModuleField), label .. " 保存编队及模块其他字段保留")
    for key, old in pairs(prior.saved.roster) do
        local now = f.modules.heroes.roster[key]
        for field, value in pairs(old) do
            if field ~= "level" and field ~= "exp" and field ~= "maxExp" then
                check(same(now[field], value), label .. " persist不覆盖其他字段 " .. tostring(key) .. ":" .. field)
            end
        end
    end
end
local function countsCheck(f, label, expectLevel, calls)
    calls = calls or 1
    local count, state = copy(f.counts), f.data()
    print(string.format("%s COUNTS mode=%s noPersist=%s case=%s calls=%d rebuild=%d refresh=%d nav=%d light=%d sort=%d rawSort=%d context=%d create=%d events=%d progress=%d",
        TAG, baseline and "baseline" or "optimized", tostring(noPersist), label, calls,
        count.rebuild, count.refresh, count.nav, count.light, count.rosterSort, count.rawSort, count.context,
        count.createHero, #state.events, #state.progress))
    local full = baseline or expectLevel
    check(count.rebuild == (full and calls or 0) and count.refresh == (full and calls or 0),
        label .. " 完整名册/战力刷新精确次数")
    check(count.rosterSort == (full and calls or 0), label .. " 只有等级变化重排名册")
    check(count.rawSort <= count.rebuild and (full or count.rawSort == 0),
        label .. " 底层table.sort不超真实rebuild且纯exp精确零调用")
    check(count.nav == (full and calls or 0), label .. " 只有等级变化重算角标")
    check(count.light == (full and 0 or calls), label .. " 纯exp原位显示同步次数")
    check(full and count.context > 0 or not full and count.context == 0,
        label .. " 真实EquipmentPower属性上下文计数")
    check(full and count.createHero > 0 or not full and count.createHero == 0,
        label .. " 真实HeroConfig.createHero计数")
    check(#state.events == (full and calls or 0) and count.powerInvalidations == (full and calls or 0),
        label .. " 纯exp不发布战力/不失效评分缓存")
    check(count.persist == (noPersist and 0 or calls), label .. " persist出口次数不变")
    return count
end
local function lightCheck(f, prior, label)
    local cp, state = f.panel, f.data()
    if not baseline then
        for index, row in ipairs(state.roster) do
            check(row == prior.rowRefs[index], label .. " 名册行身份/排序不变 index=" .. index)
        end
    end
    check(same(state.rosterPower, prior.rosterPower) and state.gamePower == prior.gamePower,
        label .. " 名册与顶栏战力缓存不变")
    for team = 1, 3 do
        local _, powers = cp.getTeamSlotsData(team)
        check(same(powers, prior.powers[team]), label .. " 各队槽位战力不变 T" .. team)
    end
    check(#state.progress == 0 and next(cp.getLastHeroesRefreshTeams()) == nil,
        label .. " 纯exp无战斗属性通知")
end
local function persistedPatch(f, expected, label)
    if not noPersist then
        check(#f.data().patches == 1 and same(f.data().patches[1], expected), label .. " 精确changed-only patch")
    else
        check(#f.data().patches == 0, label .. " 无persist出口无patch调用")
    end
end

function Start()
    local oldRequire, oldFile = require, File
    local ok, err = pcall(function()
        local f = fixture()
        local cp, et = f.panel, f.load("config.ExpTable")
        f.modules.battle = { currentStageId = 101, maxStageId = 2001,
            clearedStages = { ["905"] = true, ["1905"] = true } }
        f.modules.equipment = { inventory = {}, equipped = {} }
        f.modules.talents = { litNodes = {} }
        f.modules.artifacts = {}
        f.apply(heroes(et))
        cp.setActiveTeam(3)
        f.reset()
        local prior = snapshot(f)
        check(cp.addHeroExp(1, 3) == true, "不升级真实入口返回true")
        countsCheck(f, "below-threshold", false)
        persistedPatch(f, { [1] = { exp = 3 } }, "不升级")
        check(cp.getOwnedHero(1).exp == 3 and (noPersist or savedHero(f.modules.heroes, 1).exp == 3),
            "经验实际入账不丢且保存镜像立即同步")
        consistent(f, "不升级"); preserve(f, prior, "不升级"); lightCheck(f, prior, "不升级")

        -- 最大池三队12槽中的合法5个英雄批量入账；未部署也能独立获得经验。
        f.apply(heroes(et))
        prior = snapshot(f)
        for _, id in ipairs(OWNED_IDS) do
            check(cp.addHeroExp(id, 1) == true, "离线式逐英雄批量入口返回true hero=" .. id)
        end
        countsCheck(f, "offline-style-batch", false, #OWNED_IDS)
        consistent(f, "批量"); preserve(f, prior, "批量"); lightCheck(f, prior, "批量")
        for _, id in ipairs(OWNED_IDS) do
            check(cp.getOwnedHero(id).exp == 1 and (noPersist or savedHero(f.modules.heroes, id).exp == 1),
                "批量每名经验只入账一次 hero=" .. id)
        end

        -- 真正升级只影响对应所属队，未上阵同品质等级变化也必须重排名册。
        f.apply(heroes(et))
        prior = snapshot(f)
        check(cp.addHeroExp(5, et.getHeroExpForLevel(10) + 7), "队2真实升级成功")
        countsCheck(f, "team2-level", true)
        persistedPatch(f, { [5] = { level = 11, exp = 7, maxExp = et.getHeroExpForLevel(11) } }, "队2升级")
        check(cp.getOwnedHero(5).level == 11 and cp.getOwnedHero(5).exp == 7, "升级保留余数和maxExp")
        check(same(f.data().progress, { { teams = { 2 }, classes = {} } })
            and same(cp.getLastHeroesRefreshTeams(), { [2] = true }), "等级通知只队2且不重建职业")
        check(cp.getTotalPower(2) ~= prior.powers[2][2] + prior.powers[2][4], "等级变化真实队2战力更新")
        consistent(f, "队2升级"); preserve(f, prior, "队2升级")

        f.apply(heroes(et, { [4] = 11, [6] = 10 }))
        prior = snapshot(f)
        local function rowIndex(id)
            for index, row in ipairs(f.data().roster) do if row.heroId == id then return index end end
            return 0
        end
        -- 4/6真实同品质，先查配置，不伪造等级/品质排序条件。
        local hc = f.load("config.HeroConfig")
        check(hc.get(4).quality == hc.get(6).quality, "未部署排序夹具同真实品质")
        check(rowIndex(4) < rowIndex(6), "升级前未部署等级高者在前")
        check(cp.addHeroExp(6, et.getHeroExpForLevel(10) + et.getHeroExpForLevel(11) + 9), "未上阵连续升级成功")
        countsCheck(f, "reserve-level-sort", true)
        check(cp.getOwnedHero(6).level == 12 and cp.getOwnedHero(6).exp == 9 and rowIndex(6) < rowIndex(4),
            "只有等级变化才按原品质等级规则重排")
        check(#f.data().progress == 0 and next(cp.getLastHeroesRefreshTeams()) == nil,
            "未上阵升级完整战力刷新但不借活动队通知")
        consistent(f, "未部署升级"); preserve(f, prior, "未部署升级")

        -- TOP5地板9→10：实际被提升包含队3和未上阵英雄，持久化不得覆盖其其他字段。
        f.apply(heroes(et, { [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 9, [6] = 1, [25] = 1 }))
        savedHero(f.modules.heroes, 4).exp = 91 -- 更新中的持久化字段，面板保持旧0。
        prior = snapshot(f)
        check(cp.addHeroExp(5, et.getHeroExpForLevel(9)), "共鸣地板升级成功")
        countsCheck(f, "cross-team-resonance", true)
        persistedPatch(f, { [5] = { level = 10, maxExp = et.getHeroExpForLevel(10) },
            [6] = { level = 10, maxExp = et.getHeroExpForLevel(10) },
            [25] = { level = 10, maxExp = et.getHeroExpForLevel(10) } }, "跨队共鸣")
        check(cp.getOwnedHero(6).level == 10 and cp.getOwnedHero(25).level == 10
            and cp.getOwnedHero(6).exp == 0 and cp.getOwnedHero(25).maxExp == et.getHeroExpForLevel(10),
            "旁队及未部署共鸣真实生效")
        check(same(f.data().progress, { { teams = { 2, 3 }, classes = {} } }), "共鸣只通知真实变化队2/3")
        check(savedHero(f.modules.heroes, 4).exp == 91, "exp grant不回灌面板中较旧的其他英雄exp")
        consistent(f, "跨队共鸣"); preserve(f, prior, "跨队共鸣")

        -- 获奖英雄本身不升级，但输入名册存在待共鸣成员；不能只看目标hero的level。
        f.apply(heroes(et, { [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 10, [6] = 1, [25] = 1 }))
        prior = snapshot(f)
        check(cp.addHeroExp(1, 1), "纯目标经验触发旁队共鸣成功")
        countsCheck(f, "only-other-hero-level", true)
        check(cp.getOwnedHero(1).level == 10 and cp.getOwnedHero(25).level == 10 and cp.getOwnedHero(6).level == 10,
            "目标等级未变但任一其他level变化完整刷新")
        check(same(f.data().progress, { { teams = { 3 }, classes = {} } }), "仅其他英雄共鸣通知队3")
        consistent(f, "仅其他英雄升级"); preserve(f, prior, "仅其他英雄升级")

        -- 满级清exp/maxExp保持true，仍同步名册；全部满级不发布新的战力事件。
        local maxLevels = {}
        for _, id in ipairs(OWNED_IDS) do maxLevels[id] = et.HERO_MAX_LEVEL end
        f.apply(heroes(et, maxLevels))
        cp.getOwnedHero(1).exp, cp.getOwnedHero(1).maxExp = 19, 9
        savedHero(f.modules.heroes, 1).exp, savedHero(f.modules.heroes, 1).maxExp = 19, 9
        prior = snapshot(f)
        check(cp.addHeroExp(1, 1), "已满级入账返回true且清余数")
        countsCheck(f, "already-max-level", false)
        persistedPatch(f, { [1] = { exp = 0, maxExp = 0 } }, "已满级")
        check(cp.getOwnedHero(1).level == et.HERO_MAX_LEVEL and cp.getOwnedHero(1).exp == 0
            and cp.getOwnedHero(1).maxExp == 0, "满级不溢出等级")
        consistent(f, "已满级"); preserve(f, prior, "已满级"); lightCheck(f, prior, "已满级")
        maxLevels[1] = et.HERO_MAX_LEVEL - 1
        f.apply(heroes(et, maxLevels))
        check(cp.addHeroExp(1, et.getHeroExpForLevel(et.HERO_MAX_LEVEL - 1) + 999), "升到满级成功")
        countsCheck(f, "reach-max-level", true)
        check(cp.getOwnedHero(1).level == et.HERO_MAX_LEVEL and cp.getOwnedHero(1).exp == 0
            and cp.getOwnedHero(1).maxExp == 0, "到达满级舍弃多余经验不多升一级")
        consistent(f, "到达满级")

        -- 未提供持久化hero模块：完整轻量路径仍一致，不构造新存档或推送。
        f.apply(heroes(et))
        prior = snapshot(f)
        f.modules.heroes = nil
        check(cp.addHeroExp(3, 2), "缺存档模块路径成功")
        countsCheck(f, "missing-persistent-module", false)
        check(f.modules.heroes == nil and cp.getOwnedHero(3).exp == 2, "无persist目标不创建存档模块")
        consistent(f, "无保存目标"); lightCheck(f, prior, "无保存目标")

        -- 网络客户端仍只改变面板；不能借本地优化写回服务器英雄镜像。
        f.apply(heroes(et))
        prior = snapshot(f)
        f.network(true)
        check(cp.addHeroExp(2, 2), "网络模式面板经验路径返回值不变")
        countsCheck(f, "network-no-local-persist", false)
        check(same(f.modules.heroes, prior.saved) and cp.getOwnedHero(2).exp == 2, "网络模式不写本地持久化")
        f.network(false)
        consistent(f, "网络模式"); lightCheck(f, prior, "网络模式")

        -- 坏输入/坏任意英雄来源：原保护不得因轻量路径减弱。
        f.apply(heroes(et))
        prior = snapshot(f)
        for _, amount in ipairs({ 0, -1, math.huge, -math.huge, 0 / 0, "20", false }) do
            check(cp.addHeroExp(1, amount) == false, "拒绝非法amount " .. tostring(amount))
        end
        check(cp.addHeroExp(1, nil) == false and cp.addHeroExp(9999, 1) == false, "nil/未知英雄拒绝")
        check(same(f.modules.heroes, prior.saved) and same(f.data().roster, prior.roster), "非法入账无显示/保存修改")
        check(f.counts.context == 0 and f.counts.refresh == 0 and f.counts.persist == 0
            and #f.data().progress == 0, "拒绝路径无上下文/刷新/persist/通知")
        for _, damaged in ipairs({ { field = "level", value = 0 / 0 }, { field = "level", value = math.huge },
            { field = "level", value = 0 }, { field = "level", value = 1.5 },
            { field = "exp", value = 0 / 0 }, { field = "exp", value = math.huge },
            { field = "exp", value = -1 }, { field = "maxExp", value = math.huge } }) do
            local own = cp.getOwnedHero(6)
            local old = own[damaged.field]
            own[damaged.field] = damaged.value
            check(cp.addHeroExp(1, 1) == false, "拒绝旁成员坏字段 " .. damaged.field .. "=" .. tostring(damaged.value))
            own[damaged.field] = old
        end
        cp.getOwnedHero(1).exp = 1e308
        check(cp.addHeroExp(1, 1e308) == false, "有限amount和有限exp之和溢出拒绝")
        check(same(f.modules.heroes, prior.saved) and f.counts.persist == 0 and f.counts.context == 0,
            "坏源/溢出不污染存档或进入属性上下文")
        cp.getOwnedHero(1).exp = 0
        -- syncSlotLevel外部可先原位更新owned；保留原刷新，不冒险以相同level判成无变化。
        cp.getOwnedHero(3).level = 11
        f.reset()
        check(cp.syncSlotLevel(3, 11), "外部先修改owned的slot-level回执保留true")
        check(f.counts.rebuild == 1 and f.counts.refresh == 1 and same(f.data().progress[1].teams, { 2 }),
            "syncSlotLevel不扩写重复门控，真正外部等级变化仍完整刷新")
        check(require == oldRequire and File == oldFile, "全局require/File保持，真实玩家档完全隔离")
    end)
    if not ok then check(false, "harness error: " .. tostring(err)) end
    print(string.format("%s %s assertions=%d failures=%d mode=%s noPersist=%s", TAG,
        failures == 0 and "ALL PASS" or "FAIL", assertions, failures,
        baseline and "baseline" or "optimized", tostring(noPersist)))
    if failures > 0 then log:Write(LOG_ERROR, TAG .. " failures=" .. failures) end
    engine:Exit()
end
