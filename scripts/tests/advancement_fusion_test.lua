-- 六契共享二转专项；基于 equipment_power_perf_test 的隔离源码夹具和 Start/pcall/Exit。
-- 真实 AVC/HC/UnitAttributes/EquipmentPower/Service/PDM/Schema/StandaloneSave；
-- 源码只经 cache:GetFile 读取，玩家模块/文件/通知全部独立内存，不加载 main。
local TAG = "[advancement_fusion_test]"
local assertions, failures = 0, 0
local function check(ok, label)
    assertions = assertions + 1
    if not ok then failures = failures + 1; print(TAG .. " FAIL " .. label) end
end
local function close(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, item in pairs(v) do out[k] = copy(item) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function source(path)
    local file = assert(cache:GetFile(path), "missing source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function fixture()
    local loaded, modules, pushes = {}, {}, {}
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.File = function() error("fusion test forbids real player file access") end
    env.fileSystem = setmetatable({}, { __index = function() error("fusion test forbids real filesystem") end })
    env.require = function(name)
        if name == "core.PlayerStore" then return { Get = function(key) return modules[key] end } end
        if name == "rules.task.TaskService" then return { RefreshAchievements = function() end } end
        if loaded[name] then return loaded[name] end
        local path = name:gsub("%.", "/") .. ".lua"
        local value = assert(load(source(path), "@fusion-isolated/" .. path, "t", env))()
        loaded[name] = value
        return value
    end
    local AVC = env.require("config.AdvancementConfig")
    local HC = env.require("config.HeroConfig")
    local EP = env.require("systems.EquipmentPower")
    local PDM = env.require("rules.character.PlayerDataManager")
    local Service = env.require("rules.advancement.AdvancementService")
    local Schema = env.require("shared.schemas.CharacterSchema")
    PDM.Setup({ serverDispatcher = { pushModule = function(uid, key, value)
        pushes[#pushes + 1] = { uid = uid, key = key, value = copy(value) }
    end } })
    return { AVC = AVC, HC = HC, EP = EP, PDM = PDM, Service = Service, Schema = Schema,
        AD = env.require("systems.AttributeDef"), CombatPower = env.require("systems.CombatPower"),
        Eq = env.require("systems.EquipmentSystem"), modules = modules, pushes = pushes, env = env }
end

local pairsConfig = {
    { "seal", 101, 102, 225, "合闸", 4, "vit", "spi", "maxHp", 8, "pct" },
    { "spoil", 103, 104, 226, "骸王", 1, "str", "vit", "physAtk", 8, "pct" },
    { "rift", 105, 106, 227, "叠隙", 2, "int", "spi", "magAtk", 8, "pct" },
    { "echo", 107, 108, 228, "复调", 3, "agi", "luk", "physDmgBonus", 8, "flat" },
    { "mask", 109, 110, 229, "无相", 8, "luk", "agi", "atkSpeed", 8, "flat" },
    { "debt", 111, 112, 230, "赦祷", 9, "spi", "vit", "healBonus", 10, "flat" },
}
-- 旧36个分支的名字/天赋/父/全部属性/天赋战力固定参照，不从新增实现反向生成。
local oldFirst = {
    { "门闩", "gate_101_latch", "vit", "spi" }, { "闸门", "gate_102_sluice", "vit", "str" },
    { "骨市", "gate_103_bone_market", "str", "vit" }, { "剥壳", "gate_104_peel", "str", "agi" },
    { "错位", "gate_105_offset", "int", "spi" }, { "深缝", "gate_106_deep", "int", "luk" },
    { "残响", "gate_107_aftertone", "agi", "str" }, { "叠声", "gate_108_stacktone", "agi", "luk" },
    { "借面", "gate_109_borrow", "luk", "agi" }, { "剥面", "gate_110_stripface", "luk", "str" },
    { "延祷", "gate_111_defer2", "spi", "luk" }, { "领忏", "gate_112_confess", "spi", "vit" },
}
local oldSecond = {
    { "封条", "gate_201_seal_strip", "spi", "vit", "healBonus", 20 },
    { "殉门", "gate_202_martyr", "vit", "str", "energyShield", 7 },
    { "死闸", "gate_203_deadgate", "vit", "str", "armor", 7 },
    { "反冲闸", "gate_204_recoil", "vit", "agi", "physCritRate", 6.25 },
    { "骨潮", "gate_205_tide", "str", "agi", "physCritRate", 6.25 },
    { "骨债", "gate_206_bone_debt", "str", "vit", "critDmg", 25 },
    { "双械", "adv_207_weapon_master", "str", "agi", "physPen", 10 },
    { "连剥", "gate_208_peelchain", "str", "luk", "physCritDmg", 33 },
    { "群缝", "gate_209_mass", "int", "vit", "magPen", 10 },
    { "蚀缝", "gate_210_corrode", "int", "spi", "magCritRate", 6.25 },
    { "择缝", "gate_211_choose", "int", "spi", "magCritRate", 6.25 },
    { "爆缝", "gate_212_burst", "int", "luk", "magPen", 10 },
    { "风回", "gate_213_wind", "agi", "str", "atkSpeed", 15 },
    { "瞳回", "gate_214_eye", "agi", "luk", "critDmg", 33 },
    { "瞄回", "gate_215_aim", "agi", "luk", "physPen", 10 },
    { "重回", "gate_216_heavy", "str", "agi", "critDmg", 25 },
    { "静面", "gate_217_still", "luk", "str", "critDmg", 33 },
    { "千面", "gate_218_thousand", "agi", "luk", "physPen", 10 },
    { "致命面", "gate_219_lethal", "luk", "agi", "critRate", 6.25 },
    { "双面", "adv_220_dual_blade", "luk", "str", "physPen", 10 },
    { "战祷", "gate_221_war", "spi", "int", "healBonus", 20 },
    { "血祷", "gate_222_blood", "spi", "luk", "healCritRate", 6.25 },
    { "大赦", "gate_223_pardon", "spi", "vit", "healBonus", 20 },
    { "罚忏", "gate_224_punish", "spi", "int", "magPen", 10 },
}

local function treeTests(f)
    local AVC = f.AVC
    check(same(AVC.COST, { [1] = { level = 10, gold = 10000 },
        [2] = { level = 30, gold = 100000 } }), "旧10/30级与10000/100000金币完全保持")
    local count = 0
    for id in pairs(AVC.BRANCHES) do
        count = count + 1
        check((id >= 101 and id <= 112) or (id >= 201 and id <= 230), "不新增其他ID " .. id)
    end
    check(count == 42, "12一转+24旧二转+6融合")
    for index, row in ipairs(oldFirst) do
        local id, cfg = 100 + index, AVC.get(100 + index)
        local group = assert(pairsConfig[math.floor((index - 1) / 2) + 1])
        check(cfg.name == row[1] and cfg.talentName == row[1] and cfg.talentId == row[2]
            and cfg.baseClass == group[1] and cfg.advLevel == 1 and cfg.combatPower == 15
            and cfg.parentBranch == nil and cfg.parentBranches == nil and cfg.talentIds == nil,
            "旧一转元数据 " .. id)
        check(same(cfg.statBonus, { { key = row[3], flat = 5 }, { key = row[4], flat = 5 } }),
            "旧一转全部属性 " .. id)
        check(AVC.canAdvance(10, 10000, 1, group[1], id, nil), "旧一转入口 " .. id)
    end
    for index, row in ipairs(oldSecond) do
        local id, parent = 200 + index, 101 + math.floor((index - 1) / 2)
        local cfg = AVC.get(id)
        local class = assert(pairsConfig[math.floor((index - 1) / 4) + 1])[1]
        check(cfg.name == row[1] and cfg.talentName == row[1] and cfg.talentId == row[2]
            and cfg.parentBranch == parent and cfg.parentBranches == nil and cfg.talentIds == nil
            and cfg.baseClass == class and cfg.advLevel == 2 and cfg.combatPower == 20,
            "旧二转元数据 " .. id)
        check(same(cfg.statBonus, { { key = row[3], flat = 5 }, { key = row[4], flat = 5 },
            { key = row[5], flat = row[6] } }), "旧二转全部属性 " .. id)
        check(AVC.isParentBranch(id, parent) and AVC.canAdvance(30, 100000, 2, class, id, { first = parent }),
            "旧二转合法入口 " .. id)
        check(AVC.canAdvance(30, 100000, 2, "intentional_wrong_class", id, { first = parent }),
            "旧二转不重验classId契约 " .. id)
        local other = parent % 2 == 1 and parent + 1 or parent - 1
        check(not AVC.canAdvance(30, 100000, 2, class, id, { first = other }), "旧二转不串同职业父 " .. id)
        check(same(AVC.getTalentIds({ first = parent, second = id }),
            { AVC.get(parent).talentId, row[2] }), "旧二转天赋列表不变 " .. id)
    end
    for _, row in ipairs(pairsConfig) do
        local class, a, b, id = row[1], row[2], row[3], row[4]
        local cfg = AVC.get(id)
        check(same(AVC.FIRST_BRANCHES[class], { a, b }), "基础树原两一转 " .. class)
        check(cfg.name == row[5] and cfg.talentName == row[5] and cfg.baseClass == class
            and cfg.advLevel == 2 and cfg.combatPower == 20 and cfg.parentBranch == nil
            and same(cfg.parentBranches, { a, b }) and cfg.talentId == "gate_" .. id .. "_fusion",
            "融合元数据 " .. id)
        check(same(cfg.statBonus, { { key = row[7], flat = 5 }, { key = row[8], flat = 5 },
            { key = row[9], [row[11]] = row[10] } }), "融合严格三属性不叠两父属性 " .. id)
        check(same(cfg.talentIds, { AVC.get(a).talentId, AVC.get(b).talentId }), "融合仅两父天赋 " .. id)
        local unique = {}
        for _, parent in ipairs({ a, b }) do
            local list = AVC.SECOND_BRANCHES[parent]
            check(same(list, { 201 + (parent - 101) * 2, 202 + (parent - 101) * 2, id }),
                "每父原两项+共享第三项 " .. parent)
            for _, child in ipairs(list) do unique[child] = true end
        end
        local n = 0
        for _ in pairs(unique) do n = n + 1 end
        check(n == 5, "每对五唯一二转 " .. class)
        for _, parent in ipairs({ a, b }) do
            local path = { first = parent }
            check(AVC.isParentBranch(id, parent) and AVC.canAdvance(30, 100000, 2, class, id, path),
                "双父精确门槛入口 " .. parent)
            check(not AVC.canAdvance(29, 100000, 2, class, id, path), "等级不足 " .. parent)
            check(not AVC.canAdvance(30, 99999, 2, class, id, path), "金币不足 " .. parent)
            check(not AVC.canAdvance(30, 100000, 2, "wrong", id, path), "融合重验职业 " .. parent)
            check(not AVC.canAdvance(30, 100000, 2, class, id, { first = parent, second = id }),
                "重复融合拒绝 " .. parent)
        end
        check(not AVC.canAdvance(30, 100000, 2, class, id, nil), "无一转拒绝 " .. id)
        check(not AVC.canAdvance(30, 100000, 1, class, id, nil), "错误阶段拒绝 " .. id)
        local foreign = a == 101 and 103 or 101
        check(not AVC.isParentBranch(id, foreign)
            and not AVC.canAdvance(30, 100000, 2, class, id, { first = foreign }), "跨职业父拒绝 " .. id)
    end
end

local function attributeTests(f)
    local AVC, HC, AD = f.AVC, f.HC, f.AD
    for _, row in ipairs(pairsConfig) do
        local a, b, id, heroId = row[2], row[3], row[4], row[6]
        for _, first in ipairs({ a, b }) do
            local other = first == a and b or a
            local path = { first = first, second = id }
            local snapshot = copy(path)
            local ids = AVC.getTalentIds(path)
            check(same(ids, { AVC.get(first).talentId, AVC.get(id).talentId, AVC.get(other).talentId }),
                "真实路线先于融合两父且去重 " .. first)
            check(same(AVC.getAllBranches(path), { first, id }), "属性仅真实两分支 " .. first)
            check(AVC.hasTalent(path, AVC.get(a).talentId) and AVC.hasTalent(path, AVC.get(b).talentId)
                and AVC.hasTalent(path, AVC.get(id).talentId), "hasTalent统一双天赋 " .. first)
            check(AVC.getDualWieldMode(path) == nil, "融合不新开双持 " .. first)
            local unit = HC.createHero(heroId, 70, path, {}, {}, { litNodes = false, silent = true })
            local base = HC.createHero(heroId, 70, nil, {}, {}, { litNodes = false, silent = true })
            local expected = base.attrs:clone()
            expected:addModifier("oracle_first", AVC.get(first).statBonus)
            expected:addModifier("oracle_second", AVC.get(id).statBonus)
            expected:fillHp() -- HC 在全部属性构建后满血；oracle也必须走同一时序。
            check(unit and same(unit.advTalentIds, ids) and unit.advBranch.first == first
                and unit.advBranch.second == id, "HC真实单位保存路线和双天赋 " .. first)
            check(unit.attrs.modifiers["adv_stat_" .. first] ~= nil
                and unit.attrs.modifiers["adv_stat_" .. id] ~= nil
                and unit.attrs.modifiers["adv_stat_" .. other] == nil, "只有一份真实一转modifier " .. first)
            for key in pairs(AD.META) do
                check(close(unit.attrs:get(key), expected:get(key)), "实际属性=一份first+fusion " .. first .. "/" .. key)
            end
            AVC.applyStatBonuses(path, unit.attrs)
            check(close(unit.attrs:get(AD.MAX_HP), expected:get(AD.MAX_HP)), "重复属性应用幂等 " .. first)
            ids[1] = "test_mutation"
            check(same(AVC.getTalentIds(path), unit.advTalentIds) and same(path, snapshot),
                "天赋返回副本不污染配置/路线 " .. first)
        end
        for _, bad in ipairs({ { second = id }, { first = 999, second = id },
            { first = a == 101 and 103 or 101, second = id }, { first = id } }) do
            check(not AVC.hasTalent(bad, AVC.get(id).talentId), "非法路径不激活marker " .. id)
            local ids = AVC.getTalentIds(bad)
            for _, talentId in ipairs(AVC.get(id).talentIds) do
                local found = false
                for _, value in ipairs(ids) do if value == talentId then found = true end end
                check(not found, "非法路径不借两父天赋 " .. id)
            end
        end
    end
    check(#AVC.getTalentIds(nil) == 0 and #AVC.getTalentIds({}) == 0, "无转职空列表")
    check(same(AVC.getTalentIds({ first = 101, second = 101 }), { "gate_101_latch" }), "脏重复真实ID去重")
    check(AVC.getDualWieldMode({ first = 104, second = 207 }) == "different"
        and AVC.getDualWieldMode({ first = 110, second = 220 }) == "same", "旧双持模式不变")
    -- 校验两父配置而非仅检查列表中有first；只在本夹具的私有表上做负对照。
    local cfg, parent = AVC.get(225), AVC.get(102)
    local beforeClass, beforeStage = parent.baseClass, parent.advLevel
    parent.baseClass = "spoil"
    check(not AVC.isParentBranch(225, 101) and not AVC.hasTalent({ first = 101, second = 225 }, cfg.talentId),
        "另父跨职业时整个融合失效")
    parent.baseClass, parent.advLevel = beforeClass, 2
    check(not AVC.isParentBranch(225, 101), "另父非一转时整个融合失效")
    parent.advLevel = beforeStage
end

local function modulesFor(heroId, first)
    return { heroes = { roster = { [heroId] = { level = 70, exp = 0, shards = 0,
        advBranch = first and { first = first } or nil, awakening = {}, extraTalent = {} } },
        deployed = { heroId, 0, 0, 0 }, teams = { { slots = { heroId, 0, 0, 0 } } } },
        currency = { gold = 1000000 }, player = { level = 70, name = "fusion-test" },
        equipment = { inventory = {}, equipped = {} },
        artifacts = { bag = {}, equippedByTeam = {} }, talents = { litNodes = {} } }
end

-- 真正 StandaloneSave 的编码/写入/原子替换/恢复，所有File与dispatcher均为内存适配。
local function memorySave(f, modules)
    local files, state = {}, { name = "fusion-test", level = 70, exp = 0, gold = modules.currency.gold }
    local fileOps = 0
    local dispatcher = { snapshotAll = function() return modules end,
        get = function(key) return modules[key] end,
        handleStateUpdate = function(json)
            for key, data in pairs(cjson.decode(json).modules) do
                f.Schema.applyOnLoad(key, data)
                modules[key] = data
            end
        end }
    local saveEnv = setmetatable({}, { __index = f.env })
    saveEnv.File = function(path, mode)
        assert(path == "standalone_save.pending.json" or path == "standalone_save.json", "unexpected save path")
        fileOps = fileOps + 1
        local value, open = files[path], true
        local file = {}
        function file:IsOpen() return open and (mode == FILE_WRITE or value ~= nil) end
        function file:WriteString(json) value = json; files[path] = json; return true end
        function file:ReadString() return value end
        function file:Close() open = false; return true end
        function file:Dispose() open = false end
        return file
    end
    saveEnv.fileSystem = {
        FileExists = function(_, path) return files[path] ~= nil end,
        Delete = function(_, path) files[path] = nil; return true end,
        Rename = function(_, old, new)
            if not files[old] then return false end
            files[new], files[old] = files[old], nil
            return true
        end,
    }
    local replacements = {
        ["runtime.ClientDispatcher"] = dispatcher,
        ["core.GameState"] = { exportSave = function() return copy(state) end,
            importSave = function(saved) state = copy(saved) end, syncPlayerData = function() end },
        ["ui.battle.scene.BattleScene"] = {},
        ["rules.offline.OfflineService"] = { HasPendingRewards = function() return false end },
    }
    saveEnv.require = function(name) return replacements[name] or f.env.require(name) end
    local Save = assert(load(source("boot/StandaloneSave.lua"), "@fusion-memory-save", "t", saveEnv))()
    return { Save = Save, files = files, operations = function() return fileOps end }
end

local function serviceTests(f)
    local uid = 860225
    for _, row in ipairs(pairsConfig) do
        for _, first in ipairs({ row[2], row[3] }) do
            local heroId, fusion = row[6], row[4]
            local modules = modulesFor(heroId)
            f.PDM.AttachLocalModules(uid, modules)
            local gold = modules.currency.gold
            local ok1 = f.Service.AdvanceClass(uid, heroId, first, 1)
            local ok2, _, result = f.Service.AdvanceClass(uid, heroId, fusion, 2)
            check(ok1 and ok2 and result and result.branchName == row[5], "权威Service双入口转入 " .. first)
            check(modules.currency.gold == gold - 110000
                and same(modules.heroes.roster[heroId].advBranch, { first = first, second = fusion }),
                "Service扣单份一转二转金币并保留实际父 " .. first)
            local before = copy(modules)
            check(not f.Service.AdvanceClass(uid, heroId, fusion, 2) and same(modules, before),
                "Service重复转入零副作用 " .. first)
            local saver = memorySave(f, modules)
            check(saver.Save.Flush() and saver.operations() == 1, "实际Save全内存写入 " .. first)
            local saved = cjson.decode(saver.files["standalone_save.json"])
            check(same(saved.modules.heroes.roster["h" .. heroId].advBranch, { first = first, second = fusion }),
                "Save使用真实英雄键和路线 " .. first)
            -- 兼容冷档字符串ID，必须经实际Schema转成number，而非伪造双first。
            local branch = saved.modules.heroes.roster["h" .. heroId].advBranch
            branch.first, branch.second = tostring(first), tostring(fusion)
            saver.files["standalone_save.json"] = cjson.encode(saved)
            for key in pairs(modules) do modules[key] = nil end
            check(saver.Save.RestoreData(), "实际Save冷恢复 " .. first)
            ---@type table|nil
            local restored = modules.heroes.roster[heroId]
            assert(restored, "restored hero missing")
            check(restored and same(restored.advBranch, { first = first, second = fusion }),
                "Schema冷档水合真实双数字ID " .. first)
            local unit = f.HC.createHero(heroId, restored.level, restored.advBranch, restored.awakening,
                restored.extraTalent, { litNodes = false, silent = true })
            check(same(unit.advTalentIds, f.AVC.getTalentIds(restored.advBranch)), "冷恢复重建融合双天赋 " .. first)
            local ok, _, reset = f.Service.ResetClass(uid, heroId)
            check(ok and reset.refundGold == 110000 and modules.currency.gold == gold
                and restored.advBranch == nil, "权威重置全额单次返还 " .. first)
            local repeated, _, repeatedReset = f.Service.ResetClass(uid, heroId)
            check(repeated and repeatedReset.refundGold == 0 and modules.currency.gold == gold,
                "重复重置不重复返还 " .. first)
            check(saver.Save.Flush() and saver.Save.RestoreData()
                and modules.heroes.roster[heroId].advBranch == nil, "重置保存冷恢复无融合残留 " .. first)
            f.PDM.RemovePlayer(uid, true)
        end
    end
    local modules = modulesFor(1, 103)
    f.PDM.AttachLocalModules(uid, modules)
    for _, case in ipairs({ { level = 29, gold = 100000, target = 226 },
        { level = 30, gold = 99999, target = 226 }, { level = 30, gold = 100000, target = 225 } }) do
        modules.heroes.roster[1].level, modules.currency.gold = case.level, case.gold
        local before = copy(modules)
        local pushes = #f.pushes
        check(not f.Service.AdvanceClass(uid, 1, case.target, 2) and same(before, modules)
            and pushes == #f.pushes, "权威失败不扣钱/改路线/通知 " .. case.target .. "/" .. case.level)
    end
    f.PDM.RemovePlayer(uid, true)
    check(#f.pushes >= 72, "真实PDM只向内存dispatcher通知")
end

local function powerTests(f)
    for _, row in ipairs(pairsConfig) do
        local a, b, fusion, heroId = row[2], row[3], row[4], row[6]
        local powerResults = {}
        for _, first in ipairs({ a, b }) do
            local data = modulesFor(heroId, first)
            local equipment = data.equipment
            equipment.inventory["1"] = { templateId = "C1", quality = 1, level = 1,
                baseStats = { { f.AD.PHYS_ATK, 12 }, { f.AD.MAG_ATK, 9 }, { f.AD.MAX_HP, 50 } }, affixes = {} }
            equipment.equipped[heroId] = { accessory = 1 }
            local snapshot = copy(data)
            local ctx = assert(f.EP.buildContext(heroId, data))
            local predicted = assert(f.EP.evaluateAdvancement(ctx, fusion))
            local afterData = copy(data)
            afterData.heroes.roster[heroId].advBranch.second = fusion
            local actual = assert(f.EP.buildContext(heroId, afterData))
            local direct = f.HC.createHero(heroId, 70, { first = first, second = fusion }, {}, {},
                { litNodes = false, silent = true })
            f.EP.applyEquipment(direct.attrs, actual.equipmentData, heroId)
            -- hp是运行态（EP clone保留穿装前当前血），不是静态属性/战力输入。
            -- 比较其余所有AD属性，包括真正的生命上限，不把满血时序当属性回归。
            for key in pairs(f.AD.META) do
                if key ~= f.AD.HP then
                    check(close(direct.attrs:get(key), actual.hero.attrs:get(key)), "EP/HC实际属性相等 " .. first .. "/" .. key)
                end
            end
            check(close(predicted.currentPower, ctx.currentPower) and close(predicted.previewPower, actual.currentPower)
                and close(predicted.gain, actual.currentPower - ctx.currentPower), "融合两路估值对应真实路线 " .. first)
            local directPower = f.CombatPower.calculate(direct, { teamUnits = { direct },
                heroesData = afterData.heroes, equipmentData = actual.equipmentData,
                artifactsData = actual.artifactsData, talentsData = actual.talentsData })
            check(close(predicted.previewPower, directPower), "融合预估=直接HC单位正式战力 " .. first)
            check(f.EP.evaluateAdvancement(ctx, fusion) == predicted, "同first memo复用 " .. first)
            local other = first == a and b or a
            ctx.heroesData.roster[heroId].advBranch.first = other
            local changed = assert(f.EP.evaluateAdvancement(ctx, fusion))
            local otherData = copy(data)
            otherData.heroes.roster[heroId].advBranch.first = other
            local otherBefore = assert(f.EP.buildContext(heroId, otherData))
            otherData.heroes.roster[heroId].advBranch.second = fusion
            local otherAfter = assert(f.EP.buildContext(heroId, otherData))
            check(changed ~= predicted and close(changed.currentPower, otherBefore.currentPower)
                and close(changed.previewPower, otherAfter.currentPower), "memo含first不借另一路 " .. first)
            ctx.heroesData.roster[heroId].advBranch.first = 999
            check(f.EP.evaluateAdvancement(ctx, fusion) == nil, "非法已有first不造路线 " .. first)
            check(same(data, snapshot), "所有EP预览不写玩家输入 " .. first)
            powerResults[#powerResults + 1] = predicted
            -- 同职业原二转仍按各自原parent预览，贡献不偷偷改为当前first。
            local oldId = f.AVC.SECOND_BRANCHES[first][1]
            local old = assert(f.EP.evaluateAdvancement(ctx, oldId))
            local oldData = copy(data)
            oldData.heroes.roster[heroId].advBranch = { first = first, second = oldId }
            local oldAfter = assert(f.EP.buildContext(heroId, oldData))
            check(close(old.currentPower, predicted.currentPower) and close(old.previewPower, oldAfter.currentPower),
                "原分支增量贡献保持 " .. first)
        end
        local detailData = modulesFor(heroId)
        local blank = assert(f.EP.buildContext(heroId, detailData))
        local detail = assert(f.EP.evaluateAdvancement(blank, fusion))
        detailData.heroes.roster[heroId].advBranch = { first = a }
        local before = assert(f.EP.buildContext(heroId, detailData))
        detailData.heroes.roster[heroId].advBranch.second = fusion
        local after = assert(f.EP.buildContext(heroId, detailData))
        check(close(detail.currentPower, before.currentPower) and close(detail.previewPower, after.currentPower)
            and blank.heroesData.roster[heroId].advBranch == nil, "无一转详情首父只读预览 " .. fusion)
        print(string.format("%s POWER fusion=%d first=%d current=%.6f preview=%.6f gain=%.6f; first=%d current=%.6f preview=%.6f gain=%.6f",
            TAG, fusion, a, powerResults[1].currentPower, powerResults[1].previewPower, powerResults[1].gain,
            b, powerResults[2].currentPower, powerResults[2].previewPower, powerResults[2].gain))
    end
    check(f.EP.evaluateAdvancement(nil, 225) == nil, "无ctx安全返回nil")
    check(f.EP.evaluateAdvancement(f.EP.buildContext(1, modulesFor(1)), 225) == nil, "跨职业详情不预览")
end

local function resourceTests()
    ---@type Image[]
    local held = {}
    ---@type table<number, Image>
    local loaded = {}
    local function imageFor(id)
        if loaded[id] then return loaded[id] end
        local path = "image/职业图标/UI_icon_ZY_" .. id .. ".png"
        local file = assert(cache:GetFile(path), "missing icon " .. id)
        file:Dispose()
        local image = Image()
        held[#held + 1] = image
        assert(image:Load("/workspace/assets/" .. path), "icon load failed " .. id)
        loaded[id] = image
        return image
    end
    local ok, err = pcall(function()
        for _, row in ipairs(pairsConfig) do
            local a, b, id = row[2], row[3], row[4]
            local image, parentA, parentB = imageFor(id), imageFor(a), imageFor(b)
            check(image.width == 280 and image.height == 280 and image.components == 4,
                "融合真实PNG 280RGBA " .. id)
            check(image:GetPixel(0, 0).a == 0 and image:GetPixel(279, 0).a == 0
                and image:GetPixel(0, 279).a == 0 and image:GetPixel(279, 279).a == 0,
                "融合PNG四角全透明 " .. id)
            local outsideA, outsideB, changedA, changedB, shapeA, shapeB = 0, 0, 0, 0, 0, 0
            for y = 0, 279 do
                for x = 0, 279 do
                    local pixel = image:GetPixelInt(x, y)
                    local differsA = pixel ~= parentA:GetPixelInt(x, y)
                    local differsB = pixel ~= parentB:GetPixelInt(x, y)
                    if (x - 139.5) ^ 2 + (y - 139.5) ^ 2 > 114 ^ 2 then
                        if differsA then outsideA = outsideA + 1 end
                        if differsB then outsideB = outsideB + 1 end
                    else
                        if differsA then changedA = changedA + 1 end
                        if differsB then changedB = changedB + 1 end
                        local c, ca, cb = image:GetPixel(x, y), parentA:GetPixel(x, y), parentB:GetPixel(x, y)
                        local bright = (c.r + c.g + c.b) / 3 > 0.55
                        if bright ~= ((ca.r + ca.g + ca.b) / 3 > 0.55) then shapeA = shapeA + 1 end
                        if bright ~= ((cb.r + cb.g + cb.b) / 3 > 0.55) then shapeB = shapeB + 1 end
                    end
                end
            end
            check(outsideA == 0 and outsideB == 0, "半径114外底板与两父逐像素一致 " .. id)
            check(changedA > 500 and shapeA > 200 and changedB > 500 and shapeB > 200,
                "内圈融合独立轮廓非复制任一父 " .. id)
        end
        for i = 1, #pairsConfig - 1 do
            for j = i + 1, #pairsConfig do
                local a, b = pairsConfig[i][4], pairsConfig[j][4]
                local imageA, imageB = imageFor(a), imageFor(b)
                local changed = 0
                for y = 26, 253 do
                    for x = 26, 253 do
                        if imageA:GetPixelInt(x, y) ~= imageB:GetPixelInt(x, y) then changed = changed + 1 end
                    end
                end
                check(changed > 500, "六融合图互异 " .. a .. "/" .. b)
            end
        end
    end)
    for _, image in ipairs(held) do image:Dispose() end
    assert(ok, err)
end

function Start()
    local ok, err = pcall(function()
        local f = fixture()
        treeTests(f)
        attributeTests(f)
        serviceTests(f)
        powerTests(f)
        resourceTests()
    end)
    if not ok then check(false, "exception " .. tostring(err)) end
    print(string.format("%s %s assertions=%d failures=%d", TAG,
        failures == 0 and "ALL PASS" or "FAIL", assertions, failures))
    if engine then engine:Exit() end
    assert(failures == 0, "advancement fusion failures=" .. failures)
end
