------------------------------------------------------------------------
-- equipment_preview_test.lua —— 只读配装预览回归
-- Runtime: tests/equipment_preview_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- 不写真实存档；覆盖完整重建、互斥/拒绝、六围派生、倍率、套装得失和跨队神器。
------------------------------------------------------------------------
local Preview = require("ui.character.detail.EquipmentPreview")
local Attrs = require("ui.character.detail.CharacterDetailAttrs")
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")
local Eq = require("systems.EquipmentSystem")
local EC = require("config.EquipmentConfig")
local ESC = require("config.EquipmentSetConfig")
local Dispatcher = require("runtime.ClientDispatcher")
local Store = require("core.PlayerStore")

local failures, assertions = {}, 0
local function check(ok, message)
    assertions = assertions + 1
    if ok then print("[PASS] " .. message)
    else failures[#failures + 1] = message; print("[FAIL] " .. message) end
end
local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.000001 end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function row(data, key)
    for _, r in ipairs(data.rows) do if r.key == key then return r end end
    return nil
end
local function hasModifier(attrs, prefix)
    for k in pairs(attrs.modifiers) do if k:sub(1, #prefix) == prefix then return true end end
    return false
end
local function fixture(heroId, level)
    return {
        heroes = { roster = { [tostring(heroId)] = { level = level } }, deployed = { heroId } },
        equipment = { inventory = {}, equipped = { [tostring(heroId)] = {} }, nextSeq = 100 },
        artifacts = { bag = {} },
    }
end
local function put(options, seq, templateId, affixes, stats)
    options.equipment.inventory[tostring(seq)] = {
        templateId = templateId, level = 1, quality = 1, affixes = affixes, baseStats = stats,
    }
end
local function findTemplate(setId, slot, heroId)
    local wearable = Eq.getWearableTypeSet(heroId, slot)
    local found = {}
    for id, tpl in pairs(EC.ITEMS) do
        if tpl.slot == slot and (slot ~= "weapon" or tpl.grip == "onehand")
            and ESC.getSetIdForTemplate(tpl) == setId and
            (not wearable or wearable[tpl.type]) then found[#found + 1] = id end
    end
    table.sort(found)
    return found[1]
end

function Start()
    print("[equipment_preview_test] start")
    local oldGet, oldStoreGet = Dispatcher.get, Store.Get
    local oldPanel = package.loaded["ui.character.panel.CharacterPanel"]
    local owned = { level = 70, awakening = { [1] = true }, extraTalent = { stacks = "123" } }
    local ownedBefore, configBefore = copy(owned), copy(HC.HEROES)
    local ownedReads, globalReads = 0, 0
    package.loaded["ui.character.panel.CharacterPanel"] = {
        getOwnedHero = function() ownedReads = ownedReads + 1; return owned end,
    }
    local active = fixture(1, 70)
    Dispatcher.get = function(key) globalReads = globalReads + 1; return active[key] end
    Store.Get = function(key) globalReads = globalReads + 1; return active[key] end
    local ok, err = pcall(function()
        -- 1) 默认来源和显式来源均深拷贝，hydrate 不回写真档。
        put(active, 1, "W1")
        active.equipment.equipped["1"].weapon = 1
        put(active, 2, "W1", { { affixId = 18, value = 12.5 }, { affixId = 25, value = 7.25 } })
        active.equipment.inventory["2"].affixMult = "2"
        local before = copy(active)
        local current = Preview.build("1", 70)
        check(current.error == nil and current.preview == nil and current.candidate == nil, "无候选只返回当前属性")
        check(current.current.attrs ~= nil and #current.rows > 0 and #current.previewSets == 0, "当前完整属性与行列表可用")
        local simulated = Preview.build(1, 70, "2")
        check(simulated.preview ~= nil and simulated.error == nil, "默认来源候选装备可预览")
        check(simulated.candidate.seq == 2 and simulated.candidate.slot == "weapon", "候选序号/默认槽位已归一化")
        check(equal(active, before), "默认来源 heroes/equipment/artifacts 不被 hydrate/穿戴改写")
        local readsBefore = globalReads
        local explicit = Preview.build(1, 70, 2, "weapon", active)
        check(globalReads == readsBefore, "完整 options 不回读 dispatcher/PlayerStore")
        check(equal(active, before), "显式 options 深拷贝，affixMult 字符串与词条仍原样")
        check(equal(explicit.current.stats, simulated.current.stats), "默认/显式来源属性一致")
        check(explicit.current.attrs ~= explicit.preview.attrs, "当前/预览使用独立 UnitAttributes")
        local speed = row(explicit, AD.ATK_SPEED)
        check(close(speed.delta, 25) and speed.deltaText == "+25.0%", "词条倍率生效，百分比差值为百分点")
        local pen = row(explicit, AD.PHYS_PEN)
        check(pen and close(pen.currentValue, 0) and close(pen.previewValue, 14.5), "常驻穿透行包含当前0与精确预览数值")
        check(pen.value == AD.formatAttrDisplayValue(AD.PHYS_PEN, 0), "常驻穿透行显示当前0，不冒充已穿戴数值")
        local interval = row(explicit, AD.ATK_INTERVAL)
        check(interval.delta < 0 and interval.beneficial == true and interval.deltaText:sub(1, 1) == "-", "实际攻击间隔下降为增益，差值带负号")
        check(close(interval.previewValue, explicit.preview.attrs:getActualInterval()), "攻击间隔数值复用真实属性公式")
        local order, last = Attrs.displayOrderIndex(), 0
        local sorted, numeric = true, true
        for _, r in ipairs(explicit.rows) do
            local index = order[r.key] or math.huge
            if index < last then sorted = false end
            last = index
            if r.delta ~= nil and (type(r.currentValue) ~= "number" or type(r.previewValue) ~= "number") then numeric = false end
        end
        check(sorted, "合并行按 displayOrderIndex 稳定排序")
        check(numeric, "所有数值对比行 currentValue/previewValue 为 number")
        active.equipment.equipped["1"].weapon = 2
        local removed = Preview.build(1, 70, 1, nil, active)
        check(row(removed, AD.PHYS_PEN).deltaText == "-14.5" and row(removed, AD.PHYS_PEN).previewValue == 0,
            "穿透回落为0仍保留行与负差值")

        -- 2) 六围保留小数，派生属性与最终倍率由同一管线重算。
        local six = fixture(1, 70)
        put(six, 1, "C1", {
            { affixId = 1, value = 0.75 }, { affixId = 4, value = 1.25 },
            { affixId = 1005, value = 10 }, { affixId = 1003, value = 8 },
        }, {})
        six.equipment.inventory["1"].affixMult = 2
        local sixResult = Preview.build(1, 70, 1, nil, six)
        check(close(sixResult.preview.stats[AD.STR], (sixResult.current.stats[AD.STR] + 1.5) * 1.017), "六围普通词条吃倍率、最终力量乘区重算且保留小数")
        check(sixResult.preview.stats[AD.VIT] > sixResult.current.stats[AD.VIT], "体质词条进入六围")
        check(sixResult.preview.attrs:get(AD.PHYS_ATK) > sixResult.current.attrs:get(AD.PHYS_ATK), "力量派生物攻重算")
        check(sixResult.preview.attrs:get(AD.MAX_HP) > sixResult.current.attrs:get(AD.MAX_HP), "体质派生生命及最终生命重算")
        check(close(row(sixResult, AD.FINAL_STR_BONUS).delta, 1.7), "魔化词条按 hydrate 回正、不吃普通词条倍率")
        local attrsOnly = Attrs.collectAttributes(1, HC.get(1), 70, six)
        check(attrsOnly.attrs ~= nil and close(attrsOnly.stats[AD.STR], attrsOnly.attrs:get(AD.STR)), "collectAttributes 显式 options 返回同源原始六围")
        -- 旧调用允许本地回退；显式补齐测试来源，避免此兼容性断言触碰 Owned 替身。
        active.heroes.roster["1"].extraTalent = {}
        active.heroes.roster["1"].awakening = {}
        local legacy = Attrs.collectAttributes(1, HC.get(1), 70)
        check(legacy.stats[AD.STR] == math.floor(legacy.stats[AD.STR]), "旧属性页六围整数行为保留")
        local oldInterval
        for _, r in ipairs(legacy.right) do if r.key == AD.ATK_INTERVAL then oldInterval = r.value end end
        check(oldInterval == string.format("%.1fs", HC.get(1).atkInterval), "旧属性页攻击间隔格式/基准显示不变")

        -- 3) 双手装入自动卸副手；副手装入自动卸双手主手。
        local twohand = fixture(1, 70)
        put(twohand, 1, "W1")
        put(twohand, 2, "O1")
        put(twohand, 3, "W7")
        twohand.equipment.equipped["1"] = { weapon = 1, offhand = 2 }
        local th = Preview.build(1, 70, 3, nil, twohand)
        check(hasModifier(th.preview.attrs, "equip_3") and not hasModifier(th.preview.attrs, "equip_2"), "双手候选自动卸副手，完整属性中不残留副手")
        check(twohand.equipment.equipped["1"].offhand == 2, "双手互斥只改副本")
        twohand.equipment.equipped["1"] = { weapon = 3 }
        local off = Preview.build(1, 70, 2, nil, twohand)
        check(hasModifier(off.preview.attrs, "equip_2") and not hasModifier(off.preview.attrs, "equip_3"), "副手候选自动卸双手主手")

        -- 4) 拒绝保留 current/error；等级用请求等级而非真实英雄等级。
        put(twohand, 4, "W1")
        twohand.equipment.inventory["4"].level = 71
        local high = Preview.build(1, 70, 4, nil, twohand)
        check(high.preview == nil and high.current.attrs ~= nil and high.error:find("等级") ~= nil, "等级门槛拒绝且保留当前属性")
        local missing = Preview.build(1, 70, 9999, nil, twohand)
        check(missing.preview == nil and missing.error == "装备不存在" and #missing.rows > 0, "非法候选保留当前行")
        local mismatch = Preview.build(1, 70, 1, "armor", twohand)
        check(mismatch.preview == nil and mismatch.error == "槽位不匹配", "槽位不匹配复用真实校验")
        local dual = Preview.build(1, 70, 1, "offhand", twohand)
        check(dual.preview == nil and dual.error ~= nil, "未解锁双持拒绝副手武器")
        put(twohand, 6, "W13")
        twohand.heroes.roster["1"].advBranch = { second = 220 }
        twohand.equipment.equipped["1"] = { weapon = 1 }
        local sameBad = Preview.build(1, 70, 6, "offhand", twohand)
        check(sameBad.preview == nil and sameBad.error:find("相同类型") ~= nil, "同类型双持拒绝异类型副手")
        twohand.heroes.roster["1"].advBranch = { second = 207 }
        local diffBad = Preview.build(1, 70, 1, "offhand", twohand)
        check(diffBad.preview == nil and diffBad.error:find("不同类型") ~= nil, "异类型双持拒绝相同类型副手")
        local diffGood = Preview.build(1, 70, 6, "offhand", twohand)
        check(diffGood.preview ~= nil and hasModifier(diffGood.preview.attrs, "equip_6"), "合法双持仍按完整管线重建")
        twohand.heroes.roster["1"].advBranch = nil
        put(twohand, 5, "W25")
        local classBad = Preview.build(1, 70, 5, nil, twohand)
        check(classBad.preview == nil and classBad.error:find("类型") ~= nil, "职业类型限制拒绝")
        check(Preview.build(9999, 70, nil, nil, twohand).error == "英雄不存在", "未知英雄安全返回错误")

        -- 5) 套装获得/失去；4/6只摘要，不执行战斗条件被动。
        local sets = fixture(1, 70)
        local setWeapon, setArmor = findTemplate("carapace", "weapon", 1), findTemplate("carapace", "armor", 1)
        check(setWeapon ~= nil and setArmor ~= nil, "真实套装模板存在且职业可穿戴")
        put(sets, 1, setWeapon)
        put(sets, 2, setArmor, nil, {})
        put(sets, 3, "W1")
        sets.equipment.equipped["1"].weapon = 1
        local gain = Preview.build(1, 70, 2, nil, sets)
        check(gain.currentSets[1].count == 1 and gain.previewSets[1].twoActive, "套装候选由1件升为2件")
        check(close(row(gain, AD.HP_BONUS).delta, 6), "2件纯属性进入完整预览")
        sets.equipment.equipped["1"].armor = 2
        local loss = Preview.build(1, 70, 3, nil, sets)
        check(loss.currentSets[1].twoActive and not loss.previewSets[1].twoActive, "换出套装丢失2件效果")
        check(close(row(loss, AD.HP_BONUS).delta, -6), "丢套装生命加成呈负差值")
        for i, slot in ipairs({ "helmet", "shoes", "accessory" }) do
            local template = findTemplate("carapace", slot, 1)
            put(sets, i + 3, template)
            sets.equipment.equipped["1"][slot] = i + 3
        end
        local highSet = Preview.build(1, 70, nil, nil, sets)
        check(highSet.currentSets[1].fourActive == true, "4件高阶激活只在套装摘要显示")
        put(sets, 7, findTemplate("carapace", "offhand", 1))
        sets.equipment.equipped["1"].offhand = 7
        local sixSet = Preview.build(1, 70, nil, nil, sets)
        check(sixSet.currentSets[1].sixActive == true, "6件高阶激活保留套装摘要")
        check(highSet.current.attrs._carapaceStacks == nil, "预览不擅自运行战斗条件效果")

        -- 6) 神器按英雄所属队伍显式读副本，不错读队1；特殊数值行也保留原始值。
        local art = fixture(1, 70)
        art.heroes.deployed = { 2 }
        art.heroes.teams = { { slots = { 2 } }, { slots = { "1" } } }
        art.artifacts = {
            bag = {
                { id = "team1", artifactId = 9, value = 300 },
                { id = "team2", artifactId = 12, value = 250 },
                { id = "slow", artifactId = 13, value = 60 },
            },
            equippedByTeam = { [1] = { [1] = { "team1" } }, [2] = { [1] = { "team2", "slow" } } },
        }
        local artBefore = copy(art)
        put(art, 1, "W1", { { affixId = 19, value = 250 }, { affixId = 21, value = 10 } }, {})
        local ar = Preview.build(1, 70, 1, nil, art)
        check(ar.current.attrs.artifactNoHeal == nil and ar.current.attrs.artifactCritDmgMult == 2.5, "队2英雄只应用队2神器，不错读队1血杯")
        check(close(row(ar, "_artifactCritDmgMult").currentValue, 2.5), "神器倍率特殊行提供 numericValue")
        check(close(row(ar, "_artifactExtraDamage").currentValue, 1.6), "神器额外伤害特殊行原始倍率正确")
        local crit = row(ar, "_effCritRate")
        check(close(crit.delta, 130), "合并通用/物理暴击后计神器半率倍率")
        check(row(ar, "_effCritDmg").previewValue > row(ar, "_effCritDmg").currentValue, "溢出暴击率转暴伤沿用当前管线")
        check(equal(art.artifacts, artBefore.artifacts), "神器 Schema 读取/规范化只触及副本")
        check(equal(owned, ownedBefore) and ownedReads == 0, "显式快照缺 extraTalent 不回退 Owned、不规范化真实数据")
        check(equal(HC.HEROES, configBefore), "预览不改 HeroConfig 全局配置")
        -- 缺 equippedByTeam 时 Schema 会补字段，仍必须隔离。
        local leanArt = fixture(1, 70)
        local leanBefore = copy(leanArt)
        Preview.build(1, 70, nil, nil, leanArt)
        check(equal(leanArt, leanBefore), "空神器存档不会被读取补 equippedByTeam")

        -- 7) 装备净增益是同人物穿戴/裸装之差，不含固有值或神器。
        do
            local naked = fixture(4, 70)
            naked.includeEquipmentBonuses = true
            local bare = Preview.build(4, 70, nil, nil, naked)
            check(bare.equipmentBonuses ~= nil and bare.equipmentBonuses.preview == nil
                and #bare.equipmentBonuses.rows == 0, "空装备净增益为空，不把人物生命/攻击/护甲当装备")
            check(bare.current.attrs:get(AD.PHYS_BLOCK_RATE) >= 8
                and row(bare.equipmentBonuses, AD.PHYS_BLOCK_RATE) == nil,
                "人物固有格挡概率不进入装备净贡献")
            check(close(bare.current.attrs:get(AD.PHYS_BLOCK_RATIO), 60)
                and close(bare.current.attrs:get(AD.MAG_BLOCK_RATIO), 60)
                and row(bare.equipmentBonuses, AD.PHYS_BLOCK_RATIO) == nil
                and row(bare.equipmentBonuses, AD.MAG_BLOCK_RATIO) == nil,
                "默认物理/魔法格挡比例60不冒充装备加成")
            for _, key in ipairs(AD.BASE_STATS) do
                check(close(bare.equipmentBonuses.current.stats[key], 0), "空装备六围净增益为0: " .. key)
            end
        end

        -- 8) 六围/派生保留小数；普通词条倍率、魔化乘区和装备升阶均计入净贡献。
        do
            local bonus = fixture(1, 70)
            put(bonus, 1, "C1", {
                { affixId = 1, value = 0.75 }, { affixId = 2, value = 1.25 },
                { affixId = 3, value = 0.625 }, { affixId = 4, value = 1.125 },
                { affixId = 5, value = 0.875 }, { affixId = 6, value = 0.375 },
                { affixId = 18, value = 12.5 }, { affixId = 25, value = 7.25 },
                { affixId = 1005, value = 10 }, { affixId = 1003, value = 8 },
            }, { { AD.STR, 2.25 }, { AD.AGI, 0.5 } })
            bonus.equipment.inventory["1"].affixMult = "2"
            bonus.equipment.inventory["1"].ascendLevel = "10"
            bonus.equipment.equipped["1"].accessory = 1
            local plain = Preview.build(1, 70, nil, nil, bonus)
            check(plain.equipmentBonuses == nil, "未启用 includeEquipmentBonuses 时旧接口不额外返回净增益")
            bonus.includeEquipmentBonuses = true
            local bonusBefore, reads = copy(bonus), globalReads
            local dressed = Preview.build(1, 70, nil, nil, bonus)
            local naked = copy(bonus)
            naked.equipment.equipped["1"] = {}
            local bare = Preview.build(1, 70, nil, nil, naked)
            local net = dressed.equipmentBonuses
            check(equal(dressed.rows, plain.rows) and equal(dressed.current.stats, plain.current.stats),
                "启用净增益不改变原总属性 rows/六围接口")
            check(globalReads == reads and equal(bonus, bonusBefore), "净增益独立重建不回读存档、不水合写真档")
            local strGain = (bare.current.stats[AD.STR] + 2.25 * 1.5 + 0.75 * 2) * 1.017
                - bare.current.stats[AD.STR]
            local expected = {
                [AD.STR] = strGain, [AD.AGI] = 0.5 + 1.25 * 2, [AD.INT] = 0.625 * 2,
                [AD.VIT] = 1.125 * 2, [AD.LUK] = 0.875 * 2, [AD.SPI] = 0.375 * 2,
            }
            for _, key in ipairs(AD.BASE_STATS) do
                check(close(net.current.stats[key], expected[key])
                    and close(net.current.stats[key], dressed.current.stats[key] - bare.current.stats[key]),
                    "装备六围净增益精确且不含底板: " .. key)
            end
            local speedBonus, penBonus = row(net, AD.ATK_SPEED), row(net, AD.PHYS_PEN)
            check(speedBonus and close(speedBonus.currentValue, 25 + expected[AD.AGI] * 0.4)
                and penBonus and close(penBonus.currentValue, 14.5) and penBonus.value == "+14.5",
                "净贡献含普通词条倍率与敏捷派生，value 带正号")
            local finalStr, finalHp = row(net, AD.FINAL_STR_BONUS), row(net, AD.FINAL_HP_BONUS)
            check(finalStr and close(finalStr.currentValue, 1.7) and finalStr.value == "+1.7%"
                and finalHp and close(finalHp.currentValue, 1.7),
                "魔化词条 hydrate 回正且不吃普通倍率，最终力量/生命乘区计入")
            local phys, hp = row(net, AD.PHYS_ATK), row(net, AD.MAX_HP)
            check(phys and close(phys.currentValue, strGain + expected[AD.AGI] * 0.5 + expected[AD.LUK] * 0.5)
                and close(phys.currentValue, dressed.current.attrs:get(AD.PHYS_ATK) - bare.current.attrs:get(AD.PHYS_ATK)),
                "力量/敏捷/命数重新派生物攻，currentValue 为装备净值不是总物攻")
            check(hp and hp.currentValue > expected[AD.VIT] * 33
                and close(hp.currentValue, dressed.current.attrs:get(AD.MAX_HP) - bare.current.attrs:get(AD.MAX_HP)),
                "六围派生生命及魔化最终生命共同进入装备净贡献")
            check(row(net, AD.PHYS_BLOCK_RATIO) == nil and row(net, AD.MAG_BLOCK_RATIO) == nil
                and row(net, "_atkType") == nil and row(net, "_atkTargets") == nil,
                "已穿装备也不显示默认格挡比例或固有攻击信息")
            local unascended = copy(bonus)
            unascended.equipment.inventory["1"].ascendLevel = 0
            local lower = Preview.build(1, 70, nil, nil, unascended).equipmentBonuses
            check(close(net.current.stats[AD.STR] - lower.current.stats[AD.STR], 2.25 * 0.5 * 1.017)
                and close(net.current.stats[AD.AGI], lower.current.stats[AD.AGI]),
                "升阶只增强第一条基础属性，额外贡献也吃最终力量乘区")
            local penalized = copy(bonus)
            put(penalized, 2, "C1", nil, { { AD.STR, -2 } })
            local penalty = Preview.build(1, 70, 2, nil, penalized).equipmentBonuses
            check(close(penalty.preview.stats[AD.STR], 0)
                and penalty.preview.stats[AD.AGI] == 0 and #penalty.rows > 0,
                "试穿负六围的雷达净增益夹到0，当前正贡献对比仍保留")
            penalized.equipment.equipped["1"] = {}
            local negativeOnly = Preview.build(1, 70, 2, nil, penalized).equipmentBonuses
            check(#negativeOnly.rows == 0 and close(negativeOnly.preview.stats[AD.STR], 0),
                "两侧均无正贡献时不展示负增益或默认值行")

            -- 同一配装/候选只改变神器，装备净贡献 current/preview/rows 均不能改变。
            local artifactOptions = copy(bonus)
            put(artifactOptions, 2, "W1", { { affixId = 19, value = 20 } }, {})
            artifactOptions.artifacts = {
                bag = { { id = "blood", artifactId = 9, value = 100 } },
                equippedByTeam = { [1] = { [1] = { "blood" } } },
            }
            local withArtifact = Preview.build(1, 70, 2, nil, artifactOptions)
            artifactOptions.artifacts.bag[1].value = 300
            local artifactBefore = copy(artifactOptions)
            local changedArtifact = Preview.build(1, 70, 2, nil, artifactOptions)
            local withoutArtifact = copy(artifactOptions)
            withoutArtifact.artifacts = {}
            local noArtifact = Preview.build(1, 70, 2, nil, withoutArtifact)
            check(equal(withArtifact.equipmentBonuses, changedArtifact.equipmentBonuses)
                and equal(changedArtifact.equipmentBonuses, noArtifact.equipmentBonuses),
                "神器装备/数值变化不改变当前和试穿装备净贡献")
            check(changedArtifact.current.attrs:get(AD.MAX_HP) > withArtifact.current.attrs:get(AD.MAX_HP)
                and changedArtifact.preview.attrs:get(AD.MAX_HP) > withArtifact.preview.attrs:get(AD.MAX_HP)
                and withArtifact.current.attrs:get(AD.MAX_HP) > noArtifact.current.attrs:get(AD.MAX_HP),
                "排除神器只作用于净贡献，总属性 current/preview 仍受神器变化影响")
            check(row(changedArtifact.equipmentBonuses, "_artifactNoHeal") == nil
                and row(changedArtifact.equipmentBonuses, AD.HP_BONUS) == nil
                and equal(artifactOptions, artifactBefore), "神器特殊行/生命加成不泄漏进净增益且来源快照不变")
        end

        -- 9) 候选新增正贡献从0比较；卸掉后为0仍保留；攻击间隔负差为增益。
        do
            local swap = fixture(1, 70)
            swap.includeEquipmentBonuses = true
            put(swap, 1, "W1", {
                { affixId = 1, value = 0.75 }, { affixId = 18, value = 12.5 },
                { affixId = 25, value = 7.25 },
            }, {})
            swap.equipment.inventory["1"].affixMult = 2
            put(swap, 2, "W1", nil, {})
            local added = Preview.build(1, 70, 1, nil, swap)
            local addedPen = row(added.equipmentBonuses, AD.PHYS_PEN)
            check(addedPen and close(addedPen.currentValue, 0) and addedPen.value == "+0.0"
                and close(addedPen.previewValue, 14.5) and close(addedPen.delta, 14.5)
                and addedPen.deltaText == "+14.5" and addedPen.beneficial == true,
                "候选新增正穿透从0贡献比较，当前value不冒充试穿贡献")
            check(close(added.equipmentBonuses.current.stats[AD.STR], 0)
                and close(added.equipmentBonuses.preview.stats[AD.STR], 1.5), "新增六围分别返回当前0与试穿正贡献")
            local faster = row(added.equipmentBonuses, AD.ATK_INTERVAL)
            check(faster and close(faster.currentValue, 0) and faster.previewValue < 0
                and close(faster.previewValue, added.preview.attrs:getActualInterval() - added.current.attrs:getActualInterval())
                and faster.delta < 0 and faster.deltaText:sub(1, 1) == "-" and faster.beneficial == true,
                "攻击间隔负数净贡献也显示，缩短间隔的试穿delta为增益")
            swap.equipment.equipped["1"].weapon = 1
            local worn = Preview.build(1, 70, nil, nil, swap)
            local wornInterval = row(worn.equipmentBonuses, AD.ATK_INTERVAL)
            check(wornInterval and wornInterval.currentValue < 0 and wornInterval.value:sub(1, 1) == "-"
                and wornInterval.previewValue == nil and wornInterval.delta == nil,
                "无候选攻击间隔value带负号，仅当前净贡献不伪造preview/delta")
            local removedBonus = Preview.build(1, 70, 2, nil, swap).equipmentBonuses
            local lostPen, slower = row(removedBonus, AD.PHYS_PEN), row(removedBonus, AD.ATK_INTERVAL)
            check(lostPen and close(lostPen.currentValue, 14.5) and lostPen.value == "+14.5"
                and close(lostPen.previewValue, 0) and close(lostPen.delta, -14.5)
                and lostPen.deltaText == "-14.5" and lostPen.beneficial == false,
                "卸掉穿透贡献变0仍保留对比，delta只表示试穿变化")
            check(slower and close(slower.previewValue, 0) and slower.delta > 0
                and slower.deltaText:sub(1, 1) == "+" and slower.beneficial == false
                and close(removedBonus.preview.stats[AD.STR], 0), "卸掉攻速后负间隔贡献回0为减益，六围贡献也归0")
            local rejected = Preview.build(1, 70, 9999, nil, swap)
            check(rejected.error == "装备不存在" and rejected.preview == nil
                and equal(rejected.equipmentBonuses, worn.equipmentBonuses), "失败候选完整保留当前bonus，不生成试穿净增益")
            swap.equipment.inventory["2"].level = 71
            local overlevel = Preview.build(1, 70, 2, nil, swap)
            check(overlevel.error:find("等级") ~= nil and equal(overlevel.equipmentBonuses, worn.equipmentBonuses),
                "真实穿戴校验失败也保留当前bonus")
        end

        -- 10) 两件套属于装备来源；套装触发/丢失及其派生属性都进入净贡献。
        do
            local setBonus = fixture(1, 70)
            setBonus.includeEquipmentBonuses = true
            put(setBonus, 1, findTemplate("carapace", "weapon", 1), nil, {})
            put(setBonus, 2, findTemplate("carapace", "armor", 1), nil, {})
            put(setBonus, 3, "W1", nil, {})
            setBonus.equipment.equipped["1"].weapon = 1
            local gained = Preview.build(1, 70, 2, nil, setBonus)
            local hp, armor = row(gained.equipmentBonuses, AD.HP_BONUS), row(gained.equipmentBonuses, AD.ARMOR_BONUS)
            check(hp and close(hp.currentValue, 0) and close(hp.previewValue, 6) and close(hp.delta, 6)
                and armor and close(armor.currentValue, 0) and close(armor.previewValue, 4),
                "空基础装备由1件到2件，仅套装生命+6/护甲+4进入净贡献")
            local hpDerived = row(gained.equipmentBonuses, AD.MAX_HP)
            check(hpDerived and close(hpDerived.currentValue, 0) and hpDerived.previewValue > 0
                and close(hpDerived.previewValue, gained.preview.attrs:get(AD.MAX_HP) - gained.current.attrs:get(AD.MAX_HP)),
                "套装两件生命乘区派生的生命净增益来自完整重建")
            setBonus.equipment.equipped["1"].armor = 2
            local lost = Preview.build(1, 70, 3, nil, setBonus).equipmentBonuses
            local lostHp, lostArmor = row(lost, AD.HP_BONUS), row(lost, AD.ARMOR_BONUS)
            check(lostHp and close(lostHp.currentValue, 6) and lostHp.value == "+6.0%"
                and close(lostHp.previewValue, 0) and close(lostHp.delta, -6)
                and lostArmor and close(lostArmor.currentValue, 4) and close(lostArmor.previewValue, 0),
                "拆掉两件套贡献归0仍保留旧正增益与负试穿差值")
        end
        -- 11) 微小贡献不格式化成0；封顶来源取 uncapped 净值，不重复套绝对值 cap 文案。
        do
            local tiny = fixture(1, 70)
            tiny.includeEquipmentBonuses = true
            put(tiny, 1, "W1", nil, {
                { AD.ATK_SPEED, 0.01 }, { AD.PHYS_PEN, 0.01 }, { AD.ES_DMG_REDUCE, 90 },
            })
            put(tiny, 2, "W1", nil, {})
            put(tiny, 3, "W1", nil, {
                { AD.ATK_SPEED, 0.02 }, { AD.PHYS_PEN, 0.02 }, { AD.ES_DMG_REDUCE, 100 },
            })
            local tinyBefore = copy(tiny)
            local added = Preview.build(1, 70, 1, nil, tiny)
            local addedInterval = row(added.equipmentBonuses, AD.ATK_INTERVAL)
            check(addedInterval and addedInterval.previewValue < 0 and math.abs(addedInterval.previewValue) < 0.005
                and addedInterval.deltaText:sub(1, 1) == "-" and addedInterval.deltaText:find("[1-9]") ~= nil
                and addedInterval.beneficial == true,
                "微小攻速试穿的负间隔deltaText保留非零数字，不显示-0.00s")
            tiny.equipment.equipped["1"].weapon = 1
            local worn = Preview.build(1, 70, nil, nil, tiny)
            local net = worn.equipmentBonuses
            local speed, pen, interval = row(net, AD.ATK_SPEED), row(net, AD.PHYS_PEN), row(net, AD.ATK_INTERVAL)
            check(speed and close(speed.currentValue, 0.01) and speed.value == "+0.01%"
                and pen and close(pen.currentValue, 0.01) and pen.value == "+0.01",
                "0.01攻速/穿透净贡献value保留非零精度，不显示+0.0")
            check(interval and interval.currentValue < 0 and math.abs(interval.currentValue) < 0.005
                and close(interval.currentValue, addedInterval.previewValue)
                and interval.value:sub(1, 1) == "-" and interval.value:find("[1-9]") ~= nil,
                "当前微小负攻击间隔value不舍入为-0.00s")
            local shield = row(net, AD.ES_DMG_REDUCE)
            check(shield and close(shield.currentValue, 90)
                and close(worn.current.attrs:get(AD.ES_DMG_REDUCE), 80)
                and close(shield.currentValue, worn.current.attrs:getUncapped(AD.ES_DMG_REDUCE)
                    - added.current.attrs:getUncapped(AD.ES_DMG_REDUCE)),
                "护盾减伤净贡献取uncapped来源90，不误取封顶有效值80")
            check(shield and shield.name == "护盾减伤" and AD.ES_DMG_REDUCE == "esDmgReduce"
                and AD.META[AD.ES_DMG_REDUCE].cap == 80 and AD.META[AD.ES_DMG_REDUCE].default == 0,
                "护盾减伤短名用于真实配装净贡献，属性key/上限/默认值不变")
            check(shield and shield.value == "+90.0%" and shield.value:find("(", 1, true) == nil,
                "封顶护盾减伤净值显示+90.0%，不附绝对值溢出(+10%)")
            local increased = Preview.build(1, 70, 3, nil, tiny).equipmentBonuses
            local moreShield, moreSpeed, morePen = row(increased, AD.ES_DMG_REDUCE),
                row(increased, AD.ATK_SPEED), row(increased, AD.PHYS_PEN)
            check(moreShield and close(moreShield.currentValue, 90) and close(moreShield.previewValue, 100)
                and close(moreShield.delta, 10) and moreShield.deltaText == "+10.0%"
                and moreShield.beneficial == true,
                "两侧护盾减伤均已封顶仍比较uncapped净值90到100，差值不重新套cap")
            check(moreSpeed and close(moreSpeed.delta, 0.01) and moreSpeed.deltaText == "+0.01%"
                and morePen and close(morePen.delta, 0.01) and morePen.deltaText == "+0.01",
                "已有贡献微增0.01时deltaText也保留精度")
            local removed = Preview.build(1, 70, 2, nil, tiny).equipmentBonuses
            local lostSpeed, lostPen, slower = row(removed, AD.ATK_SPEED), row(removed, AD.PHYS_PEN),
                row(removed, AD.ATK_INTERVAL)
            check(lostSpeed and close(lostSpeed.previewValue, 0) and lostSpeed.deltaText == "-0.01%"
                and lostPen and close(lostPen.previewValue, 0) and lostPen.deltaText == "-0.01",
                "卸除微小正贡献后负deltaText不显示-0.0")
            check(slower and close(slower.previewValue, 0) and slower.delta > 0
                and slower.deltaText:sub(1, 1) == "+" and slower.deltaText:find("[1-9]") ~= nil
                and slower.beneficial == false,
                "卸除微小攻速后的正间隔delta仍非零且判定减益")
            local lostShield = row(removed, AD.ES_DMG_REDUCE)
            check(lostShield and close(lostShield.previewValue, 0) and close(lostShield.delta, -90)
                and lostShield.deltaText == "-90.0%", "卸除护盾减伤的差值按uncapped贡献-90，不附cap溢出提示")
            tinyBefore.equipment.equipped["1"].weapon = 1
            check(equal(tiny, tinyBefore), "微小贡献/护盾减伤重建均不水合改写测试来源")
        end
        -- 12) 同队装备转移：试穿裸装底板必须来自转移后的世界，不能残留原持有者贡献。
        do
            local transfer = fixture(20, 70)
            transfer.includeEquipmentBonuses = true
            transfer.heroes.deployed = { 20, 2 }
            transfer.heroes.roster["2"] = { level = 70 }
            transfer.equipment.equipped["2"] = { weapon = 1 }
            put(transfer, 1, "W25")
            local transferBefore = copy(transfer)
            local bare = Preview.build(20, 70, nil, nil, transfer)
            check(row(bare, "_melissaStarGateResonance").currentValue > 1
                and row(bare, "_melissaStarGatePen").currentValue > 0
                and #bare.equipmentBonuses.rows == 0,
                "hero20空装时可继承同队法师W25共鸣，但队友装备不冒充自身净贡献")
            local simulated = Preview.build(20, 70, 1, "weapon", transfer)
            check(simulated.error == nil and simulated.preview ~= nil
                and simulated.equipmentBonuses.preview ~= nil,
                "hero20预览同队hero2持有的W25成功")
            local wornOptions = copy(transfer)
            local equipped, equipErr = Eq.applyEquip(wornOptions.equipment, 1, 20, "weapon", wornOptions.heroes)
            check(equipped == true and equipErr == nil, "副本真实applyEquip可将同队法杖转给hero20")
            check(Eq.getHeroSlots(wornOptions.equipment, 20).weapon == 1
                and Eq.getHeroSlots(wornOptions.equipment, 2).weapon == nil,
                "实际转移副本卸掉hero2武器，仅hero20持有W25")
            local wornBefore = copy(wornOptions)
            local actual = Preview.build(20, 70, nil, nil, wornOptions)
            for _, key in ipairs({ "_melissaStarGateResonance", "_melissaStarGatePen", AD.MAG_PEN }) do
                local predicted, actualBonus = row(simulated.equipmentBonuses, key), row(actual.equipmentBonuses, key)
                check(predicted and actualBonus and close(predicted.currentValue, 0)
                    and predicted.previewValue > 0 and close(predicted.previewValue, actualBonus.currentValue)
                    and close(predicted.delta, actualBonus.currentValue) and predicted.beneficial == true,
                    "转移试穿净贡献previewValue等于实际穿后currentValue: " .. key)
            end
            check(close(row(actual.equipmentBonuses, "_melissaStarGateResonance").currentValue, 4.3 * 1.5 / 100)
                and close(row(actual.equipmentBonuses, "_melissaStarGatePen").currentValue, 2.57 * 1.5),
                "转移后的星门净贡献包含W25魔伤/魔穿，不因旧队友底板抵消为0")
            check(equal(simulated.equipmentBonuses.preview.stats, actual.equipmentBonuses.current.stats),
                "同队转移试穿六围净增益与实际穿后一致")
            check(equal(simulated.preview.stats, actual.current.stats)
                and close(row(simulated, "_melissaStarGateResonance").previewValue,
                    row(actual, "_melissaStarGateResonance").currentValue)
                and close(row(simulated, "_melissaStarGatePen").previewValue,
                    row(actual, "_melissaStarGatePen").currentValue),
                "同队转移预览总属性/星门机制仍与真实穿戴一致")
            check(equal(transfer, transferBefore) and equal(wornOptions, wornBefore),
                "同队装备转移预览和实际当前重建均不水合改写输入来源")
        end
        check(equal(owned, ownedBefore) and ownedReads == 0 and equal(HC.HEROES, configBefore),
            "净增益全部重建完成后原Owned mock与HeroConfig仍未被修改")
    end)
    Dispatcher.get, Store.Get = oldGet, oldStoreGet
    package.loaded["ui.character.panel.CharacterPanel"] = oldPanel
    if not ok then check(false, "测试异常: " .. tostring(err)) end
    if #failures == 0 then print("[equipment_preview_test] ALL PASS assertions=" .. assertions)
    else print("[equipment_preview_test] FAILURES=" .. #failures .. " assertions=" .. assertions) end
    engine:Exit()
end
