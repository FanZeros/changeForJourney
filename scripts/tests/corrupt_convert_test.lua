-- ============================================================================
-- corrupt_convert_test.lua — 腐化构筑模型回归（2026-09-30 用户拍板方案二）
-- 规则：
--   腐化石 = 一条普通词缀转同类型魔化词条（数值×1.8）+ 叠一层诅咒（基础×0.9，最多3层）
--   神圣石 = 逐层洗除诅咒（魔化词条保留），不耗精粹
--   腐化后仍可洗练（精粹×2），魔化词条在普通洗练/洗练石中保持固定
-- 验证：
--   1) 转换：条数不变、恰1条魔化、数值≥原×1.8、层数/诅咒倍率/patch layer 正确
--   2) 诅咒：baseStats 按 0.9^层 缩放
--   3) 腐化态洗练：普通洗练/洗练石可用且魔化词条不变
--   4) 神圣石逐层回退：先退第2层转换，再退第1层；第3次拒绝
--   5) 3层上限
--   6) 无可转换词缀拒绝
-- 跑法: ./.cli/UrhoXRuntime tests/corrupt_convert_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[corrupt_convert] "
local failures = {}
local function check(cond, msg)
    if cond then print(PREFIX .. "[PASS] " .. msg)
    else print(PREFIX .. "[FAIL] " .. msg); failures[#failures + 1] = msg end
end
local function eq(actual, expected, msg)
    check(actual == expected, msg .. " (实际=" .. tostring(actual) .. " 期望=" .. tostring(expected) .. ")")
end
local function near(actual, expected, msg)
    check(math.abs((actual or 0) - expected) < 0.02,
        msg .. " (实际=" .. tostring(actual) .. " 期望≈" .. tostring(expected) .. ")")
end

local EquipmentSystem = require("systems.EquipmentSystem")
local AffixConfig     = require("config.AffixConfig")
local PDM             = require("rules.character.PlayerDataManager")
local TaskService     = require("rules.task.TaskService")
local BS              = require("rules.blacksmith.BlacksmithService")

local UID = 1
local modules = {}
PDM.GetModule = function(_, name) return modules[name] end
PDM.MarkDirty = function() end
PDM.FlushImmediate = function() end
TaskService.UpdateProgress = function() end
modules.player = { level = 200 }

local function newModules()
    modules.equipment = { inventory = {}, equipped = {}, nextSeq = 1 }
    modules.currency = {
        gold = 10 ^ 12, essence = 10 ^ 9,
        weaponScroll = 10 ^ 6, offhandScroll = 10 ^ 6, armorScroll = 10 ^ 6,
        helmetScroll = 10 ^ 6, shoesScroll = 10 ^ 6, accessoryScroll = 10 ^ 6,
        enhanceStone = 10, destroyStone = 10, corruptStone = 10, sacredStone = 10,
    }
    modules.battle = { maxStageId = 0, currentStageId = 0 }
end

local nextSeq = 1
local function putEquip(equip)
    equip.seq = nextSeq
    modules.equipment.inventory[tostring(nextSeq)] = equip
    nextSeq = nextSeq + 1
    return equip
end

local function makeWeapon(quality, level)
    local equip = EquipmentSystem.generate("W1", level or 10, quality)
    assert(equip, "fixture weapon must generate")
    EquipmentSystem.hydrate(equip)
    return equip
end

local function corruptAffixesOf(equip)
    local list = {}
    for _, affix in ipairs(equip.affixes or {}) do
        if AffixConfig.isCorruptAffix(affix) then
            list[#list + 1] = affix
        end
    end
    return list
end

local function findAffix(equip, key)
    for _, affix in ipairs(equip.affixes or {}) do
        if affix.key == key then return affix end
    end
    return nil
end

function Start()
    math.randomseed(42)

    -- ========== 1) 腐化石转换 ==========
    newModules()
    local e = putEquip(makeWeapon(5))
    e.affixes = {
        { affixId = 5, quality = 3, value = 10, key = "str", name = "力量" },
        { affixId = 6, quality = 3, value = 20, key = "agi", name = "敏捷" },
    }
    local base0 = (e.baseStats and e.baseStats[1]) and e.baseStats[1][2] or nil
    local ok, err = BS.RefineEquip(UID, e.seq, "corruptStone")
    check(ok, "腐化石转换成功: " .. tostring(err))
    eq(#e.affixes, 2, "转换不改变词条条数")
    local c1 = corruptAffixesOf(e)
    eq(#c1, 1, "恰1条魔化词条")
    local c1v = c1[1] and c1[1].value or 0
    local p1 = e.corruptRevert and e.corruptRevert.patches and e.corruptRevert.patches[1]
    check(p1 ~= nil and p1[1] == "c", "revert 记录 c 型 patch")
    local orig1 = p1 and p1[3] or nil
    check(orig1 ~= nil, "patch 保存转换前原词条")
    if orig1 then
        check(c1v >= (tonumber(orig1.value) or 0) * 1.8 - 1, "魔化数值≥原数值×1.8")
    end
    eq(e.corruptCount, 1, "诅咒1层")
    near(tonumber(e.corruptBaseMult), 0.9, "诅咒倍率0.9")
    check(p1 and p1.layer == 1, "patch layer=1")
    if base0 then
        local base1 = e.baseStats and e.baseStats[1] and e.baseStats[1][2] or 0
        near(base1 / base0, 0.9, "基础属性×0.9")
    end

    -- ========== 2) 腐化态仍可洗练，魔化词条固定 ==========
    local c1vBefore = c1v
    local ok2, err2 = BS.RefineEquip(UID, e.seq, nil)
    check(ok2, "腐化态普通洗练可用: " .. tostring(err2))
    local cAfter = corruptAffixesOf(e)
    eq(#cAfter, 1, "普通洗练后魔化词条仍在")
    eq(cAfter[1] and cAfter[1].value, c1vBefore, "普通洗练不改变魔化词条数值")
    local ok3, err3 = BS.RefineEquip(UID, e.seq, "enhanceStone")
    check(ok3, "腐化态洗练石可用: " .. tostring(err3))
    local cAfter2 = corruptAffixesOf(e)
    eq(cAfter2[1] and cAfter2[1].value, c1vBefore, "洗练石不改变魔化词条数值")

    -- ========== 3) 第2层腐化 + 神圣石逐层回退 ==========
    local ok4, err4 = BS.RefineEquip(UID, e.seq, "corruptStone")
    check(ok4, "第2层腐化成功: " .. tostring(err4))
    eq(e.corruptCount, 2, "诅咒2层")
    near(tonumber(e.corruptBaseMult), 0.81, "诅咒倍率0.81")
    eq(#corruptAffixesOf(e), 2, "2条魔化词条")
    local p2 = e.corruptRevert.patches[2]
    check(p2 ~= nil and p2.layer == 2, "第2层 patch layer=2")
    local orig2 = p2 and p2[3] or nil

    local ok5, err5 = BS.RefineEquip(UID, e.seq, "sacredStone")
    check(ok5, "神圣石洗除第2层: " .. tostring(err5))
    eq(e.corruptCount, 1, "剩余1层诅咒")
    near(tonumber(e.corruptBaseMult), 0.9, "剩余诅咒倍率0.9")
    local cAfterWash = corruptAffixesOf(e)
    eq(#cAfterWash, 1, "洗除后剩1条魔化词条")
    eq(cAfterWash[1] and cAfterWash[1].value, c1vBefore, "第1层转换保留")
    if orig2 then
        local restored2 = findAffix(e, orig2.key)
        check(restored2 ~= nil
            and not AffixConfig.isCorruptAffix(restored2)
            and math.abs((tonumber(restored2.value) or 0) - (tonumber(orig2.value) or 0)) < 0.01,
            "第2层转换已还原为原词条")
    end

    local ok6, err6 = BS.RefineEquip(UID, e.seq, "sacredStone")
    check(ok6, "神圣石洗除第1层: " .. tostring(err6))
    eq(e.corruptCount, nil, "诅咒清空")
    eq(#corruptAffixesOf(e), 0, "魔化词条全部还原")
    check(e.corruptRevert == nil, "revert 清空")
    if orig1 and base0 then
        local baseNow = e.baseStats and e.baseStats[1] and e.baseStats[1][2] or 0
        near(baseNow / base0, 1.0, "基础属性恢复")
    end

    local ok7, err7 = BS.RefineEquip(UID, e.seq, "sacredStone")
    check(not ok7, "无诅咒时神圣石被拒绝: " .. tostring(err7))

    -- ========== 4) 3层上限 ==========
    newModules()
    local e2 = putEquip(makeWeapon(5))
    e2.affixes = {
        { affixId = 5, quality = 3, value = 10, key = "str", name = "力量" },
        { affixId = 6, quality = 3, value = 20, key = "agi", name = "敏捷" },
        { affixId = 7, quality = 3, value = 30, key = "maxHp", name = "生命" },
        { affixId = 8, quality = 3, value = 40, key = "armor", name = "护甲" },
    }
    for i = 1, 3 do
        local okc = BS.RefineEquip(UID, e2.seq, "corruptStone")
        check(okc, "第" .. i .. "层腐化成功")
    end
    eq(e2.corruptCount, 3, "诅咒3层")
    local ok8, err8 = BS.RefineEquip(UID, e2.seq, "corruptStone")
    check(not ok8, "第4层腐化被拒绝: " .. tostring(err8))

    -- ========== 5) 无可转换词缀 ==========
    newModules()
    local e3 = putEquip(makeWeapon(5))
    e3.affixes = {
        { affixId = 20, quality = 3, value = 5, key = "critRate", name = "暴击率" },
    }
    local ok9, err9 = BS.RefineEquip(UID, e3.seq, "corruptStone")
    check(not ok9, "无可转换词缀被拒绝: " .. tostring(err9))

    -- ========== 6) 洗练石保底只升不降 ==========
    newModules()
    local e4 = putEquip(makeWeapon(5))
    e4.affixes = {
        { affixId = 5, quality = 3, value = 100, key = "str", name = "力量" },
        { affixId = 6, quality = 3, value = 100, key = "agi", name = "敏捷" },
    }
    local okE, errE, resE = BS.RefineEquip(UID, e4.seq, "enhanceStone")
    check(okE, "洗练石可用: " .. tostring(errE))
    local noDown = true
    for i, aff in ipairs(resE.refinePreview or {}) do
        local oldV = e4.affixes[i] and e4.affixes[i].value or 0
        if (tonumber(aff.value) or 0) < oldV - 0.001 then noDown = false end
    end
    check(noDown, "洗练石结果逐条不低于原值（保底只升不降）")

    -- ========== 7) 点金石后期出口：品质上限后转词缀提品 ==========
    newModules()
    -- maxStageId=0 → getUpgradeMaxQuality=4（史诗），装备 q4 即达上限
    local e5 = putEquip(makeWeapon(4))
    e5.affixes = {
        { affixId = 5, quality = 2, value = 10, key = "str", name = "力量" },
    }
    local okD, errD, resD = BS.RefineEquip(UID, e5.seq, "destroyStone")
    check(okD, "点金石品质上限后仍可用: " .. tostring(errD))
    check(resD and resD.affixGradeUp ~= nil, "回包携带 affixGradeUp")
    eq(e5.quality, 4, "品质不变（仍为上限4）")
    eq(e5.affixes[1].quality, 3, "单条词缀品级 2→3（确定性）")
    local okD2, _, resD2 = BS.RefineEquip(UID, e5.seq, "destroyStone")
    check(okD2 and resD2.affixGradeUp and resD2.affixGradeUp.afterQ == 4, "第二次提品 3→4")

    -- 全 S 品后拒绝
    newModules()
    local e6 = putEquip(makeWeapon(4))
    e6.affixes = {
        { affixId = 5, quality = 5, value = 10, key = "str", name = "力量" },
    }
    local okD3, errD3 = BS.RefineEquip(UID, e6.seq, "destroyStone")
    check(not okD3, "全S品且品质上限后点金石被拒绝: " .. tostring(errD3))

    -- ========== 8) 升阶投入经过腐化、读档、净化后保真 ==========
    newModules()
    local eRound = putEquip(makeWeapon(5))
    eRound.affixes = {
        { affixId = 1, quality = 3, value = 10, key = "str", name = "力量", ascBonus = 7 },
        { affixId = 2, quality = 3, value = 20, key = "agi", name = "敏捷", ascBonus = 11 },
    }
    local okRound = BS.RefineEquip(UID, eRound.seq, "corruptStone")
    check(okRound, "带升阶投入的词条可腐化")
    local roundPatch = eRound.corruptRevert.patches[1]
    local roundIdx = roundPatch[2]
    local roundBefore = roundPatch[3]
    local roundValue = eRound.affixes[roundIdx].value
    eq(eRound.affixes[roundIdx].ascBonus, nil, "转换后魔化槽不持有普通加成")
    check((tonumber(roundBefore.ascBonus) or 0) > 0, "转换快照保留原普通升阶投入")
    local roundRestored = cjson.decode(cjson.encode(EquipmentSystem.dehydrate(eRound)))
    EquipmentSystem.hydrate(roundRestored)
    eq(roundRestored.affixes[roundIdx].value, roundValue, "读档不重算魔化转换增幅")
    check(roundRestored.corruptRevert.patches[1][1] == "c", "JSON 往返恢复转换 patch 数字索引")
    eRound.affixes = roundRestored.affixes
    eRound.corruptRevert = roundRestored.corruptRevert
    local okWash = BS.RefineEquip(UID, eRound.seq, "sacredStone")
    check(okWash, "读档后神圣石可净化")
    eq(eRound.affixes[roundIdx].affixId, roundBefore.affixId, "净化恢复原词条类型")
    eq(eRound.affixes[roundIdx].ascBonus, roundBefore.ascBonus, "净化恢复原升阶投入")

    -- ========== 9) 魔化夹在普通槽之间时，洗练替换仍按原槽保留投入 ==========
    newModules()
    local eMixed = putEquip(makeWeapon(5))
    eMixed.affixes = {
        { affixId = 1, quality = 3, value = 10, key = "str", name = "力量", ascBonus = 7 },
        { affixId = 1001, quality = 0, value = 5, key = "finalPhysAtkBonus", name = "最终物攻" },
        { affixId = 2, quality = 3, value = 20, key = "agi", name = "敏捷", ascBonus = 11 },
    }
    local okMixed = BS.RefineEquip(UID, eMixed.seq, nil)
    check(okMixed, "混合词条可普通洗练")
    check(BS.RefineReplace(UID, eMixed.seq), "混合词条可替换洗练结果")
    eq(eMixed.affixes[1].ascBonus, 7, "混合槽1保留升阶投入")
    eq(eMixed.affixes[2].ascBonus, nil, "混合槽2魔化不获得普通投入")
    eq(eMixed.affixes[3].ascBonus, 11, "混合槽3保留升阶投入")

    -- 旧品质魔化纠错与无数值旧档仍按模板修复。
    local oldCorrupt = { affixId = 1001, quality = 5, value = 999999 }
    EquipmentSystem.ensureAffixValue(oldCorrupt, eMixed)
    eq(oldCorrupt.quality, 0, "旧魔化品质增幅清零")
    check(oldCorrupt.value < 999999, "旧魔化错误高值仍按模板纠正")
    oldCorrupt.value = nil
    EquipmentSystem.ensureAffixValue(oldCorrupt, eMixed)
    check((tonumber(oldCorrupt.value) or 0) > 0, "旧魔化缺失数值可补齐")

    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS")
    else
        print(PREFIX .. "RESULT " .. #failures .. " FAIL")
    end
    engine:Exit()
end
