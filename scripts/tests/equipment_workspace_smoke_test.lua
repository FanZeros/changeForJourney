-- 配装真实模块集成冒烟：初始化角色/仓库、实际读写协议保持不参与预览。
local Dispatcher = require("runtime.ClientDispatcher")
local Store = require("core.PlayerStore")
local Eq = require("systems.EquipmentSystem")
local CP = require("ui.character.panel.CharacterPanel")
local Detail = require("ui.character.detail.CharacterDetail")
local Backpack = require("ui.backpack.BackpackPanel")
local ED = require("ui.character.equip.EquipmentDetail")
local EquipPanel = require("ui.character.detail.CharacterDetailEquip")
local Preview = require("ui.character.detail.EquipmentPreview")

function Start()
    local ok, err = pcall(function()
        Store.Init()
        local heroes = { roster = { [1] = { level = 60, exp = 0, shards = 0, awakening = {}, extraTalent = {} },
            [2] = { level = 60, exp = 0, shards = 0, awakening = {}, extraTalent = {} } }, deployed = { 1, 2 } }
        local equipment = { inventory = {}, equipped = { [1] = {} }, nextSeq = 4 }
        equipment.inventory["1"] = Eq.generate("W1", 1, 1)
        equipment.inventory["2"] = Eq.generate("W7", 1, 3)
        equipment.inventory["3"] = Eq.generate("O1", 1, 1)
        equipment.equipped[1] = { weapon = 1, offhand = 3 }
        Dispatcher.handleStateUpdate(cjson.encode({ modules = { heroes = heroes, equipment = equipment,
            artifacts = { bag = {} }, session = { introCompleted = true, claimedScenarios = { ["1"] = true } } } }))
        local vg = nvgCreate(1)
        assert(vg, "NanoVG 上下文创建失败")
        nvgCreateFont(vg, "sans", "Fonts/NotoSansCJKkr-Bold.otf")
        CP.init(vg)
        CP.setHeroesData(Dispatcher.get("heroes"))
        Backpack.init(vg)
        Detail.open(1, "equip")
        assert(Backpack.isOpen() and Backpack.isLeftMode(), "配装入口未自动开启左仓库")
        local Draw = require("ui.character.detail.CharacterDetailDraw")
        local slots = {}
        for _, slot in ipairs(Draw.DT_SLOTS) do slots[slot.slot] = slot end
        Detail.handleEquipmentSlotTap(slots.helmet.cx, slots.helmet.cy)
        assert(Backpack.getEquipmentSlotFilter() == "helmet", "头盔筛选未同步")
        -- 所有点击仅走部位UI联动，绝不调用装备/卸下action。
        local expected = {
            helmet = { cx = 540, cy = 165, oldCY = 185 },
            armor = { cx = 325, cy = 336, oldCY = 316 },
            accessory = { cx = 755, cy = 336, oldCY = 316 },
            weapon = { cx = 325, cy = 598, oldCY = 578 },
            offhand = { cx = 755, cy = 598, oldCY = 578 },
            shoes = { cx = 540, cy = 790, oldCY = 790 },
        }
        assert(#Draw.DT_SLOTS == 6 and Draw.DT_SLOT_SIZE == 160, "六槽尺寸/数量异常")
        local half = Draw.DT_SLOT_SIZE * 0.5
        local function tapAt(slot, y, hit, label)
            assert(Detail.handleEquipmentSlotTap(slot.cx, y) == hit, label .. "命中异常: " .. slot.slot)
            local selected = Backpack.getEquipmentSlotFilter()
            assert(selected == (hit and slot.slot or nil), label .. "仓库过滤不同步: " .. slot.slot)
        end
        for _, slot in ipairs(Draw.DT_SLOTS) do
            local target = expected[slot.slot]
            assert(target and slot.cx == target.cx and slot.cy == target.cy, "六槽新中心异常: " .. slot.slot)
            tapAt(slot, slot.cy, true, "新中心")
            tapAt(slot, slot.cy - half, true, "新上边界")
            tapAt(slot, slot.cy + half, true, "新下边界")
            tapAt(slot, slot.cy - half - 0.5, false, "新上边界外")
            tapAt(slot, slot.cy + half + 0.5, false, "新下边界外")
            local delta = slot.cy - target.oldCY
            if delta ~= 0 then
                -- 20px位移的上下差集各取中点，避免仅新旧中心都落在重叠区而漏掉旧命中表。
                local newOnly = slot.cy + (delta > 0 and half - delta * 0.5 or -half - delta * 0.5)
                local oldOnly = target.oldCY + (delta > 0 and -half + delta * 0.5 or half + delta * 0.5)
                assert(math.abs(newOnly - target.oldCY) > half and math.abs(oldOnly - slot.cy) > half,
                    "新旧边界差集夹具异常: " .. slot.slot)
                tapAt(slot, newOnly, true, "新区域独有点")
                tapAt(slot, oldOnly, false, "旧区域独有点")
            end
        end
        -- 初始化后的真实装备映射，主副手分别读取不同的合法装备实例。
        local main = EquipPanel.peekSlotEquipAt(slots.weapon.cx, slots.weapon.cy)
        local offhand = EquipPanel.peekSlotEquipAt(slots.offhand.cx, slots.offhand.cy)
        assert(main and tostring(main.seq) == "1" and main.templateId == "W1" and main.slot == "weapon",
            "主手新中心peek未读取已装备实例")
        assert(offhand and tostring(offhand.seq) == "3" and offhand.templateId == "O1" and offhand.slot == "offhand",
            "副手新中心peek未读取已装备实例")
        assert(Dispatcher.get("equipment").equipped[1].weapon == 1
            and Dispatcher.get("equipment").equipped[1].offhand == 3, "部位命中/peek意外改写穿戴映射")
        Detail.clearEquipmentSlot()
        assert(Backpack.getEquipmentSlotFilter() == nil, "取消部位不同步")
        ED.open(2, nil, nil, true, "backpack", 500, 900)
        ED.pin()
        assert(ED.getSelection().seq == "2" and ED.getSelection().pinned, "钉住候选快照丢失")
        local data = Preview.build(1, 60, 2)
        assert(data.preview and not data.error, "真实模板试穿被拒绝")
        assert(Dispatcher.get("equipment").equipped[1].weapon == 1, "预览意外穿戴装备")
        nvgBeginFrame(vg, 1080, 2400, 1)
        Detail.draw(vg)
        EquipPanel.drawSetCodex(vg)
        nvgEndFrame(vg)
        assert(EquipPanel.peekItemAt(150, 1304) == nil, "隐藏网格仍可命中")
        Detail.handleEquipmentSlotTap(755, 578)
        local preservedSlot = Backpack.getEquipmentSlotFilter()
        assert(preservedSlot == "offhand", "副手筛选必须先建立")
        ED.open(2, nil, nil, true, "backpack", 500, 900)
        ED.pin()
        Detail.handleInput(540, 930)
        assert(EquipPanel.getAttributeMode() == "equipment", "标题首击未切换装备加成")
        assert(Backpack.getEquipmentSlotFilter() == preservedSlot, "切换标题意外取消副手筛选")
        assert(ED.getSelection().pinned and ED.getSelection().seq == "2", "切换标题丢失钉住候选")
        local bonusOptions = { includeEquipmentBonuses = true }
        local bonusData = Preview.build(1, 60, nil, nil, bonusOptions)
        assert(bonusData.equipmentBonuses and #bonusData.equipmentBonuses.rows > 0, "装备净增益未构建")
        nvgBeginFrame(vg, 1080, 2400, 1)
        EquipPanel.draw(vg, 1, { equipSlot = preservedSlot })
        nvgEndFrame(vg)
        Detail.handleInput(540, 930)
        assert(EquipPanel.getAttributeMode() == "character", "标题再次点击未恢复角色属性")
        assert(Dispatcher.get("equipment").equipped[1].weapon == 1, "显示切换意外穿装")
        Detail.handleInput(540, 930)
        assert(EquipPanel.getAttributeMode() == "equipment", "角色切换前进入装备加成模式")
        Detail.open(2)
        assert(Detail.isEquipTab() and Detail.getHeroId() == 2 and EquipPanel.getAttributeMode() == "equipment",
            "出战英雄点击入口保留配装页和装备加成显示，只切角色")
        assert(Backpack.isOpen() and Backpack.getEquipmentSlotFilter() == nil, "换角色只更新仓库上下文与自然槽筛选")
        Detail.open(1)
        assert(Detail.isEquipTab() and Detail.getHeroId() == 1 and EquipPanel.getAttributeMode() == "equipment",
            "切回出战角色仍保留配装模式")
        assert(Dispatcher.get("equipment").equipped[1].weapon == 1, "切角色不得改写穿戴映射")
        Detail.handleDragBegin(80, 1800)
        Detail.handleDragMove(80, 1720)
        Detail.handleDragEnd(80, 1720)
        Detail.handleScroll(-1, 80, 1800)
        local runtimeTime = time
        time = { elapsedTime = runtimeTime.elapsedTime }
        Detail.handleInput(255, 2308)
        time.elapsedTime = time.elapsedTime + 1
        Backpack.update(1)
        assert(not Backpack.isOpen(), "离开配装未隐藏自动仓库")
        Backpack.open("left")
        Detail.open(1, "equip")
        Detail.forceClose()
        Backpack.update(1)
        assert(Backpack.isOpen(), "手动仓库被配装离开误关闭")
        time = runtimeTime
        nvgDelete(vg)
    end)
    if ok then print("[equipment_workspace_smoke_test] ALL PASS")
    else print("[equipment_workspace_smoke_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
