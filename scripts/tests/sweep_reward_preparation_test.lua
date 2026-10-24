-- 大批奖励准备只整理引用，不发奖、不读写玩家文件；标准入口独立Runtime运行。
local Preparation = require("ui.widget.RewardPreparation")
local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end

local function rank(item)
    return item.type == "hero" and 2 or item.type == "equip" and 3
        or item.type == "artifact" and 4 or 1
end

local function ordered(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    if ra == 1 then return a.index < b.index end
    if a.quality ~= b.quality then return a.quality > b.quality end
    if ra == 3 and a.level ~= b.level then return a.level > b.level end
    return a.index < b.index
end

local function exercise(count)
    local source, original = {}, {}
    local types = { "equip", "gold", "hero", "artifact", "equip" }
    for index = 1, count do
        local item = { type = types[(index - 1) % #types + 1], index = index,
            quality = index % 6 + 1, level = index % 200 + 1,
            equip = { templateId = "W1", nested = { index } } }
        source[index], original[index] = item, item
    end
    local calls, frames, result = 0, 0, nil
    local worker = coroutine.create(function()
        result = Preparation.prepare(source, function(phase, done, total)
            check(phase == "presentation" and done >= 0 and done <= total, "进度只报告真实整理阶段")
            calls = calls + 1
            coroutine.yield()
        end)
    end)
    while coroutine.status(worker) ~= "dead" do
        local ok, reason = coroutine.resume(worker)
        assert(ok, reason)
        frames = frames + 1
        check(source[1] == original[1] and source[#source] == original[#source], "准备让出期间原列表不变")
        check(result == nil or coroutine.status(worker) == "dead", "完成前不发布半成品")
    end
    if count >= 1000 then check(frames > 10 and calls > 10, "大列表真实分帧而非一次同步排序") end
    check(Preparation.take(result, {}) == nil, "其他列表不得冒用token")
    local items = assert(Preparation.take(result, source), "完整token可消费")
    check(#items == #source, "不截断或丢奖励")
    local seen = {}
    for index, item in ipairs(items) do
        check(original[item.index] == item, "完整奖励对象引用保持")
        check(not seen[item.index], "无重复奖励")
        seen[item.index] = true
        if index > 1 then check(ordered(items[index - 1], item), "类别/品质/等级及同key稳定原序") end
        check(item.equip.nested[1] == item.index, "嵌套实例未水合或修改")
    end
    for index, item in ipairs(source) do check(item == original[index], "源顺序不变") end
    check(Preparation.take(result, source) == nil, "token只可消费一次")
    print("[sweep_reward_preparation_test] count=" .. count .. " frames=" .. frames .. " checkpoints=" .. calls)
end

local function summary(source, mergeResources)
    local token = Preparation.prepare(source, function() end, mergeResources)
    return assert(Preparation.take(token, source, mergeResources))
end

local function exerciseStacks()
    local first = { type = "diamond", amount = 100, quality = 5, icon = "black-crystal" }
    local source = {}
    for index = 1, 60 do source[index] = first end
    local items = summary(source)
    check(#items == 1 and items[1].amount == 6000, "六十条黑晶100汇总成一条6000")
    check(first.amount == 100 and #source == 60 and items[1] ~= first, "共享配置奖励不被原地累加")
    check(summary(source)[1].amount == 6000, "重复整理不重复累加源配置")
    local interactive = summary(source, false)
    check(#interactive == 60 and interactive[1] == first and interactive[60] == first,
        "逐项回调模式保留全部对象和索引")
    local token = Preparation.prepare(source, function() end)
    check(Preparation.take(token, source, false) == nil, "聚合token不能用于逐项交互模式")
    check(#assert(Preparation.take(token, source)) == 1, "错误模式不误消费token")
    token = Preparation.prepare(source, function() end)
    source[#source + 1] = first
    check(Preparation.take(token, source) == nil, "token保留原始输入长度校验而非聚合长度")
    source[#source] = nil
    check(#assert(Preparation.take(token, source)) == 1, "恢复原长度后完整token仍可用")

    local equip = { type = "equip", templateId = "W1", amount = 1, quality = 3,
        level = 10, equip = { seq = 1, affixes = { { value = 3 } } } }
    local shard1, shard2 = { type = "shard", heroId = 1, amount = 2 }, { type = "shard", heroId = 2, amount = 3 }
    local nested = { type = "gold", amount = 4, extra = {} }
    local mixed = {
        { type = "gold", amount = 7 }, { type = "diamond", amount = 100 },
        shard1, shard2, { type = "gold", amount = 11 },
        { type = "shard", heroId = 1, amount = 5 }, equip, equip,
        { type = "hero", heroId = 1 }, { type = "hero", heroId = 1 },
        { type = "artifact", artifactId = 1 }, { type = "artifact", artifactId = 1 },
        nested, nested,
        { type = "seed", quality = 3, level = 10, amount = 1 },
        { type = "seed", quality = 3, level = 10, amount = 1 },
    }
    items = summary(mixed)
    check(#items == 14, "仅合法同类资源求和，不丢装备/英雄/神器/种子/嵌套项")
    check(items[1].type == "gold" and items[1].amount == 18 and items[2].type == "diamond",
        "不同资源不合并，首次出现顺序不变")
    check(items[3].heroId == 1 and items[3].amount == 7 and items[4].heroId == 2 and items[4].amount == 3,
        "同英雄碎片求和，不同英雄碎片严格隔离")
    check(shard1.amount == 2 and shard2.amount == 3, "碎片源数量不变")
    check(items[5] == nested and items[6] == nested, "含嵌套元数据的资源不猜测叠加")
    check(items[11] == equip and items[12] == equip and equip.equip.affixes[1].value == 3,
        "同模板甚至同引用的独立装备展示均保留，不水合词缀")

    local boundaries = {
        { type = "gold", amount = 1, quality = 2 }, { quality = 2, amount = 2, type = "gold" },
        { type = "gold", amount = 3, quality = 3 }, { type = "gold", amount = 4, destination = "lootbox" },
        { type = "gold", amount = 5, destination = "inventory" },
        { type = "refine_stone", amount = 1 }, { type = "enhance_star", amount = 1 },
        { type = "gold", amount = 0 }, { type = "gold", amount = -1 },
        { type = "gold", amount = 0.5 }, { type = "gold", amount = math.huge },
        { type = "unknown", amount = 1 }, { type = "unknown", amount = 2 },
        { type = "gold", amount = 9007199254740991 }, { type = "gold", amount = 1 },
    }
    items = summary(boundaries)
    check(#items == #boundaries - 1 and items[1].amount == 3,
        "字段顺序不影响同类，品质/去向/协议别名及非法数量保持独立")
    check(items[#items - 1].amount == 9007199254740991 and items[#items].amount == 1,
        "超过精确整数上限不静默舍入丢数量")

    local identities = summary({
        { type = "shard", heroId = 9007199254740992, amount = 1 },
        { type = "shard", heroId = 9007199254740993, amount = 2 },
    })
    check(#identities == 2 and identities[1].heroId ~= identities[2].heroId,
        "Lua整数元数据不经浮点格式化而误合并相邻ID")

    local large = {}
    for index = 1, 100000 do large[index] = { type = "diamond", amount = 100 } end
    local frames, result = 0, nil
    local co = coroutine.create(function()
        result = Preparation.prepare(large, function() coroutine.yield() end)
    end)
    while coroutine.status(co) ~= "dead" do
        local ok, reason = coroutine.resume(co)
        assert(ok, reason)
        frames = frames + 1
        check(large[1].amount == 100 and large[#large].amount == 100, "十万资源分帧期间不改来源")
    end
    items = assert(Preparation.take(result, large))
    check(frames > 10 and #items == 1 and items[1].amount == 10000000,
        "十万同类资源分帧聚合，数量精确守恒")
    print("[sweep_reward_preparation_test] stacks=100000 frames=" .. frames)
end

function Start()
    local random, randomseed, oldFile, oldFs = math.random, math.randomseed, File, fileSystem
    local function denied() error("奖励整理禁止RNG或玩家文件") end
    math.random, math.randomseed, File = denied, denied, denied
    fileSystem = setmetatable({}, { __index = function() return denied end })
    local ok, reason = pcall(function()
        for _, count in ipairs({ 0, 1, 17, 1000, 100000 }) do exercise(count) end
        exerciseStacks()
        local source = { { type = "gold" } }
        local accepted = pcall(Preparation.prepare, source, function() error("expected cancel") end)
        check(not accepted, "准备取消不发布token")
        check(#source == 1 and source[1].type == "gold", "取消不改来源")
    end)
    math.random, math.randomseed, File, fileSystem = random, randomseed, oldFile, oldFs
    engine:Exit()
    if not ok then error("[sweep_reward_preparation_test] FAIL " .. tostring(reason)) end
    print("[sweep_reward_preparation_test] assertions=" .. assertions .. " ALL PASS")
end
