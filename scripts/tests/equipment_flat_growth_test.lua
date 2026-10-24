-- 固定数值装备成长专项；基于 critical_rate_budget_test / corrupt_value_budget_test 骨架。
-- 仅 cache:GetFile 读取白名单源码，真实模块在私有环境执行；PDM/Task 只有内存边界。
-- 不加载 main、不读玩家档/凭据、不联网；不改全局 require/package.loaded/math.random。
-- 独立 Runtime 入口 tests/equipment_flat_growth_test.lua；不以进程退出码代替业务断言。
-- 验收必须同时找到 RESULT ALL PASS 与 failure_count=0；engine:Exit() 本身不代表通过。
local PREFIX = "[equipment_flat_growth] "
local checks, failures, conversionPairs, generationCases = 0, {}, 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then failures[#failures + 1] = label; print(PREFIX .. "[FAIL] " .. label) end
end
local function near(a, b)
    return type(a) == "number" and type(b) == "number" and a == a and b == b
        and a > -math.huge and a < math.huge and b > -math.huge and b < math.huge
        and math.abs(a - b) <= math.max(1, math.abs(b)) * 1e-10
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
    if type(a) ~= "table" then
        if type(a) == "number" then return a == b or (a ~= a and b ~= b) end
        return a == b
    end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local ALLOWED = {
    ["systems.AttributeDef"] = true, ["systems.EquipmentSystem"] = true,
    ["systems.EquipmentStatGrowth"] = true,
    ["systems.EquipmentSecondaryStats"] = true, ["config.EquipmentConfig"] = true,
    ["config.AffixConfig"] = true, ["config.BlacksmithConfig"] = true,
    ["config.ExpTable"] = true, ["config.StageConfig"] = true,
    ["rules.blacksmith.BlacksmithService"] = true, ["shared.SuccessNotificationContext"] = true,
}
for _, difficulty in ipairs({ "Normal", "Hard", "Nightmare", "Hell", "Purgatory", "Torment",
    "Torment2", "Torment3", "Torment4", "Torment5", "Annihilation", "Annihilation2",
    "Annihilation3", "Annihilation4", "Annihilation5" }) do
    ALLOWED["config.StageConfig_" .. difficulty] = true
end
local sources = {}
local function source(name)
    assert(ALLOWED[name], "禁止读取非白名单源码 " .. tostring(name))
    if sources[name] then return sources[name] end
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(cache:GetFile(path), "缺少隔离fixture源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = tostring(table.concat(lines, "\n"))
    sources[name] = text
    return text
end
local function fixture()
    local loaded, modules = {}, {}
    local rng = { state = 1, calls = 0 }
    local privateMath = copy(math)
    privateMath.randomseed = function(seed) rng.state, rng.calls = seed, 0 end
    privateMath.random = function(lo, hi)
        rng.state = (rng.state * 48271) % 2147483647
        rng.calls = rng.calls + 1
        local value = rng.state / 2147483647
        if lo == nil then return value end
        if hi == nil then hi, lo = lo, 1 end
        return lo + math.floor(value * (hi - lo + 1))
    end
    local notifications = { dirty = {}, flushes = 0, progress = 0 }
    loaded["rules.character.PlayerDataManager"] = {
        GetModule = function(uid, name) assert(uid == 1); return modules[name] end,
        MarkDirty = function(uid, name)
            assert(uid == 1 and (name == "equipment" or name == "currency"))
            notifications.dirty[name] = (notifications.dirty[name] or 0) + 1
        end,
        FlushImmediate = function(uid) assert(uid == 1); notifications.flushes = notifications.flushes + 1 end,
    }
    loaded["rules.task.TaskService"] = {
        UpdateProgress = function(uid, task, amount)
            assert(uid == 1 and (task == "refine" or task == "enhance") and amount == 1)
            notifications.progress = notifications.progress + 1
        end,
    }
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
        math = privateMath, table = table, string = string, print = function() end,
    }
    env._G = env
    local function import(name)
        if loaded[name] then return loaded[name] end
        assert(ALLOWED[name], "禁止加载非白名单模块 " .. tostring(name))
        local compile = load --[[@as fun(text: string, name: string, mode: string, env: table): function?, string?]]
        local chunk, why = compile(source(name), "@flat-growth-private/" .. name, "t", env)
        if not chunk then error(tostring(why)) end
        local value = chunk()
        loaded[name] = value
        return value
    end
    env.require = import
    modules.equipment = { inventory = {}, equipped = {}, nextSeq = 1 }
    modules.currency = { corruptStone = 10000, sacredStone = 10000, enhanceStone = 10000,
        essence = 10 ^ 12, gold = 10 ^ 12, weaponScroll = 10 ^ 6 }
    -- 故意不是装备等级；生效值/洗练都不能从玩家等级取 F。
    modules.player = { level = 9999 }
    modules.battle = { maxStageId = 0 }
    return {
        ES = import("systems.EquipmentSystem"), BS = import("rules.blacksmith.BlacksmithService"),
        AD = import("systems.AttributeDef"), AC = import("config.AffixConfig"),
        EC = import("config.EquipmentConfig"), Secondary = import("systems.EquipmentSecondaryStats"),
        math = privateMath, rng = rng, modules = modules, notifications = notifications,
    }
end
local function noRNG(f, fn, label)
    local calls, state = f.rng.calls, f.rng.state
    fn()
    check(f.rng.calls == calls and f.rng.state == state, label .. " 不消费RNG/不重置种子")
end

-- 独立固定常数，禁止从生产倍率/转换函数或生产成长配置推导期望。
local GROWTH = {
    maxHp = { 1.8, 2.8 }, hpRegen = { 1.8, 2.8 }, atkHeal = { 1.8, 2.8 },
    physAtk = { 1.6, 2.4 }, magAtk = { 1.6, 2.4 }, energyShield = { 2, 3.5 },
}
local FLAT_KEYS = { "maxHp", "hpRegen", "atkHeal", "physAtk", "magAtk", "energyShield" }
local LEVELS = { 1, 49, 50, 51, 75, 99, 100, 101, 150, 199, 200, 201, 9999 }
-- 每行依次对应生命组/攻击组/护盾组；显式边界表再校验插值oracle，防止同错。
local BOUNDARY = {
    { 1, 1, 1 }, { 1, 1, 1 }, { 1, 1, 1 }, { 1.016, 1.012, 1.02 },
    { 1.4, 1.3, 1.5 }, { 1.784, 1.588, 1.98 }, { 1.8, 1.6, 2 },
    { 1.81, 1.608, 2.015 }, { 2.3, 2, 2.75 }, { 2.79, 2.392, 3.485 },
    { 2.8, 2.4, 3.5 }, { 2.8, 2.4, 3.5 }, { 2.8, 2.4, 3.5 },
}
local function factor(key, level)
    local anchors = GROWTH[key]
    if not anchors then return 1 end
    local lv = tonumber(level) or 1
    if lv ~= lv or lv == math.huge or lv == -math.huge then lv = 1 end
    if lv <= 50 then return 1 end
    if lv <= 100 then return (100 - lv) / 50 + anchors[1] * (lv - 50) / 50 end
    if lv <= 200 then return anchors[1] * (200 - lv) / 100 + anchors[2] * (lv - 100) / 100 end
    return anchors[2]
end
local CRIT_BASE = { critRate = 8, physCritRate = 10, magCritRate = 10, healCritRate = 10 }
local CRIT_AFFIX = { critRate = 4, physCritRate = 5, magCritRate = 5, healCritRate = 5 }
local function crit(key, value, isAffix, double)
    local limit = (isAffix and CRIT_AFFIX or CRIT_BASE)[key]
    if not limit or value <= 0 then return value end
    local budget = limit * (double or 1)
    return budget / (1 + budget / value)
end
-- 45种普通词条固定顺序、每点静态价值、历史raw基值、历史数据类型。
-- 六围是完整派生总额，不乘派生目标的F；幸运独立洗练价值1，不改变战力VM=0。
local ORDINARY = {
    { "str", 1.5, 0.67 }, { "agi", 1.495, 0.67 }, { "int", 1.49, 0.67 },
    { "vit", 1.49, 0.67 }, { "luk", 1.5, 0.67 }, { "spi", 1.5, 0.67 },
    { "maxHp", 0.03, 33, "int" }, { "armor", 0.7, 1.43 }, { "energyShield", 0.1, 10 },
    { "dodge", 1, 1 }, { "hpRegen", 0.3, 3.33 }, { "atkHeal", 0.45, 2.22 },
    { "physBlockRate", 0.5, 2, "pct" }, { "magBlockRate", 0.5, 2, "pct" },
    { "abnormalRes", 0.5, 2, "pct" }, { "physAtk", 0.5, 2 }, { "magAtk", 0.5, 2 },
    { "atkSpeed", 0.4, 2.5, "pct" }, { "critRate", 1, 1, "pct" },
    { "critDmg", 0.2, 5, "pct" }, { "physCritRate", 0.8, 1.3, "pct" },
    { "physCritDmg", 0.15, 6.7, "pct" }, { "magCritRate", 0.8, 1.3, "pct" },
    { "magCritDmg", 0.15, 6.7, "pct" }, { "physPen", 0.5, 2 }, { "magPen", 0.5, 2 },
    { "dmgBonus", 0.4, 2.5, "pct" }, { "physDmgBonus", 0.3, 3.3, "pct" },
    { "magDmgBonus", 0.3, 3.3, "pct" }, { "comboRate", 0.3, 3.3, "pct" },
    { "comboDmgUp", 0.6, 1.7, "pct" }, { "maxDmgBonus", 0.12, 8.3, "pct" },
    { "minDmgBonus", 0.1, 10, "pct" }, { "hitValue", 0.8, 1.25 },
    { "healAmount", 0.5, 2 }, { "healBonus", 0.25, 4, "pct" },
    { "healCritRate", 0.8, 1.3, "pct" }, { "healCritDmg", 0.15, 6.7, "pct" },
    { "physAtkBonus", 0.6, 1.7, "pct" }, { "magAtkBonus", 0.6, 1.7, "pct" },
    { "hpBonus", 0.6, 1.7, "pct" }, { "dodgeBonus", 0.6, 1.7, "pct" },
    { "esBonus", 0.6, 1.7, "pct" }, { "armorBonus", 0.6, 1.7, "pct" }, { "dropLuck", 1, 1 },
}
local UNITS = {}
for _, row in ipairs(ORDINARY) do UNITS[row[1]] = row[2] end
local function affix(f, key, value, bonus)
    local tpl = assert(f.AC.BY_KEY[key], "缺少词条 " .. key)
    return { affixId = tpl.id, key = key, name = tpl.name,
        quality = tpl.id >= 1000 and 0 or 3, value = value, ascBonus = bonus }
end
local function baseExpected(equip, index, boost, ascend)
    local row = equip.baseStats[index]
    local steps = 0
    if index > 1 then
        local count, position = #equip.baseStats - 1, index - 1
        if ascend >= position then steps = math.floor((ascend - position) / count) + 1 end
    end
    local value = row[2] * (index == 1 and (1 + boost) or (1 + steps * 0.05))
    return crit(row[1], value * factor(row[1], equip.level), false,
        equip.slot == "weapon" and equip.grip == "twohand" and 2 or 1)
end
local function affixExpected(equip, row)
    return crit(row.key, (row.value * (equip.affixMult or 1) + (row.ascBonus or 0))
        * factor(row.key, equip.level), true,
        equip.slot == "weapon" and equip.grip == "twohand" and 2 or 1)
end
local function convertedExpected(old, target, level)
    if old.key == target.key then return old.ascBonus end
    return old.ascBonus * (UNITS[old.key] * factor(old.key, level))
        / (UNITS[target.key] * factor(target.key, level))
end

local function testBoundaries(f)
    check(same(f.EC.FLAT_STAT_GROWTH, GROWTH), "成长配置仅六key及既定100/200级常数")
    noRNG(f, function()
        for _, key in ipairs(FLAT_KEYS) do
            local group = key == "energyShield" and 3 or (key == "physAtk" or key == "magAtk") and 2 or 1
            for i, level in ipairs(LEVELS) do
                local wanted = assert(BOUNDARY[i], "缺少边界oracle")[group]
                local equip = { level = level, ascendLevel = 17, heroLevel = 9999 }
                local before = copy(equip)
                eq(factor(key, level), wanted, key .. " 独立oracle边界" .. level)
                eq(f.ES.getFlatStatGrowthMultiplier(equip, key), wanted, key .. " 实际边界" .. level)
                check(same(equip, before), key .. " 倍率只读" .. level)
            end
            eq(f.ES.getFlatStatGrowthMultiplier(nil, key), 1, key .. " nil装备按Lv1")
            eq(f.ES.getFlatStatGrowthMultiplier({}, key), 1, key .. " 缺等级按Lv1")
            for _, item in ipairs({
                { label = "负等级", level = -100, expected = 1 }, { label = "零等级", level = 0, expected = 1 },
                { label = "非法字符串", level = "bad-level", expected = 1 },
                { label = "空串", level = "", expected = 1 }, { label = "布尔", level = true, expected = 1 },
                { label = "NaN", level = 0 / 0, expected = 1 },
                { label = "正无穷", level = math.huge, expected = 1 },
                { label = "负无穷", level = -math.huge, expected = 1 },
                { label = "数字串100", level = "100", expected = GROWTH[key][1] },
                { label = "数字串200", level = "200", expected = GROWTH[key][2] },
                { label = "分数等级", level = 75.5, expected = factor(key, 75.5) },
            }) do
                local equip = { level = item.level, ascendLevel = 100, affixMult = 2.3,
                    baseStats = { { key, 17.125 }, { key, 9.25 } } }
                local before = copy(equip)
                eq(f.ES.getFlatStatGrowthMultiplier(equip, key), item.expected, key .. " " .. item.label)
                eq(f.ES.effectiveBaseStatValue(equip, 1, 0), 17.125 * item.expected, key .. " 非法/串等级主出口")
                eq(f.ES.effectiveAffixValue(equip, { key = key, value = 9.25, ascBonus = 0.375 }),
                    (9.25 * 2.3 + 0.375) * item.expected, key .. " 非法/串等级词缀出口")
                check(same(equip, before), key .. " 非法/串等级不修写raw")
            end
        end
        for _, key in ipairs({ "str", "healAmount", "hpBonus", "armor", "unknown", "" }) do
            eq(f.ES.getFlatStatGrowthMultiplier({ level = 200 }, key), 1, key .. " 非白名单helper恒等")
        end
    end, "六key边界/非法等级")
end

local function testEffectiveAndPreview(f)
    noRNG(f, function()
        for _, level in ipairs(LEVELS) do
            for _, key in ipairs(FLAT_KEYS) do
                for _, double in ipairs({ 1, 2 }) do
                    local equip = { level = level, ascendLevel = 31, affixMult = 2.3,
                        slot = "weapon", grip = double == 2 and "twohand" or "onehand",
                        baseStats = { { key, 17.125 }, { key, 9.25 }, { key, 3.375 } },
                        affixes = { affix(f, key, 11.125, 0.375) } }
                    local before, ref = copy(equip), equip.baseStats
                    local label = key .. "/lv" .. level .. "/grip" .. double
                    for _, ascend in ipairs({ 0, 1, 2, 3, 30, 31, 99, 100 }) do
                        for i = 1, 3 do
                            local wanted = baseExpected(equip, i, ascend * 0.05, ascend)
                            eq(f.ES.effectiveBaseStatValue(equip, i, nil, ascend), wanted, label .. " 升阶预览" .. ascend .. "/" .. i)
                            if i > 1 then
                                eq(f.ES.effectiveBaseStatValue(equip, i, 999, ascend), wanted, label .. " 副预览忽略mainBoost")
                            end
                        end
                    end
                    for i = 1, 3 do
                        eq(f.ES.effectiveBaseStatValue(equip, i), baseExpected(equip, i, 1.55, 31), label .. " 默认取装备升阶")
                    end
                    eq(f.ES.effectiveBaseStatValue(equip, 1, 0.7, 100), 17.125 * 1.7 * factor(key, level),
                        label .. " 显式主boost优先但F只取equip.level")
                    eq(f.ES.effectiveAffixValue(equip, equip.affixes[1]), affixExpected(equip, equip.affixes[1]),
                        label .. " (raw*affixMult+旧bonus)*F一次")
                    local entries = f.ES.computeModifierEntries(equip, 0.7)
                    check(#entries == 4, label .. " modifier条数")
                    for i = 1, 3 do
                        check(entries[i].key == key, label .. " modifier基础key")
                        eq(entries[i].flat, baseExpected(equip, i, 0.7, 31), label .. " modifier真实基础出口")
                    end
                    eq(entries[4].flat, affixExpected(equip, equip.affixes[1]), label .. " modifier真实词缀出口不二次F")
                    check(same(equip, before) and equip.baseStats == ref, label .. " 查询/预览保持所有raw与引用")
                end
            end
        end
        for _, key in ipairs(FLAT_KEYS) do
            for _, raw in ipairs({ -17.125, 0, 0.001 }) do
                local equip = { level = 200, ascendLevel = 0, baseStats = { { key, raw } }, affixMult = 2.3 }
                eq(f.ES.effectiveBaseStatValue(equip, 1), raw * factor(key, 200), key .. " 基础非正/极小值不取整")
                eq(f.ES.effectiveAffixValue(equip, { key = key, value = raw, ascBonus = 0.013 }),
                    (raw * 2.3 + 0.013) * factor(key, 200), key .. " 词缀非正/极小值不取整")
            end
        end
        eq(f.ES.effectiveBaseStatValue({ baseStats = {} }, 1), 0, "缺基础行返回0")
        eq(f.ES.effectiveAffixValue({}, nil), 0, "缺词条返回0")
    end, "主副预览/栏位倍率/旧bonus/实际modifier")
end

local function testExclusions(f)
    local shield = f.ES.generate("O7", 200, 6, { legacySecondary = true })
    noRNG(f, function()
        local keys = { "unknown", "atkInterval" }
        for key in pairs(f.AD.META) do if not GROWTH[key] then keys[#keys + 1] = key end end
        for _, key in ipairs(keys) do
            for _, level in ipairs({ 50, 100, 200, 9999 }) do
                local equip = { level = level, ascendLevel = 30, affixMult = 2.3,
                    slot = "weapon", grip = "twohand", baseStats = { { key, 17.125 }, { key, 9.25 } },
                    affixes = { { key = key, value = 11.125, ascBonus = 0.375 } } }
                local before = copy(equip)
                eq(f.ES.getFlatStatGrowthMultiplier(equip, key), 1, key .. " 非白名单无成长")
                local main, sub = crit(key, 17.125 * 2.5, false, 2), crit(key, 9.25 * 2.5, false, 2)
                local ordinary = key:sub(1, 5) == "final" and 11.125
                    or crit(key, 11.125 * 2.3 + 0.375, true, 2)
                eq(f.ES.effectiveBaseStatValue(equip, 1), main, key .. " 主沿用旧公式/旧暴击曲线")
                eq(f.ES.effectiveBaseStatValue(equip, 2), sub, key .. " 副沿用旧公式/旧暴击曲线")
                eq(f.ES.effectiveAffixValue(equip, equip.affixes[1]), ordinary, key .. " 词缀沿用旧公式/旧暴击曲线")
                local entries = f.ES.computeModifierEntries(equip, 1.5)
                eq(entries[1].flat, key == "atkInterval" and -main or main, key .. " modifier保留间隔负号")
                eq(entries[3].flat, ordinary, key .. " 非白名单modifier不额外成长")
                check(same(equip, before), key .. " 非白名单读取无迁移")
            end
        end
        for _, tpl in ipairs(f.AC.CORRUPT_AFFIXES) do
            local row = affix(f, tpl.key, 1234.375, 999)
            local before = copy(row)
            eq(f.ES.effectiveAffixValue({ level = 200, affixMult = 17 }, row), 1234.375,
                tpl.key .. " 腐化仍忽略栏位倍率和普通bonus")
            check(same(row, before), tpl.key .. " 腐化查询不清写旧字段")
        end
        -- 故意让腐化身份带白名单key，区分“key不在表”与“腐化分支确实跳过F”。
        for _, key in ipairs(FLAT_KEYS) do
            eq(f.ES.effectiveAffixValue({ level = 200, affixMult = 17 },
                { affixId = 1001, key = key, value = 123.375, ascBonus = 999 }), 123.375,
                key .. " 腐化身份优先，绝不乘F")
        end
        shield.ascendLevel = 100
        local before = copy(shield)
        eq(f.ES.effectiveBaseStatValue(shield, 4, 999, 100), 50, "真实盾固有怨引早返50")
        eq(f.ES.getSecondaryAscendCount(shield, 2, 99), 50, "固有行不占副轮转名额")
        eq(f.ES.getSecondaryAscendCount(shield, 3, 99), 49, "副轮转保留奇数阶差异")
        eq(f.ES.computeModifierEntries(shield, 999)[4].flat, 50, "真实固有modifier不升阶")
        check(same(shield, before), "真实固有属性读取保持raw")
    end, "非白名单/六围/百分比/腐化/固有排除")
    -- 私有fixture中构造白名单固有行，验证早返是在F之前，不改任何生产源文件。
    local id = "__flat_growth_intrinsic_fixture"
    f.EC.ITEMS[id] = { intrinsicStats = { { "maxHp", 50 } } }
    local ok, why = pcall(function()
        local equip = { templateId = id, level = 200, ascendLevel = 99,
            baseStats = { { "physAtk", 10 }, { "energyShield", 5 }, { "maxHp", 50 }, { "atkHeal", 7 } } }
        eq(f.ES.effectiveBaseStatValue(equip, 3, 999, 100), 50, "白名单固有行早返不乘F")
        eq(f.ES.effectiveBaseStatValue(equip, 2, nil, 3), 5 * 1.1 * 3.5, "跨固有行副轮转第一槽2次")
        eq(f.ES.effectiveBaseStatValue(equip, 4, nil, 3), 7 * 1.05 * 2.8, "跨固有行副轮转第二槽1次")
    end)
    f.EC.ITEMS[id] = nil
    check(ok, "白名单固有fixture清理完成 " .. tostring(why))
end

-- 历史生成oracle：私有LCG的独立状态；不调用被测roll/unitValue/倍率来产生期望。
local function oracleRNG(seed)
    local rng = { state = seed, calls = 0 }
    function rng.draw()
        rng.state = rng.state * 48271 % 2147483647
        rng.calls = rng.calls + 1
        return rng.state / 2147483647
    end
    return rng
end
local AFFIX_QUALITY = {
    { 100, 1, 1.2 }, { 80, 1.2, 1.5 }, { 60, 1.5, 1.9 }, { 40, 1.9, 2.4 }, { 20, 2.4, 3 },
}
local function oracleAffixes(rng, count, maxQuality, level, strength, double)
    local pool, chosen, result = copy(ORDINARY), {}, {}
    for i = 1, count do chosen[i] = table.remove(pool, math.floor(rng.draw() * #pool) + 1) end
    local total = 0
    for i = 1, maxQuality do total = total + assert(AFFIX_QUALITY[i], "缺少历史词缀品质")[1] end
    for i, row in ipairs(chosen) do
        local roll, accumulated, tier = rng.draw() * total, 0, maxQuality
        for q = 1, maxQuality do
            accumulated = accumulated + assert(AFFIX_QUALITY[q], "缺少历史词缀品质")[1]
            if roll <= accumulated then tier = q break end
        end
        local q = assert(AFFIX_QUALITY[tier], "缺少历史词缀品质")
        local multiplier = q[2] + rng.draw() * (q[3] - q[2])
        local value = row[3] * multiplier * (1 + (level - 1) * 0.05) * strength * double
        if row[4] == "int" then value = math.floor(value + 0.5) end
        result[i] = { key = row[1], quality = tier, value = value }
    end
    return result
end
local PHYSICAL = { "physPen", "physDmgBonus", "atkSpeed", "critRate", "critDmg", "hitValue" }
local MAGICAL = { "magPen", "magDmgBonus", "atkSpeed", "critRate", "critDmg", "hitValue" }
local HEALING = { "healBonus", "healCritRate", "healCritDmg", "spi", "atkSpeed" }
local DEFENSE = { "armor", "energyShield", "dodge", "atkSpeed", "hpBonus", "esBonus", "abnormalRes", "vit" }
local TEMPLATES = {
    { id = "W1", rows = { { "physAtk", 6.28 }, { "hitValue", 0.8 }, { "atkSpeed", 1.6 } }, pool = PHYSICAL },
    { id = "W25", rows = { { "magAtk", 12.58 }, { "magPen", 2.57 }, { "magDmgBonus", 4.3 } }, pool = MAGICAL, double = 2 },
    { id = "A7", rows = { { "maxHp", 101 }, { "armor", 0.87 }, { "energyShield", 6.07 } }, pool = DEFENSE, defense = true },
    { id = "O19", rows = { { "energyShield", 31.42 }, { "magBlockRate", 1.2 }, { "magPen", 1.26 } }, pool = MAGICAL },
    { id = "W72", rows = { { "healAmount", 18.86 }, { "healBonus", 15.4 } }, pool = HEALING },
    { id = "C15", rows = { { "luk", 4.28 }, { "critDmg", 12.9 } }, pool = { "atkSpeed", "critRate", "critDmg", "hitValue" } },
}
local function oracleSecondary(rng, template)
    local pool, stats = copy(template.pool), {}
    for i = 2, #template.rows do
        local total = 0
        for _, key in ipairs(pool) do
            total = total + (template.defense and (key == "armor" or key == "energyShield" or key == "dodge") and 3 or 1)
        end
        local roll, accumulated, selected = rng.draw() * total, 0, #pool
        for j, key in ipairs(pool) do
            accumulated = accumulated + (template.defense and (key == "armor" or key == "energyShield" or key == "dodge") and 3 or 1)
            if roll < accumulated then selected = j break end
        end
        local key, original = table.remove(pool, selected), template.rows[i]
        stats[i - 1] = { key, original[2] * UNITS[original[1]] / UNITS[key] }
    end
    return { version = 1, stats = stats }
end
local function oracleRaw(template, level, strength, roll)
    local result = {}
    for i, original in ipairs(template.rows) do
        local row = i > 1 and roll and roll.stats[i - 1] or original
        local value = row[2] * (1 + (level - 1) * 0.05) * strength
        -- 历史raw本来是int就保留四舍五入；不能要求主HP生成保存小数。
        if row[1] == "maxHp" then value = math.floor(value + 0.5) end
        result[i] = { row[1], value }
    end
    return result
end
local function rowsNear(actual, expected, label)
    check(type(actual) == "table" and #actual == #expected, label .. " 行数")
    for i, row in ipairs(expected) do
        local a = actual and actual[i]
        check(a and a[1] == row[1], label .. " key/顺序" .. i)
        eq(a and a[2], row[2], label .. " raw值" .. i)
    end
end
local function testRawGenerationAndPersistence(f)
    -- 一次抽全45种保证六个白名单都实际经过生产raw词缀生成；含HP旧取整、双手旧倍率。
    for _, level in ipairs({ 1, 100, 200 }) do
        for _, double in ipairs({ 1, 2 }) do
            local seed = 100003 + level + double
            local rng = oracleRNG(seed)
            local wanted = oracleAffixes(rng, 45, 5, level, 1.5, double)
            f.math.randomseed(seed)
            local actual = f.ES.rollAffixes(45, 5, level, {}, 1.5, double == 2 and "twohand" or "onehand")
            check(#actual == 45, "真实raw生成覆盖45种")
            for i, row in ipairs(wanted) do
                check(actual[i].key == row.key and actual[i].quality == row.quality, "历史词缀key/品质/顺序")
                eq(actual[i].value, row.value, "历史词缀raw不烘焙F " .. row.key)
            end
            check(f.rng.calls == rng.calls and f.rng.state == rng.state, "全词缀历史RNG状态/次数不变")
        end
    end
    for _, template in ipairs(TEMPLATES) do
        check(same(f.EC.ITEMS[template.id].stats, template.rows), template.id .. " 模板raw不改")
        for _, level in ipairs({ 1, 50, 100, 200, 9999 }) do
            for _, quality in ipairs({ 1, 4, 6 }) do
                for _, legacy in ipairs({ false, true }) do
                    generationCases = generationCases + 1
                    local strength, maxQuality, count = 1 + (quality - 1) * 0.1, quality == 6 and 5 or 3, quality == 1 and 0 or 2
                    local seed = 20261024 + generationCases
                    local rng = oracleRNG(seed)
                    local wantedAffixes = oracleAffixes(rng, count, maxQuality, level, strength, template.double or 1)
                    local roll = not legacy and oracleSecondary(rng, template) or nil
                    local raw = oracleRaw(template, level, strength, roll)
                    f.math.randomseed(seed)
                    local equip = f.ES.generate(template.id, level, quality, { legacySecondary = legacy })
                    local label = template.id .. "/lv" .. level .. "/q" .. quality .. (legacy and "/legacy" or "/v1")
                    check(f.rng.calls == rng.calls and f.rng.state == rng.state, label .. " 历史生成RNG精确一致")
                    rowsNear(equip.baseStats, raw, label)
                    check((legacy and equip.secondaryRoll == nil) or (not legacy and equip.secondaryRoll.version == 1), label .. " 新旧版本保持")
                    if roll then rowsNear(equip.secondaryRoll.stats, roll.stats, label .. " 未放大保存副基值") end
                    for i, row in ipairs(wantedAffixes) do
                        check(equip.affixes[i].key == row.key and equip.affixes[i].quality == row.quality, label .. " 词缀身份原样")
                        eq(equip.affixes[i].value, row.value, label .. " 词缀raw原样")
                        equip.affixes[i].ascBonus = 0.013 + i * 0.125
                    end
                    equip.ascendLevel = 31
                    noRNG(f, function()
                        local rawSnapshot, rollSnapshot, affixSnapshot = copy(equip.baseStats), copy(equip.secondaryRoll), copy(equip.affixes)
                        for pass = 1, 3 do
                            local before = copy(equip)
                            local entries = f.ES.computeModifierEntries(equip, 1.55)
                            for i in ipairs(rawSnapshot) do
                                eq(entries[i].flat, baseExpected(equip, i, 1.55, 31), label .. " JSON出口仅一次F")
                            end
                            local lean = f.ES.dehydrate(equip)
                            check(same(equip, before), label .. " 脱水不写源实例")
                            check(lean.baseStats == nil and lean.name == nil and lean.slot == nil, label .. " 仍为原精简协议")
                            check(lean.flatStatGrowth == nil and lean.flatGrowthVersion == nil and lean.effectiveBaseStats == nil,
                                label .. " 无成长迁移/生效缓存字段")
                            equip = f.ES.hydrate(cjson.decode(cjson.encode(lean)))
                            rowsNear(equip.baseStats, rawSnapshot, label .. " JSON重建pass" .. pass)
                            if rollSnapshot then rowsNear(equip.secondaryRoll.stats, rollSnapshot.stats, label .. " JSON副基值")
                            else check(equip.secondaryRoll == nil, label .. " 旧精简不补roll") end
                            for i, row in ipairs(affixSnapshot) do
                                eq(equip.affixes[i].value, row.value, label .. " JSON词缀raw不写F")
                                eq(equip.affixes[i].ascBonus, row.ascBonus, label .. " JSON旧bonus不预乘F")
                                eq(f.ES.effectiveAffixValue(equip, equip.affixes[i]), affixExpected(equip, row), label .. " JSON词缀出口")
                            end
                            local hydrated = copy(equip)
                            f.ES.hydrate(equip)
                            f.ES.computeModifierEntries(equip, 1.55)
                            check(same(equip, hydrated), label .. " 重复水合与读取幂等")
                        end
                    end, label .. " 重复JSON/水合/读取")
                end
            end
        end
    end
    check(generationCases == 180, "6模板×5等级×3品质×新旧=180生成/JSON组合")
    -- 完整旧缓存与旧精简分开测：完整缓存不因新F改raw/换引用，精简仍按原模板重建。
    local cached = { templateId = "W1", level = 200, quality = 4, ascendLevel = 31, affixMult = 2.3,
        baseStats = { { "physAtk", 123.375 }, { "hpRegen", 7.125 }, { "atkHeal", 2.625 } },
        affixes = { affix(f, "maxHp", 1, 25000.375) } }
    local rawRef, before = cached.baseStats, copy(cached.baseStats)
    noRNG(f, function()
        f.ES.hydrate(cached)
        local hydrated = copy(cached)
        for _ = 1, 5 do
            f.ES.hydrate(cached)
            local entries = f.ES.computeModifierEntries(cached, 1.55)
            eq(entries[1].flat, 123.375 * 2.55 * 2.4, "完整旧缓存主值只在出口成长")
            eq(entries[4].flat, (2.3 + 25000.375) * 2.8, "旧低raw/极高bonus不裁剪")
            check(cached.baseStats == rawRef and same(cached.baseStats, before) and same(cached, hydrated),
                "完整旧缓存读取不迁移/不改raw/不换引用")
        end
    end, "完整旧缓存")
    local legacyLean = { templateId = "W1", level = 200, quality = 4, ascendLevel = 31,
        affixMult = 2.3, affixes = {} }
    for i, key in ipairs(FLAT_KEYS) do
        legacyLean.affixes[i] = { affixId = f.AC.BY_KEY[key].id, quality = 3,
            value = 1.125, ascBonus = 25000.375 + i }
    end
    local expectedLean, lean = copy(legacyLean), copy(legacyLean)
    noRNG(f, function()
        for pass = 1, 5 do
            local equip = f.ES.hydrate(cjson.decode(cjson.encode(lean)))
            check(equip.secondaryRoll == nil, "旧精简六key不补secondaryRoll")
            for i, key in ipairs(FLAT_KEYS) do
                eq(equip.affixes[i].value, 1.125, key .. " 旧精简不放大raw")
                eq(equip.affixes[i].ascBonus, 25000.375 + i, key .. " 旧精简不裁剪/放大bonus")
                eq(f.ES.effectiveAffixValue(equip, equip.affixes[i]),
                    (1.125 * 2.3 + 25000.375 + i) * factor(key, 200), key .. " 旧精简出口一次F")
            end
            local beforeEquip = copy(equip)
            lean = f.ES.dehydrate(equip)
            check(same(lean, expectedLean) and same(equip, beforeEquip), "旧精简原协议精确相同pass" .. pass)
        end
        check(same(legacyLean, expectedLean), "旧精简输入不迁移")
        -- 固定一份合法v1防御副属性，确保energyShield随机副的持久化不依赖碰巧抽中。
        local v1 = { templateId = "A7", level = 200, quality = 4, ascendLevel = 31,
            secondaryRoll = { version = 1, stats = { { "energyShield", 3.75 }, { "hpBonus", 4.25 } } },
            affixes = {} }
        f.ES.hydrate(v1)
        local rawSnapshot, savedRoll = copy(v1.baseStats), copy(v1.secondaryRoll)
        eq(v1.baseStats[1][2], 1438, "v1主HP保持历史raw整数四舍五入")
        eq(v1.baseStats[2][2], 3.75 * 10.95 * 1.3, "v1护盾副raw仅乘历史等级品质")
        for _ = 1, 5 do
            local entries = f.ES.computeModifierEntries(v1, 1.55)
            eq(entries[2].flat, v1.baseStats[2][2] * 1.8 * 3.5, "v1护盾副升阶16次后再F")
            v1 = f.ES.hydrate(cjson.decode(cjson.encode(f.ES.dehydrate(v1))))
            rowsNear(v1.baseStats, rawSnapshot, "固定v1多次JSON不改raw")
            check(same(v1.secondaryRoll, savedRoll), "固定v1多次JSON保存基值/顺序不变")
        end
    end, "显式旧精简六key/固定v1护盾副JSON")
end

local function testConversionMatrix(f)
    check(#f.AC.AFFIXES == 45, "正式普通词条数45")
    for i, row in ipairs(ORDINARY) do
        check(f.AC.AFFIXES[i].key == row[1], "45key固定顺序 " .. row[1])
        if i <= 6 then eq(f.Secondary.unitValue(row[1]), row[2], row[1] .. " 六围完整派生静态价值不吃F")
        elseif row[1] == "dropLuck" then
            eq(f.AD.META.dropLuck.valueModel, 0, "幸运战力VM仍0")
            eq(f.AD.META.dropLuck.refineValueModel, 1, "幸运洗练VM仍1")
        else eq(f.Secondary.unitValue(row[1]), row[2], row[1] .. " 静态VM不改") end
    end
    noRNG(f, function()
        for _, level in ipairs({ 50, 100, 200 }) do
            for i, from in ipairs(ORDINARY) do
                for j, to in ipairs(ORDINARY) do
                    conversionPairs = conversionPairs + 1
                    local bonus = 0.013 + i * 0.037 + j * 0.001
                    local old, target = affix(f, from[1], 0.001, bonus), affix(f, to[1], 98765, 999)
                    local beforeOld, beforeTarget = copy(old), copy(target)
                    local equip = { level = level, ascendLevel = 100, affixMult = 17, heroLevel = 9999 }
                    local beforeEquip = copy(equip)
                    local actual = f.ES.convertAscBonusForRefine(old, target, equip)
                    local wanted = convertedExpected(old, target, level)
                    local label = "lv" .. level .. "/" .. old.key .. "->" .. target.key
                    eq(actual, wanted, label .. " 独立线性预算比")
                    eq(actual and actual * to[2] * factor(target.key, level), bonus * from[2] * factor(old.key, level),
                        label .. " 生效线性预算守恒（暴率曲线前）")
                    local back = f.ES.convertAscBonusForRefine(affix(f, target.key, 1e6, actual), affix(f, old.key, 1), equip)
                    eq(back, bonus, label .. " roundtrip无套利/不取整")
                    if i == j then check(actual == bonus, label .. " 同key严格原量") end
                    check(same(old, beforeOld) and same(target, beforeTarget) and same(equip, beforeEquip), label .. " 三输入不修改")
                end
            end
        end
        -- 旧二参调用缺少上下文时按Lv1；全2025对验证兼容，不能偷读玩家等级。
        for _, from in ipairs(ORDINARY) do
            for _, to in ipairs(ORDINARY) do
                local old, target = affix(f, from[1], 1, 0.013), affix(f, to[1], 9999)
                local wanted = convertedExpected(old, target, 1)
                eq(f.ES.convertAscBonusForRefine(old, target), wanted, "nil上下文兼容 " .. old.key .. "->" .. target.key)
                eq(f.ES.convertAscBonusForRefine(old, target, {}), wanted, "缺等级上下文兼容 " .. old.key .. "->" .. target.key)
            end
        end
        for _, invalidLevel in ipairs({ -100, "bad-level", 0 / 0, math.huge, -math.huge }) do
            eq(f.ES.convertAscBonusForRefine(affix(f, "maxHp", 1, 16), affix(f, "str", 1), { level = invalidLevel }),
                0.32, "非法等级换算按Lv1")
        end
        eq(f.ES.convertAscBonusForRefine(affix(f, "maxHp", 1, 16), affix(f, "str", 1), { level = "100" }),
            0.576, "数字串等级换算按Lv100")
        check(f.ES.convertAscBonusForRefine(nil, affix(f, "str", 1), { level = 200 }) == nil, "缺源词条不转移")
        check(f.ES.convertAscBonusForRefine(affix(f, "str", 1, 2), nil, { level = 200 }) == nil, "缺目标词条不转移")
        for _, bonus in ipairs({ 0, -1, math.huge, -math.huge, 0 / 0 }) do
            check(f.ES.convertAscBonusForRefine(affix(f, "maxHp", 1, bonus), affix(f, "str", 1), { level = 200 }) == nil,
                "非法bonus不转移 " .. tostring(bonus))
        end
        check(f.ES.convertAscBonusForRefine(affix(f, "maxHp", 1), affix(f, "str", 1), { level = 200 }) == nil,
            "未投入bonus不凭空产生")
        check(f.ES.convertAscBonusForRefine(affix(f, "finalHpBonus", 1, 3), affix(f, "maxHp", 1), { level = 200 }) == nil,
            "腐化源不转普通bonus")
        check(f.ES.convertAscBonusForRefine(affix(f, "maxHp", 1, 3), affix(f, "finalHpBonus", 1), { level = 200 }) == nil,
            "腐化目标不接普通bonus")
        for _, level in ipairs({ 50, 100, 200 }) do
            local bonus = 0.013
            for _ = 1, 100 do
                local hp = f.ES.convertAscBonusForRefine(affix(f, "str", 1, bonus), affix(f, "maxHp", 1), { level = level })
                local back = f.ES.convertAscBonusForRefine(affix(f, "maxHp", 1, hp), affix(f, "str", 1), { level = level })
                eq(hp, 0.65 / factor("maxHp", level), "整数HP目标仍保存原始小数投入")
                eq(back, 0.013, "反复换属性无舍入套利")
                bonus = back
            end
        end
    end, "45x45x3全线性预算/往返/兼容")
    check(conversionPairs == 6075, "50/100/200级各45x45共6075换属性组合")
end

local function put(f, rows, level, id)
    local equip = { templateId = id or "W1", level = level, quality = 4,
        ascendLevel = 31, affixMult = 2.3, affixes = rows }
    f.ES.hydrate(equip)
    f.ES.addToInventory(f.modules.equipment, equip)
    return equip
end
local function preview(f, equip, resource, locks)
    local ok, err, result = f.BS.RefineEquip(1, equip.seq, resource, locks)
    check(ok and result and result.refinePreview, "真实RefineEquip成功 " .. tostring(err))
    assert(ok and result and result.refinePreview, "真实预览不可缺")
    return result
end
local function replace(f, equip)
    local ok, err, result = f.BS.RefineReplace(1, equip.seq)
    check(ok and result and result.refineReplaced, "真实RefineReplace成功 " .. tostring(err))
    assert(ok and result, "真实替换不可缺")
    return result
end
-- 不替换随机生成函数；搜索可重放seed，再令真实服务重放同一次生产roll。
local function seedForTarget(f, equip, targetKey)
    for attempt = 1, 300 do
        local seed = (attempt * 104729 + 20261024) % 2147483647
        f.math.randomseed(seed)
        local rolled = f.ES.rollAffixesForRefine(equip.affixes, nil, 3, equip.level, 1.3, equip.grip)
        if rolled[1].key == targetKey then
            local expected, calls, state = copy(rolled), f.rng.calls, f.rng.state
            f.math.randomseed(seed)
            return expected, calls, state
        end
    end
    error("真实随机词缀找不到目标seed " .. targetKey)
end
local function testRealPreviewReplace(f)
    local pairsToTest = {
        { "maxHp", "str" }, { "str", "energyShield" }, { "energyShield", "physAtk" },
        { "physAtk", "hpRegen" }, { "hpRegen", "magAtk" }, { "magAtk", "atkHeal" },
        { "atkHeal", "maxHp" }, { "maxHp", "critRate" }, { "critRate", "energyShield" }, { "vit", "maxHp" },
    }
    for _, level in ipairs({ 50, 100, 200 }) do
        for _, pair in ipairs(pairsToTest) do
            local equip = put(f, { affix(f, pair[1], 111.125, 0.013) }, level)
            local before, base, roll = copy(equip.affixes), copy(equip.baseStats), copy(equip.secondaryRoll)
            local rolled, calls, state = seedForTarget(f, equip, pair[2])
            local wanted = convertedExpected(before[1], rolled[1], level)
            local originalConvert = f.ES.convertAscBonusForRefine
            local spy = { preflight = 0, transfer = 0, context = true }
            -- 只旁观第三参并调用原实现，不伪造任何业务返回值；私有模块，结束即恢复。
            f.ES.convertAscBonusForRefine = function(old, target, context)
                if context ~= equip then spy.context = false end
                if f.rng.calls == 0 then spy.preflight = spy.preflight + 1 else spy.transfer = spy.transfer + 1 end
                return originalConvert(old, target, context)
            end
            local ran, result = pcall(preview, f, equip)
            f.ES.convertAscBonusForRefine = originalConvert
            assert(ran, tostring(result))
            local p, label = result.refinePreview, "真实lv" .. level .. "/" .. pair[1] .. "->" .. pair[2]
            check(spy.preflight == 45 and spy.transfer == 1 and spy.context, label .. " 预校验与真实转移均传同一装备第三参")
            check(f.rng.calls == calls and f.rng.state == state, label .. " 真实roll完整RNG与试算重放一致")
            check(same(equip.affixes, before) and same(equip.baseStats, base) and same(equip.secondaryRoll, roll), label .. " preview不改现有raw")
            check(p[1].key == pair[2], label .. " 真实随机目标key")
            eq(p[1].value, rolled[1].value, label .. " preview保留真实roll raw")
            eq(p[1].ascBonus, wanted, label .. " preview旧投入只转一次")
            eq(f.ES.effectiveAffixValue(equip, p[1]), affixExpected(equip, p[1]), label .. " preview生效一次F/旧暴击曲线")
            local currencyBeforeReplace = copy(f.modules.currency)
            noRNG(f, function() replace(f, equip) end, label .. " replace")
            eq(equip.affixes[1].ascBonus, wanted, label .. " replace沿用preview不重复换算")
            check(same(equip.affixes, p) and same(f.modules.currency, currencyBeforeReplace), label .. " replace不二次收费/重随")
            local entries = f.ES.computeModifierEntries(equip, 1.55)
            eq(entries[#equip.baseStats + 1].flat, affixExpected(equip, equip.affixes[1]), label .. " 实际modifier")
            check(not f.BS.RefineReplace(1, equip.seq), label .. " preview消费后不可重复replace")
        end
    end
    -- 未确认的新预览必须仍从旧装转移；弃掉/清理也不改变raw或投入。
    local equip = put(f, { affix(f, "maxHp", 1, 16) }, 200)
    local before = copy(equip.affixes)
    seedForTarget(f, equip, "str")
    local first = preview(f, equip).refinePreview
    seedForTarget(f, equip, "energyShield")
    local second = preview(f, equip).refinePreview
    eq(first[1].ascBonus, 0.896, "未确认第一预览HP->str")
    eq(second[1].ascBonus, 3.84, "第二预览从原HP投入转ES，不从第一份叠算")
    check(same(equip.affixes, before), "重复preview不改原词条")
    f.BS.Cleanup(1)
    check(not f.BS.RefineReplace(1, equip.seq) and same(equip.affixes, before), "取消preview不应用新bonus")
end

local function testLocksAndStone(f)
    local equip = put(f, { affix(f, "maxHp", 1, 0.375), affix(f, "finalPhysAtkBonus", 7.125),
        affix(f, "energyShield", 2, 0.625) }, 200)
    local before, base = copy(equip.affixes), copy(equip.baseStats)
    local p = preview(f, equip, nil, { 1 }).refinePreview
    check(same(p[1], before[1]), "真实锁槽保留key/raw/bonus精确原量")
    check(same(p[2], before[2]), "真实腐化中间槽在洗练preview原样")
    eq(p[3].ascBonus, convertedExpected(before[3], p[3], 200), "锁索引跨腐化槽映射正确")
    check(same(equip.affixes, before), "混合锁preview不改原装备")
    replace(f, equip)
    check(same(equip.affixes, p) and same(equip.baseStats, base), "混合锁replace保留基础raw")
    local stale = preview(f, equip).refinePreview
    check(f.BS.hasPendingRefine(1, equip.seq), "洗练石前有真实待替换preview")
    local originalAffixes, currency = copy(equip.affixes), copy(f.modules.currency)
    local count = equip.refineCount or 0
    -- 同key石头忽略旧锁，包括所有索引；低第一槽改善，极高最后槽触发keepHigher。
    equip.affixes[1].value, equip.affixes[3].value = 0.001, 1e9
    originalAffixes = copy(equip.affixes)
    local plain = { copy(originalAffixes[1]), copy(originalAffixes[3]) }
    f.math.randomseed(1022)
    local wanted = f.ES.rerollAffixValuesWithLocks(plain, 3, 200, 1.3, equip.grip, nil)
    local calls, state = f.rng.calls, f.rng.state
    f.math.randomseed(1022)
    local result = preview(f, equip, "enhanceStone", { 1, 2, 3 })
    check(result.autoReplaced and equip.affixes == result.refinePreview, "真实洗练石同key立即替换")
    check(f.rng.calls == calls and f.rng.state == state, "洗练石忽略锁后RNG与真实无锁roll一致")
    for i, compact in ipairs({ 1, 3 }) do
        check(equip.affixes[compact].key == originalAffixes[compact].key, "洗练石保持原key")
        eq(equip.affixes[compact].ascBonus, originalAffixes[compact].ascBonus, "洗练石同key不折算/不预乘F")
        eq(equip.affixes[compact].value, math.max(originalAffixes[compact].value, wanted[i].value), "洗练石raw沿用keepHigher")
        eq(f.ES.effectiveAffixValue(equip, equip.affixes[compact]), affixExpected(equip, equip.affixes[compact]), "洗练石实际消费F一次")
    end
    check(same(equip.affixes[2], originalAffixes[2]), "洗练石保留腐化槽原值")
    check(not f.BS.hasPendingRefine(1, equip.seq) and not f.BS.RefineReplace(1, equip.seq), "洗练石清理旧preview防止覆盖")
    check(not same(equip.affixes, stale), "洗练石不是提交旧preview")
    local expectedCurrency = copy(currency)
    expectedCurrency.enhanceStone = expectedCurrency.enhanceStone - 1
    check(same(f.modules.currency, expectedCurrency), "洗练石只扣一石不扣精粹")
    eq(equip.refineCount, math.min(20, count + 1), "洗练石只增加一次次数")
    check(same(equip.baseStats, base), "洗练石不改基础raw")
end

local function testCorruptCleanse(f)
    for _, key in ipairs({ "maxHp", "energyShield", "physAtk", "magAtk" }) do
        local equip = put(f, { affix(f, key, 1000.125, 0.375) }, 200)
        local before, base, mult = copy(equip.affixes[1]), copy(equip.baseStats), equip.affixMult
        local initialEffective = affixExpected(equip, before)
        local result = preview(f, equip, "corruptStone")
        check(result.autoReplaced and f.AC.isCorruptAffix(equip.affixes[1]), key .. " 真腐化直接应用")
        check(equip.affixes[1].ascBonus == nil, key .. " 腐化不持有普通bonus")
        -- Lv200模板下限=1.7*10.95=18.615，四个1000.125源的等价预算均高于它。
        local wanted = 1000.125 * UNITS[key] / 0.6 * 1.8
        eq(equip.affixes[1].value, wanted, key .. " 腐化raw仍用原静态预算，不烘焙F/affixMult/bonus")
        eq(f.ES.effectiveAffixValue(equip, equip.affixes[1]), wanted, key .. " 腐化生效不乘F")
        check(same(equip.corruptRevert.patches[1][3], before), key .. " c快照保存原raw与bonus")
        noRNG(f, function()
            local restored = f.ES.hydrate(cjson.decode(cjson.encode(f.ES.dehydrate(equip))))
            restored.seq = equip.seq
            f.modules.equipment.inventory[tostring(equip.seq)] = restored
            equip = restored
            eq(equip.affixes[1].value, wanted, key .. " JSON不迁移腐化值")
            local cleaned = preview(f, equip, "sacredStone")
            check(cleaned.autoReplaced and same(equip.affixes[1], before), key .. " 真净化精确还原原key/raw/bonus")
            check(equip.corruptCount == nil and equip.corruptRevert == nil and equip.corruptBaseMult == nil, key .. " 净化清理诅咒状态")
            rowsNear(equip.baseStats, base, key .. " 净化还原原基础raw")
            eq(equip.affixMult, mult, key .. " 净化不改栏位倍率")
            eq(f.ES.effectiveAffixValue(equip, equip.affixes[1]), initialEffective, key .. " 净化恢复原生效值，不二次F")
        end, key .. " 净化/JSON")
    end
end

function Start()
    print(PREFIX .. "start isolated whitelist / private RNG / memory PDM+Task / no main or player save")
    local groups = {
        { "六key等级边界", testBoundaries }, { "主副升阶预览与生效顺序", testEffectiveAndPreview },
        { "非白名单与腐化固有排除", testExclusions }, { "历史生成RNG与新旧JSON", testRawGenerationAndPersistence },
        { "全45x45线性预算", testConversionMatrix }, { "真实洗练预校验preview-replace", testRealPreviewReplace },
        { "锁定腐化槽与同key洗练石", testLocksAndStone }, { "真实腐化净化原值回归", testCorruptCleanse },
    }
    for _, group in ipairs(groups) do
        -- 各组重新建立私有模块状态；异常不能污染后续组，也不会泄漏到宿主生产模块。
        local ok, why = pcall(function()
            local f = fixture()
            group[2](f)
            f.BS.Cleanup(1)
            if group[2] == testRealPreviewReplace or group[2] == testLocksAndStone or group[2] == testCorruptCleanse then
                check((f.notifications.dirty.equipment or 0) > 0 and (f.notifications.dirty.currency or 0) > 0
                    and f.notifications.flushes > 0 and f.notifications.progress > 0,
                    group[1] .. " 真实服务内存通知边界已走到")
            end
        end)
        if not ok then check(false, group[1] .. " exception: " .. tostring(why)) end
        print(PREFIX .. "完成 " .. group[1])
    end
    print(PREFIX .. "RESULT " .. (#failures == 0 and "ALL PASS" or "FAIL")
        .. " assertions=" .. checks .. " conversion_pairs=" .. conversionPairs
        .. " generation_cases=" .. generationCases .. " failure_count=" .. #failures)
    engine:Exit()
end
