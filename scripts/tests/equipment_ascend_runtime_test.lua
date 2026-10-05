-- 装备升阶后的真实订阅、战斗与左仓库联动回归；不读取或写入玩家存档。
local TAG = "[equipment_ascend_runtime_test]"
local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end

function Start()
    local ok, err = xpcall(function()
        local Dispatcher = require("runtime.ClientDispatcher")
        local Store = require("core.PlayerStore")
        local Equipment = require("systems.EquipmentSystem")
        local Config = require("config.EquipmentConfig")
        local CP = require("ui.character.panel.CharacterPanel")
        local Backpack = require("ui.backpack.BackpackPanel")
        local Scene = require("ui.battle.scene.BattleScene")
        local Driver = require("ui.battle.tri.BattleTriDriver")
        local Service = require("rules.blacksmith.BlacksmithService")
        local PDM = require("rules.character.PlayerDataManager")
        local AD = require("systems.AttributeDef")
        local Task = require("rules.task.TaskService")
        local GameState = require("core.GameState")
        local Forge = require("ui.blacksmith.BlacksmithPage")
        local PowerEffect = require("ui.fx.SpinePowerUpEffect")
        local ResultEffect = require("ui.fx.SpineResultEffect")
        Store.Init()
        local heroes = { roster = {}, deployed = { 1, 2, 9 }, teams = {} }
        for id = 1, 25 do
            heroes.roster[id] = { level = 100, exp = 0, shards = 0, awakening = {}, extraTalent = {} }
        end
        local equipment = { inventory = {}, equipped = {}, nextSeq = 1 }
        local function put(templateId, heroId, slot)
            local seq = equipment.nextSeq
            equipment.nextSeq = seq + 1
            local item = assert(Equipment.generate(templateId, 85, 6))
            item.seq = seq
            equipment.inventory[tostring(seq)] = item
            if heroId then
                equipment.equipped[heroId] = equipment.equipped[heroId] or {}
                equipment.equipped[heroId][slot] = seq
            end
            return seq
        end
        local weapon = put("W1", 1, "weapon")
        local tome = put("O13", 9, "offhand")
        local shield = put("O7", 1, "offhand")
        local spare = put("W1")
        -- 六槽装备与多角色用于覆盖装备订阅的重复属性重算路径。
        local firstBySlot = {}
        for id, item in pairs(Config.ITEMS) do
            if not firstBySlot[item.slot] then firstBySlot[item.slot] = id end
        end
        for id = 1, 25 do
            for _, slot in ipairs(Config.SLOTS) do
                if not (equipment.equipped[id] and equipment.equipped[id][slot]) then
                    put(assert(firstBySlot[slot]), id, slot)
                end
            end
        end
        local currency = { gold = 10 ^ 12, essence = 10 ^ 9,
            weaponScroll = 10 ^ 6, offhandScroll = 10 ^ 6, armorScroll = 10 ^ 6,
            helmetScroll = 10 ^ 6, shoesScroll = 10 ^ 6, accessoryScroll = 10 ^ 6 }
        Dispatcher.set("player", { level = 100, exp = 0, maxExp = 100 })
        Dispatcher.set("heroes", heroes)
        Dispatcher.set("equipment", equipment)
        Dispatcher.set("currency", currency)
        Dispatcher.set("artifacts", { bag = {}, equipped = {} })
        Dispatcher.set("battle", { maxStageId = 2501, currentStageId = 101, clearedStages = {} })
        GameState.setLevel(100)
        local vg = assert(nvgCreate(1), "NanoVG上下文")
        nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
        CP.init(vg)
        CP.setHeroesData(Dispatcher.get("heroes"))
        Backpack.init(vg)
        Scene.init(vg)
        Scene.setAllies(CP.getDeployedTeam(1))
        Forge.init(vg)
        Forge.open()
        PowerEffect.init()
        for _ = 1, 150 do PowerEffect.draw(vg) end
        Backpack.open("left")
        PDM.AttachLocalModules(1, Dispatcher.getAll())
        PDM.Setup({ serverDispatcher = { pushModule = function(_, name, data)
            Dispatcher.set(name, data)
        end } })
        Task.UpdateProgress = function() end
        local driver = Driver.new(1)
        driver:start(101)
        local signature = CP.getTeamSignature(1)
        check(#driver.allies > 0, "真实编队生成战斗单位")
        print(TAG .. " 装备订阅与战斗夹具就绪")
        for _, seq in ipairs({ spare, weapon, tome, shield }) do
            Forge.setEquipBySeq(seq)
            for _, target in ipairs({ 1, 4, 5, 10, 12, 20, 25 }) do
                print(TAG .. " 开始升阶 seq=" .. seq .. " target=" .. target)
                local begin = os.clock()
                local success, reason, result = Service.AscendEquipToLevel(1, seq, target)
                check(success, "升阶成功: " .. tostring(reason))
                Forge.onEquipmentDataUpdate(equipment)
                Forge.onActionResult(assert(result))
                check(ResultEffect.isPlaying(), "成功回执启动升阶特效")
                check(CP.getTeamSignature(1) == signature, "升阶不改变编队")
                check(Equipment.getAscendLevel(equipment.inventory[tostring(seq)]) == target, "装备等级提交")
                print(TAG .. string.format(" 升阶订阅耗时 %.4fs", os.clock() - begin))
                for frame = 1, 180 do
                    driver:update(1 / 60)
                    Backpack.update(1 / 60)
                    nvgBeginFrame(vg, 1080, 2400, 1)
                    ResultEffect.draw(vg, 540, 165, 160)
                    PowerEffect.draw(vg)
                    if frame == 1 then
                        print(TAG .. " 升阶特效首帧加载结束")
                        Forge.draw(vg)
                        Backpack.draw(vg)
                    end
                    nvgEndFrame(vg)
                    if frame % 60 == 0 then
                        print(TAG .. " 战斗和左栏继续更新 frame=" .. frame)
                    end
                end
                check(driver._sigTick ~= nil, "升阶后战斗帧完整推进")
                nvgBeginFrame(vg, 1080, 2400, 1)
                Backpack.draw(vg)
                CP.draw(vg)
                nvgEndFrame(vg)
                check(equipment.equipped[1].weapon == weapon, "升阶不改变穿戴映射")
                for _, unit in ipairs(driver.allies) do
                    check(unit.attrs ~= nil and unit.attrs:get(AD.MAX_HP) > 0, "战斗属性保持完整")
                end
            end
        end
        local Detail = require("ui.character.equip.EquipmentDetail")
        Detail.close()
        Backpack.open("left", "equip")
        Backpack.setEquipmentSlotFilter("offhand", 9)
        local hx, hy = 0, 0
        local found = false
        for row = 0, 7 do
            for col = 0, 4 do
                local cx, cy = 160 + 190 * col, 550 + 190 * row
                local candidate = Backpack.peekEquipAt(cx, cy)
                if candidate and tonumber(candidate.seq) == shield then hx, hy, found = cx, cy, true end
            end
        end
        check(found, "真实仓库可见格能命中+25实体盾O7")
        local nativeTime = time
        -- 仅控制hover等待时间，保留其真实候选查找与详情打开路径。
        local hoverOk, hoverErr = xpcall(function()
            time = { elapsedTime = 500 }
            Backpack.handleHover(hx, hy)
            time = { elapsedTime = 500.32 }
            Backpack.handleHover(hx, hy)
            check(Detail.isOpen() and Detail.isCompactCorner(), "实体盾升阶后真实hover打开compact详情")
            local selected = Detail.getSelection()
            check(selected and selected.seq == tostring(shield) and selected.owner == "backpack",
                "hover详情属于仓库选中的实体盾")
            nvgBeginFrame(vg, 1080, 2400, 1)
            Backpack.draw(vg)
            nvgSave(vg)
            nvgResetScissor(vg)
            Detail.draw(vg)
            nvgRestore(vg)
            nvgEndFrame(vg)
        end, debug.traceback)
        time = nativeTime
        check(hoverOk, "实体盾升阶小数/词条详情绘制完成: " .. tostring(hoverErr))
        Detail.close()
        nvgDelete(vg)
    end, debug.traceback)
    if ok then print(TAG .. " ALL PASS assertions=" .. assertions)
    else print(TAG .. " FAIL: " .. tostring(err)) end
    engine:Exit()
end
