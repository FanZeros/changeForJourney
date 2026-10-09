------------------------------------------------------------------------
-- character_attribute_stability_test.lua —— 真实属性管线的稳定展示回归
-- 不修改 HC/PlayerStore/Dispatcher；显式快照隔离装备水合与穿戴。
------------------------------------------------------------------------
local Preview = require("ui.character.detail.EquipmentPreview")
local Attrs = require("ui.character.detail.CharacterDetailAttrs")
local AD = require("systems.AttributeDef")
local HC = require("config.HeroConfig")

local assertions, failures = 0, 0
local function check(ok, message)
    assertions = assertions + 1
    if ok then print("[PASS] " .. message)
    else failures = failures + 1; print("[FAIL] " .. message) end
end
local function fixture(heroId)
    return {
        heroes = { roster = { [tostring(heroId)] = { level = 70 } }, deployed = { heroId } },
        equipment = { inventory = {}, equipped = { [tostring(heroId)] = {} }, nextSeq = 100 },
        artifacts = { bag = {} },
    }
end
local function put(options, seq, affixes, stats)
    options.equipment.inventory[tostring(seq)] = {
        templateId = "C1", level = 1, quality = 1, affixes = affixes or {}, baseStats = stats or {},
    }
end
local function row(data, key)
    for _, column in ipairs({ data.left, data.right }) do
        for _, r in ipairs(column) do if r.key == key then return r end end
    end
    return nil
end
local function numericKeys(data)
    local keys = {}
    for _, column in ipairs({ data.left, data.right }) do
        for _, r in ipairs(column) do
            if r.numericValue ~= nil then keys[#keys + 1] = r.key end
        end
    end
    return table.concat(keys, "|")
end
local function previewNumericKeys(data)
    local keys = {}
    for _, r in ipairs(data.rows) do
        if type(r.currentValue) == "number" then keys[#keys + 1] = r.key end
    end
    return table.concat(keys, "|")
end
local function noDuplicates(data)
    local seen = {}
    for _, column in ipairs({ data.left, data.right }) do
        for _, r in ipairs(column) do
            if seen[r.key] then return false end
            seen[r.key] = true
        end
    end
    return true
end
local function absent(data, keys)
    for _, key in ipairs(keys) do if row(data, key) then return false end end
    return true
end

local function readSource(path)
    local file = assert(cache:GetFile(path), "missing source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- 私有 _ENV 装载真实属性模块：只替数据读取边界，不替数值/装备/神器公式，不写全局 HC。
local function presentationCacheRegression()
    local data = fixture(20)
    data.talents = { litNodes = {} }
    data.heroes.teams = { { slots = { 20, 2, 9, 21 } } }
    for _, id in ipairs({ 20, 2, 9, 21, 1 }) do
        data.heroes.roster[tostring(id)] = { level = 70, awakening = {}, extraTalent = {} }
        data.equipment.equipped[tostring(id)] = {}
    end
    local sources, revisions = data, { heroes = 1, equipment = 1, artifacts = 1, talents = 1 }
    local owned = data.heroes.roster
    local litNodes, language = data.talents.litNodes, "zh_CN"
    local builds, creates, inventoryScans = 0, 0, 0
    local modules = {}
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local store = { Get = function(key) return sources[key] end,
        GetRevision = function(key) return revisions[key] or 0 end }
    local hero = setmetatable({
        _getSavedLitNodes = function() return litNodes end,
        createHero = function(id, level, adv, awakening, extra, opts)
            creates = creates + 1
            local fallback = owned[tostring(id)] or owned[id] or {}
            local actualOptions = opts or { litNodes = litNodes or false, silent = true }
            return HC.createHero(id, level, adv, awakening or fallback.awakening or {},
                extra == nil and (fallback.extraTalent or {}) or extra, actualOptions)
        end,
    }, { __index = HC })
    env.pairs = function(value)
        if sources.equipment and value == sources.equipment.inventory then inventoryScans = inventoryScans + 1 end
        return pairs(value)
    end
    env.require = function(name)
        if name == "core.PlayerStore" then return store end
        if name == "runtime.ClientDispatcher" then return { get = store.Get } end
        if name == "core.I18n" then return { get = function() return language end } end
        if name == "config.HeroConfig" then return hero end
        if name == "ui.character.panel.CharacterPanel" then
            return { getOwnedHero = function(id) return owned[tostring(id)] or owned[id] end }
        end
        if name == "systems.ArtifactBridge" or name == "ui.character.detail.CharacterDetailAttrs" then
            if not modules[name] then
                modules[name] = assert(load(readSource(name:gsub("%.", "/") .. ".lua"), "@cache-regression/" .. name, "t", env))()
            end
            return modules[name]
        end
        return require(name)
    end
    local actual = env.require("ui.character.detail.CharacterDetailAttrs")
    local lastCollected = {}
    local read = actual.createPresentationCache(function(...)
        builds = builds + 1
        lastCollected = actual.collectAttributes(...)
        return lastCollected
    end)
    local function sample(id, level, options) return read(id or 20, assert(HC.get(id or 20)), level or 70, options) end
    local function assertMatches(view, id, level, options, label)
        local fresh = actual.collectAttributes(id or 20, assert(HC.get(id or 20)), level or 70, options)
        local expected, order = {}, actual.displayOrderIndex()
        for _, column in ipairs({ fresh.left, fresh.right }) do
            for _, r in ipairs(column) do expected[#expected + 1] = r end
        end
        local indices = {}
        for i, r in ipairs(expected) do indices[r] = i end
        table.sort(expected, function(a, b)
            local oa, ob = order[a.key] or 9999, order[b.key] or 9999
            return oa < ob or (oa == ob and indices[a] < indices[b])
        end)
        check(same(view.rows, actual.filterDisplayRows(expected)) and same(view.stats, fresh.stats),
            label .. " cached rows/six stats equal filtered actual formulas")
        check(view.attrs == nil, label .. " presentation does not expose mutable attrs")
    end
    local first = sample()
    check(builds == 1 and creates == 4, "four-member star-gate cold presentation builds exactly once/four actual heroes")
    local initialCreates = creates
    assertMatches(first, 20, 70, nil, "cold star-gate")
    initialCreates = creates
    -- 冷构建先隔离快照可复制背包；只测180暖帧依赖检查不得再次扫描整库存。
    inventoryScans = 0
    local stable = true
    for _ = 1, 180 do if sample() ~= first then stable = false end end
    check(stable, "180 warm presentation frames reuse host-private rows")
    check(builds == 1 and creates == initialCreates, "180 stable frames create no heroes and perform no row rebuild")
    check(inventoryScans == 0, "presentation dependency checks do not scan whole inventory")
    local sourceRows = copy(lastCollected.left)
    local independent = lastCollected.left[1].value
    first.rows[1].value = "private render mutation"
    check(same(lastCollected.left, sourceRows), "render cache cannot mutate collector return rows")
    first.rows[1].value = independent
    local otherHost = actual.createPresentationCache()
    local other = otherHost(20, assert(HC.get(20)), 70)
    check(other ~= first and other.rows ~= first.rows and other.rows[1] ~= first.rows[1], "independent host caches cannot share mutable presentation rows")

    local function changed(label, change, id, level, options)
        local before = builds
        change()
        local view = sample(id, level, options)
        check(builds == before + 1, label .. " invalidates exactly once")
        check(sample(id, level, options) == view and builds == before + 1, label .. " post-hydration stable next frame")
        assertMatches(view, id, level, options, label)
        return view
    end
    local beforeExp = builds
    data.heroes.roster["20"].exp, data.heroes.roster["2"].exp = 100, 200
    revisions.heroes = revisions.heroes + 1
    check(sample() == first and builds == beforeExp, "same-reference own/team exp publish does not rebuild presentation")
    data.heroes = copy(data.heroes)
    data.heroes.roster["20"].shards = 999
    revisions.heroes = revisions.heroes + 1
    check(sample() == first and builds == beforeExp, "replacement roster with only exp/shards changes does not rebuild")
    changed("same-reference own level", function() data.heroes.roster["20"].level = 71 end, 20, 71)
    changed("same-reference teammate level", function() data.heroes.roster["2"].level = 72 end, 20, 71)
    changed("teammate awakening", function() data.heroes.roster["2"].awakening[1] = true end, 20, 71)
    changed("same-reference extra talent", function() data.heroes.roster["2"].extraTalent.burnKills = 2 end, 20, 71)
    changed("same-reference advancement", function() data.heroes.roster["20"].advBranch = { first = 105 } end, 20, 71)
    changed("worn old-item hydration", function()
        put(data, 1, { { affixId = 25, value = 12.5 } })
        data.equipment.equipped["20"].accessory = 1
    end, 20, 71)
    changed("worn affix nested patch", function() data.equipment.inventory["1"].affixes[1].value = 20 end, 20, 71)
    local noChange = builds
    put(data, 999, { { affixId = 25, value = 99 } })
    check(builds == noChange and sample(20, 71) ~= nil and builds == noChange, "unworn inventory insertion is not a dependency")
    changed("artifact same-reference value", function()
        data.artifacts.bag = { { id = "test", artifactId = 12, value = 250 } }
        data.artifacts.equippedByTeam = { { [1] = { "test" } } }
    end, 20, 71)
    local swapped = changed("artifact same-reference nested patch", function() data.artifacts.bag[1].value = 280 end, 20, 71)
    check(row({ left = swapped.rows, right = {} }, "_artifactCritDmgMult") ~= nil,
        "artifact fixture applies actual id12 multiplier rather than only invalidating a key")
    changed("team reassignment", function() data.heroes.teams[1].slots = { 2, 20, 21, 9 } end, 20, 71)
    changed("same-reference lit nodes", function() litNodes[#litNodes + 1] = 1 end, 20, 71)
    changed("language", function() language = "ko" end, 20, 71)
    changed("clear mirror with same Dispatcher content", function()
        revisions.equipment, revisions.artifacts, revisions.talents = 2, 2, 2
    end, 20, 71)
    changed("missing own roster entry", function() data.heroes.roster["20"] = nil end, 20, 71)
    local switched = changed("switch hero", function() end, 1, 70)
    check(row({ left = switched.rows, right = {} }, "_melissaStarGateResonance") == nil, "switch hero does not leak star-gate rows")
    changed("switch back hero", function() end, 20, 71)
    local restored = copy(data)
    changed("clear all sources", function() sources = {} end, 20, 71)
    changed("restore after clear", function() sources = restored end, 20, 71)
    changed("explicit empty snapshots never use live fallback", function() end, 20, 71, {})
    local a = actual.collectAttributes(1, assert(HC.get(1)), 70, restored)
    local b = actual.collectAttributes(1, assert(HC.get(1)), 70, restored)
    a.left[1].value = "caller changed"; a.attrs.base[AD.MAX_HP] = -1
    check(b.left[1].value ~= a.left[1].value and b.attrs.base[AD.MAX_HP] ~= -1,
        "collectAttributes retains independent rows/attrs for public preview callers")
end

function Start()
    print("[character_attribute_stability_test] start")
    local ok, err = pcall(function()
        -- 同一个真实英雄：无装备 → 预览 → 真穿戴 → 卸回空槽，行集合与顺序都不变。
        for _, heroId in ipairs({ 1, 2, 9, 20 }) do
            local options = fixture(heroId)
            put(options, 1, {
                { affixId = 19, value = 10 }, { affixId = 25, value = 12.5 },
                { affixId = 26, value = 8.25 }, { affixId = 30, value = 15 },
                { affixId = 37, value = 11 }, { affixId = 36, value = 4 },
            })
            local result = Preview.build(heroId, 70, 1, nil, options)
            local currentOnly = Preview.build(heroId, 70, nil, nil, options)
            check(previewNumericKeys(currentOnly) == previewNumericKeys(result), "hero" .. heroId .. " 预览合并后的数值key及排序不跳动")
            check(result.error == nil and result.preview ~= nil, "hero" .. heroId .. " 真实装备候选可预览")
            local preview = assert(result.preview)
            local heroCfg = assert(HC.get(heroId))
            local keys = numericKeys(result.current)
            check(keys == numericKeys(preview), "hero" .. heroId .. " current/preview 数值key与顺序一致")
            check(noDuplicates(result.current) and noDuplicates(preview), "hero" .. heroId .. " 生命/护甲别名/治疗量/暴击无重复行")
            options.equipment.equipped[tostring(heroId)].accessory = 1
            local equipped = Attrs.collectAttributes(heroId, heroCfg, 70, options)
            check(keys == numericKeys(equipped), "hero" .. heroId .. " 真穿戴不改变属性key与顺序")
            options.equipment.equipped[tostring(heroId)].accessory = nil
            local removed = Attrs.collectAttributes(heroId, heroCfg, 70, options)
            check(keys == numericKeys(removed), "hero" .. heroId .. " 卸装后仍保留所有原有数值行")
            local category = AD.getAtkCategory(heroCfg.atkType)
            local unrelated = category == "physical" and {
                AD.MAG_ATK, AD.MAG_ATK_BONUS, AD.MAG_PEN, AD.MAG_DMG_BONUS,
                AD.FINAL_MAG_ATK_BONUS, AD.HEAL_AMOUNT, AD.HEAL_BONUS, AD.HEAL_CRIT_RATE, AD.HEAL_CRIT_DMG,
            } or category == "magical" and {
                AD.PHYS_ATK, AD.PHYS_ATK_BONUS, AD.PHYS_PEN, AD.PHYS_DMG_BONUS,
                AD.FINAL_PHYS_ATK_BONUS, AD.HEAL_AMOUNT, AD.HEAL_BONUS, AD.HEAL_CRIT_RATE, AD.HEAL_CRIT_DMG,
            } or {
                AD.PHYS_ATK, AD.MAG_ATK, AD.PHYS_ATK_BONUS, AD.MAG_ATK_BONUS,
                AD.PHYS_PEN, AD.MAG_PEN, AD.PHYS_DMG_BONUS, AD.MAG_DMG_BONUS,
                AD.FINAL_PHYS_ATK_BONUS, AD.FINAL_MAG_ATK_BONUS, AD.DMG_BONUS, AD.COMBO_RATE, AD.COMBO_DMG_UP,
                AD.HEAL_CRIT_RATE, AD.HEAL_CRIT_DMG,
            }
            check(absent(result.current, unrelated) and absent(equipped, unrelated), "hero" .. heroId .. " 非本职属性即使装备带值也不显示")
            if category ~= "healing" then
                check(row(removed, AD.COMBO_RATE).numericValue == 0 and row(removed, AD.COMBO_RATE).value == "0.0%",
                    "hero" .. heroId .. " 连击0%常驻")
                check(row(equipped, AD.COMBO_RATE).numericValue == 15, "hero" .. heroId .. " 连击装备后精确升至15%")
            end
            check(row(removed, AD.PHYS_BLOCK_RATIO).numericValue == 60 and row(removed, AD.MAG_BLOCK_RATIO).numericValue == 60,
                "hero" .. heroId .. " 默认格挡比例60%也显示，不误转为0")
            if category ~= "healing" then
                local penKey = category == "physical" and AD.PHYS_PEN or AD.MAG_PEN
                check(row(removed, penKey).numericValue == 0 and row(equipped, penKey).numericValue > 0,
                    "hero" .. heroId .. " 穿透0→正值→卸装0始终同一行")
            end
            check((row(removed, "_melissaStarGatePen") ~= nil) == (heroId == 20), "hero" .. heroId .. " 星门行仅固有机制角色存在")
            check(absent(removed, { "_artifactCritRateMult", "_artifactCritDmgMult", "_artifactIgnoreArmor", "_artifactNoHeal" }),
                "hero" .. heroId .. " 无神器不虚构神器倍率/布尔能力")
        end

        -- 真实治疗英雄的暴击率默认0，不依赖改全局配置或假造英雄。
        local healer = fixture(9)
        put(healer, 1, { { affixId = 37, value = 11 } })
        local healing = Preview.build(9, 70, 1, nil, healer)
        check(row(healing.current, "_effCritRate").numericValue == 0
            and row(healing.current, "_effCritRate").value == "0.0%", "治疗暴击率0%常驻且保留原始0")
        check(row(healing.preview, "_effCritRate").numericValue == 11, "治疗暴击词条使同一行0→11%")
        check(row(healing.current, "_effCritDmg").name == "暴击治疗", "治疗倍率使用暴击治疗名称")
        local displayed = Attrs.filterDisplayRows(healing.rows)
        local displayKeys = {}
        for _, item in ipairs(displayed) do displayKeys[item.key] = true end
        check(not displayKeys[AD.FINAL_HP_BONUS] and not displayKeys[AD.FINAL_SPI_BONUS]
            and displayKeys[AD.MAX_HP] and displayKeys["_effCritDmg"], "总属性保留实际值、不重复展示最终乘区")
        check(row(healing.current, AD.FINAL_HP_BONUS) ~= nil, "显示过滤不删除原始预览属性")

        -- 用装备减值使真实物理英雄暴击率/暴伤恰好为0，再更换为空属性装备。
        local physical = fixture(1)
        local base = Attrs.collectAttributes(1, assert(HC.get(1)), 70, physical)
        put(physical, 1, nil, {
            { AD.CRIT_RATE, -row(base, "_effCritRate").numericValue },
            { AD.CRIT_DMG, -row(base, "_effCritDmg").numericValue },
        })
        put(physical, 2)
        physical.equipment.equipped["1"].accessory = 1
        local zero = Preview.build(1, 70, 2, nil, physical)
        check(row(zero.current, "_effCritRate").numericValue == 0 and row(zero.current, "_effCritRate").value == "0.0%",
            "物理有效暴击率恰为0时不隐藏")
        check(row(zero.current, "_effCritDmg").numericValue == 0 and row(zero.current, "_effCritDmg").value == "0.0%",
            "有效暴伤恰为0时也不隐藏")
        local zeroPreview = assert(zero.preview)
        check(numericKeys(zero.current) == numericKeys(zeroPreview), "零暴击/暴伤恢复正值不改变行集合与顺序")
        local comparable = true
        for _, r in ipairs(zero.rows) do
            if r.delta ~= nil and (type(r.currentValue) ~= "number" or type(r.previewValue) ~= "number") then comparable = false end
        end
        check(comparable, "预览数值行始终为number，不从格式文本反解析")
        presentationCacheRegression()
    end)
    if not ok then check(false, "测试异常: " .. tostring(err)) end
    if failures == 0 then print("[character_attribute_stability_test] ALL PASS assertions=" .. assertions)
    else print("[character_attribute_stability_test] FAILURES=" .. failures .. " assertions=" .. assertions) end
    engine:Exit()
end
