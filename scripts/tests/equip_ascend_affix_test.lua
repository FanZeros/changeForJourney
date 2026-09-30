-- ============================================================================
-- equip_ascend_affix_test.lua — 装备升阶随机词条回归
-- 规则（2026-09-30 用户拍板）：
--   所有品质可参与；每跨过 +5 的倍数阶必定新增 1 条普通词条；
--   普通词条总数上限 4；魔化词条不占普通上限；升阶词条净化不删。
-- 验证：
--   1) 普通品质(q1, 0词条)升到 +5/+10/+15/+20 逐个里程碑各得 1 条，+25 满员不再得
--   2) 单阶与一键路径在同一随机种子下逐条一致
--   3) 新增词条 key 与已有词条互斥（无重复属性）
--   4) 魔化词条不占普通上限（2普通+1魔化 → 升阶后普通可到 4）
--   5) 腐化期间升阶所得词条，神圣石净化后保留；魔化新增词条被移除
--   6) 脱水→JSON→水合 存档往返词条/升阶等级保真
--   7) computeModifierEntries 词条数随升阶增加（属性管线生效）
--   8) 普通品质装备经升阶获得词条后，普通洗练/洗练石不再被品质门槛拒绝
-- 跑法: cd scripts && ../.cli/UrhoXRuntime tests/equip_ascend_affix_test.lua \
--         -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local PREFIX = "[equip_ascend_affix] "
local failures = {}
local function check(cond, msg)
    if cond then print(PREFIX .. "[PASS] " .. msg)
    else print(PREFIX .. "[FAIL] " .. msg); failures[#failures + 1] = msg end
end
local function eq(actual, expected, msg)
    check(actual == expected, msg .. " (实际=" .. tostring(actual) .. " 期望=" .. tostring(expected) .. ")")
end

local EquipmentSystem  = require("systems.EquipmentSystem")
local EquipmentConfig  = require("config.EquipmentConfig")
local AffixConfig      = require("config.AffixConfig")
local BlacksmithConfig = require("config.BlacksmithConfig")
local PDM              = require("rules.character.PlayerDataManager")
local TaskService      = require("rules.task.TaskService")

-- ======================== 测试环境 ========================

local UID = 1
local modules = {}
local dirtyCount = {}
PDM.GetModule = function(_, name) return modules[name] end
PDM.MarkDirty = function(_, fieldKey) dirtyCount[fieldKey] = (dirtyCount[fieldKey] or 0) + 1 end
PDM.FlushImmediate = function() end
TaskService.UpdateProgress = function() end

modules.player = { level = 200 }  -- 升阶上限 = 远征等级，200 级放开到表封顶

local function newCurrency()
    return {
        gold = 10 ^ 12, essence = 10 ^ 9,
        weaponScroll = 10 ^ 6, offhandScroll = 10 ^ 6, armorScroll = 10 ^ 6,
        helmetScroll = 10 ^ 6, shoesScroll = 10 ^ 6, accessoryScroll = 10 ^ 6,
        enhanceStone = 10, destroyStone = 10, corruptStone = 10, sacredStone = 10,
    }
end

local nextSeq = 1
local function putEquip(equip)
    equip.seq = nextSeq
    modules.equipment.inventory[tostring(nextSeq)] = equip
    nextSeq = nextSeq + 1
    return equip
end

local function newModules()
    modules.equipment = { inventory = {}, equipped = {}, nextSeq = 1 }
    modules.currency = newCurrency()
    modules.battle = { maxStageId = 0, currentStageId = 0 }
    dirtyCount = {}
end

--- W1 练习用剑 lv1-16 单手武器（真实模板）
local function makeWeapon(quality, level)
    local equip = EquipmentSystem.generate("W1", level or 10, quality)
    assert(equip, "fixture weapon must generate")
    EquipmentSystem.hydrate(equip)
    return equip
end

local function normalAffixCount(equip)
    local n = 0
    for _, a in ipairs(equip.affixes or {}) do
        if not AffixConfig.isCorruptAffix(a) then n = n + 1 end
    end
    return n
end

local function affixKeys(affixes)
    local keys = {}
    for _, a in ipairs(affixes or {}) do keys[#keys + 1] = a.key end
    return keys
end

local BS = require("rules.blacksmith.BlacksmithService")

function Start()
    print(PREFIX .. "start")
    local ok, err = pcall(function()
        eq(BlacksmithConfig.ASCEND_AFFIX_INTERVAL, 5, "里程碑间隔=5")
        eq(BlacksmithConfig.ASCEND_NORMAL_AFFIX_LIMIT, 4, "普通词条上限=4")

        -- ========== 1) 普通品质逐里程碑必得，满员封顶 ==========
        newModules()
        local e1 = putEquip(makeWeapon(1))
        eq(#(e1.affixes or {}), 0, "q1 初始 0 词条")
        local okA, errA, resA = BS.AscendEquipToLevel(UID, e1.seq, 5)
        check(okA, "升到+5成功: " .. tostring(errA))
        eq(#resA.gainedAffixes, 1, "+5 里程碑得 1 条")
        eq(normalAffixCount(e1), 1, "普通词条=1")

        BS.AscendEquipToLevel(UID, e1.seq, 10)
        eq(normalAffixCount(e1), 2, "+10 后普通词条=2")
        BS.AscendEquipToLevel(UID, e1.seq, 15)
        eq(normalAffixCount(e1), 3, "+15 后普通词条=3")
        BS.AscendEquipToLevel(UID, e1.seq, 20)
        eq(normalAffixCount(e1), 4, "+20 后普通词条=4（达上限）")
        local okFull, _, resFull = BS.AscendEquipToLevel(UID, e1.seq, 30)
        check(okFull, "满员后仍可继续升阶")
        eq(#resFull.gainedAffixes, 0, "满员后里程碑不再新增")
        eq(normalAffixCount(e1), 4, "普通词条保持 4")
        eq(EquipmentSystem.getAscendLevel(e1), 30, "升阶等级=30")

        -- ========== 2) 单阶与一键同种子等价 ==========
        newModules()
        local eX = putEquip(makeWeapon(3))
        local eY = putEquip(makeWeapon(3))
        -- Y 初始词条强制与 X 一致（深拷贝），保证两条路径起点相同
        eY.affixes = {}
        for _, a in ipairs(eX.affixes) do
            eY.affixes[#eY.affixes + 1] = {
                affixId = a.affixId, quality = a.quality, value = a.value,
                key = a.key, name = a.name,
            }
        end
        math.randomseed(930)
        BS.AscendEquipToLevel(UID, eX.seq, 5)          -- 一键 0→5
        math.randomseed(930)
        for _ = 1, 5 do BS.AscendEquip(UID, eY.seq) end -- 单阶 ×5
        eq(EquipmentSystem.getAscendLevel(eY), 5, "单阶路径到达+5")
        eq(#eX.affixes, #eY.affixes, "单阶与一键词条数一致")
        local identical = #eX.affixes == #eY.affixes
        for i = 1, #eX.affixes do
            local a, b = eX.affixes[i], eY.affixes[i]
            if a.affixId ~= b.affixId or a.quality ~= b.quality or a.value ~= b.value then
                identical = false
            end
        end
        check(identical, "同种子下单阶与一键新增词条逐条一致")

        -- ========== 3) 新增词条 key 互斥 ==========
        newModules()
        local e3 = putEquip(makeWeapon(6))
        BS.AscendEquipToLevel(UID, e3.seq, 20)
        local seen = {}
        local dupFound = false
        for _, k in ipairs(affixKeys(e3.affixes)) do
            if seen[k] then dupFound = true end
            seen[k] = true
        end
        check(not dupFound, "全部词条 key 互斥（含初始+升阶）")

        -- ========== 4) 魔化词条不占普通上限 ==========
        newModules()
        local e4 = putEquip(makeWeapon(5))
        e4.affixes = {
            { affixId = 1, quality = 3, value = 10, key = "str", name = "力量" },
            { affixId = 2, quality = 3, value = 10, key = "agi", name = "敏捷" },
            { affixId = 1001, quality = 0, value = 5, key = "finalPhysAtkBonus", name = "最终物攻" },
        }
        eq(normalAffixCount(e4), 2, "夹具：2普通+1魔化")
        BS.AscendEquipToLevel(UID, e4.seq, 10)
        eq(normalAffixCount(e4), 4, "两个里程碑后普通=4（魔化不占额）")
        eq(#e4.affixes, 5, "总词条=5（4普通+1魔化）")
        BS.AscendEquipToLevel(UID, e4.seq, 15)
        eq(normalAffixCount(e4), 4, "普通满员后不再增")
        eq(#e4.affixes, 5, "总词条仍=5")

        -- ========== 5) 腐化期间升阶，净化保留升阶词条 ==========
        newModules()
        local e5 = putEquip(makeWeapon(5))
        e5.affixes = {
            { affixId = 1, quality = 3, value = 10, key = "str", name = "力量" },
            { affixId = 2, quality = 3, value = 99, key = "agi", name = "敏捷" },   -- 被腐化改过值
            { affixId = 1002, quality = 0, value = 5, key = "finalMagAtkBonus", name = "最终魔攻" }, -- 腐化新增
        }
        e5.corruptCount = 1
        e5.corruptRevert = { affixCount = 2, patches = { { "s", 2, 8 }, { "a" } } }  -- agi 原值 8；尾部 +1 为魔化
        BS.AscendEquipToLevel(UID, e5.seq, 5)
        eq(#e5.affixes, 4, "腐化态升阶新增 1 条")
        eq(e5.corruptRevert.affixCount, 3, "净化保留段计入升阶词条")
        -- 升阶词条应插在保留段（前 3 条），魔化仍在尾部
        check(AffixConfig.isCorruptAffix(e5.affixes[4]), "魔化词条仍在尾部")
        check(not AffixConfig.isCorruptAffix(e5.affixes[3]), "升阶词条位于保留段")

        local okC, errC = BS.RefineEquip(UID, e5.seq, "sacredStone")
        check(okC, "净化成功: " .. tostring(errC))
        eq(#e5.affixes, 3, "净化移除魔化词条，保留 2 原词条 + 1 升阶词条")
        eq(e5.corruptCount, nil, "腐化状态清空")
        check(not AffixConfig.isCorruptAffix(e5.affixes[3]), "净化后升阶词条仍在")
        eq(e5.affixes[2].value, 8, "改值 patch 索引正确（agi 恢复原值 8）")

        -- ========== 6) 存档往返 ==========
        newModules()
        local e6 = putEquip(makeWeapon(1))
        BS.AscendEquipToLevel(UID, e6.seq, 10)
        eq(normalAffixCount(e6), 2, "往返前普通词条=2")
        local lean = EquipmentSystem.dehydrate(e6)
        local restored = cjson.decode(cjson.encode(lean))
        EquipmentSystem.hydrate(restored)
        eq(EquipmentSystem.getAscendLevel(restored), 10, "往返后升阶等级=10")
        eq(normalAffixCount(restored), 2, "往返后普通词条=2")
        local keysBefore, keysAfter = affixKeys(e6.affixes), affixKeys(restored.affixes)
        local keysSame = #keysBefore == #keysAfter
        for i = 1, #keysBefore do
            if keysBefore[i] ~= keysAfter[i] then keysSame = false end
        end
        check(keysSame, "往返后词条 key 序列一致")

        -- ========== 7) 属性管线生效 ==========
        local entriesBefore = #EquipmentSystem.computeModifierEntries(makeWeapon(1), 0)
        local entries = #EquipmentSystem.computeModifierEntries(e6, EquipmentSystem.getAscendBoost(e6))
        local baseCount = #(e6.baseStats or {})
        eq(entries - baseCount, 2, "computeModifierEntries 含 2 条词条 modifier")
        check(entries > entriesBefore, "词条使 modifier 条目增加")

        -- ========== 8) 普通品质升阶后可洗练 ==========
        newModules()
        local e8 = putEquip(makeWeapon(1))
        local okR0, errR0 = BS.RefineEquip(UID, e8.seq, nil)
        check(not okR0, "无词条 q1 洗练仍被拒绝: " .. tostring(errR0))
        BS.AscendEquipToLevel(UID, e8.seq, 5)
        eq(normalAffixCount(e8), 1, "q1 升阶后有词条")
        local okR, errR, resR = BS.RefineEquip(UID, e8.seq, nil)
        check(okR, "q1 带词条可普通洗练: " .. tostring(errR))
        eq(#resR.refinePreview, 1, "洗练预览词条数=1")
        local okR2, errR2 = BS.RefineEquip(UID, e8.seq, "enhanceStone")
        check(okR2, "q1 带词条可用洗练石: " .. tostring(errR2))

        -- ========== 9) 里程碑边界：+4→+5 得、+5→+9 不得 ==========
        newModules()
        local e9 = putEquip(makeWeapon(2))
        local base9 = normalAffixCount(e9)
        e9.ascendLevel = 4
        e9.enhanceLevel = 4
        local ok9, _, res9 = BS.AscendEquip(UID, e9.seq)
        check(ok9 and #res9.gainedAffixes == 1, "+4→+5 单阶得 1 条")
        eq(normalAffixCount(e9), math.min(4, base9 + 1), "普通词条 +1")
        local _, _, res9b = BS.AscendEquipToLevel(UID, e9.seq, 9)
        eq(#res9b.gainedAffixes, 0, "+5→+9 无里程碑不得词条")
        local _, _, res9c = BS.AscendEquip(UID, e9.seq)
        eq(#res9c.gainedAffixes, 1, "+9→+10 单阶得 1 条")

        -- ========== 10) 满员后里程碑转为栏位倍率升级（洗练不丢） ==========
        newModules()
        local e10 = putEquip(makeWeapon(4))
        eq(normalAffixCount(e10), 2, "q4 初始 2 词条")
        eq(EquipmentSystem.getAffixMult(e10), 1, "初始倍率=1")
        local _, _, r10a = BS.AscendEquipToLevel(UID, e10.seq, 10)   -- 里程碑 +5/+10 → 满 4 条
        eq(normalAffixCount(e10), 4, "两个里程碑补满 4 条")
        eq(r10a.multUps, 0, "未满员阶段无倍率升级")
        eq(EquipmentSystem.getAffixMult(e10), 1, "倍率仍=1")

        local _, _, r10b = BS.AscendEquipToLevel(UID, e10.seq, 20)   -- +15/+20 → 2 次倍率
        eq(#r10b.gainedAffixes, 0, "满员后不再新增词条")
        eq(r10b.multUps, 2, "两个里程碑转倍率升级 ×2")
        eq(EquipmentSystem.getAffixMult(e10), 1.2, "倍率=1.2（每层+10%）")
        eq(r10b.affixMult, 1.2, "回包携带 affixMult")

        -- 生效值 = 基础值 × 倍率（普通词条）；魔化词条不吃倍率
        local normal = e10.affixes[1]
        local eff = EquipmentSystem.effectiveAffixValue(e10, normal)
        check(math.abs(eff - normal.value * 1.2) < 1e-9, "普通词条生效值=value×1.2")
        local corruptAffix = { affixId = 1001, quality = 0, value = 7, key = "finalPhysAtkBonus", name = "最终物攻" }
        eq(EquipmentSystem.effectiveAffixValue(e10, corruptAffix), 7, "魔化词条不吃倍率")

        -- 战斗属性管线吃到倍率
        local entriesM = EquipmentSystem.computeModifierEntries(e10, 0)
        local foundScaled = false
        for _, en in ipairs(entriesM) do
            if en.key == normal.key and math.abs(en.flat - normal.value * 1.2) < 1e-9 then
                foundScaled = true
            end
        end
        check(foundScaled, "computeModifierEntries 输出含倍率放大值")

        -- 洗练（普通重随 + 替换）不丢倍率
        local okW, errW = BS.RefineEquip(UID, e10.seq, nil)
        check(okW, "满员装备可洗练: " .. tostring(errW))
        local okRep = BS.RefineReplace(UID, e10.seq)
        check(okRep, "洗练替换成功")
        eq(EquipmentSystem.getAffixMult(e10), 1.2, "洗练+替换后倍率不丢")
        eq(normalAffixCount(e10), 4, "洗练后词条数不变")

        -- 洗练石（保种类重随数值）同样不丢倍率
        local okS = BS.RefineEquip(UID, e10.seq, "enhanceStone")
        check(okS, "洗练石可用")
        BS.RefineReplace(UID, e10.seq)
        eq(EquipmentSystem.getAffixMult(e10), 1.2, "洗练石路径倍率不丢")

        -- 存档往返保留倍率
        local lean10 = EquipmentSystem.dehydrate(e10)
        eq(lean10.affixMult, 1.2, "脱水保留 affixMult")
        local restored10 = cjson.decode(cjson.encode(lean10))
        EquipmentSystem.hydrate(restored10)
        eq(EquipmentSystem.getAffixMult(restored10), 1.2, "JSON 往返后倍率=1.2")
        local leanNoMult = EquipmentSystem.dehydrate(makeWeapon(1))
        eq(leanNoMult.affixMult, nil, "倍率=1 时脱水省略字段")

        -- 浮点精度：多层累加不漂移（0→100 共 20 里程碑，q4 补 2 条后 18 层 → 1+1.8=2.8）
        newModules()
        local e11 = putEquip(makeWeapon(4))
        BS.AscendEquipToLevel(UID, e11.seq, 100)
        eq(normalAffixCount(e11), 4, "e11 词条补满")
        eq(EquipmentSystem.getAffixMult(e11), 2.8, "18 层倍率累加=2.8（无浮点漂移）")

        -- 腐化装备满员后倍率升级也生效，且净化不丢倍率
        newModules()
        local e12 = putEquip(makeWeapon(5))
        e12.affixes = {
            { affixId = 1, quality = 3, value = 10, key = "str", name = "力量" },
            { affixId = 2, quality = 3, value = 10, key = "agi", name = "敏捷" },
            { affixId = 3, quality = 3, value = 10, key = "int", name = "秘识" },
            { affixId = 4, quality = 3, value = 10, key = "vit", name = "体质" },
        }
        BS.AscendEquipToLevel(UID, e12.seq, 5)
        eq(EquipmentSystem.getAffixMult(e12), 1.1, "满员4条后里程碑→倍率1.1")
        local okC12 = BS.RefineEquip(UID, e12.seq, "corruptStone")
        check(okC12, "腐化成功")
        BS.AscendEquipToLevel(UID, e12.seq, 10)
        eq(EquipmentSystem.getAffixMult(e12), 1.2, "腐化态满员升阶倍率继续累加")
        local okC12b = BS.RefineEquip(UID, e12.seq, "sacredStone")
        check(okC12b, "净化成功")
        eq(EquipmentSystem.getAffixMult(e12), 1.2, "净化不丢倍率")
    end)
    if not ok then
        print(PREFIX .. "[FAIL] 测试抛异常: " .. tostring(err))
        failures[#failures + 1] = "exception: " .. tostring(err)
    end

    if #failures == 0 then
        print(PREFIX .. "RESULT ALL PASS")
    else
        print(PREFIX .. "RESULT FAIL " .. #failures)
        for _, f in ipairs(failures) do print(PREFIX .. "  - " .. f) end
    end
    engine:Exit()
end
