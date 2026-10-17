-- 基于scaffold-2d生命周期的真实大列表详情验收；所有业务模块在私有环境加载，不启动main或玩家档。
-- 36条离线回执，完整装备在equip内；固定时间/固定数据，不抽装备、不消费随机数。
local nativeRequire, nativeCache = require, cache
---@type NVGContextWrapper?
local vg = nil
local popup = {}
local modules, texts, rewards = {}, {}, {}
local clock = { elapsedTime = 100 }
local frames, ioAttempts, actions, errors = 0, 0, 0, 0
local initial = ""
local env = setmetatable({}, { __index = _G })
env._G, env.time = env, clock
local function fingerprint(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local parts = {}
    for key, child in pairs(value) do parts[#parts + 1] = fingerprint(key) .. "=" .. fingerprint(child) end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end
local function forbidden()
    ioAttempts = ioAttempts + 1
    error("奖励显示验收禁止访问玩家档", 0)
end
env.File = forbidden
env.fileSystem = setmetatable({}, { __index = function() return forbidden end })
env.clientCloud, env.serverCloud, env.network = env.fileSystem, env.fileSystem, env.fileSystem
-- 套装详情只读取空的内存装备表，其他Store入口/真实存档仍禁止访问。
modules["core.PlayerStore"] = setmetatable({ Get = function(key)
    assert(key == "equipment", "预览只允许查询内存装备表")
    return { inventory = {}, heroSlots = {} }
end }, { __index = function() return forbidden end })
modules["runtime.GameAction"] = { sendAction = function() actions = actions + 1; error("禁止奖励动作", 0) end }
modules["systems.GameSFX"] = { play = function() end }
modules["ui.hud.popup.SettingsPanel"] = { isSetIconsEnabled = function() return true end }
env.nvgText = function(ctx, x, y, text, ...)
    texts[tostring(text)] = (texts[tostring(text)] or 0) + 1
    return nvgText(ctx, x, y, text, ...)
end
env.require = function(name)
    if modules[name] then return modules[name] end
    if name:find("^urhox%-libs") or name == "cjson" then return nativeRequire(name) end
    local path = name:gsub("%.", "/") .. ".lua"
    local file = assert(nativeCache:GetFile(path), "缺少源码 " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    local placeholder = {}; modules[name] = placeholder
    local value = assert(load(table.concat(lines, "\n"), "@奖励详情验收:" .. path, "t", env))()
    if type(value) == "table" then
        for key, child in pairs(value) do placeholder[key] = child end
        setmetatable(placeholder, getmetatable(value))
        return placeholder
    end
    modules[name] = value
    return value
end
function Start()
    vg = assert(nvgCreate(1))
    assert(nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf") >= 0)
    local config = env.require("config.EquipmentConfig")
    local query = env.require("systems.EquipmentQuery")
    local templateId = nil ---@type string|number|nil
    for id, item in pairs(config.ITEMS) do
        if item.name == "羽制耳环" then templateId = id; break end
    end
    assert(templateId, "羽制耳环模板必须存在")
    local equip = query.hydrateCopy({ templateId = templateId, quality = 5, level = 66,
        id = "offline-preview-earring", affixes = { { affixId = 1, quality = 3, value = 7 } } })
    rewards[1] = { type = "equip", templateId = templateId, quality = 5, level = 66,
        amount = 1, destination = "lootbox", equip = equip }
    local ids = { "W1", "W7", "W13", "A1", "A7", "C1", "C7" }
    for i = 2, 36 do
        local id = ids[(i - 2) % #ids + 1]
        rewards[i] = { type = "equip", templateId = id, quality = 4, level = 47, amount = 1,
            destination = "lootbox", equip = query.hydrateCopy({ templateId = id, quality = 4, level = 47, affixes = {} }) }
    end
    initial = fingerprint(rewards)
    env.require("core.I18n").set("zh_CN")
    env.require("ui.character.equip.EquipmentDetail").init(vg)
    popup = env.require("ui.hud.popup.RewardPopup")
    popup.init(vg)
    popup.show("离线装备已入遗匣", rewards, { cascade = false })
    clock.elapsedTime = 101
    popup.update(1)
    SubscribeToEvent(vg, "NanoVGRender", "HandleOfflineTooltipPreview")
    print("[offline-tooltip-preview] 初始化36件真实包装；选中羽制耳环")
end
function HandleOfflineTooltipPreview()
    local ctx = vg
    if not ctx then return end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(ctx, width, height, dpr)
    nvgBeginPath(ctx); nvgRect(ctx, 0, 0, width, height)
    nvgFillColor(ctx, nvgRGBA(14, 17, 22, 255)); nvgFill(ctx)
    texts = {}
    local ok, why = xpcall(function() popup.drawLarge(ctx, width, height) end, debug.traceback)
    nvgEndFrame(ctx)
    if not ok then errors = errors + 1; print("[offline-tooltip-preview] FAIL " .. tostring(why)); engine:Exit(); return end
    frames = frames + 1
    if frames == 120 then
        local pass = texts["羽制耳环"] and texts["耳环"] and texts["魔法攻击力"]
            and not texts["???"] and not texts["equip"] and fingerprint(rewards) == initial
            and ioAttempts == 0 and actions == 0 and errors == 0
        print("[offline-tooltip-preview] " .. (pass and "ALL PASS" or "FAIL")
            .. " name=" .. tostring(texts["羽制耳环"]) .. " type=" .. tostring(texts["耳环"])
            .. " attribute=" .. tostring(texts["魔法攻击力"]) .. " io=" .. ioAttempts .. " actions=" .. actions)
    end
end
function Stop()
    if vg then nvgDelete(vg); vg = nil end
end
