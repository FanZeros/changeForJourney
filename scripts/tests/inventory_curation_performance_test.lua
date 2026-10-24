-- 只读规划受控CPU/调用专项：私有真实模块、确定性夹具，不启动Boot或访问玩家档。
local F = require("tests.InventoryCurationFixture")
local TAG = "[inventory_curation_performance_test]"
local assertions = 0
local function check(value, label) assertions = assertions + 1; assert(value, label) end
local function eq(a, b, label) check(a == b, label .. " " .. tostring(a) .. "/" .. tostring(b)) end

local function setup()
    local h = F.new()
    h.Curation = h.require("systems.InventoryCuration")
    h.Query = h.require("systems.EquipmentQuery")
    h.Power = h.require("systems.EquipmentPower")
    h.Eq = h.require("systems.EquipmentSystem")
    local hydrate, score = h.Query.hydrateCopy, h.Power.genericScore
    h.calls = { hydrate = 0, score = 0, base = 0 }
    h.Query.hydrateCopy = function(item)
        h.calls.hydrate = h.calls.hydrate + 1
        return hydrate(item)
    end
    h.Power.genericScore = function(item)
        h.calls.score = h.calls.score + 1
        if item.level == nil then h.calls.base = h.calls.base + 1 end
        return score(item)
    end
    function h:reset() self.calls = { hydrate = 0, score = 0, base = 0 } end
    return h
end

local function main()
    local h = setup()
    local templates = { "W1", "C1", "A1", "H1", "S1", "O1" }
    for _, count in ipairs({ 500, 2000, 10000 }) do
        local bag, box = F.bag(h, 500), { seeds = {} }
        for index = 1, count do
            -- 重复底材、不同随机词条：禁止因此合并成品分或条目。
            local item = F.item(h, templates[(index - 1) % 6 + 1], (index - 1) % 200 + 1, (index - 1) % 6 + 1)
            item.affixes = { { affixId = 1, key = "str", value = index % 7 + 1 } }
            box.seeds[index] = { equip = item, count = 1 }
        end
        local before, aliases = F.copy({ bag, box }), F.aliases({ bag, box })
        local samples, expected = {}, nil ---@type number[], table|nil
        for repeatIndex = 1, 5 do
            h:reset()
            local started = os.clock()
            local result, why = h.Curation.plan(bag, box)
            samples[repeatIndex] = (os.clock() - started) * 1000
            check(result ~= nil, tostring(why))
            if expected then F.same(result, expected, "repeat full plan") else expected = F.copy(result) end
            eq(result.counts.inventoryAfter, 500, "capacity")
            eq(result.moveInCount, result.moveOutCount, "inventory conservation")
            eq(h.calls.hydrate, 500 + count, "every instance independently hydrated")
            -- 成品分逐件计算；仅无词条且未投入的低级装备可复用刚算出的等价结果。
            eq(h.calls.score - h.calls.base, 500 + count, "ready scoring never merged")
            if not _G.LOOT_PERF_BASELINE then
                eq(h.calls.base, count, "plain low-level bag reuses only equivalent ready scores")
            end
        end
        table.sort(samples)
        print(TAG .. string.format(" SAMPLE bag=500 box=%d median_cpu_ms=%.3f range=%.3f..%.3f hydrate=%d generic=%d foundation=%d",
            count, samples[3], samples[1], samples[5], h.calls.hydrate, h.calls.score, h.calls.base))
        F.same({ bag, box }, before, "all input fields unchanged")
        F.assertAliases(aliases)
    end
    -- 同引用真实字段变化必须影响下一次plan；缓存不得跨规划保留。
    local bag, box = F.bag(h, 500), F.box({ F.item(h, "W1", 1, 1) })
    local first = assert(h.Curation.plan(bag, box))
    box.seeds[1].equip.baseStats[1][2] = 1000000
    local second = assert(h.Curation.plan(bag, box))
    check(first.moveInCount == 0 and second.moveInCount == 1, "same source nested base patch visible next plan")
    eq(second.moveIn[1].index, 1, "correct incoming original index")
    local stronger = second.moveIn[1].baseScore
    box.seeds[1].equip.baseStats[1][1] = "hp"
    local third = assert(h.Curation.plan(F.bag(h, 0), box))
    check(third.moveIn[1].baseScore ~= stronger, "foundation stat key included")
    -- 相同数值但不同顺序/模板：投影必须按实际完整顺序判别，保留intrinsic规则。
    local variants = {
        { templateId = "W1", level = 40, quality = 1, baseStats = {{"str",10},{"agi",7}}, affixes = {} },
        { templateId = "W1", level = 40, quality = 1, baseStats = {{"agi",7},{"str",10}}, affixes = {} },
        { templateId = "W1", level = 40, quality = 1, baseStats = {{"str",10},{"agi",8}}, affixes = {} },
        { templateId = "W1", level = 40, quality = 1, baseStats = {{"str","10"},{"agi",7}}, affixes = {} },
        { templateId = "W1", level = 40, quality = 1, baseStats = {}, affixes = {} },
    }
    local plan = assert(h.Curation.plan(F.bag(h, 0), F.box(variants)))
    eq(plan.moveInCount, #variants, "all variants preserved")
    for _, row in ipairs(plan.moveIn) do
        local view = h.Query.hydrateCopy(variants[row.index])
        local reference = h.Power.genericScore({ templateId = view.templateId, baseStats = view.baseStats, affixes = {} })
        eq(row.baseScore, reference, "ordered foundation exact score " .. row.index)
    end
    local malformed = F.item(h)
    malformed.baseStats = { false }
    local protected = assert(h.Curation.plan(F.bag(h, 0), F.box({ malformed })))
    eq(protected.moveInCount, 0, "malformed foundation remains protected")
    eq(protected.protected.reasons.invalid, 1, "invalid reason retained")
    -- 遍历真实模板及50/51等级补偿边界；成品/底材分必须逐值等于原正式投影。
    local cfg = h.require("config.EquipmentConfig")
    local ids = {}
    for id in pairs(cfg.ITEMS) do ids[#ids + 1] = id end
    table.sort(ids)
    local boundaryItems = {}
    for _, id in ipairs(ids) do
        for _, level in ipairs({ 1, 50, 51, 200 }) do
            local item = F.item(h, id, level, 1)
            boundaryItems[#boundaryItems + 1] = item
        end
    end
    local function compareItems(items)
        -- 空仓容量500，分批确保不因配额未选到而漏掉基础评分验证。
        for first = 1, #items, 400 do
            local selected = {}
            for index = first, math.min(first + 399, #items) do selected[#selected + 1] = items[index] end
            local actual = assert(h.Curation.plan(F.bag(h, 0), F.box(selected)))
            eq(actual.moveInCount, #selected, "all score-boundary items included")
            for _, row in ipairs(actual.moveIn) do
                local view = h.Query.hydrateCopy(selected[row.index])
                local stats = view.baseStats
                if view.corruptBaseMult ~= nil and view.corruptBaseMult ~= 1 then
                    local q = cfg.QUALITY[view.quality]
                    stats = h.Eq.recalcBaseStats(view.templateId, view.level, q and q.baseStrength or 1, view.secondaryRoll)
                end
                eq(row.score, h.Power.genericScore(view), "ready score exact")
                eq(row.baseScore, h.Power.genericScore({templateId=view.templateId,baseStats=stats,affixes={}}),
                    "foundation score exact " .. tostring(view.templateId) .. "/" .. view.level)
            end
        end
    end
    compareItems(boundaryItems)
    local special = {}
    for _, patch in ipairs({ {ascendLevel=1}, {enhanceLevel=1,ascendLevel=false},
        {affixMult=2}, {affixes={{affixId=1,value=2}}}, {affixes={opaque=true}},
        {corruptBaseMult=1.2}, {corruptBaseMult=1}, {slot="offhand",grip="twohand"},
        {level="50"}, {level=50.5}, {level=-1} }) do
        local item = F.item(h,"W1",1,1)
        for key,value in pairs(patch) do item[key]=value end
        special[#special+1]=item
    end
    compareItems(special)
    eq(h.randomCalls, 0, "no RNG")
    eq(h.fileCalls + h.fsCalls, 0, "no File/FS")
    print(TAG .. " ALL PASS assertions=" .. assertions .. " softwareCPUOnly=true")
end

function Start()
    local ok, err = pcall(main)
    if not ok then print(TAG .. " [FAIL] " .. tostring(err)) end
    engine:Exit()
end
