-- 独立Runtime复现入口；基于现有equipment_workspace_smoke_test真模块夹具与2D生命周期。
-- 只读cache中的生产源码，不加载正式main/Boot，不访问任何玩家File/存档。
-- 运行：tests/equipment_ascend_freeze_repro.lua -tool_mode -graphicssurfaceless
-- 可选：-repro-inventory=360 -repro-quality=6 -repro-heroes=12 -repro-start=4
-- 证据由Runtime stdout/-log/-validate-output写入.git/ascend-freeze-validation。
local TAG = "[ascend-freeze-repro]"
local ctx = { modules = {}, metrics = {}, errors = {}, stage = "setup", frames = 0,
    fileAttempts = 0, saveAttempts = 0, actions = {}, assertions = 0, inventory = 12,
    quality = 1, heroes = 4, ascendStart = 0, bulkTarget = 20, done = false, clock = 30,
    item = "W1", selectedSeq = 1, stageMetrics = {} }
---@type NVGContextWrapper?
local vg = nil
local env = setmetatable({}, { __index = _G })
env._G = env
local nativeTime = time

local function traceback(err)
    if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
    return tostring(err)
end
local function reportError(name, err)
    local key = name .. "|" .. tostring(err)
    local entry = ctx.errors[key]
    if not entry then entry = { count = 0, message = tostring(err) }; ctx.errors[key] = entry end
    entry.count = entry.count + 1
    if entry.count <= 2 then
        print(TAG .. " ERROR stage=" .. ctx.stage .. " frame=" .. ctx.frames .. " op=" .. name .. " " .. tostring(err))
    end
end
local function measured(name, fn, ...)
    local metricKey = ctx.stage .. "|" .. name
    local metric = ctx.metrics[metricKey]
    if not metric then metric = { calls = 0, total = 0, max = 0, errors = 0 }; ctx.metrics[metricKey] = metric end
    metric.calls = metric.calls + 1
    local before = os.clock()
    local result = table.pack(xpcall(fn, traceback, ...))
    local elapsed = (os.clock() - before) * 1000
    metric.total = metric.total + elapsed
    metric.max = math.max(metric.max, elapsed)
    if not result[1] then
        metric.errors = metric.errors + 1
        reportError(name, result[2])
        error(result[2], 0)
    end
    if elapsed > 50 then
        print(string.format("%s SLOW stage=%s frame=%d op=%s cpu_ms=%.3f", TAG, ctx.stage, ctx.frames, name, elapsed))
    end
    return table.unpack(result, 2, result.n)
end
local function probe(name, fn, ...)
    local result = table.pack(pcall(measured, name, fn, ...))
    return result[1], table.unpack(result, 2, result.n)
end
env.reproMeasure = measured
env.table = setmetatable({ sort = function(...) return measured("table.sort", table.sort, ...) end }, { __index = table })
local function check(condition, label)
    ctx.assertions = ctx.assertions + 1
    if not condition then reportError("assert", label) end
end
local function source(name)
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(cache:GetFile(path), "missing readonly source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n"), path
end
-- 硬隔离：任何模块File请求立即失败，连正式档只读访问也禁止。
env.File = function(path)
    ctx.fileAttempts = ctx.fileAttempts + 1
    error("REPRO_FORBIDDEN_FILE " .. tostring(path), 0)
end
env.fileSystem = { FileExists = function(_, path)
    print(TAG .. " ISOLATED FileExists=false path=" .. tostring(path))
    return false -- 未调用原生FS；其他UI只见空的隔离环境。
end, Rename = function() error("REPRO_FORBIDDEN_FS_RENAME") end,
    Delete = function() error("REPRO_FORBIDDEN_FS_DELETE") end }
env.time = { elapsedTime = ctx.clock }
local safeSave = { Flush = function()
    ctx.saveAttempts = ctx.saveAttempts + 1
    return true -- 只记请求，不序列化或写档；本入口不测试持久化。
end, RestoreData = function() error("REPRO_FORBIDDEN_RESTORE") end,
Update = function() error("REPRO_FORBIDDEN_SAVE_UPDATE") end }
env.require = function(name)
    if name == "boot.StandaloneSave" then return safeSave end
    assert(not name:match("^boot%.") or name == "boot.StandaloneRT", "REPRO_FORBIDDEN_BOOT " .. name)
    if name == "cjson" then return cjson end
    if name:match("^urhox%-libs") or name:match("^LuaScripts/") then return require(name) end
    if ctx.modules[name] then return ctx.modules[name] end
    local text, path = source(name)
    if name == "ui.backpack.BackpackGrids" then
        -- 仅读到内存后的透明计时包装，不写生产文件；draw里的local调用也必须捕获。
        text = text:gsub("local function getEquipList%(%)", "local function realGetEquipList()", 1)
        local insert = "    local function getEquipList() return reproMeasure('BackpackGrids.getEquipList', realGetEquipList) end\n"
        text = text:gsub("    local function drawEquipGrid%(vg%)", insert .. "    local function drawEquipGrid(vg)", 1)
    end
    local module = assert(load(text, "@/workspace/scripts/" .. path, "t", env))()
    ctx.modules[name] = module
    return module
end
local function mod(name) return env.require(name) end
local function wrap(moduleName, key)
    local target = mod(moduleName)
    local original = target[key]
    assert(type(original) == "function", "missing instrumentation " .. moduleName .. "." .. key)
    target[key] = function(...) return measured(moduleName .. "." .. key, original, ...) end
end
local function initialize()
    math.randomseed(10052026)
    for _, arg in ipairs(GetArguments()) do
        local k, v = arg:match("^%-repro%-([a-z]+)=(%d+)$")
        if k == "inventory" then ctx.inventory = math.min(1000, tonumber(v) or 12)
        elseif k == "quality" then ctx.quality = math.max(1, math.min(6, tonumber(v) or 1))
        elseif k == "heroes" then ctx.heroes = math.max(1, math.min(12, tonumber(v) or 4))
        elseif k == "start" then ctx.ascendStart = math.min(19, tonumber(v) or 0) end
        if arg == "-repro-item=O13" then ctx.item, ctx.selectedSeq = "O13", 2 end
        if arg == "-repro-unequipped" then ctx.selectedSeq = 7 end
        if arg == "-repro-spine=missing" then
            ---@diagnostic disable-next-line: assign-type-mismatch
            env.nvgSpineCreate = false -- 故障注入：false遮蔽环境fallback的真实扩展。
        end
        if arg == "-repro-spine=load-fail" then
            env.nvgSpineCreate = function()
                return measured("injected.SpineCreate", function()
                    return { Load = function() return false end, Dispose = function()
                        return measured("injected.SpineDispose", function() end)
                    end }
                end)
            end
        end
    end
    print(string.format("%s INPUT inventory=%d quality=%d heroes=%d ascend=%d bulkTarget=%d seed=10052026 save=blocked",
        TAG, ctx.inventory, ctx.quality, ctx.heroes, ctx.ascendStart, ctx.bulkTarget))
    local Store = mod("core.PlayerStore")
    Store.Init()
    local originalSubscribe = Store.Subscribe
    Store.Subscribe = function(key, callback)
        return originalSubscribe(key, function(...)
            return measured("subscriber." .. key, callback, ...)
        end)
    end
    local heroes = { roster = {}, deployed = {}, teams = {} }
    for id = 1, ctx.heroes do
        heroes.roster[id] = { level = 60, exp = 0, shards = 0, awakening = {}, extraTalent = {} }
        local t, slot = math.floor((id - 1) / 4) + 1, ((id - 1) % 4) + 1
        heroes.teams[t] = heroes.teams[t] or { slots = {} }
        heroes.teams[t].slots[slot] = id
        if t == 1 then heroes.deployed[slot] = id end
    end
    for t = 1, 3 do heroes.teams[t] = heroes.teams[t] or { slots = {} } end
    local Eq = mod("systems.EquipmentSystem")
    local equipment = { inventory = {}, equipped = {}, nextSeq = ctx.inventory + 1 }
    local ids = { "W1", "O1", "A31", "H31", "S31", "C1" }
    ctx.inventory = math.max(6, ctx.inventory)
    for seq = 1, ctx.inventory do
        local item = Eq.generate(ids[((seq - 1) % #ids) + 1], 1, ctx.quality)
        item.ascendLevel, item.enhanceLevel = ctx.ascendStart, ctx.ascendStart
        equipment.inventory[tostring(seq)] = item
    end
    equipment.equipped[1] = { weapon = 1, offhand = 2, armor = 3, helmet = 4, shoes = 5, accessory = 6 }
    if ctx.item == "O13" then
        equipment.inventory[tostring(ctx.selectedSeq)] = Eq.generate("O13", 1, ctx.quality)
        equipment.inventory[tostring(ctx.selectedSeq)].ascendLevel = ctx.ascendStart
        equipment.inventory[tostring(ctx.selectedSeq)].enhanceLevel = ctx.ascendStart
        if ctx.selectedSeq == 2 then
            equipment.equipped[1].offhand = nil
            equipment.equipped[2] = { offhand = 2 } -- 黄桃龙魔典，正式职业合法。
        end
    end
    print(TAG .. " ITEM " .. ctx.item .. " seq=" .. ctx.selectedSeq .. " equipped=" .. tostring(ctx.selectedSeq <= 6))
    local currency = { gold = 1000000000, gems = 100000, essence = 1000000,
        weaponScroll = 100000, offhandScroll = 100000, armorScroll = 100000,
        accessoryScroll = 100000, helmetScroll = 100000, shoesScroll = 100000 }
    local battle = { currentStageId = 101, maxStageId = 1905, battleMode = "idle", autoBattle = true,
        clearedStages = { ["101"] = true, ["905"] = true, ["1905"] = true },
        teamStageIds = { ["1"] = 101, ["2"] = 101, ["3"] = 101 } }
    local Dispatcher = mod("runtime.ClientDispatcher")
    Dispatcher.handleStateUpdate(cjson.encode({ modules = { heroes = heroes, equipment = equipment,
        currency = currency, player = { level = 60, exp = 0, maxExp = 10000 }, battle = battle,
        artifacts = { bag = {} }, talents = { litNodes = {0} },
        session = { introCompleted = true, claimedScenarios = { ["1"] = true } } } }))
    mod("core.GameState").syncFromCurrency(Dispatcher.get("currency"))
    mod("core.GameState").setLevel(60, { silent = true })
    vg = nvgCreate(1)
    assert(vg, "NanoVG initialization")
    nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
    for _, key in ipairs({ "hydrate", "applyToUnit", "computeModifierEntries", "generate" }) do
        wrap("systems.EquipmentSystem", key)
    end
    wrap("config.HeroConfig", "createHero")
    wrap("ui.battle.scene.BattleScene", "refreshAllyStats")
    wrap("ui.battle.scene.BattleScene", "reloadStage")
    wrap("ui.character.panel.CharacterPanel", "applyEquippedItems")
    wrap("ui.character.panel.CharacterPanel", "getDeployedTeam")
    wrap("ui.blacksmith.BlacksmithEnhance", "updateEnhanceData")
    wrap("ui.blacksmith.BlacksmithRefine", "updateRefineData")
    wrap("ui.blacksmith.BlacksmithEnhance", "onActionResult")
    wrap("ui.blacksmith.BlacksmithPage", "onEquipmentDataUpdate")
    wrap("rules.blacksmith.BlacksmithService", "AscendEquip")
    wrap("rules.blacksmith.BlacksmithService", "AscendEquipToLevel")
    wrap("ui.fx.SpineResultEffect", "play")
    wrap("ui.fx.SpineResultEffect", "draw")
    local CP, Scene = mod("ui.character.panel.CharacterPanel"), mod("ui.battle.scene.BattleScene")
    CP.init(vg)
    CP.setHeroesData(Dispatcher.get("heroes"))
    mod("ui.backpack.BackpackPanel").init(vg)
    Scene.init(vg)
    Scene.setAllies(CP.getDeployedTeam(1))
    Scene.setBattleData(Dispatcher.get("battle"))
    Scene.resume()
    mod("runtime.LocalActionBridge").init()
    local Msg = mod("runtime.ClientMessageHandler")
    Msg.setup({ sendAction = mod("runtime.GameAction").sendAction, ui = {} })
    Msg.setupDataSubscriptions()
    local originalResult = Msg.handleActionResult
    Msg.handleActionResult = function(data, ...)
        ctx.actions[#ctx.actions + 1] = data
        return measured("ClientMessageHandler.result", originalResult, data, ...)
    end
    -- 正式入口也是此订阅补仓库脏标；记录但不改变订阅顺序/异常吞噬契约。
    local Forge = mod("ui.blacksmith.BlacksmithPage")
    Forge.init(vg)
    Forge.open()
    check(Forge.setEquipBySeq(ctx.selectedSeq), "workbench selected")
    local Tri = mod("ui.battle.tri.BattleTriPage")
    Tri.init(vg)
    Tri.open()
    print(TAG .. " SETUP COMPLETE true CharacterPanel/Backpack/Blacksmith/CMH/Bridge/Service/Tri")
end
local function actionFrame()
    local Forge = mod("ui.blacksmith.BlacksmithPage")
    if ctx.frames == 15 then
        ctx.stage = "single"
        print(TAG .. " ACTION single x307 y2129")
        probe("input.single", Forge.handleInput, 307, 2129)
        local equip = mod("runtime.ClientDispatcher").get("equipment").inventory[tostring(ctx.selectedSeq)]
        check(mod("systems.EquipmentSystem").getAscendLevel(equip) == ctx.ascendStart + 1, "single actual ascend")
    elseif ctx.frames == 35 and ctx.item == "O13" then
        ctx.stage = "single-second"
        print(TAG .. " ACTION second single x307 y2129")
        probe("input.single-second", Forge.handleInput, 307, 2129)
        local equip = mod("runtime.ClientDispatcher").get("equipment").inventory[tostring(ctx.selectedSeq)]
        check(mod("systems.EquipmentSystem").getAscendLevel(equip) == ctx.ascendStart + 2, "second single actual ascend")
    elseif ctx.frames == 45 then
        ctx.stage = "bulk-dialog"
        print(TAG .. " ACTION bulk open x770 y2129 then slider minimum-to20")
        probe("input.bulk-open", Forge.handleInput, 770, 2129)
        local Enhance = mod("ui.blacksmith.BlacksmithEnhance")
        check(Enhance.isDialogOpen(), "bulk confirmation opens")
        -- 正式拖动滑条，远征Lv60上限60；在[当前+1,60]间选择20，不直改dlg。
        local selected = mod("runtime.ClientDispatcher").get("equipment").inventory[tostring(ctx.selectedSeq)]
        local minLevel = mod("systems.EquipmentSystem").getAscendLevel(selected) + 1
        local x = 340 + 400 * (ctx.bulkTarget - minLevel) / (60 - minLevel)
        probe("input.bulk-slider", Forge.handleDragBegin, x, 1342)
        Forge.handleDragEnd(x, 1342)
    elseif ctx.frames == 55 then
        ctx.stage = "bulk"
        print(TAG .. " ACTION bulk confirm x540 y1503")
        probe("input.bulk-confirm", Forge.handleInput, 540, 1503)
        local equip = mod("runtime.ClientDispatcher").get("equipment").inventory[tostring(ctx.selectedSeq)]
        check(mod("systems.EquipmentSystem").getAscendLevel(equip) == ctx.bulkTarget, "bulk actual ascend20")
    elseif ctx.frames == 100 then
        ctx.stage = "closed"
        Forge.forceClose()
        print(TAG .. " ACTION close smith; continuing battle/backpack/right updates")
    end
end
local function updateFrame()
    actionFrame()
    probe("update.Dispatcher", mod("runtime.ClientDispatcher").update, 1/60)
    probe("update.CharacterPanel", mod("ui.character.panel.CharacterPanel").update, 1/60)
    probe("update.Backpack", mod("ui.backpack.BackpackPanel").update, 1/60)
    probe("update.Tri", mod("ui.battle.tri.BattleTriPage").update, 1/60)
end
local function renderFrame()
    if not vg or ctx.done then return end
    local dpr = graphics:GetDPR()
    local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local VP = mod("core.Viewport")
    local ox, oy, scale = VP.layout(w, h)
    nvgBeginFrame(vg, w, h, dpr)
    probe("draw.Tri", mod("ui.battle.tri.BattleTriPage").draw, vg, w, h)
    local Forge, Backpack = mod("ui.blacksmith.BlacksmithPage"), mod("ui.backpack.BackpackPanel")
    VP.begin(vg, VP.PANELS.center, ox, oy, scale)
    local forgeOK = probe("draw.Blacksmith", Forge.draw, vg)
    VP.finish(vg)
    if not forgeOK then
        -- 正式Horizon未对锻炉独立pcall：异常会截断其后的左栏绘制/帧收尾。
        -- 这里只补GPU帧收尾，以安全反复观测；不补画被正式时序阻断的左/右栏。
        nvgEndFrame(vg)
        return
    end
    VP.begin(vg, VP.PANELS.left, ox, oy, scale)
    probe("draw.Backpack", Backpack.draw, vg)
    VP.finish(vg)
    VP.begin(vg, VP.PANELS.right, ox, oy, scale)
    probe("draw.CharacterPanel", mod("ui.character.panel.CharacterPanel").draw, vg)
    VP.finish(vg)
    nvgEndFrame(vg)
end
local function finish()
    ctx.done = true
    local keys, errorCount = {}, 0
    for key in pairs(ctx.metrics) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local m = ctx.metrics[key]
        print(string.format("%s METRIC %s calls=%d cpu_total_ms=%.3f cpu_max_ms=%.3f errors=%d",
            TAG, key, m.calls, m.total, m.max, m.errors))
    end
    for _, entry in pairs(ctx.errors) do errorCount = errorCount + entry.count end
    print(string.format("%s SUMMARY frames=%d assertions=%d captured_errors=%d actions=%d blocked_file_attempts=%d save_requests_not_written=%d",
        TAG, ctx.frames, ctx.assertions, errorCount, #ctx.actions, ctx.fileAttempts, ctx.saveAttempts))
    print(TAG .. " END timings are CPU in software Runtime, not device/frame-performance certification")
    engine:Exit()
end
function Start()
    local ok = probe("setup", initialize)
    if not ok then finish(); return end
    ctx.stage = "baseline"
    SubscribeToEvent("Update", function()
        if ctx.done then return end
        ctx.frames = ctx.frames + 1
        ctx.clock = 30 + ctx.frames / 30 -- deterministic simulation; >.5s gate cooldown between actions
        env.time.elapsedTime = ctx.clock
        probe("frame.update", updateFrame)
        if ctx.frames % 30 == 0 then
            print(TAG .. " HEARTBEAT stage=" .. ctx.stage .. " frame=" .. ctx.frames
                .. " spine_playing=" .. tostring(mod("ui.fx.SpineResultEffect").isPlaying()))
        end
        if ctx.frames >= 150 then finish() end
    end)
    SubscribeToEvent(vg, "NanoVGRender", function() probe("frame.render", renderFrame) end)
end
function Stop()
    env.time = nativeTime
    if vg then nvgDelete(vg); vg = nil end
end
