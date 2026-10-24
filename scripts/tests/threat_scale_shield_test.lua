-- 怨引百点制与盾牌固有属性专项；复用 equipment_secondary_stats_test 的独立 Runtime 骨架。
-- 入口仅执行白名单生产模块，不 require main、不读取玩家档、不联网、不发奖。
-- 由主代理统一构建/运行；以 failure_count 为准，engine:Exit() 本身不表示通过。
-- 铁憨憨真实 TalentManager 开战全链、BattleCombat 多目标落地由主代理另行验收，
-- 本文件不为其构建庞大的天赋/投射物替身链。
local PREFIX = "[threat_scale_shield] "
local checks, failures = 0, {}
local function check(ok, text)
    checks = checks + 1
    if not ok then failures[#failures + 1] = text; print(PREFIX .. "[FAIL] " .. text) end
end
local function near(a, b)
    return type(a) == "number" and type(b) == "number" and a == a and b == b
        and math.abs(a - b) <= math.max(1, math.abs(b)) * 1e-9
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
local sources = {}
---@param path string
---@return string
local function source(path)
    if sources[path] then return sources[path] end
    local file = assert(cache:GetFile(path), "缺少测试源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = table.concat(lines, "\n")
    sources[path] = text
    return text
end
local ALLOWED = {
    ["systems.AttributeDef"] = true, ["systems.UnitAttributes"] = true,
    ["systems.EquipmentSystem"] = true, ["systems.EquipmentSecondaryStats"] = true,
    ["systems.ThreatManager"] = true, ["systems.CombatFormula"] = true,
    ["systems.BattleDiag"] = true, ["config.ClassConfig"] = true,
    ["config.EquipmentConfig"] = true, ["config.AffixConfig"] = true,
    ["config.BlacksmithConfig"] = true, ["core.BattleLayout"] = true,
}
local function fixture()
    local loaded, artifactCalls = {}, {}
    local rng = { calls = 0 }
    -- 只复制纯 Lua 必需能力；不继承 _G，不暴露 File/存档/网络/引擎入口。
    local privateMath = copy(math)
    privateMath.random = function(...)
        rng.calls = rng.calls + 1
        return math.random(...)
    end
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        tonumber = tonumber, tostring = tostring, type = type, select = select,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
        math = privateMath, table = table, string = string, print = print,
        os = { clock = os.clock },
    }
    env._G = env
    local function import(name)
        if loaded[name] then return loaded[name] end
        if name == "systems.ArtifactRuntime" then
            -- 唯一业务边界替身：不修改仇恨量，记录收到的是已归一化结果。
            local boundary = { adjustThreatGain = function(unit, amount)
                artifactCalls[#artifactCalls + 1] = { unit = unit, amount = amount }
                return amount
            end }
            loaded[name] = boundary
            return boundary
        end
        assert(ALLOWED[name], "禁止加载非白名单模块 " .. tostring(name))
        local path = name:gsub("%.", "/") .. ".lua"
        local result = assert(load(source(path), "@threat-private/" .. path, "t", env))()
        loaded[name] = result
        return result
    end
    env.require = import
    return {
        AD = import("systems.AttributeDef"), UA = import("systems.UnitAttributes"),
        Eq = import("systems.EquipmentSystem"), Secondary = import("systems.EquipmentSecondaryStats"),
        EC = import("config.EquipmentConfig"), TM = import("systems.ThreatManager"),
        CF = import("systems.CombatFormula"), Layout = import("core.BattleLayout"),
        artifactCalls = artifactCalls, math = privateMath, rng = rng,
    }
end
local function noRNG(f, fn, label)
    local before = f.rng.calls
    fn()
    check(f.rng.calls == before, label .. "不消费RNG")
end
local function withRolls(f, rolls, fn, label)
    local original, consumed = f.math.random, 0
    f.math.random = function(...)
        assert(select("#", ...) == 0, "选敌只应请求无参随机")
        consumed = consumed + 1
        return assert(rolls[consumed], "发生额外选敌RNG")
    end
    local ok, err = xpcall(fn, debug.traceback)
    f.math.random = original
    check(ok, label .. "无异常 " .. (ok and "" or tostring(err)))
    check(consumed == #rolls, label .. "随机调用次数=" .. #rolls)
end
local function unit(f, threat)
    local cfg = { maxHp = 1000 }
    if threat ~= nil then cfg.threat = threat end
    local attrs = f.UA.create(cfg)
    attrs:fillHp()
    return { attrs = attrs, hp = attrs:get(f.AD.HP), name = "测试单位" }
end
local function threatRows(stats)
    local count, value, index = 0, 0, 0
    for i, row in ipairs(stats or {}) do
        if row[1] == "threat" then count, value, index = count + 1, row[2], i end
    end
    return count, value, index
end
local function checkIntrinsic(f, item, label)
    local count, value, index = threatRows(item.baseStats)
    check(count == 1 and value == 50, label .. "仅一条固有怨引50")
    if count ~= 1 then return end
    check(f.Eq.getSecondaryAscendCount(item, index) == 0, label .. "固有不占升阶次数")
    check(f.Eq.effectiveBaseStatValue(item, index) == 50
        and f.Eq.effectiveBaseStatValue(item, index, 100000, 100) == 50,
        label .. "固有生效常量50，不吃显式主倍率/升阶预览")
    local total, entries = 0, f.Eq.computeModifierEntries(item, 100000)
    for _, entry in ipairs(entries) do if entry.key == "threat" then total = total + entry.flat end end
    -- 当前随机词缀无怨引；基础条目独立核验，防未来新增同key来源掩盖固有层错误。
    local baseThreat = 0
    for i = 1, #item.baseStats do
        if entries[i].key == "threat" then baseThreat = baseThreat + entries[i].flat end
    end
    check(baseThreat == 50 and total >= 50, label .. "真实modifier基础怨引仍50")
end

local function testAttributeScale(f)
    local AD = f.AD
    check(AD.THREAT_BASE == 100, "怨引基准明确为100")
    check(AD.META.threat.default == 100 and AD.META.threat.dataType == AD.TYPE_INT
        and near(AD.META.threat.valueModel, 0.0008), "META默认100/整数/价值0.0008")
    local u = unit(f)
    check(u.attrs:get(AD.THREAT) == 100 and f.TM.getThreatMultiplier(u) == 1, "真实属性默认100=1倍")
    u.attrs:addModifier("pct15", { { key = "threat", pct = 15 } })
    check(u.attrs:get(AD.THREAT) == 115, "无盾基础100加15%=115")
    local shield = f.Eq.generate("O1", 1, 1, { legacySecondary = true })
    f.Eq.applyToUnit(u.attrs, shield, 1, 0)
    check(u.attrs:get(AD.THREAT) == 173, "真实盾50与pct15叠加：(100+50)×1.15取整=173")
    check(near(f.TM.getThreatMultiplier(u), 1.73), "盾与百分比最终173换算1.73倍")
    f.Eq.removeFromUnit(u.attrs, 1)
    check(u.attrs:get(AD.THREAT) == 115, "卸盾恢复115，不残留固有层")
    u.attrs:removeModifier("pct15")
    check(u.attrs:get(AD.THREAT) == 100, "移除百分比恢复100")
    check(f.TM.getThreatMultiplier({}) == 1, "缺attrs按100而非旧1点解释")
    check(near(f.TM.getThreatMultiplier(unit(f, 0)), 0.01)
        and near(f.TM.getThreatMultiplier(unit(f, -50)), 0.01), "零/负怨引最低1点=0.01倍")
    check(f.TM.getThreatMultiplier(unit(f, 150)) == 1.5, "显式150=1.5倍")
end

local function testThreatGains(f)
    local TM = f.TM
    TM.mount(TM.newState())
    for _, sample in ipairs({ { 100, 105, 125, 100, 10.5 }, { 150, 157.5, 187.5, 150, 15.75 } }) do
        local u = unit(f, sample[1])
        local first = #f.artifactCalls
        TM.onDamageDealt(u, 100)
        check(near(TM.getThreat(u), sample[2]), "真实攻击：怨引" .. sample[1] .. "伤害100含基础5")
        check(#f.artifactCalls == first + 1 and f.artifactCalls[#f.artifactCalls].unit == u
            and near(f.artifactCalls[#f.artifactCalls].amount, sample[2]), "神器边界收到归一化攻击量，不再乘100")
        TM.clearThreat(u)
        TM.onHealingDone(u, 100)
        check(near(TM.getThreat(u), sample[3]), "真实治疗：怨引" .. sample[1] .. "治疗100含基础25")
        check(near(f.artifactCalls[#f.artifactCalls].amount, sample[3]), "神器边界收到归一化治疗量")
        TM.clearThreat(u)
        TM.onDamageDealt(u, 100, false)
        check(near(TM.getThreat(u), sample[4]), "多目标后续命中不重复基础5")
        TM.clearThreat(u)
        TM.onDamageDealt(u, 100, true, 0.1)
        check(near(TM.getThreat(u), sample[5]), "飞剑0.1倍率只应用一次")
        TM.clearThreat(u)
        TM.onDamageDealt(u, 100, true)
        TM.onDamageDealt(u, 100, false)
        check(near(TM.getThreat(u), sample[1] == 100 and 205 or 307.5), "同一多目标出手基础仇恨仅计一次")
        local before = #f.artifactCalls
        u._laoliuStealthLeft = 1
        TM.onDamageDealt(u, 100)
        check(#f.artifactCalls == before, "隐匿攻击不进入神器仇恨边界")
    end
    local noAttrs = { hp = 1000 }
    TM.onDamageDealt(noAttrs, 100)
    check(TM.getThreat(noAttrs) == 105, "无attrs真实攻击仍是1倍")
    TM.clearThreat(noAttrs)
    TM.onHealingDone(noAttrs, 100)
    check(TM.getThreat(noAttrs) == 125, "无attrs真实治疗仍是1倍")
end

local function testTargeting(f)
    local TM, CF = f.TM, f.CF
    TM.mount(TM.newState())
    local units = { unit(f), unit(f), unit(f), unit(f) }
    for i, expected in ipairs({ 50, 40, 20, 20 }) do
        check(TM.getTargetWeight(units[i], i) == expected, "基础主目标权重5:4:2:2槽" .. i)
    end
    check(same(f.Layout.HIT_WEIGHTS, { 5, 4, 2, 2 }), "正式站位受击表未被测试替换")
    local basicRolls = { 0, 0.38, 0.39, 0.69, 0.70, 0.84, 0.85, 0.999999 }
    local basicExpected = { 1, 1, 2, 2, 3, 3, 4, 4 }
    for _, selector in ipairs({ TM.selectTarget, CF.selectTarget }) do
        withRolls(f, basicRolls, function()
            for i, expected in ipairs(basicExpected) do
                check(selector(units) == expected, "真实选敌基础区间样本" .. i)
            end
        end, "TM/CF基础5:4:2:2")
    end
    local shield = f.Eq.generate("O7", 1, 1, { legacySecondary = true })
    f.Eq.applyToUnit(units[1].attrs, shield, 7, 0)
    check(units[1].attrs:get("threat") == 150 and TM.getTargetWeight(units[1], 1) == 75,
        "真实盾前排静态权重7.5:4:2:2，站位只乘一次")
    local shieldRolls = { 0, 0.48, 0.49, 0.74, 0.75, 0.87, 0.88, 0.999999 }
    local shieldExpected = { 1, 1, 2, 2, 3, 3, 4, 4 }
    for _, selector in ipairs({ TM.selectTarget, CF.selectTarget }) do
        withRolls(f, shieldRolls, function()
            for i, expected in ipairs(shieldExpected) do
                check(selector(units) == expected, "真实盾选敌区间样本" .. i)
            end
        end, "TM/CF盾前排7.5:4:2:2")
    end
    -- 不借被测helper生成oracle：前排动态10+静态15，再乘5，明确是125。
    TM.setThreat(units[1], 10)
    check(TM.getTargetWeight(units[1], 1) == 125, "动态10只加一次，不再乘1.5")
    withRolls(f, { 0.60 }, function()
        check(TM.selectTarget(units) == 1, "真实TM主目标包含动态仇恨")
    end, "动态仇恨主目标")
    withRolls(f, { 0.60 }, function()
        check(CF.selectTarget(units) == 2, "真实CF静态选敌不读取TM动态表")
    end, "真实CF静态独立")
    TM.forceTarget(units[4], 1)
    withRolls(f, {}, function() check(TM.selectTarget(units) == 4, "强制嘲讽覆盖权重且不掷骰") end, "强嘲讽")
    units[4].artifactUntargetable = true
    withRolls(f, { 0.999999 }, function()
        check(TM.selectTarget(units) == 3, "不可选的强嘲讽目标被跳过")
        check(TM.selectTarget({ units[4] }) == 0, "全不可选返回0")
    end, "强嘲讽不可选")
    units[4].artifactUntargetable = nil
    units[4].hp = 0
    units[4].attrs.final[f.AD.HP] = 0
    withRolls(f, { 0.999999, 0.999999 }, function()
        check(TM.selectTarget(units) == 3, "死者强嘲讽被跳过")
        check(CF.selectTarget(units) == 3, "真实CF跳过attrs已死目标")
    end, "死者过滤")
    units[4].hp = 1000
    units[4].attrs:fillHp()
    TM.update(2)
    withRolls(f, { 0 }, function() check(TM.selectTarget(units) == 1, "嘲讽到期恢复加权选敌") end, "嘲讽到期")
    units[1].hp = 0
    units[1].attrs.final[f.AD.HP] = 0
    units[2].artifactUntargetable = true
    units[4].artifactUntargetable = true
    for _, selector in ipairs({ TM.selectTarget, CF.selectTarget }) do
        withRolls(f, {}, function()
            check(selector(units) == 3, "唯一活且可选者保持原槽3，不压缩站位")
            check(selector({}) == 0, "空阵返回0")
            check(selector({ units[1], units[2] }) == 0, "全死/不可选返回0")
        end, "单目标/空阵不耗RNG")
    end
end

local function testMountIsolation(f)
    local TM, u, v = f.TM, unit(f), unit(f, 150)
    local a, b = TM.newState(), TM.newState()
    TM.mount(a)
    TM.setThreat(u, 20)
    TM.forceTarget(v, 10)
    TM.mount(b)
    check(TM.getThreat(u) == 0 and TM.getTargetWeight(u, 1) == 50, "第二战斗不继承第一场动态仇恨")
    TM.setThreat(u, 7)
    withRolls(f, { 0 }, function() check(TM.selectTarget({ u, v }) == 1, "第二场不继承第一场强嘲讽") end, "mount强嘲讽隔离")
    TM.forceTarget(u, 5)
    TM.mount(a)
    check(TM.getThreat(u) == 20 and TM.getTargetWeight(u, 1) == 150, "挂回第一场保留原动态20")
    withRolls(f, {}, function() check(TM.selectTarget({ u, v }) == 2, "挂回第一场保留强嘲讽") end, "第一场保留嘲讽")
    TM.reset()
    TM.mount(b)
    check(TM.getThreat(u) == 7, "reset第一场不清第二场动态")
    withRolls(f, {}, function() check(TM.selectTarget({ u, v }) == 1, "reset第一场不清第二场嘲讽") end, "第二场独立嘲讽")
    TM.removeUnit(u)
    check(TM.getThreat(u) == 0, "removeUnit仅清当前实例目标")
    TM.mount(nil)
end

-- 固定历史模板oracle：三条主/副不含新固有层，不能从被测buildBaseStats倒算。
local SHIELDS = {
    O1 = { "dodge", 3.14, "atkSpeed", 1.6, "physBlockRate", 1.2 },
    O2 = { "dodge", 4.40, "atkSpeed", 2.2, "physBlockRate", 1.8 },
    O3 = { "dodge", 5.66, "atkSpeed", 2.8, "physBlockRate", 2.3 },
    O4 = { "dodge", 6.91, "atkSpeed", 3.4, "physBlockRate", 2.7 },
    O5 = { "dodge", 8.18, "atkSpeed", 4.0, "physBlockRate", 3.3 },
    O6 = { "dodge", 9.43, "atkSpeed", 4.8, "physBlockRate", 3.8 },
    O7 = { "armor", 4.49, "physBlockRate", 1.2, "magBlockRate", 1.2 },
    O8 = { "armor", 6.28, "physBlockRate", 1.8, "magBlockRate", 1.8 },
    O9 = { "armor", 8.08, "physBlockRate", 2.3, "magBlockRate", 2.3 },
    O10 = { "armor", 9.87, "physBlockRate", 2.7, "magBlockRate", 2.7 },
    O11 = { "armor", 11.68, "physBlockRate", 3.3, "magBlockRate", 3.3 },
    O12 = { "armor", 13.47, "physBlockRate", 3.8, "magBlockRate", 3.8 },
    O31 = { "dodge", 8.18, "atkSpeed", 4.0, "physBlockRate", 3.3 },
    O32 = { "dodge", 9.43, "atkSpeed", 4.8, "physBlockRate", 3.8 },
    O33 = { "armor", 11.68, "physBlockRate", 3.3, "magBlockRate", 3.3 },
    O34 = { "dodge", 9.43, "atkSpeed", 4.8, "physBlockRate", 3.8 },
    O35 = { "armor", 13.47, "physBlockRate", 3.8, "magBlockRate", 3.8 },
    O38 = { "armor", 13.47, "physBlockRate", 3.8, "magBlockRate", 3.8 },
}
local QUALITY_STRENGTH = { 1, 1.1, 1.2, 1.3, 1.4, 1.5 }
local function historicalStats(id, level, quality, corrupt)
    local values, result = assert(SHIELDS[id]), {}
    for i = 1, 3 do
        result[i] = { values[i * 2 - 1], values[i * 2]
            * (1 + (level - 1) * 0.05) * QUALITY_STRENGTH[quality] * (corrupt or 1) }
    end
    return result
end
local function prefix(stats, length)
    local result = {}
    for i = 1, length do result[i] = copy(stats[i]) end
    return result
end
local function testAllShields(f)
    local shieldCount, lightCount, heavyCount = 0, 0, 0
    local ids = {}
    for id, tpl in pairs(f.EC.ITEMS) do
        local isShield = tpl.slot == "offhand" and (tpl.type == "轻盾" or tpl.type == "重盾")
        if isShield then
            shieldCount = shieldCount + 1
            if tpl.type == "轻盾" then lightCount = lightCount + 1 else heavyCount = heavyCount + 1 end
            check(SHIELDS[id] ~= nil, id .. "在独立历史oracle中")
            ids[#ids + 1] = id
            check(same(tpl.intrinsicStats, { { "threat", 50 } }), id .. "模板固有层恰为threat50")
            check(same(tpl.stats, historicalStats(id, 1, 1)), id .. "三条历史主副key/值/顺序完全不变")
        else
            local n = threatRows(tpl.intrinsicStats)
            check(n == 0, id .. "非盾不增加固有怨引")
        end
    end
    check(shieldCount == 18 and lightCount == 9 and heavyCount == 9, "全部18盾模板覆盖，轻重各9")
    for id in pairs(SHIELDS) do check(f.EC.ITEMS[id] ~= nil, id .. "历史盾模板仍存在") end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local tpl = f.EC.ITEMS[id]
        local snapshot = copy(tpl)
        for quality = 1, 6 do
            for _, level in ipairs({ 1, 81, 9999 }) do
                for _, legacy in ipairs({ false, true }) do
                    local label = id .. "/q" .. quality .. "/lv" .. level .. (legacy and "/旧副" or "/新副")
                    local item = f.Eq.generate(id, level, quality, { legacySecondary = legacy })
                    check(#item.baseStats == 4, label .. "固有只附加一行")
                    checkIntrinsic(f, item, label)
                    local roll = copy(item.secondaryRoll)
                    if legacy then
                        check(item.secondaryRoll == nil and same(prefix(item.baseStats, 3), historicalStats(id, level, quality)),
                            label .. "原副值不变且不补抽")
                    else
                        check(item.secondaryRoll.version == 1 and #item.secondaryRoll.stats == 2,
                            label .. "随机副仍两条，不含固有行")
                        for _, row in ipairs(item.secondaryRoll.stats) do check(row[1] ~= "threat", label .. "固有不挤进secondaryRoll") end
                    end
                    -- 每个模板/品质/等级/新旧路径都再经腐化+满升阶重算。
                    item.corruptCount, item.corruptBaseMult, item.ascendLevel = 1, 1.35, 100
                    item.baseStats = nil
                    noRNG(f, function() f.Eq.hydrate(item) end, label .. "腐化水合")
                    checkIntrinsic(f, item, label .. "/腐化升阶100")
                    check(same(item.secondaryRoll, roll), label .. "腐化不改保存副基值")
                    if legacy then
                        check(same(prefix(item.baseStats, 3), historicalStats(id, level, quality, 1.35)), label .. "只普通主副吃腐化1.35")
                    end
                    check(f.Eq.getSecondaryAscendCount(item, 2) == 50
                        and f.Eq.getSecondaryAscendCount(item, 3) == 50, label .. "满升阶两副各50次，不被固有分流")
                end
            end
        end
        check(same(tpl, snapshot), id .. "生成/水合不污染模板")
    end
    print(PREFIX .. "模板覆盖=" .. shieldCount .. "，品质=1..6，等级=1/81/9999，新旧副均测腐化及升阶100")
end

local function testRotationAndPersistence(f)
    for _, id in ipairs({ "O1", "O7", "O34", "O38" }) do
        for _, legacy in ipairs({ false, true }) do
            local item = f.Eq.generate(id, 81, 6, { legacySecondary = legacy })
            item.ascendLevel, item.corruptCount, item.corruptBaseMult = 100, 1, 1.35
            item.baseStats = nil
            f.Eq.hydrate(item)
            local saved, roll = copy(item.baseStats), copy(item.secondaryRoll)
            check(f.Eq.getSecondaryAscendCount(item, 0) == 0
                and f.Eq.getSecondaryAscendCount(item, 1) == 0
                and f.Eq.getSecondaryAscendCount(item, 99) == 0, id .. "非法/主词条索引不获得副升阶次数")
            for _, row in ipairs({ { 0, 0, 0 }, { 1, 1, 0 }, { 2, 1, 1 }, { 3, 2, 1 }, { 99, 50, 49 }, { 100, 50, 50 } }) do
                item.ascendLevel = row[1]
                check(f.Eq.getSecondaryAscendCount(item, 2) == row[2]
                    and f.Eq.getSecondaryAscendCount(item, 3) == row[3], id .. "独立轮转oracle升阶" .. row[1])
                -- 当前设计每次副属性提升5%；不从被测计数或BC配置反算期望。
                check(near(f.Eq.effectiveBaseStatValue(item, 2), saved[2][2] * (1 + row[2] * 0.05))
                    and near(f.Eq.effectiveBaseStatValue(item, 3), saved[3][2] * (1 + row[3] * 0.05)),
                    id .. "旧副提升公式不变升阶" .. row[1])
                checkIntrinsic(f, item, id .. "/轮转" .. row[1])
            end
            item.ascendLevel = 100
            noRNG(f, function()
                for _ = 1, 4 do f.Secondary.restore(f.EC.ITEMS[id], item); f.Eq.hydrate(item) end
                local lean = f.Eq.dehydrate(item)
                check(lean.baseStats == nil, id .. "脱水仍省略可派生baseStats")
                if not legacy then
                    check(lean.secondaryRoll ~= item.secondaryRoll and lean.secondaryRoll.stats ~= item.secondaryRoll.stats,
                        id .. "脱水副基值深拷贝")
                end
                local restored = f.Eq.hydrate(cjson.decode(cjson.encode(lean)))
                check(same(restored.baseStats, saved) and same(restored.secondaryRoll, roll), id .. "JSON往返保主副/固有/腐化")
                check(restored.ascendLevel == 100 and restored.corruptBaseMult == 1.35, id .. "JSON保升阶与腐化倍率")
                checkIntrinsic(f, restored, id .. "/JSON")
                local stable = copy(restored)
                for _ = 1, 4 do f.Secondary.restore(f.EC.ITEMS[id], restored); f.Eq.hydrate(restored) end
                check(same(restored, stable), id .. "重复restore/hydrate完全幂等")
            end, id .. "持久化/重复restore")
        end
    end
end

local function testOldCacheAndInventory(f)
    for _, id in ipairs({ "O1", "O7", "O34", "O38" }) do
        local tpl = f.EC.ITEMS[id]
        -- 自带完整name/type/slot的旧遗匣，是addToInventory原先不会hydrate的缺口。
        local cached = { templateId = id, name = tpl.name, type = tpl.type, slot = tpl.slot,
            level = 81, quality = 6, ascendLevel = 100, affixes = {}, baseStats = historicalStats(id, 81, 6) }
        local original, reference = copy(cached.baseStats), cached.baseStats
        noRNG(f, function()
            f.Secondary.restore(tpl, cached)
            check(cached.baseStats == reference and same(prefix(cached.baseStats, 3), original), id .. "旧缓存原地补固有，不重算主副")
            check(cached.secondaryRoll == nil, id .. "旧缓存不创建随机副字段")
            checkIntrinsic(f, cached, id .. "/旧缓存")
            for _ = 1, 4 do f.Secondary.restore(tpl, cached) end
            check(#cached.baseStats == 4, id .. "旧缓存重复restore不重复附加")
            cached.baseStats = copy(original)
            local inventory = { nextSeq = 41, inventory = {} }
            local seq = f.Eq.addToInventory(inventory, cached)
            check(seq == 41 and inventory.nextSeq == 42 and inventory.inventory["41"] == cached,
                id .. "完整旧盾真实入包保引用/序号")
            checkIntrinsic(f, cached, id .. "/完整旧盾入包")
            check(same(prefix(cached.baseStats, 3), original) and cached.secondaryRoll == nil, id .. "入包不改原副/不补骰")
            local restored = f.Eq.hydrate(cjson.decode(cjson.encode(f.Eq.dehydrate(cached))))
            check(same(restored.baseStats, cached.baseStats), id .. "已迁移旧缓存JSON再入场不丢固有")
        end, id .. "旧缓存/完整入包")
        -- 历史缓存中若已有固有行，不能叠加到100；同一key重复行要合并为一条50。
        cached.baseStats = copy(original)
        cached.baseStats[#cached.baseStats + 1] = { "threat", 50000 }
        cached.baseStats[#cached.baseStats + 1] = { "threat", 50 }
        f.Secondary.restore(tpl, cached)
        checkIntrinsic(f, cached, id .. "/重复脏固有修复")
        check(same(prefix(cached.baseStats, 3), original), id .. "清理重复固有不破坏历史主副")
    end
    local nonShield = f.Eq.generate("O13", 81, 6, { legacySecondary = true })
    local before = copy(nonShield.baseStats)
    f.Secondary.restore(f.EC.ITEMS.O13, nonShield)
    check(same(nonShield.baseStats, before) and threatRows(nonShield.baseStats) == 0, "魔典旧缓存不被误判为盾")
end

local function testRNGCompatibility(f)
    for _, id in ipairs({ "O1", "O7", "O34", "O38" }) do
        local tpl = f.EC.ITEMS[id]
        for quality = 1, 6 do
            for _, legacy in ipairs({ false, true }) do
                math.randomseed(20261024 + quality)
                -- 重放既有词缀+两次固定副抽取；无固有信息的模板副本提供旧链基线。
                local q = f.EC.QUALITY[quality]
                local expectedAffixes = f.Eq.rollAffixes(q.affixCount, q.maxAffixQuality, 81, {}, q.randomStrength, tpl.grip)
                local previousTemplate = copy(tpl)
                previousTemplate.intrinsicStats = nil
                ---@type table|nil
                local expectedRoll = nil
                if not legacy then expectedRoll = f.Secondary.roll(previousTemplate) end
                local nextExpected = math.random()
                math.randomseed(20261024 + quality)
                local actual = f.Eq.generate(id, 81, quality, { legacySecondary = legacy })
                local nextActual = math.random()
                check(same(actual.affixes, expectedAffixes) and same(actual.secondaryRoll, expectedRoll), id .. "/q" .. quality .. "固有不改原词缀/副roll结果")
                check(nextActual == nextExpected, id .. "/q" .. quality .. "生成固有不消费额外RNG")
                noRNG(f, function()
                    f.Secondary.buildBaseStats(tpl, 9999, 999, actual.secondaryRoll)
                    f.Eq.recalcBaseStats(id, 9999, 999, actual.secondaryRoll)
                    f.Secondary.restore(tpl, actual)
                    f.Eq.hydrate(actual)
                    f.Eq.dehydrate(actual)
                    f.Eq.getSecondaryAscendCount(actual, 2, 100)
                    f.Eq.effectiveBaseStatValue(actual, 4, 1000, 100)
                end, id .. "/q" .. quality .. "查询/重算")
            end
        end
    end
end

function Start()
    local ok, err = xpcall(function()
        local f = fixture()
        -- 各组独立捕获，某组失败不会吞掉后续装备/战斗覆盖。
        for _, group in ipairs({
            { "属性百点制", testAttributeScale }, { "真实攻击治疗仇恨", testThreatGains },
            { "真实TM/CF选敌", testTargeting }, { "多实例隔离", testMountIsolation },
            { "全盾模板与倍率", testAllShields }, { "轮转与持久化", testRotationAndPersistence },
            { "旧缓存与完整入包", testOldCacheAndInventory }, { "RNG兼容", testRNGCompatibility },
        }) do
            local passed, why = xpcall(function() group[2](f) end, debug.traceback)
            if not passed then check(false, group[1] .. " Runtime异常:" .. tostring(why)) end
            print(PREFIX .. "完成 " .. group[1])
        end
    end, debug.traceback)
    if not ok then check(false, "Runtime初始化异常:" .. tostring(err)) end
    print(PREFIX .. "checks=" .. checks .. " failure_count=" .. #failures)
    print(PREFIX .. (#failures == 0 and "RESULT ALL PASS" or "RESULT " .. #failures .. " FAIL"))
    engine:Exit()
end
