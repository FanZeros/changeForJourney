-- 冷详情Update->Render隔离回归；仅cache读源码/内存Store/CPU绘图spy，禁止玩家File/FS。
-- Runtime: tests/character_detail_performance_test.lua -tool_mode -graphicsheadless -nosound
local TAG = "[character_detail_performance_test]"
local assertions, failures = 0, 0
local function check(ok, text)
    assertions = assertions + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. text) end
end
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function source(name)
    local f = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), name)
    local lines = {}; while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end; f:Dispose()
    return table.concat(lines, "\n")
end

local function fixture()
    local data, revisions, modules = {}, {}, {}
    local noop = function() end
    local counts = { build = 0, context = 0, evaluate = 0, score = 0, gain = 0, preview = 0, attrs = 0, io = 0, hydrate = 0 }
    local selection = nil
    local actions, icons, latest = {}, {}, {}
    local cards = 0
    local metrics = { drawColdBuild = 0, updateMaxMs = 0, updates = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G, env.time, env.H_SEAM_BACK = env, { elapsedTime = 100 }, true
    env.File = function() counts.io = counts.io + 1; error("player IO forbidden") end
    env.fileSystem = setmetatable({}, { __index = function() return env.File end })
    local store = { Get = function(k) return data[k] end, GetRevision = function(k) return revisions[k] or 0 end,
        Subscribe = noop, Unsubscribe = noop }
    modules["core.PlayerStore"] = store
    modules["runtime.ClientDispatcher"] = { get = store.Get }
    modules["core.I18n"] = { get = function() return "zh" end, t = function(s) return s end,
        lookup = function(s) return s end, format = string.format }
    modules["core.GameState"] = {}
    modules["core.DrawUtil"] = { drawTextStroke = noop, drawImageCentered = noop, drawCardImage = function() cards = cards + 1 end,
        seamSlideX = function() return 0 end }
    modules["core.DarkIcon"] = { drawNine = noop, drawQualityBg = noop, drawIconDark = noop, draw = noop }
    modules["core.BattleLayout"] = { CARD_W = 198, CARD_H = 198 * 955 / 538 }
    modules["config.HeroAssetUtil"] = { ensureCard = function() return 1 end }
    modules["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop }
    modules["systems.TutorialManager"] = { getPreferredCharacterTab = function() return "equip" end,
        isActive = function() return false end }
    modules["runtime.LocalActionBridge"] = { isQuickEquipPending = function() return false end }
    modules["runtime.GameAction"] = { sendAction = function(action, payload)
        actions[#actions + 1] = { action = action, payload = payload }; return true end }
    modules["ui.character.equip.EquipmentBag"] = { init = noop, draw = noop, isOpen = function() return false end,
        shouldBattleOverlay = function() return false end }
    modules["ui.character.equip.EquipmentDetail"] = { getSelection = function() return selection end,
        dismissHover = noop, isOpen = function() return false end, isCompactCorner = function() return false end }
    modules["ui.character.hero.AwakeningPanel"] = { initImages = noop, reset = noop,
        setClassIcons = noop, setOwnedDataGetter = noop }
    modules["ui.church.ChurchPage"] = { hasAdvanceForHero = function() return false end }
    modules["ui.character.hero.AwakeningArtwork"] = { close = noop }
    modules["ui.character.hero.HeroScenario"] = { onOpenHero = noop }
    modules["ui.character.panel.CharacterPanel"] = { getOwnedHero = function(id)
        return data.heroes and data.heroes.roster[id] end }
    modules["ui.backpack.BackpackPanel"] = { acquireForEquipment = noop, releaseForEquipment = noop,
        setEquipmentSlotFilter = noop }
    modules["ui.widget.ImageCache"] = { init = noop, getEquipIcon = function(id)
        icons[#icons + 1] = id; return -1 end, getQualityBg = function() return -1 end }
    modules["ui.widget.KeywordText"] = { new = function() return { clear = noop, drawPopup = noop,
        isOpen = function() return false end, setPopupTransform = noop } end }
    modules["ui.widget.EquipmentSetIcon"] = { drawBadge = noop,
        levelLayout = function(_, x, y) return { x = x + 70, y = y + 70, fontSize = 30, align = 0 } end,
        badgeLayout = function(x) return { x = x - 90, size = 30 } end }
    modules["ui.hud.popup.SettingsPanel"] = { isEquipmentPowerEnabled = function() return true end }
    modules["ui.character.detail.QuickEquipActivity"] = { draw = noop }
    local function contains(r, x, y) return r and x and y and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
    local stats = { LAYOUT = { panel = { x = 0, y = 890, w = 1080, h = 1340 },
            attrs = { x = 40, y = 1040, w = 450, h = 700 }, sets = { x = 40, y = 1830, w = 1000, h = 350 },
            radar = { x = 550, y = 1040, w = 500, h = 700 }, title = { x = 390, y = 894, w = 300, h = 68 } },
        contains = contains, rowAt = function() return nil end,
        createRadarTransition = function() return { reset = noop, sample = function() return {} end } end,
        sortComparisonRows = function(rows) return rows end, unionSets = function(rows) latest.sets = rows; return rows end,
        drawHeader = noop, drawRows = function(_, rows) latest.rows = rows; return 0, {} end,
        drawSets = function() return 0 end, drawRadar = function(_, current, preview) latest.current, latest.preview = current, preview end,
        drawEmptyBonuses = noop, drawTooltip = noop }
    stats.drawBackground = noop
    stats.LEGACY = { STAT_BOX_W = 437, STAT_BOX_H = 95, STAT_COL1_CX = 308.5, STAT_COL2_CX = 771.5,
        STAT_ROW1_CY = 1641, STAT_ROW_STEP = 111, STAT_LAYOUT = {}, HEX_CX = 800, HEX_CY = 1507,
        HEX_LABEL_R = 238, HEX_NAMES = { "力量", "敏捷", "体质", "魂火", "命数", "秘识" } }
    modules["ui.character.detail.CharacterEquipStats"] = stats
    local attrView = { ATTRIBUTE_LAYOUT = { firstY = 1050, y = 1020, h = 720 }, STYLE = {},
        ATTRIBUTE_STYLE = { boxW = 440, rowH = 50, boxCX = 265, rowStep = 60 },
        createStyle = function() return {} end, setSharedImages = noop, formatNumber = function(v) return tostring(math.floor(v + 0.5)) end,
        formatInterval = function(v) return string.format("%.2f", v) end, drawDivider = noop }
    -- 真实属性收集需要格式化函数；不替换属性/预览/评分公式。
    modules["ui.character.detail.CharacterAttributeView"] = attrView
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScissor", "nvgIntersectScissor", "nvgResetScissor", "nvgTranslate",
        "nvgScale", "nvgGlobalAlpha", "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor", "nvgFill", "nvgStrokeColor",
        "nvgStrokeWidth", "nvgStroke", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText", "nvgFillPaint", "nvgMoveTo", "nvgLineTo" }) do env[name] = noop end
    env.nvgRGBA = function() return {} end
    env.nvgImagePattern = function() return {} end
    env.nvgTextBounds = function(_, _, _, text) return #tostring(text) * 10 end
    env.nvgCreateImage = function() return -1 end
    env.require = function(name)
        if modules[name] then return modules[name] end
        assert(not name:match("^boot%.") and not name:match("^runtime%."), "undeclared dependency " .. name)
        local value = assert(load(source(name), "@detail-private/" .. name, "t", env))()
        modules[name] = assert(value, name)
        local methods = name == "systems.EquipmentPower" and { buildContext = "build", getContext = "context", evaluate = "evaluate", scoreInContext = "score", evaluateGain = "gain" }
            or name == "ui.character.detail.EquipmentPreview" and { build = "preview" }
            or name == "ui.character.detail.CharacterDetailAttrs" and { collectAttributes = "attrs" }
            or name == "systems.EquipmentSystem" and { hydrate = "hydrate" } or {}
        for method, counter in pairs(methods) do
            local original = value[method]
            value[method] = function(...) counts[counter] = counts[counter] + 1; return original(...) end
        end
        return value
    end
    local Detail = env.require("ui.character.detail.CharacterDetail")
    local Draw = env.require("ui.character.detail.CharacterDetailDraw")
    local EP, Eq, EC = env.require("systems.EquipmentPower"), env.require("systems.EquipmentSystem"), env.require("config.EquipmentConfig")
    data.heroes = { roster = { [1] = { level = 80, awakening = {}, extraTalent = {} },
        [2] = { level = 80, awakening = {}, extraTalent = {} }, [20] = { level = 80, awakening = {}, extraTalent = {} } },
        teams = { { slots = { 1, 2, 20 } }, { slots = {} }, { slots = {} } } }
    data.equipment = { inventory = {}, equipped = { [1] = {}, [2] = {}, [20] = {} } }
    data.artifacts, data.talents = { bag = {} }, { litNodes = {} }
    local wearable = Eq.getWearableTypeSet(1, "accessory")
    local template
    for _, tid in ipairs(EC.BY_SLOT.accessory) do
        if not wearable or wearable[EC.ITEMS[tid].type] then template = tid; break end
    end
    for i = 1, 500 do
        local item = Eq.generate(assert(template), 1 + i % 40, 1 + i % 6)
        item.seq = i; data.equipment.inventory[tostring(i)] = item
    end
    data.equipment.equipped[1].accessory = 1
    data.equipment.equipped[2].accessory = 2
    Detail.init({})
    Detail.setContext({ getOwnedData = function(id) return data.heroes.roster[id] end,
        getHeroRoster = function() return { { heroId = 1, owned = true }, { heroId = 2, owned = true }, { heroId = 20, owned = true } } end,
        calcHeroPower = function() error("equip Render calcHeroPower forbidden") end })
    local f = { detail = Detail, drawModule = Draw, panel = Detail._EquipPanel, env = env, data = data, counts = counts,
        actions = actions, latest = latest, icons = icons, EP = EP, Eq = Eq, EC = EC, metrics = metrics }
    function f.select(seq) selection = seq and { seq = seq, owner = "backpack", pinned = true } or nil end
    function f.notify(key)
        revisions[key] = (revisions[key] or 0) + 1
        EP.invalidate(); Detail.markPowerDirty()
    end
    function f.exp()
        data.heroes = copy(data.heroes)
        for _, own in pairs(data.heroes.roster) do own.exp = (own.exp or 0) + 1 end
        for _, team in ipairs(data.heroes.teams) do team.exp = (team.exp or 0) + 1 end
        f.notify("heroes")
    end
    function f.update()
        env.time.elapsedTime = env.time.elapsedTime + 1 / 60
        local started = os.clock()
        Detail.update(1 / 60)
        metrics.updateMaxMs = math.max(metrics.updateMaxMs, (os.clock() - started) * 1000)
        metrics.updates = metrics.updates + 1
    end
    function f.draw()
        local before = copy(counts)
        for i = #icons, 1, -1 do icons[i] = nil end
        local cardsBefore = cards
        Detail.draw({})
        metrics.drawColdBuild = metrics.drawColdBuild + counts.build - before.build
        check(cards > cardsBefore, "Render traverses actual card power branch")
        check(equal(before, counts), "Render zero build/score/evaluateGain/preview/attrs/hydrate/IO")
    end
    function f.finish(stream)
        for frame = 1, 30000 do
            if stream then f.exp() end
            f.update()
            if not Detail.getPreparedEquipment().pending then return frame end
        end
        error("detail queue starved")
    end
    function f.enableRealPopup()
        modules["ui.character.equip.EquipmentDetail"] = nil
        local function drawLeaf(ctx, equip, slot, diff)
            latest.popupPower = ctx.calcEquipPower(equip, ctx.detState.heroId, slot)
            latest.popupGain = diff
        end
        modules["ui.character.equip.EquipmentDetailDraw"] = { create = function(ctx)
            return { drawEquipPanel = function(_, equip, _, _, _, _, _, diff)
                    drawLeaf(ctx, equip, ctx.detState.slot, diff)
                end,
                drawCompactPanel = function(_, equip, _, _, scoreContext)
                    drawLeaf(ctx, equip, scoreContext and scoreContext.slot or ctx.detState.slot)
                end }
        end }
        local popup = env.require("ui.character.equip.EquipmentDetail")
        Detail._EquipDetail = popup
        popup.setPreparedReader(Detail.getPreparedEquipScore)
        -- 真open/getSelection，只有像素绘制叶子替身；保留评分getter的真实注入链。
        function f.select(seq, heroId, compact, owner, slot)
            if seq then popup.open(seq, slot, heroId or Detail.getHeroId(), compact ~= false, owner or "backpack", 100, 200)
            else popup.close() end
        end
        return popup
    end
    return f
end

local function runTests()
    local f = fixture()
    local d, data = f.detail, f.data
    d.open(1, "equip")
    f.select(3)
    local before = copy(data)
    f.draw()
    check(#f.icons >= 1, "cold pending retains equipped slot artwork")
    local frames = f.finish(true)
    f.draw()
    check(frames > 1 and not d.getPreparedEquipment().pending, "continuous roster/team exp finishes private worker")
    check(equal(before.equipment, data.equipment) and equal(before.artifacts, data.artifacts)
        and equal(before.talents, data.talents), "preparation never mutates live equipment/artifacts/talents")
    local heroBefore = copy(data.heroes)
    local context = f.EP.buildContext(1, data)
    local result = d.getPreparedEquipment()
    check(result.power == math.floor(context.currentPower + 0.5), "prepared power equals synchronous context oracle")
    for _, slot in ipairs(f.drawModule.DT_SLOTS) do
        check(result.upgrades[slot.slot] == d._hasUpgradeForSlot(1, slot.slot, context.equipmentData, context),
            "upgrade oracle " .. slot.slot)
        local seq = f.Eq.getHeroSlots(context.equipmentData, 1)[slot.slot]
        if seq then check(result.scores[slot.slot] == f.EP.scoreInContext(context,
            f.Eq.getFromInventory(context.equipmentData, seq), slot.slot, seq), "score oracle " .. slot.slot) end
    end
    check(equal(heroBefore, data.heroes), "scoring never normalizes live hero data")
    local Preview = f.env.require("ui.character.detail.EquipmentPreview")
    local options = copy(data); options.compactEquipment = false
    local oracle = Preview.build(1, 80, 3, nil, options)
    check(equal(result.panel.rows, oracle.rows) and equal(result.panel.currentSets, oracle.currentSets)
        and equal(result.panel.previewSets, oracle.previewSets), "compact preview equals full synchronous oracle")
    local builds = f.counts.build
    for _ = 1, 12 do f.exp(); f.update(); f.draw() end
    check(f.counts.build == builds, "exp plus invalidate/markDirty does not rebuild completed semantic version")
    for _, field in ipairs({ "level", "advBranch", "awakening", "extraTalent" }) do
        local previousPower = d.getPreparedEquipment().power
        -- 原地无通知，每个战斗字段都必须使旧评分/箭头/比较不可见。
        if field == "level" then data.heroes.roster[1].level = 81
        elseif field == "advBranch" then data.heroes.roster[1].advBranch = {}
        elseif field == "awakening" then data.heroes.roster[1].awakening[1] = true
        else data.heroes.roster[1].extraTalent.stacks = 250 end
        f.update()
        check(d.getPreparedEquipment().pending, "unnotified " .. field .. " hides old scores/arrows")
        f.draw(); check(#f.icons >= 1 and f.latest.preview == nil, "growth pending retains basic slots, not old comparison")
        f.finish(true)
        if field == "extraTalent" then
            local grownContext = f.EP.buildContext(1, data)
            check(d.getPreparedEquipment().power > previousPower
                and d.getPreparedEquipment().power == math.floor(grownContext.currentPower + 0.5),
                "real awakened stacks change prepared power and equal fresh synchronous oracle")
        end
    end
    -- Update完成后、Render前发生无通知成长，也必须即刻隐藏上下比较与箭头。
    f.update()
    data.heroes.roster[1].extraTalent.stacks = 500
    check(d.getPreparedEquipment().pending and f.panel.getPrepared(1, {}).pending,
        "postUpdate preRender growth rejects both committed consumers without pumping")
    f.draw()
    check(f.latest.preview == nil and #f.icons >= 1, "same-frame growth never paints stale comparison or empty slots")
    f.finish(true)
    f.panel.toggleAttributeMode()
    f.finish(true)
    local bonusOptions = copy(data)
    bonusOptions.includeEquipmentBonuses, bonusOptions.compactEquipment = true, false
    local bonusOracle = Preview.build(1, data.heroes.roster[1].level, 3, nil, bonusOptions)
    local bonusResult = d.getPreparedEquipment().panel
    check(equal(bonusResult.equipmentBonuses.rows, bonusOracle.equipmentBonuses.rows)
        and equal(bonusResult.equipmentBonuses.current.stats, bonusOracle.equipmentBonuses.current.stats)
        and equal(bonusResult.equipmentBonuses.preview, bonusOracle.equipmentBonuses.preview),
        "equipment-only mode compact rows/stats equal full synchronous oracle")
    f.draw()
    f.panel.toggleAttributeMode()
    f.finish(true)
    -- 持续真实成长不可能承诺完成；必须诚实pending并保持操作可用。
    for _ = 1, 8 do
        data.heroes.roster[1].level = data.heroes.roster[1].level + 1
        f.update(); f.draw()
        check(d.getPreparedEquipment().pending and #f.icons >= 1, "continuous real growth remains usable pending")
    end
    local Draw = f.drawModule
    d.handleInput(Draw.BTN_UNEQUIP_CX, Draw.BTN_UNEQUIP_CY)
    check(#f.actions == 1, "pending does not disable real unequip action")
    f.select(4); check(d.getPreparedEquipment().pending, "selection edge immediately rejects old result")
    f.update(); f.select(5); f.finish(true)
    check(d.getPreparedEquipment().panel.candidate.seq == 5, "newest selection commits, never superseded selection")
    d.open(2, "equip"); check(d.getPreparedEquipment().pending, "hero edge cancels old generation")
    f.finish(true); check(not d.getPreparedEquipment().pending, "new hero finishes")
    d.handleInput(Draw.BTN_TAB_ATTR_CX, Draw.BTN_TAB_ATTR_CY)
    check(d.getPreparedEquipment().pending, "leaving equip cancels committed generation")
    d.open(1, "equip"); f.update(); d.close(); f.update()
    check(d.getPreparedEquipment().pending, "close cancels pending job")
    d.open(1, "equip"); f.update(); d.forceClose(); f.update()
    check(d.getPreparedEquipment().pending, "forceClose cancels pending job")
    d.open(20, "equip"); f.select(2); f.finish(true)
    local melissa = d.getPreparedEquipment().panel
    options = copy(data); options.compactEquipment = false
    local melissaOracle = Preview.build(20, 80, 2, nil, options)
    check(equal(melissa.rows, melissaOracle.rows), "star gate and borrowed teammate candidate equal full-world oracle")
    -- 真实候选浮窗原先藏有getContext/evaluate冷路径，不能被isOpen=false边界掩盖。
    local popup = f.enableRealPopup()
    d.open(1, "equip")
    f.select(3, 1, true, "backpack", "accessory")
    f.update()
    local popupCounts = copy(f.counts)
    popup.draw({})
    check(equal(popupCounts, f.counts) and f.latest.popupPower == "—", "real compact popup pending renders no context/evaluation")
    f.finish(true)
    popupCounts = copy(f.counts)
    popup.draw({})
    check(equal(popupCounts, f.counts), "ready real compact popup remains render-only")
    f.draw()
    local preparedCandidate = d.getPreparedEquipment().candidate
    check(preparedCandidate and f.latest.popupPower == preparedCandidate.score, "real compact drawer consumes private candidate score")
    data.heroes.roster[1].level = data.heroes.roster[1].level + 1
    f.notify("heroes")
    popupCounts = copy(f.counts)
    popup.draw({})
    check(equal(popupCounts, f.counts) and f.latest.popupPower == "—", "growth-invalidated real popup cannot rebuild cold global context")
    f.finish(true)
    f.select(3, 1, false, "bag", "accessory")
    f.finish(true)
    popupCounts = copy(f.counts)
    popup.draw({})
    preparedCandidate = d.getPreparedEquipment().candidate
    check(equal(popupCounts, f.counts) and preparedCandidate
        and f.latest.popupPower == preparedCandidate.score and f.latest.popupGain == preparedCandidate.gain,
        "real noncompact popup consumes private score and gain")
    local weaponTypes = f.Eq.getWearableTypeSet(1, "weapon")
    local twohandTemplate
    for _, tid in ipairs(f.EC.BY_SLOT.weapon) do
        local tpl = f.EC.ITEMS[tid]
        if tpl.grip == "twohand" and (not weaponTypes or weaponTypes[tpl.type]) then twohandTemplate = tid; break end
    end
    local twohand = f.Eq.generate(assert(twohandTemplate), 1, 1)
    twohand.seq = 901
    data.equipment.inventory["901"] = twohand
    data.equipment.equipped[1].weapon, data.equipment.equipped[1].offhand = 901, nil
    f.notify("equipment")
    popup.close()
    f.finish(true)
    popup.openEquipped(901, "offhand", 1, 100, 200)
    f.finish(true)
    local handledMain, mainScore = d.getPreparedEquipScore(901, 1, "weapon", "character")
    local handledOff, offScore = d.getPreparedEquipScore(901, 1, "offhand", "character")
    check(handledMain and handledOff and type(mainScore) == "number" and offScore == mainScore,
        "twohand occupied offhand aliases prepared weapon score")
    popupCounts = copy(f.counts)
    popup.draw({})
    check(equal(popupCounts, f.counts) and f.latest.popupPower == mainScore,
        "real openEquipped offhand popup consumes occupied weapon score without recomputation")
    f.select(3, 2, true, "backpack", "accessory")
    f.finish(true)
    popupCounts = copy(f.counts); popup.draw({})
    check(equal(popupCounts, f.counts) and f.latest.popupPower == "—", "different-hero popup never borrows active hero score or cold context")
    f.select(3, 1, false, "character", "accessory")
    f.finish(true)
    f.EP.invalidate()
    d.close()
    popupCounts = copy(f.counts)
    d.draw({})
    check(equal(popupCounts, f.counts) and popup.isOpen() and f.latest.popupPower == "—",
        "detail close animation with live noncompact popup cannot synchronously rebuild")
    d.forceClose()
    f.select(3, 1, false, "smith", "accessory")
    popupCounts = copy(f.counts); popup.draw({})
    check(f.counts.context > popupCounts.context and type(f.latest.popupPower) == "number",
        "nonlinked smith popup preserves prior synchronous score behavior")
    popup.close()
    local numericOnly = copy(data)
    numericOnly.equipment.inventory[900] = copy(numericOnly.equipment.inventory["5"])
    numericOnly.equipment.inventory[900].seq = 900
    numericOnly.compactEquipment = false
    local numericOracle = Preview.build(1, numericOnly.heroes.roster[1].level, "900", nil, numericOnly)
    numericOnly.compactEquipment = true
    local numericCompact = Preview.build(1, numericOnly.heroes.roster[1].level, "900", nil, numericOnly)
    check(numericCompact.candidate and numericCompact.candidate.seq == 900
        and equal(numericCompact.rows, numericOracle.rows), "string candidate resolves numeric-only inventory key identically")
    local Snapshot = f.env.require("ui.character.detail.CharacterDetailSnapshot")
    -- 证明preview裁剪只点查需要项，不能偷偷pairs整个inventory。
    local inventory = data.equipment.inventory
    setmetatable(inventory, { __pairs = function() error("full inventory traversal forbidden") end })
    local compact = Snapshot.compactEquipment(data.equipment, 5)
    check(compact.inventory["1"] and compact.inventory["2"] and compact.inventory["5"], "compact preserves all worn plus candidate without inventory enumeration")
    local built = Preview.build(1, data.heroes.roster[1].level, 5, nil, data)
    check(built.current ~= nil, "preview's internal attribute copies only see compact inventory")
    setmetatable(inventory, nil)
    check(f.counts.io == 0, "no player File/FS access")
    print(string.format("%s METRICS coldFrames=%d build=%d score=%d gain=%d preview=%d drawColdBuild=%d updateMaxMs=%.3f updates=%d", TAG,
        frames, f.counts.build, f.counts.score, f.counts.gain, f.counts.preview,
        f.metrics.drawColdBuild, f.metrics.updateMaxMs, f.metrics.updates))
end

function Start()
    local ok, err = pcall(runTests)
    if not ok then check(false, "exception: " .. tostring(err)) end
    print(string.format("%s SUMMARY assertions=%d failures=%d %s", TAG, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
