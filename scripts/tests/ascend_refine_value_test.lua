-- ============================================================================
-- ascend_refine_value_test.lua — 洗练跨属性的固定升阶投入按静态价值守恒
-- 仅修今后的洗练：旧装备 hydrate/dehydrate 不迁移、不按当前 value 裁剪。
-- 六围按完整 AD.DERIVATIVES 计价，pct 按 valueModel/100 计价，不读角色；
-- 同 key 不变，跨 key 不取整（包括 int 目标），魔化词条不接收普通投入。
-- 基于 equip_ascend_affix_test / corrupt_convert_test 的真实服务回归环境。
-- 跑法: cd /workspace && .cli/UrhoXRuntime tests/ascend_refine_value_test.lua \
--         -tapcode_dir=/workspace -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[ascend_refine_value] "
local failures = {}
local assertionCount = 0

local function check(cond, msg, quiet)
    assertionCount = assertionCount + 1
    if not cond then
        print(PREFIX .. "[FAIL] " .. msg)
        failures[#failures + 1] = msg
    elseif not quiet then
        print(PREFIX .. "[PASS] " .. msg)
    end
end

local function eq(actual, expected, msg, quiet)
    check(actual == expected,
        msg .. " (actual=" .. tostring(actual) .. " expected=" .. tostring(expected) .. ")", quiet)
end

local function near(actual, expected, msg, quiet)
    local tolerance = 1e-10 * math.max(1, math.abs(expected))
    check(type(actual) == "number" and actual == actual
            and math.abs(actual - expected) <= tolerance,
        msg .. " (actual=" .. tostring(actual) .. " expected=" .. tostring(expected) .. ")", quiet)
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function same(actual, expected)
    if type(actual) ~= type(expected) then return false end
    if type(actual) ~= "table" then return actual == expected end
    for key, value in pairs(expected) do
        if not same(actual[key], value) then return false end
    end
    for key in pairs(actual) do
        if expected[key] == nil then return false end
    end
    return true
end

local ES = require("systems.EquipmentSystem")
local AC = require("config.AffixConfig")
local AD = require("systems.AttributeDef")
local PDM = require("rules.character.PlayerDataManager")
local TaskService = require("rules.task.TaskService")
local BS = require("rules.blacksmith.BlacksmithService")

-- 独立 oracle：直接展开全部派生项，不调用产品内部的换算/角色计价函数。
local function unitWeight(key)
    local derivatives = AD.DERIVATIVES[key]
    if derivatives then
        local result = 0
        for _, derivative in ipairs(derivatives) do
            local meta = assert(AD.META[derivative.attr], "missing derivative meta")
            local perUnit = meta.valueModel
            if meta.dataType == AD.TYPE_PCT then perUnit = perUnit / 100 end
            result = result + derivative.perPoint * perUnit
        end
        return result
    end
    local meta = assert(AD.META[key], "missing affix meta")
    return meta.dataType == AD.TYPE_PCT and meta.valueModel / 100 or meta.valueModel
end

local function affix(key, value, bonus)
    local tpl = assert(AC.BY_KEY[key], "missing affix template: " .. tostring(key))
    return {
        affixId = tpl.id, key = tpl.key, name = tpl.name,
        quality = AC.isCorruptAffix(tpl.id) and 0 or 3,
        value = value or 1, ascBonus = bonus,
    }
end

local UID = 1
local modules = {}
local dirtyCount = {}
PDM.GetModule = function(_, name) return modules[name] end
PDM.MarkDirty = function(_, name) dirtyCount[name] = (dirtyCount[name] or 0) + 1 end
PDM.FlushImmediate = function() end
TaskService.UpdateProgress = function() end

local nextSeq = 1
local function newModules()
    BS.Cleanup(UID)
    modules.player = { level = 200 }
    modules.equipment = { inventory = {}, equipped = {}, nextSeq = 1 }
    modules.currency = {
        gold = 10 ^ 12, essence = 10 ^ 9,
        weaponScroll = 10 ^ 6, offhandScroll = 10 ^ 6, armorScroll = 10 ^ 6,
        helmetScroll = 10 ^ 6, shoesScroll = 10 ^ 6, accessoryScroll = 10 ^ 6,
        enhanceStone = 20, destroyStone = 20, corruptStone = 20, sacredStone = 20,
    }
    modules.battle = { maxStageId = 0, currentStageId = 0 }
    dirtyCount = {}
end

local function putEquip(affixes, mult)
    local equip = assert(ES.generate("W1", 10, 4), "fixture weapon must generate")
    ES.hydrate(equip)
    equip.affixes = affixes
    equip.affixMult = mult or 1.7
    equip.seq = nextSeq
    nextSeq = nextSeq + 1
    modules.equipment.inventory[tostring(equip.seq)] = equip
    return equip
end

local originalRoll = ES.rollAffixesForRefine
local originalConvert = ES.convertAscBonusForRefine
local rollPlan = {}
local rollCalls = {}

-- 仅控制随机结果；RefineEquip/RefineReplace、魔化拆合、锁索引映射均走真实实现。
local function controlledRoll(existing, lockedSet)
    rollCalls[#rollCalls + 1] = { count = #existing, locks = copy(lockedSet or {}) }
    local rolled = {}
    for i, old in ipairs(existing) do
        if not (lockedSet and lockedSet[i]) then
            local planned = assert(rollPlan[i], "missing controlled roll at plain slot " .. i)
            rolled[#rolled + 1] = affix(planned.key, planned.value)
        end
    end
    return ES.mergeAffixesWithLocks(existing, rolled, lockedSet)
end

local function preview(equip, plan, resource, locks)
    rollPlan = plan
    local ok, err, result = BS.RefineEquip(UID, equip.seq, resource, locks)
    check(ok, "RefineEquip succeeds: " .. tostring(err))
    assert(ok and result and result.refinePreview, "preview must exist")
    return result.refinePreview
end

local function replace(equip)
    local ok, err, result = BS.RefineReplace(UID, equip.seq)
    check(ok and result and result.refineReplaced, "RefineReplace succeeds: " .. tostring(err))
    assert(ok, "replace must succeed")
end

local function assertEntry(equip, index, expected, msg)
    local entries = ES.computeModifierEntries(equip, 0)
    local entry = entries[#(equip.baseStats or {}) + index]
    eq(entry and entry.key, equip.affixes[index].key, msg .. " modifier key")
    near(entry and entry.flat, expected, msg .. " modifier fixed bonus applied once")
end

local function testHelper()
    eq(#AC.AFFIXES, 44, "covers all 44 ordinary keys")
    local expectedBaseWeights = { str = 1.5, agi = 1.495, int = 1.49, vit = 1.49, luk = 1.5, spi = 1.5 }
    for _, key in ipairs(AD.BASE_STATS) do
        near(unitWeight(key), expectedBaseWeights[key], key .. " full derivative static weight")
    end
    for _, tpl in ipairs(AC.AFFIXES) do
        check(unitWeight(tpl.key) > 0, tpl.key .. " has positive ordinary unit value", true)
    end

    near(ES.convertAscBonusForRefine(affix("maxHp", 100, 16), affix("str", 2)), 0.32,
        "maxHp bonus 16 converts to str bonus 0.32")
    near(ES.convertAscBonusForRefine(affix("str", 999, 2), affix("energyShield", 0.01)), 30,
        "str to energyShield includes complete str derivatives")
    near(ES.convertAscBonusForRefine(affix("str", 0.01, 2), affix("critDmg", 999)), 15,
        "str to percentage uses per-percentage-point value")
    near(ES.convertAscBonusForRefine(affix("str", 1, 2), affix("hpBonus", 1)), 5,
        "str to hpBonus converts percentage denominator")
    near(ES.convertAscBonusForRefine(affix("str", 1, 0.013), affix("maxHp", 100)), 0.65,
        "INT target maxHp keeps fractional fixed bonus")
    eq(ES.convertAscBonusForRefine(affix("maxHp", 1, 0.375), affix("maxHp", 900)), 0.375,
        "same key keeps exact fractional bonus regardless of value")
    eq(ES.convertAscBonusForRefine(affix("str", 1, 40), affix("str", 900)), 40,
        "same key does not scale by rerolled value")
    eq(ES.convertAscBonusForRefine(nil, affix("str")), nil, "nil old affix has no bonus")
    eq(ES.convertAscBonusForRefine(affix("str", 1, 2), nil), nil, "nil new affix has no bonus")
    eq(ES.convertAscBonusForRefine(affix("str"), affix("maxHp")), nil, "missing bonus remains nil")
    eq(ES.convertAscBonusForRefine(affix("str", 1, 0), affix("str")), nil, "same-key zero remains nil")
    eq(ES.convertAscBonusForRefine(affix("str", 1, 0), affix("maxHp")), nil, "cross-key zero remains nil")
    for _, invalid in ipairs({ -1, math.huge, -math.huge, 0 / 0 }) do
        eq(ES.convertAscBonusForRefine(affix("str", 1, invalid), affix("maxHp")), nil,
            "invalid non-positive/non-finite bonus rejected: " .. tostring(invalid))
    end
    eq(ES.convertAscBonusForRefine(affix("finalStrBonus", 5, 7), affix("str")), nil,
        "corrupt source does not transfer ordinary bonus")
    eq(ES.convertAscBonusForRefine(affix("str", 5, 7), affix("finalStrBonus")), nil,
        "corrupt target does not receive ordinary bonus")

    local pairsChecked = 0
    for i, oldTpl in ipairs(AC.AFFIXES) do
        for j, newTpl in ipairs(AC.AFFIXES) do
            local bonus = 0.013 + i * 0.37 + j * 0.001
            local old = affix(oldTpl.key, 1, bonus)
            local target = affix(newTpl.key, 98765, 999)
            local oldCopy, targetCopy = copy(old), copy(target)
            local converted = ES.convertAscBonusForRefine(old, target)
            local tag = old.key .. " -> " .. target.key
            near(converted and converted * unitWeight(target.key), bonus * unitWeight(old.key),
                tag .. " value conservation", true)
            local back = ES.convertAscBonusForRefine(affix(target.key, 999, converted), affix(old.key, 0.001))
            near(back, bonus, tag .. " roundtrip", true)
            check(same(old, oldCopy) and same(target, targetCopy), tag .. " helper does not mutate inputs", true)
            pairsChecked = pairsChecked + 1
        end
    end
    eq(pairsChecked, 44 * 44, "all 1936 ordered ordinary-key pairs checked")

    -- 若 INT 目标取整，str 0.013 -> HP 0.65 -> str 0.02 会产生往返套利。
    local current = 0.013
    for i = 1, 250 do
        local hp = ES.convertAscBonusForRefine(affix("str", 1, current), affix("maxHp", 1))
        local nextBonus = ES.convertAscBonusForRefine(affix("maxHp", 1, hp), affix("str", 1))
        near(hp, 0.65, "fractional INT roundtrip " .. i, true)
        near(nextBonus, 0.013, "no roundtrip gain or loss " .. i, true)
        current = nextBonus
    end
end

local function testPreviewReplace()
    newModules()
    local e = putEquip({ affix("maxHp", 100, 16) })
    local originalAffixes = e.affixes
    local before = copy(e.affixes)
    local baseBefore = copy(e.baseStats)
    local p1 = preview(e, { { key = "str", value = 2 } })
    near(p1[1].ascBonus, 0.32, "preview carries converted str bonus")
    check(e.affixes == originalAffixes and same(e.affixes, before), "preview does not modify old affixes")
    check(same(e.baseStats, baseBefore), "preview does not modify equipment base stats")
    near(ES.effectiveAffixValue(e, e.affixes[1]), 186, "old equipment stays effective before replacement")
    near(ES.effectiveAffixValue(e, p1[1]), 3.72, "preview effective value is value*mult plus fixed converted bonus")

    -- 未确认的再次预览从旧装换算，不从上一份 preview 继续累加。
    local p2 = preview(e, { { key = "energyShield", value = 4 } })
    near(p2[1].ascBonus, 4.8, "second preview converts original HP bonus only once")
    near(p1[1].ascBonus, 0.32, "second preview does not modify first preview")
    check(e.affixes == originalAffixes and same(e.affixes, before), "second preview still leaves old equipment unchanged")
    replace(e)
    eq(e.affixes[1].key, "energyShield", "replacement applies latest preview key")
    near(e.affixes[1].ascBonus, 4.8, "replacement applies latest converted bonus")
    near(ES.effectiveAffixValue(e, e.affixes[1]), 11.6, "replacement effective value keeps bonus outside mult")
    near(ES.getAffixMult(e), 1.7, "replacement preserves equipment affix multiplier")
    assertEntry(e, 1, 11.6, "replacement")
    check((dirtyCount.equipment or 0) > 0, "real service marks equipment dirty")
    local applied = copy(e.affixes)
    check(not BS.RefineReplace(UID, e.seq), "consumed preview cannot be replaced twice")
    check(same(e.affixes, applied), "repeated replacement does not accumulate bonus")

    local cancelled = preview(e, { { key = "maxHp", value = 5 } })
    near(cancelled[1].ascBonus, 16, "reverse preview conserves previous original HP investment")
    -- UI 取消就是不确认；Cleanup 是现有服务用于丢弃待定状态的入口。
    BS.Cleanup(UID)
    check(same(e.affixes, applied), "discarding pending preview leaves applied equipment untouched")
    check(not BS.RefineReplace(UID, e.seq), "discarded preview cannot be applied")
    local fresh = preview(e, { { key = "str", value = 3 } })
    near(fresh[1].ascBonus, 0.32, "fresh preview after cancel does not accumulate abandoned bonus")
    check(same(e.affixes, applied), "fresh preview still leaves existing affixes untouched")
    replace(e)
    near(e.affixes[1].ascBonus, 0.32, "fresh replacement applies exactly one converted investment")
    assertEntry(e, 1, 5.42, "fresh replacement")
end

local function testFractionalIntAndNoBonus()
    newModules()
    local e = putEquip({ affix("str", 1, 0.013) })
    local p = preview(e, { { key = "maxHp", value = 5 } })
    near(p[1].ascBonus, 0.65, "real service INT target retains fractional bonus")
    replace(e)
    near(e.affixes[1].ascBonus, 0.65, "INT fraction survives replacement")
    assertEntry(e, 1, 9.15, "INT target")
    local restored = cjson.decode(cjson.encode(ES.dehydrate(e)))
    ES.hydrate(restored)
    near(restored.affixes[1].ascBonus, 0.65, "INT fraction survives existing JSON persistence")
    near(ES.effectiveAffixValue(restored, restored.affixes[1]), 9.15, "restored INT bonus is not rounded")

    -- 洗练石走真实同属性重随，不用 controlledRoll。
    local stoneBefore = copy(e.affixes)
    local stonePreview = preview(e, {}, "enhanceStone")
    eq(stonePreview[1].key, "maxHp", "enhance stone keeps same INT key")
    near(stonePreview[1].ascBonus, 0.65, "enhance stone preserves exact same-key fraction")
    check(same(e.affixes, stoneBefore), "enhance stone preview leaves old affixes untouched")
    check(stonePreview[1].value >= stoneBefore[1].value, "enhance stone keeps existing higher-value guarantee")
    replace(e)
    near(e.affixes[1].ascBonus, 0.65, "enhance stone replacement preserves exact fraction")

    newModules()
    local noBonus = putEquip({ affix("str", 1), affix("agi", 2, 0) })
    local noBonusPreview = preview(noBonus, { { key = "maxHp", value = 5 }, { key = "critRate", value = 3 } })
    eq(noBonusPreview[1].ascBonus, nil, "service missing bonus remains nil after cross-key reroll")
    eq(noBonusPreview[2].ascBonus, nil, "service zero bonus remains nil after cross-key reroll")
    replace(noBonus)
    eq(noBonus.affixes[1].ascBonus, nil, "replaced slot without investment does not gain bonus")
    eq(noBonus.affixes[2].ascBonus, nil, "replaced zero-investment slot does not gain bonus")
end

local function testLocksAndCorruptSlots()
    newModules()
    local e = putEquip({
        affix("maxHp", 100, 16),
        affix("finalPhysAtkBonus", 5),
        affix("agi", 2, 11),
    })
    local before = copy(e.affixes)
    local oldMagic = e.affixes[2]
    local conversionCalls = {}
    ES.convertAscBonusForRefine = function(old, new)
        conversionCalls[#conversionCalls + 1] = { oldKey = old and old.key, newKey = new and new.key }
        return originalConvert(old, new)
    end
    local p = preview(e, {
        { key = "energyShield", value = 99 }, -- locked slot: must be ignored
        { key = "physCritDmg", value = 3 },
    }, nil, { 1 })
    ES.convertAscBonusForRefine = originalConvert
    check(#conversionCalls >= 2, "service validates then converts ordinary slots")
    local onlyOrdinary = true
    for _, call in ipairs(conversionCalls) do
        if AC.isCorruptAffix(AC.BY_KEY[call.oldKey].id) or AC.isCorruptAffix(AC.BY_KEY[call.newKey].id) then
            onlyOrdinary = false
        end
    end
    check(onlyOrdinary, "service preflight and transfer both skip corrupt slot")
    local lastRoll = rollCalls[#rollCalls]
    eq(lastRoll.count, 2, "real service removes corrupt slot before controlled ordinary roll")
    check(lastRoll.locks[1] == true and lastRoll.locks[2] == nil, "locked index mapped to plain list correctly")
    check(same(p[1], before[1]), "locked affix preserves key, quality, value and fixed bonus")
    check(p[2] == oldMagic and same(p[2], before[2]), "corrupt middle slot stays entirely unchanged")
    eq(p[2].ascBonus, nil, "corrupt middle slot receives no ordinary investment")
    eq(p[3].key, "physCritDmg", "unlocked ordinary slot rerolls at original index")
    near(p[3].ascBonus, 11 * 1.495 / 0.15, "unlocked slot uses its own full agi value, not compacted neighbor")
    check(same(e.affixes, before), "mixed locked preview does not modify original equipment")
    replace(e)
    check(same(e.affixes[1], before[1]), "locked slot survives replacement exactly")
    check(same(e.affixes[2], before[2]), "corrupt slot survives replacement exactly")
    near(e.affixes[3].ascBonus, 11 * 1.495 / 0.15, "mixed replacement applies converted bonus once")
    assertEntry(e, 3, 3 * 1.7 + 11 * 1.495 / 0.15, "mixed slot")

    local stoneBefore = copy(e.affixes)
    local sp = preview(e, {}, "enhanceStone", { 1 })
    check(same(sp[1], stoneBefore[1]), "enhance stone also preserves locked ordinary slot")
    check(same(sp[2], stoneBefore[2]), "enhance stone also preserves corrupt middle slot")
    near(sp[3].ascBonus, stoneBefore[3].ascBonus, "enhance stone same-key unlocked bonus is unchanged")
    replace(e)
    near(e.affixes[3].ascBonus, stoneBefore[3].ascBonus, "enhance stone replacement does not compound bonus")
end

local function testCorruptCleanseRestoration()
    newModules()
    local e = putEquip({ affix("str", 2, 0.32) })
    local before = copy(e.affixes[1])
    local baseBefore = copy(e.baseStats)
    local ok, err, result = BS.RefineEquip(UID, e.seq, "corruptStone")
    check(ok and result and result.autoReplaced, "real corrupt conversion auto-applies: " .. tostring(err))
    assert(ok and e.corruptRevert, "corrupt fixture requires revert patch")
    check(AC.isCorruptAffix(e.affixes[1]), "ordinary affix becomes corrupt")
    eq(e.affixes[1].ascBonus, nil, "corrupt affix does not carry ordinary fixed bonus")
    local patch = e.corruptRevert.patches[1]
    eq(patch[1], "c", "conversion uses ordinary snapshot patch")
    check(same(patch[3], before), "conversion snapshot preserves original fractional ordinary affix exactly")
    local corruptValue = e.affixes[1].value
    local restored = cjson.decode(cjson.encode(ES.dehydrate(e)))
    ES.hydrate(restored)
    eq(restored.affixes[1].ascBonus, nil, "persisted corrupt affix remains without ordinary bonus")
    near(restored.affixes[1].value, corruptValue, "persistence does not recalculate existing corrupt value")
    near(restored.corruptRevert.patches[1][3].ascBonus, 0.32, "JSON revert snapshot preserves converted investment")
    e.affixes = restored.affixes
    e.corruptRevert = restored.corruptRevert
    local washed, washErr = BS.RefineEquip(UID, e.seq, "sacredStone")
    check(washed, "real cleanse restores original affix: " .. tostring(washErr))
    check(same(e.affixes[1], before), "cleanse restores original key/value/quality/bonus without reconversion")
    eq(e.corruptCount, nil, "cleanse clears curse count")
    eq(e.corruptRevert, nil, "cleanse clears revert patch")
    check(same(e.baseStats, baseBefore), "cleanse restores original equipment base stats")
    near(ES.getAffixMult(e), 1.7, "corrupt and cleanse preserve equipment affix multiplier")
    assertEntry(e, 1, 3.72, "cleanse restoration")
end

local function testInvalidValueNoCharge()
    local invalidPairs = {
        { { affixId = 90001, key = "unknownAscendKey", value = 1, ascBonus = 7 }, affix("str"), "unknown source" },
        { affix("str", 1, 7), { affixId = 90002, key = "unknownAscendKey", value = 1 }, "unknown target" },
        { { affixId = 90003, key = AD.HP, value = 1, ascBonus = 7 }, affix("str"), "zero-value source" },
        { affix("str", 1, 7), { affixId = 90004, key = AD.HP, value = 1 }, "zero-value target" },
        { affix("str", 1, 1e308), affix("maxHp"), "cross-key converted bonus overflow" },
    }
    for _, test in ipairs(invalidPairs) do
        local old, target = test[1], test[2]
        local oldBefore, targetBefore = copy(old), copy(target)
        local ok, err = pcall(ES.convertAscBonusForRefine, old, target)
        check(not ok and type(err) == "string", test[3] .. " fails loudly rather than copying incompatible units")
        check(same(old, oldBefore) and same(target, targetBefore), test[3] .. " does not mutate either input")
    end
    eq(ES.convertAscBonusForRefine(affix("str", 1, 1e308), affix("str")), 1e308,
        "same-key finite extreme bonus is still preserved")
    near(ES.convertAscBonusForRefine(affix("maxHp", 1, 1e308), affix("str")), 2e306,
        "finite narrowing conversion does not overflow intermediate multiply")

    local invalidSources = {
        { affixId = 90001, key = "unknownAscendKey", quality = 3, value = 1, ascBonus = 7 },
        { affixId = 90003, key = AD.HP, quality = 3, value = 1, ascBonus = 7 },
        affix("str", 1, 1e308),
    }
    for i, source in ipairs(invalidSources) do
        newModules()
        local e = putEquip({ copy(source) })
        local equipBefore, currencyBefore = copy(e), copy(modules.currency)
        local rollsBefore = #rollCalls
        local callOk, accepted, err, result = pcall(BS.RefineEquip, UID, e.seq, nil)
        check(callOk and accepted == false and type(err) == "string", "invalid service source " .. i .. " rejected before charge")
        eq(result, nil, "invalid service source " .. i .. " yields no preview")
        check(same(e, equipBefore), "invalid service source " .. i .. " leaves entire equipment and refineCount unchanged")
        check(same(modules.currency, currencyBefore), "invalid service source " .. i .. " deducts no gold/essence/stone")
        eq(#rollCalls, rollsBefore, "invalid service source " .. i .. " rejected before random roll")
        check(next(dirtyCount) == nil, "invalid service source " .. i .. " marks no persistent field dirty")
        check(not BS.RefineReplace(UID, e.seq), "invalid service source " .. i .. " creates no pending replacement")
    end
end

local function testMissingConfigNoCharge()
    local cases = {
        { name = "missing str derivatives", breakConfig = function() AD.DERIVATIVES.str = nil end },
        { name = "empty str derivatives", breakConfig = function() AD.DERIVATIVES.str = {} end },
        { name = "missing derived armor meta", breakConfig = function() AD.META.armor = nil end },
    }
    for _, invalid in ipairs({
        { name = "missing perPoint" },
        { name = "string perPoint", value = "invalid" },
        { name = "negative perPoint", value = -1 },
        { name = "NaN perPoint", value = 0 / 0 },
        { name = "infinite perPoint", value = math.huge },
        { name = "negative infinite perPoint", value = -math.huge },
    }) do
        cases[#cases + 1] = {
            name = invalid.name,
            breakConfig = function() AD.DERIVATIVES.str[1].perPoint = invalid.value end,
        }
    end

    for _, test in ipairs(cases) do
        newModules()
        -- 在破坏配置前建立真实待替换预览；失败必须保留它，也不能给另一件装备创建 pending。
        local withPending = putEquip({ affix("str", 1, 7) })
        withPending.refineCount = 9
        local pendingBefore = copy(preview(withPending, { { key = "energyShield", value = 4 } }))
        local withoutPending = putEquip({ affix("maxHp", 100, 16) })
        withoutPending.refineCount = 4
        local savedDerivatives, savedArmor = AD.DERIVATIVES.str, AD.META.armor
        local derivativesBefore, armorBefore = copy(savedDerivatives), copy(savedArmor)

        -- 只损坏副本，且即使测试出现异常也先恢复配置，避免污染后续用例。
        AD.DERIVATIVES.str = copy(savedDerivatives)
        local ran, runErr = pcall(function()
            test.breakConfig()
            local pairsToReject = {
                { affix("str", 1, 7), affix("maxHp"), "invalid source derivatives" },
                { affix("maxHp", 1, 16), affix("str"), "invalid target derivatives" },
            }
            for _, pair in ipairs(pairsToReject) do
                local oldBefore, targetBefore = copy(pair[1]), copy(pair[2])
                local ok, err = pcall(ES.convertAscBonusForRefine, pair[1], pair[2])
                check(not ok and type(err) == "string", test.name .. " " .. pair[3] .. " raises helper error")
                check(same(pair[1], oldBefore) and same(pair[2], targetBefore),
                    test.name .. " helper preserves both inputs")
            end

            -- str 源配置与 maxHp 的候选目标配置均必须在扣费、roll、dirty 前拒绝。
            for _, e in ipairs({ withPending, withoutPending }) do
                local tag = test.name .. " " .. e.affixes[1].key .. " service"
                local equipBefore, currencyBefore = copy(e), copy(modules.currency)
                local rollsBefore, dirtyBefore = #rollCalls, copy(dirtyCount)
                local callOk, accepted, err, result = pcall(BS.RefineEquip, UID, e.seq, nil)
                check(callOk and accepted == false and type(err) == "string", tag .. " returns false with error")
                eq(result, nil, tag .. " yields no new preview")
                check(same(e, equipBefore), tag .. " preserves entire equipment")
                eq(e.refineCount, equipBefore.refineCount, tag .. " preserves refineCount")
                check(same(modules.currency, currencyBefore), tag .. " deducts no currency or stone")
                eq(#rollCalls, rollsBefore, tag .. " performs no random roll")
                check(same(dirtyCount, dirtyBefore), tag .. " adds no dirty fields")
            end
        end)
        AD.DERIVATIVES.str = savedDerivatives
        AD.META.armor = savedArmor
        check(ran, test.name .. " assertions completed: " .. tostring(runErr))
        check(AD.DERIVATIVES.str == savedDerivatives and same(AD.DERIVATIVES.str, derivativesBefore)
                and AD.META.armor == savedArmor and same(AD.META.armor, armorBefore),
            test.name .. " restores original configuration references and values")
        if ran then
            check(not BS.RefineReplace(UID, withoutPending.seq), test.name .. " creates no pending replacement")
            replace(withPending)
            check(same(withPending.affixes, pendingBefore), test.name .. " preserves prior pending preview exactly")
            -- 恢复后真实换算立即恢复正常，证明配置破坏未泄漏到下一用例。
            near(ES.convertAscBonusForRefine(affix("maxHp", 100, 16), affix("str", 2)), 0.32,
                test.name .. " restored configuration converts normally")
        end
    end
end

local function testLegacyUnchanged()
    local legacy = {
        templateId = "W1", level = 10, quality = 4,
        ascendLevel = 8, affixMult = 1.2, refineCount = 7,
        affixes = {
            { affixId = 1, quality = 3, value = 1, ascBonus = 40 },
            { affixId = 7, quality = 3, value = 1, ascBonus = 25000.375 },
        },
    }
    local expectedLean = copy(legacy)
    local firstLean = ES.dehydrate(legacy)
    check(same(legacy, expectedLean), "dehydrate does not mutate old low-value/high-bonus save")
    check(same(firstLean, expectedLean), "dehydrate returns old save fields unchanged, no value migration")
    local e = cjson.decode(cjson.encode(firstLean))
    for i = 1, 5 do
        ES.hydrate(e)
        eq(e.affixes[1].value, 1, "legacy str value remains 1 at pass " .. i)
        eq(e.affixes[1].ascBonus, 40, "legacy str bonus remains 40 at pass " .. i)
        eq(e.affixes[2].value, 1, "legacy INT value remains 1 at pass " .. i)
        eq(e.affixes[2].ascBonus, 25000.375, "legacy large fractional INT bonus remains at pass " .. i)
        local lean = ES.dehydrate(e)
        check(same(lean, expectedLean), "legacy hydrate/dehydrate performs zero rewrite at pass " .. i)
        e = cjson.decode(cjson.encode(lean))
    end
    ES.hydrate(e)
    near(ES.effectiveAffixValue(e, e.affixes[1]), 41.2, "old str equipment effect remains unchanged")
    near(ES.effectiveAffixValue(e, e.affixes[2]), 25001.575, "old large INT bonus effect remains unchanged")
end

function Start()
    print(PREFIX .. "start")
    math.randomseed(1003)
    local ok, err = pcall(function()
        assert(type(originalConvert) == "function", "convertAscBonusForRefine is not ready")
        ES.rollAffixesForRefine = controlledRoll
        testHelper()
        testPreviewReplace()
        testFractionalIntAndNoBonus()
        testLocksAndCorruptSlots()
        testCorruptCleanseRestoration()
        testInvalidValueNoCharge()
        testMissingConfigNoCharge()
        testLegacyUnchanged()
    end)
    ES.rollAffixesForRefine = originalRoll
    ES.convertAscBonusForRefine = originalConvert
    BS.Cleanup(UID)
    if not ok then
        check(false, "exception: " .. tostring(err))
    end
    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS assertions=" .. assertionCount .. " pairs=1936")
    else
        print(PREFIX .. "RESULT FAIL failures=" .. #failures .. " assertions=" .. assertionCount)
        for _, failure in ipairs(failures) do print(PREFIX .. "  - " .. failure) end
    end
    engine:Exit()
end
