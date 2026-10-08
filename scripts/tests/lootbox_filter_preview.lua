-- 基于 scaffold-2d 的 Start/Update/Stop 与官方 NanoVGRender 宿主帧。
-- 真实遗匣Page/通用筛选条/属性菜单绘制；私有require环境禁止Boot、玩家File和持久化。
-- Runtime截图写外部验证目录；-lootbox-preview=page|menu，125帧自动退出。
local mode = "menu"
for _, argument in ipairs(GetArguments()) do
    mode = argument:match("^%-lootbox%-preview=(.+)$") or mode
end
local vg = nil ---@type NVGContextWrapper?
local page, bar, viewport = {}, {}, {} ---@type table, table, table
local source, snapshot = {}, {} ---@type table[], table[]
local frames, rendered, fileCalls, actions = 0, 0, 0, 0
local errors = {} ---@type string[]

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function check(value, name)
    if not value then errors[#errors + 1] = name end
end
local function sourceText(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), "缺少真实源码 " .. name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

function Start()
    local ok, err = pcall(function()
        -- 与SweepRegressionFixture同样的私有require沙箱，但不加载扫荡或正式Boot。
        local env = setmetatable({}, { __index = _G })
        env._G, env.time = env, { elapsedTime = 100 }
        env.File = function() fileCalls = fileCalls + 1; error("遗匣预览禁止玩家File") end
        env.fileSystem = setmetatable({}, { __index = function()
            return function() fileCalls = fileCalls + 1; error("遗匣预览禁止玩家filesystem") end
        end })
        local modules = {
            ["systems.GameSFX"] = { playUIMove = function() end, playUIClick = function() end },
            ["core.PlayerStore"] = { Get = function() return nil end },
            ["runtime.ClientDispatcher"] = { get = function() return nil end },
        }
        env.package = { loaded = modules, preload = {}, path = "" }
        env.require = function(name)
            if modules[name] ~= nil then return modules[name] end
            assert(not name:match("^boot%."), "预览禁止加载正式Boot " .. name)
            if name == "cjson" then return cjson end
            if name:match("^urhox%-libs") then return require(name) end
            local value = assert(load(sourceText(name), "@lootbox-preview/" .. name, "t", env))()
            assert(value ~= nil, "真实模块缺少返回值 " .. name)
            modules[name] = value
            return value
        end
        local filters = env.require("ui.backpack.BackpackFilters")
        local bind = filters.bind
        filters.bind = function(deps) bar = bind(deps); return bar end
        page = env.require("ui.loot.LootBoxPage")
        viewport = env.require("core.Viewport")
        vg = assert(nvgCreate(1), "真实NanoVG上下文")
        assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0, "真实宿主中文字体")
        page.init(vg)
        for index = 1, 12 do
            source[index] = { sourceIndex = index, count = 1,
                equip = { templateId = index % 2 == 0 and "W13" or "W1", quality = index % 2 == 0 and 5 or 6,
                    level = 35 + index, ascendLevel = index % 6,
                    affixes = { { affixId = 1, value = index * 2, ascBonus = 1 } }, affixMult = 1.5 } }
        end
        source[#source + 1] = { count = 2 }
        snapshot = copy(source)
        local function noAction() actions = actions + 1; error("预览禁止领取/回收") end
        page.setOnClaimOne(noAction); page.setOnClaimAll(noAction)
        page.setOnDecomposeOne(noAction); page.setOnDecomposeAll(noAction)
        page.open(source)
        env.time.elapsedTime = 101 -- 冻结已完成的开窗动画，不依赖玩家时钟。
        local options = bar.getOptions("sort")
        local wanted = 0
        for index, option in ipairs(options) do if option.value == "str" then wanted = index break end end
        assert(wanted > 0, "属性菜单包含力量")
        page.handleInput(295, 524)
        page.handleScroll(10000)
        local scroll = math.max(0, wanted - 8)
        page.handleScroll(-scroll)
        page.handleInput(295, 573 + (wanted - scroll - 0.5) * 62)
        assert(bar.getState().sortKey == "str", "通过真实菜单设置属性排序")
        if mode == "menu" then page.handleInput(295, 524) end
        SubscribeToEvent("Update", "LootboxFilterPreviewUpdate")
        SubscribeToEvent(vg, "NanoVGRender", "LootboxFilterPreviewRender")
        print("[lootbox_filter_preview] START real Page + Viewport left mode=" .. mode)
    end)
    if not ok then
        errors[#errors + 1] = tostring(err)
        log:Write(LOG_ERROR, "[lootbox_filter_preview] Start " .. tostring(err))
        engine:Exit()
    end
end

function LootboxFilterPreviewUpdate()
    frames = frames + 1
    if frames >= 125 then engine:Exit() end
end
function LootboxFilterPreviewRender()
    if not vg then return end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    -- nvg-resolution-mode A：1920×1080 contain，DPR只交给BeginFrame，真实左栏宿主变换。
    local scale = math.min(width / 1920, height / 1080)
    nvgBeginFrame(vg, width, height, dpr)
    nvgSave(vg)
    nvgTranslate(vg, (width - 1920 * scale) / 2, (height - 1080 * scale) / 2)
    nvgScale(vg, scale, scale)
    nvgBeginPath(vg); nvgRect(vg, 0, 0, 1920, 1080)
    nvgFillColor(vg, nvgRGBA(12, 13, 17, 255)); nvgFill(vg)
    local ox, oy, fit = viewport.layout(1920, 1080)
    viewport.begin(vg, viewport.PANELS.left, ox, oy, fit)
    local ok, err = xpcall(function() page.draw(vg); rendered = rendered + 1 end, debug.traceback)
    if not ok then
        errors[#errors + 1] = tostring(err)
        log:Write(LOG_ERROR, "[lootbox_filter_preview] Render " .. tostring(err))
        engine:Exit()
    end
    viewport.finish(vg)
    nvgRestore(vg)
    nvgEndFrame(vg)
end
function Stop()
    check(rendered > 0, "真实Page没有渲染")
    check(equal(source, snapshot), "预览改写来源装备")
    check(fileCalls == 0 and actions == 0, "预览发生玩家IO或领取回收")
    if page.forceClose then page.forceClose() end
    if vg then nvgDelete(vg); vg = nil end
    print(string.format("[lootbox_filter_preview] SUMMARY mode=%s frames=%d rendered=%d failures=%d file=%d actions=%d",
        mode, frames, rendered, #errors, fileCalls, actions))
    for _, err in ipairs(errors) do log:Write(LOG_ERROR, "[lootbox_filter_preview] " .. err) end
end
