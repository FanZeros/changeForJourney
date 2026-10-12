-- 装备操作性能回归：真实数据分发/升阶业务，隔离 UI 与文件系统，不接触玩家存档。
local TAG = "[equipment_operation_performance_test]"

local function source(path)
    local file = assert(cache:GetFile(path), "缺少测试源码: " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

function Start()
    local assertions = 0
    local function check(condition, label)
        assertions = assertions + 1
        assert(condition, label)
    end
    local ok, err = xpcall(function()
        local Dispatcher = require("runtime.ClientDispatcher")
        local Store = require("core.PlayerStore")
        local Eq = require("systems.EquipmentSystem")
        local EC = require("config.EquipmentConfig")
        local PDM = require("rules.character.PlayerDataManager")
        local Task = require("rules.task.TaskService")
        local Protocol = require("shared.Protocol")
        local Schema = require("shared.schemas.CharacterSchema")
        Dispatcher.reset()
        Store.Cleanup()
        Store.Init()

        local equipment = { inventory = {}, equipped = { [1] = { weapon = 1 } }, nextSeq = 1001 }
        for seq = 1, 1000 do
            local item = assert(Eq.generate(seq % 2 == 0 and "O1" or "W1", 1, 1))
            item.seq = seq
            equipment.inventory[tostring(seq)] = item
        end
        local hydrateCalls = 0
        local nativeHydrate = Eq.hydrateInventory
        Eq.hydrateInventory = function(inventory)
            hydrateCalls = hydrateCalls + 1
            return nativeHydrate(inventory)
        end
        Dispatcher.set("equipment", equipment)
        check(hydrateCalls == 2, "外部导入仍保留两套兼容加载")
        local oldRevision = Store.GetRevision("equipment")
        local inventory, equipped = equipment.inventory, equipment.equipped
        local notifications, globalUpdates = 0, 0
        Dispatcher.subscribe("equipment", function(data)
            notifications = notifications + 1
            check(data == equipment, "已规范模块通知保留同源表")
        end)
        Dispatcher.setOnAnyUpdate(function(modules)
            if modules.equipment then globalUpdates = globalUpdates + 1 end
        end)
        hydrateCalls = 0
        equipment.inventory["1"].ascendLevel = 1
        Dispatcher.set("equipment", equipment, { normalized = true })
        check(hydrateCalls == 0, "运行态更新不水合1000件库存")
        check(equipment.inventory == inventory and equipment.equipped == equipped, "更新不替换库存/穿戴映射")
        check(Store.GetRevision("equipment") > oldRevision, "原地更新仍提升派生版本")
        check(notifications == 1 and globalUpdates == 1, "模块订阅和全局UI仍各通知一次")
        Eq.hydrateInventory = nativeHydrate

        -- 真正动作桥只替换显示和GameState边界；升阶Handler/Service/PDM使用生产模块。
        local state = { name = "测试", level = 60, exp = 0, maxExp = 100, power = 1000 }
        local currency = { gold = 10 ^ 9, essence = 10000, weaponScroll = 10000,
            offhandScroll = 10000, armorScroll = 10000, helmetScroll = 10000,
            shoesScroll = 10000, accessoryScroll = 10000 }
        local fakeState = {}
        for _, field in ipairs({ "name", "level", "exp", "maxExp", "power" }) do
            fakeState["get" .. field:sub(1, 1):upper() .. field:sub(2)] = function() return state[field] end
        end
        for field in pairs(Schema.Fields.currency.getDefault()) do
            local key = field
            fakeState["get" .. key:sub(1, 1):upper() .. key:sub(2)] = function() return currency[key] or 0 end
        end
        fakeState.setLocalPlayerSync = function(fn) fakeState.playerSync = fn end
        fakeState.syncFromCurrency = function(data)
            for key, value in pairs(data) do currency[key] = value end
        end
        fakeState.syncPlayerData = function(data)
            for _, field in ipairs({ "name", "level", "exp", "maxExp", "power" }) do
                if data[field] ~= nil then state[field] = data[field] end
            end
            fakeState.playerSync(state)
        end
        local results = {}
        local fakeMsg = { handleActionResult = function(result) results[#results + 1] = result end }
        local env = setmetatable({}, { __index = _G })
        env.require = function(name)
            if name == "core.GameState" then return fakeState end
            if name == "runtime.ClientMessageHandler" then return fakeMsg end
            if name:match("^rules%..*Handler$") and name ~= "rules.blacksmith.BlacksmithHandler" then return {} end
            if name == "rules.redeem.RedeemService" then return { Init = function() end } end
            return require(name)
        end
        local bridge = assert(load(source("runtime/LocalActionBridge.lua"), "@runtime/LocalActionBridge.lua", "t", env))()
        Dispatcher.set("player", state)
        Dispatcher.set("currency", currency)
        equipment.inventory["1"].ascendLevel, equipment.inventory["1"].enhanceLevel = 0, 0
        bridge.init()
        local playerPushes = 0
        Dispatcher.subscribe("player", function() playerPushes = playerPushes + 1 end)
        bridge.syncPlayerIntoPdm()
        bridge.syncPlayerIntoPdm()
        check(playerPushes == 0, "无变化玩家镜像不重复推送")
        state.exp = 1
        bridge.syncPlayerIntoPdm(state)
        check(playerPushes == 1 and PDM.GetModule(1, "player").exp == 1, "共享表原地经验变更仍通知")
        bridge.syncPlayerIntoPdm(state)
        check(playerPushes == 1, "重复经验镜像只通知一次")
        hydrateCalls = 0
        Eq.hydrateInventory = function(inv) hydrateCalls = hydrateCalls + 1; return nativeHydrate(inv) end
        local nativeTask = Task.UpdateProgress
        Task.UpdateProgress = function() end
        local beforeGold = currency.gold
        check(bridge.dispatch(Protocol.ACTION_TYPES.ENHANCE_EQUIP, { seq = 1 }), "正式升阶请求被处理")
        check(#results == 1 and results[1].success == true, "正式升阶成功回执")
        check(Eq.getAscendLevel(equipment.inventory["1"]) == 1 and currency.gold < beforeGold, "等级和扣费已提交")
        check(hydrateCalls == 0, "真实升阶发布不触发全库存加载")
        check(playerPushes == 1, "升阶前玩家镜像没有额外推送")
        local revisionBeforeAvatar = Store.GetRevision("player")
        Dispatcher.get("player").avatarHeroId = 2
        bridge.syncPlayerIntoPdm()
        check(playerPushes == 2 and Store.GetRevision("player") > revisionBeforeAvatar,
            "五标量不变时规则层原地改头像仍发布通知")
        bridge.syncPlayerIntoPdm()
        check(playerPushes == 2, "头像镜像无变化不重复通知")
        Eq.hydrateInventory, Task.UpdateProgress = nativeHydrate, nativeTask

        -- 网格仅隔离评分以精确统计调用次数，筛选/排序/真实模板及版本来自生产模块。
        local scores = 0
        local scoreStub = { score = function(item) scores = scores + 1; return Eq.getAscendLevel(item) end,
            getContext = function() return {} end,
            evaluate = function() return { valid = true, gain = 1 } end }
        local gridsEnv = setmetatable({}, { __index = _G })
        local empty = { get = function() return -1 end }
        gridsEnv.require = function(name)
            if name == "systems.EquipmentPower" then return scoreStub end
            if name == "ui.character.panel.CharacterPanel" or name == "ui.widget.HeroFrame"
                or name == "ui.widget.EquipmentSetIcon" or name == "core.DarkIcon"
                or name == "core.DrawUtil" or name == "ui.widget.ImageCache" then return empty end
            return require(name)
        end
        local gridModule = assert(load(source("ui/backpack/BackpackGrids.lua"), "@ui/backpack/BackpackGrids.lua", "t", gridsEnv))()
        local filterState = { qualitySet = {}, setFilter = {} }
        local slotFilter, heroId = nil, nil
        local Sets = require("config.EquipmentSetConfig")
        local grids = gridModule.bind({ GRID = {}, CELL_COL_CX = {}, DESIGN_W = 1080,
            state = {}, decomposeState = filterState,
            qualityChecked = function(q) return not next(filterState.qualitySet) or filterState.qualitySet[q] end,
            setChecked = function(id)
                if not next(filterState.setFilter) then return true end
                return filterState.setFilter[Sets.getSetIdForTemplate(EC.ITEMS[id]) or "none"] == true
            end,
            getEquipmentSlotFilter = function() return slotFilter, heroId end })
        local list = grids.getEquipList()
        check(#list == 1000 and scores == 1000, "首建完整库存评分一次")
        for _ = 1, 120 do check(grids.getEquipList() == list, "绘制/命中复用同一列表") end
        check(scores == 1000, "120帧稳态不重复1000件评分")
        equipment.inventory["1"].locked = true
        Dispatcher.set("equipment", equipment, { normalized = true })
        local nextList = grids.getEquipList()
        check(nextList ~= list and scores == 2000, "同引用锁定更新按revision重建")
        local foundLocked = false
        for _, item in ipairs(nextList) do if item.seq == 1 then foundLocked = item.locked == true end end
        check(foundLocked, "缓存更新呈现最新锁状态")
        slotFilter = "weapon"
        check(#grids.getEquipList() == 500, "部位筛选实时失效")
        filterState.qualitySet[2] = true
        check(#grids.getEquipList() == 0, "原地品质勾选实时失效")
        filterState.qualitySet = {}
        filterState.setFilter.none = true
        check(#grids.getEquipList() > 0, "原地套装勾选实时失效")
        heroId = 1
        check(grids.getEquipList() ~= nextList, "英雄上下文切换实时失效")
        local beforeRevisionScores = scores
        Dispatcher.set("artifacts", { bag = {}, equipped = {} }, { normalized = true })
        grids.getEquipList()
        check(scores > beforeRevisionScores, "神器版本变化重建评分")
        Store.ClearCache()
        check(#grids.getEquipList() == 0, "清档后不借旧玩家列表")
        print(TAG .. " 大库存=1000，升阶全库存水合=0，120帧重复评分=0")
    end, debug.traceback)
    if not ok then error(TAG .. " FAIL " .. tostring(err), 0) end
    print(TAG .. " ALL PASS assertions=" .. assertions)
    if engine then engine:Exit() end
end
