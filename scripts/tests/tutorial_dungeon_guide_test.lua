-- 独立strict专项；沿用scaffold-2d Start/Stop生命周期，不启动游戏/main/真实存档。
-- cwd MUST be /home/Maker/tutorial-onboarding-validation-20261006.
-- /home/Maker/resource-dungeon-visual-validation-20261006/.cli/UrhoXRuntime tests/tutorial_dungeon_guide_test.lua
-- -tapcode_dir=/workspace -tool_mode -nosound -graphicsheadless
-- -validate -validate-frames=60 -validate-timeout=45 -validate-output=<isolated cwd>/dungeon-guide.json
-- 可选 -dungeon-guide-review=gold：真实Dialog/Overlay/PNG，纯NanoVG，生产BTP放大变换。
-- review使用-graphicssurfaceless -screenshot=<isolated cwd>/dungeon-guide.png -screenshot-frame=120 -x 1920 -y 1080。
-- 真实TM/Recovery/Config/Dialog/Resources/Overlay/Viewport/HorizonInput；BTP只执行明确完整闭包。
-- Driver:start、Scene.gotoStage/pump、ensureDrivers是精确内存边界；不测/不宣称setTeams持久化。
-- 旧DungeonPage只提供拒绝访问的dead-module哨兵，绝不读取或加载真实旧模块。
-- 底层绘图spy用于语义/几何验收，不等价于手机实测或真实战斗验收。
local PROJECT = "/workspace"
local CWD = "/home/Maker/tutorial-onboarding-validation-20261006"
local TAG = "[tutorial_dungeon_guide_test] "
local ROOT, REVIEW = "", ""
for _, arg in ipairs(GetArguments()) do
    local root = arg:match("^%-tapcode_dir=(.+)$")
    if root then ROOT = root:gsub("/+$", "") end
    local review = arg:match("^%-dungeon%-guide%-review=(.+)$")
    if review then REVIEW = review end
end
local SOURCE_FILES = {
    ["config.TutorialConfig"] = PROJECT .. "/scripts/config/TutorialConfig.lua",
    ["config.GameConfig"] = PROJECT .. "/scripts/config/GameConfig.lua",
    ["config.ExpTable"] = PROJECT .. "/scripts/config/ExpTable.lua",
    ["config.StageConfig"] = PROJECT .. "/scripts/config/StageConfig.lua",
    ["config.StageConfig_Normal"] = PROJECT .. "/scripts/config/StageConfig_Normal.lua",
    ["config.StageConfig_Hard"] = PROJECT .. "/scripts/config/StageConfig_Hard.lua",
    ["config.StageConfig_Nightmare"] = PROJECT .. "/scripts/config/StageConfig_Nightmare.lua",
    ["config.StageConfig_Hell"] = PROJECT .. "/scripts/config/StageConfig_Hell.lua",
    ["config.StageConfig_Purgatory"] = PROJECT .. "/scripts/config/StageConfig_Purgatory.lua",
    ["config.StageConfig_Torment"] = PROJECT .. "/scripts/config/StageConfig_Torment.lua",
    ["config.StageConfig_Torment2"] = PROJECT .. "/scripts/config/StageConfig_Torment2.lua",
    ["config.StageConfig_Torment3"] = PROJECT .. "/scripts/config/StageConfig_Torment3.lua",
    ["config.StageConfig_Torment4"] = PROJECT .. "/scripts/config/StageConfig_Torment4.lua",
    ["config.StageConfig_Torment5"] = PROJECT .. "/scripts/config/StageConfig_Torment5.lua",
    ["config.StageConfig_Annihilation"] = PROJECT .. "/scripts/config/StageConfig_Annihilation.lua",
    ["config.StageConfig_Annihilation2"] = PROJECT .. "/scripts/config/StageConfig_Annihilation2.lua",
    ["config.StageConfig_Annihilation3"] = PROJECT .. "/scripts/config/StageConfig_Annihilation3.lua",
    ["config.StageConfig_Annihilation4"] = PROJECT .. "/scripts/config/StageConfig_Annihilation4.lua",
    ["config.StageConfig_Annihilation5"] = PROJECT .. "/scripts/config/StageConfig_Annihilation5.lua",
    ["config.DungeonConfig"] = PROJECT .. "/scripts/config/DungeonConfig.lua",
    ["config.DungeonIdleConfig"] = PROJECT .. "/scripts/config/DungeonIdleConfig.lua",
    ["config.TowerConfig"] = PROJECT .. "/scripts/config/TowerConfig.lua",
    ["config.MonsterConfig"] = PROJECT .. "/scripts/config/MonsterConfig.lua",
    ["config.ResourceDefs"] = PROJECT .. "/scripts/config/ResourceDefs.lua",
    ["core.DrawUtil"] = PROJECT .. "/scripts/core/DrawUtil.lua",
    ["core.DarkIcon"] = PROJECT .. "/scripts/core/DarkIcon.lua",
    ["core.NumberUtil"] = PROJECT .. "/scripts/core/NumberUtil.lua",
    ["core.Viewport"] = PROJECT .. "/scripts/core/Viewport.lua",
    ["systems.TutorialManager"] = PROJECT .. "/scripts/systems/TutorialManager.lua",
    ["ui.tutorial.TutorialOverlay"] = PROJECT .. "/scripts/ui/tutorial/TutorialOverlay.lua",
    ["ui.tutorial.TutorialPageRecovery"] = PROJECT .. "/scripts/ui/tutorial/TutorialPageRecovery.lua",
    ["ui.battle.stage.StageSelectDialog"] = PROJECT .. "/scripts/ui/battle/stage/StageSelectDialog.lua",
    ["ui.battle.stage.ExpeditionOverview"] = PROJECT .. "/scripts/ui/battle/stage/ExpeditionOverview.lua",
    ["ui.battle.stage.StageSelectResources"] = PROJECT .. "/scripts/ui/battle/stage/StageSelectResources.lua",
    ["ui.battle.stage.StageSelectRewardPreview"] = PROJECT .. "/scripts/ui/battle/stage/StageSelectRewardPreview.lua",
    ["ui.battle.stage.BattleEnemySpawn"] = PROJECT .. "/scripts/ui/battle/stage/BattleEnemySpawn.lua",
    ["ui.battle.tri.BattleTriPage"] = PROJECT .. "/scripts/ui/battle/tri/BattleTriPage.lua",
    ["boot.StandaloneHorizon"] = PROJECT .. "/scripts/boot/StandaloneHorizon.lua",
    ["boot.StandaloneHorizonInput"] = PROJECT .. "/scripts/boot/StandaloneHorizonInput.lua",
}
local FRAGMENTS_ONLY = { ["ui.battle.tri.BattleTriPage"] = true, ["boot.StandaloneHorizon"] = true }
local ALLOWED_PATHS = {}
for _, path in pairs(SOURCE_FILES) do ALLOWED_PATHS[path] = true end
local nativeFile, nativeCache, nativeCreateImage, nativeDeleteImage = File, cache, nvgCreateImage, nvgDeleteImage
local sources, reads, contexts, fragments = {}, {}, {}, {} ---@type any
local checks, groups, failures = 0, 0, 0
local loadedBefore, globalsBefore = {}, {} ---@type any
local function check(ok, label) checks = checks + 1; assert(ok, label) end
local function eq(a, b, label) check(a == b, label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b)) end
local function near(a, b, label) check(type(a) == "number" and math.abs(a - b) < 0.00001, label) end
local function noop() end
local function copy(v)
    if type(v) ~= "table" then return v end
    local result = {}; for k, x in pairs(v) do result[k] = copy(x) end; return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
-- 唯一宿主cache读口：绝对白名单保留源码身份；调用方不能拼路径/选择写模式，失败同样Dispose。
local function fixedFile(path, mode)
    assert(ROOT == PROJECT, "unexpected project root")
    assert(ALLOWED_PATHS[path] == true and mode == FILE_READ, "fixedFile path/mode denied")
    assert(path:sub(1, #PROJECT + 9) == PROJECT .. "/scripts/" and path:sub(-4) == ".lua"
        and not path:find("..", 1, true), "fixed absolute Lua source only")
    local resource = path:sub(#PROJECT + 10)
    local file = assert(nativeCache:GetFile(resource), "source cache File unavailable " .. resource)
    local ok, text = pcall(function()
        assert(file:IsOpen(), "source open failed " .. resource)
        assert(file:GetMode() == FILE_READ, "source must be read-only " .. resource)
        local lines = {}; while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose()
    assert(ok, text)
    reads[#reads + 1] = resource
    return text
end
local function source(name)
    local path = assert(SOURCE_FILES[name], "source denied " .. tostring(name))
    if not sources[name] then sources[name] = fixedFile(path, FILE_READ) end
    return sources[name]
end
local function section(name, first, last)
    local text = source(name)
    local a = assert(text:find(first, 1, true), "source boundary missing " .. name .. " " .. first)
    assert(not text:find(first, a + #first, true), "source boundary ambiguous " .. name .. " " .. first)
    local b = assert(text:find(last, a + #first, true), "source end missing " .. name .. " " .. last)
    fragments[#fragments + 1] = { name = name, first = first, last = last }
    return text:sub(a, b - 1)
end
local function compile(text, label, env)
    local chunk, why = load(text, "@" .. label, "t", env); assert(chunk, why); return chunk()
end
local PAGE_PATHS = {
    "ui.hud.TopBar", "ui.hud.BottomNav", "ui.character.panel.CharacterPanel", "ui.dev.CEPanel",
    "ui.character.hero.HeroRosterPanel", "ui.hud.popup.RewardPopup", "ui.town.TownScene",
    "ui.blacksmith.BlacksmithPage", "ui.church.ChurchPage", "ui.church.talent.TalentPage",
    "ui.tavern.TavernPage", "ui.market.MarketPage", "ui.dungeon.DungeonBattleScene", "ui.tower.TowerBattleScene",
    "ui.backpack.BackpackPanel", "ui.loot.LootBox", "ui.loot.LootBoxPage", "ui.story.task.TaskPage",
    "ui.hud.popup.LevelUpPopup", "ui.hud.popup.OfflineRewardPanel", "ui.hud.popup.UpdateNoticePopup",
    "ui.hud.popup.PlayerInfoPanel", "ui.story.gate.StartScreen", "ui.story.gate.DarkTitleScreenGate",
    "ui.battle.stage.SweepDialog", "ui.battle.popup.DamageStatsPanel", "ui.battle.popup.TerminalConfirmDialog",
    "ui.story.gate.IntroCutscene", "ui.story.gate.LetterIntro", "ui.story.ScenarioDialogue",
    "ui.character.detail.CharacterDetail", "ui.character.equip.EquipmentBag", "ui.character.EquipCrossDrag",
    "ui.character.equip.EquipmentDetail", "ui.tavern.TargetRecruitPanel", "ui.tavern.TavernPopups",
}
local HANDLERS = {
    HandleMouseButtonDownHorizon = true, HandleMouseButtonUpHorizon = true, HandleMouseMoveHorizon = true,
    HandleEquipmentHoverTickHorizon = true, HandleTouchBeginHorizon = true, HandleTouchEndHorizon = true,
    HandleTouchMoveHorizon = true, HandleMouseWheelHorizon = true,
}
local NVG_NOOPS = {
    "nvgArc", "nvgBezierTo", "nvgCircle", "nvgClosePath", "nvgEllipse", "nvgFontFace", "nvgTextLineHeight",
    "nvgGlobalCompositeBlendFuncSeparate", "nvgGlobalCompositeOperation", "nvgLineCap", "nvgLineJoin",
    "nvgLineTo", "nvgMoveTo", "nvgQuadTo", "nvgRotate", "nvgRoundedRectVarying", "nvgShapeAntiAlias",
    "nvgSkewX", "nvgStrokeColor", "nvgStrokeWidth",
}
---@return any
local function newContext(review, vg)
    local c = { env = {}, modules = {}, loading = {}, denied = {}, calls = {}, events = {}, texts = {}, draws = {},
        registrations = {}, handles = {}, loads = {}, deleted = {}, nextHandle = 1, views = {}, persists = 0, saved = {},
        clock = { elapsedTime = 100 }, cursor = { x = 0, y = 0 }, nav = 3, activeTeam = 2, sceneStage = 305,
        sceneAccept = true, driverApply = true, sceneCalls = {}, starts = {}, pumps = 0, ensures = 0,
        review = review == true, vg = vg or {}, font = 20, align = 0, stack = {},
        transform = { tx = 0, ty = 0, sx = 1, sy = 1 },
        memory = { session = { introCompleted = true, claimedScenarios = {},
                tutorialProgress = { version = 1, completed = {}, queue = {} } },
            currency = { gold = 1234, gems = 567, sweepTicket = 8 },
            heroes = { roster = { [1] = { level = 20 } }, deployed = { 1, 0, 0, 0 } },
            equipment = { inventory = {}, equipped = {} },
            battle = { currentStageId = 305, maxStageId = 306, activeTeam = 2,
                teamStageIds = { 305, 201, 301 }, clearedStages = { ["305"] = true } },
            dungeon = { gold_mine = { floor = 1, cleared = {}, sweepsToday = 1 },
                equipment_vault = { floor = 1, cleared = {}, sweepsToday = 1 },
                black_diamond = { floor = 1, cleared = {}, sweepsToday = 1 },
                babel_tower = { floor = 1, sweepsToday = 1 }, ancient_ruin = { floor = 40, idleAccumSec = 99 } } },
        rt = { logicalW = 1920, logicalH = 1080, windowW = 1920, windowH = 1080, dpr = 1,
            frameScale = 1, frameOx = 0, frameOy = 0, DESIGN_W = 1080, DESIGN_H = 2400, bootReady_ = true },
    } ---@type any
    contexts[#contexts + 1] = c
    local e = c.env
    local function deny(label) c.denied[#c.denied + 1] = label; error("isolated test denies " .. tostring(label)) end
    c.deny = deny
    local function strict(fields, label)
        return setmetatable(fields, { __index = function(_, key) return deny(label .. "." .. tostring(key)) end,
            __newindex = function(_, key) return deny(label .. " assignment " .. tostring(key)) end })
    end
    c.mock = function(name, fields) c.modules[name] = strict(fields, name); return c.modules[name] end
    c.record = function(name, x, y)
        c.calls[name] = (c.calls[name] or 0) + 1
        c.draws[#c.draws + 1] = { kind = "call", name = name, x = x, y = y }
    end
    for _, key in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "tonumber",
        "tostring", "type", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal" }) do e[key] = _G[key] end
    e.math, e.string, e.table, e.utf8 = copy(math), copy(string), copy(table), copy(utf8)
    e.math.randomseed = function() return deny("global RNG seed") end
    e.math.random = function() return deny("random battle/reward generation") end
    e._G, e.time, e.print = e, c.clock, noop
    e.cjson = strict({ encode = cjson.encode, decode = cjson.decode }, "cjson")
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:match("^NVG_") or k:match("^MOUSEB_")) then e[k] = v end
    end
    e.FILE_READ, e.FILE_WRITE = FILE_READ, FILE_WRITE
    e.File = function() return deny("File any path/mode") end
    for _, key in ipairs({ "io", "os", "package", "debug", "cache", "fileSystem", "engine", "network", "clientCloud", "serverCloud" }) do
        e[key] = strict({}, key)
    end
    for _, key in ipairs({ "load", "loadfile", "dofile", "GetFileSystem", "GetEngine", "SubscribeToEvent", "SendEvent" }) do
        e[key] = function() return deny(key) end
    end
    e.input = strict({ GetMousePosition = function() return c.cursor end }, "input")
    e.H_ox, e.H_oy, e.H_s, e.H_skipDone, e.H_SKIP_START, e.H_SEAM_BACK, e.H_TRI_L0 = 0, 0, 1, false, false, false, false
    e.H_focusPanel, e.H_lastPanel = "center", "center"
    e.nvgRGBA = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    e.nvgFontSize = function(_, size) c.font = size end
    e.nvgTextAlign = function(_, align) c.align = align end
    e.nvgTextBounds = function(_, _, _, text)
        local width = 0
        for _, code in utf8.codes(text) do width = width + (code < 128 and c.font * 0.55 or c.font) end
        return width
    end
    e.nvgText = function(_, x, y, text)
        local t = c.transform
        c.texts[#c.texts + 1] = { x = x, y = y, text = text, font = c.font, align = c.align,
            px = t.tx + x * t.sx, py = t.ty + y * t.sy, clip = copy(c.clip) }
        return 0
    end
    e.nvgSave = function()
        c.stack[#c.stack + 1] = { transform = copy(c.transform), font = c.font, align = c.align, clip = copy(c.clip) }
    end
    e.nvgRestore = function()
        local saved = assert(table.remove(c.stack), "unbalanced nvgRestore")
        c.transform, c.font, c.align, c.clip = saved.transform, saved.font, saved.align, saved.clip
    end
    e.nvgTranslate = function(_, x, y)
        local t = c.transform; t.tx, t.ty = t.tx + x * t.sx, t.ty + y * t.sy
    end
    e.nvgScale = function(_, x, y) local t = c.transform; t.sx, t.sy = t.sx * x, t.sy * y end
    e.nvgResetTransform = function() c.transform = { tx = 0, ty = 0, sx = 1, sy = 1 } end
    local function transformed(x, y, w, h)
        local t = c.transform; return { x = t.tx + x * t.sx, y = t.ty + y * t.sy, w = w * t.sx, h = h * t.sy }
    end
    e.nvgResetScissor = function() c.clip = nil end
    e.nvgScissor = function(_, x, y, w, h) c.clip = transformed(x, y, w, h) end
    e.nvgIntersectScissor = function(_, x, y, w, h)
        local r = transformed(x, y, w, h)
        if c.clip then
            local right, bottom = math.min(r.x + r.w, c.clip.x + c.clip.w), math.min(r.y + r.h, c.clip.y + c.clip.h)
            r.x, r.y = math.max(r.x, c.clip.x), math.max(r.y, c.clip.y)
            r.w, r.h = math.max(0, right - r.x), math.max(0, bottom - r.y)
        end
        c.clip = r
    end
    e.nvgBeginPath = function() c.shape, c.paint = nil, nil end
    local function rect(kind, _, x, y, w, h)
        c.shape = { kind = kind, x = x, y = y, w = w, h = h, screen = transformed(x, y, w, h), clip = copy(c.clip) }
    end
    e.nvgRect = function(...) rect("rect", ...) end
    e.nvgRoundedRect = function(...) rect("rounded", ...) end
    e.nvgFillColor = function(_, color) c.color, c.paint = color, nil end
    e.nvgFillPaint = function(_, paint) c.paint = paint end
    e.nvgFill = function() c.draws[#c.draws + 1] = { kind = "fill", shape = copy(c.shape), paint = copy(c.paint) } end
    e.nvgStroke = function() c.draws[#c.draws + 1] = { kind = "stroke", shape = copy(c.shape) } end
    e.nvgLinearGradient, e.nvgRadialGradient = function() return {} end, function() return {} end
    e.nvgPathWinding = function(_, direction)
        assert(c.shape and c.shape.kind == "rounded" and direction == NVG_HOLE, "hole must follow rounded target")
        c.draws[#c.draws + 1] = { kind = "hole", shape = copy(c.shape) }
    end
    for _, key in ipairs(NVG_NOOPS) do e[key] = noop end
    c.mock("core.BattleLayout", {})
    c.mock("core.GameState", { getPower = function() return 100 end })
    c.mock("core.I18n", { get = function() return "zh_CN" end, lookup = function(s) return s end,
        difficulty = function(s) return s end, format = function(s, ...) return string.format(s, ...) end })
    c.mock("config.StageRecommendPower", { get = function() return nil end })
    c.mock("systems.AttributeDef", { DODGE = "dodge", MAG_ARMOR = "energyShield", HIT_VALUE = "hitValue",
        CRIT_RATE = "critRate", PHYS_ARMOR = "armor", PHYS_PEN = "physPen", MAG_PEN = "magPen", ATK_HEAL = "atkHeal",
        COMBO_RATE = "comboRate", ATK_SPEED = "atkSpeed", ABNORMAL_RES = "abnormalRes" })
    c.mock("systems.UnitAttributes", {})
    c.mock("systems.ButtonFeedback", { begin = function() return false end, finish = noop,
        trigger = function(name) c.record(name) end })
    -- 本专项不进入远征概览：加载真实Overview，但离线服务/头像的任何调用明确拒绝。
    c.mock("rules.offline.OfflineService", {})
    c.mock("ui.widget.HeroFrame", {})
    c.mock("runtime.ClientDispatcher", { get = function(key)
        if c.memory[key] == nil then return deny("dispatcher unknown get " .. tostring(key)) end
        return c.memory[key]
    end })
    for _, name in ipairs(PAGE_PATHS) do
        local state = { open = false, opens = 0, closes = 0, confirm = false, busy = false }
        c.views[name] = state
        local api = {
            isOpen = function() return state.open end, isActive = function() return state.open end,
            isVisible = function() return state.open end, isPresentationBlocked = function() return false end,
            open = function() state.open = true; state.opens = state.opens + 1 end,
            close = function() state.open = false; state.closes = state.closes + 1 end,
            forceClose = function() state.open = false; state.closes = state.closes + 1 end,
            getSeamAnim = function() return 100, 0, 0.45, 0.38 end,
            isRecruitBusy = function() return state.busy or state.confirm end,
            isRecruitConfirmOpen = function() return state.confirm end,
            isDraggingCard = function() return false end, isArmed = function() return false end,
            isEquipTab = function() return false end, isPinned = function() return false end,
            isCompactCorner = function() return false end, shouldBattleOverlay = function() return false end,
            hasOverlayRegion = function() return false end, hitOverlayWindow = function() return false end,
            currentRowTag = function() return nil end, currentPanel = function() return nil end,
            getSelectedIndex = function() return c.nav end,
            setSelectedIndex = function(index) c.nav = index; c.record("nav.set") end,
            setTabLocked = function() c.record("nav.unlock") end,
            cancelPendingPageOpen = function() c.record("town.cancelPending") end,
            cancel = noop, reset = noop,
        }
        for _, key in ipairs({ "handleInput", "handleDown", "handleUp", "handleWheel", "handleScroll", "handleHover",
            "handleDragBegin", "handleDragMove", "handleDragEnd", "handleRightClick" }) do
            api[key] = function(x, y) c.record(name .. "." .. key, x, y); return false end
        end
        c.mock(name, api)
    end
    rawset(c.modules["ui.hud.BottomNav"], "isAllLocked", function() return c.navLocked == true end)
    rawset(c.modules["ui.hud.BottomNav"], "isTabLocked", function(tab)
        assert(tab == 3, "Dialog selection only queries battle nav3")
        return c.battleTabLocked == true
    end)
    -- 模块名仍被旧HorizonInput顶层require；访问任何旧接口都必须失败，而不是静默兼容。
    c.mock("ui.dungeon.DungeonPage", {})
    c.mock("boot.ArtifactGesture", { bind = function() return nil end, down = function() return false end,
        up = function() return false end, move = function() return false end, hover = noop, cancel = noop })
    c.mock("ui.widget.SoundToggle", { handleButtonInput = function() return deny("non-dialog HUD sound input") end })
    c.mock("runtime.GameAction", { sendAction = function() return deny("runtime action") end })
    e.require = function(name)
        if c.modules[name] ~= nil then return c.modules[name] end
        if FRAGMENTS_ONLY[name] then return deny("whole module " .. tostring(name)) end
        if not SOURCE_FILES[name] then return deny("unknown require " .. tostring(name)) end
        if c.loading[name] then return deny("unexpected eager circular require " .. tostring(name)) end
        c.loading[name] = true
        local ok, value = pcall(compile, source(name), SOURCE_FILES[name], e)
        c.loading[name] = nil
        if not ok then error(value) end
        assert(value ~= nil, "module no return " .. name)
        c.modules[name] = value
        return value
    end
    c.require = e.require
    setmetatable(e, { __index = function(_, key) return deny("unknown global " .. tostring(key)) end,
        __newindex = function(t, key, value)
            if not HANDLERS[key] then return deny("unknown global assignment " .. tostring(key)) end
            rawset(t, key, value)
        end })
    c.sc = c.require("config.StageConfig")
    c.dc = c.require("config.DungeonConfig")
    local mc = c.require("config.MonsterConfig")
    local allowedImages = {
        ["image/通用图标/UI_ICON_XG.png"] = true, ["image/界面底板/通用面板/UI_TY_EJQRK.png"] = true,
        ["image/按钮/UI_AN_HUANG.png"] = true, ["image/通用图标/UI_ICON_SUO.png"] = true,
        ["image/通用图标/ICON_ZDL.png"] = true, ["image/货币道具/UI_icon_JB_X.png"] = true,
        ["image/货币道具/UI_icon_FBBX.png"] = true, ["image/货币道具/UI_icon_SJ_X.png"] = true,
        ["image/战斗背景/金币副本.png"] = true, ["image/战斗背景/装备副本.png"] = true,
        ["image/战斗背景/黑钻副本.png"] = true, ["image/战斗背景/通天塔.png"] = true,
    }
    for quality = 1, 6 do allowedImages["image/品质框/UI_icon_ZBBJ_" .. quality .. ".png"] = true end
    for chapter = 1, 23 do allowedImages[c.sc.getBattleBackground(chapter * 100 + 1)] = true end
    for id in pairs(mc.MONSTERS) do allowedImages[string.format("image/怪物卡牌/KP_GW_%d.png", mc.getCardArtId(id))] = true end
    rawset(e, "nvgCreateImage", function(ctx, path, flags)
        if not allowedImages[path] then return deny("image path " .. tostring(path)) end
        c.loads[path] = (c.loads[path] or 0) + 1
        local handle
        if c.review then handle = nativeCreateImage(ctx, path, flags); assert(handle and handle >= 0, "review image missing " .. path)
        else handle = c.nextHandle; c.nextHandle = handle + 1 end
        c.handles[handle] = path; return handle
    end)
    rawset(e, "nvgDeleteImage", function(ctx, handle)
        assert(c.handles[handle], "delete unknown image")
        c.deleted[handle] = true; if c.review then nativeDeleteImage(ctx, handle) end
    end)
    rawset(e, "nvgImageSize", function() return 1896, 720 end)
    rawset(e, "nvgImagePattern", function(_, x, y, w, h, angle, handle, alpha)
        assert(c.handles[handle], "paint unknown image")
        return { path = c.handles[handle], x = x, y = y, w = w, h = h, alpha = alpha, angle = angle }
    end)
    rawset(e, "nvgImagePatternTinted", function(ctx, x, y, w, h, angle, handle, tint)
        return e.nvgImagePattern(ctx, x, y, w, h, angle, handle, tint.a / 255)
    end)
    if c.review then
        -- 只切换明确的图形API；原生File/require/业务边界仍严格拒绝。
        for key, value in pairs(e) do
            if type(key) == "string" and key:match("^nvg") and type(value) == "function"
                and key ~= "nvgCreateImage" and key ~= "nvgDeleteImage" then
                rawset(e, key, assert(_G[key], "real NVG unavailable " .. key))
            end
        end
    end
    local qualityImages = {}
    c.mock("ui.widget.ImageCache", { getQualityBg = function(quality)
        assert(type(quality) == "number" and quality % 1 == 0 and quality >= 1 and quality <= 6, "quality range")
        if not qualityImages[quality] then
            qualityImages[quality] = e.nvgCreateImage(c.vg, "image/品质框/UI_icon_ZBBJ_" .. quality .. ".png", 0)
        end
        return qualityImages[quality]
    end })
    c.store = strict({ Get = function(key)
        if c.memory[key] == nil then return deny("store unknown get " .. tostring(key)) end
        return c.memory[key]
    end }, "store")
    c.persist = function(progress)
        c.persists = c.persists + 1; c.memory.session.tutorialProgress = copy(progress)
        c.saved[#c.saved + 1] = copy(c.memory)
    end
    c.tm = c.require("systems.TutorialManager")
    c.tm.init(c.vg, c.store, c.persist)
    local register, notify = c.tm.registerHotspot, c.tm.notifyEvent
    c.tm.registerHotspot = function(key, cx, cy, w, h, panel, spotlight)
        c.registrations[#c.registrations + 1] = { key = key, cx = cx, cy = cy, w = w, h = h, panel = panel }
        return register(key, cx, cy, w, h, panel, spotlight)
    end
    c.tm.notifyEvent = function(name)
        c.events[#c.events + 1] = name
        return notify(name) -- 观察真实Dialog事件，不在Driver/goto替身中发事件。
    end
    local setRect = c.tm.setOverlayRect
    c.tm.setOverlayRect = function(w, h, hs)
        c.projected = copy(hs)
        return setRect(w, h, hs)
    end
    c.dialog = c.require("ui.battle.stage.StageSelectDialog")
    local init, open, openDungeon, prepare = c.dialog.init, c.dialog.open, c.dialog.openDungeon, c.dialog.prepareTutorial
    assert(type(prepare) == "function", "production Dialog.prepareTutorial required")
    c.dialog.init = function(ctx) c.record("dialog.init"); return init(ctx) end
    c.dialog.open = function(...) c.record("dialog.open"); return open(...) end
    c.dialog.openDungeon = function(...) c.record("dialog.openDungeon"); return openDungeon(...) end
    c.dialog.prepareTutorial = function(...) c.record("dialog.prepare"); return prepare(...) end
    c.dialog.init(c.vg)
    c.drivers = {}
    for team, stageId in ipairs({ 305, 201, 301 }) do
        local driver = { stageId = stageId, allies = {} }
        driver.start = function(self, id)
            assert(self == driver and c.sc.getStage(id), "Driver.start context/id")
            c.starts[#c.starts + 1] = { team = team, id = id }
            if c.driverApply then self.stageId = id end
        end
        c.drivers[team] = strict(driver, "Driver" .. team)
    end
    c.mock("ui.battle.scene.BattleScene", {
        getStageId = function() return c.sceneStage end,
        getMaxStageId = function() return c.memory.battle.maxStageId end,
        getClearedStages = function() return c.memory.battle.clearedStages end,
        pumpBattleCards = function() c.pumps = c.pumps + 1 end,
        gotoStage = function(id, options)
            assert(c.sc.getStage(id) and same(options, { deferEnter = true }), "Scene.gotoStage exact request")
            c.sceneCalls[#c.sceneCalls + 1] = { id = id, options = copy(options) }
            if c.sceneAccept then c.sceneStage = id; return true end
            return false
        end,
        isSpeedButtonVisible = function() return false end,
    })
    rawset(e, "TEST_DRIVERS", c.drivers)
    rawset(e, "TEST_ENSURE_DRIVERS", function()
        c.ensures = c.ensures + 1; return c.require("config.ExpTable").getUnlockedTeamCount(c.memory.battle)
    end)
    rawset(e, "TEST_START_TERMINAL", function() return deny("terminal live combat") end)
    local btp = "ui.battle.tri.BattleTriPage"
    local prefix = [[
local BattleTriPage = {}
local StageConfig = require("config.StageConfig")
local ExpTable = require("config.ExpTable")
local ClientDispatcher = require("runtime.ClientDispatcher")
local StageSelectDialog = require("ui.battle.stage.StageSelectDialog")
local SweepDialog = require("ui.battle.stage.SweepDialog")
local DamageStatsPanel = require("ui.battle.popup.DamageStatsPanel")
local TerminalConfirmDialog = require("ui.battle.popup.TerminalConfirmDialog")
local RewardPopup = require("ui.hud.popup.RewardPopup")
local EquipmentBag = require("ui.character.equip.EquipmentBag")
local SoundToggle = require("ui.widget.SoundToggle")
local BattleLayout = require("core.BattleLayout")
local drivers = TEST_DRIVERS
local ensureDrivers = TEST_ENSURE_DRIVERS
local startTerminalRaid = TEST_START_TERMINAL
local COL_COUNT = ExpTable.TEAM_COUNT
local isOpen_, battleReady = false, true
local terminalRaid = nil
local region = { x=0, y=0, w=1920, h=1080 }
function BattleTriPage.isOpen() return isOpen_ end
]]
    -- 每段为生产完整函数/闭包，不复制goto、输入或变换算法，不启动整个BTP模块。
    local transform = section(btp, "function BattleTriPage.getDialogTransform(", "\n--- 击杀奖励回调")
    local life = section(btp, "function BattleTriPage.open()", "\n--- 幂等初始化")
    local terminalState = section(btp, "function BattleTriPage.isTerminalRaidActive()", "\nfunction BattleTriPage.setBattleReady(")
    local interior = section(btp, "local PLATE_AR =", "\n--- [三队并行] 行内矩形")
    local gotoText = section(btp, "function BattleTriPage.getTeamStageId(", "\n--- 每行 HUD")
    local inputText = section(btp, "function BattleTriPage.handleInput(", "\n--- 三队实时快照")
    local modalText = section(btp, "    -- [对话框覆盖]", "\n    -- [三行并行] 获得弹窗")
    local regionLine = "    region = { x = 0, y = 0, w = logicalW, h = logicalH }"
    assert(source(btp):find(regionLine, 1, true), "production draw region assignment missing")
    local drawText = "\nfunction BattleTriPage.draw(vg, logicalW, logicalH)\n"
        .. regionLine .. "\nlocal BattleScene = require(\"ui.battle.scene.BattleScene\")\n" .. modalText .. "\nend\n"
    c.tri, c.setTerminalRaid = compile(prefix .. transform .. life .. terminalState .. interior .. gotoText .. inputText .. drawText
        .. "\nreturn BattleTriPage, function(active) terminalRaid = active and {} or nil end",
        SOURCE_FILES[btp] .. "#complete-dialog-closures", e)
    c.modules[btp] = c.tri
    c.rt.vg = c.vg
    local vp = c.require("core.Viewport")
    for name, value in pairs({ TutorialManager = c.tm, Viewport = vp, BattleTriPage = c.tri, StageSelectDialog = c.dialog,
        ScenarioDialogue = c.modules["ui.story.ScenarioDialogue"], LetterIntro = c.modules["ui.story.gate.LetterIntro"],
        IntroCutscene = c.modules["ui.story.gate.IntroCutscene"], DarkTitleScreen = c.modules["ui.story.gate.DarkTitleScreenGate"],
        DungeonBattleScene = c.modules["ui.dungeon.DungeonBattleScene"], TowerBattleScene = c.modules["ui.tower.TowerBattleScene"],
        BottomNav = c.modules["ui.hud.BottomNav"], logicalW = function() return c.rt.logicalW end,
        logicalH = function() return c.rt.logicalH end, DESIGN_W = function() return 1080 end,
        DESIGN_H = function() return 2400 end, vg = function() return c.vg end,
        applyFrame = function() e.nvgTranslate(c.vg, c.rt.frameOx, c.rt.frameOy); e.nvgScale(c.vg, c.rt.frameScale, c.rt.frameScale) end,
    }) do rawset(e, name, value) end
    c.project = compile(section("boot.StandaloneHorizon", "local function HorizonDrawTutorialOverlay()", "\n--- [弹窗聚焦]")
        .. "\nreturn HorizonDrawTutorialOverlay", SOURCE_FILES["boot.StandaloneHorizon"] .. "#complete-overlay", e)
    c.config = c.require("config.TutorialConfig")
    c.configBefore = copy(c.config)
    c.recovery = c.require("ui.tutorial.TutorialPageRecovery")
    c.tm.update(0)
    c.tick = function(dt) c.clock.elapsedTime = c.clock.elapsedTime + dt; c.tm.update(dt) end
    c.begin = function(stepIndex)
        c.memory.session.tutorialProgress = { version = 1, completed = {}, queue = {}, group = 15, step = stepIndex or 1 }
        c.tm.init(c.vg, c.store, c.persist); c.tick(0)
    end
    c.settle = function() c.tick(0.6); c.tick(0.6) end
    c.clearDraw = function()
        c.texts, c.draws, c.registrations = {}, {}, {}
        e.nvgResetTransform(); e.nvgResetScissor()
    end
    c.draw = function()
        c.tm.clearHotspots(); c.clearDraw()
        e.applyFrame(); c.tri.draw(c.vg, c.rt.logicalW, c.rt.logicalH); c.project()
        if not c.review then
            check(#c.stack == 0 and c.clip == nil, "drawing save/restore/scissor balanced")
        end
    end
    return c
end
local function count(c, name) return c.calls[name] or 0 end
local function eventCount(c, name)
    local n = 0; for _, event in ipairs(c.events) do if event == name then n = n + 1 end end; return n
end
local function ledger(c)
    local result = copy(c.memory); result.session.tutorialProgress = nil; return result
end
local function audit(c)
    eq(#c.denied, 0, "no forbidden production accesses")
    check(same(c.config, c.configBefore), "TutorialConfig unchanged")
    if not c.review then eq(#c.stack, 0, "no drawing stack leak") end
    check(c.modules["ui.dungeon.DungeonPage"] ~= nil and sources["ui.dungeon.DungeonPage"] == nil,
        "old DungeonPage dead sentinel only, no real module")
end
local function target(c)
    local hs = assert(c.tm.getCurrentHotspot(), "real Dialog draw must register target")
    near(hs.cx, 605, "actual first-row centerX"); near(hs.cy, 860, "actual first-row centerY")
    near(hs.w, 580, "actual first-row width"); near(hs.h, 140, "actual first-row height")
    eq(hs.panel, "tri_modal", "actual target dedicated BTP panel"); check(hs.spotlight == nil, "no whole modal spotlight")
    return hs
end
local function textFound(c, text)
    for _, item in ipairs(c.texts) do if item.text == text then return item end end
end
local function hole(c)
    for _, draw in ipairs(c.draws) do if draw.kind == "hole" then return draw.shape end end
end
local function overlaps(a, b)
    return a and b and math.abs(a.cx - b.cx) < (a.w + b.w) * 0.5 and math.abs(a.cy - b.cy) < (a.h + b.h) * 0.5
end
local function inScreen(r, w, h, label)
    check(r and r.w > 0 and r.h > 0, label .. " positive")
    check(r.cx - r.w / 2 >= -0.001 and r.cx + r.w / 2 <= w + 0.001, label .. " X bounds")
    check(r.cy - r.h / 2 >= -0.001 and r.cy + r.h / 2 <= h + 0.001, label .. " Y bounds")
end
local function screen(c, x, y)
    local ox, oy, fit = c.tri.getDialogTransform(c.rt.logicalW, c.rt.logicalH)
    return ox + x * fit, oy + y * fit
end
local function bindInput(c)
    local rt = c.rt
    local gesture = { hasPress = function() return false end, reset = noop, cancel = noop, cancelIfBlocked = noop }
    local offline = { hasPress = function() return false end, cancel = noop,
        toDesign = function(x, y) return x, y end, handleWheel = function() return false end }
    local ctx = { RT = rt, Viewport = c.require("core.Viewport"), OfflineRewardOverlay = offline,
        vg = function() return c.vg end, logicalW = function() return rt.logicalW end,
        logicalH = function() return rt.logicalH end, windowW = function() return rt.windowW end,
        windowH = function() return rt.windowH end, dpr = function() return rt.dpr end,
        DESIGN_W = function() return 1080 end, DESIGN_H = function() return 2400 end,
        bootReady_ = function() return true end,
        toDesign = function(x, y) return (x - rt.frameOx) / rt.frameScale, (y - rt.frameOy) / rt.frameScale end,
        talentPageUsesWideLayout = function() return false end, syncTalentPageLayout = noop,
        talentPageRightEdge = function() return 0 end, equipOverlayDesign = function() return nil end,
        seamHitAt = function() return nil end, seamInputBlocked = function() return true end, seamGesture = gesture,
    }
    c.require("boot.StandaloneHorizonInput").bind(ctx)
    c.pointer = function(x, y)
        c.cursor.x = (rt.frameOx + x * rt.frameScale) * rt.dpr
        c.cursor.y = (rt.frameOy + y * rt.frameScale) * rt.dpr
    end
    c.invoke = function(name, event)
        c.env[name](name, event or { Button = { GetInt = function() return MOUSEB_LEFT end } })
    end
    c.click = function(x, y)
        c.pointer(x, y); c.invoke("HandleMouseButtonDownHorizon"); c.clock.elapsedTime = c.clock.elapsedTime + 0.2
        c.invoke("HandleMouseButtonUpHorizon")
    end
    c.touch = function(id, x, y)
        local px = math.floor((rt.frameOx + x * rt.frameScale) * rt.dpr + 0.5)
        local py = math.floor((rt.frameOy + y * rt.frameScale) * rt.dpr + 0.5)
        return { TouchID = { GetInt = function() return id end }, X = { GetInt = function() return px end },
            Y = { GetInt = function() return py end } }
    end
end
local function readyContext()
    local c = newContext(); c.begin(1); c.settle(); c.draw(); target(c); return c
end
local function contractCases()
    local c = newContext()
    local cfg = c.config[15]
    eq(#cfg.steps, 2, "group15 retains compatible entry step")
    eq(cfg.steps[2].highlight, "dungeon_gold_mine", "gold highlight")
    eq(cfg.steps[2].advanceOn, "enter_gold_mine", "success event not click")
    eq(cfg.steps[2].pointerTarget, true, "restrict to real row")
    check(cfg.steps[2].text:find("1-1", 1, true) ~= nil, "explicit first row instruction")
    eq(c.dc.getStageId("gold_mine", 1), 100001, "independent first task ID oracle")
    local ids = c.require("ui.battle.stage.StageSelectResources").getGroups()[1].ids
    eq(ids[1], 100001, "actual resource rows first ID")
    check(c.modules["ui.battle.stage.ExpeditionOverview"] ~= nil
        and sources["ui.battle.stage.ExpeditionOverview"] ~= nil and sources["config.ResourceDefs"] ~= nil,
        "Dialog eager dependency uses real allowlisted Overview/ResourceDefs")
    local before = ledger(c)
    c.dialog.close()
    for _, gate in ipairs({ "navLocked", "battleTabLocked", "terminal", "dungeon", "tower" }) do
        c.navLocked, c.battleTabLocked = gate == "navLocked", gate == "battleTabLocked"
        c.setTerminalRaid(gate == "terminal")
        c.views["ui.dungeon.DungeonBattleScene"].open = gate == "dungeon"
        c.views["ui.tower.TowerBattleScene"].open = gate == "tower"
        c.dialog.openDungeon(1, "gold_mine")
        check(not c.dialog.isOpen(), "actual Dialog selection guard refuses " .. gate)
        eq(#c.sceneCalls, 0, "guarded Dialog open submits no task " .. gate)
        eq(#c.starts, 0, "guarded Dialog open starts no driver " .. gate)
        eq(eventCount(c, "enter_gold_mine"), 0, "guarded Dialog open emits no success " .. gate)
    end
    c.navLocked, c.battleTabLocked = false, false; c.setTerminalRaid(false)
    c.views["ui.dungeon.DungeonBattleScene"].open, c.views["ui.tower.TowerBattleScene"].open = false, false
    check(same(ledger(c), before), "selection guards preserve gameplay ledger")
    audit(c)
end
local function recoveryCases()
    for _, stepIndex in ipairs({ 1, 2 }) do
        for _, initiallyOpen in ipairs({ false, true }) do
            local c = newContext()
            if initiallyOpen then c.tri.open(); c.dialog.openDungeon(1, "gold_mine"); c.clock.elapsedTime = c.clock.elapsedTime + 1 end
            local before = ledger(c)
            c.begin(stepIndex); c.settle(); c.draw(); target(c)
            eq(c.tm.getCurrentGroup(), 15, "restored active15")
            eq(c.tm.getProgress().step, 2, "old step1 canonicalized to gold row")
            eq(c.nav, 3, "new flow stays battle nav3")
            check(c.tri.isOpen() and c.dialog.isOpen() and c.tm.isInputActive(), "open Dialog not self-blocking")
            check(not textFound(c, "正在准备引导页面，请稍候…"), "screenshot preparing resolved by real target")
            check(not c.tm.isGroupCompleted(15) and eventCount(c, "enter_gold_mine") == 0,
                "automatic prepare never counts as business success")
            check(same(ledger(c), before), "restore/prepare doesn't modify gameplay ledger")
            local opens, inits, pumps, ensures = count(c, "dialog.open"), count(c, "dialog.init"), c.pumps, c.ensures
            for _ = 1, 6 do c.tick(0.6); c.draw() end
            eq(count(c, "dialog.open"), opens, "stable no repeated Dialog.open")
            eq(count(c, "dialog.init"), inits, "stable no repeated Dialog.init")
            eq(c.pumps, pumps, "stable no repeated BTP pump")
            eq(c.ensures, ensures, "stable no repeated ensureDrivers")
            c.dialog.close(); c.tick(0.6); c.settle(); c.draw(); target(c)
            eq(count(c, "dialog.open"), opens + 1, "closed target reopens exactly once")
            local progress = copy(c.tm.getProgress()); c.memory.session.tutorialProgress = progress
            c.tm.init(c.vg, c.store, c.persist); c.tick(0); c.settle(); c.draw(); target(c)
            eq(c.tm.getCurrentGroup(), 15, "restart still active15")
            check(not c.tm.isGroupCompleted(15) and same(ledger(c), before), "restart no success or reward")
            audit(c)
        end
    end
    local c = newContext(); c.nav = 5; c.tri.open(); c.dialog.openDungeon(3, "equipment_vault")
    c.begin(2); c.settle(); c.draw(); target(c)
    eq(c.nav, 3, "old nav5 replaced rather than old DungeonPage route")
    eq(c.activeTeam, 2, "editing team not stolen by fixed tutorial team1")
    c.dialog.handleScroll(-4, 340, 900); c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg)
    c.tick(0.6); c.settle(); c.draw(); target(c)
    check(textFound(c, "1-1") ~= nil, "recovery resets gold row scroll to zero")
    audit(c)
end
local function blockerCases()
    local blockers = {
        "ui.hud.popup.OfflineRewardPanel", "ui.hud.popup.UpdateNoticePopup", "ui.hud.popup.LevelUpPopup",
        "ui.story.gate.DarkTitleScreenGate", "ui.story.gate.LetterIntro", "ui.story.gate.IntroCutscene",
        "ui.dungeon.DungeonBattleScene", "ui.tower.TowerBattleScene", "ui.battle.stage.SweepDialog",
        "ui.battle.popup.DamageStatsPanel", "ui.battle.popup.TerminalConfirmDialog",
    }
    for _, path in ipairs(blockers) do
        local c = readyContext(); local opens, progress = count(c, "dialog.open"), copy(c.tm.getProgress())
        c.views[path].open = true
        check(c.recovery.isBlocked("dungeon_gold_mine"), "target exception doesn't exclude higher priority " .. path)
        c.tick(3)
        check(not c.tm.isInputActive() and c.tm.canPointerStart(0, 0) and not c.tm.handleScreenClick(0, 0),
            "hidden tutorial yields input " .. path)
        eq(count(c, "dialog.open"), opens, "blocked no reopen " .. path)
        check(c.views[path].open and same(c.tm.getProgress(), progress), "blocker preserved and progress paused " .. path)
        c.views[path].open = false; c.tick(0.6); c.draw(); target(c)
        check(c.tm.isInputActive(), "same active15 resumes " .. path)
        audit(c)
    end
    for _, path in ipairs({ "ui.hud.popup.RewardPopup", "ui.story.ScenarioDialogue" }) do
        local c = readyContext(); local progress = copy(c.tm.getProgress())
        c.views[path].open = true; c.tick(5); c.clearDraw(); c.project()
        check(not c.tm.isInputActive() and hole(c) == nil, "TM reward/story preserves priority " .. path)
        check(same(c.tm.getProgress(), progress), "reward/story doesn't consume step")
        c.views[path].open = false; c.tick(0.6); c.draw(); target(c); audit(c)
    end
    local c = readyContext()
    c.views["ui.tavern.TavernPage"].confirm = true; c.tick(2)
    check(not c.tm.isInputActive(), "recruit confirmation remains blocker")
    c.views["ui.tavern.TavernPage"].confirm = false
    check(not c.recovery.isBlocked("dungeon_gold_mine") and not c.recovery.isBlocked("tab_dungeon"),
        "only tutorial targets exclude StageSelectDialog itself")
    for _, key in ipairs({ "building_tavern", "character_slot_1", "smith_btn_enhance", "unknown_target" }) do
        check(c.recovery.isBlocked(key), "other target retains Dialog blocker " .. key)
    end
    check(c.recovery.isBlocked(), "noarg queue arbitration keeps Dialog blocker")
    audit(c)
end
local function queueCases()
    for _, sid in ipairs({ 58, 59, 60 }) do
        local c = newContext(); c.tri.open(); c.dialog.openDungeon(1, "gold_mine")
        c.tm.onScenarioClaimed(sid); c.tm.onScenarioClaimed(sid)
        eq(#c.tm.getProgress().queue, 1, "queue15 dedup scenario " .. sid)
        c.tick(20); check(not c.tm.isActive(), "open Dialog blocks pending queue (noarg)")
        c.dialog.close(); c.tick(0.15)
        check(not c.tm.isActive(), "queue quiet window not bypassed")
        c.views["ui.hud.popup.RewardPopup"].open = true; c.tick(2)
        c.views["ui.hud.popup.RewardPopup"].open = false; c.tick(0.15)
        check(not c.tm.isActive(), "priority interruption resets quiet")
        c.tick(0.11); c.settle(); c.draw(); target(c)
        eq(c.tm.getCurrentGroup(), 15, "queue15 starts after quiet")
        eq(#c.tm.getProgress().queue, 0, "queue consumed once")
        check(not c.tm.canPlayPendingStory(), "active15 protects task from ordinary story")
        audit(c)
    end
    local c = newContext()
    c.memory.session.tutorialProgress = { version = 1, completed = {}, queue = { 15 } }
    c.tm.init(c.vg, c.store, c.persist); c.tick(0.1)
    check(not c.tm.isActive() and #c.tm.getProgress().queue == 1, "restart preserves pending15")
    c.tick(0.16); c.settle(); c.draw(); target(c)
    eq(c.tm.getCurrentGroup(), 15, "restored pending15 consumes once")
    audit(c)
end
local function registrationCases()
    -- 命中设计：实际行315..895 × 790..930；视窗315..895 × 786..1676。
    -- gold/队1/first unlocked/.18s稳定才注册；洞外扩不能改变按钮命中。
    local c = newContext(); c.begin(2)
    c.clock.elapsedTime = c.clock.elapsedTime + 0.17
    c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg)
    eq(c.tm.getCurrentHotspot(), nil, "opening .17s not stable hotspot")
    c.clock.elapsedTime = c.clock.elapsedTime + 0.02
    c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg); target(c)
    -- 默认档max306只解锁队1；新Dialog会拒绝锁定队2请求，保留原队1视图和合法热点。
    eq(c.require("config.ExpTable").getUnlockedTeamCount(c.memory.battle), 1, "fixture initially only team1 unlocked")
    local before = ledger(c)
    c.dialog.openDungeon(2, "gold_mine"); c.clock.elapsedTime = c.clock.elapsedTime + 1
    c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg); target(c)
    check(textFound(c, "队伍 1 · 选择关卡") ~= nil, "locked team2 request retains actual team1 selector")
    check(same(ledger(c), before), "locked team2 request preserves gameplay ledger")
    -- 显式补已越过905的资格，再验证真正切到队2时绝不借用队1教程热点。
    c.memory.battle.maxStageId = 906
    eq(c.require("config.ExpTable").getUnlockedTeamCount(c.memory.battle), 2, "wrong-team fixture explicitly unlocks team2")
    c.dialog.openDungeon(2, "gold_mine"); c.clock.elapsedTime = c.clock.elapsedTime + 1
    c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg)
    check(textFound(c, "队伍 2 · 选择关卡") ~= nil, "wrong-team check actually reached team2 selector")
    eq(c.tm.getCurrentHotspot(), nil, "unlocked targetTeam2 no borrowed team1 target")
    eq(#c.sceneCalls, 0, "team selection never submits task")
    eq(#c.starts, 0, "team selection never starts driver")
    eq(eventCount(c, "enter_gold_mine"), 0, "team selection never invents gold completion")
    check(not c.tm.isGroupCompleted(15), "team selection does not complete guide15")
    -- 已开窗时openDungeon仍会重新定位并重置openTime；仅推进墙钟，不跑教程恢复重置滚动。
    c.dialog.openDungeon(1, "equipment_vault"); c.clock.elapsedTime = c.clock.elapsedTime + 1
    c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg)
    eq(c.tm.getCurrentHotspot(), nil, "wrong selected resource no target")
    c.dialog.openDungeon(1, "gold_mine"); c.clock.elapsedTime = c.clock.elapsedTime + 1
    c.dialog.handleScroll(-0.4, 340, 900)
    c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg)
    local clipped = assert(c.tm.getCurrentHotspot(), "partially clipped real first row still has visible target")
    near(clipped.cx, 605, "partial row keeps actual X"); near(clipped.cy, 828, "partial row clipped centerY")
    near(clipped.w, 580, "partial row actual width"); near(clipped.h, 84, "partial row clip-only height")
    eq(clipped.panel, "tri_modal", "partial row same dedicated projection panel")
    c.dialog.handleScroll(-1, 340, 900)
    c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg)
    eq(c.tm.getCurrentHotspot(), nil, "first row fully outside viewport no stale target")
    c.dialog.prepareTutorial(c.vg); c.clock.elapsedTime = c.clock.elapsedTime + 1
    c.memory.battle.maxStageId = 304; c.memory.battle.clearedStages = {}
    c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg)
    eq(c.tm.getCurrentHotspot(), nil, "locked first row no hotspot")
    local n = #c.sceneCalls; c.dialog.handleInput(605, 860)
    eq(#c.sceneCalls, n, "locked first row cannot submit")
    eq(eventCount(c, "enter_gold_mine"), 0, "locked first row no event")
    c.memory.battle.maxStageId = 306; c.memory.battle.clearedStages = { ["305"] = true }
    c.settle(); c.draw(); target(c)
    c.dialog.close(); c.clearDraw(); c.tm.clearHotspots(); c.dialog.draw(c.vg)
    eq(c.tm.getCurrentHotspot(), nil, "closed Dialog no stale registration")
    audit(c)
end
local function legacyModalCases()
    local c = readyContext()
    -- 仅投影控制用例注入generic modal；业务集成用例始终由真实Dialog注册tri_modal。
    --证明新增panel不会挪动原本的普通modal、nav5横屏modal或Viewport面板契约。
    local key = c.tm.getCurrentHighlight()
    for _, nav in ipairs({ 3, 5 }) do
        c.nav = nav; c.tm.clearHotspots(); c.clearDraw()
        c.tm.registerHotspot(key, 605, 860, 580, 140, "modal")
        c.project()
        local dw, dh = nav == 5 and 1920 or 1080, nav == 5 and 1080 or 2400
        local fit = math.min(c.rt.logicalW / dw, c.rt.logicalH / dh)
        near(c.projected.cx, (c.rt.logicalW - dw * fit) / 2 + 605 * fit, "ordinary modal offsetX unchanged")
        near(c.projected.cy, (c.rt.logicalH - dh * fit) / 2 + 860 * fit, "ordinary modal offsetY unchanged")
        near(c.projected.w, 580 * fit, "ordinary modal fit unchanged")
    end
    c.nav = 3
    local vp = c.require("core.Viewport")
    vp.note("left", 21, 13, 0.6, 0.2)
    c.tm.clearHotspots(); c.clearDraw(); c.tm.registerHotspot(key, 605, 860, 580, 140, "left")
    c.project()
    near(c.projected.cx, 21 + 605 * 0.2, "Viewport custom scaleX unchanged")
    near(c.projected.cy, 13 + 860 * 0.6 * vp.DS, "Viewport vertical DS unchanged")
    c.draw(); target(c)
    local ox, oy, fit = c.tri.getDialogTransform(c.rt.logicalW, c.rt.logicalH)
    near(c.projected.cx, ox + 605 * fit, "real Dialog returns to dedicated tri_modal")
    near(c.projected.cy, oy + 860 * fit, "no legacy modal transform leak")
    audit(c)
end
local function geometryInputCases()
    for _, size in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 844, 390 } }) do
        for _, ratio in ipairs({ 1, 2, 3 }) do
            for _, outer in ipairs({ false, true }) do
                local c = newContext(); local rt = c.rt
                rt.logicalW, rt.logicalH, rt.windowW, rt.windowH = size[1], size[2], size[1], size[2]
                rt.dpr, rt.frameScale = ratio, outer and 0.8 or 1
                rt.frameOx, rt.frameOy = outer and 37 or 0, outer and 23 or 0
                c.begin(2); c.settle(); c.draw(); target(c)
                local expectedFit = math.min(size[1] / 1080, size[2] / 2400) * 2
                local ox, oy, fit = c.tri.getDialogTransform(size[1], size[2])
                near(fit, expectedFit, "actual BTP doubled-fit independent oracle")
                near(ox, size[1] / 2 - 540 * fit, "actual BTP offsetX")
                near(oy, size[2] / 2 - 1195 * fit, "actual BTP offsetY")
                local x, y = ox + 605 * fit, oy + 860 * fit
                local expected = { cx = x, cy = y, w = 580 * fit, h = 140 * fit }
                local layout = c.require("ui.tutorial.TutorialOverlay").layout(size[1], size[2], expected)
                local actualHole = assert(hole(c), "production projection draws actual hole")
                near(actualHole.x, layout.hole.cx - layout.hole.w / 2, "actual hole aligns enlarged rowX")
                near(actualHole.y, layout.hole.cy - layout.hole.h / 2, "actual hole aligns enlarged rowY")
                near(actualHole.w, layout.hole.w, "actual hole row width not old half-size modal")
                inScreen(layout.bubble, size[1], size[2], "bubble"); inScreen(layout.skip, size[1], size[2], "skip")
                check(not overlaps(layout.bubble, layout.hole) and not overlaps(layout.skip, layout.hole), "overlay avoids actual row")
                local row
                for _, draw in ipairs(c.draws) do
                    local shape = draw.shape
                    if draw.kind == "fill" and shape and shape.x == 315 and shape.y == 790 and shape.w == 580 and shape.h == 140 then
                        row = shape; break
                    end
                end
                check(row ~= nil, "real Dialog row drawn through real BTP modal block")
                near(row.screen.x, rt.frameOx + (ox + 315 * fit) * rt.frameScale, "actual row outer-frame X")
                near(row.screen.y, rt.frameOy + (oy + 790 * fit) * rt.frameScale, "actual row outer-frame Y")
                bindInput(c)
                local before, persists = ledger(c), c.persists
                for _, point in ipairs({ { 200, 918 }, { 605, 1010 }, { 605, 935 }, { 900, 860 }, { 605, 780 } }) do
                    local wx, wy = screen(c, point[1], point[2]); c.click(wx, wy)
                    eq(#c.sceneCalls, 0, "wrong resource/row/gap/outside no submission")
                    eq(eventCount(c, "enter_gold_mine"), 0, "wrong input no actual event")
                end
                eq(c.persists, persists, "wrong clicks don't save tutorial")
                c.pointer(x, y); c.invoke("HandleMouseButtonDownHorizon")
                eq(#c.sceneCalls, 0, "physical down cannot submit")
                eq(c.persists, persists, "physical down cannot advance")
                c.clock.elapsedTime = c.clock.elapsedTime + 0.2; c.invoke("HandleMouseButtonUpHorizon")
                eq(#c.sceneCalls, 1, "physical up reaches real gotoTeamStage once")
                eq(c.sceneCalls[1].id, 100001, "real Scene request correct task")
                eq(#c.starts, 1, "real BTP starts one driver")
                eq(c.starts[1].team, 1, "real BTP fixed tutorial team1")
                eq(c.tri.getTeamStageId(1), 100001, "readback actual driver ID")
                eq(eventCount(c, "enter_gold_mine"), 1, "real Dialog emits successful event once")
                check(c.tm.isGroupCompleted(15) and not c.dialog.isOpen(), "only successful event completes and closes")
                eq(c.persists, persists + 1, "completion persisted once before fade")
                c.invoke("HandleMouseButtonUpHorizon")
                eq(#c.sceneCalls, 1, "duplicate mouse up inert")
                eq(c.tri.getTeamStageId(2), 201, "team2 unchanged")
                eq(c.tri.getTeamStageId(3), 301, "team3 unchanged")
                eq(c.nav, 3, "successful task keeps nav3")
                check(same(ledger(c), before), "no save/economy/module ledger write from tested closure")
                audit(c)
            end
        end
    end
end
local function touchCases()
    for _, ratio in ipairs({ 1, 2, 3 }) do
        local c = readyContext(); c.rt.dpr, c.rt.frameScale, c.rt.frameOx, c.rt.frameOy = ratio, 0.8, 37, 23
        c.draw(); bindInput(c)
        local x, y = screen(c, 605, 860)
        local primary, secondary = c.touch(41, x, y), c.touch(42, x, y)
        c.invoke("HandleTouchBeginHorizon", primary)
        c.invoke("HandleTouchBeginHorizon", secondary); c.invoke("HandleTouchEndHorizon", secondary)
        eq(#c.sceneCalls, 0, "secondary can't release primary")
        c.clock.elapsedTime = c.clock.elapsedTime + 0.2; c.invoke("HandleTouchEndHorizon", primary)
        eq(#c.sceneCalls, 1, "physical touch DPR/frame reaches task once")
        eq(eventCount(c, "enter_gold_mine"), 1, "touch event from real Dialog")
        c.invoke("HandleTouchEndHorizon", primary); c.invoke("HandleTouchEndHorizon", secondary)
        eq(#c.sceneCalls, 1, "duplicate touch up inert")
        audit(c)
        local r = readyContext(); r.rt.dpr = ratio; bindInput(r)
        local rx, ry = screen(r, 605, 860)
        r.invoke("HandleTouchBeginHorizon", r.touch(61, rx, ry))
        r.invoke("HandleTouchMoveHorizon", r.touch(61, rx + 100, ry + 150))
        r.clock.elapsedTime = r.clock.elapsedTime + 0.2
        r.invoke("HandleTouchEndHorizon", r.touch(61, rx + 100, ry + 150))
        eq(#r.sceneCalls, 0, "drag out doesn't submit resource task")
        eq(eventCount(r, "enter_gold_mine"), 0, "drag out doesn't fake completion")
        r.tick(0.6); r.settle(); r.draw(); target(r)
        r.invoke("HandleTouchBeginHorizon", r.touch(62, rx, ry)); r.clock.elapsedTime = r.clock.elapsedTime + 0.2
        r.invoke("HandleTouchEndHorizon", r.touch(62, rx, ry))
        eq(#r.sceneCalls, 1, "cancelled drag releases capture for new touch")
        audit(r)
    end
end
local function staleGestureCases()
    for _, ratio in ipairs({ 1, 2, 3 }) do
        for _, kind in ipairs({ "mouse", "touch" }) do
            local c = readyContext(); c.rt.dpr = ratio; bindInput(c)
            local x, y = screen(c, 605, 860)
            c.pointer(x, y)
            c.invoke("HandleMouseWheelHorizon", { Wheel = { GetInt = function() return -1 end } })
            c.draw()
            eq(c.tm.getCurrentHotspot(), nil, "wheel scrolled first row out: no stale hotspot")
            eq(#c.sceneCalls, 0, "tutorial wheel never submits a task")
            c.tick(0.6); c.tick(0.6); c.draw(); target(c)
            local _, _, fit = c.tri.getDialogTransform(c.rt.logicalW, c.rt.logicalH)
            if kind == "mouse" then
                c.pointer(x, y); c.invoke("HandleMouseButtonDownHorizon")
                c.pointer(x, y + 80 * fit); c.invoke("HandleMouseMoveHorizon")
                c.pointer(x, y); c.invoke("HandleMouseMoveHorizon")
            else
                c.invoke("HandleTouchBeginHorizon", c.touch(81, x, y))
                c.invoke("HandleTouchMoveHorizon", c.touch(81, x, y + 80 * fit))
                c.invoke("HandleTouchMoveHorizon", c.touch(81, x, y))
            end
            c.draw()
            local dragged = assert(c.tm.getCurrentHotspot(), "dragged first-row visible clip")
            -- touch整数物理像素量化允许一个设计像素内偏差；mouse保持精确oracle。
            check(math.abs(dragged.h - (140 - 80 + 4)) <= (kind == "touch" and 1 or 0.00001),
                "out-and-back leaves real80 scroll rather than starting position " .. kind)
            local prepares = count(c, "dialog.prepare")
            -- real moved先锁存；恢复重置rowScroll后，持按.6+.6跨settle .45才放手。
            c.tick(0.6); c.draw(); c.tick(0.6); c.draw(); target(c)
            check(count(c, "dialog.prepare") > prepares, "held gesture crossed actual recovery " .. kind)
            if kind == "mouse" then
                c.pointer(x, y); c.invoke("HandleMouseButtonUpHorizon")
            else c.invoke("HandleTouchEndHorizon", c.touch(81, x, y)) end
            eq(#c.sceneCalls, 0, "held out-and-back cannot become click after recovery " .. kind)
            eq(eventCount(c, "enter_gold_mine"), 0, "stale held gesture no completion event " .. kind)
            check(not c.tm.isGroupCompleted(15), "stale release keeps guide active " .. kind)
            if kind == "mouse" then c.click(x, y)
            else
                c.invoke("HandleTouchBeginHorizon", c.touch(82, x, y)); c.clock.elapsedTime = c.clock.elapsedTime + 0.2
                c.invoke("HandleTouchEndHorizon", c.touch(82, x, y))
            end
            eq(#c.sceneCalls, 1, "next genuine tap works after stale release " .. kind)
            eq(eventCount(c, "enter_gold_mine"), 1, "only next genuine tap success event " .. kind)
            audit(c)
        end
    end
end
local function submissionCases()
    local c = readyContext(); bindInput(c); local x, y = screen(c, 605, 860)
    local before, persists = ledger(c), c.persists
    c.sceneAccept = false; c.click(x, y)
    eq(#c.sceneCalls, 1, "real BTP attempts rejected Scene.gotoStage")
    eq(#c.starts, 0, "rejected Scene doesn't start driver")
    eq(eventCount(c, "enter_gold_mine"), 0, "rejected submit no event")
    check(c.dialog.isOpen() and not c.tm.isGroupCompleted(15), "rejected task stays retryable")
    eq(c.persists, persists, "rejected task no progress persist")
    c.sceneAccept = true; c.click(x, y)
    eq(#c.sceneCalls, 2, "retry performs fresh actual submit")
    eq(eventCount(c, "enter_gold_mine"), 1, "retry completion from real Dialog")
    check(c.tm.isGroupCompleted(15) and same(ledger(c), before), "success without gameplay ledger mutation")
    local saved = copy(c.saved[#c.saved]); c.tm.notifyEvent("enter_gold_mine")
    eq(c.persists, persists + 1, "duplicate event no duplicate save")
    check(same(c.saved[#c.saved], saved), "persist history deep copied")
    c.tick(0.3); c.tm.init(c.vg, c.store, c.persist); c.tick(0); c.tick(2)
    check(c.tm.isGroupCompleted(15) and not c.tm.isActive(), "completed15 restart doesn't reopen")
    audit(c)
    local stale = readyContext(); stale.driverApply = false
    stale.dialog.handleInput(605, 860)
    eq(#stale.sceneCalls, 1, "stale readback actual submit attempted")
    eq(#stale.starts, 1, "start boundary invoked but intentionally no driver readback change")
    eq(stale.tri.getTeamStageId(1), 305, "wrong readback independent oracle")
    eq(eventCount(stale, "enter_gold_mine"), 0, "goto true without actual team ID not successful event")
    check(not stale.tm.isGroupCompleted(15), "wrong readback doesn't finish")
    audit(stale)
    -- 同关确认是Dialog自身契约；正常active15恢复会先被TM幂等完成，不强行绕过它。
    local current = readyContext(); current.drivers[1].stageId = 100001; current.sceneStage = 100001
    current.dialog.handleInput(605, 860)
    eq(#current.sceneCalls, 0, "already-current confirmation doesn't restart Scene")
    eq(#current.starts, 0, "already-current confirmation doesn't restart driver")
    eq(eventCount(current, "enter_gold_mine"), 1, "real Dialog current-task confirmation emits actual event")
    check(current.tm.isGroupCompleted(15) and not current.dialog.isOpen(), "current-task confirmation closes")
    audit(current)
    local other = readyContext(); other.memory.battle.maxStageId = 2501
    other.dialog.openDungeon(2, "equipment_vault"); other.dialog.handleInput(605, 860)
    eq(other.tri.getTeamStageId(2), 200001, "actual non-target team task can submit outside tutorial pointer path")
    eq(eventCount(other, "enter_gold_mine"), 0, "wrong resource/team no gold event")
    check(not other.tm.isGroupCompleted(15), "wrong task never finishes gold guide")
    audit(other)
end
local function existingGoldCases()
    for _, stageId in ipairs({ 100001, 100006, 100003 }) do
        for _, stepIndex in ipairs({ 1, 2 }) do
            local c = newContext(); c.drivers[1].stageId, c.sceneStage = stageId, stageId
            local before, opens = ledger(c), count(c, "dialog.open")
            c.begin(stepIndex)
            check(c.tm.isGroupCompleted(15), "actual team1 gold already entered completes at resume " .. stageId)
            eq(eventCount(c, "enter_gold_mine"), 1, "TM readback completion emits once " .. stageId)
            eq(c.tri.getTeamStageId(1), stageId, "old gold ID retained exactly " .. stageId)
            eq(#c.sceneCalls, 0, "already-gold resume no Scene.gotoStage")
            eq(#c.starts, 0, "already-gold resume no Driver.start")
            eq(count(c, "dialog.open"), opens, "already-gold resume no Dialog reopen")
            check(same(ledger(c), before), "already-gold resume no gameplay ledger mutation")
            c.tick(0.3); c.tick(1)
            eq(eventCount(c, "enter_gold_mine"), 1, "completion doesn't replay after fade")
            check(not c.tm.isActive(), "already-gold guide releases input")
            audit(c)
        end
    end
    for _, team in ipairs({ 2, 3 }) do
        local c = newContext(); c.drivers[team].stageId = 100006
        c.begin(2); c.settle(); c.draw(); target(c)
        check(not c.tm.isGroupCompleted(15), "other team gold cannot skip team1 instruction")
        eq(eventCount(c, "enter_gold_mine"), 0, "other team gold no completion event")
        eq(c.tri.getTeamStageId(1), 305, "other team doesn't steal team1 task")
        audit(c)
    end
end
local function safetyCases()
    local c = newContext()
    local probes = {
        function() fixedFile(PROJECT .. "/scripts/main.lua", FILE_READ) end,
        function() fixedFile(SOURCE_FILES["config.GameConfig"], FILE_WRITE) end,
        function() source("ui.dungeon.DungeonPage") end,
        function() c.require("main") end, function() c.require("boot.Standalone") end,
        function() c.require("boot.StandaloneSave") end, function() c.require("core.PlayerStore") end,
        function() c.require("runtime.LocalActionBridge") end, function() c.require("unknown.Module") end,
        function() c.env.File("standalone_save.json", FILE_READ) end,
        function() c.env.File("standalone_save.json", FILE_WRITE) end,
        function() c.env.load("return _G") end, function() c.env.loadfile("main.lua") end,
        function() c.env.dofile("main.lua") end, function() return c.env.package.loaded end,
        function() return c.env.network.Connect end, function() return c.env.clientCloud.Set end,
        function() return c.env.cache.GetFile end, function() return c.env.fileSystem.Rename end,
        function() return c.env.unknownGlobal end, function() c.env.unknownAssignment = true end,
        function() return c.require("ui.dungeon.DungeonPage").isOpen end,
        function() return c.require("runtime.GameAction").sendAction("x", {}) end,
        function() return c.env.math.random() end,
    }
    for i, probe in ipairs(probes) do check(not pcall(probe), "strict dangerous probe " .. i) end
    local boundaryProbes = {
        function() c.require("rules.offline.OfflineService").PreviewTeamIncome() end,
        function() c.require("ui.widget.HeroFrame").initImages() end,
        function() c.require("ui.widget.HeroFrame").draw() end,
    }
    for i, probe in ipairs(boundaryProbes) do
        local before = #c.denied
        check(not pcall(probe), "unexercised Overview service/graphics boundary rejects " .. i)
        eq(#c.denied, before + 1, "Overview boundary denial recorded " .. i)
    end
    c.denied = {}; audit(c)
    local other = newContext()
    check(c.env ~= other.env and c.tm ~= other.tm and c.dialog ~= other.dialog and c.tri ~= other.tri,
        "loadenv and all actual module states isolated")
    local progress = other.tm.getProgress(); progress.completed["15"] = true; progress.queue[1] = 15
    check(not other.tm.isGroupCompleted(15) and #other.tm.getProgress().queue == 0, "progress snapshot detached")
    audit(other)
end
local function hostAudit()
    for _, c in ipairs(contexts) do audit(c) end
    for k, v in pairs(loadedBefore) do eq(package.loaded[k], v, "package original " .. tostring(k)) end
    for k, v in pairs(package.loaded) do eq(loadedBefore[k], v, "no package additions " .. tostring(k)) end
    local function equalValue(a, b) return a == b or type(a) == "number" and type(b) == "number" and a ~= a and b ~= b end
    for k, v in pairs(globalsBefore) do check(equalValue(_G[k], v), "host global original " .. tostring(k)) end
    for k, v in pairs(_G) do check(equalValue(globalsBefore[k], v), "no host globals added " .. tostring(k)) end
    for _, resource in ipairs(reads) do
        check(ALLOWED_PATHS[PROJECT .. "/scripts/" .. resource] == true, "every cache read exact allowlisted script resource")
    end
    check(#reads > 0 and #fragments > 0, "audit covers actual sources and full production closures")
    check(SOURCE_FILES["ui.dungeon.DungeonPage"] == nil and SOURCE_FILES["boot.StandaloneSave"] == nil,
        "old page/save outside readable source set")
    eq(File, nativeFile, "host File never overwritten")
    eq(cache, nativeCache, "host cache never overwritten")
    eq(nvgCreateImage, nativeCreateImage, "host NanoVG never overwritten")
    check(sources["ui.battle.stage.ExpeditionOverview"] ~= nil and sources["config.ResourceDefs"] ~= nil,
        "new eager dependencies read as real allowlisted source")
    check(SOURCE_FILES["rules.offline.OfflineService"] == nil and sources["rules.offline.OfflineService"] == nil
        and SOURCE_FILES["ui.widget.HeroFrame"] == nil and sources["ui.widget.HeroFrame"] == nil,
        "unexercised Overview service/graphics remain rejecting boundaries, never real IO modules")
end
---@type any
local reviewContext, reviewVG = nil, nil
function HandleDungeonGuideReview()
    local pw, ph, ratio = graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()
    local w, h = pw / ratio, ph / ratio
    local c = reviewContext
    c.rt.logicalW, c.rt.logicalH, c.rt.windowW, c.rt.windowH = w, h, w, h
    c.rt.dpr = ratio
    -- 模式B逻辑帧+DPR；内部Dialog采用生产设计空间transform，Overlay用宿主逻辑空间。
    nvgBeginFrame(reviewVG, w, h, ratio)
    nvgBeginPath(reviewVG); nvgRect(reviewVG, 0, 0, w, h)
    nvgFillColor(reviewVG, nvgRGBA(20, 17, 14, 255)); nvgFill(reviewVG)
    c.draw()
    nvgEndFrame(reviewVG)
end
local function runCase(label, fn)
    groups = groups + 1
    local ok, why = pcall(fn)
    if ok then print(TAG .. "PASS " .. label)
    else failures = failures + 1; log:Write(LOG_ERROR, TAG .. "FAIL " .. label .. " " .. tostring(why)) end
end
function Start()
    loadedBefore, globalsBefore = {}, {}
    for k, v in pairs(package.loaded) do loadedBefore[k] = v end
    for k, v in pairs(_G) do globalsBefore[k] = v end
    eq(ROOT, PROJECT, "explicit intended project root")
    eq(fileSystem:GetCurrentDir():gsub("/+$", ""), CWD, "isolated validation cwd required")
    if REVIEW ~= "" then
        eq(REVIEW, "gold", "only explicit optional gold review")
        reviewVG = assert(nvgCreate(1)); check(nvgCreateFont(reviewVG, "sans", "Fonts/MiSans-Regular.ttf") >= 0, "review font once")
        reviewContext = newContext(true, reviewVG); reviewContext.begin(2); reviewContext.settle()
        SubscribeToEvent(reviewVG, "NanoVGRender", "HandleDungeonGuideReview")
        print(TAG .. "REVIEW gold: actual Dialog/Overlay/Horizon projection and BTP transform; no main/combat/save.")
        return
    end
    runCase("strict-source-loadenv-danger-probes", safetyCases)
    runCase("real-config15-event-pointer-and-first-resource-ID", contractCases)
    runCase("active15-reset-restart-already-open-nav3-idempotent", recoveryCases)
    runCase("higher-priority-blockers-preserved-current-target-exception-only", blockerCases)
    runCase("queue15-noarg-blocking-quiet-dedup-restart", queueCases)
    runCase("real-Dialog-stable-gold-team1-first-unlocked-register", registrationCases)
    runCase("dedicated-tri-modal-leaves-old-modal-and-Viewport-unchanged", legacyModalCases)
    runCase("real-draw-Horizon-project-input-DPR123-outer-frame", geometryInputCases)
    runCase("real-touch-secondary-duplicate-up-drag-cancel", touchCases)
    runCase("held-row-drag-recovery-stale-release-no-false-event", staleGestureCases)
    runCase("real-Dialog-event-submit-reject-readback-retry-current-confirm", submissionCases)
    runCase("actual-team1-gold-first-anchor-legacy-ID-idempotent-resume", existingGoldCases)
    runCase("host-package-global-source-ledger-audit", hostAudit)
    print(TAG .. "RESULT " .. (failures == 0 and "ALL PASS" or "FAIL") .. " groups=" .. groups .. " checks=" .. checks .. " failures=" .. failures)
    print(TAG .. "LIMIT: Driver/Scene/ensureDrivers are memory boundaries; actual setTeams/save/combat not exercised.")
    if failures > 0 then log:Write(LOG_ERROR, TAG .. "validation assertions failed=" .. failures) end
    -- 官方validate帧预算退出；不以进程退出码替代断言和报告。
end
function Stop()
    if reviewVG then nvgDelete(reviewVG); reviewVG = nil end
end
