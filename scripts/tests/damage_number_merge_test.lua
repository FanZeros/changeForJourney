-- 即时伤害数字专项：隔离执行完整生产模块；不加载玩家档，不改全局RNG。
-- GPU/战斗外围有限spy，真实Fx/Combo/BattleCombat/Draw/Icon/NumberUtil均完整load。
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
---@type table
local reviewDraw = {}

local function startReview()
    -- 复用本测试入口的真实像素矩阵；业务依赖隔离，只执行原图标/飘字模块。
    local function module(path, mocks)
        local file = assert(cache:GetFile(path))
        local lines = {}; while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        file:Dispose()
        local env = setmetatable({}, { __index = _G })
        env.require = function(name) return assert(mocks[name], name) end
        env.math = setmetatable({ random = function() error("REVIEW_RNG") end }, { __index = math })
        return assert(load(table.concat(lines, "\n"), "@damage-review/" .. path, "t", env))()
    end
    local AD = require("systems.AttributeDef")
    local Number = module("core/NumberUtil.lua", {})
    local Icon = module("ui/battle/scene/DamageTypeIcon.lua", { ["systems.AttributeDef"] = AD })
    local Fx = module("ui/battle/combat/BattleCombatFx.lua", { ["core.NumberUtil"] = Number,
        ["ui.battle.scene.DamageTypeIcon"] = Icon,
        ["ui.hud.popup.SettingsPanel"] = { isEffectsEnabled = function() return true end } })
    local Util = module("core/DrawUtil.lua", { ["core.BattleLayout"] = {} })
    reviewDraw = module("ui/battle/scene/BattleDraw.lua", {
        ["systems.StatusEffectManager"] = {}, ["systems.TalentManager"] = {}, ["core.NumberUtil"] = Number,
        ["core.BattleLayout"] = { CARD_W = 100, CARD_H = 100 }, ["core.DrawUtil"] = Util,
        ["systems.ExtraTalentSystem"] = {}, ["config.HeroAssetUtil"] = {}, ["ui.battle.scene.DamageTypeIcon"] = Icon,
    })
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
    reviewVg = nvgCreate(1)
    assert(reviewVg)
    assert(nvgCreateFont(reviewVg, "sans", "Fonts/MiSans-Regular.ttf") >= 0)
    SubscribeToEvent(reviewVg, "NanoVGRender", "HandleDamageReviewRender")
    print(TAG .. " REVIEW phase=" .. reviewPhase .. " frame-controlled=true player-save=false gameplay-rng=false")
end

function HandleDamageReviewRender()
    local width, height = graphics:GetWidth(), graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logicalW, logicalH = width / dpr, height / dpr
    local scale = math.min(logicalW / 1640, logicalH / 1100)
    nvgBeginFrame(reviewVg, logicalW, logicalH, dpr)
    nvgScale(reviewVg, scale, scale)
    nvgBeginPath(reviewVg); nvgRect(reviewVg, 0, 0, logicalW / scale, logicalH / scale)
    nvgFillColor(reviewVg, nvgRGBA(17, 20, 27, 255)); nvgFill(reviewVg)
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
    for _, arg in ipairs(GetArguments()) do
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
        local function compile(path, mocks, fields)
            local env = setmetatable(fields or {}, { __index = _G })
            env._G = env
            env.require = function(name)
                assert(mocks[name] ~= nil, "undeclared require " .. name)
                return mocks[name]
            end
            env.math = setmetatable({ random = function() error("VISUAL_CONSUMED_GAMEPLAY_RNG") end,
                randomseed = function() error("VISUAL_RESET_GAMEPLAY_RNG") end }, { __index = math })
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
        local Icon, iconEnv = compile("ui/battle/scene/DamageTypeIcon.lua", { ["systems.AttributeDef"] = AD })
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
            and near(first.timer, 0.1) and first.duration == 0.7 and first.pulseTimer > 0,
            "同目标火100+250原数相加350，寿命不续，轻微pulse")
        Fx.addCombatNumber(bcs, target, 50, 300, 180, {
            channel = "damage", atkType = AD.ATK_FIRE, isCrit = true, isBlocked = true, isDot = true,
        })
        check(first.amount == 400 and first.isCrit and first.isBlocked and first.isDot
            and first.fontSize == 160 and #bcs.floatingTexts == 1,
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

        -- GPU记录器：真实图标轮廓与真实DrawUtil描边，矩阵/alpha栈隔离。
        local rec = { calls = {}, matrix = { 1, 0, 0, 1, 0, 0 }, alpha = 0.63,
            font = 13, stack = {}, color = { 1, 2, 3, 255 } }
        local gpu = {}
        local function emit(name, ...)
            local c = { name = name, args = { ... }, alpha = rec.alpha, color = rec.color }
            rec.calls[#rec.calls + 1] = c
            return c
        end
        local function point(x, y)
            local m = rec.matrix
            return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
        end
        gpu.nvgSave = function()
            rec.stack[#rec.stack + 1] = { matrix = rec.matrix, alpha = rec.alpha, font = rec.font, color = rec.color }
        end
        gpu.nvgRestore = function()
            local s = assert(table.remove(rec.stack))
            rec.matrix, rec.alpha, rec.font, rec.color = s.matrix, s.alpha, s.font, s.color
        end
        gpu.nvgTranslate = function(_, x, y)
            local m = rec.matrix
            rec.matrix = { m[1], m[2], m[3], m[4], m[5] + m[1] * x + m[3] * y, m[6] + m[2] * x + m[4] * y }
        end
        gpu.nvgScale = function(_, x, y)
            local m = rec.matrix
            rec.matrix = { m[1] * x, m[2] * x, m[3] * y, m[4] * y, m[5], m[6] }
        end
        gpu.nvgGlobalAlpha = function(_, a) rec.alpha = a; emit("alpha", a) end
        gpu.nvgFontSize = function(_, s) rec.font = s end
        gpu.nvgFillColor = function(_, color) rec.color = color end
        gpu.nvgRGBA = function(...) return { ... } end
        gpu.nvgStrokeColor = function(_, color) emit("strokeColor", color) end
        gpu.nvgLinearGradient = function(_, ...) return emit("gradient", ...) end
        gpu.nvgTextBounds = function(_, _, _, text) return #text * rec.font * 0.6 end
        gpu.nvgText = function(_, x, y, text)
            local c = emit("text", text); c.x, c.y = point(x, y); c.size = rec.font * rec.matrix[1]
        end
        for _, name in ipairs({ "nvgMoveTo", "nvgLineTo", "nvgQuadTo", "nvgCircle", "nvgRect", "nvgRoundedRect" }) do
            gpu[name] = function(_, ...)
                local c = emit(name, ...); c.x, c.y = point(c.args[1], c.args[2])
            end
        end
        for _, name in ipairs({ "nvgBeginPath", "nvgClosePath", "nvgFill", "nvgStroke", "nvgStrokeWidth",
            "nvgFontFace", "nvgTextAlign", "nvgFillPaint" }) do gpu[name] = function(_, ...) emit(name, ...) end end
        for name, fn in pairs(gpu) do iconEnv[name] = fn end
        local Util, utilEnv = compile("core/DrawUtil.lua", { ["core.BattleLayout"] = {} })
        for name, fn in pairs(gpu) do utilEnv[name] = fn end
        local Draw, drawEnv = compile("ui/battle/scene/BattleDraw.lua", {
            ["systems.StatusEffectManager"] = {}, ["systems.TalentManager"] = {}, ["core.NumberUtil"] = Number,
            ["core.BattleLayout"] = { CARD_W = 100, CARD_H = 100 }, ["core.DrawUtil"] = Util,
            ["systems.ExtraTalentSystem"] = {}, ["config.HeroAssetUtil"] = {}, ["ui.battle.scene.DamageTypeIcon"] = Icon,
        })
        for name, fn in pairs(gpu) do drawEnv[name] = fn end
        local function named(name)
            local found = {}; for _, c in ipairs(rec.calls) do if c.name == name then found[#found + 1] = c end end
            return found
        end
        local seen = {}
        for atkType = 1, 8 do
            rec.calls = {}
            Icon.draw(nil, { channel = "damage", atkType = atkType }, 100, 200, 72)
            local signature = {}
            for _, c in ipairs(rec.calls) do
                if c.name == "nvgMoveTo" or c.name == "nvgLineTo" or c.name == "nvgQuadTo" or c.name == "nvgCircle" then
                    signature[#signature + 1] = c.name .. ":" .. table.concat(c.args, ",")
                end
            end
            local sig = table.concat(signature, ";")
            check(sig ~= "" and not seen[sig] and #named("gradient") > 0 and #named("nvgStroke") > 0,
                "AD属性" .. atkType .. "有独立轮廓/暗铁边/骨白属性高光")
            seen[sig] = true
            check(rec.alpha == 0.63 and #rec.stack == 0 and rec.matrix[1] == 1, "属性绘制恢复父alpha/缩放 " .. atkType)
        end
        for _, kind in ipairs({ "phys", "magic", "burn", "block", "shield", "heal", "crit", "critblockmagic" }) do
            check(Icon.resolve(nil, kind) ~= nil, "旧kind可解析 " .. kind)
        end
        check(Icon.resolve(nil, "未知") == nil and Icon.resolve(nil, "") == nil, "未知/空kind不留空图标占位")
        local resolved = Icon.resolve({ channel = "damage", atkType = AD.ATK_HOLY }, "heal")
        check(resolved.channel == "damage" and resolved.atkType == AD.ATK_HOLY, "显式damage不会被holy/旧heal语义覆盖")
        Fx.resetFloatingTexts(bcs)
        local drawNumber = Fx.addCombatNumber(bcs, target, 123, 300, 180, fire)
        Draw.setContext({ combat = { getFloatingTexts = function() return bcs.floatingTexts end } })
        rec.calls = {}; Draw.drawFloatingTexts(nil)
        local textCalls = named("text")
        check(#textCalls == 9 and textCalls[9].args[1] == "123" and textCalls[9].alpha == 1
            and textCalls[9].color[1] == 255 and near(drawNumber.timer, 0), "初生真实Draw即显9道字/描边，无alpha0帧")
        local initialSize = textCalls[9].size
        Fx.addCombatNumber(bcs, target, 200, 300, 180, fire)
        rec.calls = {}; Draw.drawFloatingTexts(nil)
        check(named("text")[9].size > initialSize and named("text")[9].args[1] == "323",
            "叠加立即改总值并真实绘制轻微放大pulse")
        drawNumber.timer = drawNumber.duration * 0.9
        drawNumber.pulseTimer = 0
        rec.calls = {}; Draw.drawFloatingTexts(nil)
        local fade = named("text")[9].alpha
        local once = #named("alpha") == 1 and near(fade, 102 / 255)
        for _, c in ipairs(named("strokeColor")) do once = once and c.args[1][4] == 255 and near(c.alpha, fade) end
        for _, c in ipairs(named("gradient")) do once = once and c.args[5][4] == 255 and c.args[6][4] == 255 end
        check(once and rec.alpha == 0.63 and #rec.stack == 0, "末段alpha仅外层一次，图标不双乘且完整恢复父状态")
        rec.calls = {}
        Icon.draw(nil, { channel = "damage", atkType = AD.ATK_FIRE, isCrit = true, isBlocked = true, isDot = true }, 0, 0, 72)
        local corners = { crit = false, block = false, dot = false }
        for _, c in ipairs(named("nvgMoveTo")) do
            if near(c.x, 25) and near(c.y, -24 - 27 * 0.34) then corners.crit = true end
            if near(c.x, 25) and near(c.y, 24 - 28 * 0.34) then corners.block = true end
        end
        for _, c in ipairs(named("nvgCircle")) do if near(c.x, -24) and near(c.y, 24) then corners.dot = true end end
        check(corners.crit and corners.block and corners.dot and #rec.stack == 0,
            "暴击右上/格挡右下/DOT左下三个角标均存在且不盖属性主体")

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
        local mocks = {
            ["systems.CombatFormula"] = Formula, ["systems.AttributeDef"] = AD,
            ["systems.ThreatManager"] = { onDamageDealt = noop, onHealingDone = noop, getThreat = function() return 1 end },
            ["systems.StatusEffectManager"] = { getDamageTakenMult = function() return 1 end },
            ["systems.TalentManager"] = Talent, ["ui.battle.combat.ProjectileSystem"] = {},
            ["systems.BattleDiag"] = { logEnabled = false }, ["core.BattleLayout"] = layout,
            ["systems.RelicConditionHandler"] = Relic, ["systems.ArtifactRuntime"] = Artifact,
            ["systems.MapAffixSystem"] = { getHealReduce = function() return 0 end, shouldSuppressCrit = function() return false end,
                onEnemyDamaged = noop, onAllyHit = noop }, ["ui.dungeon.DungeonBattle"] = Dungeon,
            ["systems.BattleStats"] = Stats, ["systems.GameSFX"] = { play = noop },
            ["ui.battle.combat.BattleCombatFx"] = Fx, ["ui.battle.combat.BattleCombatAnim"] = animations,
            ["systems.ClassGateRuntime"] = { applyDebtTaken = function(_, d) return d end,
                absorbIncoming = function(_, d) return d end, tryDeferDeath = function() return false end },
            ["systems.EquipmentSetRuntime"] = { onIncoming = function(_, d) return d end, onBlocked = noop },
        }
        mocks["ui.battle.combat.BattleCombatCombo"] = compile("ui/battle/combat/BattleCombatCombo.lua", mocks)
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
        local FourNew = compile("systems/talents/TalentFourNew.lua", {
            ["systems.AttributeDef"] = AD,
            ["systems.ThreatManager"] = { addThreat = noop },
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
            "ui/battle/combat/BattleCombatCombo.lua", "ui/battle/scene/BattleDraw.lua", "ui/battle/scene/DamageTypeIcon.lua" }) do
            check(sources[path] ~= nil, "完整真实模块执行 " .. path)
        end
    end, debug.traceback)
    if not ok then failures = failures + 1; print(TAG .. " HARNESS_ERROR " .. tostring(err)) end
    print(string.format("%s RESULT assertions=%d failures=%d %s", TAG, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    if failures > 0 then error(TAG .. " FAILED assertions=" .. assertions .. " failures=" .. failures) end
    engine:Exit()
end
