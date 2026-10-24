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
    local work = { phase = false, version = 0, matches = 0, read = 0, panelRead = 0, dependencies = 0, signature = 0, sort = 0, concat = 0, bytes = 0 }
    local env = setmetatable({}, { __index = _G })
    local language = "zh"
    local dpr = 1
    env.graphics = { GetDPR = function() return dpr end, GetWidth = function() return 1080 * dpr end,
        GetHeight = function() return 2400 * dpr end }
    env.table = setmetatable({
        sort = function(...)
            if work.phase then work.sort = work.sort + 1 end
            return table.sort(...)
        end,
        concat = function(...)
            local result = table.concat(...)
            if work.phase then work.concat, work.bytes = work.concat + 1, work.bytes + #result end
            return result
        end,
    }, { __index = table })
    env._G, env.time, env.H_SEAM_BACK = env, { elapsedTime = 100 }, true
    env.File = function() counts.io = counts.io + 1; error("player IO forbidden") end
    env.fileSystem = setmetatable({}, { __index = function() return env.File end })
    local store = { Get = function(k) return data[k] end, GetRevision = function(k) return revisions[k] or 0 end,
        Subscribe = noop, Unsubscribe = noop }
    modules["core.PlayerStore"] = store
    modules["runtime.ClientDispatcher"] = { get = store.Get }
    modules["core.I18n"] = { get = function() return language end, t = function(s) return s end,
        lookup = function(s) return s end, format = string.format,
        displayBounds = function(_, _, _, text) return #tostring(text) * 10 end,
        displayText = noop }
    modules["core.I18nEquipmentText"] = { lookup = function(s) return s end }
    modules["core.GameState"] = {}
    modules["core.DrawUtil"] = { drawTextStroke = noop, drawImageCentered = noop, drawCardImage = function() cards = cards + 1 end,
        seamSlideX = function() return 0 end }
    modules["core.DarkIcon"] = { drawNine = noop, drawQualityBg = noop, drawIconDark = noop, draw = noop,
        QUALITY_TRIM = { { 240, 240, 240 }, { 0, 255, 0 }, { 0, 0, 255 }, { 255, 0, 255 }, { 255, 255, 0 }, { 255, 0, 0 } } }
    modules["core.BattleLayout"] = { CARD_W = 198, CARD_H = 198 * 955 / 538 }
    modules["config.HeroAssetUtil"] = { ensureCard = function() return 1 end }
    modules["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop }
    modules["systems.TutorialManager"] = { getPreferredCharacterTab = function() return "equip" end,
        isActive = function() return false end, isBuildingUnlocked = function() return false end }
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
        isOpen = function() return false end, setPopupTransform = noop, beginFrame = noop, draw = noop,
        drawAttribute = function() return 0 end } end }
    modules["ui.widget.EquipmentSetIcon"] = { drawBadge = noop, draw = function() return false end,
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
        "nvgStrokeWidth", "nvgStroke", "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgText", "nvgFillPaint", "nvgMoveTo", "nvgLineTo",
        "nvgClosePath", "nvgTextBox" }) do env[name] = noop end
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
        local probes = name == "ui.character.detail.CharacterDetailPreparation" and { version = "version" }
            or name == "ui.character.detail.CharacterDetailSnapshot" and { dependencies = "dependencies", signature = "signature", matchesDependencies = "matches" }
            or name == "ui.character.detail.CharacterDetail" and { getPreparedEquipment = "read" }
            or name == "ui.character.detail.CharacterDetailEquip" and { getPrepared = "panelRead" } or {}
        for method, counter in pairs(probes) do
            local original = value[method]
            value[method] = function(...)
                if work.phase then work[counter] = work[counter] + 1 end
                return original(...)
            end
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
    function f.setLanguage(value) language = value end
    function f.setDPR(value) dpr = value end
    function f.probe(fn)
        work.matches, work.read, work.panelRead, work.version = 0, 0, 0, 0
        work.phase = "probe"
        local ok, err = pcall(fn)
        work.phase = false
        if not ok then error(err) end
        return copy(work)
    end
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
    function f.measure(label, frames, popup)
        local samples = {}
        for _, phase in ipairs({ "render", "update", "pair" }) do
            for _, key in ipairs({ "version", "matches", "read", "panelRead", "dependencies", "signature", "sort", "concat", "bytes" }) do work[key] = 0 end
            collectgarbage("collect")
            local heap = collectgarbage("count")
            local started = os.clock()
            work.phase = phase
            for _ = 1, frames do
                if phase ~= "render" then Detail.update(1 / 60) end
                if phase ~= "update" then
                    Detail.draw({})
                    if popup then popup.draw({}) end
                end
            end
            work.phase = false
            local elapsed = (os.clock() - started) * 1000
            samples[phase] = copy(work)
            print(string.format("%s HOTPATH %s phase=%s frames=%d meanMs=%.4f heapDeltaKiB=%.1f version=%d matches=%d read=%d panelRead=%d dependencies=%d signature=%d sort=%d concat=%d concatBytes=%d", TAG,
                label, phase, frames, elapsed / frames, collectgarbage("count") - heap, work.version,
                work.matches, work.read, work.panelRead, work.dependencies, work.signature, work.sort, work.concat, work.bytes))
        end
        return samples
    end
    function f.enableRealPopup()
        modules["ui.character.equip.EquipmentDetail"] = nil
        local function drawLeaf(ctx, equip, slot, diff, reader)
            if f.popupHook then f.popupHook() end
            latest.popupPower = ctx.calcEquipPower(equip, ctx.detState.heroId, slot, reader)
            latest.popupGain = diff
        end
        modules["ui.character.equip.EquipmentDetailDraw"] = { create = function(ctx)
            return { drawEquipPanel = function(_, equip, _, _, _, _, _, diff, _, _, _, _, _, reader)
                    drawLeaf(ctx, equip, ctx.detState.slot, diff, reader)
                end,
                drawCompactPanel = function(_, equip, _, _, scoreContext)
                    drawLeaf(ctx, equip, scoreContext and scoreContext.slot or ctx.detState.slot,
                        nil, scoreContext and scoreContext.reader)
                end }
        end }
        local popup = env.require("ui.character.equip.EquipmentDetail")
        Detail._EquipDetail = popup
        popup.setPreparedReader(Detail.getPreparedEquipScore, Detail.createPreparedEquipScoreReader)
        function f.realPopupPixels()
            -- 再走真实EquipmentDetailDraw；只替换NVG/字体/关键词叶子，不替换战力getter。
            modules["ui.character.equip.EquipmentDetailDraw"] = nil
            modules["ui.character.equip.EquipmentDetail"] = nil
            modules["core.DrawUtil"].drawTextStroke = function(_, _, y, text, _, _, r, g, b)
                if r == 0xf7 and g == 0xfe and b == 0x77 and (y == 34 or y == 625) then
                    latest.popupPower = tostring(text)
                    latest.popupPowerDraws = (latest.popupPowerDraws or 0) + 1
                end
            end
            popup = env.require("ui.character.equip.EquipmentDetail")
            Detail._EquipDetail = popup
            popup.setPreparedReader(Detail.getPreparedEquipScore, Detail.createPreparedEquipScoreReader)
            return popup
        end
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
    f.update()
    check(not f.panel.getPrepared(1, {}).pending and d.getPreparedEquipment().pending,
        "first Update publishes complete attributes before 500-item score worker finishes")
    f.draw()
    check(#f.latest.rows > 0 and (f.latest.current.str or 0) > 0 and f.latest.preview ~= nil,
        "first Update renders nonzero radar, rows and current candidate while scores pending")
    local frames = f.finish(true)
    f.draw()
    local readyWork = f.measure("ready-500", 120)
    for _, phase in ipairs({ "render", "update", "pair" }) do
        local sample = readyWork[phase]
        local expectedMatches = phase == "pair" and 240 or 120
        check(sample.matches == expectedMatches and sample.panelRead == 0,
            "stable " .. phase .. " validates once per Update/draw, not again for attributes")
        check(sample.dependencies == 0 and sample.signature == 0 and sample.sort == 0 and sample.concat == 0,
            "stable " .. phase .. " performs no full dependency serialization, sorting or concatenation")
    end
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
    local SnapshotProbe = f.env.require("ui.character.detail.CharacterDetailSnapshot")
    local PreparationProbe = f.env.require("ui.character.detail.CharacterDetailPreparation")
    local worn = data.equipment.inventory["1"]
    local candidateItem = data.equipment.inventory["3"]
    for index, target in ipairs({ worn, candidateItem, data.heroes.roster[1].extraTalent,
        data.artifacts, data.talents.litNodes }) do
        local baselinePanel = f.panel.getPrepared(1, {})
        local original = target._detailPatchProbe
        target._detailPatchProbe = { nested = { value = index } }
        local countsBefore = copy(f.counts)
        for _ = 1, 3 do
            check(d.getPreparedEquipment().pending and f.panel.getPrepared(1, {}).pending,
                "same-frame nested in-place patch rejects both consumers repeatedly " .. index)
        end
        f.draw()
        check(equal(countsBefore, f.counts) and f.latest.preview == nil,
            "invalid render does not rebuild attribute/scoring snapshot " .. index)
        target._detailPatchProbe = original
        check(not d.getPreparedEquipment().pending and f.panel.getPrepared(1, {}) == baselinePanel,
            "exact-content ABA restores original compatible snapshot " .. index)
    end
    -- 显式guard与不传guard的默认version分别校验，复用request也不能留下旧key。
    local guard = {}
    local request = PreparationProbe.version(f.panel.capture(1), guard, true)
    local signatureBefore = PreparationProbe.version(f.panel.capture(1)).panelKey
    candidateItem._detailPatchProbe = { value = 1 }
    PreparationProbe.version(request, guard, false)
    check(request.key == nil and request.panelKey == nil,
        "guarded read clears old keys on reused request after live mutation")
    local signatureAfter = PreparationProbe.version(f.panel.capture(1)).panelKey
    check(signatureAfter ~= signatureBefore, "default version remains stateless full-content compatible")
    candidateItem._detailPatchProbe = nil
    local candidateLevel = candidateItem.level
    candidateItem.level = candidateLevel + 1
    check(d.getPreparedEquipment().pending and f.panel.getPrepared(1, {}).pending,
        "existing candidate scalar mutation is detected against independent frozen item")
    candidateItem.level = candidateLevel
    local wornItem = data.equipment.inventory["1"]
    data.equipment.inventory["1"] = nil
    check(d.getPreparedEquipment().pending and f.panel.getPrepared(1, {}).pending,
        "removed worn item immediately rejects frozen consumers")
    data.equipment.inventory["1"] = wornItem
    local absentFrozen = SnapshotProbe.freezeDependencies(data, 99999, 1)
    data.equipment.inventory["99999"] = copy(candidateItem)
    check(not SnapshotProbe.matchesDependencies(absentFrozen, data.heroes, data.equipment, data.artifacts, data.talents, 1),
        "newly materialized previously absent candidate rejects frozen baseline")
    data.equipment.inventory["99999"] = nil
    local frozen = SnapshotProbe.freezeDependencies(data, 3, 1)
    local inventoryGuard = data.equipment.inventory
    setmetatable(inventoryGuard, { __pairs = function() error("Render inventory enumeration forbidden") end })
    check(SnapshotProbe.matchesDependencies(frozen, data.heroes, data.equipment, data.artifacts, data.talents, 1),
        "read-only validator only point-looks-up inventory")
    setmetatable(inventoryGuard, nil)
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
        f.draw(); check(#f.icons >= 1 and f.latest.preview ~= nil and not f.panel.getPrepared(1, {}).pending,
            "growth Update refreshes current attributes and candidate without waiting for score worker")
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
    -- 持续真实成长允许评分pending，但下部属性每次Update必须是完整当前值，不能永久空白。
    for _ = 1, 8 do
        data.heroes.roster[1].level = data.heroes.roster[1].level + 1
        f.update(); f.draw()
        local currentOracle = Preview.build(1, data.heroes.roster[1].level, 3, nil, data)
        local currentPanel = f.panel.getPrepared(1, {})
        check(d.getPreparedEquipment().pending and not d.getPreparedEquipment().scoresPending
            and type(d.getPreparedEquipment().candidate.score) == "number" and #f.icons >= 1,
            "continuous real growth publishes current equipment scores while arrows remain pending")
        check(not currentPanel.pending and #f.latest.rows > 0 and equal(currentPanel.rows, currentOracle.rows)
            and equal(f.latest.current, currentOracle.current.stats) and f.latest.preview ~= nil,
            "continuous real growth publishes latest complete rows/radar/comparison in same Update")
    end
    -- 三队12人：别队持续真实成长不取消本队比较或整库评分。
    local HC = f.env.require("config.HeroConfig")
    local ids = { 1, 2, 20 }
    for id = 3, 100 do
        if id ~= 20 and HC.get(id) and #ids < 12 then
            ids[#ids + 1] = id
            data.heroes.roster[id] = { level = 80, awakening = {}, extraTalent = {} }
            data.equipment.equipped[id] = { accessory = id + 10 }
        end
    end
    check(#ids == 12, "three-team stress fixture has twelve real heroes")
    for team = 1, 3 do
        data.heroes.teams[team].slots = {}
        for slot = 1, 4 do data.heroes.teams[team].slots[slot] = ids[(team - 1) * 4 + slot] end
    end
    f.update()
    local stablePanel = f.panel.getPrepared(1, {})
    local panelBuilds = f.counts.preview
    local otherId = ids[5]
    for frame = 1, 30000 do
        data.heroes.roster[otherId].level = 80 + frame
        f.notify("heroes")
        f.update()
        if not d.getPreparedEquipment().pending then break end
    end
    check(not d.getPreparedEquipment().pending and f.counts.preview == panelBuilds
        and f.panel.getPrepared(1, {}) == stablePanel,
        "continuous other-team level growth preserves ready panel and lets full score finish")
    -- 目标队友成长仍属真实依赖，下部即刻新建，评分拒绝旧版本。
    data.heroes.roster[2].level = 81
    check(f.panel.getPrepared(1, {}).pending and d.getPreparedEquipment().pending,
        "same-team growth invalidates panel and full score before Update")
    f.update()
    check(not f.panel.getPrepared(1, {}).pending and d.getPreparedEquipment().pending,
        "same-team growth refreshes panel without waiting for full score")
    panelBuilds = f.counts.preview
    stablePanel = f.panel.getPrepared(1, {})
    f.notify("equipment")
    check(f.panel.getPrepared(1, {}) == stablePanel and d.getPreparedEquipment().pending,
        "inventory-only revision does not clear unchanged current attributes")
    f.update()
    check(f.counts.preview == panelBuilds and f.panel.getPrepared(1, {}) == stablePanel,
        "score restart does not rebuild or clear panel")
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
    check(equal(popupCounts, f.counts) and type(f.latest.popupPower) == "number"
        and d.getPreparedEquipment().pending and not d.getPreparedEquipment().scoresPending,
        "first Update real compact popup displays current score without waiting for full inventory")
    f.finish(true)
    popupCounts = copy(f.counts)
    popup.draw({})
    check(equal(popupCounts, f.counts), "ready real compact popup remains render-only")
    f.draw()
    local preparedCandidate = d.getPreparedEquipment().candidate
    check(preparedCandidate and f.latest.popupPower == preparedCandidate.score, "real compact drawer consumes private candidate score")
    local readWork = f.probe(function()
        d.getPreparedEquipment(); f.panel.getPrepared(1, {})
        d.getPreparedEquipScore(3, 1, "accessory", "backpack")
        d.getPreparedEquipScore(3, 1, "accessory", "backpack")
    end)
    check(readWork.matches == 4, "every external bundle/panel/score read independently validates, even in same frame")
    f.draw()
    local patch = data.equipment.inventory["3"]
    patch._drawBoundaryProbe = { nested = 1 }
    popup.draw({})
    local _, staleScore = d.getPreparedEquipScore(3, 1, "accessory", "backpack")
    check(f.latest.popupPower == "—" and staleScore == nil and f.panel.getPrepared(1, {}).pending,
        "patch between detail draw and popup/external reads rejects previous draw bundle")
    patch._drawBoundaryProbe = nil
    popup.draw({})
    check(f.latest.popupPower == preparedCandidate.score, "same-frame ABA redraw validates again and restores compatible score")
    for _, compact in ipairs({ true, false }) do
        f.select(3, 1, compact, "backpack", "accessory"); f.update()
        local selectedScore = d.getPreparedEquipment().candidate.score
        local popupWork = f.probe(function() popup.draw({}) end)
        check(popupWork.matches == 1 and f.latest.popupPower == selectedScore,
            "popup gain plus visible card(s) share exactly one validation compact=" .. tostring(compact))
    end
    f.select(3, 1, true, "backpack", "accessory"); f.update()
    f.popupHook = function() error("expected popup draw fault") end
    local drawOK = pcall(popup.draw, {})
    f.popupHook = nil
    patch._drawBoundaryProbe = true
    local afterFault = f.probe(function() popup.draw({}) end)
    check(not drawOK and afterFault.matches == 1 and f.latest.popupPower == "—",
        "draw exception leaves no module-local validated reader alive for next draw")
    patch._drawBoundaryProbe = nil
    local nestedOnce = false
    f.popupHook = function()
        if not nestedOnce then nestedOnce = true; popup.draw({}) end
    end
    local nestedWork = f.probe(function() popup.draw({}) end)
    f.popupHook = nil
    check(nestedOnce and nestedWork.matches == 2 and type(f.latest.popupPower) == "number",
        "nested draw owns independent local reader without replacing outer state")
    local nestedCandidatePower = false
    nestedOnce = false
    f.popupHook = function()
        if not nestedOnce then
            nestedOnce = true
            f.select(4, 1, true, "backpack", "accessory")
            popup.draw({})
            nestedCandidatePower = f.latest.popupPower
            f.select(3, 1, true, "backpack", "accessory")
        end
    end
    nestedWork = f.probe(function() popup.draw({}) end)
    f.popupHook = nil
    check(nestedWork.matches == 1 and nestedCandidatePower == "—" and type(f.latest.popupPower) == "number",
        "nested different-candidate draw cannot borrow outer reader or replace original candidate bundle")
    local wrongHeroReader = d.createPreparedEquipScoreReader(2, "backpack")
    local handledWrong, wrongHeroScore = wrongHeroReader(3, 2, "accessory", "backpack")
    local ownReader = d.createPreparedEquipScoreReader(1, "backpack")
    local _, ownScore = ownReader(3, 1, "accessory", "backpack")
    local _, crossHeroScore = ownReader(3, 2, "accessory", "backpack")
    local _, crossOwnerScore = ownReader(3, 1, "accessory", "character")
    local _, crossSlotScore = ownReader(3, 1, "weapon", "backpack")
    check(handledWrong and wrongHeroScore == nil and type(ownScore) == "number"
        and crossHeroScore == nil and crossOwnerScore == nil and crossSlotScore == nil,
        "local factory reader never lends scores to another hero/owner/comparison slot")
    f.setLanguage("en")
    popup.draw({})
    check(f.latest.popupPower == "—" and f.panel.getPrepared(1, {}).pending,
        "language edge immediately rejects previous localized bundle")
    f.update()
    local languageScore = d.getPreparedEquipment().candidate.score
    f.setDPR(2)
    popup.draw({})
    check(f.latest.popupPower == languageScore, "DPR changes do not retain pixel/text cache or invalidate semantic scores")
    f.setDPR(1); f.setLanguage("zh"); f.update()
    popup.setComparisonSlot("weapon")
    -- action slot仍为accessory，但选择快照的比较槽变化也必须拒绝旧视图。
    popup.draw({})
    check(f.latest.popupPower == "—", "comparison-slot edge refuses old view before Update")
    popup.setComparisonSlot(nil)
    f.select(3, 1, true, "character", "accessory")
    popup.draw({})
    check(f.latest.popupPower == "—", "owner edge refuses old selection before Update")
    f.select(3, 1, true, "backpack", "accessory"); f.update()
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
    -- 真实EquipmentDetail -> EquipmentDetailDraw -> 右上战力字：不把getter-only当作显示验收。
    popup = f.realPopupPixels()
    d.open(20, "equip")
    local crystal = f.Eq.generate("W36", 100, 3)
    crystal.seq = nil -- 精简库存：序号只在map键，不允许Render扫全库找seq。
    data.equipment.inventory["902"] = crystal
    data.heroes.roster[20].level = 80
    f.notify("equipment")
    f.select(902, 20, true, "backpack")
    popup.setComparisonSlot("weapon")
    f.update()
    local crystalContext = f.EP.buildContext(20, data)
    local crystalItem = f.Eq.getFromInventory(crystalContext.equipmentData, 902)
    local crystalEvaluation = f.EP.evaluate(crystalContext, 902, "weapon")
    local crystalScore = f.EP.scoreInContext(crystalContext, crystalItem, "weapon", 902)
    check(crystal.name == "水晶魔杖" and not crystalEvaluation.valid and crystalScore > 0,
        "Lv100 crystal wand fixture is a real level-locked candidate with usable stat value")
    popupCounts = copy(f.counts); popup.draw({})
    local crystalPrepared = d.getPreparedEquipment()
    check(equal(popupCounts, f.counts) and f.latest.popupPower == tostring(crystalScore)
        and crystalPrepared.pending and not crystalPrepared.scoresPending
        and crystalPrepared.candidate.gain == nil and next(crystalPrepared.upgrades) == nil,
        "real compact pixels show Lv100 invalid wand score immediately, never legal gain or upgrade arrow")
    -- 每一帧本人/同队成长都重新与全库同步oracle核对；不能用旧分让画面看似不空。
    for frame = 1, 12 do
        local previousScore = crystalPrepared.candidate.score
        data.heroes.roster[20].level = 100 + frame
        data.heroes.roster[1].extraTalent.stacks = 500 + frame * 20
        data.heroes.roster[2].level = 90 + frame
        f.notify("heroes")
        popupCounts = copy(f.counts); popup.draw({})
        check(equal(popupCounts, f.counts) and f.latest.popupPower == "—",
            "preUpdate real growth refuses prior pixel score " .. frame)
        f.update()
        local currentContext = f.EP.buildContext(20, data)
        local currentItem = f.Eq.getFromInventory(currentContext.equipmentData, 902)
        local expected = f.EP.scoreInContext(currentContext, currentItem, "weapon", 902)
        local expectedEvaluation = f.EP.evaluate(currentContext, 902, "weapon")
        crystalPrepared = d.getPreparedEquipment()
        popupCounts = copy(f.counts); popup.draw({})
        check(equal(popupCounts, f.counts) and crystalPrepared.pending and not crystalPrepared.scoresPending
            and crystalPrepared.candidate.score == expected and crystalPrepared.power == math.floor(currentContext.currentPower + 0.5)
            and crystalPrepared.candidate.gain == expectedEvaluation.gain and f.latest.popupPower == tostring(expected),
            "continuous own/same-team growth shows latest score and gain in real compact drawer " .. frame)
        check(type(previousScore) == "number", "prior generation existed before invalidation " .. frame)
    end
    local compactBuilds = f.counts.build
    f.exp(); f.update(); popup.draw({})
    check(f.counts.build == compactBuilds and f.latest.popupPower == tostring(crystalPrepared.candidate.score),
        "pure-exp notification preserves ready current score without rebuild")
    -- 同帧洗练、神器、天赋及队位真实变化也拒旧；下一Update只点查小世界。
    for index, mutate in ipairs({
        function() crystal.baseStats[1][2] = crystal.baseStats[1][2] + 10 end,
        function() data.talents.litNodes._pixelProbe = true end,
        function() data.artifacts._pixelProbe = { level = 1 } end,
        function() local slots = data.heroes.teams[1].slots; slots[1], slots[3] = slots[3], slots[1] end,
    }) do
        mutate()
        popupCounts = copy(f.counts); popup.draw({})
        check(equal(popupCounts, f.counts) and f.latest.popupPower == "—",
            "same-frame semantic pixel invalidation without cold render " .. index)
        f.update()
        check(not d.getPreparedEquipment().scoresPending, "next Update restores compact score " .. index)
    end
    -- 空白装备的正式贡献就是0：nil占位与数值0不能混淆。已穿项也无seq。
    local zeroItem = { templateId = crystal.templateId, name = "zero-score-wand", type = crystal.type,
        slot = "weapon", grip = crystal.grip, quality = 1, level = 1, baseStats = {}, affixes = {} }
    data.equipment.inventory["903"] = zeroItem
    data.equipment.equipped[20].weapon = 903
    f.notify("equipment")
    popup.openEquipped(903, "weapon", 20, 100, 200)
    f.update()
    popupCounts = copy(f.counts); popup.draw({})
    check(equal(popupCounts, f.counts) and f.latest.popupPower == "0"
        and d.getPreparedEquipment().scores.weapon == 0,
        "real current-equipment compact drawer prints score 0, not pending dash")
    -- 真实比较卡当前装备无seq；读取六槽身份，不借候选或把旧分挂在新装备上。
    f.select(902, 20, true, "backpack")
    popup.setComparisonSlot("weapon")
    f.update()
    local inventoryNoPairs = data.equipment.inventory
    setmetatable(inventoryNoPairs, { __pairs = function() error("popup Render inventory enumeration forbidden") end })
    popupCounts = copy(f.counts); popup.draw({})
    check(equal(popupCounts, f.counts) and f.latest.popupPower == tostring(d.getPreparedEquipment().candidate.score),
        "real two-card compact render resolves no-seq worn and candidate without inventory enumeration")
    setmetatable(inventoryNoPairs, nil)
    f.select(902, 20, false, "bag", "weapon")
    f.update()
    popupCounts = copy(f.counts); popup.draw({})
    check(equal(popupCounts, f.counts) and f.latest.popupPower == tostring(d.getPreparedEquipment().candidate.score),
        "real noncompact drawer prints independently committed score while whole-library arrows pending")
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
    -- 星门+三队全六槽+候选+装备来源模式：量测原子小世界，不将软预算冒充硬上限。
    for _, id in ipairs(ids) do
        for index, slot in ipairs(f.EC.SLOTS) do
            local wearableTypes = f.Eq.getWearableTypeSet(id, slot)
            local tid
            for _, candidateId in ipairs(f.EC.BY_SLOT[slot]) do
                local template = f.EC.ITEMS[candidateId]
                if template.grip ~= "twohand" and (not wearableTypes or wearableTypes[template.type]) then
                    tid = candidateId
                    break
                end
            end
            local item = f.Eq.generate(assert(tid, "wearable stress template " .. slot), 20, 3)
            local seq = 2000 + id * 10 + index
            item.seq = seq
            data.equipment.inventory[tostring(seq)] = item
            data.equipment.equipped[id][slot] = seq
        end
    end
    f.notify("equipment")
    d.open(20, "equip")
    f.select(3, 20, true, "backpack", "accessory")
    f.panel.toggleAttributeMode()
    local heavyBefore = copy(data)
    local started = os.clock()
    f.update()
    local heavyMs = (os.clock() - started) * 1000
    local heavyPanel = f.panel.getPrepared(20, {})
    local heavyOptions = copy(data)
    heavyOptions.includeEquipmentBonuses, heavyOptions.compactEquipment = true, false
    local heavyOracle = Preview.build(20, data.heroes.roster[20].level, 3, nil, heavyOptions)
    check(not heavyPanel.pending and equal(heavyPanel.rows, heavyOracle.rows)
        and equal(heavyPanel.equipmentBonuses.rows, heavyOracle.equipmentBonuses.rows)
        and equal(heavyPanel.equipmentBonuses.current.stats, heavyOracle.equipmentBonuses.current.stats),
        "full worn three-team star gate equipment mode first Update equals full inventory oracle")
    check(equal(heavyBefore, data), "atomic panel stress never mutates live sources")
    f.draw()
    f.finish(false)
    local heavyWork = f.measure("ready-three-team-72", 120)
    local powerDrawsBefore = f.latest.popupPowerDraws
    local popupWork = f.measure("ready-three-team-72-two-card", 120, popup)
    check(f.latest.popupPowerDraws - powerDrawsBefore == 480,
        "hotpath fixture renders two real compact cards per Render/pair draw")
    for _, phase in ipairs({ "render", "update", "pair" }) do
        check(heavyWork[phase].matches == (phase == "pair" and 240 or 120),
            "72 worn items validate once for full character draw " .. phase)
        check(popupWork[phase].matches == (phase == "render" and 240 or phase == "update" and 120 or 360),
            "two-card popup validates independently once, no per-card traversal " .. phase)
    end
    check(popupWork.render.dependencies == 0 and popupWork.render.signature == 0,
        "two-card popup performs no dependency serialization")
    check(heavyWork.render.dependencies == 0 and heavyWork.render.signature == 0
        and heavyWork.render.sort == 0 and heavyWork.render.concat == 0
        and heavyWork.pair.sort == 0 and heavyWork.pair.concat == 0,
        "72 worn items remove serialization work from whole Update+Render, not just timed draw")
    f.panel.toggleAttributeMode()
    -- 新bundle合并读取不能把评分异常变成属性空白；只故障评分入口，不改属性oracle。
    local realBuildContext = f.EP.buildContext
    local attrsBeforeScoreFault = f.counts.preview
    f.EP.buildContext = function() error("expected visible score fault") end
    f.update()
    f.EP.buildContext = realBuildContext
    local scoreFaultBundle = d.getPreparedEquipment()
    local scoreFaultPanel = f.panel.getPrepared(20, {})
    check(scoreFaultBundle.scoresPending and not scoreFaultPanel.pending
        and scoreFaultBundle.panel == scoreFaultPanel and f.counts.preview == attrsBeforeScoreFault + 1,
        "score preparation fault retains independently committed validated attribute bundle")
    f.draw()
    check(#f.latest.rows > 0 and f.latest.preview ~= nil,
        "whole detail draw displays current rows/radar/preview despite visible score fault")
    local faultPatch = data.equipment.inventory["3"]
    faultPatch._scoreFaultProbe = true
    check(d.getPreparedEquipment().panel == nil and f.panel.getPrepared(20, {}).pending,
        "same-frame patch refuses attribute-only fallback bundle after scoring fault")
    faultPatch._scoreFaultProbe = nil
    f.update()
    check(not d.getPreparedEquipment().scoresPending, "next Update retries score without clearing healthy attribute panel")
    -- 属性准备失败不阻断宿主，不提交失败版本；重试和cancel后可恢复。
    local Preparation = f.env.require("ui.character.detail.CharacterDetailPreparation")
    local shouldFail, commits, clears = true, 0, 0
    local probe = Preparation.bind({ capture = function() return { heroId = 1, viewKey = "fault-probe" } end,
        prepare = function()
            if shouldFail then error("expected panel fault") end
            return { rows = {}, current = { stats = {} } }
        end,
        commit = function() commits = commits + 1 end, clear = function() clears = clears + 1 end,
        slots = {}, hasUpgrade = function() return false end })
    local ok = pcall(probe.update)
    check(ok and commits == 0 and probe.read("fault-probe").pending,
        "panel exception is isolated without publishing a failed generation")
    shouldFail = false
    probe.update()
    check(commits == 1, "valid retry commits panel after preparation failure")
    probe.cancel()
    check(clears == 1 and probe.read("fault-probe").pending, "cancel clears independent panel and scoring generation")
    local reentrant = { cancel = function() end }
    local staleCommits = 0
    reentrant = Preparation.bind({ capture = function() return { heroId = 1, viewKey = "cancel-probe" } end,
        prepare = function()
            reentrant.cancel()
            return { rows = {}, current = { stats = {} } }
        end,
        commit = function() staleCommits = staleCommits + 1 end, clear = function() end,
        slots = {}, hasUpgrade = function() return false end })
    reentrant.update()
    check(staleCommits == 0 and reentrant.read("cancel-probe").pending,
        "cancel during preparation prevents stale same-key panel commit")
    check(f.counts.io == 0, "no player File/FS access")
    local inventoryCount = 0
    for _ in pairs(data.equipment.inventory) do inventoryCount = inventoryCount + 1 end
    print(string.format("%s PANEL_STRESS hero=20 teams=3 slots=72 inventory=%d firstUpdateMs=%.3f", TAG,
        inventoryCount, heavyMs))
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
