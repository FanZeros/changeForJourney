-- 装备暴率软预算与星图专项；沿用 threat_scale_shield_test 的独立 Runtime 骨架。
-- 不加载 main、不读玩家档、不联网；生产模块在无引擎/存档能力的白名单环境执行。
-- 只测数据/真实属性链，不调用星图绘图；由主代理统一隔离运行，不 build。
-- 判定以 failure_count / RESULT 为准，engine:Exit() 不代表断言通过。
local PREFIX = "[critical_rate_budget] "
local checks, failures = 0, {}
local function check(ok, label)
    checks = checks + 1
    if not ok then failures[#failures + 1] = label; print(PREFIX .. "[FAIL] " .. label) end
end
local function near(a, b)
    return type(a) == "number" and type(b) == "number" and a == a and b == b
        and a > -math.huge and a < math.huge
        and math.abs(a - b) <= math.max(1, math.abs(b)) * 1e-9
end
local function eq(a, b, label)
    check(near(a, b), label .. " actual=" .. tostring(a) .. " expected=" .. tostring(b))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return type(a) == "number" and near(a, b) or a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local sources = {}
local function source(path)
    if sources[path] then return sources[path] end
    local file = assert(cache:GetFile(path), "缺少fixture源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = table.concat(lines, "\n")
    sources[path] = text
    return text
end
-- 隔离runner必须包含这些真实源码；没有业务替身/星图数据替身。
local ALLOWED = {
    ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true,
    ["systems.EquipmentSystem"] = true, ["systems.EquipmentSecondaryStats"] = true,
    ["systems.EquipmentStatGrowth"] = true,
    ["systems.CombatFormula"] = true, ["systems.StatusEffectManager"] = true,
    ["systems.BattleDiag"] = true, ["core.BattleLayout"] = true,
    ["systems.talents.TalentAfterAttack"] = true, ["systems.talents.TalentEnemyDeath"] = true,
    ["systems.talents.TalentComboAttack"] = true, ["systems.talents.TalentUpdate"] = true,
    ["systems.TalentEffect"] = true, ["config.ClassConfig"] = true,
    ["config.EquipmentConfig"] = true, ["config.AffixConfig"] = true,
    ["config.BlacksmithConfig"] = true, ["shared.talent.TalentNodeDefs"] = true,
    ["ui.church.talent.TalentStarMap"] = true, ["ui.widget.TalentGlyph"] = true,
    ["ui.widget.TalentGlyphContours"] = true, ["ui.widget.TalentGlyphExtra"] = true,
}
local function fixture()
    local loaded, rng = {}, { state = 1, calls = 0 }
    local privateMath = copy(math)
    -- 私有可重放RNG，既不污染全局种子，也不依赖宿主Lua版本的random算法。
    privateMath.randomseed = function(seed) rng.state, rng.calls = seed, 0 end
    privateMath.random = function(lo, hi)
        rng.state = (rng.state * 48271) % 2147483647
        rng.calls = rng.calls + 1
        local value = rng.state / 2147483647
        if lo == nil then return value end
        if hi == nil then hi, lo = lo, 1 end
        return lo + math.floor(value * (hi - lo + 1))
    end
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
        math = privateMath, table = table, string = string, print = print,
        os = { clock = os.clock },
    }
    env._G = env
    local function import(name)
        if loaded[name] then return loaded[name] end
        -- 叶子边界只屏蔽英雄专属成长与遗物；本专项heroId=0，任何意外调用均报错。
        if name == "systems.ExtraTalentSystem" then
            local leaf = { onAfterAttack = function() end, onEnemyDeath = function() end, update = function() end }
            loaded[name] = leaf
            return leaf
        end
        if name == "systems.RelicConditionHandler" or name == "config.AwakeningConfig" or name == "systems.ThreatManager" then
            local leaf = setmetatable({}, { __index = function(_, key) error("意外调用非星图边界 " .. name .. "/" .. key) end })
            loaded[name] = leaf
            return leaf
        end
        assert(ALLOWED[name], "禁止加载非白名单模块 " .. tostring(name))
        local path = name:gsub("%.", "/") .. ".lua"
        -- 引擎LSP的全局load签名不含标准Lua的字符串入口，局部收窄而非改生产声明。
        local compile = load --[[@as fun(text: string, name: string, mode: string, env: table): function?, string?]]
        local chunk, why = compile(source(path), "@crit-private/" .. path, "t", env)
        if not chunk then error(tostring(why)) end
        local value = chunk()
        loaded[name] = value
        return value
    end
    env.require = import
    return {
        Eq = import("systems.EquipmentSystem"), Secondary = import("systems.EquipmentSecondaryStats"),
        EC = import("config.EquipmentConfig"), AD = import("systems.AttributeDef"),
        UA = import("systems.UnitAttributes"), TE = import("systems.TalentEffect"),
        TSM = import("ui.church.talent.TalentStarMap"), Defs = import("shared.talent.TalentNodeDefs"),
        math = privateMath, rng = rng, import = import,
    }
end
local function noRNG(f, fn, label)
    local before = f.rng.calls
    fn()
    check(f.rng.calls == before, label .. "不消费RNG")
end
-- 独立常数oracle，绝不调用scaleCritRate或读取EC曲线来产生期望。
local BASE = { critRate = 8, physCritRate = 10, magCritRate = 10, healCritRate = 10 }
local AFFIX = { critRate = 4, physCritRate = 5, magCritRate = 5, healCritRate = 5 }
local KEYS = { "critRate", "physCritRate", "magCritRate", "healCritRate" }
local function curve(value, budget)
    if not budget or value <= 0 then return value end
    return budget / (1 + budget / value)
end
local function sum(entries, key)
    local total = 0
    for _, row in ipairs(entries) do if row.key == key then total = total + (row.flat or 0) end end
    return total
end
-- 固定数值补偿独立oracle：三档常数写死，不读取EC或调用生产倍率函数。
local function flatGrowth(key, level)
    local anchors = { maxHp = { 1.8, 2.8 }, hpRegen = { 1.8, 2.8 }, atkHeal = { 1.8, 2.8 },
        physAtk = { 1.6, 2.4 }, magAtk = { 1.6, 2.4 }, energyShield = { 2, 3.5 } }
    local pair = anchors[key]
    if not pair or level <= 50 then return 1 end
    if level < 100 then return 1 + (pair[1] - 1) * (level - 50) / 50 end
    if level < 200 then return pair[1] + (pair[2] - pair[1]) * (level - 100) / 100 end
    return pair[2]
end
local function baseExpected(item, i, boost, double)
    local row, count = item.baseStats[i], #item.baseStats - 1
    local steps = i == 1 and 0 or math.floor(((item.ascendLevel or 0) + count - i + 1) / count)
    local raw = row[2] * (i == 1 and (1 + boost) or (1 + steps * 0.05))
        * flatGrowth(row[1], item.level)
    local typeBudget = (row[1] == "maxDmgBonus" or row[1] == "minDmgBonus") and 30 * double or nil
    local typed = curve(raw, typeBudget)
    return curve(typed, BASE[row[1]] and BASE[row[1]] * double)
end

local function testCurve(f)
    check(same(f.EC.CRIT_RATE_CURVE, { base = BASE, affix = AFFIX }), "曲线配置恰为四key/两来源常数")
    local forms = {
        { nil, 1 }, { {}, 1 }, { { slot = "weapon", grip = "onehand" }, 1 },
        { { slot = "weapon", grip = "twohand" }, 2 },
        { { slot = "offhand", grip = "twohand" }, 1 },
        { { slot = "accessory", grip = "twohand" }, 1 },
        { { templateId = "W24" }, 2 }, { { templateId = "W18" }, 1 },
        { { templateId = "W24", slot = "accessory" }, 1 },
        { { templateId = "W24", grip = "onehand" }, 1 },
        { { templateId = "W24", slot = "weapon" }, 2 },
        { { templateId = "W24", grip = "twohand" }, 2 },
    }
    noRNG(f, function()
        for _, src in ipairs({ "base", "affix" }) do
            for _, key in ipairs(KEYS) do
                for n, form in ipairs(forms) do
                    local budget = (src == "base" and BASE[key] or AFFIX[key]) * form[2]
                    local previous = 0
                    for _, value in ipairs({ -17, 0, 0.001, 0.25, 100, 1e300 }) do
                        local label = src .. "/" .. key .. "/form" .. n .. "/" .. value
                        local actual = f.Eq.scaleCritRate(form[1], key, value, src)
                        eq(actual, curve(value, budget), label)
                        if value > 0 then
                            check(actual > previous and actual <= budget and actual <= value,
                                label .. "单调/正值/有界且极大输入有限")
                            previous = actual
                        else check(actual == value, label .. "非正数原样返回") end
                    end
                end
            end
        end
        eq(f.Eq.scaleCritRate({}, "critRate", 100, "unknown"), 100, "未知来源不缩放")
    end, "直接曲线")
end

local function testEffectiveOrder(f)
    for _, key in ipairs(KEYS) do
        for _, double in ipairs({ 1, 2 }) do
            ---@type table
            local item = { slot = "weapon", grip = double == 2 and "twohand" or "onehand",
                ascendLevel = 30, affixMult = 2.5,
                baseStats = { { key, 100 }, { key, 50 }, { "atkSpeed", 9 } } }
            local snapshot = copy(item)
            for _, value in ipairs({ -17, 0, 0.001, 100, 1e300 }) do
                item.baseStats[1][2], item.baseStats[2][2] = value, value
                eq(f.Eq.effectiveBaseStatValue(item, 1), curve(value * 2.5, BASE[key] * double), key .. "主升阶后一次")
                eq(f.Eq.effectiveBaseStatValue(item, 2), curve(value * 1.75, BASE[key] * double), key .. "副轮转15次后一次")
                eq(f.Eq.effectiveBaseStatValue(item, 1, 3), curve(value * 4, BASE[key] * double), key .. "显式主倍率优先")
                eq(f.Eq.effectiveBaseStatValue(item, 2, 99, 100), curve(value * 3.5, BASE[key] * double), key .. "预览副不吃主倍率")
                local affix = { key = key, value = value, ascBonus = 3 }
                eq(f.Eq.effectiveAffixValue(item, affix), curve(value * 2.5 + 3, AFFIX[key] * double), key .. "raw乘栏位再加固定量后一次")
                check(affix.value == value and affix.ascBonus == 3, key .. "词缀查询不写回")
            end
            item.baseStats[1][2], item.baseStats[2][2] = 100, 50
            check(same(item, snapshot), key .. "原始实例完全不变")
            local entries = f.Eq.computeModifierEntries(item, 1.5)
            eq(entries[1].flat, curve(250, BASE[key] * double), key .. "modifier主出口不二次压缩")
            eq(entries[2].flat, curve(87.5, BASE[key] * double), key .. "modifier副出口不二次压缩")
            eq(f.Eq.effectiveBaseStatValue(item, 99), 0, "缺行返回0")
        end
    end
    eq(f.Eq.effectiveAffixValue({}, nil), 0, "缺词缀返回0")
end

local function testNonRates(f)
    local keys = { "str", "agi", "int", "vit", "luk", "spi", "critDmg", "physCritDmg",
        "magCritDmg", "healCritDmg", "threat", "atkSpeed", "physAtk", "magAtk", "armor",
        "healBonus", "comboRate", "physPen", "magPen", "unknown" }
    for _, key in ipairs(keys) do
        for _, value in ipairs({ -3, 0, 0.25, 100, 1e300 }) do
            local item = { slot = "weapon", grip = "twohand", ascendLevel = 30,
                affixMult = 2, baseStats = { { key, value }, { key, value } } }
            for _, src in ipairs({ "base", "affix" }) do
                check(f.Eq.scaleCritRate(item, key, value, src) == value, key .. "非暴率helper恒等")
            end
            eq(f.Eq.effectiveBaseStatValue(item, 1), value * 2.5, key .. "主属性旧升阶公式")
            eq(f.Eq.effectiveBaseStatValue(item, 2), value * 2.5, key .. "单副30次旧公式")
            eq(f.Eq.effectiveAffixValue(item, { key = key, value = value, ascBonus = 7 }), value * 2 + 7, key .. "词缀旧公式")
        end
    end
    local shield = f.Eq.generate("O7", 100, 5, { legacySecondary = true })
    shield.ascendLevel = 100
    eq(f.Eq.effectiveBaseStatValue(shield, 4, 999), 50, "固有怨引仍50不升阶")
    local attrs = f.UA.create({ luk = 7 })
    eq(attrs:get("critRate"), 2.1, "命数7仍线性派生2.1暴率")
    eq(attrs:get("critDmg"), 210.5, "命数7仍派生10.5暴伤")
    attrs:addModifier("hero_overflow", { { key = "critRate", flat = 170 } })
    eq(attrs:getUncapped("critRate"), 172.1, "非装备英雄/天赋暴率不被统一压缩或封顶")
end

local function testMatrixAndPersistence(f)
    local strength = { [1] = 1, [5] = 1.4, [6] = 1.5 }
    local matrixCount = 0
    for _, id in ipairs({ "W18", "W24", "W72", "C15" }) do
        for _, level in ipairs({ 1, 50, 100, 200 }) do
            for _, quality in ipairs({ 1, 5, 6 }) do
                for _, legacy in ipairs({ false, true }) do
                    local item = f.Eq.generate(id, level, quality, { legacySecondary = legacy })
                    local raw, roll = copy(item.baseStats), copy(item.secondaryRoll)
                    local double = id == "W24" and 2 or 1
                    local label = id .. "/lv" .. level .. "/q" .. quality .. (legacy and "/旧" or "/新")
                    for _, ascend in ipairs({ 0, 30, 100 }) do
                        matrixCount = matrixCount + 1
                        item.ascendLevel = ascend
                        noRNG(f, function()
                            local entries = f.Eq.computeModifierEntries(item, ascend * 0.05)
                            for i in ipairs(raw) do
                                local expected = baseExpected(item, i, ascend * 0.05, double)
                                eq(f.Eq.effectiveBaseStatValue(item, i), expected, label .. "独立升阶oracle")
                                eq(entries[i].flat, expected, label .. "真实modifier")
                            end
                            check(same(item.baseStats, raw) and same(item.secondaryRoll, roll), label .. "消费不改raw/roll")
                            local lean = f.Eq.dehydrate(item)
                            check(lean.baseStats == nil and same(lean.secondaryRoll, roll), label .. "存档无曲线迁移字段")
                            local restored = f.Eq.hydrate(cjson.decode(cjson.encode(lean)))
                            check(same(restored.baseStats, raw) and same(restored.secondaryRoll, roll), label .. "JSON原值/顺序精确不变")
                            for i in ipairs(raw) do
                                eq(f.Eq.effectiveBaseStatValue(restored, i), baseExpected(item, i, ascend * 0.05, double), label .. "JSON仍只缩一次")
                            end
                            local stable = copy(restored)
                            f.Eq.hydrate(restored); f.Eq.computeModifierEntries(restored, ascend * 0.05)
                            check(same(restored, stable), label .. "重复水合/消费幂等")
                        end, label)
                    end
                    -- 主值依旧是模板×等级×品质，不在raw生成端缩放。
                    eq(raw[1][2], f.EC.ITEMS[id].stats[1][2] * (1 + (level - 1) * 0.05) * strength[quality], label .. "主raw不变")
                    check(legacy and item.secondaryRoll == nil or not legacy and item.secondaryRoll.version == 1, label .. "新旧版本不迁移")
                end
            end
        end
    end
    check(matrixCount == 288, "4代表模板×4等级×3品质×新旧×3升阶=288组合")
end

-- 独立历史副预算/候选顺序，不用被测unitValue/roll当作随机副的oracle。
local POOLS = {
    W18 = { { "physPen", 0.5 }, { "physDmgBonus", 0.3 }, { "atkSpeed", 0.4 }, { "critRate", 1 }, { "critDmg", 0.2 }, { "hitValue", 0.8 } },
    W24 = { { "physPen", 0.5 }, { "physDmgBonus", 0.3 }, { "atkSpeed", 0.4 }, { "critRate", 1 }, { "critDmg", 0.2 }, { "hitValue", 0.8 } },
    W72 = { { "healBonus", 0.25 }, { "healCritRate", 0.8 }, { "healCritDmg", 0.15 }, { "spi", 1.5 }, { "atkSpeed", 0.4 } },
    C15 = { { "atkSpeed", 0.4 }, { "critRate", 1 }, { "critDmg", 0.2 }, { "hitValue", 0.8 } },
}
local BUDGET = { W18 = { 3.855 }, W24 = { 3.852, 3.87 }, W72 = { 3.85 }, C15 = { 2.58 } }
local function historicalRoll(f, id)
    local pool, rows = copy(POOLS[id]), {}
    for i, budget in ipairs(BUDGET[id]) do
        local chosen = math.floor(f.math.random() * #pool) + 1
        local selected = table.remove(pool, chosen)
        rows[i] = { selected[1], budget / selected[2] }
    end
    return { version = 1, stats = rows }
end
local function testBudgetsAndRNG(f)
    for _, id in ipairs({ "W18", "W24", "W72", "C15" }) do
        for _, quality in ipairs({ 1, 5, 6 }) do
            for seed = 1, 12 do
                local q, tpl = f.EC.QUALITY[quality], f.EC.ITEMS[id]
                f.math.randomseed(20261024 + seed)
                local affixes = f.Eq.rollAffixes(q.affixCount, q.maxAffixQuality, 100, {}, q.randomStrength, tpl.grip)
                local oldNext, oldCalls = f.math.random(), f.rng.calls
                f.math.randomseed(20261024 + seed)
                local old = f.Eq.generate(id, 100, quality, { legacySecondary = true })
                check(same(old.affixes, affixes) and old.secondaryRoll == nil, id .. "旧生成不补抽")
                check(f.math.random() == oldNext and f.rng.calls == oldCalls, id .. "旧生成RNG完全不变")
                f.math.randomseed(20261024 + seed)
                f.Eq.rollAffixes(q.affixCount, q.maxAffixQuality, 100, {}, q.randomStrength, tpl.grip)
                local expected = historicalRoll(f, id)
                local nextExpected, callsExpected = f.math.random(), f.rng.calls
                f.math.randomseed(20261024 + seed)
                local item = f.Eq.generate(id, 100, quality)
                check(same(item.affixes, affixes), id .. "副抽取仍在原词缀之后")
                -- 预算浮点乘除容差不放宽key/版本/顺序。
                check(item.secondaryRoll.version == 1 and #item.secondaryRoll.stats == #expected.stats, id .. "v1副槽数不变")
                for i, row in ipairs(expected.stats) do
                    local actual = item.secondaryRoll.stats[i]
                    check(actual[1] == row[1], id .. "历史RNG选key/顺序")
                    eq(actual[2], row[2], id .. "历史raw副预算")
                end
                check(f.math.random() == nextExpected and f.rng.calls == callsExpected, id .. "新生成调用数与后继RNG不变")
                noRNG(f, function()
                    f.Eq.computeModifierEntries(item, 1.5); f.Eq.hydrate(item); f.Eq.dehydrate(item)
                    f.Secondary.restore(tpl, item)
                end, id .. "只读/重算")
            end
        end
    end
end

local function testFullOldCache(f)
    for _, key in ipairs(KEYS) do
        local tpl = f.EC.ITEMS.W24
        local item = { templateId = "W24", name = tpl.name, type = tpl.type, slot = tpl.slot,
            grip = tpl.grip, level = 100, quality = 5, ascendLevel = 30, affixMult = 2,
            baseStats = { { "physAtk", 314.2076 }, { key, 12345 }, { "critDmg", 67 } },
            affixes = { { key = key, value = 100, ascBonus = 3 } } }
        local snapshot, reference = copy(item), item.baseStats
        noRNG(f, function()
            local entries = f.Eq.computeModifierEntries(item, 1.5)
            eq(entries[2].flat, curve(12345 * 1.75, BASE[key] * 2), key .. "完整旧缓存直接消费")
            eq(entries[4].flat, curve(203, AFFIX[key] * 2), key .. "旧词缀新出口")
            check(same(item, snapshot) and item.baseStats == reference, key .. "无迁移/改raw/换引用")
            local inventory = { nextSeq = 41, inventory = {} }
            f.Eq.addToInventory(inventory, item)
            check(inventory.inventory["41"] == item and item.baseStats == reference, key .. "完整缓存入包无需水合迁移")
            f.Eq.hydrate(item)
            check(same(item.baseStats, snapshot.baseStats) and item.secondaryRoll == nil, key .. "旧水合保缓存/不补roll")
        end, key .. "完整旧缓存")
    end
end

local function representative(f, id, roll)
    local item = f.Eq.generate(id, 100, 5)
    item.secondaryRoll, item.baseStats = { version = 1, stats = { { "critRate", roll } } }, nil
    item.ascendLevel, item.affixes = 30, {}
    return f.Eq.hydrate(item)
end
local function testRepresentativeAndLifecycle(f)
    local weapon, charm = representative(f, "W18", 3.855), representative(f, "C15", 2.58)
    local wSnapshot, cSnapshot = copy(weapon), copy(charm)
    eq(weapon.baseStats[2][2], 32.11215, "W18保存raw未缩放")
    eq(charm.baseStats[2][2], 21.4914, "C15保存raw未缩放")
    eq(f.Eq.effectiveBaseStatValue(weapon, 2), 7.2750370623142455, "W18新通暴约7.275")
    eq(f.Eq.effectiveBaseStatValue(charm, 2), 6.963201762557003, "C15新通暴约6.963")
    local attrs = f.UA.create({ maxHp = 1000 })
    local original = copy(attrs.final)
    f.Eq.applyToUnit(attrs, weapon, 18, 1.5); f.Eq.applyToUnit(attrs, charm, 15, 1.5)
    eq(attrs:get("luk"), 89.131, "C15命数未进装备暴率曲线")
    eq(attrs.derived.critRate, 26.7393, "命数独立贡献26.7393")
    eq(attrs:get("critRate"), 40.97753882487125, "真实双装备新总暴率")
    -- 旧数值仅从真实实例raw组装旧modifier，UA仍为生产实现，不改任何生产函数。
    local oldAttrs, oldEntries = f.UA.create({ maxHp = 1000 }), {}
    for _, item in ipairs({ weapon, charm }) do
        for _, row in ipairs(item.baseStats) do oldEntries[#oldEntries + 1] = { key = row[1], flat = row[2] * 2.5 } end
    end
    oldAttrs:addModifier("historical_raw_only", oldEntries)
    eq(oldAttrs:get("critRate"), 160.748175, "同实例独立还原旧总160.748175")
    eq(attrs:get("critDmg"), oldAttrs:get("critDmg"), "LUK派生暴伤完全不变")
    eq(attrs:get("physAtk"), oldAttrs:get("physAtk") + weapon.baseStats[1][2] * 2.5 * 0.6,
        "Lv100武器直给物攻补偿1.6，六围派生攻击不额外放大")
    local clone = attrs:clone()
    clone:recalc()
    eq(clone:get("critRate"), attrs:get("critRate"), "clone/recalc不再缩一次")
    f.Eq.removeFromUnit(clone, 18)
    eq(clone:get("critRate"), 33.702501762557, "clone卸武器仅移除7.275")
    eq(attrs:get("critRate"), 40.97753882487125, "clone卸装不污染原属性链")
    f.Eq.removeFromUnit(attrs, 15)
    eq(attrs:get("critRate"), 7.2750370623142455, "卸C15同时移除直给与LUK派生")
    f.Eq.removeFromUnit(attrs, 18)
    check(same(attrs.final, original), "全卸装恢复全属性而非仅暴率")
    check(same(weapon, wSnapshot) and same(charm, cSnapshot), "穿卸/clone不污染原装备/secondaryRoll")
end

local OLD_OUTPUT = {
    [5] = { atkSpeed = 4 },
    [7] = { magAtkBonus = 2.5 },
    [11] = { physAtkBonus = 2.5 },
    [14] = { atkSpeed = 2 },
    [17] = { magDmgBonus = 5 },
    [19] = { physDmgBonus = 5 },
    [26] = { magAtkBonus = 3.3 },
    [27] = { critDmg = 10 },
    [28] = { comboRate = 7 },
    [29] = { physAtkBonus = 3.3 },
    [33] = { magAtkBonus = 3 },
    [35] = { atkSpeed = 5 },
    [38] = { physAtkBonus = 3 },
    [41] = { magDmgBonus = 10 },
    [42] = { magAtkBonus = 5 },
    [44] = { magCritDmg = 20 },
    [45] = { critDmg = 15 },
    [48] = { atkSpeed = 8 },
    [49] = { physCritDmg = 20 },
    [51] = { physAtkBonus = 5 },
    [52] = { physDmgBonus = 10 },
    [61] = { magDmgBonus = 10 },
    [64] = { magAtkBonus = 5 },
    [65] = { critDmg = 15 },
    [67] = { atkSpeed = 8 },
    [68] = { comboRate = 10 },
    [69] = { physAtkBonus = 5 },
    [72] = { physDmgBonus = 10 },
    [77] = { magDmgBonus = 15 },
    [78] = { atkSpeed = 12, comboRate = 9 },
    [79] = { physDmgBonus = 15 },
    [82] = { magDmgBonus = 7 },
    [83] = { critDmg = 20 },
    [86] = { magAtkBonus = 5 },
    [90] = { physAtkBonus = 5 },
    [94] = { magAtkBonus = 5 },
    [95] = { magCritDmg = 20 },
    [96] = { atkSpeed = 8 },
    [97] = { comboRate = 10 },
    [98] = { physCritDmg = 20 },
    [99] = { physAtkBonus = 5 },
    [102] = { magCritDmg = 8 },
    [103] = { physCritDmg = 8 },
    [114] = { atkSpeed = 15, comboRate = 10 },
    [118] = { magDmgBonus = 10 },
    [119] = { magCritDmg = 20 },
    [120] = { atkSpeed = 7 },
    [121] = { critDmg = 15 },
    [122] = { physCritDmg = 20 },
    [123] = { physDmgBonus = 10 },
    [127] = { critDmg = 50, dmgBonus = -10 },
    [130] = { magDmgBonus = 20 },
    [131] = { magCritDmg = 28 },
    [132] = { comboRate = 15, comboDmgUp = 8 },
    [133] = { critDmg = 45 },
    [134] = { physCritDmg = 28 },
    [135] = { physDmgBonus = 20 },
    [140] = { magCritDmg = 27 },
    [142] = { atkSpeed = 10 },
    [144] = { comboRate = 13 },
    [145] = { physAtkBonus = 6.5 },
    [148] = { physCritDmg = 27 },
    [154] = { atkSpeed = 18 },
    [155] = { critDmg = 28 },
    [157] = { magDmgBonus = 15 },
    [158] = { magCritDmg = 21 },
    [159] = { atkSpeed = 12 },
    [160] = { comboRate = 16, critDmg = 16 },
    [161] = { physAtkBonus = 8 },
    [162] = { physDmgBonus = 16, physCritDmg = 21 },
    [165] = { magDmgBonus = 20, magAtkBonus = 10 },
    [166] = { atkSpeed = 18, comboRate = 16 },
    [167] = { physDmgBonus = 20, physAtkBonus = 10 },
    [172] = { magCritDmg = 32 },
    [174] = { atkSpeed = 12 },
    [176] = { comboRate = 15 },
    [177] = { physAtkBonus = 8 },
    [180] = { physCritDmg = 32 },
    [186] = { magCritDmg = 28, atkSpeed = 10 },
    [187] = { critDmg = 35 },
    [189] = { magDmgBonus = 18 },
    [190] = { magAtkBonus = 12 },
    [191] = { atkSpeed = 14 },
    [192] = { comboRate = 18, comboDmgUp = 10 },
    [193] = { physAtkBonus = 10 },
    [194] = { physDmgBonus = 18, physCritDmg = 24 },
    [197] = { magDmgBonus = 24, magAtkBonus = 12 },
    [198] = { atkSpeed = 22, comboRate = 18 },
    [199] = { physDmgBonus = 24, physAtkBonus = 12 },
    [204] = { magDmgBonus = 16, magCritDmg = 24 },
    [205] = { physCritDmg = 32, physDmgBonus = 10 },
    [206] = { critDmg = 20, physAtkBonus = 4 },
    [207] = { atkSpeed = 14, comboRate = 8 },
    [208] = { comboRate = 12, comboDmgUp = 8 },
}

local OUTPUT_SCALE = { atkSpeed = 0.25, physAtkBonus = 0.4, magAtkBonus = 0.4,
    physDmgBonus = 0.25, magDmgBonus = 0.25, critDmg = 0.2,
    physCritDmg = 0.2, magCritDmg = 0.2, comboRate = 0.25, comboDmgUp = 0.5, dmgBonus = 0.25 }
-- 只规范化本轮授权的数值位置；其他属性、概率、时长、阈值和全文仍锁定旧源hash。
local function frozenEffect(id, text)
    for _, name in ipairs({ "物理暴击伤害", "魔法暴击伤害", "暴击伤害", "攻击速度",
        "物理攻击加成", "魔法攻击加成", "物理伤害加成", "魔法伤害加成", "连击概率", "连击增伤" }) do
        text = text:gsub(name .. "([+-])[%d%.]+%%", name .. "%1#%%")
    end
    if id == 127 then text = text:gsub("伤害加成%-[%d%.]+%%", "伤害加成-#%%") end
    local patterns = { [113] = { "增加[%d%.]+%%", "增加#%%" },
        [115] = { "×[%d%.]+%%", "×#%%" }, [128] = { "的[%d%.]+%%伤害加成", "的#%%伤害加成" },
        [204] = { "追加[%d%.]+%%伤害", "追加#%%伤害" }, [206] = { "追加[%d%.]+%%伤害", "追加#%%伤害" },
        [208] = { "连击[%d%.]+%%伤害", "连击#%%伤害" } }
    local pair = patterns[id]
    if pair then text = text:gsub(pair[1], pair[2]) end
    return text
end

local function testOutputBudget(f)
    local all = {}
    for id = 0, 208 do all[#all + 1] = id end
    local totals = { atkSpeed = 49.75, physAtkBonus = 34.92, magAtkBonus = 25.12,
        physDmgBonus = 39.5, magDmgBonus = 42.5, critDmg = 53.8,
        physCritDmg = 46.4, magCritDmg = 45.6, comboRate = 44.25, comboDmgUp = 13, dmgBonus = -2.5 }
    local untouched = { str = 12, agi = 11, int = 13, vit = 13, luk = 7, spi = 8,
        physPen = 73, magPen = 64, physAtk = 6, magAtk = 6, hitValue = 13 }
    for _, classId in ipairs({ "seal", "spoil", "rift", "echo", "mask", "debt" }) do
        for id = 0, 208 do
            local entries = f.TE.collectEntries({ id }, classId)
            local row = OLD_OUTPUT[id] or {}
            for key, scale in pairs(OUTPUT_SCALE) do
                local expected = (row[key] or 0) * scale
                if id == 106 and classId == "rift" and key == "magDmgBonus" then expected = expected + 1.25 end
                if id == 108 and classId == "mask" and key == "critDmg" then expected = expected + 2 end
                if id == 109 and classId == "echo" and key == "atkSpeed" then expected = expected + 1.25 end
                if id == 111 and classId == "spoil" and key == "physDmgBonus" then expected = expected + 1.25 end
                eq(sum(entries, key), expected, classId .. "/单节点独立旧值倍率 " .. id .. "/" .. key)
            end
        end
        local entries = f.TE.collectEntries(all, classId)
        for key, total in pairs(totals) do
            local extra = (classId == "rift" and key == "magDmgBonus" or classId == "spoil" and key == "physDmgBonus") and 1.25
                or (classId == "echo" and key == "atkSpeed") and 1.25
                or (classId == "mask" and key == "critDmg") and 2 or 0
            eq(sum(entries, key), total + extra, classId .. "/全树来源预算 " .. key)
        end
        for key, total in pairs(untouched) do eq(sum(entries, key), total, classId .. "/非目标来源不变 " .. key) end
        local attrs = f.UA.create({})
        f.TE.applyToUnit(attrs, all, classId)
        local snapshot = copy(attrs.final)
        f.TE.applyToUnit(attrs, all, classId)
        check(same(attrs.final, snapshot), classId .. "重复应用全树不叠加")
        local clone = attrs:clone()
        clone:removeModifier("talent_starmap")
        check(same(clone.final, f.UA.create({}).final), classId .. "clone移除全树完全恢复")
        check(same(attrs.final, snapshot), classId .. "clone不污染原属性")
    end
    local routes = {
        { { 1,14,5,18,78,27,35,45,120,96,114,126,141,173,154,207,186,174,191,198 }, { atkSpeed = 35.75 } },
        { { 2,11,19,30,38,52,123,135,147,162,167,199 }, { physDmgBonus = 26.25, physAtkBonus = 11, dmgBonus = 0 } },
        { { 4,7,107,26,34,43,57,190,197 }, { magAtkBonus = 11.92, magDmgBonus = 6, int = 5, magAtk = 6, magCritRate = 2 } },
    }
    for ri, route in ipairs(routes) do
        local lit, ids = { [0] = true }, { 0 }
        for _, id in ipairs(route[1]) do
            local adjacent = false
            for _, neighbor in ipairs(f.TSM.getNode(id).adj) do if lit[neighbor] then adjacent = true end end
            check(adjacent and not lit[id], "路线真实相邻合法且每点一次 " .. ri .. "/" .. id)
            lit[id], ids[#ids + 1] = true, id
        end
        local entries = f.TE.collectEntries(ids, "seal")
        for key, expected in pairs(route[2]) do eq(sum(entries, key), expected, "合法路线来源预算 " .. ri .. "/" .. key) end
        local oldIds = copy(ids)
        f.TE.applyToUnit(f.UA.create({}), ids, "seal")
        check(same(oldIds, ids), "旧litNodes不迁移/增删点 " .. ri)
    end
    print(PREFIX .. "预算 atkSpeed=49.75 physDmgBonus=39.5 magDmgBonus=42.5 comboRate=44.25；六围/暴率保持")
end

local function testStarMap(f)
    local groups = {
        { "critRate", { 13, 66, 143, 175, 187, 198, 206, 208 }, 6, { 0.5, 0.5, 1, 1, 1, 0.5, 1, 0.5 } },
        { "physCritRate", { 37, 70, 83, 103, 108, 110, 134, 147, 155, 179 }, 9 },
        { "magCritRate", { 34, 63, 82, 102, 107, 131, 139, 154, 158, 171, 186, 190 }, 9 },
        { "healCritRate", { 53, 136, 195, 202 }, 8 },
    }
    local hash, effectHash, allIds, graphSnapshot = 0, 0, {}, {}
    for id = 0, 208 do
        local node, def = f.TSM.getNode(id), f.Defs.getNode(id)
        assert(node and def, "节点缺失 " .. id)
        -- 邻接是集合而非消费顺序；TSM历史203/205/207与Defs仅数组顺序不同。
        -- 排序独立副本，不修改真实节点；保留长度与重复项，仍能检测增边/删边/重复边。
        local nodeAdj, defAdj = copy(node.adj), copy(def.adj)
        table.sort(nodeAdj); table.sort(defAdj)
        check(node.id == id and same(nodeAdj, defAdj), "星图ID/服务端邻接集合一致 " .. id)
        graphSnapshot[id] = { id = node.id, adj = copy(node.adj), effect = node.effect }
        for _, value in ipairs({ id, #nodeAdj, table.unpack(nodeAdj) }) do hash = (hash * 131 + value + 1) % 2147483647 end
        local nonRateText = frozenEffect(id, node.effect or "")
        effectHash = (effectHash * 131 + id + 1) % 2147483647
        for i = 1, #nonRateText do effectHash = (effectHash * 131 + nonRateText:byte(i)) % 2147483647 end
        allIds[#allIds + 1] = id
    end
    check(f.TSM.getNode(-1) == nil and f.TSM.getNode(209) == nil, "ID边界仍0..208")
    check(f.Defs.getNodeCount() == 209 and hash == 1621190722, "209节点完整邻接集合与历史冻结hash不变")
    check(effectHash == 154765033, "209节点仅目标输出数值可变，其余全文冻结hash不变")
    for _, classId in ipairs({ "seal", "spoil", "rift", "echo", "mask", "debt" }) do
        for _, group in ipairs(groups) do
            local key, ids, total = group[1], group[2], group[3]
            eq(sum(f.TE.collectEntries(ids, classId), key), total, classId .. "/" .. key .. "真实collect分类总额")
            eq(sum(f.TE.collectEntries(allIds, classId), key), total, classId .. "/" .. key .. "无遗漏直给节点")
            for i, id in ipairs(ids) do
                if group[4] then eq(sum(f.TE.collectEntries({ id }, classId), key), group[4][i], "通用八节点单值 " .. id) end
            end
            local attrs = f.UA.create({ luk = 7 })
            f.TE.applyToUnit(attrs, ids, classId)
            local expected = total + (key == "critRate" and 2.1 or 0)
            eq(attrs:get(key), expected, classId .. "/" .. key .. "真实apply不套装备曲线")
            f.TE.applyToUnit(attrs, ids, classId)
            eq(attrs:get(key), expected, "重复应用覆盖同名modifier不叠加")
            local clone = attrs:clone()
            clone:removeModifier("talent_starmap")
            eq(clone:get(key), key == "critRate" and 2.1 or 0, "clone移除星图不残留")
        end
    end
    local attrs = f.UA.create({})
    f.TE.applyToUnit(attrs, { 6, 46, 58, 88 }, "seal")
    eq(attrs:get("luk"), 7, "四个命数节点合计7未削减")
    eq(attrs:get("critRate"), 2.1, "真实星图命数7派生2.1未削减")
    eq(sum(f.TE.collectEntries({ 83 }, "seal"), "critDmg"), 4, "混合节点83暴伤20缩至4")
    eq(sum(f.TE.collectEntries({ 108 }, "mask"), "critDmg"), 2, "职业额外暴伤10缩至2")
    for id, snapshot in pairs(graphSnapshot) do
        local node = f.TSM.getNode(id)
        check(same({ id = node.id, adj = node.adj, effect = node.effect }, snapshot), "collect/apply不改节点 " .. id)
    end
end

-- 沿用独立Runtime骨架，真实运行四个触发模块/SEM/UA；伤害落地为显式内存记录边界。
local function testRuntimeOutput(f)
    local sem = f.import("systems.StatusEffectManager")
    sem.mount(sem.newSemState())
    local states, refs, events = {}, {}, {}
    local function state(u) return states[u] end
    local function unit(nodes, hp)
        local attrs = f.UA.create({ maxHp = 10000 })
        local u = { name = "星图测试", hp = hp or 10000, maxHp = 10000, attrs = attrs,
            nodes = {}, dmgMainType = "魔法" }
        for _, id in ipairs(nodes or {}) do u.nodes[id] = true end
        states[u] = { heroId = 0, patrolQueue = {}, windStacks = 0, critBoostStacks = 0,
            corrosionCds = {}, slaughterTimer = 0, resonanceTimer = 0 }
        return u
    end
    local deps = {
        getState = state, ensureState = state,
        hasAdv = function() return false end, hasAwaken = function() return false end,
        hasStarNode = function(u, id) return u.nodes[id] == true end,
        teamHasStarNode = function() return false end, talentLog = function() end,
        getTAL_BCS = function() return refs end,
        wrapDealDmgForLuoxing = function(_, fn) return fn end,
        getPrimaryAyane = function() return nil end,
        getAliveEnemies = function(list)
            local live = {}; for _, u in ipairs(list) do if u.hp > 0 then live[#live + 1] = u end end
            return live
        end,
        findLivingElwyn = function() return nil end,
    }
    local after = f.import("systems.talents.TalentAfterAttack").bind(deps)
    local death = f.import("systems.talents.TalentEnemyDeath").bind(deps)
    local combo = f.import("systems.talents.TalentComboAttack").bind(deps)
    local update = f.import("systems.talents.TalentUpdate").bind(deps)
    local function damage(target, amount, side, prefix)
        events[#events + 1] = { target = target, amount = amount, side = side, prefix = prefix }
    end
    local function attack(u, t, result, allies)
        after.onAfterAttack(u, t, result or { category = "magical", totalDamage = 1000 }, true, { t }, damage, allies or { u })
    end
    local savedRandom = f.math.random
    local roll, calls = 0, 0
    f.math.random = function() calls = calls + 1; return roll end
    local ok, why = xpcall(function()
        local u, target = unit({ 113 }), unit({})
        roll = 0.1499; attack(u, target)
        eq(sem.get(target, sem.ARCANE_MARK).data.mult, 0.02, "113真实注入易伤2%")
        eq(sem.get(target, sem.ARCANE_MARK).remaining, 5, "113持续5秒保持")
        eq(sem.getDamageTakenMult(target), 1.02, "113真实受伤倍率")
        sem.reset(); roll = 0.15; attack(u, target)
        check(not sem.has(target, sem.ARCANE_MARK), "113概率15%严格边界不触发")
        sem.apply(target, sem.ARCANE_MARK, 5, u, {})
        eq(sem.getDamageTakenMult(target), 1.02, "113省略mult仍兜底2%")
        sem.update(5); check(not sem.has(target, sem.ARCANE_MARK), "113五秒过期")
        eq(sem.getDamageTakenMult(target), 1, "113过期倍率恢复")
        sem.reset(); u.dmgMainType = "物理"; roll = 0; attack(u, target)
        check(not sem.has(target, sem.ARCANE_MARK), "113原魔法主类型条件保持")

        u = unit({ 115 }); target.hp = 2000
        local count = #events
        attack(u, target, { category = "physical", isCrit = true, totalDamage = 1000 })
        eq(#events, count + 1, "115暴击只追加一次")
        eq(events[#events].amount, 60, "115命中后损失80%乘7.5%=60")
        attack(u, target, { category = "physical", totalDamage = 1000 })
        eq(#events, count + 1, "115非暴击不追加")

        u = unit({ 120 }); target = unit({})
        for n = 1, 9 do
            attack(u, target)
            eq(states[u].pursuitStacks, math.min(5, n - 1), "120原第2击起最多5层")
            eq(u.attrs:get("atkSpeed"), math.min(5, n - 1) * 0.5, "120每层0.5且不重复叠modifier")
        end
        local other = unit({}); attack(u, other)
        eq(u.attrs:get("atkSpeed"), 0, "120换目标清层")
        attack(u, other, { category = "healing" })
        eq(states[u].pursuitStacks, 0, "120治疗不叠层")

        u = unit({ 126 }); local peer, fallen = unit({ 126 }), unit({ 126 }, 0)
        death.onEnemyDeath(target, { u, peer, fallen }, {})
        for _, live in ipairs({ u, peer }) do
            eq(live.attrs:get("atkSpeed"), 7.5, "126保持存活友军原触发域")
            eq(states[live].slaughterTimer, 5, "126原5秒")
        end
        eq(fallen.attrs:get("atkSpeed"), 0, "126不施加给阵亡友军")
        update.update(2, { u, peer }, {}, {})
        eq(u.attrs:get("atkSpeed"), 7.5, "126到期前保留")
        death.onEnemyDeath(target, { u, peer }, {})
        eq(u.attrs:get("atkSpeed"), 7.5, "126重触发刷新而非叠加")
        update.update(5, { u, peer }, {}, {})
        eq(u.attrs:get("atkSpeed"), 0, "126刷新后完整5秒到期移除")

        u = unit({ 128 }); peer = unit({}); fallen = unit({}, 0)
        roll = 0.1499; attack(u, target, nil, { u, peer, fallen })
        for _, live in ipairs({ u, peer }) do
            eq(live.attrs:get("dmgBonus"), 1.25, "128真实全队1.25%")
            eq(states[live].resonanceTimer, 3, "128原3秒")
        end
        eq(fallen.attrs:get("dmgBonus"), 0, "128排除死亡")
        update.update(3, { u, peer }, {}, {})
        eq(u.attrs:get("dmgBonus"), 0, "128三秒到期移除")
        roll = 0.15; attack(u, target, nil, { u, peer })
        eq(u.attrs:get("dmgBonus"), 0, "128概率15%边界不触发")
        roll = 0; attack(u, target, { category = "healing" }, { u, peer })
        eq(u.attrs:get("dmgBonus"), 1.25, "128治疗入口也触发")

        u = unit({ 204 }); target = unit({}); count = #events
        roll = 0.1999; attack(u, target, { category = "magical", isCrit = true, totalDamage = 1000 })
        eq(#events, count + 1, "204二成概率内只一段")
        eq(events[#events].amount, 45, "204真实追加4.5%")
        roll = 0.20; attack(u, target, { category = "magical", isCrit = true, totalDamage = 1000 })
        attack(u, target, { category = "physical", isCrit = true, totalDamage = 1000 })
        attack(u, target, { category = "magical", totalDamage = 1000 })
        eq(#events, count + 1, "204概率/物理/非暴击拒绝保持")

        u = unit({ 206 }); target.hp = 3000; count = #events
        attack(u, target, { category = "physical", totalDamage = 1000, actualDamage = 499 })
        eq(#events, count + 1, "206命中前低于35%触发")
        eq(events[#events].amount, 30, "206真实附伤3%")
        attack(u, target, { category = "physical", totalDamage = 1000, actualDamage = 500 })
        eq(#events, count + 1, "206等于35%不触发")

        u = unit({ 207 }); update.onDodge(u)
        eq(u.attrs:get("atkSpeed"), 3, "207闪避真实加速3%")
        eq(states[u].shadowstepTimer, 3, "207原3秒持续")
        eq(states[u].shadowstepCd, 6, "207原6秒冷却")
        update.update(1, { u }, {}, {}); update.onDodge(u)
        eq(states[u].shadowstepTimer, 2, "207冷却中不刷新")
        update.update(2, { u }, {}, {})
        eq(u.attrs:get("atkSpeed"), 0, "207到3秒移除")
        update.onDodge(u); eq(u.attrs:get("atkSpeed"), 0, "207到期但仍冷却不能触发")
        update.update(3, { u }, {}, {}); update.onDodge(u)
        eq(u.attrs:get("atkSpeed"), 3, "207满6秒再次触发")

        u = unit({ 208 }); count = #events
        combo.onComboAttack(u, target, true, { target }, damage, { category = "physical", totalDamage = 1000 })
        eq(#events, count + 1, "208真实连击仅一段")
        eq(events[#events].amount, 30, "208附伤3%")
        combo.onComboAttack(u, target, true, { target }, damage, { category = "healing", totalDamage = 1000 })
        target.hp = 0
        combo.onComboAttack(u, target, true, { target }, damage, { category = "physical", totalDamage = 1000 })
        eq(#events, count + 1, "208治疗/死亡目标不触发")
        check(calls > 0, "触发概率使用明确私有RNG")
    end, debug.traceback)
    f.math.random = savedRandom
    if not ok then error(why) end
    print(PREFIX .. "真实触发113/115/120/126/128/204/206/207/208及过期/冷却通过")
end

function Start()
    local ok, err = xpcall(function()
        local f = fixture()
        for _, group in ipairs({
            { "四key两来源与双手兜底", testCurve }, { "生效顺序只压一次", testEffectiveOrder },
            { "非暴率与派生", testNonRates }, { "等级品质升阶新旧JSON", testMatrixAndPersistence },
            { "历史副预算与RNG", testBudgetsAndRNG }, { "完整旧缓存无迁移", testFullOldCache },
            { "W18+C15真实属性穿卸clone", testRepresentativeAndLifecycle }, { "真实星图全类别", testStarMap },
            { "209节点输出预算与合法路线", testOutputBudget },
            { "真实星图触发幅度", testRuntimeOutput },
        }) do
            local passed, why = xpcall(function() group[2](f) end, debug.traceback)
            if not passed then check(false, group[1] .. " Runtime异常:" .. tostring(why)) end
            print(PREFIX .. "完成 " .. group[1])
        end
    end, debug.traceback)
    if not ok then check(false, "fixture初始化异常:" .. tostring(err)) end
    print(PREFIX .. "checks=" .. checks .. " failure_count=" .. #failures)
    print(PREFIX .. (#failures == 0 and "RESULT ALL PASS" or "RESULT " .. #failures .. " FAIL"))
    engine:Exit()
end
