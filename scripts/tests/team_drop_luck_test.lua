-- ============================================================================
-- 小队独立幸运值专项。官方 Runtime 入口，不访问玩家存档、不修改生产模块/配置。
-- 运行：tests/team_drop_luck_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- 以三份既有 Runtime 回归为起点：tri_clear_unlock / auto_decompose / equipment_preview。
-- 真配置、生成器、属性、掉落、Driver 与规则层均从资源缓存隔离编译；只替换数据/显示出口。
-- LSP、官方 build 和 Runtime 执行由主会话集中负责。
-- ============================================================================
local PREFIX = "[team_drop_luck] "
local assertions = 0
local failures = {} ---@type string[]
local sources = {} ---@type table<string, string>

local function check(ok, message)
    assertions = assertions + 1
    print(PREFIX .. (ok and "通过 " or "失败 ") .. message)
    if not ok then failures[#failures + 1] = message end
end
local function eq(actual, expected, message)
    check(actual == expected, message .. "（实际=" .. tostring(actual) .. "，期望=" .. tostring(expected) .. "）")
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        message .. "（实际=" .. tostring(actual) .. "，期望=" .. tostring(expected) .. "）")
end
---@param value any
---@return any
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {} ---@type table
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
---@param a any
---@param b any
---@return boolean
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, child in pairs(a) do if not equal(child, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function source(name)
    if sources[name] then return sources[name] end
    -- 只读资源，不能用沙箱 File 读用户档，也不能依赖运行机器安装 git。
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少真实源码 " .. name)
    local lines = {} ---@type string[]
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local text = table.concat(lines, "\n")
    sources[name] = text
    return text
end
---@param text string
---@param first string
---@param last string
---@return string
local function slice(text, first, last)
    local from = assert(text:find(first, 1, true), "真实源码缺少起始锚点 " .. first)
    local finish = assert(text:find(last, from + #first, true), "真实源码缺少结束锚点 " .. last)
    return text:sub(from, finish - 1)
end
---@param text string
---@param name string
---@param env table
---@return any
local function compile(text, name, env)
    return assert(load(text, "@幸运专项/" .. name, "t", env))()
end
local function noop() end

-- 私有 require/cache/math/time；项目依赖绝不写 package.loaded 或全局 require。
-- 未声明的依赖照常编译真实源码，不用全能 noop 把遗漏 API/守卫错误藏起来。
---@param data table|nil
---@return table
local function fixture(data)
    local records = data or {} ---@type table
    local modules = {} ---@type table<string, any>
    local env = setmetatable({}, { __index = _G }) ---@type table
    env._G = env
    env.math = copy(math)
    env.os = copy(os)
    env.os.time = function() return 1791200000 end
    env.time = { elapsedTime = 100 }
    env.package = { loaded = modules, preload = {}, path = "" }
    env.print = noop -- 大样本只关闭业务调试日志，断言与异常仍由入口输出/抛出。
    env.File = function() error("专项禁止读取/写入玩家文件") end
    env.fileSystem = { FileExists = function() error("专项禁止读取玩家存档") end }
    local wallet = { essence = 0 } ---@type table
    modules["core.GameState"] = {
        getEssence = function() return wallet.essence end,
        setEssence = function(value) wallet.essence = value end,
        getSweepTicket = function() return wallet.sweepTicket or 0 end,
        setSweepTicket = function(value) wallet.sweepTicket = value end,
        exportSave = function() return copy(records.currency or wallet) end,
        syncFromCurrency = function(value) wallet = copy(value) end,
    }
    modules["core.PlayerStore"] = { Get = function(key) return records[key] end, Subscribe = noop }
    modules["runtime.ClientDispatcher"] = { get = function(key) return records[key] end }
    modules["rules.character.PlayerDataManager"] = {
        GetModule = function(_, key) return records[key] end,
        MarkDirty = function(_, key)
            records._dirty = records._dirty or {}
            records._dirty[key] = (records._dirty[key] or 0) + 1
        end,
        FlushImmediate = function() error("专项禁止玩家存档写入") end,
    }
    modules["rules.task.TaskService"] = { UpdateProgress = noop }
    modules["shared.ModuleRegistry"] = { find = function() return nil end }
    modules["shared.schemas.CharacterSchema"] = { Fields = {} }
    modules["systems.GameSFX"] = { play = noop, playHit = noop, playHeroAttack = noop,
        playMonsterAttack = noop, playDeath = noop, playUI = noop }
    -- Driver测试只验战斗/掉落快照；战力显示出口不用UI库构树，也不替换业务模块。
    modules["ui.fx.SpinePowerUpEffect"] = { play = noop, playPowerUp = noop }
    -- Driver真实读取BattleScene首通账本，保留Scene业务，只隔离顶层加载的两个纯显示页。
    modules["ui.battle.stage.SweepDialog"] = { init = noop, draw = noop, drawButton = noop,
        handleInput = function() return false end, handleButtonInput = function() return false end }
    modules["ui.battle.popup.BattleResultPanel"] = { init = noop, draw = noop,
        isOpen = function() return false end, handleInput = noop }
    modules["ui.hud.popup.SettingsPanel"] = {
        isEffectsEnabled = function() return false end,
        isDamageTextEnabled = function() return true end,
        isBattleEffectsEnabled = function() return false end,
        getBattleEffects = function() return false end,
    }
    modules["ui.widget.SpeechBubble"] = { trigger = noop, reset = noop, update = noop }
    modules["ui.hud.BottomNav"] = { setSelectedIndex = noop, setAllLocked = noop }
    env.require = function(name)
        if modules[name] ~= nil then return modules[name] end
        local loaded = compile(source(name), name, env)
        assert(loaded ~= nil, "模块必须返回实例 " .. name)
        modules[name] = loaded
        return loaded
    end
    return { env = env, modules = modules, data = records, wallet = function() return wallet end,
        require = env.require }
end

-- 固定参考：git HEAD 372f4506a6f55342f28964b73ee60312e3c96c59 的 DropSystem。
-- 原文件从开头到 generateKillDrop 之前逐字摘录；只追加 return 导出，不改算法。
-- 内嵌而非运行时 git/dofile，旧 RNG 的整数区间形态与调用次数也可直接对照。
local LEGACY_DROP = [====[
------------------------------------------------------------------------
-- DropSystem.lua  —— 装备掉落系统
-- 职责: 击杀掉落概率判定、品质加权随机、首通奖励生成
-- 依赖: StageConfig, EquipmentSystem, MonsterConfig
------------------------------------------------------------------------
local EquipmentSystem = require("systems.EquipmentSystem")
local MC = require("config.MonsterConfig")
local StageConfig     = require("config.StageConfig")

local DropSystem = {}

--- 地狱难度击杀掉落：传说/至臻装备权重倍率（仅 rollKillDrop 生效，不影响首通 fcMinQ）
local HELL_EQUIP_WEIGHT_BOOST = {
    [5] = 3.0,
    [6] = 3.0,
}

------------------------------------------------------------------------
-- 内部工具
------------------------------------------------------------------------

--- 根据关卡品质权重表加权随机选取装备品质 (1-4)，用于首通奖励
---@param qw number[] 权重数组 {q1, q2, q3, q4}（来自 stageEntry.qw）
---@return number quality 1~4
local function rollQualityByStage(qw)
    local total = 0
    for i = 1, 4 do
        total = total + (qw[i] or 0)
    end
    if total <= 0 then return 1 end

    local r = math.random(1, total)
    local acc = 0
    for i = 1, 4 do
        acc = acc + (qw[i] or 0)
        if r <= acc then
            return i
        end
    end
    return 1  -- fallback
end

--- 根据怪物品质加权随机选取装备品质 (1-6)，用于击杀掉落
---@param monsterQuality number 怪物品质 1~6
---@param difficulty string|nil 关卡难度（地狱时提升 Q5/Q6 权重）
---@return number quality 1~6
local function rollQualityByMonster(monsterQuality, difficulty)
    local qualityData = MC.QUALITY[monsterQuality] or MC.QUALITY[1]
    local dw = qualityData.dropWeights
    local isHighDiff = difficulty == StageConfig.DIFFICULTY_HELL
        or difficulty == StageConfig.DIFFICULTY_PURGATORY
        or difficulty == StageConfig.DIFFICULTY_TORMENT
        or difficulty == StageConfig.DIFFICULTY_TORMENT2
        or difficulty == StageConfig.DIFFICULTY_TORMENT3
        or difficulty == StageConfig.DIFFICULTY_TORMENT4
        or difficulty == StageConfig.DIFFICULTY_TORMENT5
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION2
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION3
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION4
        or difficulty == StageConfig.DIFFICULTY_ANNIHILATION5
    local total = 0
    local weights = {}
    for i = 1, 6 do
        local w = dw[i] or 0
        if isHighDiff and HELL_EQUIP_WEIGHT_BOOST[i] then
            ---@diagnostic disable-next-line: assign-type-mismatch
            w = w * HELL_EQUIP_WEIGHT_BOOST[i]
        end
        weights[i] = w
        total = total + w
    end
    if total <= 0 then return 1 end

    local r = math.random(1, total)
    local acc = 0
    for i = 1, 6 do
        acc = acc + weights[i]
        if r <= acc then return i end
    end
    return 1
end

--- 从关卡怪物列表中随机抽取一个怪物品质（服务端自主决策）
--- 包含 Boss：Boss 参与品质池（权重等同 1 个普通怪位），使高难度关卡有机会掉落传说装备
---@param stageEntry StageEntry
---@return number monsterQuality 1~6
local function pickMonsterQuality(stageEntry)
    local monsters = stageEntry.monsters
    local pool = {}
    if monsters then
        for _, id in ipairs(monsters) do
            pool[#pool + 1] = id
        end
    end
    -- Boss 也加入品质池
    if stageEntry.bossId and stageEntry.bossId > 0 then
        pool[#pool + 1] = stageEntry.bossId
    end
    if #pool == 0 then return 1 end
    local monsterId = pool[math.random(1, #pool)]
    local template = MC.MONSTERS[monsterId]
    return template and template.quality or 1
end

------------------------------------------------------------------------
-- 公开 API
------------------------------------------------------------------------

--- 判定一次击杀是否掉落装备，装备品质由怪物品质决定
---@param stageEntry StageEntry 关卡配置条目
---@return number|nil quality 掉落装备品质 (1-5)，nil=未掉落
function DropSystem.rollKillDrop(stageEntry)
    local rate = stageEntry.dropRate or 0
    if rate <= 0 then
        return nil
    end

    local roll = math.random()
    if roll > rate then
        return nil
    end

    -- 命中掉落：服务端随机选取一个怪物品质，再按其权重决定装备品质
    local monsterQ = pickMonsterQuality(stageEntry)
    local difficulty = StageConfig.getDifficulty(stageEntry.id)
    local quality = rollQualityByMonster(monsterQ, difficulty)
    -- 品质上限：普通最高 4，困难 5，噩梦/地狱/炼狱/折磨(I/II/III) 6
    local maxQ = StageConfig.getMaxDropQuality(stageEntry)
    if quality > maxQ then quality = maxQ end
    print(string.format("[DropSystem] rollKillDrop: HIT roll=%.4f monsterQ=%d → equipQ=%d (cap=%d)", roll, monsterQ, quality, maxQ))
    return quality
end

]====]

local function testAttributes()
    local f = fixture()
    local AD, AF, ES, UA = f.require("systems.AttributeDef"), f.require("config.AffixConfig"),
        f.require("systems.EquipmentSystem"), f.require("systems.UnitAttributes")
    eq(AD.DROP_LUCK, "dropLuck", "幸运值使用独立 key")
    eq(AD.DROP_LUCK_CAP, 200, "本队有效幸运上限200")
    eq(AD.META[AD.DROP_LUCK].valueModel, 0, "幸运值不增加战斗价值")
    eq(AD.META[AD.DROP_LUCK].refineValueModel, 1, "洗练投入换算价值独立为1")
    eq(AD.META[AD.DROP_LUCK].default, 0, "旧英雄默认幸运值为0")
    eq(AD.META[AD.DROP_LUCK].dataType, AD.TYPE_FLOAT, "幸运值保留小数")
    eq(#AD.BASE_STATS, 6, "六围数量未增加")
    eq(AD.LUK, "luk", "命数 key 未更改")
    eq(AD.DERIVATIVES[AD.DROP_LUCK], nil, "幸运值没有战斗派生")
    eq(AF.BY_ID[5].key, AD.LUK, "既有 id5 仍然是命数")
    local tpl = assert(AF.BY_ID[45])
    eq(tpl.key, AD.DROP_LUCK, "真实普通词条 id45")
    eq(tpl.baseValue, 1, "幸运词条基础值1")
    eq(tpl.weight, 100, "幸运词条普通池权重100")
    eq(tpl.dataType, "float", "幸运词条不是整数或百分比类型")
    check(not AF.isCorruptAffix(45) and AF.BY_KEY[AD.DROP_LUCK] == tpl,
        "幸运只在普通池，不进入魔化映射")
    eq(AF.NORMAL_TO_CORRUPT_KEY[AD.DROP_LUCK], nil, "幸运不冒充最终命数")

    -- 不改池/权重，不直接构造生成结果：只把第一次 RNG 定在 id45 真实区间中点。
    local beforeWeight = 0
    for _, affix in ipairs(AF.AFFIXES) do
        if affix.id == 45 then break end
        beforeWeight = beforeWeight + affix.weight
    end
    local calls = 0
    f.env.math.random = function(...)
        eq(select("#", ...), 0, "普通词条生成保持浮点 RNG 入口")
        calls = calls + 1
        if calls == 1 then return (beforeWeight + tpl.weight * 0.5) / AF.TOTAL_WEIGHT end
        return 0.5
    end
    local generated = ES.rollAffixes(1, 5, 20, nil, 1.25, "twohand")
    eq(#generated, 1, "真实 ES.rollAffixes 生成一条")
    local lucky = assert(generated[1])
    eq(lucky.affixId, 45, "仅控制 RNG 即可生成幸运 id45")
    eq(lucky.key, AD.DROP_LUCK, "生成幸运词条带正确属性")
    local EC = f.require("config.EquipmentConfig")
    local tier = AF.QUALITY[lucky.quality]
    local expected = (tier.minMult + tier.maxMult) * 0.5 * (1 + 19 * EC.LEVEL_SCALE) * 1.25 * 2
    near(lucky.value, expected, "真实品质/等级/装备强度/双手倍率，float不取整")
    eq(calls, 3, "选普通词条、品质、数值各一次随机")

    local equip = { templateId = "C1", quality = 4, level = 20, baseStats = {},
        affixMult = "2", affixes = { copy(lucky) } } ---@type table
    equip.affixes[1].ascBonus = "0.75"
    ES.hydrate(equip)
    near(ES.effectiveAffixValue(equip, equip.affixes[1]), lucky.value * 2 + 0.75,
        "幸运普通词条吃栏位倍率，升阶固定投入不吃倍率")
    local baseline = UA.create({ str = 12, agi = 8, int = 7, vit = 10, luk = 9, spi = 6, maxHp = 100 })
    local dressed = baseline:clone()
    ES.applyToUnit(dressed, equip, 99001)
    near(dressed:get(AD.DROP_LUCK), expected * 2 + 0.75, "真实UA应用装备得到幸运值")
    for key in pairs(AD.META) do
        if key ~= AD.DROP_LUCK then near(dressed:get(key), baseline:get(key), "不改命数/战斗属性 " .. key) end
    end
    local cloned = dressed:clone()
    near(cloned:get(AD.DROP_LUCK), dressed:get(AD.DROP_LUCK), "UA clone包含幸运值")
    cloned:addModifier("临时幸运", { { key = AD.DROP_LUCK, flat = 100 } })
    near(dressed:get(AD.DROP_LUCK), expected * 2 + 0.75, "clone修改器与原属性独立")
    ES.removeFromUnit(cloned, 99001)
    near(cloned:get(AD.DROP_LUCK), 100, "clone移除装备只移除自身幸运词条")
    local original = copy(equip)
    local lean = ES.dehydrate(equip)
    check(equal(equip, original), "脱水不改原装备")
    eq(lean.affixes[1].key, nil, "脱水只保存稳定 id 不保存派生 key")
    eq(lean.affixes[1].affixId, 45, "脱水保存幸运 id45")
    near(lean.affixes[1].ascBonus, 0.75, "脱水保留固定升阶投入")
    local restored = ES.hydrate(cjson.decode(cjson.encode(lean)))
    near(ES.effectiveAffixValue(restored, restored.affixes[1]), expected * 2 + 0.75,
        "真实JSON脱水/水合往返保留幸运有效值")
    local old = ES.hydrate({ templateId = "C1", quality = 1, level = 1,
        affixes = { { affixId = "5", value = "3.25", ascBonus = "2", quality = 1 } } })
    eq(old.affixes[1].key, AD.LUK, "旧字符串 id5 水合仍是命数")
    near(old.affixes[1].value, 3.25, "旧命数数值不迁成幸运")
    near(old.affixes[1].ascBonus, 2, "旧档已有升阶投入不丢")
    local noLucky = baseline:clone()
    ES.applyToUnit(noLucky, old, 99002)
    eq(noLucky:get(AD.DROP_LUCK), 0, "旧档装备不凭空获得幸运值")
    local missing = ES.hydrate({ templateId = "C1", quality = 2, level = 3,
        affixes = { { affixId = "45", quality = 1 } } })
    eq(missing.affixes[1].key, AD.DROP_LUCK, "缺value的精简幸运档识别字符串id")
    near(missing.affixes[1].value, 1.1 * (1 + 2 * EC.LEVEL_SCALE) * EC.QUALITY[2].randomStrength,
        "缺value旧档沿用真实模板中点估值")

    local physical = { affixId = 16, key = AD.PHYS_ATK, ascBonus = 2, value = 5 } ---@type table
    local toLucky = { affixId = 45, key = AD.DROP_LUCK, value = 1 } ---@type table
    local physicalBefore = copy(physical)
    local luckyBonus = ES.convertAscBonusForRefine(physical, toLucky)
    near(luckyBonus, 1, "物攻2点升阶投入按0.5价值换为幸运1点")
    toLucky.ascBonus = luckyBonus
    near(ES.convertAscBonusForRefine(toLucky, physical), 2, "幸运投入反向换回物攻2点")
    near(ES.convertAscBonusForRefine(toLucky, { affixId = 45, key = AD.DROP_LUCK }), 1,
        "同幸运key换值保留原固定投入")
    check(equal(physical, physicalBefore), "真实洗练换算不修改旧词条/旧装备")
    for _ = 1, 50 do
        physical.ascBonus = ES.convertAscBonusForRefine(toLucky, physical)
        toLucky.ascBonus = ES.convertAscBonusForRefine(physical, toLucky)
    end
    near(toLucky.ascBonus, 1, "跨普通/幸运反复换算不增殖或丢投入")
    local oldBonus = ES.hydrate({ templateId = "W1", quality = 2, level = 10,
        affixMult = 2, affixes = { { affixId = 16, quality = 1, value = 5, ascBonus = 2 } } })
    near(ES.convertAscBonusForRefine(oldBonus.affixes[1], toLucky), 1,
        "旧装备水合后固定投入按真实价值转幸运，不按栏位倍率二次放大")

    -- 客户端详情已改为EquipmentPower.score委托，规则服务不再保留旧私有计价函数。
    -- 抽取真实委托函数，公共计价模块亦编译真实源码，不复刻旧公式。
    local detailText = slice(source("ui.character.equip.EquipmentDetail"),
        "local function calcEquipPower(", "local function replacementGain(")
    local powerEnv = setmetatable({ EquipmentPower = f.require("systems.EquipmentPower") }, { __index = f.env })
    local detailPower = compile(detailText .. "\nreturn calcEquipPower", "详情真实计价委托", powerEnv)
    local plain = copy(equip)
    plain.affixes = {}
    for _, id in ipairs({ 0, 1, 2, 4 }) do
        local hero = id > 0 and id or nil
        eq(detailPower(equip, hero), detailPower(plain, hero), "幸运不抬详情委托战力 英雄" .. id)
        eq(f.require("systems.EquipmentPower").score(equip, hero),
            f.require("systems.EquipmentPower").score(plain, hero), "幸运不抬公共装备计价 英雄" .. id)
    end
    local HC = f.require("config.HeroConfig")
    local heroData = { heroes = { deployed = { 1 }, roster = { [1] = { level = 10 } } },
        equipment = { inventory = {}, equipped = { ["1"] = { accessory = 99001 } } } } ---@type table
    local items = heroData.equipment.inventory
    items["99001"] = { templateId = "C1", quality = 1, level = 1, baseStats = {},
        affixMult = 3, affixes = { { affixId = 45, key = AD.DROP_LUCK, value = 100, ascBonus = 5 } } }
    local teams = { { slots = { { state = "occupied", heroId = 1 } } }, { slots = {} }, { slots = {} } }
    local values = { ownedSet = { [1] = { level = 10 } }, teams = teams } ---@type table
    local getter = { get = function(key) return heroData[key] end, Get = function(key) return heroData[key] end }
    local power = f.require("ui.character.panel.CharacterPower").bind({ AD = AD, HC = HC,
        ClientDispatcher = getter, PlayerStore = getter, EquipmentSystem = ES, EquipmentConfig = EC,
        ArtifactBridge = f.require("systems.ArtifactBridge"), AwakeningConfig = f.require("config.AwakeningConfig"),
        MAX_SLOTS = 4, TEAM_COUNT = 3, get = function(key) return values[key] end, set = noop })
    local luckyPower = power.calcHeroPower(1, 1, 1)
    items["99001"].affixes = {}
    eq(power.calcHeroPower(1, 1, 1), luckyPower, "真实CharacterPower完整英雄战力不计幸运值/固定投入")
end

local function testLuckBoundaries()
    local f = fixture()
    local D, UA, AD = f.require("systems.DropSystem"), f.require("systems.UnitAttributes"), f.require("systems.AttributeDef")
    for _, value in ipairs({ -1, -math.huge, math.huge, 0 / 0, "100", "非法", false, {} }) do
        eq(D.normalizeLuck(value), 0, "非法/负幸运归零 " .. tostring(value))
    end
    eq(D.normalizeLuck(nil), 0, "缺幸运归零")
    near(D.normalizeLuck(0.25), 0.25, "小数幸运不取整")
    eq(D.normalizeLuck(1000000), 200, "单值按本队上限钳制")
    local a = { heroId = 1, hp = 0, attrs = UA.create({ dropLuck = 999 }),
        _baseSnapshot = UA.create({ dropLuck = 20.5 }) } ---@type table
    local allies = { a, { heroId = "1", attrs = UA.create({ dropLuck = 100 }) },
        { heroId = 2, hp = 0, attrs = UA.create({ dropLuck = 30 }) },
        { monsterId = 10, attrs = UA.create({ dropLuck = 200 }) },
        { attrs = UA.create({ dropLuck = 200 }), isSummon = true },
        { heroId = 0, attrs = UA.create({ dropLuck = 200 }) },
        { heroId = 3, attrs = UA.create({ dropLuck = -10 }) }, { heroId = 4 } }
    near(D.captureTeamLuck(allies), 50.5, "真实capture优先基线、数字/字符串id去重、阵亡仍计、非英雄忽略")
    near(a._baseSnapshot:get(AD.DROP_LUCK), 20.5, "capture只读基线不改快照")
    eq(D.captureTeamLuck(nil), 0, "空队兼容")
    eq(D.captureTeamLuck({ { heroId = 1, attrs = UA.create({ dropLuck = 150 }) },
        { heroId = 2, attrs = UA.create({ dropLuck = 150 }) } }), 200, "两人150合计按队封顶200")
    local SC = f.require("config.StageConfig")
    local stage = copy(assert(SC.getStage(105)))
    stage.dropRate = 0.1
    local calls = 0
    local roll = 0.15
    f.env.math.random = function(minimum, maximum)
        calls = calls + 1
        if minimum then return minimum end
        return roll
    end
    eq(D.rollKillDrop(stage), nil, "旧10%在15%分位不掉落")
    check(D.rollKillDrop(stage, { teamIdx = 2, dropLuck = 100 }) ~= nil, "100幸运使10%相对提升到20%，15%命中")
    roll = 0.200001
    eq(D.rollKillDrop(stage, { teamIdx = 2, dropLuck = 100 }), nil, "20%以上未命中，不是增加100个百分点")
    roll = 0.2
    check(D.rollKillDrop(stage, { teamIdx = 2, dropLuck = 100 }) ~= nil, "20%边界保留<=语义")
    roll = 0.299999
    check(D.rollKillDrop(stage, { teamIdx = 1, dropLuck = 200 }) ~= nil, "200幸运使10%升到30%")
    roll = 0.300001
    eq(D.rollKillDrop(stage, { teamIdx = 3, dropLuck = 99999 }), nil, "超上限幸运不突破30%")
    stage.dropRate = 0.5
    roll = 0.999999
    check(D.rollKillDrop(stage, { teamIdx = 3, dropLuck = 200 }) ~= nil, "高基础掉率乘算封顶100%")
    stage.dropRate, roll = 0.1, 0.15
    for _, ctx in ipairs({ {}, { dropLuck = 200 }, { teamIdx = 0, dropLuck = 200 },
        { teamIdx = 4, dropLuck = 200 }, { teamIdx = 1.5, dropLuck = 200 },
        { teamIdx = "2", dropLuck = 200 }, { teamIdx = math.huge, dropLuck = 200 },
        { teamIdx = 0 / 0, dropLuck = 200 }, { teamIdx = 1, dropLuck = "200" },
        { teamIdx = 1, dropLuck = -20 }, { teamIdx = 1, dropLuck = math.huge },
        { teamIdx = 1, dropLuck = 0 / 0 }, true, "非法上下文", 2 }) do
        eq(D.rollKillDrop(stage, ctx), nil, "无效context不误启幸运 " .. tostring(ctx))
    end
    for _, mode in ipairs({ "resource_dungeon", "terminal" }) do
        stage.mode = mode
        eq(D.rollKillDrop(stage, { teamIdx = 1, dropLuck = 200 }), nil, mode .. "即使非零dropRate也不启幸运")
    end
    stage.mode = nil
    for _, rate in ipairs({ 0, -1 }) do
        stage.dropRate, calls = rate, 0
        eq(D.rollKillDrop(stage, { teamIdx = 1, dropLuck = 200 }), nil, "非正掉率直接返回")
        eq(calls, 0, "非正掉率不消耗任何 RNG")
    end
    local terminal = assert(SC.getStage(SC.TERMINAL_NORMAL))
    calls = 0
    eq(D.rollKillDrop(terminal, { teamIdx = 2, dropLuck = 200 }), nil, "真实终焉配置零掉率")
    eq(calls, 0, "真实终焉零掉率不消耗 RNG")
end

local function testZeroLuckReplay()
    local f = fixture()
    local D, SC = f.require("systems.DropSystem"), f.require("config.StageConfig")
    local old = compile(LEGACY_DROP .. "\nreturn DropSystem", "固定旧DropSystem", f.env)
    local nativeRandom = math.random
    local function replay(seed, legacy, stage, context)
        math.randomseed(seed, 20261005)
        local trace, outcomes = {}, {} ---@type string[], string[]
        f.env.math.random = function(...)
            local args = table.pack(...)
            trace[#trace + 1] = tostring(args.n) .. ":" .. tostring(args[1]) .. ":" .. tostring(args[2])
            return nativeRandom(...)
        end
        local module = legacy and old or D
        for _ = 1, 32 do outcomes[#outcomes + 1] = tostring(module.rollKillDrop(stage, context)) end
        return table.concat(outcomes, ","), table.concat(trace, "|"), nativeRandom()
    end
    for _, id in ipairs({ 101, 105, 2405, 4701, 4705, 7005, 9305, 11605, 18505, 23105, 32305, 34505, 999 }) do
        local stage = assert(SC.getStage(id))
        local sameResults, sameShape, sameTail = true, true, true
        for seed = 1, 64 do
            local expected, trace, tail = replay(seed, true, stage)
            for _, context in ipairs({ {}, { teamIdx = 1, dropLuck = 0 }, { teamIdx = 2, dropLuck = 0 },
                { teamIdx = 3, dropLuck = -5 }, { teamIdx = 0, dropLuck = 200 } }) do
                local actual, actualTrace, actualTail = replay(seed, false, stage, context)
                sameResults = sameResults and actual == expected
                sameShape = sameShape and actualTrace == trace
                sameTail = sameTail and actualTail == tail
            end
            local actual, actualTrace, actualTail = replay(seed, false, stage)
            sameResults = sameResults and actual == expected
            sameShape = sameShape and actualTrace == trace
            sameTail = sameTail and actualTail == tail
        end
        local raw = D.getStageQualityProbabilities(stage, 0, true)
        if raw[6] >= D.MIN_RED_PROBABILITY or (stage.dropRate or 0) <= 0 then
            check(sameResults, "已有高红率/无掉落零幸运与旧参考逐种子同结果 stage=" .. id)
            check(sameShape, "已有高红率/无掉落保留旧 RNG 形态 stage=" .. id)
            check(sameTail, "已有高红率/无掉落最终随机状态不漂移 stage=" .. id)
        else
            -- 早期品质骰需从千分整数改为浮点才能表达万分之一；不可再要求旧品质/随机尾同值。
            eq(raw[6], 0, "低红率基线仍按旧cap为零 stage=" .. id)
            near(D.getStageQualityProbabilities(stage)[6], 0.0001, "仅新增极小至臻尾 stage=" .. id)
        end
    end
end

local function testQualityDistribution()
    local f = fixture()
    local D, MC, SC = f.require("systems.DropSystem"), f.require("config.MonsterConfig"), f.require("config.StageConfig")
    local monsterIds = {} ---@type table<number, number>
    for id, monster in pairs(MC.MONSTERS) do
        if not monsterIds[monster.quality] or id < monsterIds[monster.quality] then monsterIds[monster.quality] = id end
    end
    local quantile = 0.5
    local floatCalls = 0
    f.env.math.random = function(minimum, maximum)
        if minimum then
            if maximum == 1 then return 1 end
            return math.min(maximum or minimum, minimum + math.floor(quantile * ((maximum or minimum) - minimum + 1)))
        end
        floatCalls = floatCalls + 1
        return floatCalls % 2 == 1 and 0 or quantile
    end
    -- 验收公式只计算期望概率，不替换真实掉落函数、真实怪物池或品质选择器。
    local function expectedWeights(monsterQ, luck, high)
        local weights, total = {}, 0
        for q = 1, 6 do
            local weight = MC.QUALITY[monsterQ].dropWeights[q] or 0
            if high and q >= 5 then weight = weight * 3 end
            local modified = weight * (1 + (q - 1) * luck / 500)
            weights[q] = modified
            total = total + modified
        end
        return weights, total
    end
    local function draw(stage, luck, t)
        quantile, floatCalls = t, 0
        return assert(D.rollKillDrop(stage, { teamIdx = 2, dropLuck = luck }))
    end
    for monsterQ = 1, 6 do
        local stage = copy(assert(SC.getStage(7005)))
        stage.monsters, stage.bossId, stage.dropRate = { assert(monsterIds[monsterQ]) }, 0, 1
        local monotone, zeroClosed = true, true
        for _, luck in ipairs({ 0, 1, 50, 100, 200 }) do
            local counts = { 0, 0, 0, 0, 0, 0 }
            local weights, total = expectedWeights(monsterQ, luck, true)
            for i = 1, 2048 do
                local t = (i - 0.5) / 2048
                local actual = draw(stage, luck, t)
                counts[actual] = counts[actual] + 1
                if actual ~= 6 and (MC.QUALITY[monsterQ].dropWeights[actual] or 0) <= 0 then zeroClosed = false end
                if luck > 0 and actual < draw(stage, 0, t) then monotone = false end
            end
            for q = 1, 6 do
                check(math.abs(counts[q] / 2048 - weights[q] / total) <= 2 / 2048,
                    "真实分位网格Q" .. q .. "分布符合原权重×幸运×旧高难3倍 怪Q" .. monsterQ .. " 幸运" .. luck)
            end
        end
        check(monotone, "同分位幸运增加不降低品质，怪Q" .. monsterQ)
        check(zeroClosed, "除至臻微小尾外，幸运不开放原0权重品质，怪Q" .. monsterQ)
        -- 零分位特别覆盖 Q5/Q6 怪物的前导0，不把浮点0误判为Q1。
        local weights = expectedWeights(monsterQ, 200, true)
        local first = 1
        for q = 1, 6 do if weights[q] > 0 then first = q break end end
        eq(draw(stage, 200, 0), first, "浮点零分位跳过前导0权重，怪Q" .. monsterQ)
    end
    for _, entry in ipairs({ { 105, 4 }, { 2405, 5 }, { 4705, 6 }, { 7005, 6 }, { 9305, 6 } }) do
        local stage = copy(assert(SC.getStage(entry[1])))
        stage.monsters, stage.bossId, stage.dropRate = { assert(monsterIds[6]) }, 0, 1
        eq(draw(stage, 200, 0.999999), 6, "所有难度极小至臻机会，不改通用cap stage=" .. entry[1])
        eq(SC.getMaxDropQuality(stage), entry[2], "普通/困难非至臻及点金上限未解除 stage=" .. entry[1])
    end
    -- 所有既有高难分支继续保持 Q5/Q6 的三倍权重，不只检查地狱一档。
    for _, id in ipairs({ 7005, 9305, 11605, 13905, 16205, 18505, 20805, 23105, 25405, 27705, 30005, 32305 }) do
        local stage = copy(assert(SC.getStage(id)))
        stage.monsters, stage.bossId, stage.dropRate = { assert(monsterIds[5]) }, 0, 1
        local weights, total = expectedWeights(5, 100, true)
        local acc = 0
        for q = 1, 6 do
            if weights[q] > 0 then
                eq(draw(stage, 100, (acc + weights[q] * 0.5) / total), q,
                    "高难旧3倍权重与幸运乘算共存 stage=" .. id .. " Q" .. q)
            end
            acc = acc + weights[q]
        end
    end
    -- 独立确定性尾部边界，不依赖大样本碰运气；每件只沿既有品质骰。
    for _, stageId in ipairs({ 101, 105, 2401, 4701, 7001 }) do
        local stage = copy(assert(SC.getStage(stageId)))
        stage.dropRate = 1
        local probabilities = D.getStageQualityProbabilities(stage)
        near(probabilities[6], 0.0001, "无红来源的每件概率恰为万分之一 stage=" .. stageId)
        eq(draw(stage, 0, 0.99995), 6, "零幸运尾区也可出红 stage=" .. stageId)
        check(draw(stage, 0, 0.9998) ~= 6, "尾区外不凭空保底红 stage=" .. stageId)
        quantile, floatCalls = 0.99995, 0
        D.rollKillDrop(stage, { teamIdx = 1, dropLuck = 0 })
        eq(floatCalls, 2, "只原掉落骰+品质骰，无额外红装骰 stage=" .. stageId)
    end
    local early = copy(assert(SC.getStage(101)))
    early.dropRate = 0.05
    quantile, floatCalls = 0.99995, 0
    f.env.math.random = function(lower)
        if lower then return lower end
        floatCalls = floatCalls + 1
        return floatCalls == 1 and 0.051 or 0.99995
    end
    eq(D.rollKillDrop(early), nil, "极小红尾不提高原掉装备概率")
    eq(floatCalls, 1, "未命中不骰品质/红尾")
    f.env.math.random = function(lower, upper)
        if lower then return lower end
        return 0.99995
    end
    local firstClear = D.generateFirstClearEquips(SC.getStage(101))
    eq(firstClear[1].quality, 6, "真实首通四档qw随机也有红尾")
    eq(firstClear[1].level, 1, "前期红装沿原等级不是高等级模板奖励")
    check(firstClear[1].secondaryRoll ~= nil and #firstClear[1].affixes == 2,
        "前期红装正常生成副属性与至臻词缀")
end

-- 真实 StandaloneBoot 的 applyKillDrop 和三队 wrapper；没有复制分发/分解算法。
---@param f table
---@return table
local function bootDropFixture(f)
    local env = setmetatable({}, { __index = f.env }) ---@type table
    env.StageConfig, env.DropSystem = f.require("config.StageConfig"), f.require("systems.DropSystem")
    env.BlacksmithConfig, env.LootBoxSystem = f.require("config.BlacksmithConfig"), f.require("systems.LootBoxSystem")
    env.ClientDispatcher, env.PlayerStore = f.modules["runtime.ClientDispatcher"], f.modules["core.PlayerStore"]
    env.GameState = f.modules["core.GameState"]
    env.pendingFcSeeds, env.pendingFcScrolls = {}, {}
    local handlers = {} ---@type table
    local updates = 0
    env.LootBox = { updateSeedData = function() updates = updates + 1 end, addSeedHint = noop }
    env.BattleScene = { setOnEnemyDrop = function(callback) handlers.single = callback end }
    env.BattleTriPage = { setOnDrop = function(callback) handlers.tri = callback end }
    local text = slice(source("boot.StandaloneBoot"), "    local function addKillEquipment(",
        "    BattleTriPage.setOnStageClear(")
    compile(text, "Boot真实掉落与wrapper", env)
    assert(type(handlers.single) == "function" and type(handlers.tri) == "function", "真实Boot回调未注册")
    return { env = env, handlers = handlers, updates = function() return updates end }
end

local function testBootBranches()
    local f = fixture({ equipment = { settings = {}, inventory = {}, equipped = {}, nextSeq = 1 }, lootbox = { seeds = {} } })
    local b = bootDropFixture(f)
    local SC, BC, LBS = f.require("config.StageConfig"), f.require("config.BlacksmithConfig"), f.require("systems.LootBoxSystem")
    local stage = assert(SC.getStage(105))
    local rate = stage.dropRate
    check(rate > 0 and rate < 0.5, "Boot真实关卡适合相对概率夹具")
    f.env.math.random = function(minimum) if minimum then return minimum end return rate * 1.5 end
    b.handlers.tri({ stageId = 105, teamIdx = 2, dropLuck = 0, dropOnly = true })
    eq(#b.env.pendingFcSeeds, 0, "真实Boot wrapper零幸运未命中")
    b.handlers.tri({ stageId = 105, teamIdx = 2, dropLuck = 100, dropOnly = true })
    eq(#b.env.pendingFcSeeds, 1, "真实Boot dropOnly wrapper保留teamIdx/dropLuck，新增命中进首通暂存")
    eq(#f.data.lootbox.seeds, 0, "dropOnly暂存不提前进遗匣")
    eq(f.wallet().essence, 0, "dropOnly暂存不提前自动分解")
    local quality = b.env.pendingFcSeeds[1].quality
    f.data.equipment.settings = { autoQuality = 6, autoLevel = 0 }
    b.handlers.tri({ stageId = 105, teamIdx = 3, dropLuck = 100 })
    local essence = BC.calcAutoDecomposeEssence(quality, stage.monsterLevel)
    eq(f.wallet().essence, essence, "真实Boot非dropOnly保留队上下文且走真实自动分解精粹")
    eq(#f.data.lootbox.seeds, 0, "自动分解不同时入遗匣")
    eq(f.data.lootbox.autoDecomposeNotice.count, 1, "真实自动分解notice累计一次")
    eq(f.data.lootbox.autoDecomposeNotice.essence, essence, "notice记录实际精粹")
    f.data.equipment.settings = { autoQuality = 0, autoLevel = 0 }
    b.handlers.tri({ stageId = 105, teamIdx = 1, dropLuck = 100 })
    eq(LBS.getTotalCount(f.data.lootbox), 1, "真实保留分支入遗匣一件")
    check(f.data.lootbox.seeds[1].equip ~= nil, "真实LootBoxSystem立即生成确定装备，而非mock种子")
    eq(f.wallet().essence, essence, "保留分支不额外发精粹")
    local before = #b.env.pendingFcSeeds
    b.handlers.single({ stageId = 105, teamIdx = 1, dropLuck = 100, isFirstClear = true })
    eq(#b.env.pendingFcSeeds, before + 1, "单线真实Boot入口也继续传队1幸运")
    local missingBefore = #b.env.pendingFcSeeds
    b.handlers.single({ stageId = 105, dropLuck = 200, isFirstClear = true })
    eq(#b.env.pendingFcSeeds, missingBefore, "没有明确队号的旧入口不误启幸运")
    check(b.updates() >= 2, "自动分解/保留均调用现有UI刷新出口")
end

local function testDriverSnapshots()
    local f = fixture({ equipment = { settings = {}, inventory = {}, equipped = {}, nextSeq = 1 }, lootbox = { seeds = {} } })
    local AD, HC, ES = f.require("systems.AttributeDef"), f.require("config.HeroConfig"), f.require("systems.EquipmentSystem")
    local Reset = f.require("ui.battle.scene.BattleAllyReset")
    local values = { [1] = { 60, 40 }, [2] = { 30 }, [3] = { 150, 100 } } ---@type table<number, number[]>
    local signatures = { "队1-A", "队2-A", "队3-A" }
    local reads = {} ---@type number[]
    local function allies(team)
        reads[#reads + 1] = team
        local result = {} ---@type table[]
        for i, luck in ipairs(values[team]) do
            local hero = assert(HC.createHero(i, 10))
            ES.applyToUnit(hero.attrs, { baseStats = {}, affixes = {
                { affixId = 45, key = AD.DROP_LUCK, value = luck } } }, 80000 + i)
            Reset.createSnapshot(hero)
            hero.attrs:addModifier("战中临时幸运", { { key = AD.DROP_LUCK, flat = 900 } })
            result[#result + 1] = hero
        end
        return result
    end
    f.modules["ui.character.panel.CharacterPanel"] = {
        getTeamSignature = function(team) return signatures[team] end,
        getDeployedTeam = allies,
    }
    local Driver = f.require("ui.battle.tri.BattleTriDriver")
    local drivers = {} ---@type table<number, table>
    local emitted = {} ---@type table[]
    local b = bootDropFixture(f)
    local SC = f.require("config.StageConfig")
    local rate = SC.getStage(105).dropRate
    for team = 1, 3 do
        local driver = Driver.new(team)
        driver.onDrop = function(data)
            emitted[#emitted + 1] = copy(data)
            b.handlers.tri(data)
        end
        driver:start(105)
        drivers[team] = driver
    end
    eq(table.concat(reads, ","), "1,2,3", "真实Driver.start只读取本队来源，不借活动编辑队")
    eq(drivers[1].dropLuck, 100, "队1本场快照=60+40")
    eq(drivers[2].dropLuck, 30, "队2不借队1幸运")
    eq(drivers[3].dropLuck, 200, "队3本队合计封顶")
    check(drivers[1].talRefs ~= drivers[2].talRefs and drivers[1].combatState ~= drivers[3].combatState,
        "真实多实例战斗状态与快照独立")
    local kills = {} ---@type table[]
    drivers[1].onKill = function(data) kills[#kills + 1] = data end
    local dead = drivers[1].allies[1]
    dead.hp, dead.attrs.final[AD.HP] = 0, 0
    dead.attrs:setBase(AD.DROP_LUCK, 0)
    values[1], signatures[1] = { 5 }, "队1-B"
    drivers[1]:reportKill({ expReward = 7, goldReward = 11 })
    eq(drivers[1].pendingKills[1].dropLuck, 100, "阵亡/换装后reportKill仍记录开战100")
    eq(drivers[1].pendingKills[1].teamIdx, 1, "pending记录真实队号")
    eq(#emitted, 0, "击杀只入pending不提前抽奖")
    drivers[2]:reportKill({ expReward = 3, goldReward = 5 })
    drivers[3]:reportKill({ expReward = 2, goldReward = 4 })
    -- 重开会先把旧pending入队，再读取新的本队装备；旧队列不可改为5幸运。
    drivers[1]:start(105)
    eq(drivers[1].dropLuck, 5, "真实重开刷新本队幸运")
    eq(drivers[1].rewardQueue[1].dropLuck, 100, "重开保留旧击杀快照100在延迟队列")
    eq(drivers[1].rewardQueue[1].teamIdx, 1, "重开旧队列不串队号")
    eq(kills[1].expReward, 7, "旧pending经验批结不受幸运干扰")
    eq(kills[1].goldReward, 11, "旧pending金币批结不受幸运干扰")
    eq(kills[1].allyCount, 1, "经验存活人数不等于幸运贡献人数")
    drivers[2]:queuePendingKills()
    drivers[3]:queuePendingKills()
    eq(drivers[2].rewardQueue[1].dropLuck, 30, "队2延迟队列保留30")
    eq(drivers[3].rewardQueue[1].dropLuck, 200, "队3延迟队列保留200")
    f.env.math.random = function(minimum) if minimum then return minimum end return rate * 1.5 end
    drivers[1]:tickRewards(0.049)
    eq(#emitted, 0, "真实领奖节流0.049秒不出队")
    drivers[1]:tickRewards(0.002)
    eq(#emitted, 1, "跨0.05秒真实onDrop出队一次")
    eq(emitted[1].dropLuck, 100, "onDrop继续转发旧场幸运100而非新场5")
    eq(#b.env.pendingFcSeeds, 1, "实际Driver→queue→Boot wrapper→真实掉落命中旧场幸运")
    drivers[2]:tickRewards(0.06)
    eq(#b.env.pendingFcSeeds, 1, "队2幸运30在1.5倍分位未命中，不借队1旧场100")
    drivers[3]:tickRewards(0.06)
    eq(#b.env.pendingFcSeeds, 2, "队3幸运200独立命中")
    eq(#emitted, 3, "三队旧队列各派发一份")
    drivers[1]:tickRewards(1)
    eq(#emitted, 3, "已清空队列不重复派发")
    drivers[1]:reportKill({ expReward = 0, goldReward = 0 })
    drivers[1]:queuePendingKills()
    drivers[1]:tickRewards(0.06)
    eq(emitted[4].dropLuck, 5, "新场击杀改用5幸运")
    eq(#b.env.pendingFcSeeds, 2, "新场5幸运不追用旧场命中概率")

    -- 用真实update的15帧签名检查触发重开，不替换driver.start或更新算法。
    values[2], signatures[2] = { 80 }, "队2-B"
    for _ = 1, 15 do drivers[2]:update(0) end
    eq(drivers[2].dropLuck, 80, "真实签名变化重开更新队2幸运")
    eq(drivers[1].dropLuck, 5, "队2签名变化不刷新队1")
    eq(drivers[3].dropLuck, 200, "队2签名变化不刷新队3")
    drivers[2].enemies[1].hp = 0
    drivers[2].enemies[1].attrs.final[AD.HP] = 0
    drivers[2]:reportDefeatedEnemies()
    drivers[2]:reportDefeatedEnemies()
    eq(#drivers[2].pendingKills, 1, "真实死亡扫描幂等，幸运击杀只记一次")
    eq(drivers[2].pendingKills[1].dropLuck, 80, "真实死亡扫描使用新场80")
end

local function testSingleLineSnapshot()
    local f = fixture()
    local AD, HC, ES, Reset = f.require("systems.AttributeDef"), f.require("config.HeroConfig"),
        f.require("systems.EquipmentSystem"), f.require("ui.battle.scene.BattleAllyReset")
    local ally = assert(HC.createHero(1, 10))
    ES.applyToUnit(ally.attrs, { baseStats = {}, affixes = { { affixId = 45, key = AD.DROP_LUCK, value = 100 } } }, 90001)
    Reset.createSnapshot(ally)
    ally.attrs:addModifier("临时", { { key = AD.DROP_LUCK, flat = 900 } })
    local flowCalls = 0
    local env = setmetatable({ allies = { ally }, enemies = {}, DropSystem = f.require("systems.DropSystem"),
        BattleStageFlow = { startBattleTalents = function() flowCalls = flowCalls + 1 end } }, { __index = f.env })
    local text = slice(source("ui.battle.scene.BattleScene"), "local function captureDropLuck()", "--- 恢复主战斗")
    local capture = compile("local dropLuck_ = 0\n" .. text
        .. "\nreturn { start = startBattleTalents, capture = captureDropLuck, get = function() return dropLuck_ end }", "Scene正式幸运捕获", env)
    capture.start()
    eq(capture.get(), 100, "保留单线真实开战入口优先_baseSnapshot捕获幸运")
    eq(flowCalls, 1, "捕获后继续进入既有战斗天赋流程")
    ally.hp, ally.attrs.final[AD.HP] = 0, 0
    ally._baseSnapshot:setBase(AD.DROP_LUCK, 1)
    local got = {} ---@type table[]
    local enemy = f.require("config.MonsterConfig").createMonster(1, 1)
    enemy.hp, enemy.attrs.final[AD.HP] = 0, 0
    local liveEnemy = f.require("config.MonsterConfig").createMonster(1, 1)
    local ctx = { allies = { ally, assert(HC.createHero(2, 10)) }, enemies = { enemy, liveEnemy }, enemyQueue = {},
        dropLuck = capture.get(), currentStageId = 105, stageName = "单线快照测试", isFirstClear = false,
        getCardCX = function() return 100 end, getAliveUnits = function(units)
            local alive = {} ---@type table[]
            for _, unit in ipairs(units) do if unit.hp > 0 then alive[#alive + 1] = unit end end
            return alive
        end, syncUnitHp = noop, RESPAWN_DELAY = 1, reinforceCdByList = {}, ENEMY_CARD_CY = 180,
        ALLY_CARD_CY = 180, waveKillCount = 0, waveGoldEarned = 0, waveExpEarned = 0,
        getStageConfig = function() return f.require("config.StageConfig") end,
        onEnemyDropCallback = function(data) got[#got + 1] = data end }
    local Casualty = f.require("ui.battle.combat.BattleCasualty")
    Casualty.process(ctx, 0.01)
    eq(#got, 1, "真实单线死亡补位发出掉落回调")
    eq(got[1].teamIdx, 1, "单线明确转发队1")
    eq(got[1].dropLuck, 100, "单线死亡/换装不重新采集，仍转发ctx固定幸运100")
    Casualty.process(ctx, 0.01)
    eq(#got, 1, "单线死亡掉落不重复")
    local second = f.require("config.MonsterConfig").createMonster(1, 1)
    second.hp, second.attrs.final[AD.HP] = 0, 0
    ctx.enemies, ctx.dropLuck = { second, liveEnemy }, nil
    Casualty.process(ctx, 0.01)
    eq(got[2].dropLuck, 0, "单线旧ctx缺本场快照兼容归零，不读取当前配装")

    -- 真实同关寻怪完成分支：pending配装先由refresh提交，再restore，最后捕获新波幸运。
    local order = {} ---@type string[]
    env.allies = { ally }
    local combat = f.require("ui.battle.combat.BattleCombat")
    local phasesCtx = { searchingTimer = 0, SEARCH_ENEMY_DURATION = 1, isFirstClear = false,
        currentStageId = 105, maxStageId_ = 105, battleActive = false, enemies = {}, enemyQueue = {},
        allies = env.allies, clearedStages = {}, regenAccum = 0,
        updateCardAnims = combat.updateCardAnims, updateFloatingTexts = combat.updateFloatingTexts,
        updateHitFlashes = combat.updateHitFlashes, updateComboQueue = combat.updateComboQueue,
        getStageConfig = ctx.getStageConfig, BattleScene = { refreshAllyStats = function()
            order[#order + 1] = "提交配装"
            -- 配装刷新从干净英雄重建，不能clone含旧装备100的基线再加35基础值。
            local rebuilt = assert(HC.createHero(1, 10))
            ES.applyToUnit(rebuilt.attrs, { baseStats = {}, affixes = {
                { affixId = 45, key = AD.DROP_LUCK, value = 35 } } }, 90001)
            ally._pendingSnapshot = rebuilt.attrs:clone()
            eq(ally._pendingSnapshot:get(AD.DROP_LUCK), 35, "待提交新配装getter精确35，不残留旧装备幸运100")
        end }, resetAllyUnit = function(unit)
            order[#order + 1] = "恢复快照"
            Reset.resetAllyUnit(unit, env.allies, noop)
        end, captureDropLuck = function()
            order[#order + 1] = "捕获幸运"
            capture.capture()
        end, generateIdleEnemyList = function()
            return { f.require("config.MonsterConfig").createMonster(1, 1) }, 1
        end, assignEnemiesToField = f.require("ui.battle.stage.BattleEnemySpawn").assignEnemiesToField }
    local Phases = f.require("ui.battle.scene.BattleScenePhases")
    check(Phases.process(phasesCtx, 0.5), "真实寻怪中途属于前置阶段")
    eq(capture.get(), 100, "寻怪未结束不提前刷新本场幸运")
    check(Phases.process(phasesCtx, 0.6), "真实同关寻怪完成分支执行")
    eq(table.concat(order, ","), "提交配装,恢复快照,捕获幸运", "新波提交/restore/capture时序正确")
    eq(capture.get(), 35, "真实Phases新波读取已提交pending装备幸运35")
    eq(flowCalls, 1, "寻怪只捕获快照，不重复调用startBattleTalents wrapper")
    check(phasesCtx.battleActive and phasesCtx.searchingTimer == nil, "新波恢复战斗active且结束寻怪")
    eq(#phasesCtx.enemies, 1, "新波继续使用真实assignEnemiesToField")
    ally.attrs:setBase(AD.DROP_LUCK, 999)
    eq(capture.get(), 35, "新波战中属性再改变不追溯幸运快照")
end

local function testExcludedRewardPaths()
    local f = fixture({ currency = { sweepTicket = 20, gold = 0 },
        battle = { currentStageId = 4705, maxStageId = 4705, clearedStages = { ["4705"] = true } },
        heroes = { roster = { [1] = { level = 70, exp = 0 } }, deployed = { 1 },
            teams = { { slots = { 1, 0, 0, 0 } }, { slots = {} }, { slots = {} } } },
        equipment = { inventory = {}, equipped = {}, settings = {}, nextSeq = 1 }, player = {}, lootbox = { seeds = {} } })
    local D, O, SC = f.require("systems.DropSystem"), f.require("systems.OfflineCalc"), f.require("config.StageConfig")
    local nativeRandom = math.random
    local function seeded(seed, fn)
        math.randomseed(seed, 20261005)
        local trace = {} ---@type string[]
        f.env.math.random = function(...)
            local args = table.pack(...)
            trace[#trace + 1] = tostring(args.n) .. ":" .. tostring(args[1]) .. ":" .. tostring(args[2])
            return nativeRandom(...)
        end
        local result = fn()
        return result, table.concat(trace, "|"), nativeRandom()
    end
    local plainStage = copy(assert(SC.getStage(4705)))
    local luckyStage = copy(plainStage)
    luckyStage.dropLuck, luckyStage.teamIdx = 200, 1
    for _, mode in ipairs({ "离线", "种子", "在线挂机", "首通", "卷轴", "扫荡券" }) do
        local function compute(stage)
            if mode == "离线" then return O.calcRewardsFromKills(21, stage, 1, SC) end
            if mode == "种子" then return O.buildEquipSeeds(21, stage, SC) end
            if mode == "在线挂机" then
                return O.calcOnlineIdleRewards(60, 4705, 1, 4705, SC)
            end
            if mode == "首通" then return D.generateFirstClearEquips(stage, { teamIdx = 1, dropLuck = 200 }) end
            if mode == "卷轴" then return D.rollScrollDrop(stage, { teamIdx = 1, dropLuck = 200 }) end
            return D.rollSweepTicket(stage, { teamIdx = 1, dropLuck = 200 })
        end
        local resultsSame, shapeSame = true, true
        for seed = 1, 20 do
            f.data.battle.dropLuck = 0
            local a, trace, tail = seeded(seed, function() return compute(plainStage) end)
            f.data.battle.dropLuck = 200
            local b, nextTrace, nextTail = seeded(seed, function() return compute(luckyStage) end)
            resultsSame = resultsSame and equal(a, b)
            shapeSame = shapeSame and trace == nextTrace and tail == nextTail
        end
        check(resultsSame, mode .. "真实奖励算法不读取队幸运，逐20种子内容相同")
        check(shapeSame, mode .. "真实奖励路径RNG形态/次数/终态不变")
    end
    local initial = copy(f.data)
    local Sweep = f.require("rules.sweep.SweepService")
    local Dungeon = f.require("rules.dungeon.DungeonService")
    local function restore(luck)
        for key in pairs(f.data) do f.data[key] = nil end
        for key, value in pairs(copy(initial)) do f.data[key] = value end
        f.data.battle.dropLuck = luck
        f.data.heroes.roster[1].dropLuck = luck
        f.data.equipment.inventory["999"] = { templateId = "C1", quality = 1, level = 1,
            baseStats = {}, affixes = { { affixId = 45, key = "dropLuck", value = luck } } }
        f.data.equipment.equipped["1"] = { accessory = 999 }
    end
    Dungeon.SetPersistCallback(function() return true end) -- 封闭内存提交出口，不调用玩家File。
    local Rewards = f.require("shared.sweep.SweepRewards")
    -- 主线扫荡已按本队幸运逐杀；以真实在线同源接口核对应，而非旧固定件数常量。
    for seed = 1, 8 do
        for _, luck in ipairs({ 0, 200 }) do
            restore(luck)
            local expected = seeded(seed, function()
                return Rewards.calculate(SC.getStage(4705), 1, 1, true, luck, 1)
            end)
            restore(luck)
            local actual = seeded(seed, function()
                local ok, err, receipt = Sweep.Sweep(1, 1, 1)
                assert(ok, "真实扫荡失败 " .. tostring(err))
                return receipt
            end)
            eq(actual.equipCount, expected.equipCount, "主线扫荡与逐杀同源件数 幸运" .. luck .. " 种子" .. seed)
            eq(actual.gold, expected.gold, "主线扫荡金币与逐杀同源")
            check(equal(actual.scrollDrops, expected.scrollDrops), "主线扫荡卷轴与逐杀同源")
            local equips = {}
            for index, reward in ipairs(actual.equips) do
                -- 真实deliverEquipment入包会写入seq；oracle先生成后尚未交付。
                -- 按实际nextSeq逐件走真实addToInventory，对比完整字段，不能删seq放宽same。
                local oracleBag = { inventory = {}, nextSeq = index }
                f.require("systems.EquipmentSystem").addToInventory(oracleBag, expected.equips[index])
                eq(reward.equip.seq, index, "实际交付序号与原nextSeq一致")
                equips[#equips + 1] = reward.equip
            end
            check(equal(equips, expected.equips), "主线扫荡品质/完整装备生成与真实逐杀+交付oracle一致")
            eq(actual.ticketLeft, 19, "一券一场成本不因红尾/幸运改变")
        end
        local function dungeonReward(luck)
            restore(luck)
            local ok, err, receipt = Dungeon.GrantEquipment(1, "equipment_vault", 1, 6)
            assert(ok, "真实装备副本失败 " .. tostring(err))
            eq(#receipt.equips, 6, "显式交付六件不因幸运改变")
            return receipt
        end
        local a, trace, tail = seeded(seed, function() return dungeonReward(0) end)
        local b, nextTrace, nextTail = seeded(seed, function() return dungeonReward(200) end)
        check(equal(a, b), "装备副本服务不借主线幸运，内容一致 种子" .. seed)
        check(trace == nextTrace and tail == nextTail, "装备副本服务RNG形态/次数/终态一致 种子" .. seed)
    end
    Dungeon.SetPersistCallback(nil)
    local DC = f.require("config.DungeonConfig")
    local entry = assert(DC.getCombatEntry("equipment_vault", 1))
    eq(entry.mode, "resource_dungeon", "真实装备副本combat entry带排除mode")
    f.env.math.random = function() error("真实资源副本零掉率不能消耗RNG") end
    eq(D.rollKillDrop(entry, { teamIdx = 1, dropLuck = 200 }), nil, "真实装备副本不产额外幸运击杀奖励")
end

function Start()
    assertions, failures = 0, {}
    print(PREFIX .. "开始：只读真实源码、独立环境、官方Runtime专项")
    local packageBefore = {} ---@type table<string, any>
    for key, value in pairs(package.loaded) do packageBefore[key] = value end
    local nativeRequire, nativeRandom = require, math.random
    local cases = { { "配置/词条生成/属性/存档/洗练投入", testAttributes },
        { "幸运归一化/队来源/概率/上下文边界", testLuckBoundaries },
        { "固定git旧参考逐种子零幸运回放", testZeroLuckReplay },
        { "品质单调分位/各Q分布/红装与零权重", testQualityDistribution },
        { "真实Boot wrapper/自动分解与保留", testBootBranches },
        { "真实Driver启动/阵亡换装/队列/重开隔离", testDriverSnapshots },
        { "保留单线固定本场快照", testSingleLineSnapshot },
        { "离线/扫荡/装备副本保持旧奖励规则", testExcludedRewardPaths } }
    for _, case in ipairs(cases) do
        print(PREFIX .. "用例开始 " .. case[1])
        local ok, err = pcall(case[2])
        if not ok then check(false, case[1] .. "异常（不隐藏） " .. tostring(err)) end
    end
    local isolated = require == nativeRequire and math.random == nativeRandom
    for key, value in pairs(packageBefore) do if package.loaded[key] ~= value then isolated = false end end
    for key in pairs(package.loaded) do if packageBefore[key] == nil then isolated = false end end
    check(isolated, "全套真实模块未污染package.loaded/全局require/math.random")
    print(PREFIX .. "汇总：断言" .. assertions .. "，失败" .. #failures)
    if #failures > 0 then
        for _, message in ipairs(failures) do print(PREFIX .. "失败明细 " .. message) end
        error(PREFIX .. "专项失败 " .. #failures .. " 项；必须修复真实问题或夹具，不能放宽生产守卫")
    end
    print(PREFIX .. "ALL PASS 断言=" .. assertions)
    engine:Exit()
end
