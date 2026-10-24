-- 真实关闭链专项，供 forge_backpack_layer_test 调用；沿用现有 Start/pcall 测试脚手架。
-- 真实：BlacksmithPage / BlacksmithDraw / BackpackPanel / BackpackEquipLink。
-- 边界：私有Lua环境、CPU绘图spy、空内存Store、网格worker/菜单/锻造子页spy。
-- 只从cache读取上述四个模块的源码；禁止玩家File/存档/网络/动作，未声明依赖直接失败。
local M = {}

local function source(name)
    local file = assert(cache:GetFile(name:gsub("%.", "/") .. ".lua"), name)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

local function fixture()
    local modules = {}
    local env = setmetatable({}, { __index = _G })
    env._G, env.time = env, { elapsedTime = 9 }
    env.package = { loaded = modules, preload = {}, path = "" }
    local counts = { release = 0, close = 0, leave = 0, freeze = 0, cancel = 0,
        forbidden = 0, rightClose = 0, candidateClose = 0, callback = 0, images = 0, draw = 0 }
    local function noop() end
    local function forbidden()
        counts.forbidden = counts.forbidden + 1
        error("forge lifecycle must not access player IO/data/actions")
    end
    env.File, env.FileSystem = forbidden, forbidden
    env.io = setmetatable({}, { __index = function() return forbidden end })
    env.clientCloud, env.serverCloud = false, false
    env.cache = setmetatable({}, { __index = function() return forbidden end })
    env.fileSystem = setmetatable({}, { __index = function() return forbidden end })
    local right = { open = true, heroId = 42, tab = "equip" }
    local candidate = { open = false, owner = nil }
    local grid = { state = {} }
    modules["core.PlayerStore"] = { Get = forbidden, Subscribe = noop, Set = forbidden, Save = forbidden }
    modules["runtime.ClientDispatcher"] = { get = forbidden }
    modules["runtime.GameAction"] = { sendAction = forbidden }
    modules["systems.EquipmentSystem"] = { MAX_INVENTORY = 500, hydrate = forbidden, applyEquip = forbidden }
    modules["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } }
    modules["config.EquipmentConfig"] = { ITEMS = {}, QUALITY = {} }
    modules["config.BlacksmithConfig"] = { QUALITY_COST = {} }
    for _, name in ipairs({ "core.GameState", "config.EquipmentSetConfig", "config.AffixConfig",
        "systems.AttributeDef", "config.ExpTable", "config.HeroConfig", "config.UrGachaConfig",
        "shared.Protocol", "ui.backpack.BackpackItems", "ui.blacksmith.BlacksmithEnhanceCache",
        "ui.widget.EquipmentSetIcon" }) do modules[name] = {} end
    modules["core.I18n"] = { t = function(key) return key end }
    modules["core.NumberUtil"] = { format = tostring }
    modules["core.DrawUtil"] = { drawImageCentered = noop, drawTextStroke = noop, drawNineSlice = noop,
        seamSlideX = function() return 0 end }
    modules["core.DarkIcon"] = { QUALITY_TRIM = {}, drawNine = noop }
    modules["ui.widget.ImageCache"] = { init = noop }
    modules["ui.widget.QualityMark"] = { init = noop }
    modules["ui.widget.HeroFrame"] = { initImages = noop }
    modules["config.HeroAssetUtil"] = { preloadIcons = noop }
    modules["ui.widget.SetFilterDialog"] = { close = noop, isOpen = function() return false end }
    modules["ui.character.panel.CharacterPanel"] = {}
    modules["ui.character.detail.CharacterDetail"] = {
        isOpen = function() return right.open end,
        isEquipTab = function() return right.open and right.tab == "equip" end,
        getHeroId = function() return right.heroId end,
        close = function() counts.rightClose = counts.rightClose + 1; right.open = false end,
        forceClose = function() counts.rightClose = counts.rightClose + 1; right.open = false end,
    }
    modules["ui.character.equip.EquipmentDetail"] = {
        init = noop, isOpen = function() return candidate.open end,
        getOwner = function() return candidate.owner end,
        close = function() counts.candidateClose = counts.candidateClose + 1; candidate.open = false end,
        dismissHover = noop,
    }
    modules["ui.town.TownPageChrome"] = {
        easeOutCubic = function(t) return t end, easeInCubic = function(t) return t end,
        easeInOutCubic = function(t) return t end, drawNamePlate = noop, drawTabBar = noop,
    }
    modules["systems.GameSFX"] = { playUIMove = noop }
    modules["systems.TutorialManager"] = { isActive = function() return false end }
    modules["systems.StoryPlayer"] = { onPlace = function(place, action)
        assert(place == "smith" and action == "leave", "unexpected story transition")
        counts.leave = counts.leave + 1
    end }
    modules["ui.fx.SpineResultEffect"] = { preload = noop, isPlaying = function() return false end }
    modules["ui.blacksmith.BlacksmithEnhance"] = {
        setContext = noop, init = noop, clearKeywords = noop, onOpen = noop, drawConfirmDialog = noop,
    }
    modules["ui.blacksmith.BlacksmithRefine"] = {
        setContext = noop, init = noop, clearKeywords = noop, clearHover = noop,
    }
    modules["ui.blacksmith.BlacksmithDecompose"] = {
        cancelMarquee = noop, setContext = noop, init = noop, applyProfile = noop,
    }
    modules["ui.loot.InventoryCurationDialog"] = { cancelSource = noop }
    modules["systems.ButtonFeedback"] = {}
    modules["ui.backpack.BackpackGridHost"] = { bind = function(deps)
        grid.state = deps.state
        return { cancel = function() counts.cancel = counts.cancel + 1 end,
            freezeForClose = function() counts.freeze = counts.freeze + 1 end,
            update = noop, clampScroll = noop, getEquipList = function() return {} end,
            buildItemList = function() return {} end }
    end }
    modules["ui.backpack.BackpackFilters"] = { attachInput = noop, bindWarehouse = function()
        return { init = noop, close = noop }
    end }
    modules["ui.backpack.BackpackDialogs"] = { bind = function() return { closeTransferConfirm = noop } end }
    modules["ui.backpack.BackpackWindow"] = { bind = function() return noop, noop end }
    modules["ui.backpack.BackpackActionResult"] = { bind = function() return forbidden end }
    for _, name in ipairs({ "ui.loot.LootBoxPage", "ui.story.task.TaskPage", "ui.church.talent.TalentPage",
        "ui.church.ChurchPage", "ui.tavern.TavernPage", "ui.market.MarketPage" }) do
        modules[name] = { isOpen = function() return false end, resetHorizonLayout = noop }
    end
    for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgTranslate", "nvgBeginPath", "nvgRect",
        "nvgRoundedRect", "nvgFillColor", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke",
        "nvgFontFace", "nvgFontSize", "nvgTextAlign", "nvgIntersectScissor", "nvgResetScissor" }) do
        env[name] = noop
    end
    env.nvgText = function() counts.draw = counts.draw + 1 end
    env.nvgRGBA = function() return {} end
    env.nvgCreateImage = function() counts.images = counts.images + 1; return -1 end
    local real = { ["ui.blacksmith.BlacksmithPage"] = true, ["ui.blacksmith.BlacksmithDraw"] = true,
        ["ui.backpack.BackpackPanel"] = true, ["ui.backpack.BackpackEquipLink"] = true }
    env.require = function(name)
        if modules[name] ~= nil then return modules[name] end
        assert(real[name], "undeclared forge lifecycle dependency: " .. name)
        local value = assert(load(source(name), "@forge-lifecycle/" .. name, "t", env))()
        modules[name] = assert(value, name)
        return value
    end
    local warehouse = env.require("ui.backpack.BackpackPanel")
    local smith = env.require("ui.blacksmith.BlacksmithPage")
    -- 只在公开入口外计数，内部仍完整执行真实release/onManualClose/closePage。
    local release, close = warehouse.releaseWarehouse, warehouse.close
    warehouse.releaseWarehouse = function(owner)
        if owner == "blacksmith" then counts.release = counts.release + 1 end
        return release(owner)
    end
    warehouse.close = function()
        counts.close = counts.close + 1
        return close()
    end
    warehouse.init({})
    smith.init({})
    local f = { smith = smith, warehouse = warehouse, counts = counts, env = env,
        right = right, candidate = candidate, grid = grid }
    function f.at(t) env.time.elapsedTime = t end
    function f.frame(t, warehouseFirst)
        f.at(t)
        if warehouseFirst then warehouse.update(0.016) end
        smith.draw({})
        if not warehouseFirst then warehouse.update(0.016) end
    end
    function f.watchClose()
        smith.setOnCloseCallback(function() counts.callback = counts.callback + 1 end)
    end
    return f
end

function M.run(check)
    -- closeTime=10避免100+.38相减的浮点下溢；真实边界仍是严格的0.379/0.38。
    for _, manual in ipairs({ false, true }) do
        for _, warehouseFirst in ipairs({ false, true }) do
            local f = fixture()
            local s, w, c = f.smith, f.warehouse, f.counts
            if manual then w.open("left", "item"); f.grid.state.scrollY = 155 end
            s.open()
            check(s.isOpen() and w.isOpen() and w.isLeftMode(), "真实锻炉open取得真实左仓库 manual=" .. tostring(manual))
            check(f.grid.state.tab == "equip", "真实equipLink切换至装备tab")
            f.frame(9.75, warehouseFirst)
            check(c.draw > 0, "真实BlacksmithDraw已通过CPU绘图spy执行")
            -- 人工滚到当前装备视图中部；手动仓库原视图是item/155，关闭不能restore它。
            f.grid.state.scrollY, f.grid.state.scrollMax = 417, 900
            f.candidate.open, f.candidate.owner = true, "backpack"
            f.watchClose()
            f.at(10)
            s.close()
            local _, smithClose, _, smithDuration = s.getSeamAnim()
            local _, warehouseClose, _, warehouseDuration = w.getSeamAnim()
            check(s.isClosing() and f.grid.state.closing and s.isOpen() and w.isOpen(),
                "close入口两页同帧开始动画，不等待绘制或Update")
            check(smithClose == 10 and warehouseClose == smithClose and smithDuration == 0.38
                and warehouseDuration == smithDuration, "真实两页closeTime与0.38时长完全相同")
            check(c.release == 1 and c.leave == 1 and c.callback == 0,
                "仓库release发生在close边沿，完成回调尚未触发")
            check(f.grid.state.tab == "equip" and f.grid.state.scrollY == 417,
                "关闭手动仓库不先恢复原item页/滚动，退场保持当前装备视图")
            check(not f.candidate.open and c.candidateClose > 0, "真实release清理仓库持有的候选浮层")
            check(f.right.open and f.right.heroId == 42 and f.right.tab == "equip" and c.rightClose == 0,
                "关闭锻炉不得关闭/换页右侧角色详情")
            f.at(10.125)
            s.close()
            check(c.release == 1 and c.leave == 1 and select(2, s.getSeamAnim()) == 10
                and select(2, w.getSeamAnim()) == 10, "重复close幂等，不重复release、不重置任一页closeTime")
            f.frame(10.379, warehouseFirst)
            check(s.isOpen() and s.isClosing() and w.isOpen() and f.grid.state.closing and c.callback == 0,
                "同0.38完成前两页均保留关闭动画")
            f.frame(10.38, warehouseFirst)
            check(not s.isOpen() and not s.isClosing() and not w.isOpen() and not f.grid.state.closing,
                "同0.38完成两页均已关闭（两种Update/Draw顺序）")
            check(c.release == 1 and c.callback == 1, "动画完成只触发一次锻炉回调，不延迟release")
            f.frame(11, warehouseFirst)
            s.close()
            check(c.release == 1 and c.leave == 1 and c.callback == 1, "完成后重复绘制/close仍幂等")
            check(c.forbidden == 0, "真实关闭链无玩家数据/存档/事务访问")
        end
    end

    -- 旧锻炉仍在退场时新开仓库：完成帧不能二次release/close新会话。
    for _, reopen in ipairs({ "manual", "equipment", "smith" }) do
        local f = fixture()
        local s, w, c = f.smith, f.warehouse, f.counts
        s.open()
        f.at(10); f.watchClose(); s.close()
        f.at(10.125)
        if reopen == "manual" then w.open("left", "item")
        elseif reopen == "equipment" then w.acquireForEquipment(42, "helmet")
        else s.open() end
        local warehouseOpen = w.getSeamAnim()
        local released, closed = c.release, c.close
        f.frame(10.38)
        check(w.isOpen() and not f.grid.state.closing and w.getSeamAnim() == warehouseOpen,
            "旧关闭完成不误关/重置新开仓库 reopen=" .. reopen)
        if reopen == "smith" then
            check(s.isOpen() and not s.isClosing() and c.callback == 0,
                "关闭中重入锻炉取消旧退场，不触发旧完成回调")
            f.at(11); s.close()
            check(c.release == released + 1 and f.grid.state.closing
                and select(2, w.getSeamAnim()) == 11, "重入锻炉确实重新取得owner，下一次close同帧释放")
        else
            check(not s.isOpen() and c.callback == 1 and c.release == released and c.close == closed,
                "旧锻炉完成只收尾自身，不释放后来仓库持有者")
            if reopen == "equipment" then
                local slot, hero = w.getEquipmentSlotFilter()
                check(slot == "helmet" and hero == 42, "旧锻炉完成保留新配装owner与筛选上下文")
                w.releaseForEquipment()
                check(f.grid.state.closing, "新配装owner最后释放正常关仓，旧blacksmith owner没有泄漏")
            end
        end
        check(f.right.open and c.rightClose == 0 and c.forbidden == 0, "重入不影响右侧角色且不访问真实存档")
    end

    -- 配装筛选仍带hero/slot时close再release清筛选也不可重置退场滚动。
    do
        local f = fixture()
        local s, w = f.smith, f.warehouse
        s.open()
        w.setEquipmentSlotFilter("helmet", 42)
        f.grid.state.scrollY, f.grid.state.scrollMax = 533, 900
        f.at(10); s.close()
        local slot, hero = w.getEquipmentSlotFilter()
        check(slot == nil and hero == nil and f.grid.state.closing and f.grid.state.scrollY == 533,
            "close中release清除临时筛选，但不把装备退场位置跳回顶部")
        f.frame(10.379)
        check(f.grid.state.scrollY == 533, "真实update保持清筛选后的退场滚动")
    end

    -- 两个真实owner同时在场：锻炉双页close也关闭手动/配装共用左仓，但不关闭右角色。
    do
        local f = fixture()
        local s, w = f.smith, f.warehouse
        w.acquireForEquipment(42, "weapon")
        s.open()
        f.at(10); s.close()
        check(w.isOpen() and f.grid.state.closing and select(2, w.getSeamAnim()) == 10,
            "配装仍持有左仓时锻炉双页close仍同步关闭左仓")
        check(f.right.open and f.right.tab == "equip" and f.counts.rightClose == 0,
            "共用仓库关闭不反向关闭仍在配装的右侧角色")
        f.frame(10.38)
        w.acquireWarehouse("equipment", 42, "armor")
        check(not w.isOpen(), "同次配装普通重复申请尊重刚才关仓，不被Update强制弹回")
    end

    -- 单独隐藏仓库是单向操作：不反向关闭锻炉，也不允许重复申请撤销隐藏。
    do
        local f = fixture()
        local s, w, c = f.smith, f.warehouse, f.counts
        s.open(); f.watchClose(); f.at(10); w.close()
        check(s.isOpen() and not s.isClosing() and c.release == 0 and c.leave == 0,
            "单独close仓库不关闭锻炉，不释放锻炉owner")
        check(w.acquireForBlacksmith() == false and f.grid.state.closing,
            "已持有锻炉的重复申请尊重手动关仓")
        f.frame(10.38)
        check(s.isOpen() and not s.isClosing() and not w.isOpen() and c.callback == 0,
            "仓库动画完成后锻炉保持打开")
        f.at(11); s.close()
        check(s.isClosing() and not w.isOpen() and c.release == 1,
            "已隐藏仓库时关闭锻炉仍释放owner，不重新弹出仓库")
        f.frame(11.38)
        check(not s.isOpen() and not w.isOpen() and c.callback == 1 and c.forbidden == 0,
            "隐藏仓库后的锻炉关闭正常完成")
    end

    -- forceClose保持原释放语义：不新增双页手动关闭；与正常close的修改范围分开。
    for _, manual in ipairs({ false, true }) do
        local f = fixture()
        local s, w, c = f.smith, f.warehouse, f.counts
        if manual then w.open("left", "item") end
        s.open(); f.at(10); s.forceClose()
        check(not s.isOpen() and c.release == 1 and c.close == 0 and c.callback == 0,
            "forceClose仍只执行原release，不走双页close或完成回调")
        check(w.isOpen() and f.grid.state.closing == (not manual),
            "forceClose保留手动仓库，自动仓库按原release关闭 manual=" .. tostring(manual))
        s.forceClose()
        check(c.release == 1 and c.forbidden == 0, "forceClose重复调用不重复release/访问存档")
    end
end

return M
