-- 即时伤害数字专项：隔离执行完整生产模块；不加载玩家档，不改全局RNG。
-- 战斗外围有限spy；真实Fx/Combo/BattleCombat/Icon/NumberUtil完整load，-review单独显示新效果。
local TAG = "[damage_number_merge_test]"
local assertions, failures = 0, 0
local function check(value, label)
    assertions = assertions + 1
    if not value then failures = failures + 1 end
    print(TAG .. (value and " PASS " or " FAIL ") .. label)
end
local function noop() end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.000001 end

---@type any
local reviewVg = nil
local reviewPhase = "initial"
local reviewTexts = {}
---@class DamageMergeReviewLane
---@field bcs {floatingTexts: table[], ftPool: table[], combatNumberIndex: table}
---@field age number
---@field allies table[]
---@field enemies table[]
---@field label string?
---@type DamageMergeReviewLane[]
local reviewLanes = {}
local reviewFont = ""
---@type table
local reviewLayout = {}
---@type table
local reviewDraw = {}

local function isStaggerReview()
    return reviewPhase == "stagger" or reviewPhase == "stagger-late" or reviewPhase == "stagger-fade"
end

-- 固定时间快照，不订阅Update，不启动main/战斗/保存。卡片只画可核验的几何占位。
local function prepareStaggerReview(Fx, AD)
    local ages = reviewPhase == "stagger-late" and { 0.40, 0.47, 0.54 }
        or reviewPhase == "stagger-fade" and { 0.62, 0.65, 0.68 } or { 0.21, 0.27, 0.34 }
    reviewLanes = {}
    for row, age in ipairs(ages) do
        local bcs = { floatingTexts = {}, ftPool = {}, combatNumberIndex = {} }
        local allies, enemies = {}, {}
        for i = 1, 4 do allies[i], enemies[i] = { heroId = i }, { monsterId = i } end
        local cx, cy = reviewLayout.posForList(enemies, 1)
        local types = {
            { channel = "damage", atkType = AD.ATK_FIRE },
            { channel = "damage", atkType = AD.ATK_ICE },
            { channel = "damage", atkType = AD.ATK_LIGHTNING, isCrit = true },
            { channel = "shield", atkType = AD.ATK_FIRE },
            { channel = "heal", atkType = AD.ATK_HOLY },
        }
        local labels = { "典型：同目标3条（含0.21s新批）", "极密：同目标6条（含0.21s新批）", "混合：敌前排3条 + 我方治疗/吸盾" }
        local count = row == 2 and 5 or 2
        for i = 1, count do
            Fx.addCombatNumber(bcs, enemies[1], 1234 + i * 113, cx, cy, types[i])
        end
        if row == 3 then
            local ax, ay = reviewLayout.posForList(allies, 1)
            Fx.addCombatNumber(bcs, allies[1], 350, ax, ay, types[5])
            Fx.addCombatNumber(bcs, allies[1], 240, ax, ay, types[4])
            local ex, ey = reviewLayout.posForList(enemies, 3)
            Fx.addCombatNumber(bcs, enemies[3], 999960, ex, ey, types[3])
        end
        Fx.updateFloatingTexts(bcs, 0.21)
        Fx.addCombatNumber(bcs, enemies[1], 987, cx, cy, types[1])
        Fx.updateFloatingTexts(bcs, age - 0.21)
        reviewLanes[row] = { bcs = bcs, age = age, allies = allies, enemies = enemies, label = labels[row] }
    end
end

local function drawStaggerReview()
    nvgFontFace(reviewVg, "sans"); nvgFontSize(reviewVg, 30)
    nvgTextAlign(reviewVg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(reviewVg, nvgRGBA(239, 228, 204, 255))
    nvgText(reviewVg, 45, 40, "正式 Fx → BattleDraw → Impact | 固定出生错位 / 三行条带", nil)
    nvgFontSize(reviewVg, 21)
    nvgText(reviewVg, 45, 80, "phase=" .. reviewPhase .. " | 真实BattleLayout 948×360 / 双方4+4卡 / 出生后0.21s开新批", nil)
    nvgText(reviewVg, 45, 112, "sans=" .. reviewFont .. " | 无main、玩家档、RNG；矩形为模拟卡位，非真实战斗截图", nil)
    local function strip(lane, x, y, scale)
        nvgSave(reviewVg); nvgTranslate(reviewVg, x, y); nvgScale(reviewVg, scale, scale)
        nvgBeginPath(reviewVg); nvgRect(reviewVg, 0, 0, 948, 360)
        nvgFillColor(reviewVg, nvgRGBA(25, 29, 37, 255)); nvgFill(reviewVg)
        nvgStrokeColor(reviewVg, nvgRGBA(144, 127, 99, 255)); nvgStrokeWidth(reviewVg, 2); nvgStroke(reviewVg)
        local cardW = reviewLayout.CARD_W * reviewLayout.CARD_SCALE
        local cardH = reviewLayout.CARD_H * reviewLayout.CARD_SCALE
        for side, units in ipairs({ lane.allies, lane.enemies }) do
            for card = 1, 4 do
                local cx, cy = reviewLayout.posForList(units, card)
                nvgBeginPath(reviewVg); nvgRect(reviewVg, cx - cardW * 0.5, cy - cardH * 0.5, cardW, cardH)
                nvgFillColor(reviewVg, side == 1 and nvgRGBA(35, 47, 53, 255) or nvgRGBA(52, 39, 43, 255))
                nvgFill(reviewVg)
                nvgStrokeColor(reviewVg, nvgRGBA(86, 93, 107, 255)); nvgStrokeWidth(reviewVg, 1); nvgStroke(reviewVg)
                nvgBeginPath(reviewVg); nvgMoveTo(reviewVg, cx - 9, cy); nvgLineTo(reviewVg, cx + 9, cy)
                nvgMoveTo(reviewVg, cx, cy - 9); nvgLineTo(reviewVg, cx, cy + 9)
                nvgStrokeColor(reviewVg, nvgRGBA(130, 139, 150, 255)); nvgStroke(reviewVg)
                nvgFontSize(reviewVg, 16); nvgTextAlign(reviewVg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(reviewVg, nvgRGBA(165, 172, 184, 255))
                nvgText(reviewVg, cx, cy + cardH * 0.5 + 17, (side == 1 and "我" or "敌") .. card, nil)
            end
        end
        reviewDraw.setContext({ combat = { getFloatingTexts = function() return lane.bcs.floatingTexts end } })
        reviewDraw.drawFloatingTexts(reviewVg)
        nvgRestore(reviewVg)
    end
    for row, lane in ipairs(reviewLanes) do
        local y = 165 + (row - 1) * 300
        nvgFontSize(reviewVg, 20); nvgTextAlign(reviewVg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(reviewVg, nvgRGBA(210, 204, 188, 255))
        nvgText(reviewVg, 45, y - 15, string.format("行%d %s | %.2f/%.2fs | 0.80×", row, lane.label, lane.age, lane.age - 0.21), nil)
        strip(lane, 45, y, 0.80)
    end
    local focus = reviewLanes[2]
    nvgFontSize(reviewVg, 24); nvgTextAlign(reviewVg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(reviewVg, nvgRGBA(239, 228, 204, 255))
    nvgText(reviewVg, 880, 190, "行2原比例复核（1.00×，仍走strip bounds）", nil)
    strip(focus, 880, 220, 1)
    nvgFontSize(reviewVg, 20); nvgTextAlign(reviewVg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(reviewVg, nvgRGBA(185, 190, 201, 255))
    nvgText(reviewVg, 880, 620, "行2实际出生字段：seq / channel / type / spreadX,Y / age", nil)
    for i, ft in ipairs(focus.bcs.floatingTexts) do
        nvgText(reviewVg, 880, 655 + (i - 1) * 29, string.format("%s  %s  %s  (%s,%s)  %.2f",
            tostring(ft.visualSequence), tostring(ft.channel), tostring(ft.atkType),
            tostring(ft.spreadX), tostring(ft.spreadY), ft.timer), nil)
    end
end

local function startReview()
    -- 复用本测试入口的真实像素矩阵；业务依赖隔离，只执行原图标/飘字模块。
    local function module(path, mocks)
        local file = assert(cache:GetFile(path))
        local lines = {}; while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.require = function(name) return assert(mocks[name], name) end
        env.math = setmetatable({ random = function() error("REVIEW_RNG") end,
            randomseed = function() error("REVIEW_RANDOMSEED") end }, { __index = math })
        return assert(load(table.concat(lines, "\n"), "@damage-review/" .. path, "t", env))()
    end
    local AD = require("systems.AttributeDef")
    local Number = module("core/NumberUtil.lua", {})
    local Icon = module("ui/battle/scene/DamageTypeIcon.lua", { ["systems.AttributeDef"] = AD })
    local Fx = module("ui/battle/combat/BattleCombatFx.lua", { ["core.NumberUtil"] = Number,
        ["ui.battle.scene.DamageTypeIcon"] = Icon,
        ["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return true end } })
    local Util = module("core/DrawUtil.lua", { ["core.BattleLayout"] = {} })
    local Impact = module("ui/battle/scene/BattleFloatImpact.lua", { ["ui.battle.scene.DamageTypeIcon"] = Icon })
    reviewLayout = isStaggerReview() and module("core/BattleLayout.lua", {})
        or { CARD_W = 100, CARD_H = 100 }
    reviewDraw = module("ui/battle/scene/BattleDraw.lua", {
        ["systems.StatusEffectManager"] = {}, ["systems.TalentManager"] = {}, ["core.NumberUtil"] = Number,
        ["core.BattleLayout"] = reviewLayout, ["core.DrawUtil"] = Util,
        ["systems.ExtraTalentSystem"] = {}, ["config.HeroAssetUtil"] = {}, ["ui.battle.scene.BattleFloatImpact"] = Impact,
    })
    if isStaggerReview() then
        prepareStaggerReview(Fx, AD)
    else
    local bcs = { floatingTexts = {}, ftPool = {}, combatNumberIndex = {} }
    local names = { "斩击 / SLASH", "粉碎 / CRUSH", "穿刺 / PIERCE", "火焰 / FIRE",
        "冰霜 / ICE", "闪电 / LIGHTNING", "暗影 / SHADOW", "神圣额伤 / HOLY DAMAGE" }
    for i = 1, 8 do
        local x, y = 215 + ((i - 1) % 4) * 390, 260 + math.floor((i - 1) / 4) * 240
        local entry = Fx.addCombatNumber(bcs, {}, 1234, x, y, { channel = "damage", atkType = i, fontSize = 80 })
        entry.label, entry.reviewX, entry.reviewY = names[i], x, y
        entry.dirX, entry.dirY = 0, 0
    end
    for i, meta in ipairs({ { channel = "shield", atkType = AD.ATK_FIRE },
        { channel = "heal", atkType = AD.ATK_HOLY },
        { channel = "damage", atkType = AD.ATK_FIRE, isCrit = true, isBlocked = true, isDot = true } }) do
        local x, y = 235 + (i - 1) * 500, 760
        local entry = Fx.addCombatNumber(bcs, {}, 350, x, y, meta)
        entry.label = ({ "护盾吸收 / SHIELD", "治疗 / HEAL", "暴击 + 格挡 + DOT" })[i]
        entry.reviewX, entry.reviewY, entry.dirX, entry.dirY = x, y, 0, 0
    end
    local target = {}
    local total = Fx.addCombatNumber(bcs, target, 100, 1400, 950, { channel = "damage", atkType = AD.ATK_FIRE })
    total.label, total.reviewX, total.reviewY, total.dirX, total.dirY = "短窗：100 + 250 = 350", 1400, 950, 0, 0
    if reviewPhase == "merge" then
        Fx.updateFloatingTexts(bcs, 0.1)
        Fx.addCombatNumber(bcs, target, 250, 1400, 950, { channel = "damage", atkType = AD.ATK_FIRE })
    elseif reviewPhase == "fade" then
        Fx.updateFloatingTexts(bcs, 0.63)
    elseif reviewPhase == "expired" then
        Fx.updateFloatingTexts(bcs, 0.71)
    end
    reviewTexts = bcs.floatingTexts
    reviewDraw.setContext({ combat = { getFloatingTexts = function() return reviewTexts end } })
    end
    reviewVg = nvgCreate(1)
    assert(reviewVg)
    reviewFont = "Fonts/NotoSansCJKkr-Bold.otf"
    if nvgCreateFont(reviewVg, "sans", reviewFont) < 0 then
        reviewFont = "Fonts/MiSans-Regular.ttf"
        assert(nvgCreateFont(reviewVg, "sans", reviewFont) >= 0)
    end
    SubscribeToEvent(reviewVg, "NanoVGRender", "HandleDamageReviewRender")
    print(TAG .. " REVIEW phase=" .. reviewPhase .. " frame-controlled=true player-save=false gameplay-rng=false")
end

function HandleDamageReviewRender()
    local width, height = graphics:GetWidth(), graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logicalW, logicalH = width / dpr, height / dpr
    local designW = isStaggerReview() and 1900 or 1640
    local scale = math.min(logicalW / designW, logicalH / 1100)
    nvgBeginFrame(reviewVg, logicalW, logicalH, dpr)
    nvgScale(reviewVg, scale, scale)
    nvgBeginPath(reviewVg); nvgRect(reviewVg, 0, 0, logicalW / scale, logicalH / scale)
    nvgFillColor(reviewVg, nvgRGBA(17, 20, 27, 255)); nvgFill(reviewVg)
    if isStaggerReview() then
        drawStaggerReview()
        nvgEndFrame(reviewVg)
        return
    end
    nvgFontFace(reviewVg, "sans"); nvgFontSize(reviewVg, 34)
    nvgTextAlign(reviewVg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(reviewVg, nvgRGBA(239, 228, 204, 255))
    nvgText(reviewVg, 50, 55, "战斗数字：八属性 / 吸盾 / 治疗 / 独立角标", nil)
    nvgFontSize(reviewVg, 23)
    nvgText(reviewVg, 50, 100, "phase=" .. reviewPhase .. " | 即时出生、0.2秒只合并、0.7秒硬寿命", nil)
    for _, entry in ipairs(reviewTexts) do
        nvgFontSize(reviewVg, 23)
        nvgTextAlign(reviewVg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(reviewVg, nvgRGBA(180, 184, 197, 255))
        nvgText(reviewVg, entry.reviewX, entry.reviewY - 78, entry.label, nil)
    end
    reviewDraw.drawFloatingTexts(reviewVg)
    nvgEndFrame(reviewVg)
end

function Stop()
    if reviewVg then nvgDelete(reviewVg); reviewVg = nil end
end

function Start()
    local staggerOnly = false
    for _, arg in ipairs(GetArguments()) do
        if arg == "-stagger-only" then staggerOnly = true end
        if arg:find("-review-phase=", 1, true) == 1 then reviewPhase = arg:sub(15) end
    end
    for _, arg in ipairs(GetArguments()) do if arg == "-review" then startReview(); return end end
    local ok, err = xpcall(function()
        local AD = require("systems.AttributeDef")
        local sources = {}
        local function source(path)
            if not sources[path] then
                local file = assert(cache:GetFile(path), path)
                local lines = {}
                while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
                file:Dispose()
                sources[path] = table.concat(lines, "\n")
            end
            return sources[path]
        end
        local rngCalls = 0
        local function compile(path, mocks, fields)
            local env = fields or {}
            if not getmetatable(env) then setmetatable(env, { __index = _G }) end
            env._G = env
            env.require = function(name)
                assert(mocks[name] ~= nil, "undeclared require " .. name)
                return mocks[name]
            end
            env.math = setmetatable({ random = function()
                rngCalls = rngCalls + 1; error("VISUAL_CONSUMED_GAMEPLAY_RNG")
            end, randomseed = function()
                rngCalls = rngCalls + 1; error("VISUAL_RESET_GAMEPLAY_RNG")
            end }, { __index = math })
            return assert(load(source(path), "@damage-real/" .. path, "t", env))(), env
        end
        local function poolClean(bcs)
            for _, ft in ipairs(bcs.ftPool) do if next(ft) ~= nil then return false end end
            return true
        end
        local function indexEntries(bcs)
            local n = 0
            for _, target in pairs(bcs.combatNumberIndex) do
                for _, channel in pairs(target) do for _ in pairs(channel) do n = n + 1 end end
            end
            return n
        end
        local Number = compile("core/NumberUtil.lua", {})
        local Icon = compile("ui/battle/scene/DamageTypeIcon.lua", { ["systems.AttributeDef"] = AD })
        local Fx = compile("ui/battle/combat/BattleCombatFx.lua", {
            ["core.NumberUtil"] = Number, ["ui.battle.scene.DamageTypeIcon"] = Icon,
            ["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return true end },
        })
        local function state() return { floatingTexts = {}, ftPool = {}, combatNumberIndex = {}, hitFlashes = {} } end
        local bcs, target = state(), { monsterId = 1 }
        local fire = { channel = "damage", atkType = AD.ATK_FIRE }
        local first = Fx.addCombatNumber(bcs, target, 100, 300, 180, fire)
        check(#bcs.floatingTexts == 1 and first.amount == 100 and first.text == "100" and first.timer == 0,
            "首笔即生效且无需update/等待短窗")
        Fx.updateFloatingTexts(bcs, 0.1)
        local merged = Fx.addCombatNumber(bcs, target, 250, 300, 180, fire)
        check(merged == first and #bcs.floatingTexts == 1 and first.amount == 350 and first.text == "350"
            and near(first.timer, 0.1) and first.duration == 0.7,
            "同目标火100+250原数相加350，寿命不续")
        Fx.addCombatNumber(bcs, target, 50, 300, 180, {
            channel = "damage", atkType = AD.ATK_FIRE, isCrit = true, isBlocked = true, isDot = true,
        })
        check(first.amount == 400 and first.isCrit and first.isBlocked and first.isDot
            and #bcs.floatingTexts == 1,
            "普通/暴击/格挡/DOT同火合并且保留全部角标")
        local other = { monsterId = 1 }
        Fx.addCombatNumber(bcs, other, 9, 300, 180, fire)
        Fx.addCombatNumber(bcs, target, 8, 300, 180, { channel = "damage", atkType = AD.ATK_ICE })
        Fx.addCombatNumber(bcs, target, 7, 300, 180, { channel = "shield", atkType = AD.ATK_FIRE })
        Fx.addCombatNumber(bcs, target, 6, 300, 180, { channel = "heal", atkType = AD.ATK_HOLY })
        Fx.addCombatNumber(bcs, target, 5, 300, 180, { channel = "damage", atkType = AD.ATK_HOLY })
        check(#bcs.floatingTexts == 6 and indexEntries(bcs) == 6 and bcs.floatingTexts[5].text == "+6"
            and bcs.floatingTexts[6].channel == "damage", "同ID同坐标不同引用/火冰/吸盾/治疗/圣额伤各自独立")
        local immediate = Fx.addFloatingText(bcs, "免疫", 1, 2, { 1, 2, 3 }, false, nil, true)
        check(immediate.text == "免疫" and #bcs.floatingTexts == 7 and bcs.pendingFt == nil,
            "非数字兼容deferred参数但即显，无pending队列")
        check(Fx.addCombatNumber(bcs, target, 0, 1, 2, fire) == nil
            and Fx.addCombatNumber(bcs, target, -1, 1, 2, fire) == nil
            and Fx.addCombatNumber(bcs, target, math.huge, 1, 2, fire) == nil
            and Fx.addCombatNumber(bcs, nil, 1, 1, 2, fire) == nil, "零/负/非有限/无目标数字不占预算")
        Fx.resetFloatingTexts(bcs)
        check(#bcs.floatingTexts == 0 and indexEntries(bcs) == 0 and poolClean(bcs), "重置释放全部target与索引且池无旧字段")
        local abbreviated = Fx.addCombatNumber(bcs, target, 9999.6, 1, 2, fire)
        Fx.addCombatNumber(bcs, target, 0.6, 1, 2, fire)
        check(near(abbreviated.amount, 10000.2) and abbreviated.text == "10k", "先累计小数原amount后format，不把9999+0截断")
        Fx.resetFloatingTexts(bcs)
        local edge = Fx.addCombatNumber(bcs, target, 999940, 1, 2, fire)
        Fx.addCombatNumber(bcs, target, 20, 1, 2, fire)
        check(edge.amount == 999960 and edge.text == "1M", "k/M边界先sum再format进位")
        Fx.resetFloatingTexts(bcs)
        local old = Fx.addCombatNumber(bcs, target, 1, 1, 2, fire)
        Fx.updateFloatingTexts(bcs, 0.200001)
        local fresh = Fx.addCombatNumber(bcs, target, 2, 1, 2, fire)
        check(fresh ~= old and #bcs.floatingTexts == 2 and old.amount == 1, "超过0.2秒立即开新批，不等旧批淡出")
        Fx.updateFloatingTexts(bcs, 0.5)
        check(#bcs.floatingTexts == 1 and bcs.combatNumberIndex[target].damage[AD.ATK_FIRE] == fresh
            and poolClean(bcs), "旧批到期不误删新批索引，清全部旧字段")
        Fx.resetFloatingTexts(bcs)
        local continuous = Fx.addCombatNumber(bcs, target, 1, 1, 2, fire)
        for _ = 1, 6 do Fx.updateFloatingTexts(bcs, 0.1); Fx.addCombatNumber(bcs, target, 1, 1, 2, fire) end
        check(#bcs.floatingTexts == 1 and continuous.amount == 7 and near(continuous.timer, 0.6), "持续六次合并不重置出生计时")
        Fx.updateFloatingTexts(bcs, 0.100001)
        check(#bcs.floatingTexts == 0 and next(bcs.combatNumberIndex) == nil and poolClean(bcs), "持续伤害批次最晚0.7秒硬回收")
        local targets, bounded = {}, true
        for i = 1, 1000 do
            targets[i] = { monsterId = 1 }
            Fx.addCombatNumber(bcs, targets[i], i, 1, 2, fire)
            bounded = bounded and #bcs.floatingTexts <= 15 and indexEntries(bcs) <= 15
        end
        check(bounded and #bcs.floatingTexts == 15 and bcs.floatingTexts[1].amount == 986
            and bcs.floatingTexts[15].amount == 1000 and bcs.combatNumberIndex[targets[1]] == nil,
            "1000次单帧洪峰硬上限15，淘汰最旧保最新，旧目标索引释放")
        Fx.resetFloatingTexts(bcs)
        local retained = Fx.addCombatNumber(bcs, target, 100, 1, 2, fire)
        for i = 1, 999 do Fx.addCombatNumber(bcs, target, 1, 1, 2, fire) end
        check(#bcs.floatingTexts == 1 and retained.amount == 1099, "同目标单帧1000命中仅1数字但原值全部相加")
        local lanes = { state(), state(), state() }
        for _, lane in ipairs(lanes) do Fx.addCombatNumber(lane, target, 1, 1, 2, fire) end
        Fx.addCombatNumber(lanes[2], target, 10, 1, 2, fire)
        Fx.resetFloatingTexts(lanes[1])
        check(#lanes[1].floatingTexts == 0 and lanes[2].floatingTexts[1].amount == 11
            and lanes[3].floatingTexts[1].amount == 1, "同hero引用跨三BCS隔离，重置一栏不污染另两栏")

        for _, kind in ipairs({ "phys", "magic", "burn", "block", "shield", "heal", "crit", "critblockmagic" }) do
            check(Icon.resolve(nil, kind) ~= nil, "旧kind可解析 " .. kind)
        end
        check(Icon.resolve(nil, "未知") == nil and Icon.resolve(nil, "") == nil, "未知/空kind不留空图标占位")
        local resolved = Icon.resolve({ channel = "damage", atkType = AD.ATK_HOLY }, "heal")
        check(resolved.channel == "damage" and resolved.atkType == AD.ATK_HOLY, "显式damage不会被holy/旧heal语义覆盖")

        -- 出生错位契约：真实Fx，不锁死候选的具体排列/评分公式，也不使用RNG。
        local function birth(ft)
            return { x = ft.x, y = ft.y, dirX = ft.dirX, dirY = ft.dirY,
                visualSequence = ft.visualSequence, spreadX = ft.spreadX, spreadY = ft.spreadY }
        end
        local function sameBirth(ft, frozen)
            for _, key in ipairs({ "x", "y", "dirX", "dirY", "visualSequence", "spreadX", "spreadY" }) do
                if ft[key] ~= frozen[key] then return false end
            end
            return true
        end
        local function validBirth(ft)
            return type(ft.visualSequence) == "number" and ft.visualSequence > 0
                and ft.visualSequence % 1 == 0 and type(ft.spreadX) == "number"
                and ft.spreadX == ft.spreadX and math.abs(ft.spreadX) <= 32
                and type(ft.spreadY) == "number" and ft.spreadY == ft.spreadY and math.abs(ft.spreadY) <= 88
        end
        local scattered, scatterTarget = state(), {}
        local anchor = Fx.addCombatNumber(scattered, scatterTarget, 100, 474, 180, fire)
        local frozenAnchor = birth(anchor)
        check(validBirth(anchor) and scattered.ftSequence == anchor.visualSequence,
            "出生固定visualSequence/spread，X±32/Y±88且序号来自本BCS")
        Fx.updateFloatingTexts(scattered, 0.1)
        local joined = Fx.addCombatNumber(scattered, scatterTarget, 25, 999, 999,
            { channel = "damage", atkType = AD.ATK_FIRE, isCrit = true })
        check(joined == anchor and anchor.amount == 125 and near(anchor.timer, 0.1)
            and sameBirth(anchor, frozenAnchor) and scattered.ftSequence == frozenAnchor.visualSequence,
            "合并可更新金额/暴击但不挪锚点/出生偏移/序号、不消耗新序号")
        Fx.updateFloatingTexts(scattered, 0.21)
        local secondBatch = Fx.addCombatNumber(scattered, scatterTarget, 70, 474, 180, fire)
        check(secondBatch ~= anchor and validBirth(secondBatch)
            and secondBatch.visualSequence > (anchor.visualSequence or math.huge)
            and (secondBatch.spreadX ~= anchor.spreadX or secondBatch.spreadY ~= anchor.spreadY)
            and sameBirth(anchor, frozenAnchor), "0.21无新命中后新批选另一宽松位置，旧批出生字段不变")
        for _, meta in ipairs({
            { channel = "damage", atkType = AD.ATK_ICE },
            { channel = "damage", atkType = AD.ATK_LIGHTNING, isCrit = true },
            { channel = "damage", atkType = AD.ATK_SHADOW },
            { channel = "shield", atkType = AD.ATK_FIRE },
            { channel = "heal", atkType = AD.ATK_HOLY },
        }) do Fx.addCombatNumber(scattered, scatterTarget, 23, 474, 180, meta) end
        local spreadPairs = {}
        for _, ft in ipairs(scattered.floatingTexts) do
            spreadPairs[tostring(ft.spreadX) .. ":" .. tostring(ft.spreadY)] = true
            check(validBirth(ft), "同目标多属性/暴击/治疗/吸盾有效固定出生字段 " .. tostring(ft.visualSequence))
        end
        local pairCount = 0; for _ in pairs(spreadPairs) do pairCount = pairCount + 1 end
        check(pairCount == #scattered.floatingTexts, "同目标同锚点的七个活跃批次出生二维位置不重复")
        local oldest = scattered.floatingTexts[1]
        local survivors = {}
        for i = 2, #scattered.floatingTexts do
            survivors[#survivors + 1] = { ft = scattered.floatingTexts[i], frozen = birth(scattered.floatingTexts[i]) }
        end
        Fx.updateFloatingTexts(scattered, 0.4)
        local survivorStable = next(oldest) == nil
        for _, entry in ipairs(survivors) do survivorStable = survivorStable and sameBirth(entry.ft, entry.frozen) end
        check(survivorStable and poolClean(scattered) and #scattered.floatingTexts == #survivors,
            "前项寿命到期移除后剩余对象出生字段原样，池不保留旧spread/sequence/target")
        Fx.resetFloatingTexts(scattered)
        check(scattered.ftSequence == 0 and #scattered.floatingTexts == 0 and indexEntries(scattered) == 0
            and poolClean(scattered), "reset归零BCS序号并清空所有活跃项/索引及池内全部字段")
        local reborn = Fx.addFloatingText(scattered, "免疫", 474, 180, nil, false, 80)
        check(validBirth(reborn) and reborn.visualSequence == 1, "非数字兼容入口也重新取得完整出生字段，不继承池旧值")
        Fx.resetFloatingTexts(scattered)
        local replayStates = { state(), state(), state() }
        for i = 1, 36 do
            local expected = {}
            for laneIndex, lane in ipairs(replayStates) do
                local ft = Fx.addCombatNumber(lane, {}, i, 474, 180, fire)
                check(validBirth(ft) and ft.visualSequence == i and #lane.floatingTexts == math.min(i, 15),
                    "跨BCS同输入序号/15预算 " .. i .. "/" .. laneIndex)
                if laneIndex == 1 then expected = birth(ft)
                else check(sameBirth(ft, expected), "跨BCS出生错位与引用地址无关 " .. i .. "/" .. laneIndex) end
            end
        end
        local twelve = state()
        local distinctY, twelvePairs = {}, {}
        for i = 1, 12 do
            local ft = Fx.addCombatNumber(twelve, {}, i, 474, 180, fire)
            distinctY[tostring(ft.spreadY)] = true
            twelvePairs[tostring(ft.spreadX) .. ":" .. tostring(ft.spreadY)] = true
        end
        local yCount, candidateCount = 0, 0
        for _ in pairs(distinctY) do yCount = yCount + 1 end
        for _ in pairs(twelvePairs) do candidateCount = candidateCount + 1 end
        check(yCount > 3 and candidateCount == 12, "同锚点前12出生用不同宽松处，Y不是旧三档循环")
        for i = 13, 15 do
            local ft = Fx.addCombatNumber(twelve, {}, i, 474, 180, fire)
            twelvePairs[tostring(ft.spreadX) .. ":" .. tostring(ft.spreadY)] = true
        end
        local fifteenPositions = 0; for _ in pairs(twelvePairs) do fifteenPositions = fifteenPositions + 1 end
        check(fifteenPositions == 15, "同锚点15预算内出生二维位置均不同（不等于字墨无重叠）")
        local evictionSurvivors = {}
        for i = 2, 15 do
            evictionSurvivors[#evictionSurvivors + 1] = { ft = twelve.floatingTexts[i], frozen = birth(twelve.floatingTexts[i]) }
        end
        Fx.addCombatNumber(twelve, {}, 16, 474, 180, fire)
        local evictionStable = #twelve.floatingTexts == 15 and indexEntries(twelve) == 15
        for i, entry in ipairs(evictionSurvivors) do
            evictionStable = evictionStable and twelve.floatingTexts[i] == entry.ft and sameBirth(entry.ft, entry.frozen)
        end
        check(evictionStable, "第16项淘汰首项而不挪其余14项，仍为15预算/15索引")
        for _, lane in ipairs(replayStates) do Fx.resetFloatingTexts(lane) end
        Fx.resetFloatingTexts(twelve)
        check(poolClean(twelve) and #twelve.ftPool <= 15, "15预算回收/复用后池字段全部清空且池容量有界")

        -- 真实Impact + 真实Icon，所有NanoVG调用只进入局部记录器。
        -- 确定性单字符测宽，不是字体字墨/像素；bounds只验证世界锚点+裁剪契约。
        local function copyValue(value)
            if type(value) ~= "table" then return value end
            local result = {}; for key, v in pairs(value) do result[key] = copyValue(v) end
            return result
        end
        local function sameValue(a, b)
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return a == b end
            for key, value in pairs(a) do if not sameValue(value, b[key]) then return false end end
            for key in pairs(b) do if a[key] == nil then return false end end
            return true
        end
        local function snapshot(ft)
            local refs = {}; for key, value in pairs(ft) do if type(value) == "table" then refs[key] = value end end
            return { values = copyValue(ft), refs = refs }
        end
        local function unchanged(ft, before)
            if not sameValue(ft, before.values) then return false end
            for key, ref in pairs(before.refs) do if ft[key] ~= ref then return false end end
            return true
        end
        local recorder = { calls = {}, stack = {}, current = { fontSize = 19, alpha = 0.37, fontFace = "host" },
            saves = 0, restores = 0, underflow = 0 }
        local fields = {}
        for _, name in ipairs({ "nvgBeginPath", "nvgMoveTo", "nvgLineTo", "nvgQuadTo", "nvgBezierTo",
            "nvgClosePath", "nvgCircle", "nvgRect", "nvgFill", "nvgStroke", "nvgStrokeWidth",
            "nvgFillColor", "nvgStrokeColor", "nvgFillPaint", "nvgTextAlign" }) do fields[name] = noop end
        fields.nvgRGBA = function(r, g, b, a) return { r, g, b, a } end
        fields.nvgFillColor = function(_, color) recorder.current.fillColor = copyValue(color) end
        fields.nvgLinearGradient = function(...) return { ... } end
        fields.nvgSave = function()
            recorder.saves = recorder.saves + 1
            recorder.stack[#recorder.stack + 1] = copyValue(recorder.current)
        end
        fields.nvgRestore = function()
            recorder.restores = recorder.restores + 1
            if #recorder.stack == 0 then recorder.underflow = recorder.underflow + 1; return end
            recorder.current = table.remove(recorder.stack)
        end
        fields.nvgFontFace = function(_, face) recorder.current.fontFace = face end
        fields.nvgFontSize = function(_, size) recorder.current.fontSize = size end
        fields.nvgGlobalAlpha = function(_, alpha)
            recorder.current.alpha = alpha
            recorder.calls[#recorder.calls + 1] = { kind = "alpha", value = alpha }
        end
        fields.nvgTextBounds = function(_, x, y, text, _, bounds)
            local width = #text * recorder.current.fontSize * 0.6
            if bounds then bounds[1], bounds[2], bounds[3], bounds[4] = x, y - recorder.current.fontSize * 0.5,
                x + width, y + recorder.current.fontSize * 0.5 end
            return width
        end
        for _, name in ipairs({ "nvgTranslate", "nvgRotate", "nvgScale", "nvgIntersectScissor" }) do
            fields[name] = function(_, ...)
                recorder.calls[#recorder.calls + 1] = { kind = name, values = { ... } }
            end
        end
        fields.nvgText = function(_, x, y, text)
            recorder.calls[#recorder.calls + 1] = { kind = "text", x = x, y = y, text = text,
                fontSize = recorder.current.fontSize, fillColor = copyValue(recorder.current.fillColor) }
        end
        -- 不给未知nvg接口回落到原生：新接口若出现必须显式补记录器，避免假VG进入引擎。
        setmetatable(fields, { __index = function(_, key)
            if type(key) == "string" and key:sub(1, 3) == "nvg" then error("UNRECORDED_NVG " .. key) end
            return _G[key]
        end })
        local RecordedIcon = compile("ui/battle/scene/DamageTypeIcon.lua", { ["systems.AttributeDef"] = AD }, fields)
        local Impact = compile("ui/battle/scene/BattleFloatImpact.lua",
            { ["ui.battle.scene.DamageTypeIcon"] = RecordedIcon }, fields)
        local stripBounds = { x = 0, y = 0, w = 948, h = 360 }
        ---@class DamageMergeDrawRecord
        ---@field calls table[]
        ---@field translations number[][]
        ---@field rotations number[]
        ---@field scales number[][]
        ---@field clips number[][]
        ---@field texts table[]
        ---@field world number[]?
        ---@return DamageMergeDrawRecord
        local function recordedDraw(ft, slot, bounds)
            recorder.calls, recorder.stack = {}, {}
            recorder.saves, recorder.restores, recorder.underflow = 0, 0, 0
            recorder.current = { fontSize = 19, alpha = 0.37, fontFace = "host" }
            local before = snapshot(ft)
            Impact.draw({}, ft, slot, bounds)
            check(unchanged(ft, before), "Impact只读ft全部字段/嵌套值/引用 " .. tostring(ft.channel) .. "/" .. tostring(ft.timer))
            check(recorder.saves == recorder.restores and #recorder.stack == 0 and recorder.underflow == 0
                and sameValue(recorder.current, { fontSize = 19, alpha = 0.37, fontFace = "host" }),
                "Save/Restore平衡并还原宿主字号/alpha/fontFace")
            ---@type DamageMergeDrawRecord
            local result = { calls = recorder.calls, translations = {}, rotations = {}, scales = {}, clips = {}, texts = {} }
            for _, call in ipairs(recorder.calls) do
                if call.kind == "nvgTranslate" then result.translations[#result.translations + 1] = call.values
                elseif call.kind == "nvgRotate" then result.rotations[#result.rotations + 1] = call.values[1]
                elseif call.kind == "nvgScale" then result.scales[#result.scales + 1] = call.values
                elseif call.kind == "nvgIntersectScissor" then result.clips[#result.clips + 1] = call.values
                elseif call.kind == "text" then result.texts[#result.texts + 1] = call end
            end
            result.world = result.translations[1]
            return result
        end
        local drawingState = state()
        for _, meta in ipairs({ fire,
            { channel = "damage", atkType = AD.ATK_LIGHTNING, isCrit = true, isBlocked = true, isDot = true },
            { channel = "heal", atkType = AD.ATK_HOLY },
            { channel = "shield", atkType = AD.ATK_FIRE },
        }) do Fx.addCombatNumber(drawingState, {}, 1234, 474, 180, meta) end
        for _, ft in ipairs(drawingState.floatingTexts) do
            -- 早期crit旋转/side尚非零，晚期覆盖擦除条带；同一timer改变slot应得到完整相同绘制记录。
            for _, timer in ipairs({ 0.02, 0.30, 0.64 }) do
                ft.timer = timer
                local a, b = recordedDraw(ft, 1, stripBounds), recordedDraw(ft, 8, stripBounds)
                check(a.world ~= nil and #a.texts > 0 and sameValue(a.calls, b.calls),
                    "有出生字段同对象同timer换slot位置/side/擦除均不重排 " .. ft.channel .. "/" .. timer)
                if a.world then
                    check(a.world[1] >= 0 and a.world[1] <= 948 and a.world[2] >= 0 and a.world[2] <= 360
                        and sameValue(a.clips[1], { 0, 0, 948, 360 }), "strip最先世界平移在bounds内且先设真实裁剪")
                end
            end
            ft.timer = 0.25
            local early = recordedDraw(ft, 4, stripBounds)
            ft.timer = 0.55
            local late = recordedDraw(ft, 4, stripBounds)
            check(early.world ~= nil and late.world ~= nil and early.world[2] > late.world[2]
                and early.world[2] - late.world[2] < 22,
                "settle后随时间只向上轻漂（非旧240长上浮） " .. ft.channel)
            ft.timer = 0.30
            local normal = recordedDraw(ft, 3, stripBounds)
            local expectedSize = (ft.baseFontSize or 80) * 0.5
                * (ft.channel == "shield" and 0.96 or ft.channel == "damage" and ft.isCrit and 1.28 or 1)
            check(normal.texts[1] ~= nil and near(normal.texts[1].fontSize, expectedSize),
                "0.5基础字号及原风格倍率保留 " .. ft.channel)
            if ft.channel ~= "heal" then
                local compensation = normal.translations[2]
                check(compensation ~= nil and near(compensation[1], -(expectedSize * 0.72 + 7) * 0.5)
                    and compensation[2] == 0, "徽记后的数字中心补偿保留 " .. ft.channel)
            end
            ft.text = "123456789012345678901234567890"
            for _, corner in ipairs({ { -300, -300 }, { 1248, -300 }, { -300, 660 }, { 1248, 660 } }) do
                ft.x, ft.y = corner[1], corner[2]
                local drawn = recordedDraw(ft, 2, stripBounds)
                local width = #ft.text * expectedSize * 0.6
                    + (ft.channel ~= "heal" and expectedSize * 0.72 + 7 or 0)
                check(drawn.world ~= nil and drawn.world[1] >= 0 and drawn.world[1] <= 948
                    and drawn.world[2] >= 0 and drawn.world[2] <= 360
                    and sameValue(drawn.clips[1], { 0, 0, 948, 360 }),
                    "长数字四角越界锚点clamp及strip裁剪 " .. ft.channel)
                check(drawn.scales[1] ~= nil and near(drawn.scales[1][1], 200 / width)
                    and near(drawn.scales[1][2], 200 / width)
                    and drawn.texts[1] ~= nil and drawn.texts[1].text == ft.text,
                    "确定性测宽整组fit200不截长数字（非原生字墨/像素） " .. ft.channel)
            end
        end
        local positionState = state()
        local positionFt = Fx.addCombatNumber(positionState, {}, 123, 474, 180,
            { channel = "damage", atkType = AD.ATK_FIRE, isCrit = true })
        positionFt.timer = 0.30
        local positionA = recordedDraw(positionFt, 2, nil)
        local shifted = copyValue(positionFt)
        shifted.spreadX, shifted.spreadY = (positionFt.spreadX or 0) + 8, (positionFt.spreadY or 0) - 13
        local positionB = recordedDraw(shifted, 2, nil)
        check(positionA.world ~= nil and positionB.world ~= nil
            and near(positionB.world[1] - positionA.world[1], 8)
            and near(positionB.world[2] - positionA.world[2], -13),
            "Impact世界锚点实际消费固定spreadX/Y，而非只保存不用")
        positionFt.timer = 0.02
        local sideA = recordedDraw(positionFt, 2, nil)
        local alternateSequence = copyValue(positionFt)
        alternateSequence.visualSequence = (positionFt.visualSequence or 1) + 1
        local sideB = recordedDraw(alternateSequence, 2, nil)
        check(sideA.rotations[1] ~= nil and sideB.rotations[1] ~= nil and math.abs(sideA.rotations[1]) > 0
            and near(sideA.rotations[1], -sideB.rotations[1]),
            "早期暴击side由出生visualSequence奇偶决定，同slot换序号旋转方向相反")
        local compatibility = { x = 474, y = 180, text = "免疫", color = { 255, 255, 255 },
            timer = 0.3, duration = 0.7, baseFontSize = 80 }
        for _, slot in ipairs({ 1, 4, 8 }) do
            local legacy = recordedDraw(compatibility, slot, stripBounds)
            check(legacy.world ~= nil and #legacy.texts > 0, "无visualSequence兼容ft仍可绘制slot=" .. slot)
        end
        -- 融合回归：真实Fx→Impact→文字实色与高光；不是GPU像素或字体字墨验收。
        local colorCases = {
            { meta = { channel = "damage", atkType = AD.ATK_SLASH }, rgb = { 246, 228, 182 } },
            { meta = { channel = "damage", atkType = AD.ATK_CRUSH }, rgb = { 214, 170, 112 } },
            { meta = { channel = "damage", atkType = AD.ATK_PIERCE }, rgb = { 150, 236, 196 } },
            { meta = { channel = "damage", atkType = AD.ATK_FIRE }, rgb = { 255, 146, 62 } },
            { meta = { channel = "damage", atkType = AD.ATK_ICE }, rgb = { 118, 214, 255 } },
            { meta = { channel = "damage", atkType = AD.ATK_LIGHTNING }, rgb = { 176, 168, 255 } },
            { meta = { channel = "damage", atkType = AD.ATK_SHADOW }, rgb = { 190, 128, 236 } },
            { meta = { channel = "damage", atkType = AD.ATK_HOLY }, rgb = { 255, 214, 86 } },
            { meta = { channel = "damage", atkType = AD.ATK_FIRE, isCrit = true }, rgb = { 255, 90, 82 } },
            { meta = { channel = "heal", atkType = AD.ATK_HOLY, isCrit = true }, rgb = { 90, 235, 130 } },
            { meta = { channel = "shield", atkType = AD.ATK_FIRE, isCrit = true }, rgb = { 184, 196, 212 } },
            { meta = { channel = "damage", atkType = AD.ATK_FIRE, color = { 31, 73, 119 } }, rgb = { 31, 73, 119 } },
        }
        for index, entry in ipairs(colorCases) do
            local colorState = state()
            local ft = Fx.addCombatNumber(colorState, {}, 321, 474, 180, entry.meta)
            for _, timer in ipairs({ 0.02, 0.30, 0.64 }) do
                ft.timer = timer
                local drawn = recordedDraw(ft, 3, stripBounds)
                local expectedBase = { entry.rgb[1], entry.rgb[2], entry.rgb[3], 255 }
                local expectedHighlight = {}
                for i = 1, 3 do expectedHighlight[i] = math.floor(0.55 * 255 + entry.rgb[i] * 0.45) end
                expectedHighlight[4] = 150
                local correct = #drawn.texts > 0 and #drawn.texts % 6 == 0
                for i, text in ipairs(drawn.texts) do
                    local pass = (i - 1) % 6
                    local expected = pass < 4 and { 18, 15, 16, 255 }
                        or pass == 4 and expectedBase or expectedHighlight
                    correct = correct and sameValue(text.fillColor, expected)
                end
                check(correct, "文字四向描边/宿主实色/顶部高光及退出分带保留 " .. index .. "/" .. timer)
            end
            Fx.resetFloatingTexts(colorState)
        end
        -- 兼容ft只保证可画，不断言不同slot位置稳定；视觉RNG拒绝包括Fx/Impact/Icon全部路径。
        check(rngCalls == 0, "Fx出生/合并/回收与真实Impact/Icon draw均未消费或重置RNG")
        print(TAG .. " STAGGER measurement=deterministic-recorder pixel-ink=NOT_ASSERTED")
        if staggerOnly then
            print(TAG .. " STAGGER_ONLY 后方战斗命中管线未执行")
            return
        end

        -- 命中管线：完整BC/Combo，外围公式返回固定单次结果，不重写结算。
        local stats = { damage = 0, hits = 0, heal = 0, taken = 0, dot = 0, deaths = 0, attackResults = 0 }
        local resultCrit, resultBlocked, comboCount = false, false, 0
        local Formula = {
            calcAttack = function(attrs)
                stats.attackResults = stats.attackResults + 1
                local healing = attrs.atkType == AD.ATK_HOLY
                return { atkType = attrs.atkType, category = healing and "healing" or AD.getAtkCategory(attrs.atkType),
                    resistance = 0, healAmount = 80, isCrit = resultCrit, totalDamage = 80,
                    comboCount = comboCount, hits = { { damage = 80, isCrit = resultCrit, isBlocked = resultBlocked } } }
            end,
            calcAtkHeal = function() return 10 end,
            selectTarget = function() return 1 end,
        }
        local Stats = {
            mountedTeam = function() return 1 end, reset = noop,
            recordDamage = function(_, damage) stats.damage = stats.damage + damage; stats.hits = stats.hits + 1 end,
            recordTaken = function(_, damage) stats.taken = stats.taken + damage end,
            recordDotDamage = function(_, damage) stats.dot = stats.dot + damage end,
            recordHeal = function(_, amount) stats.heal = stats.heal + amount end,
        }
        local Talent = { resetEnemyDeath = noop, onStarShieldBreak = noop, onEnemyKill = noop,
            getLockedTarget = function() return 1 end, onBeforeAttack = noop, onStarDodge = noop,
            modifyDamageForTarget = function(_, damage) return damage end,
            onAfterAttack = noop, onComboAttack = noop, onDamageTaken = noop,
            onEnemyDeath = function() stats.deaths = stats.deaths + 1 end }
        local Artifact = { canHeal = function() return true end, checkShieldBreak = noop,
            onBeforeTakeDamage = function(_, _, damage) return damage end, onDodge = noop,
            consumeCounterAttacks = function() return nil end, onAfterAttack = noop }
        local Relic = { onBeforeAttack = function() return 1 end, getDamageBonus = function() return 0 end,
            onBeforeTakeDamage = function(_, damage) return damage end, onAfterAttack = noop,
            shouldSkipThreat = function() return false end, onAfterHit = function() return false end }
        local Dungeon = { getDamageMultiplier = function() return 1 end, getDamageTakenMultiplier = function() return 1 end,
            consumeDamageImmunity = function() return false end, checkExecute = function() return false end,
            isHealBlocked = function() return false end, onEnemyKill = noop }
        local animations = { LUNGE_DURATION = 0.1, RETURN_DURATION = 0.1, playAttack = noop, setRecoil = noop }
        local layout = {
            posForList = function(_, index) return 300 + index, 180 end,
            hitWeight = function() return 1 end,
        }
        local projectileState = { projectiles = {} }
        local mocks = {
            ["systems.CombatFormula"] = Formula, ["systems.AttributeDef"] = AD,
            ["systems.ThreatManager"] = { onDamageDealt = noop, onHealingDone = noop, getThreat = function() return 1 end },
            ["systems.StatusEffectManager"] = { getDamageTakenMult = function() return 1 end },
            ["systems.TalentManager"] = Talent,
            ["ui.battle.combat.ProjectileSystem"] = { mountedState = function() return projectileState end },
            ["systems.ExtraTalentSystem"] = { absorbBulwarkWard = function(_, damage) return damage end },
            ["systems.BattleDiag"] = { logEnabled = false }, ["core.BattleLayout"] = layout,
            ["systems.RelicConditionHandler"] = Relic, ["systems.ArtifactRuntime"] = Artifact,
            ["systems.MapAffixSystem"] = { getHealReduce = function() return 0 end, shouldSuppressCrit = function() return false end,
                onEnemyDamaged = noop, onAllyHit = noop }, ["ui.dungeon.DungeonBattle"] = Dungeon,
            ["systems.BattleStats"] = Stats, ["systems.GameSFX"] = { play = noop },
            ["ui.battle.combat.BattleCombatFx"] = Fx, ["ui.battle.combat.BattleCombatAnim"] = animations,
            ["systems.ClassGateRuntime"] = { applyDebtTaken = function(_, d) return d end,
                absorbIncoming = function(_, d) return d end, tryDeferDeath = function() return false end },
            ["systems.EquipmentSetRuntime"] = { onIncoming = function(_, d) return d end,
                onBlocked = noop, shouldSkipThreat = function() return false end },
        }
        mocks["ui.battle.combat.BattleCombatCombo"] = compile("ui/battle/combat/BattleCombatCombo.lua", mocks)
        mocks["ui.battle.combat.BattleAttackChain"] = compile("ui/battle/combat/BattleAttackChain.lua", {})
        local Combat, combatEnv = compile("ui/battle/combat/BattleCombat.lua", mocks)
        local function unit(heroId, atkType, hp, maxHp, shield)
            local attrs = { atkType = atkType, final = { [AD.HP] = hp, [AD.MAX_HP] = maxHp, [AD.ENERGY_SHIELD] = shield or 0 },
                energyShield = shield or 0, tempEnergyShield = 0 }
            function attrs:get(key) return self.final[key] or 0 end
            function attrs:takeDamage(damage)
                local absorb = math.min(damage, self.energyShield); self.energyShield = self.energyShield - absorb
                local actual = math.min(self.final[AD.HP], damage - absorb)
                self.final[AD.HP] = self.final[AD.HP] - actual
                return actual
            end
            function attrs:heal(amount)
                local actual = math.min(amount, self.final[AD.MAX_HP] - self.final[AD.HP])
                self.final[AD.HP] = self.final[AD.HP] + actual; return actual
            end
            return { heroId = heroId, instanceId = heroId, name = "fixture", atkType = atkType, attrs = attrs, hp = hp, maxHp = maxHp }
        end
        local attacker, victim = unit(2, AD.ATK_FIRE, 100, 1000), unit(101, AD.ATK_SLASH, 1000, 1000, 30)
        local live, landed, captured = { victim }, {}, {}
        local scene = Combat.newState("fixture")
        Combat.mount(scene)
        Combat.setContext({ getAllies = function() return { attacker } end, getEnemies = function() return live end,
            onAttackHit = function(_, _, _, _, _, _, result, apply)
                captured[#captured + 1] = result; landed[#landed + 1] = apply
            end })
        comboCount = 1
        Combat.performAttack(attacker, live, true)
        check(victim.hp == 1000 and victim.attrs.energyShield == 30 and #Combat.getFloatingTexts() == 0
            and #scene.comboQueue == 0 and #landed == 1, "投射物未命中HP/盾/数字/连击均不提前生效")
        attacker.atkType, attacker.attrs.atkType = AD.ATK_ICE, AD.ATK_ICE
        landed[1]()
        check(victim.hp == 950 and victim.attrs.energyShield == 0 and stats.damage == 80 and stats.hits == 1
            and #scene.comboQueue == 1 and #scene.floatingTexts == 3,
            "命中真实扣50HP+30盾/统计80/排连击一次，数字和攻击回血即显")
        check(scene.combatNumberIndex[victim].damage[AD.ATK_FIRE].amount == 50
            and scene.combatNumberIndex[victim].shield[AD.ATK_FIRE].amount == 30
            and scene.combatNumberIndex[attacker].heal[AD.ATK_HOLY].amount == 10,
            "主攻击实际result.fire快照不被角色落地前变冰覆盖")
        scene.comboQueue = {}
        comboCount = 0
        resultCrit, resultBlocked = true, true
        attacker.atkType, attacker.attrs.atkType = AD.ATK_FIRE, AD.ATK_FIRE
        Combat.performAttack(attacker, live, true)
        landed[2]()
        check(victim.hp == 870 and stats.damage == 160 and stats.hits == 2
            and scene.combatNumberIndex[victim].damage[AD.ATK_FIRE].amount == 130
            and scene.combatNumberIndex[victim].damage[AD.ATK_FIRE].isBlocked,
            "第二次暴击格挡火HP总130，统计仍两次独立160")
        resultCrit, resultBlocked = false, false
        local entry = { attacker = attacker, isAlly = true, targetIsAlly = false, comboHitIndex = 1,
            targetRef = victim, delay = 0, timer = 0 }
        scene.comboQueue = { entry }
        Combat.updateComboQueue(0.01)
        check(#scene.comboQueue == 0 and victim.hp == 870 and #landed == 3, "连击队列保留原命中延迟、不提前扣血")
        landed[3]()
        check(victim.hp == 790 and stats.damage == 240 and stats.hits == 3
            and scene.combatNumberIndex[victim].damage[AD.ATK_FIRE].amount == 210
            and scene.combatNumberIndex[attacker].heal[AD.ATK_HOLY].amount == 30,
            "连击真实80和攻击回血接入同批，统计仍独立第三次")
        Combat.dealDamageToUnit(victim, 20, false, "DOT", nil, attacker, {
            isDot = true, atkType = AD.ATK_FIRE, isCrit = true, floatKind = "burn",
        })
        check(victim.hp == 770 and stats.dot == 20 and stats.damage == 240
            and scene.combatNumberIndex[victim].damage[AD.ATK_FIRE].amount == 230
            and scene.combatNumberIndex[victim].damage[AD.ATK_FIRE].isDot,
            "DOT火加入火数字且recordDotDamage仍20，不变普通统计")
        -- only-atkType/floatKind 也必须透传；捕获延迟后攻击者变属性。
        local talentLand = nil ---@type function?
        scene.ctx.onTalentDealDamage = function(_, _, _, _, _, apply) talentLand = apply end
        Combat.dealTalentDamage(attacker, victim, 11, false, "ice", nil, { atkType = AD.ATK_ICE, floatKind = "ice" })
        attacker.atkType, attacker.attrs.atkType = AD.ATK_SHADOW, AD.ATK_SHADOW
        assert(talentLand)()
        check(scene.combatNumberIndex[victim].damage[AD.ATK_ICE].amount == 11 and victim.hp == 759,
            "只有atkType/floatKind选项也透传，投射物落地不事后读角色")
        scene.ctx.onTalentDealDamage = nil
        Combat.dealTalentDamage(attacker, victim, 12, false, "holy", nil, { atkType = AD.ATK_HOLY, statCategory = "magical" })
        check(victim.hp == 747 and scene.combatNumberIndex[victim].damage[AD.ATK_HOLY].amount == 12,
            "holy额伤真实扣HP且damage通道，不改为heal")
        -- 正式治疗落地走result.atkType；不改变公式/统计/目标选择。
        attacker.atkType, attacker.attrs.atkType = AD.ATK_HOLY, AD.ATK_HOLY
        Combat.performAttack(attacker, live, true)
        landed[4]()
        check(attacker.hp == 210 and stats.heal == 80
            and scene.combatNumberIndex[attacker].heal[AD.ATK_HOLY].amount == 110,
            "治疗80与攻击回血30视觉可叠，治疗统计仅原正式80")
        local deathBefore = stats.deaths
        Combat.dealDamageToUnit(victim, 2000, false, "kill", nil, attacker, { atkType = AD.ATK_FIRE })
        Combat.dealDamageToUnit(victim, 2000, false, "repeat", nil, attacker, { atkType = AD.ATK_FIRE })
        check(victim.hp == 0 and stats.deaths == deathBefore + 1, "重复伤害对死目标不重复死亡/统计回调")
        Combat.clearFloatingTexts()
        check(#scene.floatingTexts == 0 and indexEntries(scene) == 0 and poolClean(scene), "公开宿主clear回收数字/索引/目标引用")
        -- fallback原随机简化伤害保留；仅局部fixture允许其原两次RNG。
        local simple = { name = "simple", hp = 100, maxHp = 100, monsterId = 99 }
        live = { simple }
        attacker.attrs = nil
        attacker.atkType = AD.ATK_PIERCE
        combatEnv.math.random = function(n) return n and 5 or 0.9 end
        Combat.performAttack(attacker, live, true)
        check(simple.hp == 80 and scene.combatNumberIndex[simple].damage[AD.ATK_PIERCE].amount == 20,
            "fallback20真实原伤害与穿刺数字接入，未改简化公式")
        Combat.reset()
        check(#scene.floatingTexts == 0 and indexEntries(scene) == 0 and poolClean(scene), "正式reset清理结构化索引和pool")
        -- 缓冲旧6参形态保持：opts原样仍占source，不修wrapper/归因，仅增加显示属性。
        local loader = unit(24, AD.ATK_SHADOW, 100, 1000)
        local bufferTarget = unit(102, AD.ATK_SLASH, 10, 100)
        local loaderState = { heroId = 24, loadingBar = 100, loadingIdle = 0 }
        local fixedCalls, wrapperCalls, bufferSource = 0, 0, {} ---@type integer, integer, table
        local TalentAwakening = compile("config/AwakeningConfig.lua", {})
        local FourNew = compile("systems/talents/TalentFourNew.lua", {
            ["systems.AttributeDef"] = AD,
            ["systems.ThreatManager"] = { addThreat = noop },
            ["systems.ExtraTalentSystem"] = {},
            ["config.AwakeningConfig"] = TalentAwakening,
        }).bind({
            hasAwakenStage = function() return false end,
            getState = function(u) return u == loader and loaderState or nil end,
            talentLog = noop,
            getTAL_BCS = function() return {} end,
            calcTalentFixedDamage = function(u, tgt, amount, opts)
                fixedCalls = fixedCalls + 1
                check(u == loader and tgt == bufferTarget and amount == 100 and opts.atkType == AD.ATK_CRUSH,
                    "真实FourNew.update缓冲仍用原100和粉碎公式参数")
                return 40
            end,
        })
        Combat.setContext({ getAllies = function() return { loader } end,
            getEnemies = function() return { bufferTarget } end })
        local takenBefore, damageBefore, hitsBefore = stats.taken, stats.damage, stats.hits
        FourNew.update(0.01, { loader }, { bufferTarget }, {
            dealDamage = function(tgt, damage, isTargetAlly, prefix, color, sourceArg)
                wrapperCalls = wrapperCalls + 1
                bufferSource = sourceArg
                check(tgt == bufferTarget and damage == 40 and isTargetAlly == true and prefix == "缓冲 "
                    and color[1] == 180 and sourceArg.instantDamage and sourceArg.statCategory == "physical",
                    "旧6参wrapper保留目标/40伤害/原true阵营/color/opts-as-source")
                return Combat.dealDamageToUnit(tgt, damage, isTargetAlly, prefix, color, sourceArg)
            end,
        })
        check(fixedCalls == 1 and wrapperCalls == 1 and loaderState.loadingBar == 0 and loaderState.loadingIdle == 0,
            "真实FourNew.update缓冲仅消费一次原队列")
        check(bufferTarget.hp == 0 and stats.taken == takenBefore + 10 and stats.damage == damageBefore
            and stats.hits == hitsBefore and bufferTarget._killedBy == bufferSource and bufferSource ~= loader,
            "缓冲伤害/recordTaken/_killedBy保持旧source语义，不更正历史归因")
        check(scene.combatNumberIndex[bufferTarget].damage[AD.ATK_CRUSH].amount == 10
            and bufferSource.atkType == AD.ATK_CRUSH,
            "缓冲仅新增source.atkType显示CRUSH真实10HP，不修statMeta/wrapper")
        Combat.clearFloatingTexts()
        local ping = unit(25, AD.ATK_PIERCE, 100, 1000)
        local pingTarget = unit(103, AD.ATK_SLASH, 100, 100)
        local pingState = { heroId = 25, pingQueue = {
            { target = pingTarget, dmg = 30, t = 0.2, isAlly = true, hpPctAtFire = 1 },
        } }
        local PingNew = compile("systems/talents/TalentFourNew.lua", {
            ["systems.AttributeDef"] = AD,
            ["systems.ThreatManager"] = { addThreat = noop },
            ["systems.ExtraTalentSystem"] = {},
            ["config.AwakeningConfig"] = TalentAwakening,
        }).bind({
            hasAwakenStage = function() return false end,
            getState = function(u) return u == ping and pingState or nil end,
            talentLog = noop, getTAL_BCS = function() return {} end,
        })
        Combat.setContext({ getAllies = function() return { ping } end,
            getEnemies = function() return { pingTarget } end })
        local pingCalls = 0
        local pingContext = { dealDamage = function(tgt, amount, isTargetAlly, prefix, color, sourceArg)
            pingCalls = pingCalls + 1
            check(tgt == pingTarget and amount == 30 and not isTargetAlly and prefix == "高ping "
                and sourceArg.threatScale == 0.10 and sourceArg.atkType == AD.ATK_PIERCE,
                "高ping保留旧六参来源与原30伤害，仅附穿刺属性")
            return Combat.dealDamageToUnit(tgt, amount, isTargetAlly, prefix, color, sourceArg)
        end }
        PingNew.update(0.1, { ping }, { pingTarget }, pingContext)
        check(pingCalls == 0 and pingTarget.hp == 100 and #pingState.pingQueue == 1,
            "高ping延迟到期前不生成数字、不提前扣血")
        PingNew.update(0.11, { ping }, { pingTarget }, pingContext)
        check(pingCalls == 1 and #pingState.pingQueue == 0 and pingTarget.hp == 70
            and scene.combatNumberIndex[pingTarget].damage[AD.ATK_PIERCE].amount == 30,
            "高ping到期按真实30HP显示穿刺数字，不回退斩击")
        Combat.clearFloatingTexts()
        for _, path in ipairs({ "ui/battle/combat/BattleCombatFx.lua", "ui/battle/combat/BattleCombat.lua",
            "ui/battle/combat/BattleCombatCombo.lua", "ui/battle/scene/DamageTypeIcon.lua" }) do
            check(sources[path] ~= nil, "完整真实模块执行 " .. path)
        end
    end, debug.traceback)
    if not ok then failures = failures + 1; print(TAG .. " HARNESS_ERROR " .. tostring(err)) end
    print(string.format("%s RESULT assertions=%d failures=%d %s", TAG, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    if failures > 0 then error(TAG .. " FAILED assertions=" .. assertions .. " failures=" .. failures) end
    engine:Exit()
end
