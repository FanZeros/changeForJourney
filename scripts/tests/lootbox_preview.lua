-- 遗匣三栏实机验收入口：不读取、不写入玩家存档。
local Standalone = require("network.Standalone")
local Save = require("network.StandaloneSave")
local Dispatcher = require("network.ClientDispatcher")
local Page = require("ui.LootBoxPage")
local LootBox = require("ui.LootBox")
local EquipmentSystem = require("systems.EquipmentSystem")
local done = false

function Start()
    Save.RestoreData = function() return false end
    Save.Update = function() end
    Save.Flush = function() end
    local Tutorial = require("systems.TutorialManager")
    Tutorial.isActive = function() return false end
    Tutorial.isBuildingUnlocked = function() return true end
    local Offline = require("ui.OfflineRewardPanel")
    Offline.show = function() end
    Standalone.Start()
    Dispatcher.set("session", { introCompleted = true, claimedScenarios = {} })
    SubscribeToEvent("Update", "LootboxPreviewUpdate")
end

function LootboxPreviewUpdate()
    local rt = require("network.StandaloneRT")
    if not rt.bootReady_ then return end
    local Title = require("ui.DarkTitleScreenGate")
    if Title.isOpen() then
        Title.setReady(true)
        Title.handleTap()
        Title.update(1)
    end
    if done then return end
    done = true
    local seeds = {
        { quality = 6, level = 40, count = 1, equip = EquipmentSystem.generateRandom(40, 6) },
        { quality = 5, level = 35, count = 1, equip = EquipmentSystem.generateRandom(35, 5) },
    }
    for quality = 1, 6 do
        seeds[#seeds + 1] = { quality = quality, level = 20, count = quality * 3 }
    end
    Dispatcher.set("lootbox", { seeds = seeds })
    LootBox.openPage()
    assert(Page.isOpen(), "遗匣地点页面未打开")
    print("[lootbox_preview] 左栏已打开，不覆盖中间战斗和右栏")
end

function Stop()
    Standalone.Stop()
end
