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

function Start()
    local random, randomseed, oldFile, oldFs = math.random, math.randomseed, File, fileSystem
    local function denied() error("奖励整理禁止RNG或玩家文件") end
    math.random, math.randomseed, File = denied, denied, denied
    fileSystem = setmetatable({}, { __index = function() return denied end })
    local ok, reason = pcall(function()
        for _, count in ipairs({ 0, 1, 17, 1000, 100000 }) do exercise(count) end
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
