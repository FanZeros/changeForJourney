-- 左仓库快捷装备真实模块冒烟：双击/右键调用实际规则，拒绝装备不改存档。
local Store = require("core.PlayerStore")
local Dispatcher = require("runtime.ClientDispatcher")
local Eq = require("systems.EquipmentSystem")
local CP = require("ui.character.panel.CharacterPanel")
local Detail = require("ui.character.detail.CharacterDetail")
local Backpack = require("ui.backpack.BackpackPanel")
local Bridge = require("runtime.LocalActionBridge")
local Msg = require("runtime.ClientMessageHandler")
local Action = require("runtime.GameAction")

function Start()
    local savedTime, originalResult = time, Msg.handleActionResult
    local vg = nil
    local ok, err = pcall(function()
        Store.Init()
        local heroes = { roster = { [1] = { level = 60, awakening = {}, extraTalent = {}, shards = 0 } }, deployed = {1} }
        local equipment = { inventory = { ["1"] = Eq.generate("W1", 1, 1), ["2"] = Eq.generate("W7", 1, 3),
            ["3"] = Eq.generate("W31", 1, 6) }, equipped = { [1] = {} }, nextSeq = 4 }
        Dispatcher.handleStateUpdate(cjson.encode({ modules = { heroes = heroes, equipment = equipment,
            artifacts = {bag = {}}, session = {introCompleted = true, claimedScenarios = {["1"]=true}} } }))
        Bridge.init()
        Msg.handleActionResult = function(data) Backpack.onActionResult(data) end
        vg = nvgCreate(1)
        assert(vg, "NanoVG初始化失败")
        nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
        CP.init(vg); Backpack.init(vg)
        time = { elapsedTime = savedTime.elapsedTime + 5 }
        Detail.open(1, "equip")
        local function wearSlot()
            local slots = Eq.getHeroSlots(Dispatcher.get("equipment"), 1)
            return slots and slots.weapon
        end
        local x, y = 160, 470 + 80
        -- 左仓库紧凑布局：品质6错误职业第一，品质3双手剑第二，品质1单手剑第三。
        Backpack.handleInput(350, y)
        assert(wearSlot() == nil, "单击不得实际穿戴")
        time.elapsedTime = time.elapsedTime + 0.08
        Backpack.handleInput(350, y)
        assert(tonumber(wearSlot()) == 2, "双击未完成实际双手剑穿戴")
        Backpack.handleRightClick(540, y)
        assert(tonumber(wearSlot()) == 1, "右键未完成实际单手剑更换")
        Backpack.handleRightClick(160, y)
        assert(tonumber(wearSlot()) == 1, "错误职业装备不得穿戴")
        Backpack.handleRightClick(540, y)
        assert(tonumber(wearSlot()) == 1, "已穿戴同件不得快捷卸下")
        Detail.forceClose()
    end)
    Msg.handleActionResult, time = originalResult, savedTime
    if vg then nvgDelete(vg) end
    if ok then print("[backpack_quick_runtime_test] ALL PASS")
    else print("[backpack_quick_runtime_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
