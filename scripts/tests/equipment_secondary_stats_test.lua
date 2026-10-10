-- 基于现有refine_cost_fixed_test/battle_lab_boundary_test的独立Runtime测试骨架。
-- cd /workspace && ./.cli/UrhoXRuntime tests/equipment_secondary_stats_test.lua \
--   -tapcode_dir=. -tool_mode -graphicsheadless
-- 不读玩家存档、不发奖；汇总包含failure count，退出0不等于测试通过。
local Eq = require("systems.EquipmentSystem")
local Secondary = require("systems.EquipmentSecondaryStats")
local EC = require("config.EquipmentConfig")
local AD = require("systems.AttributeDef")
local BC = require("config.BlacksmithConfig")
local Power = require("systems.EquipmentPower")
local PREFIX = "[equipment_secondary_stats] "
local checks, failures = 0, {}
local function check(ok, text)
    checks = checks + 1
    if not ok then failures[#failures + 1] = text; print(PREFIX .. "[FAIL] " .. text) end
end
local function near(a, b)
    return type(a) == "number" and type(b) == "number" and a == a and b == b
        and math.abs(a - b) <= math.max(1, math.abs(b)) * 1e-9
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return type(a) == "number" and near(a, b) or a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
-- 独立价值oracle，不调用被测unitValue；pct/100，六围仅按派生不直用5。
local baseKeys = {}
for _, key in ipairs(AD.BASE_STATS) do baseKeys[key] = true end
local function unitValue(key)
    if baseKeys[key] then
        local total = 0
        for _, row in ipairs(AD.DERIVATIVES[key]) do total = total + row.perPoint * unitValue(row.attr) end
        return total
    end
    local meta = AD.META[key]
    return meta and meta.valueModel / (meta.dataType == AD.TYPE_PCT and 100 or 1) or 0
end
local function set(list)
    local result = {}
    for _, key in ipairs(list) do result[key] = true end
    return result
end
local PHYS = set({ "physPen", "physDmgBonus", "atkSpeed", "critRate", "critDmg", "hitValue" })
local MAG = set({ "magPen", "magDmgBonus", "atkSpeed", "critRate", "critDmg", "hitValue" })
local HEAL = set({ "healBonus", "healCritRate", "healCritDmg", "spi", "atkSpeed" })
local COMMON = set({ "atkSpeed", "critRate", "critDmg", "hitValue" })
local DEF = set({ "armor", "energyShield", "dodge", "atkSpeed", "hpBonus", "esBonus", "abnormalRes", "vit" })
local function expectedPool(tpl)
    local main = tpl.stats[1][1]
    if tpl.slot == "weapon" then
        return main == "physAtk" and PHYS or main == "magAtk" and MAG or HEAL
    end
    if tpl.slot == "offhand" then
        return (tpl.type == "魔典" or tpl.type == "法珠") and MAG or DEF
    end
    if tpl.slot ~= "accessory" then return DEF end
    if main == "str" or main == "physAtk" or main == "physPen" then return PHYS end
    if main == "int" or main == "magAtk" or main == "magPen" then return MAG end
    if main == "spi" or main == "healAmount" or main == "hpRegen" then return HEAL end
    if main == "agi" or main == "luk" or main == "hitValue" then return COMMON end
    return DEF
end
local function oldStats(tpl, level, quality, corrupt)
    local stats = {}
    for index, row in ipairs(tpl.stats) do
        local value = row[2] * (1 + (level - 1) * EC.LEVEL_SCALE) * EC.QUALITY[quality].baseStrength * (corrupt or 1)
        if AD.META[row[1]].dataType == AD.TYPE_INT then value = math.floor(value + 0.5) end
        stats[index] = { row[1], value }
    end
    return stats
end
local function noRNG(fn, label)
    math.randomseed(101010)
    local expected = math.random()
    math.randomseed(101010)
    fn()
    check(math.random() == expected, label .. "不消耗RNG")
end
local function testTemplates()
    local total, zero = 0, 0
    for _, slot in ipairs(EC.SLOTS) do
        for _, id in ipairs(EC.BY_SLOT[slot]) do
            total = total + 1
            local tpl = EC.ITEMS[id]
            local snapshot = copy(tpl)
            local count = #tpl.stats - 1
            if count == 0 then zero = zero + 1 end
            for quality = 1, #EC.QUALITY do
                for _, level in ipairs({ 1, tpl.levelRange[1], 9999 }) do
                    math.randomseed(total * 10000 + quality * 10 + level)
                    local item = Eq.generate(id, level, quality)
                    local label = id .. "/q" .. quality .. "/lv" .. level
                    check(item and item.secondaryRoll and item.secondaryRoll.version == 1, label .. "有新字段")
                    if item and item.secondaryRoll then
                        local roll = item.secondaryRoll
                        check(#roll.stats == count and #item.baseStats == #tpl.stats, label .. "条数不增减")
                        check(same(item.baseStats[1], oldStats(tpl, level, quality)[1]), label .. "主属性完全不变")
                        local seen = { [tpl.stats[1][1]] = true }
                        local pool = expectedPool(tpl)
                        for index, row in ipairs(roll.stats) do
                            local key, value = row[1], row[2]
                            check(not seen[key] and pool[key], label .. "副属性池合法且不重复主/副")
                            check(AD.META[key] and AD.META[key].dataType ~= AD.TYPE_INT
                                and finite(value) and unitValue(key) > 0, label .. "仅float/pct正价值")
                            seen[key] = true
                            local original = tpl.stats[index + 1]
                            check(near(value * unitValue(key), original[2] * unitValue(original[1])), label .. "逐槽预算守恒")
                            check(near(item.baseStats[index + 1][2], value * (1 + (level - 1) * EC.LEVEL_SCALE)
                                * EC.QUALITY[quality].baseStrength), label .. "倍率仅一次且不额外双手x2")
                        end
                        local lean = Eq.dehydrate(item)
                        check(lean.secondaryRoll ~= roll and lean.secondaryRoll.stats ~= roll.stats, label .. "脱水深拷贝")
                        local restored = Eq.hydrate(cjson.decode(cjson.encode(lean)))
                        check(same(restored.secondaryRoll, roll) and same(restored.baseStats, item.baseStats), label .. "JSON往返保序保值")
                    end
                end
            end
            check(same(tpl, snapshot), id .. "不污染模板")
        end
    end
    check(total == 357 and total == EC.TOTAL_COUNT, "357模板全部覆盖")
    check(zero == 6, "6个零副饰品不新增")
    print(PREFIX .. "模板覆盖=" .. total .. "，品质=6，等级样本=3，零副饰品=" .. zero)
end
local function testVariantsAndAffixes()
    for _, id in ipairs({ "W1", "W7", "W13", "W49", "W55", "W67", "O13", "O25", "A55", "C2", "C8", "C20" }) do
        local keys = {}
        for seed = 1, 32 do
            math.randomseed(seed)
            local item = Eq.generate(id, 81, 6)
            local parts = {}
            for _, row in ipairs(item.secondaryRoll.stats) do parts[#parts + 1] = row[1] end
            keys[table.concat(parts, ",")] = true
        end
        local variants = 0
        for _ in pairs(keys) do variants = variants + 1 end
        check(variants > 1, id .. "多seed有变体")
    end
    -- 原词缀生成精确A/B：legacy path保留原抽取链，新副在它之后才抽。
    for _, id in ipairs({ "W1", "W7", "W49", "W67", "C1", "A1" }) do
        local tpl = EC.ITEMS[id]
        for quality = 1, 6 do
            for seed = 1, 12 do
                math.randomseed(seed)
                local expected = Eq.rollAffixes(EC.QUALITY[quality].affixCount,
                    EC.QUALITY[quality].maxAffixQuality, 81, {}, EC.QUALITY[quality].randomStrength, tpl.grip)
                local nextRandom = math.random()
                math.randomseed(seed)
                local old = Eq.generate(id, 81, quality, { legacySecondary = true })
                check(old.secondaryRoll == nil and same(old.affixes, expected), "legacy原词缀seed链")
                check(math.random() == nextRandom, "legacy标记不消费额外RNG")
                math.randomseed(seed)
                local new = Eq.generate(id, 81, quality)
                check(same(new.affixes, expected), "新副抽取不改变本件原词缀seed结果")
            end
        end
    end
    noRNG(function() Eq.generate("C1", 1, 1) end, "零副零affix真实生成")
    for seed = 1, 12 do
        math.randomseed(seed)
        local old = Eq.generateRandom(81, 5, { legacySecondary = true })
        check(old.secondaryRoll == nil, "generateRandom透传legacy标记")
        math.randomseed(seed)
        local new = Eq.generateRandom(81, 5)
        check(old.templateId == new.templateId and same(old.affixes, new.affixes), "generateRandom本件词缀不变")
    end
    local keys = Secondary.getAttributeKeys()
    local seen = {}
    for _, key in ipairs(keys) do
        check(not seen[key] and AD.META[key] and unitValue(key) > 0, "导出池key完整合法去重")
        seen[key] = true
    end
    check(seen.abnormalRes and seen.esBonus and seen.healCritRate and not seen.comboDmgUp
        and not seen.dropLuck and not seen.finalDamageBonus and not seen.maxHp, "候选白名单排除VM0/孤立连击/最终区/整数")
    keys[1] = "changed"
    check(Secondary.getAttributeKeys()[1] ~= "changed", "查询返回独立副本")
end
local function testPersistenceAndAscend()
    math.randomseed(1010)
    local item = Eq.generate("W7", 16, 6)
    local roll = copy(item.secondaryRoll)
    local raw = item.secondaryRoll
    Eq.hydrate(item)
    check(item.secondaryRoll ~= raw and item.secondaryRoll.stats[1] ~= raw.stats[1], "水合深拷贝嵌套行")
    local first = copy(item.baseStats)
    item.baseStats = nil
    noRNG(function() Eq.hydrate(item) end, "清baseStats水合")
    check(same(first, item.baseStats) and same(roll, item.secondaryRoll), "清baseStats不重新抽")
    item.baseStats = { { "hp", 999 } }
    Eq.hydrate(item)
    check(same(first, item.baseStats), "新字段覆盖schema残留旧baseStats")
    for _, id in ipairs({ "W7", "A1", "H1", "C2" }) do
        local equip = Eq.generate(id, 81, 5)
        local saved = copy(equip.secondaryRoll)
        equip.corruptCount, equip.corruptBaseMult, equip.ascendLevel = 1, 1.35, 11
        Eq.hydrate(equip)
        equip.quality = 6
        Eq.hydrate(equip)
        local expected = Eq.recalcBaseStats(id, 81, EC.QUALITY[6].baseStrength * 1.35, saved)
        check(same(equip.baseStats, expected) and same(equip.secondaryRoll, saved), id .. "腐化+品质重算不回模板副")
        local hydrated = Eq.hydrate(cjson.decode(cjson.encode(Eq.dehydrate(equip))))
        check(same(equip.baseStats, hydrated.baseStats) and same(saved, hydrated.secondaryRoll), id .. "腐化JSON不叠倍率")
        for level = 0, 15 do
            equip.ascendLevel = level
            local boost = Eq.getAscendBoost(equip)
            local entries = Eq.computeModifierEntries(equip, boost)
            for index, row in ipairs(equip.baseStats) do
                local count = #equip.baseStats - 1
                local steps = 0
                if index > 1 and count > 0 and level >= index - 1 then
                    steps = math.floor((level - (index - 1)) / count) + 1
                end
                local expectedValue = index == 1 and row[2] * (1 + boost)
                    or row[2] * (1 + steps * BC.ASCEND_SUB_STAT_RATIO)
                check(near(Eq.effectiveBaseStatValue(equip, index), expectedValue)
                    and entries[index].key == row[1] and near(entries[index].flat, expectedValue), id .. "升阶按保存顺序轮转")
            end
            check(same(saved, equip.secondaryRoll), id .. "升阶不写入基值")
        end
        local score = 0
        for index, row in ipairs(equip.baseStats) do score = score + unitValue(row[1]) * Eq.effectiveBaseStatValue(equip, index) end
        for _, affix in ipairs(equip.affixes) do score = score + unitValue(affix.key) * Eq.effectiveAffixValue(equip, affix) end
        check(Power.genericScore(equip) == math.floor(score), id .. "真实通用战力按完整派生计价")
    end
    for _, key in ipairs(AD.BASE_STATS) do
        check(near(Secondary.unitValue(key), unitValue(key)) and Secondary.unitValue(key) ~= 5,
            key .. "六围不用meta直值5")
    end
    local templ = copy(EC.ITEMS.W7)
    templ.stats[2][2] = templ.stats[2][2] * 2
    local preserved = Secondary.copyValidated(templ, roll)
    check(same(preserved, roll), "模板未来调预算不抹掉保存基值")
    local changed = copy(roll)
    changed.stats[1][2] = changed.stats[1][2] + 1e-8
    check(same(Secondary.copyValidated(templ, changed), changed), "合法保存基值不以当前预算拒绝")
    local lean = Eq.dehydrate(item)
    lean.secondaryRoll.stats[1][2] = 100
    check(item.secondaryRoll.stats[1][2] ~= 100, "写脱水副本不影响原对象")
    local target = { templateId = "W7", level = 16, quality = 6, secondaryRoll = roll }
    Eq.hydrate(target)
    target.secondaryRoll.stats[1][2] = 100
    check(roll.stats[1][2] ~= 100, "写水合对象不影响入参嵌套源")
end
local function testLegacyAndInvalid()
    for _, id in ipairs({ "W1", "O13", "A1", "H1", "C1", "C8" }) do
        local item = { templateId = id, level = 81, quality = 6, ascendLevel = 12, affixes = {} }
        noRNG(function() Eq.hydrate(item) end, id .. "旧无字段水合")
        check(item.secondaryRoll == nil and same(item.baseStats, oldStats(EC.ITEMS[id], 81, 6)), id .. "旧无字段副保持")
        local snapshot = item.baseStats
        Eq.hydrate(item)
        check(item.baseStats == snapshot, id .. "旧缓存baseStats原契约保持")
        local hydrated = Eq.hydrate(cjson.decode(cjson.encode(Eq.dehydrate(item))))
        check(hydrated.secondaryRoll == nil and same(hydrated.baseStats, item.baseStats), id .. "旧JSON无字段不补")
        noRNG(function() Eq.recalcBaseStats(id, 81, 1.5) end, id .. "三参兼容重算")
        check(same(Eq.recalcBaseStats(id, 81, 1.5), item.baseStats), id .. "三参仍原副")
    end
    local new = Eq.generate("W1", 16, 6)
    local valid = copy(new.secondaryRoll)
    local cases = { false, "invalid", 4, {}, { version = "1", stats = valid.stats },
        { version = 0 / 0, stats = valid.stats }, { version = math.huge, stats = valid.stats },
        { version = -1, stats = valid.stats }, { version = 1.5, stats = valid.stats },
        { version = 1, stats = false }, { version = 1, stats = {} },
        { version = 1, stats = { false, false } }, { version = 1, stats = { { "physPen", 1 } } },
        { version = 1, stats = { { "physPen", 1 }, { "physPen", 2 } } },
        { version = 1, stats = { { "physAtk", 1 }, { "critRate", 2 } } },
    }
    for _, value in ipairs({ 0 / 0, math.huge, -math.huge, -1, "2", false, {} }) do
        local data = copy(valid)
        data.stats[1][2] = value
        cases[#cases + 1] = data
    end
    for _, key in ipairs({ "missing", "hp", "dropLuck", "resistance", "comboDmgUp", "finalDamageBonus", "maxHp" }) do
        local data = copy(valid)
        data.stats[1][1] = key
        cases[#cases + 1] = data
    end
    local hole = copy(valid)
    hole.stats[10] = { "critRate", 1 }
    cases[#cases + 1] = hole
    local alias = copy(valid)
    alias.stats["1"] = copy(alias.stats[1])
    cases[#cases + 1] = alias
    local cycle = { version = 1 }
    cycle.stats = cycle
    cases[#cases + 1] = cycle
    for index, data in ipairs(cases) do
        local item = { templateId = "W1", level = 16, quality = 6, secondaryRoll = data,
            baseStats = { { "hp", 999 } }, affixes = {} }
        local ok, err = pcall(function()
            noRNG(function() Eq.hydrate(item) end, "非法字段水合")
            check(item.secondaryRoll and item.secondaryRoll.version == 0, "非法字段保惰性标记" .. index)
            check(same(item.baseStats, oldStats(EC.ITEMS.W1, 16, 6)), "非法字段确定性回退" .. index)
            local lean = Eq.dehydrate(item)
            check(pcall(cjson.encode, lean), "非法字段脱水可JSON")
            check(lean.secondaryRoll.version == 0, "非法字段持久化不丢标记")
            for _, row in ipairs(item.baseStats) do check(finite(row[2]), "非法字段不NaN") end
        end)
        check(ok, "非法字段不崩" .. index .. ":" .. tostring(err))
    end
    local future = copy(valid)
    future.version = 99
    local item = { templateId = "W1", level = 16, quality = 6, secondaryRoll = future }
    noRNG(function() Eq.hydrate(item) end, "未知版本水合")
    check(same(item.secondaryRoll, future) and item.secondaryRoll ~= future, "未知合法版本保留深拷贝")
    check(same(item.baseStats, oldStats(EC.ITEMS.W1, 16, 6)), "未知版本不解释/不静默骰")
    check(same(Eq.hydrate(cjson.decode(cjson.encode(Eq.dehydrate(item)))).secondaryRoll, future), "未知版本JSON保留")
    local zero = copy(valid)
    zero.stats[1][2] = 0
    check(Secondary.copyValidated(EC.ITEMS.W1, zero).version == 1, "合法零基值不强加1")
    local strings = { version = 1, stats = {} }
    for index, row in ipairs(valid.stats) do strings.stats[tostring(index)] = { ["1"] = row[1], ["2"] = row[2] } end
    check(same(Secondary.copyValidated(EC.ITEMS.W1, strings), valid), "兼容JSON数字字符串键且保序")
    local unsupported = { id = "unknown", slot = "weapon", type = "未知", stats = { { "physAtk", 1 }, { "armor", 2 } } }
    noRNG(function() check(Secondary.roll(unsupported) == nil, "未知类型回退原副") end, "不足池生成")
    local badBudget = { id = "bad", slot = "weapon", type = "单手剑", stats = { { "physAtk", 1 }, { "hp", 1 } } }
    noRNG(function() check(Secondary.roll(badBudget) == nil, "VM0槽预算回退") end, "非法预算生成")
    for _, mult in ipairs({ 0 / 0, math.huge, -math.huge, -1, "bad" }) do
        local dirty = { templateId = "W1", level = 16, quality = 6, secondaryRoll = copy(valid), corruptBaseMult = mult }
        Eq.hydrate(dirty)
        check(dirty.corruptBaseMult == nil, "非法腐化倍率清理")
        for _, row in ipairs(dirty.baseStats) do check(finite(row[2]), "非法倍率无NaN") end
    end
end
function Start()
    local ok, err = xpcall(function()
        testTemplates()
        testVariantsAndAffixes()
        testPersistenceAndAscend()
        testLegacyAndInvalid()
    end, debug.traceback)
    if not ok then check(false, "Runtime异常:" .. tostring(err)) end
    print(PREFIX .. "checks=" .. checks .. " failure_count=" .. #failures)
    print(PREFIX .. (#failures == 0 and "RESULT ALL PASS" or "RESULT " .. #failures .. " FAIL"))
    engine:Exit()
end
