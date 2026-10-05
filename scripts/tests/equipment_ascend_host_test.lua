-- 主入口真实Update/Render中的升阶联动探针，不读取或写入玩家存档。
local TAG = "[equipment_ascend_host_test]"
local frame = 0
local updateFailures, renderFailures, requestCount, successCount = 0, 0, 0, 0
local battleTicks, backpackTicks, battleDraws, backpackDraws = 0, 0, 0, 0
local milestones = { [50] = 1, [80] = 25, [110] = 100 }
---@type string|nil
local firstError = nil
local finalUpdateMs = {}
local cardLoadRequests, finalCardLoadRequests = 0, 0

function Start()
    local Dispatcher = require("runtime.ClientDispatcher")
    local Equipment = require("systems.EquipmentSystem")
    local GameState = require("core.GameState")
    local Save = require("boot.StandaloneSave")
    -- 测试专用持久化边界：仍执行正式Update编码/防抖，不允许读旧档或写档。
    Save.RestoreData = function() return false end
    local nativeFile = File
    File = function(path, mode)
        if mode == FILE_WRITE then return nil end
        return nativeFile(path, mode)
    end
    local heroes = { roster = {}, deployed = { 1, 2, 9 }, teams = {
        [2] = { slots = { 3, 4, 5 } }, [3] = { slots = { 6, 7, 8 } },
    } }
    for id = 1, 25 do
        heroes.roster[id] = { level = 100, exp = 0, shards = 0, awakening = {}, extraTalent = {} }
    end
    local item = assert(Equipment.generate("W1", 85, 6))
    item.seq = 1
    local equipment = { inventory = { ["1"] = item }, equipped = { [1] = { weapon = 1 } }, nextSeq = 2 }
    local currency = { gold = 10 ^ 12, essence = 10 ^ 8,
        weaponScroll = 10 ^ 6, offhandScroll = 10 ^ 6, armorScroll = 10 ^ 6,
        helmetScroll = 10 ^ 6, shoesScroll = 10 ^ 6, accessoryScroll = 10 ^ 6 }
    Dispatcher.set("player", { level = 100, exp = 0, maxExp = 100 })
    Dispatcher.set("heroes", heroes)
    Dispatcher.set("equipment", equipment)
    Dispatcher.set("currency", currency)
    Dispatcher.set("artifacts", { bag = {}, equipped = {} })
    Dispatcher.set("battle", { maxStageId = 2501, currentStageId = 101, clearedStages = {} })
    Dispatcher.set("session", { introCompleted = true, lastOnlineTime = os.time(), claimedScenarios = {} })
    local session = Dispatcher.get("session")
    for id = 1, 200 do session.claimedScenarios[tostring(id)] = true end
    GameState.setLevel(100)
    GameState.syncFromCurrency(currency)
    local nativeImage = nvgCreateImage
    nvgCreateImage = function(vg, path, flags)
        if path:find("image/角色卡牌/", 1, true) or path:find("image/怪物卡牌/", 1, true) then
            cardLoadRequests = cardLoadRequests + 1
            if frame >= 140 then finalCardLoadRequests = finalCardLoadRequests + 1 end
        end
        return nativeImage(vg, path, flags)
    end
    local host = require("boot.Standalone")
    host.Start()
    local Backpack = require("ui.backpack.BackpackPanel")
    local Tri = require("ui.battle.tri.BattleTriPage")
    local Forge = require("ui.blacksmith.BlacksmithPage")
    local Msg = require("runtime.ClientMessageHandler")
    local originalResult = Msg.handleActionResult
    Msg.handleActionResult = function(result)
        local returned = originalResult(result)
        if result.action == "enhance_equip" or result.action == "enhance_equip_max" then
            assert(result.success, "升阶回执失败: " .. tostring(result.reason))
            successCount = successCount + 1
        end
        return returned
    end
    local function countCompleted(module, method, count)
        local original = module[method]
        module[method] = function(...)
            local returned = original(...)
            if frame >= 110 then count() end
            return returned
        end
    end
    countCompleted(Tri, "update", function() battleTicks = battleTicks + 1 end)
    countCompleted(Backpack, "update", function() backpackTicks = backpackTicks + 1 end)
    countCompleted(Tri, "draw", function() battleDraws = battleDraws + 1 end)
    countCompleted(Backpack, "draw", function() backpackDraws = backpackDraws + 1 end)
    local update = HandleUpdate
    local forgeReady = false
    local function probeUpdate(eventType, data)
        local begin = time.elapsedTime
        local ok, err = xpcall(function() update(eventType, data) end, debug.traceback)
        if frame >= 140 then finalUpdateMs[#finalUpdateMs + 1] = (time.elapsedTime - begin) * 1000 end
        if not ok then
            updateFailures = updateFailures + 1
            firstError = firstError or err
            if updateFailures <= 2 then print(TAG .. " UPDATE ERROR " .. tostring(err)) end
        end
        frame = frame + 1
        local title = require("ui.story.gate.DarkTitleScreenGate")
        if title.isReady() then title.handleTap() end
        local target = milestones[frame]
        if target then
            if not forgeReady then
                Forge.init(require("boot.StandaloneRT").vg)
                forgeReady = true
            end
            if not Forge.isOpen() then Forge.open() end
            Backpack.open("left")
            Forge.setEquipBySeq(1)
            print(TAG .. " SEND ASCEND frame=" .. frame .. " target=" .. target)
            local AT = require("shared.Protocol").ACTION_TYPES
            local action = target == 1 and AT.ENHANCE_EQUIP or AT.ENHANCE_EQUIP_MAX
            local handled = require("runtime.GameAction").sendAction(action, { seq = 1, targetLevel = target })
            requestCount = requestCount + 1
            assert(handled, "正式升阶请求未处理")
            assert(Equipment.getAscendLevel(Dispatcher.get("equipment").inventory["1"]) == target,
                "正式升阶请求未提交目标等级")
        end
        if frame == 160 then
            local level = Equipment.getAscendLevel(Dispatcher.get("equipment").inventory["1"])
            print(TAG .. " SUMMARY frames=" .. frame .. " requests=" .. requestCount
                .. " successes=" .. successCount .. " level=" .. level
                .. " updateErrors=" .. updateFailures .. " renderErrors=" .. renderFailures
                .. " battleTicks=" .. battleTicks .. " backpackTicks=" .. backpackTicks
                .. " battleDraws=" .. battleDraws .. " backpackDraws=" .. backpackDraws
                .. " cardLoads=" .. cardLoadRequests .. " finalCardLoads=" .. finalCardLoadRequests)
            table.sort(finalUpdateMs)
            print(TAG .. string.format(" 最后20帧Update p50=%.2fms p95=%.2fms",
                finalUpdateMs[math.max(1, math.ceil(#finalUpdateMs * 0.5))] or 0,
                finalUpdateMs[math.max(1, math.ceil(#finalUpdateMs * 0.95))] or 0))
            if firstError then print(TAG .. " FAIL: " .. tostring(firstError))
            elseif requestCount ~= 3 or successCount ~= 3 or level ~= 100 then
                print(TAG .. " FAIL: 升阶请求/成功回执/等级断言未满足")
            elseif battleTicks < 40 or backpackTicks < 40 or battleDraws < 40 or backpackDraws < 40 then
                print(TAG .. " FAIL: 升阶后战斗和左栏未持续完成更新与绘制")
            elseif finalCardLoadRequests ~= 0 then
                print(TAG .. " FAIL: 稳态战斗仍重复请求卡牌图片")
            else print(TAG .. " ALL PASS") end
            engine:Exit()
        end
    end
    UnsubscribeFromEvent("Update")
    SubscribeToEvent("Update", probeUpdate)
    local vg = require("boot.StandaloneRT").vg
    UnsubscribeFromEvent(vg, "NanoVGRender")
    SubscribeToEvent(vg, "NanoVGRender", function(eventType, data)
        local ok, err = xpcall(function() HandleNanoVGRender(eventType, data) end, debug.traceback)
        if not ok then
            renderFailures = renderFailures + 1
            firstError = firstError or err
            if renderFailures <= 2 then print(TAG .. " RENDER ERROR " .. tostring(err)) end
        end
    end)
end
