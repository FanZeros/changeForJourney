-- ============================================================================
-- battle_lab_boundary_test.lua — BattleLab.prepare 校验边界回归
-- 覆盖「战力校准样本」的全部拒绝分支与合法边界（不跑战斗，只测 prepare）：
--   1) stageId：缺省/未知关卡/终焉神殿 idle 拒绝
--   2) heroes：数量 0/5 拒绝、重复 ID、不存在 ID、等级钳制 1..345、NaN/inf 兜底
--   3) runs/seed/timeLimit 钳制边界（1..1000 / 1..2147483646 / 1..600）
--   4) loadouts：结构、非参战英雄、无效槽位、模板与槽位不符、职业不可穿戴
--   5) 装备等级 levelRange 边界（本次校准的核心拒绝规则）：
--      C1={1,7} → Lv1/Lv7 合法、Lv0/Lv8/非整数/>9999 拒绝
--      C2={8,9999} → Lv8 合法（跨档下边界）、Lv7 拒绝、Lv9999 合法
--   6) ascendLevel 0..100 边界；quality/affixes 出现即拒绝
--   7) 双手武器 + 副手互斥；单手 + 副手合法
--   8) CombatPowerEstimate 分项计价原型：同官方战力下战士/法师方向区分
-- 跑法: ./.cli/UrhoXRuntime tests/battle_lab_boundary_test.lua \
--         -tapcode_dir=<项目根> -tool_mode -graphicsheadless
-- ============================================================================

local Lab = require("tests.BattleLab")

local failures = {}

local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        print("[FAIL] " .. msg)
        failures[#failures + 1] = msg
    end
end

--- 断言 prepare 拒绝，且错误信息包含关键字
local function expectReject(config, keyword, label)
    local prepared, err = Lab.prepare(config)
    check(prepared == nil, label .. ": 被拒绝")
    check(type(err) == "string" and err:find(keyword, 1, true) ~= nil,
        label .. ": 错误含「" .. keyword .. "」，实得 " .. tostring(err))
end

--- 断言 prepare 通过并返回 prepared 表
local function expectAccept(config, label)
    local prepared, err = Lab.prepare(config)
    check(prepared ~= nil, label .. ": 通过（" .. tostring(err) .. "）")
    return prepared
end

local function baseConfig(overrides)
    local config = {
        stageId = 101, mode = "firstClear", runs = 4, seed = 926,
        timeLimit = 60, heroes = { { id = 1, level = 1 } },
    }
    for key, value in pairs(overrides or {}) do config[key] = value end
    return config
end

-- ── 1) 关卡边界 ──
local function testStage()
    -- 注意：pairs 不遍历 nil 值，缺省分支要显式置 nil
    local noStage = baseConfig()
    noStage.stageId = nil
    local prepared = expectAccept(noStage, "stageId 缺省回落首关")
    check(prepared and prepared.stageId == 101, "缺省 stageId = 101（NORMAL_FIRST_STAGE）")

    expectReject(baseConfig({ stageId = 99998 }), "未知关卡", "不存在的关卡 99998")

    prepared = expectAccept(baseConfig({ stageId = 999 }), "终焉神殿 firstClear 合法")
    check(prepared and prepared.stage.mode == "terminal", "终焉神殿 mode=terminal")

    expectReject(baseConfig({ stageId = 999, mode = "idle" }), "终焉神殿没有挂机敌人",
        "终焉神殿 + idle 拒绝")

    prepared = expectAccept(baseConfig({ stageId = "abc" }), "stageId 非数字回落缺省")
    check(prepared and prepared.stageId == 101, "非数字 stageId 钳回缺省 101")
end

-- ── 2) 英雄列表边界 ──
local function testHeroes()
    local noHeroes = baseConfig()
    noHeroes.heroes = nil
    expectReject(noHeroes, "heroes", "heroes 缺失拒绝")
    expectReject(baseConfig({ heroes = {} }), "heroes", "heroes 空表拒绝")
    expectReject(baseConfig({ heroes = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 5 } } }),
        "heroes", "5 个英雄超上限拒绝")

    local prepared = expectAccept(
        baseConfig({ heroes = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } } }),
        "4 个英雄上边界合法")
    check(prepared and #prepared.heroes == 4, "4 英雄通过数量上边界")

    expectReject(baseConfig({ heroes = { { id = 1 }, { id = 1 } } }), "重复英雄", "重复英雄 ID 拒绝")
    expectReject(baseConfig({ heroes = { { id = 999 } } }), "不存在", "英雄 ID 999 不存在拒绝")

    prepared = expectAccept(baseConfig({ heroes = { { id = 1, level = 0 } } }), "英雄等级 0 钳到 1")
    check(prepared and prepared.heroes[1].level == 1, "level 0 → 1（下边界钳制）")

    prepared = expectAccept(baseConfig({ heroes = { { id = 1, level = 400 } } }), "英雄等级 400 钳到 345")
    check(prepared and prepared.heroes[1].level == 345, "level 400 → 345（MAX_HERO_LEVEL 上边界）")

    prepared = expectAccept(baseConfig({ heroes = { { id = 1, level = 345 } } }), "英雄等级 345 合法")
    check(prepared and prepared.heroes[1].level == 345, "level 345 恰在上边界")

    prepared = expectAccept(baseConfig({ heroes = { { id = 1, level = 0 / 0 } } }), "NaN 等级回落缺省")
    check(prepared and prepared.heroes[1].level == 1, "NaN level → 缺省 1")

    prepared = expectAccept(baseConfig({ heroes = { { id = 1, level = math.huge } } }), "inf 等级回落缺省")
    check(prepared and prepared.heroes[1].level == 1, "inf level → 缺省 1")
end

-- ── 3) runs / seed / timeLimit 钳制 ──
local function testScalarClamp()
    local prepared = expectAccept(baseConfig({ runs = 0 }), "runs 0 钳到 1")
    check(prepared and prepared.runs == 1, "runs 0 → 1")

    prepared = expectAccept(baseConfig({ runs = 5000 }), "runs 5000 钳到 1000")
    check(prepared and prepared.runs == 1000, "runs 5000 → 1000（MAX_RUNS）")

    prepared = expectAccept(baseConfig({ runs = 1000 }), "runs 1000 上边界合法")
    check(prepared and prepared.runs == 1000, "runs 1000 恰在上边界")

    prepared = expectAccept(baseConfig({ seed = 0 }), "seed 0 钳到 1")
    check(prepared and prepared.seed == 1, "seed 0 → 1")

    prepared = expectAccept(baseConfig({ seed = 2147483647 }), "seed 超上界钳到 2147483646")
    check(prepared and prepared.seed == 2147483646, "seed 上边界钳制")

    prepared = expectAccept(baseConfig({ timeLimit = 0 }), "timeLimit 0 钳到 1")
    check(prepared and prepared.timeLimit == 1, "timeLimit 0 → 1")

    prepared = expectAccept(baseConfig({ timeLimit = 9999 }), "timeLimit 9999 钳到 600")
    check(prepared and prepared.timeLimit == 600, "timeLimit 9999 → 600（上边界）")
end

-- ── 4) loadouts 结构边界 ──
local function testLoadoutStructure()
    expectReject(baseConfig({ loadouts = "abc" }), "loadouts", "loadouts 非表拒绝")
    expectReject(baseConfig({ loadouts = { A = {} } }), "loadouts", "缺 B 配装拒绝")
    expectReject(baseConfig({ loadouts = { B = {} } }), "loadouts", "缺 A 配装拒绝")

    local prepared = expectAccept(baseConfig({ loadouts = { A = {}, B = {} } }), "空 A/B 合法（裸英雄对照）")
    check(prepared and prepared.loadouts and prepared.loadouts.A and prepared.loadouts.B,
        "空 loadouts 归一化为 A/B 两表")

    expectReject(baseConfig({ loadouts = { A = { ["2"] = {} }, B = {} } }), "非参战英雄",
        "非参战英雄 ID 出现在 A 拒绝")
    expectReject(baseConfig({ loadouts = { A = {}, B = { ["99"] = {} } } }), "非参战英雄",
        "非参战英雄 ID 出现在 B 拒绝")
    expectReject(baseConfig({ loadouts = { A = { ["1"] = 5 }, B = {} } }), "非参战英雄或无效槽位表",
        "英雄槽位值非表拒绝")
    expectReject(baseConfig({ loadouts = { A = { ["1"] = { foo = { templateId = "C1", level = 1 } } }, B = {} } }),
        "槽位无效", "未知槽位名 foo 拒绝")
    expectReject(baseConfig({ loadouts = { A = { ["1"] = { accessory = 5 } }, B = {} } }),
        "槽位无效", "槽位 spec 非表拒绝")
end

-- ── 5) 装备模板与穿戴边界 ──
local function testTemplateWearable()
    expectReject(baseConfig({ loadouts = { A = { ["1"] = { accessory = { templateId = "ZZZ", level = 1 } } }, B = {} } }),
        "模板与槽位不符", "不存在模板 ZZZ 拒绝")
    expectReject(baseConfig({ loadouts = { A = { ["1"] = { accessory = { templateId = "W1", level = 1 } } }, B = {} } }),
        "模板与槽位不符", "武器模板 W1 放饰品槽拒绝")
    expectReject(baseConfig({ loadouts = { A = { ["1"] = { weapon = { templateId = "W31", level = 1 } } }, B = {} } }),
        "无法穿戴", "战士(1) 穿魔杖 W31 拒绝（职业限制）")

    local prepared = expectAccept(baseConfig({
        loadouts = { A = { ["1"] = { accessory = { templateId = "C1", level = 1 } } },
            B = { ["1"] = { accessory = { templateId = "C13", level = 1 } } },
    } }), "历史合法样本 C1/C13 Lv1 仍通过")
    check(prepared and prepared.loadouts.A[1].accessory.templateId == "C1",
        "C1 归一化到英雄键（数字 ID）")

    -- 双手武器 + 副手互斥（W7 双手剑 lv{1,16}，O1 轻盾 lv{1,16}）
    expectReject(baseConfig({ loadouts = { A = { ["1"] = {
        weapon = { templateId = "W7", level = 1 },
        offhand = { templateId = "O1", level = 1 } } }, B = {} } }),
        "双手武器不可同时穿戴副手", "双手剑 + 轻盾拒绝")

    prepared = expectAccept(baseConfig({ loadouts = { A = { ["1"] = {
        weapon = { templateId = "W7", level = 16 } } }, B = {} } }),
        "双手剑 Lv16（tier 上边界）单独穿戴合法")
    check(prepared and prepared.loadouts.A[1].weapon.level == 16, "双手剑 Lv16 保留")

    prepared = expectAccept(baseConfig({ loadouts = { A = { ["1"] = {
        weapon = { templateId = "W1", level = 1 },
        offhand = { templateId = "O1", level = 1 } } }, B = {} } }),
        "单手剑 + 轻盾组合合法")
    check(prepared and prepared.loadouts.A[1].offhand ~= nil, "单手 + 副手归一化保留")

    -- 三套各挑一件新增模板验证掉落等级与职业可穿类型。
    prepared = expectAccept(baseConfig({ heroes = { { id = 17, level = 70 } },
        loadouts = { A = { ["17"] = {
            weapon = { templateId = "W73", level = 70 },
            offhand = { templateId = "O23", level = 70 } } }, B = {} } }),
        "水脉单手魔杖 + 法珠同穿合法")
    check(prepared and prepared.loadouts.A[17].weapon.templateId == "W73",
        "水脉新武器在 Lab 中正常归一化")

    prepared = expectAccept(baseConfig({ heroes = { { id = 13, level = 85 } },
        loadouts = { A = { ["13"] = {
            weapon = { templateId = "W75", level = 85 },
            offhand = { templateId = "O32", level = 85 } } }, B = {} } }),
        "硝烟单手弩 + 轻盾同穿合法")
    check(prepared and prepared.loadouts.A[13].offhand.templateId == "O32",
        "硝烟新副手在 Lab 中正常归一化")

    prepared = expectAccept(baseConfig({ heroes = { { id = 10, level = 70 } },
        loadouts = { A = { ["10"] = {
            weapon = { templateId = "W76", level = 70 },
            offhand = { templateId = "O33", level = 70 } } }, B = {} } }),
        "铁壁单手剑 + 重盾同穿合法")
    check(prepared and prepared.loadouts.A[10].weapon.templateId == "W76",
        "铁壁新武器在 Lab 中正常归一化")
end

-- ── 6) 装备等级 levelRange 边界（本轮核心：战力校准样本合法性）──
local function testLevelRange()
    local function accAt(level)
        return baseConfig({ loadouts = {
            A = { ["1"] = { accessory = { templateId = "C1", level = level } } }, B = {} } })
    end

    local prepared = expectAccept(accAt(1), "C1 Lv1（levelRange 下边界）合法")
    check(prepared and prepared.loadouts.A[1].accessory.level == 1, "C1 Lv1 保留")

    prepared = expectAccept(accAt(7), "C1 Lv7（levelRange 上边界）合法")
    check(prepared and prepared.loadouts.A[1].accessory.level == 7, "C1 Lv7 保留")

    expectReject(accAt(0), "装备等级/升阶无效", "C1 Lv0（<1）拒绝")
    expectReject(accAt(-3), "装备等级/升阶无效", "C1 Lv-3 负数拒绝")
    expectReject(accAt(8), "不在模板掉落范围", "C1 Lv8 超出 levelRange{1,7} 拒绝（跨档越界）")
    expectReject(accAt(1.5), "装备等级/升阶无效", "C1 Lv1.5 非整数拒绝")
    expectReject(accAt(10000), "装备等级/升阶无效", "C1 Lv10000 超全局上限拒绝")
    expectReject(accAt("abc"), "装备等级/升阶无效", "C1 level 非数字拒绝")

    -- C2 = 金光之戒 levelRange{8,9999}：跨档下边界
    local function acc2At(level)
        return baseConfig({ loadouts = {
            A = { ["1"] = { accessory = { templateId = "C2", level = level } } }, B = {} } })
    end
    expectReject(acc2At(7), "不在模板掉落范围", "C2 Lv7 低于 levelRange{8,9999} 拒绝")
    prepared = expectAccept(acc2At(8), "C2 Lv8（跨档下边界）合法")
    check(prepared and prepared.loadouts.A[1].accessory.level == 8, "C2 Lv8 保留")
    prepared = expectAccept(acc2At(9999), "C2 Lv9999（全局上边界）合法")
    check(prepared and prepared.loadouts.A[1].accessory.level == 9999, "C2 Lv9999 保留")

    -- 历史不合规样本必须被拒绝（antibodies 记录：C10/C4 最早 Lv28）
    expectReject(baseConfig({ loadouts = {
        A = { ["1"] = { accessory = { templateId = "C10", level = 1 } } }, B = {} } }),
        "不在模板掉落范围", "历史反例 C10 Lv1 现在被拒绝")
    expectReject(baseConfig({ loadouts = {
        A = { ["1"] = { accessory = { templateId = "C4", level = 1 } } }, B = {} } }),
        "不在模板掉落范围", "历史反例 C4 Lv1 现在被拒绝")
end

-- ── 7) ascendLevel / quality / affixes 边界 ──
local function testAscendAndDeterminism()
    local function accWith(extra)
        local spec = { templateId = "C1", level = 1 }
        for k, v in pairs(extra) do spec[k] = v end
        return baseConfig({ loadouts = { A = { ["1"] = { accessory = spec } }, B = {} } })
    end

    local prepared = expectAccept(accWith({}), "ascendLevel 缺省为 0")
    check(prepared and prepared.loadouts.A[1].accessory.ascendLevel == 0, "缺省 ascendLevel → 0")

    prepared = expectAccept(accWith({ ascendLevel = 0 }), "ascendLevel 0 下边界合法")
    check(prepared and prepared.loadouts.A[1].accessory.ascendLevel == 0, "ascendLevel 0 保留")

    prepared = expectAccept(accWith({ ascendLevel = 100 }), "ascendLevel 100 上边界合法")
    check(prepared and prepared.loadouts.A[1].accessory.ascendLevel == 100, "ascendLevel 100 保留")

    expectReject(accWith({ ascendLevel = 101 }), "装备等级/升阶无效", "ascendLevel 101 超上界拒绝")
    expectReject(accWith({ ascendLevel = -1 }), "装备等级/升阶无效", "ascendLevel -1 负数拒绝")
    expectReject(accWith({ ascendLevel = 1.5 }), "装备等级/升阶无效", "ascendLevel 非整数拒绝")
    expectReject(accWith({ ascendLevel = "abc" }), "装备等级/升阶无效", "ascendLevel 非数字拒绝")

    expectReject(accWith({ quality = 2 }), "仅支持普通品质", "显式 quality 拒绝（校准需确定性）")
    expectReject(accWith({ affixes = {} }), "仅支持普通品质", "显式 affixes（空表也算）拒绝")
end

-- ── 8) mode 归一化 ──
local function testMode()
    local prepared = expectAccept(baseConfig({ mode = "idle" }), "普通关 idle 合法")
    check(prepared and prepared.mode == "idle", "mode=idle 保留")

    prepared = expectAccept(baseConfig({ mode = "weird" }), "未知 mode 回落 firstClear")
    check(prepared and prepared.mode == "firstClear", "未知 mode → firstClear")
end

-- ── 9) 套装六槽：同级可得、同英雄可穿，五槽特例需真双手 ──
local function testSetCoverage()
    local EC = require("config.EquipmentConfig")
    local SC = require("config.EquipmentSetConfig")
    local ES = require("systems.EquipmentSystem")
    local Sets = require("systems.EquipmentSetSystem")
    local cases = {
        { "tidepress", 17, 70, { weapon="W73", offhand="O23", armor="A53", helmet="H53", shoes="S53", accessory="C10" } },
        { "tidepress", 17, 85, { weapon="W74", offhand="O24", armor="A54", helmet="H54", shoes="S54", accessory="C10" } },
        { "nitros", 13, 70, { weapon="W47", offhand="O31", armor="A17", helmet="H17", shoes="S17", accessory="C21" } },
        { "nitros", 13, 85, { weapon="W75", offhand="O32", armor="A18", helmet="H18", shoes="S18", accessory="C22" } },
        { "ironwall", 10, 70, { weapon="W76", offhand="O33", armor="A41", helmet="H41", shoes="S41", accessory="C30" } },
        { "ironwall", 10, 85, { weapon="W77", offhand="O12", armor="A48", helmet="H48", shoes="S48", accessory="C30" } },
        { "emberscout", 13, 85, { weapon="W78", offhand="O34", armor="A61", helmet="H61", shoes="S61", accessory="C37" } },
        { "swordgate", 16, 85, { weapon="W12", armor="A62", helmet="H62", shoes="S62", accessory="C23" } },
        { "bonehunger", 1, 85, { weapon="W79", offhand="O35", armor="A63", helmet="H63", shoes="S63", accessory="C14" } },
        { "riftcrystal", 20, 85, { weapon="W36", offhand="O36", armor="A64", helmet="H64", shoes="S64", accessory="C12" } },
        { "starless", 20, 85, { weapon="W80", offhand="O18", armor="A65", helmet="H65", shoes="S65", accessory="C32" } },
        { "gambler", 14, 85, { weapon="W81", offhand="O37", armor="A66", helmet="H66", shoes="S66", accessory="C33" } },
    }
    check(EC.TOTAL_COUNT == 353 and EC.SLOT_COUNT.weapon == 81
        and EC.SLOT_COUNT.offhand == 37 and EC.SLOT_COUNT.armor == 66
        and EC.SLOT_COUNT.helmet == 66 and EC.SLOT_COUNT.shoes == 66
        and EC.SLOT_COUNT.accessory == 37,
        "原模板 ID 不变，当前共 353 个模板")
    check(SC.getSetIdForTemplate(EC.ITEMS.W36) == "riftcrystal"
        and SC.getSetIdForTemplate(EC.ITEMS.W48) == "riftcrystal"
        and SC.getSetIdForTemplate(EC.ITEMS.W5) == "carapace"
        and SC.getSetIdForTemplate(EC.ITEMS.O11) == "bonehunger"
        and SC.getSetIdForTemplate(EC.ITEMS.O5) == "faceless",
        "原装备套装归属保持不变")

    for _, case in ipairs(cases) do
        local setId, heroId, level, loadout = case[1], case[2], case[3], case[4]
        local prepared = expectAccept(baseConfig({ heroes = { { id = heroId, level = level } },
            loadouts = { A = { [tostring(heroId)] = (function()
                local spec = {}
                for slot, tid in pairs(loadout) do spec[slot] = { templateId = tid, level = level } end
                return spec
            end)() }, B = {} } }),
            setId .. " Lv" .. level .. " 同职业同等级六槽配装")
        local label = setId .. " Lv" .. level
        if prepared then
            local data = { inventory = {}, equipped = { [heroId] = {} } }
            local equippedCount = 0
            for index, slot in ipairs(EC.SLOTS) do
                local tid = loadout[slot]
                if tid then
                    local tpl = EC.ITEMS[tid]
                    check(tpl ~= nil and level >= tpl.levelRange[1] and level <= tpl.levelRange[2],
                        label .. " " .. slot .. " 等级范围匹配")
                    data.inventory[tostring(index)] = ES.generate(tid, level, 1)
                    data.equipped[heroId][slot] = index
                    equippedCount = equippedCount + 1
                    check(SC.getSetIdForTemplate(tpl) == setId,
                        label .. " " .. slot .. " 模板确实归属本套")
                    local iconId = tpl.iconTemplateId or tid
                    check(EC.getIconPath(tid) == EC.getIconPath(iconId),
                        label .. " " .. slot .. " 图标映射到 " .. iconId)
                end
            end
            local counts, twoHand = Sets.countSets(data, heroId, ES.getFromInventory, ES.getHeroSlots)
            local rows = Sets.summarize(counts)
            local isTwoHand = loadout.offhand == nil
            check(equippedCount == (isTwoHand and 5 or 6)
                and counts[setId] == 6 and twoHand == isTwoHand and #rows == 1
                and rows[1].fourActive and rows[1].sixActive,
                label .. " 满套实际激活（" .. equippedCount .. " 件装备）")
            if isTwoHand then
                data.equipped[heroId].accessory = nil
            else
                data.equipped[heroId].offhand = nil
            end
            local fiveCounts = Sets.countSets(data, heroId, ES.getFromInventory, ES.getHeroSlots)
            check(fiveCounts[setId] < 6, label .. " 卸一件后六件效果失效")
        end
    end
end

-- ── 10) CombatPowerEstimate 分项计价原型：同官方战力下按职业区分适配 ──
local function testEstimate()
    local HC = require("config.HeroConfig")
    local EC = require("config.EquipmentConfig")
    local ES = require("systems.EquipmentSystem")
    local Sets = require("systems.EquipmentSetSystem")
    local CPE = require("systems.CombatPowerEstimate")
    local AD = require("systems.AttributeDef")

    -- 与 BattleLab.powerOf 相同的官方权重（跳过六围）
    local SKIP = {
        [AD.STR] = true, [AD.AGI] = true, [AD.INT] = true,
        [AD.VIT] = true, [AD.LUK] = true, [AD.SPI] = true,
        [AD.HP] = true, [AD.ATK_INTERVAL] = true,
        [AD.PHYS_RES] = true, [AD.MAG_RES] = true,
    }
    local function officialPower(attrs)
        local total = 0
        for key, meta in pairs(AD.META) do
            if not SKIP[key] and meta.valueModel and meta.valueModel > 0 then
                total = total + attrs:get(key)
                    * (meta.dataType == AD.TYPE_PCT and meta.valueModel / 100 or meta.valueModel)
            end
        end
        return math.floor(total + 0.5)
    end

    --- 造一个 Lv8 模板英雄并穿指定饰品（复刻 BattleLab.makeUnit 的最小路径）
    local function unitWith(heroId, level, templateId)
        local unit = assert(HC.createHero(heroId, level, nil, nil, false))
        local equip = ES.hydrate({ templateId = templateId, level = level,
            quality = 1, ascendLevel = 0, affixes = {} })
        local eqData = { inventory = { ["1"] = equip }, equipped = { [heroId] = { accessory = 1 } } }
        ES.applyToUnit(unit.attrs, equip, 1, ES.getAscendBoost(equip))
        Sets.applyToUnit(unit.attrs, eqData, heroId, ES.getFromInventory, ES.getHeroSlots)
        unit.attrs:fillHp()
        return unit
    end

    check(EC.ITEMS["C2"] ~= nil and EC.ITEMS["C8"] ~= nil, "C2/C8 模板存在（tier2 下边界组）")

    -- 战士（大狗嚼 id=1，physical）：力量戒 vs 智力戒
    local wStr = unitWith(1, 8, "C2")
    local wInt = unitWith(1, 8, "C8")
    local wPowA, wPowB = officialPower(wStr.attrs), officialPower(wInt.attrs)
    local wEstA, wCatA = CPE.estimate(wStr.attrs, wStr.attrs.atkType)
    local wEstB = CPE.estimate(wInt.attrs, wInt.attrs.atkType)
    check(wCatA == "physical", "战士伤害大类 = physical")
    check(wPowA == wPowB, "官方战力不区分力量/智力戒（同 " .. wPowA .. "）")
    check(wEstA > wEstB, "预估区分适配：战士力量戒 " .. wEstA .. " > 智力戒 " .. wEstB)

    -- 法师（黄桃龙 id=2，magical）：方向必须反转
    local mStr = unitWith(2, 8, "C2")
    local mInt = unitWith(2, 8, "C8")
    local mPowA, mPowB = officialPower(mStr.attrs), officialPower(mInt.attrs)
    local mEstA, mCatA = CPE.estimate(mStr.attrs, mStr.attrs.atkType)
    local mEstB = CPE.estimate(mInt.attrs, mInt.attrs.atkType)
    check(mCatA == "magical", "法师伤害大类 = magical")
    check(mPowA == mPowB, "法师官方战力同样不区分（同 " .. mPowA .. "）")
    check(mEstB > mEstA, "法师方向反转：智力戒 " .. mEstB .. " > 力量戒 " .. mEstA)

    -- 牧师（卡皮巴拉 id=9，healing）：治疗系不崩、类别正确
    local hUnit = unitWith(9, 8, "C2")
    local _, hCat = CPE.estimate(hUnit.attrs, hUnit.attrs.atkType)
    check(hCat == "healing", "牧师伤害大类 = healing")

    -- 边界：atkType 为 nil 时回落 physical，不抛错
    local estNil = CPE.estimate(wStr.attrs, nil)
    check(type(estNil) == "number" and estNil > 0, "atkType=nil 回落 physical 不抛错")

    -- estimateUnit 便捷入口与 estimate 一致
    local estDirect = CPE.estimateUnit(wStr)
    check(estDirect == wEstA, "estimateUnit 与 estimate 结果一致（" .. estDirect .. "）")
end

function Start()
    print("[battle_lab_boundary_test] start")
    local ok, err = pcall(function()
        testStage()
        testHeroes()
        testScalarClamp()
        testLoadoutStructure()
        testTemplateWearable()
        testLevelRange()
        testAscendAndDeterminism()
        testMode()
        testSetCoverage()
        testEstimate()
    end)
    if not ok then
        print("[FAIL] 测试抛异常: " .. tostring(err))
        failures[#failures + 1] = "exception"
    end
    if #failures == 0 then
        print("[battle_lab_boundary_test] ALL PASS")
    else
        print("[battle_lab_boundary_test] FAILURES=" .. #failures)
        for _, m in ipairs(failures) do print("  - " .. m) end
    end
    engine:Exit()
end
