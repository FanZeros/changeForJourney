-- 真实 BackpackPanel -> Host -> Grids -> EquipmentPower，500件冷列表预算回归。
-- Runtime: tests/backpack_performance_test.lua -tool_mode -graphicsheadless -nosound
-- 仅cache源码读取/内存Store/CPU绘图记录；不启动main/Boot，不访问玩家File。
local TAG = "[backpack_performance_test]"
local assertions, failures = 0, 0
local function check(ok, message)
    assertions = assertions + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. message) end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function fixture()
    local data, revisions, modules = {}, {}, {}
    local counts = { evaluate = 0, apply = 0, power = 0, build = 0, io = 0, hydrate = 0 }
    local metrics = { drawEvaluate = 0, drawPower = 0, updateMaxMs = 0, updateMaxEvaluate = 0, pumps = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G, env.time = env, { elapsedTime = 100 }
    env.package = { loaded = modules, preload = {}, path = "" }
    env.File = function() counts.io = counts.io + 1; error("player IO forbidden") end
    env.fileSystem = setmetatable({}, { __index = function()
        return function() counts.io = counts.io + 1; error("player IO forbidden") end
    end })
    local drawIds, detailOpens, actions, messages = {}, {}, {}, {}
    local selected, owner, pinned = nil, nil, false
    local noop = function() end
    local function hit(x, y, cx, cy, w, h) return math.abs(x - cx) <= w / 2 and math.abs(y - cy) <= h / 2 end
    local store = { Get = function(key) return data[key] end,
        GetRevision = function(key) return revisions[key] or 0 end,
        Subscribe = noop, Unsubscribe = noop }
    modules["core.PlayerStore"] = store
    local draw = { hitTest = hit, drawImageCentered = noop, drawTextStroke = noop, drawShardIcon = noop,
        seamSlideX = function() return 0 end }
    modules["core.DrawUtil"] = draw
    modules["core.DarkIcon"] = { drawNine = noop, drawQualityBg = noop, drawIconDark = noop, draw = noop,
        QUALITY_TRIM = { { 1, 2, 3 }, { 1, 2, 3 }, { 1, 2, 3 }, { 1, 2, 3 }, { 1, 2, 3 }, { 1, 2, 3 } } }
    modules["core.I18n"] = { t = function(s) return s end, lookup = function(s) return s end,
        format = string.format }
    modules["core.GameState"] = {}
    modules["core.UiToast"] = { show = function(s) messages[#messages + 1] = s end }
    modules["ui.widget.ImageCache"] = { init = noop, getEquipIcon = function(id)
        drawIds[#drawIds + 1] = id; return -1
    end }
    modules["ui.widget.QualityMark"] = { init = noop, draw = noop }
    modules["ui.widget.HeroFrame"] = { initImages = noop, draw = noop }
    modules["ui.widget.SetFilterDialog"] = { NONE_KEY = "none", close = noop, draw = noop,
        countSelected = function(t) local n = 0; for _, v in pairs(t) do if v then n = n + 1 end end; return n end,
        isOpen = function() return false end, handleHover = function() return false end }
    modules["ui.widget.EquipmentSetIcon"] = { drawBadge = noop, hasBadge = function() return false end,
        badgeLayout = function(cx, cy, size) return { x = cx - size / 2, size = size / 4 } end,
        levelLayout = function(_, cx, cy) return { x = cx + 70, y = cy + 70, fontSize = 30, align = 0 } end }
    modules["ui.hud.popup.SettingsPanel"] = { isEquipmentPowerEnabled = function() return true end }
    modules["config.HeroAssetUtil"] = { preloadIcons = noop }
    modules["ui.character.panel.CharacterPanel"] = { getShards = function() return 0 end }
    modules["ui.character.detail.CharacterDetail"] = { getHeroId = function() return 1 end,
        isEquipTab = function() return true end, markPowerDirty = noop }
    modules["ui.character.equip.EquipmentDetail"] = {
        init = noop, drawIf = noop, getOwner = function() return owner end,
        isOpen = function() return selected ~= nil end, isPinned = function() return pinned end,
        open = function(seq) selected, owner = seq, "backpack"; detailOpens[#detailOpens + 1] = seq end,
        close = function() selected, owner, pinned = nil, nil, false end,
        dismissHover = function() if not pinned then selected, owner = nil, nil end end,
        pin = function() pinned = true end, setComparisonSlot = noop, setAnchor = noop,
        handleInput = function() return false end,
    }
    modules["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop }
    modules["systems.GameSFX"] = { playUIMove = noop, play = noop }
    modules["systems.TutorialManager"] = { isActive = function() return false end, notifyEvent = noop }
    modules["ui.loot.InventoryCurationDialog"] = { cancelSource = noop, drawEntry = noop }
    modules["ui.blacksmith.BlacksmithDecompose"] = { cancelMarquee = noop }
    modules["ui.backpack.BackpackItems"] = {}
    modules["ui.backpack.BackpackDialogs"] = { bind = function() return { closeTransferConfirm = noop } end }
    modules["ui.backpack.BackpackWindow"] = { bind = function() return noop, noop end }
    modules["runtime.GameAction"] = { sendAction = function(action, payload)
        actions[#actions + 1] = { action = action, payload = payload }; return true
    end }
    modules["ui.town.TownPageChrome"] = { easeOutCubic = function(t) return t end,
        easeInCubic = function(t) return t end, easeInOutCubic = function(t) return t end,
        drawNamePlate = noop, drawBack = noop, drawTabBar = noop,
        tabSlide = function() return 1, 1, 1 end, hitBack = function() return false end,
        hitTab = function(x, y)
            if y == 2308 and x == 540 then return 2 end
            if y == 2308 and x == 274 then return 1 end
        end }
    -- 菜单控件树不是本专项对象；保留真实Panel筛选状态并记录onChange适配。
    local filters = {}
    modules["ui.backpack.BackpackFilters"] = { attachInput = noop, bindWarehouse = function(state)
        filters.state = state
        return { close = noop, draw = noop, drawOverlay = noop, isOpen = function() return false end,
            handleInput = function() return false end }
    end }
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScissor", "nvgTranslate", "nvgScale", "nvgGlobalAlpha",
        "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth",
        "nvgStroke", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText" }) do env[name] = noop end
    env.nvgRGBA = function() return {} end
    env.nvgTextBounds = function(_, _, _, text) return #text * 12 end
    env.require = function(name)
        if modules[name] ~= nil then return modules[name] end
        assert(not name:match("^boot%.") and not name:match("^runtime%."), "undeclared dependency " .. name)
        local value = assert(load(source(name), "@backpack-private/" .. name, "t", env))()
        modules[name] = assert(value, name)
        if name == "systems.EquipmentPower" then
            for method, counter in pairs({ evaluate = "evaluate", buildContext = "build" }) do
                local original = value[method]
                value[method] = function(...)
                    counts[counter] = counts[counter] + 1
                    return original(...)
                end
            end
        elseif name == "systems.EquipmentSystem" then
            for method, counter in pairs({ applyEquip = "apply", hydrate = "hydrate" }) do
                local original = value[method]
                value[method] = function(...)
                    counts[counter] = counts[counter] + 1
                    return original(...)
                end
            end
        elseif name == "systems.CombatPower" then
            local original = value.calculate
            value.calculate = function(...) counts.power = counts.power + 1; return original(...) end
        end
        return value
    end
    local panel = env.require("ui.backpack.BackpackPanel")
    local EP, EC = env.require("systems.EquipmentPower"), env.require("config.EquipmentConfig")
    local Eq = env.require("systems.EquipmentSystem")
    local Grids = env.require("ui.backpack.BackpackGrids")
    local latestGrids = {}
    local bind = Grids.bind
    Grids.bind = function(deps)
        local grids = bind(deps)
        latestGrids = grids
        return grids
    end
    local f = { panel = panel, EP = EP, EC = EC, Eq = Eq, data = data, counts = counts,
        metrics = metrics, env = env, filters = filters, actions = actions, detailOpens = detailOpens, drawIds = drawIds }
    function f.notify(key, invalidate)
        revisions[key] = (revisions[key] or 0) + 1
        if invalidate ~= false then EP.invalidate() end
    end
    function f.initialize()
        data.heroes = { roster = { [1] = { level = 80, awakening = {}, extraTalent = {} },
            [2] = { level = 80, awakening = {}, extraTalent = {} } },
            teams = { { slots = { 1, 2 } }, { slots = {} }, { slots = {} } }, deployed = { 1, 2 } }
        data.equipment = { inventory = {}, equipped = { [1] = {}, [2] = {} } }
        data.artifacts, data.talents = { bag = {}, equippedByTeam = {} }, { litNodes = {} }
        data.currency = { gold = 0 }
        for i = 1, 500 do
            local tid = EC.BY_SLOT.accessory[((i - 1) % #EC.BY_SLOT.accessory) + 1]
            local item = Eq.generate(tid, 30 + i % 40, 1 + i % 6)
            item.seq = i
            data.equipment.inventory[tostring(i)] = item
        end
        for _, key in ipairs({ "heroes", "equipment", "artifacts", "talents" }) do f.notify(key) end
    end
    function f.grids() return latestGrids end
    function f.list() return latestGrids.getCommittedEquipList() end
    function f.expFlow(replace)
        if replace then data.heroes = copy(data.heroes) end
        data.heroes.roster[1].exp = (data.heroes.roster[1].exp or 0) + 1
        for _, team in ipairs(data.heroes.teams) do team.exp = (team.exp or 0) + 1 end
        data.heroes.gold = (data.heroes.gold or 0) + 1
        data.currency.gold = data.currency.gold + 10
        f.notify("heroes"); f.notify("currency")
    end
    function f.draw()
        for i = #drawIds, 1, -1 do drawIds[i] = nil end
        local before = copy(counts)
        panel.draw({})
        metrics.drawEvaluate = metrics.drawEvaluate + counts.evaluate - before.evaluate
        metrics.drawPower = metrics.drawPower + counts.power - before.power
        check(counts.evaluate == before.evaluate and counts.apply == before.apply and counts.power == before.power
            and counts.build == before.build and counts.hydrate == before.hydrate, "Render contains no scoring/context/hydration")
    end
    function f.update()
        local before, start = counts.evaluate, os.clock()
        panel.update(1 / 60)
        metrics.updateMaxMs = math.max(metrics.updateMaxMs, (os.clock() - start) * 1000)
        metrics.updateMaxEvaluate = math.max(metrics.updateMaxEvaluate, counts.evaluate - before)
        metrics.pumps = metrics.pumps + 1
        check(counts.evaluate - before <= 128, "Update evaluation bounded independently of inventory size")
    end
    function f.finish(expected, stream)
        for frame = 1, 20000 do
            if stream then f.expFlow(frame % 5 == 0) end
            f.update()
            local list = f.list()
            check(#list == 0 or #list == expected, "private list never partially publishes")
            f.draw()
            if #list == expected then return list, frame end
        end
        error("budget queue starvation")
    end
    f.initialize()
    return f
end

local function runTests()
    local f = fixture()
    local panel, data, metrics = f.panel, f.data, f.metrics
    local inventoryBefore = copy(data.equipment)
    panel.open("left", "equip")
    panel.setEquipmentSlotFilter(nil, 1)
    f.draw()
    check(#f.drawIds == 0 and f.counts.evaluate == 0 and f.counts.build == 0, "500 cold candidates not scored in first draw")
    check(panel.peekEquipAt(160, 840) == nil, "cold list has no hit target")
    f.update()
    check(#f.list() == 0 and panel.peekEquipAt(160, 840) == nil, "partial context never exposed")
    local list, frames = f.finish(500, true)
    check(frames > 1 and #list == 500, "500 entries complete under continuous roster/team exp and currency notifications")
    check(f.counts.build == 1, "exp replacement/invalidation never restarts private context")
    check(#f.drawIds > 0 and #f.drawIds < 100, "real grid only draws viewport after full scoring finishes")
    check(equal(data.equipment, inventoryBefore), "snapshot/hydrate/preview never mutate live inventory or equipped")
    local first = list[1]
    local peek = panel.peekEquipAt(160, 840)
    check(peek and peek.seq == first.seq and f.drawIds[1] == first.templateId, "draw and peek share presented order")
    panel.handleHover(160, 840); f.env.time.elapsedTime = f.env.time.elapsedTime + 0.4; panel.handleHover(160, 840)
    check(f.detailOpens[#f.detailOpens] == first.seq, "hover opens same displayed seq")
    panel.handleInput(160, 840)
    check(f.detailOpens[#f.detailOpens] == first.seq, "single click pins same displayed seq")
    panel.handleRightClick(160, 840)
    check(#f.actions == 1 and f.actions[1].payload.seq == first.seq, "right click submits same displayed seq through authoritative precheck")
    local stableBuilds, stableEvaluations = f.counts.build, f.counts.evaluate
    for i = 1, 20 do f.expFlow(i % 2 == 0); f.update(); f.draw() end
    check(f.list() == list and f.counts.build == stableBuilds and f.counts.evaluate == stableEvaluations,
        "completed list stable under continued equal notifications")

    -- Update完成新列表但Render尚未展示时，不能点击一个未见过的新排序。
    f.filters.state.sortKey, f.filters.state.sortAscending = "level", true
    check(panel.peekEquipAt(160, 840) == nil, "new sort blocks old cell immediately")
    f.draw(); check(#f.drawIds == 0, "new sort draws no stale old list")
    for i = 1, 20000 do f.update(); if #f.list() == 500 then break end end
    check(#f.list() == 500 and panel.peekEquipAt(160, 840) == nil, "new commit cannot be hit before it is rendered")
    f.draw()
    list = f.list()
    peek = panel.peekEquipAt(160, 840)
    check(peek and peek.seq == list[1].seq and list[1].level <= list[500].level, "new rendered ascending level order is clickable")

    -- 评分中途筛选/装备/真实成长更换：撤销旧版本，不partialpublish。
    f.filters.state.sortKey = "power"
    f.update()
    f.filters.state.qualitySet[6] = true
    f.update()
    data.equipment.inventory["1"].locked = true
    f.notify("equipment")
    f.update()
    data.heroes.roster[2].extraTalent = { issuedCards = 4 }
    f.notify("heroes")
    check(panel.peekEquipAt(160, 840) == nil and #f.list() == 0, "real equipment/team growth cancels stale candidates")
    local count = 0
    for _, item in pairs(data.equipment.inventory) do if item.quality == 6 then count = count + 1 end end
    list = f.finish(count, true)
    for _, item in ipairs(list) do check(item.quality == 6, "only new quality filter committed") end

    -- 同步查询穿插：保留独立即时完整结果，不yield、不篡改在途ctx。
    f.filters.state.qualitySet, f.filters.state.sortKey = {}, "level"
    f.update()
    local synchronous = f.grids().getEquipList()
    check(#synchronous == 500 and coroutine.isyieldable() == false, "explicit synchronous query retains immediate full result")
    local synchronousAgain = f.grids().getEquipList()
    check(synchronous == synchronousAgain, "explicit synchronous cache identity retained")
    f.draw(); f.update()
    check(f.list() == synchronous, "synchronous complete result atomically usable without partial task overwrite")
    local EP = f.EP
    f.filters.state.sortAscending = false
    f.update()
    local context = EP.getContext(1)
    local score = EP.score(data.equipment.inventory["10"], 1)
    local preview = EP.evaluate(context, 10)
    check(type(score) == "number" and preview ~= nil, "synchronous getContext/score/evaluate still independent during private work")
    list = f.finish(500, true)
    check(list[1].level >= list[500].level, "private work finishes correct descending order after sync scoring")
    local function parity(label)
        local async = f.list()
        local synchronousList = f.grids().getEquipList()
        check(#async == #synchronousList, label .. " sync/async length")
        for i, item in ipairs(async) do
            local other = synchronousList[i]
            check(other and item.seq == other.seq and item.power == other.power and item.canWear == other.canWear
                and item.upgrade == other.upgrade and item.cannotEquipReason == other.cannotEquipReason,
                label .. " sync/async authoritative score/order/grey/recommendation " .. i)
        end
    end
    parity("generated full inventory")
    data.equipment.inventory["1"] = { templateId = "C1", level = 999, quality = 3 }
    data.equipment.inventory["2"] = { templateId = "A55", level = 1, quality = 3 }
    data.equipment.inventory["3"] = { templateId = "W1", level = 1, quality = 3 }
    f.notify("equipment")
    f.finish(500, true)
    parity("lean invalid-level/class and valid candidate")
    -- 原同步score优先equip.seq；只有缺seq才按源实例identity反查库存键。
    data.equipment.inventory["4"].seq = 5
    data.equipment.inventory["6"].seq = nil
    f.notify("equipment")
    f.finish(500, true)
    parity("mismatched seq/key and missing seq")
    panel.setEquipmentSlotFilter("weapon", 1)
    f.finish(1, true)
    parity("weapon structural selection")
    panel.setEquipmentSlotFilter(nil, 1)
    f.finish(500, true)

    -- 无通知的本地成长patch同样必须被commit终检和读取端发现。
    local growth = data.heroes.roster[1].extraTalent
    growth.issuedCards = 5
    check(#f.list() == 0 and panel.peekEquipAt(160, 840) == nil, "no-notify same-table growth invalidates committed list")
    f.update()
    growth.issuedCards = 6
    check(#f.list() == 0, "no-notify growth during private snapshot never exposes mixed result")
    list = f.finish(500, true)
    check(#list == 500, "no-notify growth restarts and finishes full latest version")

    -- 各战斗输入（包括原地名册值）不可错误忽略。
    local changes = {
        { "level", "heroes", function() data.heroes.roster[1].level = 81 end },
        { "team", "heroes", function() data.heroes.teams[1].slots = { 2, 1 } end },
        { "awakening", "heroes", function() data.heroes.roster[1].awakening = { [1] = true } end },
        { "branch", "heroes", function() data.heroes.roster[1].advBranch = { first = 104 } end },
        { "talent", "talents", function() data.talents.litNodes = { 113 } end },
        { "artifact", "artifacts", function() data.artifacts.bag = {} end },
        { "equipped", "equipment", function() data.equipment.equipped[1].accessory = 1 end },
    }
    for _, case in ipairs(changes) do
        local before = f.list()
        case[3](); f.notify(case[2])
        check(#f.list() == 0 and panel.peekEquipAt(160, 840) == nil, case[1] .. " invalidates before update")
        list = f.finish(500, true)
        check(list ~= before, case[1] .. " publishes fresh complete version")
    end
    -- 离页/关闭撤销，重入绝不恢复半成品；正式Store清根/换玩家identity模型。
    f.filters.state.sortKey = "power"; f.update()
    panel.handleInput(540, 2308); f.update()
    check(#f.list() == 0, "leaving equip tab cancels private work")
    panel.handleInput(274, 2308); f.update()
    panel.close(); f.update()
    check(#f.list() == 0, "close cancels private list immediately")
    panel.open("left", "equip"); panel.setEquipmentSlotFilter(nil, 1)
    f.draw(); check(#f.drawIds == 0, "reentry never publishes prior session partial list")
    f.update()
    for _, key in ipairs({ "equipment", "heroes", "artifacts", "talents" }) do data[key] = copy(data[key]); f.notify(key) end
    check(#f.list() == 0, "player module root replacement discards prior player snapshot")
    f.finish(500, true)
    check(metrics.drawEvaluate == 0 and metrics.drawPower == 0 and f.counts.io == 0, "all draw paths zero evaluations and no player IO")
    print(string.format("%s METRICS coldFrames=%d updateMaxMs=%.3f updateMaxEvaluate=%d pumps=%d drawEvaluate=%d drawPower=%d",
        TAG, frames, metrics.updateMaxMs, metrics.updateMaxEvaluate, metrics.pumps, metrics.drawEvaluate, metrics.drawPower))
end

function Start()
    local ok, err = pcall(runTests)
    if not ok then check(false, "exception: " .. tostring(err)); print(TAG .. " " .. tostring(err)) end
    print(string.format("%s SUMMARY assertions=%d failures=%d %s", TAG, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
