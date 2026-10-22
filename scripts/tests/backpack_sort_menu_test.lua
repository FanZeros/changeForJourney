-- 属性菜单专项：私有 require + 内存状态，禁止玩家存档/Boot/动作，不依赖其他回归。
-- /workspace/.cli/UrhoXRuntime tests/backpack_sort_menu_test.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local PREFIX = "[backpack_sort_menu_test] "
local assertions, failures = 0, 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then failures = failures + 1; print(PREFIX .. "FAIL " .. message) end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function readSource(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "missing source " .. name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function runTests()
    local labels, changes, ioCalls = {}, 0, 0
    local env = setmetatable({}, { __index = _G })
    env._G, env.time = env, { elapsedTime = 100 }
    env.File = function() ioCalls = ioCalls + 1; error("test forbids player File") end
    env.fileSystem = setmetatable({}, { __index = function()
        return function() ioCalls = ioCalls + 1; error("test forbids player filesystem") end
    end })
    -- 只记录真实菜单的绘图调用，不创建 NanoVG/GPU context，不宣称像素验收。
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgFontFace", "nvgFontSize", "nvgTranslate",
        "nvgBeginPath", "nvgRoundedRect", "nvgFillColor", "nvgFill", "nvgIntersectScissor" }) do
        env[name] = function() end
    end
    env.nvgRGBA = function() return {} end
    local modules = {
        ["core.DrawUtil"] = {
            hitTest = function(x, y, cx, cy, w, h)
                return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
            end,
            drawTextStroke = function(_, _, _, text) labels[#labels + 1] = text end,
        },
        ["core.DarkIcon"] = { drawNine = function() end },
        ["core.I18n"] = { lookup = function(text) return text end,
            displayBounds = function(_, _, _, text) return #text * 10 end },
        ["ui.hud.popup.SettingsPanel"] = { isSetIconsEnabled = function() return true end },
        ["ui.widget.HeroFrame"] = {}, ["urhox-libs/UI"] = {},
        ["ui.widget.DesignWidgetSurface"] = {},
        ["core.PlayerStore"] = { Get = function() return nil end },
    }
    env.package = { loaded = modules, preload = {}, path = "" }
    env.require = function(name)
        if modules[name] ~= nil then return modules[name] end
        assert(not name:match("^boot%."), "test forbids Boot " .. name)
        local result = assert(load(readSource(name), "@sort-menu/" .. name, "t", env))()
        modules[name] = assert(result, "module returned nil " .. name)
        return result
    end
    local Filters = env.require("ui.backpack.BackpackFilters")
    local Affixes = env.require("config.AffixConfig")
    local EC = env.require("config.EquipmentConfig")
    local Secondary = env.require("systems.EquipmentSecondaryStats")
    local before = copy(Affixes)
    local GRID = { FIRST_ROW_TOP = 660, CLIP_BOTTOM = 2120 }
    local function bind(state)
        return Filters.bind({ filters = state, GRID = GRID, sortHint = false,
            getSlot = function() return state.slotFilter end,
            setSlot = function(slot) state.slotFilter = slot end,
            onChange = function() changes = changes + 1 end })
    end
    local state = { sortAscending = false }
    local bar = bind(state)
    check(state.sortKey == nil and not bar.isOpen() and changes == 0, "initial default remains closed and unchanged")
    local expected = { default = true, power = true, quality = true, level = true, ascend = true }
    for _, tpl in pairs(EC.ITEMS) do
        for _, stat in ipairs(tpl.stats or {}) do expected[stat[1]] = true end
    end
    for _, key in ipairs(Secondary.getAttributeKeys()) do expected[key] = true end
    for _, affix in ipairs(Affixes.AFFIXES) do expected[affix.key] = true end
    local options, counts = bar.getOptions("sort"), {}
    for _, option in ipairs(options) do
        counts[option.value] = (counts[option.value] or 0) + 1
        check(not option.label:find("最终", 1, true), "no final caption " .. option.value)
    end
    check(#Affixes.AFFIXES == 45 and #Affixes.CORRUPT_AFFIXES == 13, "45 normal and 13 corrupt definitions remain intact")
    check(#options == 50, "exactly 45 attributes plus five standard modes (previously 63)")
    for key in pairs(expected) do check(counts[key] == 1, "retained exactly once " .. key) end
    for key in pairs(counts) do check(expected[key] == true, "no unexpected menu option " .. key) end
    for _, affix in ipairs(Affixes.AFFIXES) do
        check(counts[affix.key] == 1, "normal attribute including percentages retained " .. affix.key)
    end
    for _, affix in ipairs(Affixes.CORRUPT_AFFIXES) do
        check(counts[affix.key] == nil, "corrupt option removed " .. affix.key)
        local old = { sortKey = affix.key, sortAscending = true, slotFilter = "weapon", typeFilter = "单手剑",
            classFilter = "seal", qualitySet = { [6] = true }, setFilter = { none = true } }
        local wanted = copy(old)
        wanted.sortKey = nil
        local oldBar = bind(old)
        check(same(old, wanted) and oldBar.getState() == old, "old selection resets only sortKey " .. affix.key)
        labels = {}
        oldBar.draw(nil)
        check(labels[3] == "排序 · 默认排序", "trigger has default label instead of stale final marker " .. affix.key)
        check(oldBar.handleInput(295, 524) and oldBar.isOpen(), "old selection can open default menu " .. affix.key)
        oldBar.drawOverlay(nil)
        for _, text in ipairs(labels) do check(not text:find("最终", 1, true), "overlay has no final marker " .. affix.key) end
        oldBar.close()
    end
    check(changes == 0, "binding fallback does not run broad reset/change callbacks")
    -- 所有正常键与五个基础模式均保留当前选择；default 按既有契约可写 nil。
    for key in pairs(expected) do
        local normal = { sortKey = key, sortAscending = true, qualitySet = { [2] = true } }
        local snapshot = copy(normal)
        bind(normal)
        check(same(normal, snapshot), "valid selection preserved " .. key)
    end
    -- 仓库适配器和遗匣通用入口共享选项；各自的状态不会串页。
    local warehouse = { sortKey = "finalHpBonus", sortAscending = true, typeFilter = "单手剑",
        qualitySet = { [3] = true }, setFilter = { none = true }, classFilter = "seal" }
    local warehouseWanted = copy(warehouse)
    warehouseWanted.sortKey = nil
    local warehouseBar = Filters.bindWarehouse(warehouse, GRID, { scrollY = 100 }, {}, {})
    check(same(warehouse, warehouseWanted), "warehouse adapter falls back without clearing other selections")
    check(same(warehouseBar.getOptions("sort"), options), "warehouse and lootbox use identical 50-option menu")
    check(state.sortKey == nil and state.sortAscending == false, "warehouse fallback never affects other menu state")
    -- 真实点击仍可选择普通百分比属性，再选默认；覆盖下拉滚动与稳定 key。
    local function choose(value)
        local index = 0
        for i, option in ipairs(options) do if option.value == value then index = i; break end end
        assert(index > 0, "missing option " .. value)
        assert(bar.handleInput(295, 524) and bar.isOpen(), "open menu")
        bar.handleScroll(#options)
        local scroll = math.max(0, index - 8)
        bar.handleScroll(-scroll)
        bar.handleInput(295, 573 + (index - scroll - 0.5) * 62)
    end
    choose("physAtkBonus")
    check(state.sortKey == "physAtkBonus" and not bar.isOpen(), "normal percentage remains selectable")
    choose("default")
    check(state.sortKey == nil and not bar.isOpen(), "default click clears only sort key")
    check(same(Affixes, before), "menu operations never mutate normal/corrupt affix generation definitions")
    check(ioCalls == 0, "no player persistence IO")
end

function Start()
    local ok, err = pcall(runTests)
    if not ok then check(false, "exception: " .. tostring(err)); log:Write(LOG_ERROR, PREFIX .. tostring(err)) end
    print(string.format("%sassertions=%d failures=%d %s", PREFIX, assertions, failures,
        failures == 0 and "ALL PASS" or "FAILED"))
    engine:Exit()
end
