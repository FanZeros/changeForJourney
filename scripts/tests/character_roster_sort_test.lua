-- 名册排序独立Runtime专项：纯比较器 + 真实Panel/Power/HeroSync/Input联动。
-- 不启动main、不读写玩家档、不发送编队动作。日志由调用者存入.git/validation。
local checks, failures = 0, 0
local function check(value, message)
    checks = checks + 1
    if value then print("[PASS] " .. message)
    else failures = failures + 1; print("[FAIL] " .. message) end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function order(roster, ownedOnly)
    local result = {}
    for _, entry in ipairs(roster) do
        if not ownedOnly or entry.owned then result[#result + 1] = tostring(entry.heroId) end
    end
    return table.concat(result, ",")
end
local function resourceModule(name, loader)
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(cache:GetFile(path), path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local env = setmetatable({ require = loader }, { __index = _G })
    return assert(load(table.concat(lines, "\n"), "@" .. path, "t", env))()
end

local function pureSort(nativeRequire)
    local roster, powerCache = {}, {}
    local owned = { [1] = { level = 10 }, [2] = { level = 20 }, [3] = { level = 20 },
        [4] = { level = 8 }, [5] = { level = 30 }, [6] = { level = 30 } }
    local qualities = { 2, 3, 3, 5, 4, 4, 5, 5, 1 }
    local teams = { { slots = { { state = "empty" }, { state = "occupied", heroId = 1 } } },
        { slots = { { state = "empty" }, { state = "occupied", heroId = 3 },
            { state = "occupied", heroId = 2 } } },
        { slots = { { state = "occupied", heroId = 4 } } } }
    local busy, canceled = false, 0
    local Sort = nativeRequire("ui.character.panel.CharacterRosterSort")
    local sort = Sort.bind({ HC = { getAllIds = function() return { 9, 6, 3, 7, 2, 8, 4, 1, 5 } end,
        get = function(id) return { quality = qualities[id] } end,
        createHero = function() error("比较器禁止建英雄") end },
        ExpTable = { getHeroExpForLevel = function() return 5 end }, MAX_SLOTS = 4, TEAM_COUNT = 3,
        getTeams = function() return teams end, getHeroRoster = function() return roster end,
        getPowerCache = function() return powerCache end, getOwnedSet = function() return owned end,
        getShardMap = function() return { [7] = 1, [8] = 999999 } end,
        isInteractionBusy = function() return busy end,
        cancelInteraction = function() canceled = canceled + 1; busy = false end })
    sort.rebuild()
    check(order(roster) == "4,2,3,1,5,6,7,8,9", "default精确保留拥有/任队出战/品质降/等级降/ID升")
    local powers = { [1] = 100, [2] = 300, [3] = 300, [4] = 20, [5] = 900, [6] = 900 }
    for i, entry in ipairs(roster) do powerCache[i] = entry.owned and powers[entry.heroId] or 0 end
    sort.powerRefreshed()
    local cases = {
        { "team", false, "1,3,2,4,5,6", true },
        { "default", true, "4,2,3,1,5,6", false },
        { "power", false, "5,6,2,3,1,4", false },
        { "power", true, "4,1,2,3,5,6", true },
        { "level", false, "5,6,2,3,1,4", false },
        { "level", true, "4,1,2,3,5,6", true },
        { "rarity", false, "4,5,6,2,3,1", false },
        { "rarity", true, "1,2,3,5,6,4", true },
    }
    for _, c in ipairs(cases) do
        check(sort.setSort(c[1], c[2]), "接受模式/方向 " .. c[1] .. "/" .. tostring(c[2]))
        local mode, ascending = sort.getSort()
        check(mode == c[1] and ascending == c[4], "固定/数值方向返回正确 " .. c[1])
        check(order(roster, true) == c[3], "原始键方向与ID稳定平局 " .. c[1] .. "/" .. tostring(c[2]))
        check(order(roster):sub(-5) == "7,8,9", "未拥有不借战力/等级/碎片改变稳定稀有度ID序 " .. c[1])
        for i, entry in ipairs(roster) do
            check(powerCache[i] == (entry.owned and powers[entry.heroId] or 0), "按heroId重映射缓存 " .. entry.heroId)
        end
    end
    local before, oldMode, oldAscending, oldCanceled = order(roster), sort.getSort(), true, canceled
    for _, c in ipairs({ { "bad" }, { false }, { "power", "false" }, { "level", 1 } }) do
        check(not sort.setSort(c[1], c[2]), "非法API返回false")
        check(order(roster) == before and canceled == oldCanceled, "非法API不改变名册或交互")
    end
    local mode, ascending = sort.getSort()
    check(mode == oldMode and ascending == oldAscending, "非法API不改已有mode/方向")
    sort.setSort("power", false)
    busy = true
    local stable = order(roster)
    powers[1] = 1000
    for i, entry in ipairs(roster) do powerCache[i] = entry.owned and powers[entry.heroId] or 0 end
    sort.powerRefreshed()
    check(order(roster) == stable and not sort.flush(), "按压时power刷新只更新缓存不换位置")
    owned[4].level = 100
    sort.rebuild()
    check(order(roster) == stable, "拖拽时水合完整更新level但保住原ID次序")
    busy = false
    check(sort.flush() and roster[1].heroId == 1, "结束后一次应用待排power结果")
    sort.reset(); sort.rebuild()
    mode, ascending = sort.getSort()
    check(mode == "default" and not ascending and sort.getPower(1) == nil, "reset恢复default并清旧会话映射")
end

local function realPanel(nativeRequire)
    local HC = nativeRequire("config.HeroConfig")
    local Draw = nativeRequire("ui.character.panel.CharacterPanelDraw2")
    local EP = nativeRequire("systems.EquipmentPower")
    -- 正式当前穿戴评分走轻快照；独立oracle始终保留完整库存上下文。
    local oldBuild, oldWornBuild, oldRequire, savedLit = EP.buildContext, EP.buildWornContext, require, HC._getSavedLitNodes()
    local data, storeListeners, dispatcherListeners = {}, {}, {}
    local context, contexts, dirty, snapshots, actions, synchronousCacheReads = {}, 0, 0, {}, 0, 0
    local panel = {}
    local progressCounts = { rebuild = 0, refresh = 0, nav = 0, light = 0 }
    local progressTeams, layoutInvalidations = {}, {}
    ---@type table
    local sortSession
    ---@type table
    local inputSession
    local overlayVisible = false
    local detail = { opened = nil, visible = false }
    local noop = function() end
    detail.init, detail.draw, detail.setContext = noop, noop, noop
    detail.isOpen = function() return detail.visible end
    detail.open = function(id) detail.opened = id; detail.visible = true end
    detail.markPowerDirty = function() dirty = dirty + 1 end
    detail.hasAnyUpgradeForHero, detail.hasAwakeningUpgrade = function() return false end, function() return false end
    detail.handleInput, detail.handleDragBegin, detail.handleDragMove, detail.handleDragEnd = noop, noop, noop, noop
    local modules = {}
    local mocks = {
        ["runtime.ClientDispatcher"] = { get = function(k) return data[k] end,
            subscribe = function(k, cb) dispatcherListeners[k] = cb end },
        ["core.PlayerStore"] = { Get = function(k) return data[k] end,
            Subscribe = function(k, cb) storeListeners[k] = cb end },
        ["core.GameState"] = { getLevel = function() return 100 end, setPower = noop },
        ["ui.hud.BottomNav"] = { setBadge = noop, refreshTownBadge = noop },
        ["ui.character.detail.CharacterDetail"] = detail,
        ["core.EventBus"] = { emit = function(_, payload)
            snapshots[#snapshots + 1] = copy(payload)
            if context.getHeroRoster and panel.getRosterPower then
                local cacheValues = context.getRosterPowerCache()
                local correct = true
                for i, entry in ipairs(context.getHeroRoster()) do
                    if cacheValues[i] ~= (entry.owned and panel.getRosterPower(entry.heroId) or 0) then correct = false end
                end
                if correct then synchronousCacheReads = synchronousCacheReads + 1 end
            end
        end },
        ["ui.battle.tri.BattleTriPage"] = {
            invalidateTeams = function(teams) layoutInvalidations[#layoutInvalidations + 1] = copy(teams) end,
            refreshHeroProgressTeams = function(teams, classes)
                progressTeams[#progressTeams + 1] = { teams = copy(teams), classes = copy(classes) }
            end },
        ["ui.battle.scene.BattleScene"] = { refreshAllyStats = noop },
        ["ui.hud.popup.OfflineRewardPanel"] = { isOpen = function() return false end },
        ["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end },
        ["systems.GameSFX"] = { play = noop },
        ["systems.TutorialManager"] = { isActive = function() return false end,
            notifyHeroDeployed = noop, notifyCharacterDetailOpened = noop },
        ["runtime.GameAction"] = { sendAction = function() actions = actions + 1 end },
    }
    for _, name in ipairs({ "ui.hud.popup.LevelUpPopup", "ui.hud.popup.PlayerInfoPanel",
        "ui.story.gate.DarkTitleScreenGate", "ui.story.gate.StartScreen", "ui.story.gate.LetterIntro",
        "ui.battle.popup.TerminalConfirmDialog", "ui.dungeon.DungeonBattleScene", "ui.tower.TowerBattleScene",
        "ui.dev.CEPanel", "ui.hud.popup.RewardPopup" }) do
        mocks[name] = { isOpen = function() return false end, isActive = function() return false end }
    end
    mocks["ui.story.gate.IntroCutscene"] = { isActive = function() return false end }
    mocks["ui.story.ScenarioDialogue"] = { isActive = function() return false end }
    mocks["ui.hud.popup.UpdateNoticePopup"] = { isOpen = function() return overlayVisible end }
    local drawFacade = setmetatable({ setContext = function(ctx) context = ctx; Draw.setContext(ctx) end,
        draw = noop, initImages = noop, getSharedImages = function() return {} end, resetPresentation = noop,
        clearSortInteraction = noop, clearTeamInteraction = noop, setSortInteraction = noop, setTeamInteraction = noop },
        { __index = Draw })
    mocks["ui.character.panel.CharacterPanelDraw2"] = drawFacade
    local function mocked(name)
        if mocks[name] then return mocks[name] end
        if modules[name] then return modules[name] end
        if name == "ui.character.panel.CharacterPanel" or name == "ui.character.panel.CharacterPower"
            or name == "ui.character.panel.CharacterHeroSync" or name == "ui.character.panel.CharacterInput"
            or name == "ui.character.panel.CharacterRosterSort" or name == "ui.character.panel.CharacterProgress" then
            modules[name] = resourceModule(name, mocked)
            local value = modules[name]
            if name == "ui.character.panel.CharacterProgress" then
                local bind = value.bind
                value.bind = function(deps)
                    for key, counter in pairs({ rebuildRoster = "rebuild", refreshPowerCache = "refresh",
                        refreshNavBadge = "nav", syncRosterExpFromOwned = "light" }) do
                        local original = deps[key]
                        if original then deps[key] = function(...)
                            progressCounts[counter] = progressCounts[counter] + 1
                            return original(...)
                        end end
                    end
                    return bind(deps)
                end
            elseif name == "ui.character.panel.CharacterRosterSort" then
                local bind = value.bind
                value.bind = function(deps) sortSession = bind(deps); return sortSession end
            elseif name == "ui.character.panel.CharacterInput" then
                local bind = value.bind
                value.bind = function(deps) inputSession = bind(deps); return inputSession end
            end
            return value
        end
        return nativeRequire(name)
    end
    EP.buildWornContext = function(...) contexts = contexts + 1; return oldWornBuild(...) end
    require = mocked
    local ok, err = pcall(function()
        local Panel = mocked("ui.character.panel.CharacterPanel")
        panel = Panel
        Panel.init({})
        data.heroes = { roster = {}, deployed = { 0, 1, 0, 0 }, teams = {
            { slots = { 0, 1, 0, 0 } }, { slots = { 0, 0, 2, 0 } }, { slots = { 3, 0, 0, 0 } } } }
        for id = 1, 8 do data.heroes.roster[tostring(id)] = { level = id + 10, exp = id,
            maxExp = 30, advBranch = {}, awakening = {}, extraTalent = {}, shards = 0 } end
        data.heroes.roster["9"] = { shards = 500 }
        data.battle = { clearedStages = { [905] = true, [1905] = true }, maxStageId = 2305 }
        data.equipment = { inventory = {}, equipped = {} }
        data.artifacts = { bag = { { id = "a", artifactId = 5, value = 20 },
            { id = "b", artifactId = 5, value = 80 }, { id = "c", artifactId = 5, value = 140 } },
            equippedByTeam = { { {}, { "a" } }, { {}, {}, { "b" } }, { { "c" } } } }
        data.talents = { litNodes = {} }
        contexts, dirty, snapshots, synchronousCacheReads = 0, 0, {}, 0
        Panel.setHeroesData(data.heroes)
        check(contexts == 8 and dirty == 1 and #snapshots == 1, "真实Panel水合八人仅八评分上下文/一次完整refresh事件")
        check(synchronousCacheReads == 1, "完整事件同步回调读取的新heroId映射与名册索引缓存完全一致")
        check(snapshots[1].ready and #snapshots[1].powers == 3, "水合完整三队快照ready不丢PR116回调契约")
        check(Panel.getOwnedHero(8).level == 18 and Panel.getOwnedHero(8).exp == 8
            and Panel.getOwnedHero(8).extraTalent ~= nil, "完整heroesData同步非单字段排序副本")
        local roster, cacheValues = context.getHeroRoster(), context.getRosterPowerCache()
        for _, mode in ipairs({ "default", "team", "power", "level", "rarity" }) do
            local countBefore = contexts
            check(Panel.setRosterSort(mode), "真实Panel公开排序 " .. mode)
            check(contexts == countBefore and actions == 0, "显式排序不额外calc或发送编队动作 " .. mode)
            for i, entry in ipairs(roster) do
                check(cacheValues[i] == (entry.owned and Panel.getRosterPower(entry.heroId) or 0),
                    "真实Panel缓存随heroId搬迁 " .. mode .. "/" .. entry.heroId)
            end
        end
        Panel.setRosterSort("team")
        check(order(roster, true):sub(1, 5) == "1,2,3", "真实team按队1槽2/队2槽3/队3槽1排序")
        local mapped, oracle = {}, {}
        for id = 1, 3 do
            mapped[id] = Panel.getRosterPower(id)
            oracle[id] = math.floor(oldBuild(id, { heroData = Panel.getOwnedHero(id), heroes = data.heroes,
                equipment = data.equipment, artifacts = data.artifacts, talents = data.talents }).currentPower + 0.5)
            check(mapped[id] == oracle[id], "名册hero" .. id .. "与独立真实装备神器上下文oracle一致")
            local _, slotsPower = Panel.getTeamSlotsData(id)
            local slot = ({ 2, 3, 1 })[id]
            check(slotsPower[slot] == mapped[id], "神器真实team/slot缓存匹配本人 " .. id)
        end
        data.artifacts = { bag = {}, equippedByTeam = {} }; Panel.refreshPower()
        for id = 1, 3 do
            local bare = math.floor(oldBuild(id, { heroData = Panel.getOwnedHero(id), heroes = data.heroes,
                equipment = data.equipment, artifacts = data.artifacts, talents = data.talents }).currentPower + 0.5)
            check(Panel.getRosterPower(id) == bare and oracle[id] > bare,
                "清神器后映射与真实oracle一致且只移除本人装配贡献 " .. id)
        end
        check(Panel.getRosterPower(9) == nil, "真实未拥有不伪造可排序战力")
        local oldLayout = table.concat(Panel.getTeamSlotLayout(2), ",")
        local countBefore = contexts
        check(not Panel.setRosterSort("wrong") and not Panel.setRosterSort("level", 1), "真实API拒非法mode/方向")
        check(contexts == countBefore and table.concat(Panel.getTeamSlotLayout(2), ",") == oldLayout,
            "真实非法API不改缓存/编队")

        Panel.setRosterSort("power", false)
        local previousFirst = roster[1].heroId
        local benchId = previousFirst == 8 and 7 or 8
        local index
        for i, entry in ipairs(roster) do if entry.heroId == previousFirst then index = i; break end end
        local row = math.ceil(index / Draw.MAX_PER_ROW)
        local col = index - (row - 1) * Draw.MAX_PER_ROW
        local rowCount = math.min(Draw.MAX_PER_ROW, #roster - (row - 1) * Draw.MAX_PER_ROW)
        local total = rowCount * Draw.ROSTER_ICON + (rowCount - 1) * 24
        local x = (Draw.DESIGN_W - total) * 0.5 + Draw.ROSTER_ICON * 0.5 + (col - 1) * (Draw.ROSTER_ICON + 24)
        local y = Draw.ROW1_CY + (row - 1) * Draw.ROW_SPACING + Draw.CONTENT_SHIFT_Y
        Panel.handleDragBegin(x, y)
        data.equipment.inventory["100"] = { templateId = "C1", level = 1, quality = 1,
            baseStats = { { benchId == 7 and "magAtk" or "physAtk", 1000000 } }, affixes = {} }
        data.equipment.equipped[tostring(benchId)] = { accessory = 100 }
        contexts = 0
        storeListeners.equipment()
        check(contexts == 8 and roster[1].heroId == previousFirst, "装备刷新power一次全刷新但Down期间不换目标")
        detail.visible, detail.opened = false, nil
        Panel.handleDragEnd(x, y); Panel.handleInput(x, y)
        check(detail.opened == previousFirst, "真实End->Input仍打开原Down英雄不是新战力首位")
        detail.visible = false; Panel.update(0.016)
        print("[roster equip actual] first=" .. tostring(roster[1].heroId) .. " expected=" .. tostring(benchId)
            .. " targetPower=" .. tostring(Panel.getRosterPower(benchId)) .. " prevPower=" .. tostring(Panel.getRosterPower(previousFirst)))
        check(roster[1].heroId == benchId and actions == 0, "Down结束后更新才power重排，未发送编队动作")

        local avX, avY = Draw.avatarCenter(2, 3)
        avX, avY = avX + Draw.CONTENT_SHIFT_X, avY + Draw.CONTENT_SHIFT_Y
        Panel.handleDragBegin(avX, avY); Panel.handleDragMove(avX + 40, avY)
        check(Panel.isDraggingCard(), "负End测试先激活原头像拖拽")
        Panel.handleDragEnd(-1, -1)
        check(not Panel.isDraggingCard() and context.getDragState().heroId == nil,
            "直接负坐标End立即取消活动卡/滚动，不依赖先调用Input")
        Panel.update(0.016)
        Panel.handleDragBegin(avX, avY)
        Panel.setHeroesData(data.heroes)
        Panel.handleDragEnd(avX, avY); Panel.handleInput(avX, avY)
        check(detail.opened == 2, "同身份完整水合不取消合法头像Down")
        detail.visible, detail.opened = false, nil; Panel.update(0.016)
        Panel.handleDragBegin(avX, avY)
        data.heroes.teams[2].slots[3] = 4
        Panel.setHeroesData(data.heroes)
        data.heroes.teams[2].slots[3] = 2
        Panel.setHeroesData(data.heroes)
        Panel.handleDragEnd(avX, avY); Panel.handleInput(avX, avY)
        check(detail.opened == nil, "头像A->B->A水合瞬换永久取消旧Down")
        Panel.update(0.016)
        Panel.handleDragBegin(avX, avY); Panel.handleDragMove(avX + 40, avY)
        check(Panel.isDraggingCard(), "头像超阈值仍启动原正常拖拽")
        data.heroes.teams[2].slots[3] = 4; Panel.setHeroesData(data.heroes)
        check(not Panel.isDraggingCard(), "活动拖拽源被新水合替换时立即取消，不会搬走新英雄")
        local dropX, dropY = Draw.avatarCenter(2, 4)
        Panel.handleInput(dropX + Draw.CONTENT_SHIFT_X, dropY + Draw.CONTENT_SHIFT_Y)
        Panel.handleDragEnd(dropX + Draw.CONTENT_SHIFT_X, dropY + Draw.CONTENT_SHIFT_Y)
        check(Panel.getTeamSlotLayout(2)[3] == 4 and Panel.getTeamSlotLayout(2)[4] == 0,
            "取消旧drag后Up不交换替代B到目标空槽")
        data.heroes.teams[2].slots[3] = 2; Panel.setHeroesData(data.heroes); Panel.update(0.016)
        Panel.handleDragBegin(x, y)
        local pressedId = context.getDragState().heroId
        if pressedId then
            local oldEntry = copy(data.heroes.roster[tostring(pressedId)])
            data.heroes.roster[tostring(pressedId)] = { shards = 12 }; Panel.setHeroesData(data.heroes)
            data.heroes.roster[tostring(pressedId)] = oldEntry; Panel.setHeroesData(data.heroes)
            detail.opened = nil
            Panel.handleDragEnd(x, y); Panel.handleInput(x, y)
            check(detail.opened == nil, "名册owned true->false->true永久取消旧Down")
        else check(false, "名册owned ABA找到真实按压源") end
        Panel.update(0.016)

        local sortX, sortY
        for yy = Draw.ROW1_CY - 200 + Draw.CONTENT_SHIFT_Y, Draw.ROW1_CY + Draw.CONTENT_SHIFT_Y do
            for xx = 0, Draw.DESIGN_W, 4 do
                if Draw.hitTestRosterSort(xx, yy) == "level" then sortX, sortY = xx + 2, yy + 2; break end
            end
            if sortX then break end
        end
        check(sortX ~= nil, "使用真实Draw寻找排序栏命中不复制布局")
        Panel.setRosterSort("power")
        Panel.handleInput(sortX, sortY)
        check(Panel.getRosterSort() == "power", "裸Input不能排序")
        Panel.handleDragBegin(sortX, sortY)
        Panel.handleDragEnd(sortX, sortY); Panel.handleInput(sortX, sortY)
        check(Panel.getRosterSort() == "level", "真实Begin->End->Input排序一次")
        Panel.handleInput(sortX, sortY)
        check(Panel.getRosterSort() == "level", "同released重复Input不复触")
        Panel.handleDragBegin(sortX, sortY); Panel.handleDragMove(sortX + 200, sortY)
        Panel.handleDragMove(sortX, sortY); Panel.handleDragEnd(sortX, sortY); Panel.handleInput(sortX, sortY)
        check(Panel.getRosterSort() == "level", "排序Move离栏后返回仍永久取消")
        Panel.handleDragBegin(sortX, sortY); Panel.handleRightClick(sortX, sortY)
        Panel.handleDragEnd(sortX, sortY); Panel.handleInput(sortX, sortY)
        check(Panel.getRosterSort() == "level", "右键只取消旧排序按压，不切模式")
        Panel.handleDragBegin(sortX, sortY); Panel.handleDragEnd(sortX, sortY); Panel.update(0.016)
        Panel.setRosterSort("power"); Panel.handleInput(sortX, sortY)
        check(Panel.getRosterSort() == "power", "released跨update过期不能重放")
        Panel.handleDragBegin(sortX, sortY); Panel.handleDragEnd(sortX, sortY)
        Panel.draw({}); Panel.handleInput(sortX, sortY)
        check(Panel.getRosterSort() == "power", "真实tab3仅draw也清released，不靠tab1 update")
        Panel.handleDragBegin(sortX, sortY)
        overlayVisible = true; Panel.draw({}); overlayVisible = false
        Panel.handleDragEnd(sortX, sortY); Panel.handleInput(sortX, sortY)
        check(Panel.getRosterSort() == "power", "引擎非package缓存overlay瞬时出现后关闭仍取消旧Down")
        -- PR117融合：纯exp不影响五模式原始排序键、缓存或合法Down；旁队共鸣仍完整刷新。
        local ET = nativeRequire("config.ExpTable")
        local savedHeroes = copy(data.heroes)
        local function same(a, b)
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return a == b end
            for key, value in pairs(a) do if not same(value, b[key]) then return false end end
            for key in pairs(b) do if a[key] == nil then return false end end
            return true
        end
        local function rowPoint(id)
            local found
            for i, entry in ipairs(roster) do if entry.heroId == id then found = i; break end end
            assert(found, "真实名册找不到hero=" .. tostring(id))
            local r = math.ceil(found / Draw.MAX_PER_ROW)
            local c = found - (r - 1) * Draw.MAX_PER_ROW
            local n = math.min(Draw.MAX_PER_ROW, #roster - (r - 1) * Draw.MAX_PER_ROW)
            local width = n * Draw.ROSTER_ICON + (n - 1) * 24
            return (Draw.DESIGN_W - width) * 0.5 + Draw.ROSTER_ICON * 0.5
                + (c - 1) * (Draw.ROSTER_ICON + 24) + Draw.CONTENT_SHIFT_X,
                Draw.ROW1_CY + (r - 1) * Draw.ROW_SPACING + Draw.CONTENT_SHIFT_Y, found
        end
        local function applyExpFixture(levels)
            detail.visible, detail.opened = false, nil
            Panel.update(0.016)
            data.heroes = copy(savedHeroes)
            for id = 1, 8 do
                local own = data.heroes.roster[tostring(id)]
                own.level = levels and levels[id] or 10
                own.exp, own.maxExp = 0, ET.getHeroExpForLevel(own.level)
            end
            Panel.setHeroesData(data.heroes)
            Panel.update(0.016)
        end
        local function resetExpCounts()
            contexts, dirty, snapshots, synchronousCacheReads = 0, 0, {}, 0
            progressTeams, layoutInvalidations = {}, {}
            for key in pairs(progressCounts) do progressCounts[key] = 0 end
        end
        for _, mode in ipairs({ "default", "team", "power", "level", "rarity" }) do
            applyExpFixture()
            Panel.setRosterSort(mode, mode == "level")
            local priorOrder, priorRevision = order(roster), sortSession.getRevision()
            local priorRows, priorPower, mappedPower = {}, copy(cacheValues), {}
            for i, entry in ipairs(roster) do priorRows[i] = entry end
            for id = 1, 8 do mappedPower[id] = Panel.getRosterPower(id) end
            local priorSlots, priorSlotPowers, priorLayouts = {}, {}, {}
            for team = 1, 3 do
                local slots, values = Panel.getTeamSlotsData(team)
                priorSlots[team], priorSlotPowers[team] = slots, copy(values)
                priorLayouts[team] = Panel.getTeamSlotLayout(team)
            end
            local pressedId = roster[1].heroId
            local px, py = rowPoint(pressedId)
            Panel.handleDragBegin(px, py)
            check(inputSession.isRosterInteractionBusy() and context.getDragState().heroId == pressedId,
                "纯exp前真实名册Down绑定原hero " .. mode)
            resetExpCounts()
            check(Panel.addHeroExp(pressedId, 1), "纯exp真实入口成功 " .. mode)
            check(progressCounts.rebuild == 0 and progressCounts.refresh == 0 and progressCounts.nav == 0
                and progressCounts.light == 1, "纯exp仅一次原位同步/完整刷新零次 " .. mode)
            check(contexts == 0 and dirty == 0 and #snapshots == 0 and synchronousCacheReads == 0,
                "纯exp无真实穿戴评分/战力dirty/事件 " .. mode)
            check(order(roster) == priorOrder and sortSession.getRevision() == priorRevision
                and Panel.getRosterSort() == mode, "纯exp不重排或改mode/revision " .. mode)
            for i, entry in ipairs(roster) do
                check(entry == priorRows[i], "纯exp保留每一名册行引用 " .. mode .. "/" .. entry.heroId)
            end
            check(context.getHeroRoster() == roster and context.getRosterPowerCache() == cacheValues
                and same(cacheValues, priorPower), "纯exp名册/索引缓存引用与值均保留 " .. mode)
            for id = 1, 8 do
                check(Panel.getRosterPower(id) == mappedPower[id] and Panel.getOwnedHero(id).level == 10,
                    "纯exp保持heroId战力/等级 " .. mode .. "/" .. id)
            end
            for team = 1, 3 do
                local slots, values = Panel.getTeamSlotsData(team)
                check(slots == priorSlots[team] and same(values, priorSlotPowers[team])
                    and same(Panel.getTeamSlotLayout(team), priorLayouts[team]),
                    "纯exp三队槽引用/战力/编队不变 " .. mode .. "/" .. team)
            end
            check(roster[1].exp == 1 and roster[1].maxExp == ET.getHeroExpForLevel(10)
                and Panel.getOwnedHero(pressedId).exp == 1 and data.heroes.roster[tostring(pressedId)].exp == 1,
                "纯exp显示/owned/持久镜像立即一致 " .. mode)
            Panel.draw({})
            check(inputSession.isRosterInteractionBusy() and context.getDragState().heroId == pressedId
                and order(roster) == priorOrder and sortSession.getRevision() == priorRevision,
                "纯exp及tab3 draw不取消或换掉原Down " .. mode)
            Panel.handleDragEnd(px, py); Panel.handleInput(px, py)
            check(detail.opened == pressedId, "纯exp后End->Input仍打开原Down英雄 " .. mode)
            detail.visible, detail.opened = false, nil; Panel.update(0.016)
            check(contexts == 0 and order(roster) == priorOrder and sortSession.getRevision() == priorRevision
                and #progressTeams == 0 and #layoutInvalidations == 0 and actions == 0,
                "纯exp收尾无延迟重排/战斗属性通知/编队动作 " .. mode)
        end

        -- 获奖hero1自身10级不变；真实TOP5地板10提升队3的hero3及bench7/8。
        applyExpFixture({ [1] = 10, [2] = 10, [3] = 1, [4] = 10,
            [5] = 10, [6] = 10, [7] = 1, [8] = 1 })
        Panel.setRosterSort("level", false)
        local priorOrder, priorRevision = order(roster), sortSession.getRevision()
        local priorTeam3Power = Panel.getTotalPower(3)
        local priorTeamPowers, priorLayouts = {}, {}
        for team = 1, 3 do
            local _, values = Panel.getTeamSlotsData(team)
            priorTeamPowers[team], priorLayouts[team] = copy(values), Panel.getTeamSlotLayout(team)
        end
        check(order(roster, true) == "1,2,4,5,6,3,7,8" and Panel.getResonanceLevel() == 10,
            "旁队共鸣夹具真实TOP5与旧level降序正确")
        local px, py, pressedIndex = rowPoint(6)
        Panel.handleDragBegin(px, py)
        resetExpCounts()
        check(Panel.addHeroExp(1, 1), "获奖英雄不升级也能触发旁队/bench共鸣")
        check(Panel.getOwnedHero(1).level == 10 and Panel.getOwnedHero(1).exp == 1
            and Panel.getOwnedHero(3).level == 10 and Panel.getOwnedHero(7).level == 10
            and Panel.getOwnedHero(8).level == 10, "全owned检测旁队与bench等级变化不只检查获奖hero")
        check(progressCounts.rebuild == 1 and progressCounts.refresh == 1 and progressCounts.nav == 1
            and progressCounts.light == 0 and contexts == 8 and dirty == 1 and #snapshots == 1,
            "旁队共鸣精确一次完整rebuild/穿戴评分refresh/角标/完整事件")
        check(synchronousCacheReads == 1 and snapshots[1].ready and #snapshots[1].powers == 3,
            "旁队共鸣完整事件同步读取heroId映射及三队ready正确")
        check(same(progressTeams, { { teams = { 3 }, classes = {} } })
            and same(Panel.getLastHeroesRefreshTeams(), { [3] = true }) and #layoutInvalidations == 0,
            "旁队共鸣只通知真实队3属性，不失效编队或借编辑队")
        check(Panel.getTotalPower(3) > priorTeam3Power, "旁队共鸣实际队3战力立即增长")
        for team = 1, 3 do
            local slots, values = Panel.getTeamSlotsData(team)
            check(same(Panel.getTeamSlotLayout(team), priorLayouts[team]), "旁队共鸣三队孔位不变 " .. team)
            if team < 3 then check(same(values, priorTeamPowers[team]), "未变等级队战力不被旁队共鸣污染 " .. team) end
            for _, slot in ipairs(slots) do
                if slot.state == "occupied" then
                    check(slot.level == Panel.getOwnedHero(slot.heroId).level,
                        "旁队共鸣真实槽位level同步 " .. team .. "/" .. slot.heroId)
                end
            end
        end
        for i, entry in ipairs(roster) do
            if entry.owned then
                local own = Panel.getOwnedHero(entry.heroId)
                check(entry.level == own.level and entry.exp == own.exp and entry.maxExp == own.maxExp
                    and cacheValues[i] == Panel.getRosterPower(entry.heroId),
                    "旁队共鸣全owned显示与正式缓存立即一致 " .. entry.heroId)
            end
        end
        check(order(roster) == priorOrder and sortSession.getRevision() == priorRevision
            and roster[pressedIndex].heroId == 6 and inputSession.isRosterInteractionBusy(),
            "旁队共鸣Down期间完整刷新但延迟level重排保住原索引")
        Panel.handleDragEnd(px, py); Panel.handleInput(px, py)
        check(detail.opened == 6, "旁队共鸣后Up不点到新level次序里的其他英雄")
        detail.visible, detail.opened = false, nil; Panel.update(0.016)
        check(order(roster, true) == "1,2,3,4,5,6,7,8" and sortSession.getRevision() == priorRevision + 1
            and contexts == 8 and #snapshots == 1 and actions == 0,
            "旁队共鸣Down结束精确一次level重排，不重复评分/事件或发送编队")
        for id = 1, 8 do
            local current = math.floor(oldBuild(id, { heroData = Panel.getOwnedHero(id), heroes = data.heroes,
                equipment = data.equipment, artifacts = data.artifacts, talents = data.talents }).currentPower + 0.5)
            check(Panel.getRosterPower(id) == current, "旁队共鸣穿戴缓存与完整库存oracle一致 " .. id)
        end
        data.heroes = savedHeroes
        Panel.setHeroesData(data.heroes); Panel.setRosterSort("power"); Panel.update(0.016)
        local signature = Panel.getTeamSignature(2)
        local ownedLevel = Panel.getOwnedHero(2).level
        Panel.destroyPresentation()
        check(Panel.getTeamSignature(2) == signature and Panel.getOwnedHero(2).level == ownedLevel
            and Panel.getRosterSort() == "power", "展示析构不重置玩家编队/拥有数据/排序mode")
        Panel.handleDragBegin(sortX, sortY); Panel.resetSessionData()
        Panel.handleDragEnd(sortX, sortY); Panel.handleInput(sortX, sortY)
        local mode, ascending = Panel.getRosterSort()
        check(mode == "default" and not ascending and not Panel.isHeroesDataApplied(), "reset清旧Down/default与水合ready")
        check(actions == 0, "排序专项全过程无编队/合成动作")
    end)
    EP.buildWornContext, require = oldWornBuild, oldRequire
    HC.setDefaultLitNodes(savedLit)
    if not ok then check(false, "真实Panel异常 " .. tostring(err)) end
end

function Start()
    local nativeRequire = require
    local sameModule = nativeRequire("ui.hud.popup.UpdateNoticePopup")
    print("[roster overlay probe] package.loaded UpdateNotice=" .. tostring(package.loaded["ui.hud.popup.UpdateNoticePopup"] == sameModule))
    local ok, err = pcall(function() pureSort(nativeRequire); realPanel(nativeRequire) end)
    if not ok then check(false, "专项异常 " .. tostring(err)) end
    print("[character_roster_sort_test] " .. (failures == 0 and "ALL PASS" or "FAILURES=" .. failures)
        .. " assertions=" .. checks)
    engine:Exit()
end
