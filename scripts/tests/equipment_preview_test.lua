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
        check(pen and close(pen.currentValue, 0) and close(pen.previewValue, 14.5), "新出现非零行包含当前0与精确预览数值")
        check(pen.value == AD.formatAttrDisplayValue(AD.PHYS_PEN, 0), "新出现行 value 显示当前0，不冒充已穿戴数值")
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
            "消失非零行保留负差值，不被过滤")

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
    end)
    Dispatcher.get, Store.Get = oldGet, oldStoreGet
    package.loaded["ui.character.panel.CharacterPanel"] = oldPanel
    if not ok then check(false, "测试异常: " .. tostring(err)) end
    if #failures == 0 then print("[equipment_preview_test] ALL PASS assertions=" .. assertions)
    else print("[equipment_preview_test] FAILURES=" .. #failures .. " assertions=" .. assertions) end
    engine:Exit()
end
