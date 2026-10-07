-- 专项只读业务验证，采用 scaffold-2d 的 Start/Stop 生命周期，不初始化 UI/main/真实档。
-- cwd=/home/Maker/tutorial-onboarding-validation-20261006
-- /home/Maker/resource-dungeon-visual-validation-20261006/.cli/UrhoXRuntime
-- tests/tutorial_recruit_deploy_test.lua -tapcode_dir=/workspace
-- -tool_mode -nosound -graphicsheadless -validate -validate-frames=60 -validate-timeout=45
-- -validate-output=/home/Maker/tutorial-onboarding-validation-20261006/recruit-deploy-validate.json
-- 完整真实 TM/TavernPage/CharacterDeploy/CharacterInput/Draw2；Panel getter/名册命中
-- 仅抽完整闭包。动作、存储、动画、剧情与装饰均为显式内存替身。
-- 不执行其他旧测试，不把 mock 的成功事件冒充生产事件，不创建 GPU/截图。
local PROJECT = "/workspace"
local CWD = "/home/Maker/tutorial-onboarding-validation-20261006"
local TAG = "[tutorial_recruit_deploy_test] "
local ROOT = ""
for _, argument in ipairs(GetArguments()) do
    local root = argument:match("^%-tapcode_dir=(.+)$")
    if root then ROOT = root:gsub("/+$", "") end
end
local SOURCE_FILES = {
    ["config.TutorialConfig"] = PROJECT .. "/scripts/config/TutorialConfig.lua",
    ["config.GameConfig"] = PROJECT .. "/scripts/config/GameConfig.lua",
    ["config.GachaConfig"] = PROJECT .. "/scripts/config/GachaConfig.lua",
    ["config.UrGachaConfig"] = PROJECT .. "/scripts/config/UrGachaConfig.lua",
    ["core.DrawUtil"] = PROJECT .. "/scripts/core/DrawUtil.lua",
    ["systems.TutorialManager"] = PROJECT .. "/scripts/systems/TutorialManager.lua",
    ["ui.tavern.TavernPage"] = PROJECT .. "/scripts/ui/tavern/TavernPage.lua",
    ["ui.tavern.TavernRecruitOrders"] = PROJECT .. "/scripts/ui/tavern/TavernRecruitOrders.lua",
    ["ui.character.panel.CharacterDeploy"] = PROJECT .. "/scripts/ui/character/panel/CharacterDeploy.lua",
    ["ui.character.panel.CharacterInput"] = PROJECT .. "/scripts/ui/character/panel/CharacterInput.lua",
    ["ui.character.panel.CharacterPanelDraw2"] = PROJECT .. "/scripts/ui/character/panel/CharacterPanelDraw2.lua",
    ["ui.character.panel.CharacterPanel"] = PROJECT .. "/scripts/ui/character/panel/CharacterPanel.lua",
    ["core.I18nStory"] = PROJECT .. "/scripts/core/I18nStory.lua",
}
local FRAGMENTS_ONLY = { ["ui.character.panel.CharacterPanel"] = true }
local nativeFile, nativeCache = File, cache
local sources, reads, contexts = {}, {}, {} ---@type any
local checks, groups, failures = 0, 0, 0
local hostLoaded, hostGlobals = {}, {} ---@type any
local function check(ok, label) checks = checks + 1; assert(ok, label) end
local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, child in pairs(a) do if not same(child, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function noop() end
local function source(name)
    assert(ROOT == PROJECT, "wrong project root")
    local path = assert(SOURCE_FILES[name], "source name denied " .. tostring(name))
    assert(path:sub(1, #PROJECT + 9) == PROJECT .. "/scripts/" and path:sub(-4) == ".lua"
        and not path:find("..", 1, true), "fixed absolute Lua source only")
    if sources[name] then return sources[name] end
    -- cache 只在宿主读取已白名单化的脚本资源；不进入任何生产 env，不读玩家文件。
    local resource = path:sub(#PROJECT + 10)
    local file = assert(nativeCache:GetFile(resource), "source cache File unavailable " .. resource)
    local ok, text = pcall(function()
        assert(file:IsOpen(), "source open failed " .. resource)
        assert(file:GetMode() == FILE_READ, "source must be read-only " .. resource)
        local lines = {}; while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose(); assert(ok, text)
    sources[name] = text; reads[#reads + 1] = resource; return text
end
local function section(name, first, last)
    local text = source(name)
    local a = assert(text:find(first, 1, true), "fragment start missing " .. first)
    assert(not text:find(first, a + #first, true), "fragment start not unique " .. first)
    local b = assert(text:find(last, a + #first, true), "fragment end missing " .. last)
    return text:sub(a, b - 1)
end
local function topFunction(name, first)
    -- 顶层函数 end 不缩进；嵌套 end 均缩进，不截半个函数、不手抄被测函数。
    return section(name, first, "\nend\n") .. "\nend\n"
end
local function compile(text, name, env)
    local fn, why = load(text, "@" .. name, "t", env); assert(fn, why); return fn()
end
local function slots(ids)
    local result = {}
    for i = 1, 4 do
        local id = ids and (ids[i] or ids[tostring(i)])
        result[i] = id and tonumber(id) ~= 0 and { state = "occupied", heroId = id, level = 1 }
            or { state = "empty" }
    end
    return result
end

---@return any
local function newContext(options)
    options = options or {}
    local c = { env = {}, modules = {}, loading = {}, denied = {}, events = {}, persists = {},
        actions = {}, localPulls = {}, histories = {}, stories = {}, anims = {}, frames = {}, images = {},
        confirms = {}, messages = {}, recoveries = {}, teamChanges = {}, clock = { elapsedTime = 100 },
        activeTeam = options.activeTeam or 1, unlockedTeams = options.unlockedTeams or 3,
        drag = { active = false, moved = false }, selection = { active = false },
        scrolling = false, scroll = 0, scrollLastY = 0, scrollDelta = 0, velocity = 0,
        animPlaying = false, animPending = {}, animCallbacks = 0,
        allowConfirm = true, canPull = true, sendMode = "pending",
        callbackMode = "accept", nextResults = {}, font = 24, stack = 0,
        memory = { session = { claimedScenarios = {}, unrelatedLedger = { keep = 17 },
            tutorialProgress = { version = 1, completed = {}, queue = {} } },
            heroes = { roster = { [1] = { level = 1 }, [2] = { level = 1 }, [3] = { level = 1 } } },
            currency = { recruitTicket = 100, stellarRecruitTicket = 100, diamond = 100000,
                gachaPitySR = 0, gachaPitySSR = 0, urPityUR = 0 },
            battle = { maxStageId = 7001, clearedStages = {} } },
        teams = { { slots = slots({1, 2, 3, 0}) }, { slots = slots() }, { slots = slots() } },
        powers = { { 10, 20, 30, 0 }, {0, 0, 0, 0}, {0, 0, 0, 0} }, roster = {},
        unrelated = { marker = "never touch" }, detailOpened = 0, nav = 1, reward = false, story = false,
    } ---@type any
    contexts[#contexts + 1] = c
    local e = c.env
    local function deny(label)
        c.denied[#c.denied + 1] = label; error("strict recruit test denies " .. tostring(label))
    end
    c.deny = deny
    local function blocked(label)
        return setmetatable({}, { __index = function(_, key) return deny(label .. "." .. tostring(key)) end,
            __newindex = function(_, key) return deny(label .. "." .. tostring(key)) end })
    end
    local function mock(name, values)
        c.modules[name] = setmetatable(values, { __index = function(_, key)
            return deny("unmocked dependency " .. name .. "." .. tostring(key))
        end })
        return c.modules[name]
    end
    c.mock = mock
    for _, key in ipairs({"assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select",
        "tonumber", "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal"}) do e[key] = _G[key] end
    e.math, e.string, e.table, e.utf8 = copy(math), copy(string), copy(table), copy(utf8)
    e.math.random = function() return deny("RNG") end
    e.math.randomseed = function() return deny("RNG seed") end
    e._G, e.time, e.H_SEAM_BACK, e.H_TRI_L0 = e, c.clock, true, false
    e.graphics = { GetWidth = function() return 1458 end, GetHeight = function() return 1080 end,
        GetDPR = function() return 1 end }
    e.print = noop
    for key, value in pairs(_G) do
        if type(key) == "string" and (key:match("^NVG_") or key:match("^MOUSEB_")) then e[key] = value end
    end
    e.FILE_READ, e.FILE_WRITE = FILE_READ, FILE_WRITE
    e.File = function() return deny("File all paths/modes") end
    for _, key in ipairs({"io", "os", "package", "debug", "cache", "fileSystem", "engine",
        "network", "clientCloud", "serverCloud"}) do e[key] = blocked(key) end
    for _, key in ipairs({"load", "loadfile", "dofile", "GetFileSystem", "GetEngine", "SubscribeToEvent", "SendEvent"}) do
        e[key] = function() return deny(key) end
    end
    e.nvgCreateImage = function(_, path)
        assert(type(path) == "string" and path:sub(1, 6) == "image/" and not path:find("..", 1, true), "image spy resource path")
        c.images[#c.images + 1] = path; return #c.images
    end
    e.nvgImageSize = function() return 1080, 2400 end
    e.nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    e.nvgSave = function() c.stack = c.stack + 1 end
    e.nvgRestore = function() c.stack = c.stack - 1; assert(c.stack >= 0, "unbalanced nvgRestore") end
    e.nvgFontSize = function(_, size) c.font = size end
    e.nvgTextBounds = function(_, _, _, text) return (utf8.len(text) or #text) * c.font * 0.55 end
    e.nvgImagePattern = function() return {} end
    e.nvgImagePatternTinted = function() return {} end
    for _, key in ipairs({"nvgTranslate", "nvgScale", "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor",
        "nvgFillPaint", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFontFace", "nvgTextAlign",
        "nvgText", "nvgScissor", "nvgResetScissor", "nvgIntersectScissor", "nvgGlobalAlpha", "nvgFontBlur",
        "nvgCircle", "nvgShapeAntiAlias", "nvgSkewX"}) do e[key] = noop end
    mock("core.BattleLayout", {})
    mock("config.HeroConfig", { SHARD_DUPE_CONVERT = 10, SHARD_SYNTHESIZE_COST = 10,
        get = function(id) return { name = "hero" .. tostring(id) } end })
    mock("config.HeroAssetUtil", { ensureIcon = function(_, handles, id) handles[id] = 1; return 1 end })
    mock("config.ExpTable", {})
    mock("shared.Protocol", { ACTION_TYPES = { GACHA_PULL = "gacha_pull", TAVERN_SHOP_BUY = "tavern_shop_buy" } })
    mock("runtime.ClientDispatcher", { get = function(key) return c.memory[key] end,
        subscribe = function(name, callback) c.currencySubscriber = callback; eq(name, "currency", "only currency subscription") end })
    mock("core.GameState", { getRecruitTicket = function() return c.memory.currency.recruitTicket end,
        getStellarRecruitTicket = function() return c.memory.currency.stellarRecruitTicket end,
        getGems = function() return c.memory.currency.diamond end })
    mock("core.I18n", { t = function(text) return text end, get = function() return "zh_CN" end, lookup = function(text) return text end })
    mock("core.DarkIcon", { drawNine = noop })
    mock("core.HorizonBg", { draw = noop })
    mock("core.NumberUtil", { format = tostring })
    mock("systems.ButtonFeedback", { trigger = noop, begin = function() return false end, finish = noop })
    mock("systems.GameSFX", { play = noop, playUIMove = noop })
    mock("ui.widget.HeroFrame", { draw = function(_, opts) c.frames[#c.frames + 1] = copy(opts) end })
    mock("ui.hud.BottomNav", { setTabLocked = noop, setSelectedIndex = function(idx) c.nav = idx end,
        getSelectedIndex = function() return c.nav end })
    mock("ui.story.ScenarioDialogue", { isActive = function() return c.story end })
    mock("ui.hud.popup.RewardPopup", { isOpen = function() return c.reward end,
        currentPanel = function() return "right" end, currentRowTag = function() return nil end })
    -- 正式Input在首个手势缓存覆盖层引用；只显式提供只读API，不开放文件或未知依赖。
    for _, name in ipairs({ "ui.hud.popup.OfflineRewardPanel", "ui.hud.popup.LevelUpPopup",
        "ui.hud.popup.UpdateNoticePopup", "ui.hud.popup.PlayerInfoPanel", "ui.story.gate.DarkTitleScreenGate",
        "ui.story.gate.StartScreen", "ui.story.gate.LetterIntro", "ui.battle.popup.TerminalConfirmDialog",
        "ui.dungeon.DungeonBattleScene", "ui.dev.CEPanel" }) do
        mock(name, { isOpen = function() return false end })
    end
    mock("ui.story.gate.IntroCutscene", { isActive = function() return false end })
    mock("ui.tower.TowerBattleScene", { isActive = function() return false end })
    mock("systems.StoryPlayer", { onPlace = noop, followOf = function() return nil end })
    mock("ui.tutorial.TutorialOverlay", { layout = function(_, _, target)
        return { hole = target, skip = { cx = 10, cy = 10, w = 5, h = 5 } } end, draw = noop })
    mock("ui.battle.tri.BattleTriPage", { getTeamStageId = function(team)
        assert(team == 1, "recruit fixture only reads team1 stage")
        return 101
    end })
    mock("config.DungeonConfig", { decodeStageId = function(id)
        assert(id == 101, "recruit fixture only decodes main stage101")
        return nil
    end })
    mock("ui.tutorial.TutorialPageRecovery", { isBlocked = function() return c.blocked == true end,
        prepare = function(_, _, target, heroId, initial)
            c.recoveries[#c.recoveries + 1] = { target = target, heroId = heroId, initial = initial }
            return false -- 本专项只验证调度/真实事件；恢复动作由focused专项真实Recovery覆盖。
        end })
    mock("ui.character.hero.HeroScenario", { onRecruitResults = function(results)
        c.stories[#c.stories + 1] = copy(results) end })
    mock("ui.character.detail.CharacterDetail", { isOpen = function() return false end,
        open = function() c.detailOpened = c.detailOpened + 1 end })
    -- 新右栏装饰不属于招募业务；几何/输入仍执行完整正式Draw2。
    mock("ui.character.panel.CharacterRosterPresentation", { reset = noop, observe = noop,
        finishObservation = noop, drawHeader = noop, drawSort = noop,
        getFeedback = function() return false, false, 0, 0 end,
        hitTestSort = function() return nil end, setSortInteraction = noop,
        clearSortInteraction = noop, setTeamInteraction = noop, clearTeamInteraction = noop })
    mock("systems.GachaSystem", { canPull = function() return c.canPull, "ticket" end,
        setPityCounts = noop, getSSRPityRemain = function() return 80 end,
        pull = function(count, payType)
            c.localPulls[#c.localPulls + 1] = { count = count, payType = payType }
            if c.localFailure then return nil end
            c.grant(c.nextResults); return copy(c.nextResults) -- 内存结果/名册边界，不生成随机/扣券。
        end })
    mock("ui.tavern.TavernPopups", { init = noop,
        setContext = function(ctx) c.popupContext = ctx end,
        checkAndShowConfirm = function(count) c.confirms[#c.confirms + 1] = count; return c.allowConfirm end,
        isRecruitConfirmOpen = function() return c.confirmOpen == true end,
        isBlocking = function() return c.confirmOpen == true end,
        resetAll = function() c.confirmOpen = false end,
        showFloatText = function(text) c.messages[#c.messages + 1] = text end,
        recordHistory = function(results, pool) c.histories[#c.histories + 1] = { results = copy(results), pool = pool } end,
        formatGachaFailReason = tostring, update = noop, drawAll = noop, openInfo = noop,
        handleInput = function() return true end })
    mock("ui.tavern.RecruitAnim", { init = noop, setOnAgain = function(fn) c.again = fn end,
        isPlaying = function() return c.animPlaying end, update = noop, draw = noop,
        handleInput = function() return true end,
        start = function(results, callback, count, pool)
            c.animPlaying = true
            c.anims[#c.anims + 1] = { results = copy(results), finish = callback, count = count, pool = pool }
            c.animPending[#c.animPending + 1] = callback
        end,
        close = function()
            -- 与真实RecruitAnim一致：先释放忙碌状态并取走整批回调，再调用；重复关闭不重复消费。
            c.animPlaying = false
            local callbacks = c.animPending; c.animPending = {}
            for _, callback in ipairs(callbacks) do
                c.animCallbacks = c.animCallbacks + 1; callback()
            end
        end })
    mock("ui.tavern.TavernShopPage", { init = noop, resetScroll = noop, syncPurchasedFromStore = noop,
        isPendingBuy = function() return false end, update = noop, drawContent = noop,
        handleInput = function() return false end })
    mock("ui.tavern.TargetRecruitPanel", { init = noop, isOpen = function() return false end, close = noop, draw = noop })
    mock("ui.town.TownPageChrome", { easeOutCubic = function(t) return 1 - (1 - t)^3 end,
        easeInCubic = function(t) return t^3 end, hitBack = function() return false end,
        hitTab = function(x, y, items, w, h)
            for i, item in ipairs(items) do
                if c.modules["core.DrawUtil"].hitTest(x, y, item.cx, item.cy, w, h) then return i end
            end
            return nil
        end })
    e.require = function(name)
        if c.modules[name] ~= nil then return c.modules[name] end
        if FRAGMENTS_ONLY[name] then return deny("whole fragment-only module " .. name) end
        if not SOURCE_FILES[name] then return deny("unknown require " .. tostring(name)) end
        if c.loading[name] then return deny("circular require " .. name) end
        c.loading[name] = true
        local ok, value = pcall(compile, source(name), SOURCE_FILES[name], e)
        c.loading[name] = nil; if not ok then error(value) end
        assert(type(value) == "table", "real module must return table " .. name)
        c.modules[name] = value; return value
    end
    setmetatable(e, { __index = function(_, key) return deny("unknown global " .. tostring(key)) end,
        __newindex = function(_, key) return deny("unknown global assignment " .. tostring(key)) end })
    c.require = e.require
    c.grant = function(results)
        for _, result in ipairs(results) do
            if result.type == "hero" and result.isNew == true and tonumber(result.heroId) then
                c.memory.heroes.roster[tonumber(result.heroId)] = { level = 1, exp = 0, maxExp = 5 }
            end
        end
        c.rebuild()
        if c.syncPanel then c.syncPanel() end
    end
    c.rebuild = function()
        c.roster = {}
        for id, own in pairs(c.memory.heroes.roster) do
            if own.level and own.level > 0 then c.roster[#c.roster + 1] = { heroId = tonumber(id), owned = true, level = own.level } end
        end
        table.sort(c.roster, function(a, b) return a.heroId < b.heroId end)
    end
    c.rebuild()
    c.tm = c.require("systems.TutorialManager")
    c.store = { Get = function(key) return c.memory[key] end }
    c.tm.init({}, c.store, function(progress)
        c.memory.session.tutorialProgress = copy(progress); c.persists[#c.persists + 1] = copy(progress)
    end)
    local realNotify = c.tm.notifyEvent
    c.tm.notifyEvent = function(name) c.events[#c.events + 1] = name; return realNotify(name) end
    c.page = c.require("ui.tavern.TavernPage")
    c.page.init({}); c.page.open(); c.clock.elapsedTime = 101
    c.draw = c.require("ui.character.panel.CharacterPanelDraw2")

    -- 固定完整Panel getter/名册命中闭包，不 require 整Panel，不开放 debug.upvalue。
    local panelEnv = {}
    for key, value in pairs(e) do panelEnv[key] = value end
    panelEnv._G, panelEnv.CharacterPanel = panelEnv, {}
    panelEnv.MAX_SLOTS, panelEnv.TEAM_COUNT = 4, 3
    panelEnv.ownedSet = {}
    panelEnv.Draw, panelEnv.DESIGN_W, panelEnv.DESIGN_H = c.draw, 1080, 2400
    panelEnv.ROW1_CY, panelEnv.ROW_SPACING = c.draw.ROW1_CY, c.draw.ROW_SPACING
    panelEnv.MAX_PER_ROW, panelEnv.SCROLL_TOP, panelEnv.SCROLL_BOTTOM = c.draw.MAX_PER_ROW, c.draw.SCROLL_TOP, c.draw.SCROLL_BOTTOM
    panelEnv.teams, panelEnv.teamPowerCaches = c.teams, c.powers
    panelEnv.teamSlots, panelEnv.slotPowerCache = c.teams[c.activeTeam].slots, c.powers[c.activeTeam]
    panelEnv.heroRoster, panelEnv.scrollY = c.roster, c.scroll
    setmetatable(panelEnv, { __index = function(_, key) return deny("Panel fragment unknown global " .. tostring(key)) end,
        __newindex = function(_, key) return deny("Panel fragment global assignment " .. tostring(key)) end })
    c.syncPanel = function()
        panelEnv.teams, panelEnv.teamPowerCaches = c.teams, c.powers
        panelEnv.teamSlots, panelEnv.slotPowerCache = c.teams[c.activeTeam].slots, c.powers[c.activeTeam]
        panelEnv.heroRoster, panelEnv.scrollY = c.roster, c.scroll
        panelEnv.ownedSet = {}
        for id, own in pairs(c.memory.heroes.roster) do
            if tonumber(own.level) and tonumber(own.level) > 0 then panelEnv.ownedSet[tonumber(id)] = own end
        end
    end
    c.syncPanel()
    compile(topFunction("ui.character.panel.CharacterPanel", "function CharacterPanel.isOwned(heroId)")
        .. topFunction("ui.character.panel.CharacterPanel", "function CharacterPanel.getTeamSlotsData(")
        .. topFunction("ui.character.panel.CharacterPanel", "function CharacterPanel.getTeamSlotLayout(teamIdx)"),
        SOURCE_FILES["ui.character.panel.CharacterPanel"], panelEnv)
    c.panel = panelEnv.CharacterPanel
    c.panel.isHeroesDataApplied = function() return c.heroesReady ~= false end
    c.panel.getEffectiveLevel = function(id) local own = c.memory.heroes.roster[id]; return own and own.level or 1 end
    c.panel.setActiveTeam = function(idx)
        if idx < 1 or idx > c.unlockedTeams then return false end
        c.activeTeam = idx; c.syncPanel(); return true
    end
    c.panel.prepareTutorial = function() c.activeTeam = 1; c.syncPanel() end
    c.panel.requestSynthesizeHero = function() return deny("synthesis not in tested path") end
    c.modules["ui.character.panel.CharacterPanel"] = c.panel
    c.hitRoster = compile(topFunction("ui.character.panel.CharacterPanel", "local function hitTestRosterCard(dx, dy)")
        .. "\nreturn hitTestRosterCard", SOURCE_FILES["ui.character.panel.CharacterPanel"], panelEnv)
    c.draw.setContext({ getTeamSlots = function() return c.teams[c.activeTeam].slots end,
        getHeroRoster = function() return c.roster end, getSlotPowerCache = function() return c.powers[c.activeTeam] end,
        getRosterPowerCache = function() return {0,0,0,0,0,0,0,0} end,
        getDragState = function() return c.drag end, getSelectSlotState = function() return c.selection end,
        getHeroDeployTeams = function() return {} end, getUpgradeBadgeCache = function() return {} end,
        getActiveTeamIdx = function() return c.activeTeam end, getUnlockedTeamCount = function() return c.unlockedTeams end,
        getTeamOccupiedCounts = function() return {} end, getTeams = function() return c.teams end,
        getTeamPowerCaches = function() return c.powers end })
    c.onChanged = function(team, other)
        c.teamChanges[#c.teamChanges + 1] = { team = team, other = other, before = copy(c.teams) }
        check(not c.tm.isGroupCompleted(9), "business callback occurs before tutorial success")
        if c.callbackMode == "rollback" then c.teams = copy(c.acceptedTeams) end
        if c.callbackMode == "redirect" then
            c.teams = copy(c.acceptedTeams); c.teams[2].slots[4] = { state = "occupied", heroId = 18 }
        end
        c.syncPanel()
    end
    c.deploy = c.require("ui.character.panel.CharacterDeploy").bind({ HC = c.modules["config.HeroConfig"], MAX_SLOTS = 4, TEAM_COUNT = 3,
        getTeams = function() return c.teams end, getTeamSlots = function() return c.teams[c.activeTeam].slots end,
        getActiveTeamIdx = function() return c.activeTeam end, getOwnedSet = function() return c.memory.heroes.roster end,
        getTeamPowerCaches = function() return c.powers end, getSlotPowerCache = function() return c.powers[c.activeTeam] end,
        calcHeroPower = function() return 10 end,
        rebuildRoster = function() c.rebuild(); c.syncPanel() end,
        refreshPowerCache = noop, refreshNavBadge = noop, getOnTeamChanged = function() return c.onChanged end })
    c.input = c.require("ui.character.panel.CharacterInput").bind({ CharacterDetail = c.modules["ui.character.detail.CharacterDetail"],
        Draw = c.draw, CharacterPanel = c.panel, hitTestRosterCard = c.hitRoster,
        getTeamSlots = function() return c.teams[c.activeTeam].slots end, getSlotPowerCache = function() return c.powers[c.activeTeam] end,
        getDragState = function() return c.drag end, getSelectSlotState = function() return c.selection end,
        getTeams = function() return c.teams end, getTeamPowerCaches = function() return c.powers end,
        getHeroRoster = function() return c.roster end, getShardMap = function() return {} end,
        getActiveTeamIdx = function() return c.activeTeam end, getOnTeamChanged = function() return c.onChanged end,
        deployHeroToSlot = c.deploy.deployHeroToSlot,
        rebuildRoster = function() c.rebuild(); c.syncPanel() end, refreshPowerCache = noop, refreshNavBadge = noop,
        isHeroDeployed = function(id)
            for team = 1, 3 do for _, slot in ipairs(c.teams[team].slots) do
                if slot.state == "occupied" and tonumber(slot.heroId) == tonumber(id) then return true end
            end end
            return false
        end,
        isInScrollArea = function(x, y) return x >= 0 and x <= 1080 and y >= c.draw.SCROLL_TOP + c.draw.CONTENT_SHIFT_Y and y <= 2400 end,
        clampScroll = noop, getScroll = function() return c.scroll end, setScroll = function(v) c.scroll = v; c.syncPanel() end,
        getIsDragging = function() return c.scrolling end, setIsDragging = function(v) c.scrolling = v end,
        getDragLastY = function() return c.scrollLastY end, setDragLastY = function(v) c.scrollLastY = v end,
        getDragDeltaY = function() return c.scrollDelta end, setDragDeltaY = function(v) c.scrollDelta = v end,
        setScrollVelocity = function(v) c.velocity = v end, SCROLL_WHEEL_STEP = 80, HC = c.modules["config.HeroConfig"] })
    c.acceptedTeams = copy(c.teams)
    c.tm.update(0)
    c.tick = function(dt) c.clock.elapsedTime = c.clock.elapsedTime + dt; c.tm.update(dt) end
    c.finishAnim = function(index)
        local animation = assert(c.anims[index or #c.anims], "animation callback not captured")
        c.modules["ui.tavern.RecruitAnim"].close(); return animation.finish
    end
    c.send = function(mode)
        c.sendMode = mode or "pending"
        c.page.setSendAction(function(action, params)
            eq(action, "gacha_pull", "only recruit request through injected spy")
            c.actions[#c.actions + 1] = { action = action, params = copy(params) }
            check(c.page.isRecruitBusy(), "pending set before synchronous transport")
            if c.sendMode == "reject" then return false end
            if c.sendMode == "sync" then c.receipt(c.nextResults) end
            return true
        end)
    end
    c.receipt = function(results, opts)
        opts = opts or {}
        if opts.success ~= false and type(results) == "table" then c.grant(results); c.syncPanel() end
        c.page.onActionResult({ action = opts.action or "gacha_pull", success = opts.success ~= false,
            gachaResults = results, reason = "fixture", poolId = opts.poolId })
    end
    c.request = function(count)
        return c.page.handleInput(count == 1 and 314 or 766, 1902)
    end
    c.safebefore = copy({ currency = c.memory.currency, claims = c.memory.session.claimedScenarios,
        unrelated = c.unrelated, ledger = c.memory.session.unrelatedLedger, battle = c.memory.battle })
    return c
end

local function eventCount(c, name)
    local n = 0; for _, event in ipairs(c.events) do if event == name then n = n + 1 end end
    return n
end
local function queued(c, id)
    local n = 0; for _, group in ipairs(c.tm.getProgress().queue) do if group == id then n = n + 1 end end
    return n
end
local function audit(c)
    eq(#c.denied, 0, "production made no forbidden capability access")
    eq(c.stack, 0, "drawing save/restore balanced")
    check(same(c.safebefore, { currency = c.memory.currency, claims = c.memory.session.claimedScenarios,
        unrelated = c.unrelated, ledger = c.memory.session.unrelatedLedger, battle = c.memory.battle }), "unrelated/currency/claim ledger unchanged")
end
local function ownedResults()
    return { { type = "hero", heroId = 1, isNew = false }, { type = "dupe_to_shard", heroId = 2 },
        { type = "hero", heroId = 3 }, { type = "shard", heroId = 18, isNew = true },
        { type = "hero", heroId = 18, isNew = true }, { type = "hero", heroId = 19, isNew = true } }
end
local function begin8(c, state)
    if state == "active" then c.tm.startGroup(8); c.tick(0.6)
    elseif state == "queued" then c.reward = true; c.tm.onScenarioClaimed(31)
    else eq(c.tm.getCurrentGroup(), nil, "before any tutorial31") end
end
local function activate9(c)
    -- active8 首先0.2淡出，然后独立0.25quiet；非active8直接等quiet。
    c.reward, c.story, c.blocked = false, false, false
    c.tick(0.21); c.tick(0.249)
    if c.tm.getCurrentGroup() ~= 9 and not c.tm.isGroupCompleted(9) then c.tick(0.002) end
    eq(c.tm.getCurrentGroup(), 9, "first real recruitment auto starts group9 without leave/story32")
    c.tick(0.6)
    eq(c.tm.getCurrentHighlight(), "character_new_hero", "group9 correct newly owned card target")
end
local function armed9(c, id)
    c.memory.heroes.roster[id or 18] = { level = 1, exp = 0, maxExp = 5 }
    c.rebuild(); c.syncPanel(); c.tm.setNewHeroId(id or 18); c.tm.startGroup(9); c.tick(0.6)
    eq(c.tm.getCurrentGroup(), 9, "deployment fixture starts real group9")
    c.acceptedTeams = copy(c.teams)
end
local function drawnRoster(c, heroId)
    c.frames = {}; c.tm.clearHotspots(); c.draw.draw({}, c.scroll, false)
    local target = assert(c.tm.getCurrentHotspot(), "real Draw2 hotspot for selected result hero")
    local frame
    for _, value in ipairs(c.frames) do if value.heroId == heroId and value.nameLabel then frame = value end end
    check(frame ~= nil, "real Draw2 draws target roster entry")
    eq(target.cx, frame.cx + c.draw.CONTENT_SHIFT_X, "target x matches real card")
    eq(target.cy, frame.cy + c.draw.CONTENT_SHIFT_Y, "target y matches real card")
    eq(target.panel, "right", "new hero target in actual right panel")
    eq(c.hitRoster(target.cx, target.cy), (function()
        for index, entry in ipairs(c.roster) do if entry.heroId == heroId then return index end end
    end)(), "actual Panel hit closure matches draw target")
    return target.cx, target.cy
end
local function avatar(c, team, slot)
    c.frames = {}; c.draw.draw({}, c.scroll, false)
    local wanted = ({"前锋", "中锋", "中卫", "后卫"})[slot]
    local count = 0
    for _, frame in ipairs(c.frames) do
        if frame.posLabel == wanted then
            count = count + 1
            if count == team then
                local x, y = frame.cx + c.draw.CONTENT_SHIFT_X, frame.cy + c.draw.CONTENT_SHIFT_Y
                local actualTeam, actualSlot = c.draw.hitTestAvatarSlot(x, y)
                eq(actualTeam, team, "real avatar geometry team"); eq(actualSlot, slot, "real avatar geometry slot")
                return x, y
            end
        end
    end
    error("real avatar frame missing")
end
local function drag(c, x, y, dx, dy)
    c.input.handleDragBegin(x, y); c.input.handleDragMove(x + 31, y)
    check(c.drag.active, "real Input arms drag after movement threshold")
    c.input.handleDragMove(dx, dy); c.input.handleInput(dx, dy); c.input.handleDragEnd(dx, dy)
    check(not c.drag.active and c.drag.heroId == nil and c.drag.fromSlot == nil and c.drag.fromTeam == nil, "real Input clears drag state after drop")
end

local function safetyCases()
    local c = newContext()
    local probes = {
        function() c.require("main") end, function() c.require("boot.StandaloneSave") end,
        function() c.require("core.PlayerStore") end, function() c.require("runtime.GameAction") end,
        function() c.require("runtime.LocalActionBridge") end, function() c.require("ui.character.panel.CharacterPower") end,
        function() c.require("unknown.Module") end, function() c.env.File("player_save.json", FILE_READ) end,
        function() c.env.File("save.json", FILE_WRITE) end, function() c.env.cache:GetFile("main.lua") end,
        function() c.env.clientCloud:Get("player") end, function() c.env.serverCloud:Set("player", {}) end,
        function() c.env.fileSystem:CreateDir("saves") end, function() c.env.network:Connect() end,
        function() c.env.load("return _G") end, function() c.env.loadfile("main.lua") end,
        function() c.env.dofile("main.lua") end, function() return c.env.missingGlobal end,
        function() c.env.missingGlobal = 1 end, function() c.modules["systems.GachaSystem"].unexpected() end,
        function() c.env.package.loaded.main = true end,
    }
    for index, probe in ipairs(probes) do
        local before = #c.denied; check(not pcall(probe), "danger rejected " .. index)
        eq(#c.denied, before + 1, "denial logged even if pcall catches " .. index)
    end
    c.denied = {}; audit(c)
    local other = newContext()
    check(other.tm ~= c.tm and other.page ~= c.page and other.draw ~= c.draw, "each case own real module cache/env")
    local snapshot = c.tm.getProgress(); snapshot.completed["9"] = true; snapshot.queue[1] = 9
    check(not c.tm.isGroupCompleted(9) and queued(c, 9) == 0, "TM snapshots detached")
    audit(other)
end
local function configAndGetterCases()
    local c = newContext({activeTeam = 2})
    local config = c.require("config.TutorialConfig")
    eq(config[9].steps[1].advanceOn, "drag_to_slot_4", "only rear slot4 completion event")
    check(config[9].steps[1].text:find("4", 1, true) and config[9].steps[1].text:find("后卫", 1, true), "slot4 rear guard prompt")
    for _, sid in ipairs({32, 33, 34}) do eq(config.SCENARIO_TO_GROUP[sid], 9, "legacy tavern leave mapping retained " .. sid) end
    local current, currentPower = c.panel.getTeamSlotsData()
    eq(current, c.teams[2].slots, "getter no argument retains active team"); eq(currentPower, c.powers[2], "getter no argument retains cache")
    local main, mainPower = c.panel.getTeamSlotsData(1)
    eq(main, c.teams[1].slots, "explicit team1 ignores active team2"); eq(mainPower, c.powers[1], "explicit matching team cache")
    eq(c.activeTeam, 2, "read-only getter does not switch editing team")
    c.teams[3].slots[4] = { state = "occupied", heroId = "18" }; c.syncPanel()
    eq(c.panel.getTeamSlotLayout(3)[4], "18", "real getter preserves string hero id in correct slot4")
    eq(c.panel.getTeamSlotLayout(1)[4], 0, "explicit team1 getter never borrows team3")
    check(c.panel.isOwned(1) and not c.panel.isOwned(18), "real isOwned uses normalized valid ownedSet only")
    audit(c)
end
local function recruitSuccessCases()
    for _, transport in ipairs({"local", "pending", "sync"}) do
        for _, count in ipairs({1, 10}) do
            for _, groupState in ipairs({"active", "queued", "absent"}) do
                local c = newContext(); begin8(c, groupState); c.nextResults = ownedResults()
                if transport ~= "local" then c.send(transport) end
                c.request(count)
                if transport == "pending" then
                    eq(#c.anims, 0, "deferred request no premature results animation")
                    check(not c.tm.isGroupCompleted(8) and queued(c, 9) == 0, "started is not completion")
                    c.receipt(c.nextResults)
                end
                eq(#c.anims, 1, "real Page calls one animation")
                eq(c.anims[1].pool, "standard", "real request default standard pool")
                local sends = #c.actions + #c.localPulls
                c.request(count); eq(#c.actions + #c.localPulls, sends, "playing animation blocks repeat button")
                c.tick(1); check(c.tm.getCurrentGroup() ~= 9, "busy animation never starts group9")
                c.finishAnim()
                eq(c.tm.getNewHeroId(), 18, "only first genuinely new hero selected, not old/missing-isNew/shard")
                check(c.tm.isGroupCompleted(8), "real successful first recruitment satisfies group8 without reconsumption")
                eq(queued(c, 9), 1, "one automatic group9 queued before story32")
                eq(#c.stories, 1, "real Page animation callback retains HeroScenario delivery")
                activate9(c); drawnRoster(c, 18)
                local target = c.tm.getNewHeroId(); c.nextResults = { {type = "hero", heroId = 25, isNew = true} }
                c.page.forceClose(); c.page.open(); c.clock.elapsedTime = c.clock.elapsedTime + 1
                c.request(count); if transport == "pending" then c.receipt(c.nextResults) end
                c.finishAnim(); eq(c.tm.getNewHeroId(), target, "later recruitment cannot overwrite active9 target")
                eq(queued(c, 9), 0, "active9 never duplicated into queue")
                audit(c)
            end
        end
    end
end
local function recruitCloseCases()
    for _, mode in ipairs({"forceClose", "close"}) do
        for _, timing in ipairs({"after-result", "in-flight"}) do
            local c = newContext(); begin8(c, "active"); c.send(); c.request(10)
            if timing == "in-flight" then
                c.page[mode](); c.page[mode]()
                check(c.page.isRecruitBusy(), "closing must preserve in-flight request " .. mode)
            end
            local savedBefore = #c.persists
            c.receipt(ownedResults())
            eq(#c.persists, savedBefore + 1, "recruit8 and queued9 saved in one snapshot " .. mode .. timing)
            local saved = c.persists[#c.persists]
            check(saved.completed["8"] and saved.newHeroId == 18 and same(saved.queue, {9}),
                "first success save contains completed8 and actual target/queue9")
            if timing == "after-result" then
                check(c.page.isRecruitBusy() and c.animPlaying, "visible result stays busy before close")
                eq(#c.stories, 0, "HeroScenario waits for visible result close callback")
                c.tick(1); check(c.tm.getCurrentGroup() ~= 9, "result animation gates queued9")
                c.page[mode](); c.page[mode]()
            end
            eq(#c.anims, timing == "after-result" and 1 or 0, "closed/closing receipt starts no hidden animation")
            eq(c.animCallbacks, timing == "after-result" and 1 or 0, "result close callback consumed once")
            check(not c.animPlaying and not c.page.isRecruitBusy(), "close clears result/request busy " .. mode .. timing)
            eq(#c.stories, 1, "successful result reaches HeroScenario exactly once")
            c.modules["ui.tavern.RecruitAnim"].close()
            eq(#c.stories, 1, "idle animation close does not repeat old callback")
            if mode == "close" then
                c.clock.elapsedTime = c.clock.elapsedTime + 0.4
                eq(c.page.getAnimProgress(), 0, "ordinary close reaches end of page transition")
            else check(not c.page.isOpen(), "forceClose closes page immediately") end
            eq(queued(c, 9), 1, "close retains one actual new-hero tutorial")
            activate9(c); audit(c)
        end
    end
end
local function duplicateAndPriorityCases()
    local c = newContext(); begin8(c, "queued"); c.send(); c.nextResults = ownedResults()
    c.request(10); c.receipt(c.nextResults); local callback = c.finishAnim()
    local progress = copy(c.tm.getProgress()); local before = #c.persists
    callback(); check(same(c.tm.getProgress(), progress), "duplicate real animation callback no new tutorial state")
    eq(#c.persists, before, "duplicate callback no extra tutorial persist")
    for _, gate in ipairs({"reward", "story", "blocked"}) do
        c.reward, c.story, c.blocked = false, false, false; c[gate] = true; c.tick(2)
        check(c.tm.getCurrentGroup() ~= 9 and queued(c, 9) == 1, "queued9 waits priority " .. gate)
    end
    c.reward, c.story, c.blocked = false, false, false
    c.tick(0.249); check(c.tm.getCurrentGroup() ~= 9, "continuous quiet 0.249 still waits")
    c.tick(0.002); eq(c.tm.getCurrentGroup(), 9, "continuous quiet >=0.25 activates auto9")
    for _, sid in ipairs({32, 33, 34, 32}) do c.tm.onScenarioClaimed(sid) end
    eq(queued(c, 9), 0, "legacy claim cannot double-queue active9")
    audit(c)
    local queuedTarget = newContext(); queuedTarget.send(); queuedTarget.request(1); queuedTarget.receipt(ownedResults()); queuedTarget.finishAnim()
    eq(queued(queuedTarget, 9), 1, "precondition queued9")
    queuedTarget.nextResults = {{type="hero",heroId=25,isNew=true}}
    queuedTarget.request(1); queuedTarget.receipt(queuedTarget.nextResults); queuedTarget.finishAnim()
    eq(queuedTarget.tm.getNewHeroId(), 18, "later recruitment cannot overwrite queued9 target")
    eq(queued(queuedTarget, 9), 1, "later successful recruitment queue dedup")
    audit(queuedTarget)
end
local function allDuplicateCases()
    local results = { {type="hero",heroId=1,isNew=false}, {type="dupe_to_shard",heroId=18},
        {type="hero",heroId=2}, {type="shard",heroId=19,isNew=true}, {type="resource",amount=1} }
    for _, transport in ipairs({"local", "pending", "sync"}) do
        for _, count in ipairs({1,10}) do
            local c = newContext(); begin8(c,"active"); c.tm.setNewHeroId(99); c.nextResults = results
            if transport ~= "local" then c.send(transport) end
            c.request(count); if transport == "pending" then c.receipt(results) end
            c.finishAnim()
            eq(c.tm.getNewHeroId(), nil, "all duplicate pull clears stale target")
            check(c.tm.isGroupCompleted(8) and c.tm.isGroupCompleted(9), "all duplicate first recruitment marks9 skipped")
            eq(queued(c,9), 0, "all duplicate never queues nonexistent card")
            c.tick(0.3); c.tick(1); check(not c.tm.isActive(), "all duplicate no deadlocked drag tutorial")
            for _, sid in ipairs({32,33,34}) do c.tm.onScenarioClaimed(sid) end
            eq(queued(c,9),0,"legacy story cannot resurrect duplicate skip")
            c.nextResults = {{type="hero",heroId=25,isNew=true}}
            c.request(count); if transport == "pending" then c.receipt(c.nextResults) end; c.finishAnim()
            eq(c.tm.getNewHeroId(), nil, "completed9 not overwritten by later new pull")
            eq(queued(c,9),0,"completed9 not restarted")
            audit(c)
        end
    end
    local c = newContext(); begin8(c,"active"); c.send(); c.request(1); c.receipt(ownedResults()); c.finishAnim(); activate9(c)
    local x,y=drawnRoster(c,18); local dx,dy=avatar(c,1,4); drag(c,x,y,dx,dy); c.tick(0.3)
    eq(c.tm.getNewHeroId(),18,"completed9 keeps selected target for historical progress")
    c.request(1); c.receipt({{type="hero",heroId=25,isNew=true}}); c.finishAnim()
    eq(c.tm.getNewHeroId(),18,"later real recruitment cannot overwrite completed9 nonnil target")
    check(c.tm.isGroupCompleted(9) and queued(c,9)==0 and not c.tm.isActive(),"later recruitment never restarts completed9")
    audit(c)
end
local function failureCases()
    for _, count in ipairs({1,10}) do
    for _, failure in ipairs({"reject", "server", "missing", "empty", "timeout", "disconnect", "local"}) do
        local c = newContext(); begin8(c,"active"); c.nextResults = ownedResults()
        if failure == "local" then c.localFailure = true else c.send(failure == "reject" and "reject" or "pending") end
        c.request(count)
        if failure == "server" then c.receipt(nil,{success=false})
        elseif failure == "missing" then c.receipt(nil)
        elseif failure == "empty" then c.receipt({})
        elseif failure == "timeout" then c.clock.elapsedTime = c.clock.elapsedTime + 8; c.page.update(0)
        elseif failure == "disconnect" then c.page.onServerDisconnect() end
        check(not c.tm.isGroupCompleted(8) and not c.tm.isGroupCompleted(9), "failure doesn't complete tutorial " .. failure)
        eq(queued(c,9),0,"failure no auto9 " .. failure)
        eq(c.tm.getCurrentHighlight(),"tavern_btn_gacha10","failure restores actual retry target " .. failure)
        eq(#c.anims,0,"failure no success animation " .. failure)
        if failure == "timeout" or failure == "disconnect" then
            c.receipt(ownedResults()); if #c.anims > 0 then c.finishAnim() end
            check(not c.tm.isGroupCompleted(8) and queued(c,9)==0,"late unassociated result cannot complete after " .. failure)
        end
        audit(c)
    end
    end
    local c = newContext(); begin8(c,"active"); c.send()
    c.allowConfirm=false; c.request(10); eq(#c.actions,0,"cancelled confirm sends nothing")
    eq(eventCount(c,"gacha10_started"),0,"cancelled confirm no started")
    c.allowConfirm,c.canPull=true,false; c.request(10); eq(#c.actions,0,"no funds sends nothing")
    eq(eventCount(c,"gacha10_started"),0,"no funds no started")
    c.canPull=true; c.request(10); c.receipt(ownedResults(),{action="claim_offline_rewards"})
    check(c.page.isRecruitBusy() and queued(c,9)==0,"unrelated receipt preserves pending, no tutorial success")
    c.receipt(ownedResults()); c.finishAnim(); activate9(c); audit(c)
    local orphan = newContext(); orphan.send(); orphan.receipt(ownedResults())
    if #orphan.anims>0 then orphan.finishAnim() end
    check(not orphan.tm.isGroupCompleted(8) and not orphan.tm.isGroupCompleted(9) and queued(orphan,9)==0,"orphan success never invents first recruit")
    orphan.tm.onRecruitCompleted(ownedResults(),10)
    check(not orphan.tm.isGroupCompleted(8) and queued(orphan,9)==0,"TM API requires actual in-flight started receipt")
    audit(orphan)
end
local function startEligibilityCases()
    for _, case in ipairs({"missing", "zero", "shardOnly", "team1", "team2", "team3", "occupied4", "locked4"}) do
        local c=newContext({activeTeam=2}); c.tm.setNewHeroId(18)
        if case=="zero" then c.memory.heroes.roster[18]={level=0}
        elseif case=="shardOnly" then c.memory.heroes.roster[18]={shards=10}
        elseif case~="missing" then c.memory.heroes.roster[18]={level=1} end
        if case:match("^team") then c.teams[tonumber(case:sub(-1))].slots[4]={state="occupied",heroId=18,level=1}
        elseif case=="occupied4" then c.teams[1].slots[4]={state="occupied",heroId=2,level=1}
        elseif case=="locked4" then c.teams[1].slots[4]={state="locked"} end
        c.syncPanel(); local before=copy(c.teams); c.tm.startGroup(9)
        check(c.tm.isGroupCompleted(9) and not c.tm.isActive(),"invalid/deployed/full/locked target skips " .. case)
        check(same(c.teams,before),"eligibility never auto-deploys/replaces " .. case)
        eq(#c.teamChanges,0,"eligibility no formation callback " .. case)
        audit(c)
    end
    local c=newContext(); c.memory.heroes.roster["18"]={level=1}; c.rebuild(); c.syncPanel(); c.tm.setNewHeroId("18"); c.tm.startGroup(9)
    eq(c.tm.getCurrentGroup(),9,"string-key genuinely owned new hero still tutorial eligible"); audit(c)
end
local function localizedCases()
    local c=newContext(); local prompt=c.require("config.TutorialConfig")[9].steps[1].text
    local dictionary=c.require("core.I18nStory")
    for _, lang in ipairs({"zh_TW","en","ja","ko"}) do
        local translated=dictionary.lookup(prompt,lang)
        check(type(translated)=="string" and translated~="" and translated~=prompt,"actual slot4 prompt translated " .. lang)
        check(translated:find("4",1,true)~=nil,"translated prompt retains data slot4 " .. lang)
    end
    eq(c.require("config.TutorialConfig")[9].steps[1].text,prompt,"dictionary never mutates source tutorial text")
    audit(c)
end
local function realDeploymentCases()
    for _, path in ipairs({"rosterDrag", "emptySlotSelect"}) do
        for _, outcome in ipairs({"accept", "rollback", "redirect"}) do
            local c=newContext(); armed9(c); c.callbackMode=outcome
            local x,y=drawnRoster(c,18); local dx,dy=avatar(c,1,4)
            if path=="rosterDrag" then drag(c,x,y,dx,dy)
            else c.input.handleInput(dx,dy); c.input.handleInput(x,y) end
            eq(#c.teamChanges,1,"real " .. path .. " callback once")
            eq(c.tm.isGroupCompleted(9),outcome=="accept","tutorial checks callback readback " .. path .. "/" .. outcome)
            eq(eventCount(c,"drag_to_slot_4"),outcome=="accept" and 1 or 0,"only successful actual slot4 emits production event")
            local layout=c.panel.getTeamSlotLayout(1)
            eq(layout[1],1,"starter1 retained"); eq(layout[2],2,"starter2 retained"); eq(layout[3],3,"starter3 retained")
            eq(layout[4],outcome=="accept" and 18 or 0,"actual layout slot4 reflects receipt")
            if outcome=="accept" then
                c.tm.notifyHeroDeployed(18,1,4); eq(eventCount(c,"drag_to_slot_4"),1,"duplicate success cannot complete again")
            end
            audit(c)
        end
    end
    for _, destination in ipairs({{1,3},{2,4},{3,4}}) do
        local c=newContext(); armed9(c); local x,y=drawnRoster(c,18); local dx,dy=avatar(c,destination[1],destination[2])
        drag(c,x,y,dx,dy)
        check(not c.tm.isGroupCompleted(9),"wrong slot/team never completes9")
        eq(eventCount(c,"drag_to_slot_4"),0,"wrong team/slot no successful target event"); audit(c)
    end
    local c=newContext(); armed9(c)
    local x,y=drawnRoster(c,18); c.input.handleInput(x,y)
    eq(c.detailOpened,0,"real Input blocks click opening target instead of drag"); check(not c.tm.isGroupCompleted(9),"target click not successful deployment")
    c.teams[1].slots[4]={state="locked"}; c.syncPanel()
    eq(c.deploy.deployHeroToSlot(18,4),false,"locked deployment rejected"); eq(#c.teamChanges,0,"locked no callback")
    eq(c.deploy.deployHeroToSlot(999,4),false,"unowned deployment rejected"); check(not c.tm.isGroupCompleted(9),"rejection doesn't complete9")
    audit(c)
end
local function realSwapCases()
    for _, outcome in ipairs({"accept", "rollback"}) do
        for _, sourceTeam in ipairs({1,2}) do
            local c=newContext(); armed9(c)
            c.teams[sourceTeam].slots[sourceTeam==1 and 3 or 1]={state="occupied",heroId=18,level=1}
            c.syncPanel(); c.acceptedTeams=copy(c.teams); c.callbackMode=outcome
            local x,y=avatar(c,sourceTeam,sourceTeam==1 and 3 or 1); local dx,dy=avatar(c,1,4)
            drag(c,x,y,dx,dy)
            eq(#c.teamChanges,1,"real slot movement/swap callback exactly once")
            eq(c.tm.isGroupCompleted(9),outcome=="accept","real Input validates after synchronous callback " .. outcome)
            eq(eventCount(c,"drag_to_slot_4"),outcome=="accept" and 1 or 0,"real Input success event gated by readback")
            audit(c)
        end
    end
    local c=newContext(); armed9(c); c.teams[1].slots[4]={state="occupied",heroId=18}; c.syncPanel()
    c.tm.notifyHeroDeployed(1,1,4); c.tm.notifyHeroDeployed(18,2,4); c.tm.notifyHeroDeployed(18,1,3)
    check(not c.tm.isGroupCompleted(9),"central verifier rejects wrong hero/team/slot even when target occupied")
    eq(eventCount(c,"drag_to_slot_4"),0,"central mismatches produce no production success event"); audit(c)
end
local function persistenceCases()
    local c=newContext(); c.send(); c.request(1); c.receipt(ownedResults()); c.finishAnim()
    eq(queued(c,9),1,"save has automatically queued9")
    local saved=copy(c.memory.session.tutorialProgress); local before=copy(c.teams)
    c.tm.init({},c.store,function(progress) c.memory.session.tutorialProgress=copy(progress); c.persists[#c.persists+1]=copy(progress) end)
    c.tick(0); eq(queued(c,9),1,"real init/restore retains queue9")
    eq(c.tm.getNewHeroId(),18,"real init/restore retains new hero target")
    c.tick(0.249); check(not c.tm.isActive(),"restored queue respects quiet"); c.tick(0.002); eq(c.tm.getCurrentGroup(),9,"restored queue resumes group9")
    check(same(c.teams,before),"resume never modifies lineup")
    local x,y=drawnRoster(c,18); local dx,dy=avatar(c,1,4); drag(c,x,y,dx,dy); c.tick(0.3)
    check(c.tm.isGroupCompleted(9),"actual successful deployment persisted")
    eq(saved.completed["9"],nil,"saved queued snapshot not retro-mutated")
    c.tm.init({},c.store,function(progress) c.memory.session.tutorialProgress=copy(progress) end); c.tick(0)
    check(c.tm.isGroupCompleted(9) and not c.tm.isActive(),"completed9 readback no repeat teaching")
    for _, sid in ipairs({32,33,34}) do c.tm.onScenarioClaimed(sid) end
    eq(queued(c,9),0,"legacy claim after reload cannot resurrect9"); audit(c)
end
local function delayedHeroesReadyCases()
    for _, entry in ipairs({"direct", "restored", "queued"}) do
        local c=newContext(); c.heroesReady=false; c.blocked=true -- 标题fade遮挡的纯内存优先级标记。
        c.teams[1].slots[4]={state="locked"}; c.syncPanel()
        if entry=="direct" then
            c.tm.setNewHeroId(18); c.tm.startGroup(9)
            eq(queued(c,9),1,"not-ready direct9 retained in queue")
        elseif entry=="restored" then
            c.memory.session.tutorialProgress={version=1,completed={["8"]=true},queue={10},group=9,step=1,newHeroId=18}
            c.tm.init({},c.store,function(progress)
                c.memory.session.tutorialProgress=copy(progress); c.persists[#c.persists+1]=copy(progress)
            end)
            c.tick(0)
            eq(queued(c,9),1,"not-ready restore converts saved active9 into durable retry queue")
            eq(c.memory.session.tutorialProgress.queue[1],9,"restore persists queued9 instead of default locked skip")
            eq(c.tm.getProgress().queue[2],10,"restored active9 retains priority ahead of previously queued10")
        else
            c.tm.setNewHeroId(18); c.tm.onScenarioClaimed(32)
            eq(queued(c,9),1,"not-ready legacy32 enqueues9")
        end
        local before=copy(c.teams)
        for _=1,3 do c.tick(0.3) end
        check(not c.tm.isGroupCompleted(9) and not c.tm.isActive(),"title fade/data delay never mis-skips9 " .. entry)
        check(same(c.teams,before),"not-ready checks never mutate locked default lineup " .. entry)
        c.blocked=false -- 标题已收起，但真实heroes数据仍未推到Panel。
        for _=1,3 do c.tick(0.3) end
        check(not c.tm.isGroupCompleted(9) and not c.tm.isActive(),"no title but no heroes still waits " .. entry)
        eq(c.tm.getNewHeroId(),18,"retry preserves original recruit target " .. entry)
        eq(queued(c,9),1,"failed queue pop reinserts exactly once " .. entry)
        if entry=="restored" then
            check(same(c.tm.getProgress().queue,{9,10}),"not-ready queue retry keeps saved active9 before10")
            eq(queued(c,10),1,"not-ready restore doesn't lose following10")
        end
        eq(#c.teamChanges,0,"not-ready validation sends no formation transaction")
        -- 模拟真实setHeroesData交付：本次目标成为owned，slot4由默认locked改为实际empty。
        c.memory.heroes.roster[18]={level=1}; c.rebuild()
        c.teams[1].slots[4]={state="empty"}; c.heroesReady=true; c.syncPanel()
        for _=1,3 do if c.tm.getCurrentGroup()~=9 then c.tick(0.3) end end
        eq(c.tm.getCurrentGroup(),9,"delayed actual heroes data resumes9 " .. entry)
        check(not c.tm.isGroupCompleted(9),"ready starts operation, not fake deployment success")
        eq(queued(c,9),0,"readiness consumes queue once " .. entry)
        c.tick(0.6); local x,y=drawnRoster(c,18); local dx,dy=avatar(c,1,4)
        drag(c,x,y,dx,dy)
        check(c.tm.isGroupCompleted(9),"only subsequent real Input/Deploy completes delayed9 " .. entry)
        eq(eventCount(c,"drag_to_slot_4"),1,"delayed9 successful production event exactly once")
        if entry=="restored" then
            eq(c.tm.getProgress().queue[1],10,"successful restored9 still preserves queued10 for next tutorial")
            check(not c.tm.isGroupCompleted(10),"following10 not fabricated completed during delayed9")
        end
        audit(c)
    end
end
local function finalAudit()
    for _, c in ipairs(contexts) do audit(c) end
    for key,value in pairs(hostLoaded) do eq(package.loaded[key],value,"host loaded original " .. key) end
    for key,value in pairs(package.loaded) do eq(hostLoaded[key],value,"no host module added " .. key) end
    for key,value in pairs(hostGlobals) do
        local actual=_G[key]; check(actual==value or type(actual)=="number" and type(value)=="number" and actual~=actual and value~=value,"host global unchanged " .. tostring(key))
    end
    for key,value in pairs(_G) do
        local actual=hostGlobals[key]; check(actual==value or type(actual)=="number" and type(value)=="number" and actual~=actual and value~=value,"no host global added " .. tostring(key))
    end
    for _, resource in ipairs(reads) do
        local allowed=false; for _, permitted in pairs(SOURCE_FILES) do
            if resource==permitted:sub(#PROJECT+10) then allowed=true end
        end
        check(allowed,"cache read exact allowlisted script resource " .. resource)
    end
    eq(File,nativeFile,"native File unchanged")
    eq(cache,nativeCache,"native cache unchanged")
    check(#contexts>0 and #reads>0,"actual production loaded under strict capability audit")
end
local function runCase(label, fn)
    groups=groups+1; local ok,why=pcall(fn)
    if ok then print(TAG .. "[PASS] " .. label)
    else failures=failures+1; local text=TAG .. "[FAIL] " .. label .. " " .. tostring(why)
        print(text); log:Write(LOG_ERROR,text)
    end
end
function Start()
    hostLoaded,hostGlobals={},{}
    for key,value in pairs(package.loaded) do hostLoaded[key]=value end
    for key,value in pairs(_G) do hostGlobals[key]=value end
    eq(ROOT,PROJECT,"exact intended project root")
    eq(fileSystem:GetCurrentDir():gsub("/+$",""),CWD,"isolated validation cwd mandatory before source IO")
    runCase("strict-loader-denials-independent-env-deepcopy",safetyCases)
    runCase("config9-rear4-legacy-map-and-real-Panel-getters",configAndGetterCases)
    runCase("real-Tavern-local-deferred-sync-single-ten-active-queued-absent8",recruitSuccessCases)
    runCase("real-Tavern-close-forceClose-result-inflight-callback-once-and-auto9",recruitCloseCases)
    runCase("real-animation-callback-duplicate-and-quiet-priority-dedup",duplicateAndPriorityCases)
    runCase("all-duplicate-newness-stale-target-and-completed-skip",allDuplicateCases)
    runCase("request-failure-timeout-disconnect-orphan-no-premature9",failureCases)
    runCase("real-TM-start-owned-deployed-full-locked-eligibility",startEligibilityCases)
    runCase("real-slot4-prompt-four-language-I18n",localizedCases)
    runCase("real-Input-Deploy-card-geometry-slot4-after-callback-rejection",realDeploymentCases)
    runCase("real-Input-same-cross-team-swap-after-callback-readback",realSwapCases)
    runCase("real-TM-queued-active-completed-save-readback",persistenceCases)
    runCase("real-TM-cold-direct-restored-queued9-delayed-heroes-readiness",delayedHeroesReadyCases)
    runCase("all-contexts-global-package-and-source-audit",finalAudit)
    print(TAG .. "RESULT " .. (failures==0 and "ALL PASS" or "FAIL") .. " groups=" .. groups .. " checks=" .. checks .. " failures=" .. failures)
    if failures>0 then log:Write(LOG_ERROR,TAG .. "validation assertions failed=" .. failures) end
    -- validate帧预算负责退出/写报告；不engine:Exit、不将退出码等同断言通过。
end
function Stop() end
