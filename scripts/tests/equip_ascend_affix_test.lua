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

        -- 生效值 = 基础值 × 倍率 + ascBonus（普通词条）；魔化词条两者都不吃
        local normal = e10.affixes[1]
        local ascB10 = tonumber(normal.ascBonus) or 0
        local eff = EquipmentSystem.effectiveAffixValue(e10, normal)
        check(math.abs(eff - (normal.value * 1.2 + ascB10)) < 1e-9, "普通词条生效值=value×1.2+ascBonus")
        local corruptAffix = { affixId = 1001, quality = 0, value = 7, key = "finalPhysAtkBonus", name = "最终物攻" }
        eq(EquipmentSystem.effectiveAffixValue(e10, corruptAffix), 7, "魔化词条不吃倍率")

        -- 战斗属性管线吃到倍率+ascBonus
        local entriesM = EquipmentSystem.computeModifierEntries(e10, 0)
        local foundScaled = false
        for _, en in ipairs(entriesM) do
            if en.key == normal.key and math.abs(en.flat - (normal.value * 1.2 + ascB10)) < 1e-9 then
                foundScaled = true
            end
        end
        check(foundScaled, "computeModifierEntries 输出含倍率+ascBonus 放大值")

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

        -- 腐化装备满员后倍率升级也生效，且洗除诅咒不丢倍率
        -- 构筑模型：腐化石会把 1 条普通转魔化，故夹具用 5 普通，转换后普通恰好满员 4
        newModules()
        local e12 = putEquip(makeWeapon(5))
        e12.affixes = {
            { affixId = 1, quality = 3, value = 10, key = "str", name = "力量" },
            { affixId = 2, quality = 3, value = 10, key = "agi", name = "敏捷" },
            { affixId = 3, quality = 3, value = 10, key = "int", name = "秘识" },
            { affixId = 4, quality = 3, value = 10, key = "vit", name = "体质" },
            { affixId = 9, quality = 3, value = 10, key = "luk", name = "运气" },
        }
        BS.AscendEquipToLevel(UID, e12.seq, 5)
        eq(EquipmentSystem.getAffixMult(e12), 1.1, "满员后里程碑→倍率1.1")
        local okC12 = BS.RefineEquip(UID, e12.seq, "corruptStone")
        check(okC12, "腐化成功")
        eq(normalAffixCount(e12), 4, "转换后普通恰满员 4")
        BS.AscendEquipToLevel(UID, e12.seq, 10)
        eq(EquipmentSystem.getAffixMult(e12), 1.2, "腐化态满员升阶倍率继续累加")
        local okC12b = BS.RefineEquip(UID, e12.seq, "sacredStone")
        check(okC12b, "洗除诅咒成功")
        eq(EquipmentSystem.getAffixMult(e12), 1.2, "洗除诅咒不丢倍率")

        -- ========== 11) 升阶副属性递增（每阶轮转 1 条普通词条 +5% 当前 value） ==========
        eq(BlacksmithConfig.ASCEND_SUB_STAT_RATIO, 0.05, "副属性步长比例=5%")

        -- 11a) q4 双词条轮转顺序：+1→词条1, +2→词条2, +3→词条1, +4→词条2
        newModules()
        local s1 = putEquip(makeWeapon(4))
        local v1 = s1.affixes[1].value
        local v2 = s1.affixes[2].value
        BS.AscendEquipToLevel(UID, s1.seq, 4)
        eq(s1.affixes[1].ascBonus, v1 * 0.05 * 2, "词条1 轮转 2 次=+10%")
        eq(s1.affixes[2].ascBonus, v2 * 0.05 * 2, "词条2 轮转 2 次=+10%")

        -- 11b) 生效值 = value×倍率 + ascBonus（倍率=1 时即 value+ascBonus）
        local effS1 = EquipmentSystem.effectiveAffixValue(s1, s1.affixes[1])
        check(math.abs(effS1 - (v1 + v1 * 0.1)) < 1e-9, "生效值含 ascBonus")
        local entriesS = EquipmentSystem.computeModifierEntries(s1, 0)
        local foundAsc = false
        for _, en in ipairs(entriesS) do
            if en.key == s1.affixes[1].key and math.abs(en.flat - effS1) < 1e-9 then
                foundAsc = true
            end
        end
        check(foundAsc, "computeModifierEntries 输出含 ascBonus 加成")

        -- 11c) 单阶与一键同种子等价（轮转确定性，无随机）
        newModules()
        local sX = putEquip(makeWeapon(3))
        local sY = putEquip(makeWeapon(3))
        sY.affixes = {}
        for _, a in ipairs(sX.affixes) do
            sY.affixes[#sY.affixes + 1] = {
                affixId = a.affixId, quality = a.quality, value = a.value,
                key = a.key, name = a.name,
            }
        end
        math.randomseed(931)
        BS.AscendEquipToLevel(UID, sX.seq, 6)
        math.randomseed(931)
        for _ = 1, 6 do BS.AscendEquip(UID, sY.seq) end
        local sameAsc = #sX.affixes == #sY.affixes
        for i = 1, #sX.affixes do
            if (tonumber(sX.affixes[i].ascBonus) or 0) ~= (tonumber(sY.affixes[i].ascBonus) or 0) then
                sameAsc = false
            end
        end
        check(sameAsc, "单阶与一键 ascBonus 逐条一致")

        -- 11d) 洗练重随/替换不丢 ascBonus（按位置转移）
        newModules()
        local s2 = putEquip(makeWeapon(4))
        BS.AscendEquipToLevel(UID, s2.seq, 4)
        local bonusBefore = { s2.affixes[1].ascBonus, s2.affixes[2].ascBonus }
        local okR2a = BS.RefineEquip(UID, s2.seq, nil)
        check(okR2a, "带 ascBonus 可洗练")
        local okR2b = BS.RefineReplace(UID, s2.seq)
        check(okR2b, "洗练替换成功")
        eq(s2.affixes[1].ascBonus, bonusBefore[1], "替换后槽1 ascBonus 保留")
        eq(s2.affixes[2].ascBonus, bonusBefore[2], "替换后槽2 ascBonus 保留")
        local okR2c = BS.RefineEquip(UID, s2.seq, "enhanceStone")
        check(okR2c, "洗练石可用")
        BS.RefineReplace(UID, s2.seq)
        eq(s2.affixes[1].ascBonus, bonusBefore[1], "洗练石路径 ascBonus 保留")

        -- 11e) 魔化词条不轮转不持有；净化后普通槽位保留
        newModules()
        local s3 = putEquip(makeWeapon(5))
        s3.affixes = {
            { affixId = 1, quality = 3, value = 10, key = "str", name = "力量" },
            { affixId = 1001, quality = 0, value = 5, key = "finalPhysAtkBonus", name = "最终物攻" },
            { affixId = 2, quality = 3, value = 10, key = "agi", name = "敏捷" },
        }
        BS.AscendEquipToLevel(UID, s3.seq, 3)
        eq(s3.affixes[2].ascBonus, nil, "魔化词条不持有 ascBonus")
        eq(s3.affixes[1].ascBonus, 10 * 0.05 * 2, "普通槽1 轮转 2 次（跳过魔化槽）")
        eq(s3.affixes[3].ascBonus, 10 * 0.05 * 1, "普通槽2 轮转 1 次")

        -- 11f) q1 零词条阶段跳过不补债；出词条后开始轮转
        newModules()
        local s4 = putEquip(makeWeapon(1))
        BS.AscendEquipToLevel(UID, s4.seq, 4)
        eq(#s4.affixes, 0, "+4 仍无词条")
        BS.AscendEquipToLevel(UID, s4.seq, 5)
        eq(#s4.affixes, 1, "+5 里程碑出首条")
        eq(s4.affixes[1].ascBonus, nil, "首条当阶起轮转：+5 阶轮转到槽1 得 1 次? 见下验证")
        -- +5 阶：轮转在里程碑新增之前执行（normalCount=0 跳过），故首条 +5 阶当阶无加成
        BS.AscendEquipToLevel(UID, s4.seq, 6)
        check((tonumber(s4.affixes[1].ascBonus) or 0) > 0, "+6 阶首条获得 ascBonus")

        -- 11g) 存档往返保留 ascBonus
        newModules()
        local s5 = putEquip(makeWeapon(4))
        BS.AscendEquipToLevel(UID, s5.seq, 6)
        local b5 = s5.affixes[1].ascBonus
        local lean5 = EquipmentSystem.dehydrate(s5)
        check(lean5.affixes[1].ascBonus ~= nil, "脱水持久化 ascBonus")
        local restored5 = cjson.decode(cjson.encode(lean5))
        EquipmentSystem.hydrate(restored5)
        -- cjson 默认 14 位有效数字序列化，用容差比较
        check(math.abs((tonumber(restored5.affixes[1].ascBonus) or -1) - b5) < 1e-9,
            "JSON 往返 ascBonus 保真")

        -- 11h) 洗练换成低值属性后，读档和再次升阶不裁掉之前的固定投入
        newModules()
        local sLow = putEquip(makeWeapon(4))
        sLow.affixes = {
            { affixId = 1, quality = 3, value = 1, key = "str", name = "力量", ascBonus = 40 },
        }
        local lowRestored = cjson.decode(cjson.encode(EquipmentSystem.dehydrate(sLow)))
        EquipmentSystem.hydrate(lowRestored)
        eq(lowRestored.affixes[1].ascBonus, 40, "低值词条读档保留历史升阶投入")
        sLow.affixes = lowRestored.affixes
        BS.AscendEquip(UID, sLow.seq)
        check((tonumber(sLow.affixes[1].ascBonus) or 0) > 40, "再次升阶不裁掉旧投入")

        -- 11i) hydrate 清理非有限值，有限正值不依赖当前词条数值
        newModules()
        local s6 = putEquip(makeWeapon(4))
        s6.affixes[1].ascBonus = -5
        s6.affixes[2].ascBonus = 10 ^ 9
        EquipmentSystem.hydrate(s6)
        eq(s6.affixes[1].ascBonus, nil, "负值清理为 nil")
        eq(s6.affixes[2].ascBonus, 10 ^ 9, "有限正值保留，不按当前 value 裁剪")
        s6.affixes[1].ascBonus = 0 / 0
        s6.affixes[2].ascBonus = math.huge
        EquipmentSystem.hydrate(s6)
        eq(s6.affixes[1].ascBonus, nil, "NaN 清理为 nil")
        eq(s6.affixes[2].ascBonus, nil, "无穷值清理为 nil")
        s6.affixes[1] = {
            affixId = 1001, quality = 0, value = 5, key = "finalPhysAtkBonus", ascBonus = 40,
        }
        EquipmentSystem.hydrate(s6)
        eq(s6.affixes[1].ascBonus, nil, "魔化词条不保留普通升阶加成")
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
