-- ============================================================================
-- BlacksmithEquipSlots - 铁匠装备槽绘制（玩法不变）
-- ============================================================================

local CharacterPanel = require("ui.character.panel.CharacterPanel")
local ClientDispatcher = require("runtime.ClientDispatcher")
local PlayerStore = require("core.PlayerStore")
local EquipmentSystem = require("systems.EquipmentSystem")
local DrawUtil = require("core.DrawUtil")

local M = {}
local _equipSlotDbgTimer = 0

function M.bind(deps)
    local CharacterPanel = deps.CharacterPanel
    local ClientDispatcher = deps.ClientDispatcher
    local DarkIcon = deps.DarkIcon
    local DrawUtil = deps.DrawUtil
    local EQUIP_LV_FONT_SIZE = deps.EQUIP_LV_FONT_SIZE
    local EQUIP_LV_Y_OFFSET = deps.EQUIP_LV_Y_OFFSET
    local EQUIP_SLOT_ORDER = deps.EQUIP_SLOT_ORDER
    local EQUIP_SLOT_SIZE = deps.EQUIP_SLOT_SIZE
    local EquipmentSystem = deps.EquipmentSystem
    local PlayerStore = deps.PlayerStore
    local drawImageCentered = deps.drawImageCentered
    local drawTextStroke = deps.drawTextStroke
    local getCachedSlotCanEnhance = deps.getCachedSlotCanEnhance
    local getEquipIconCached = deps.getEquipIconCached
    local getEquipSlotCX = deps.getEquipSlotCX
    local getEquipSlotCY = deps.getEquipSlotCY
    local imgIconUp = deps.imgIconUp
    local imgSlotBg = deps.imgSlotBg
    local imgSlotSelected = deps.imgSlotSelected
    local state = deps.state

    local function drawEquipSlots(vg)
    local teamSlots = CharacterPanel.getTeamSlotsData()
    local selectedSlot = teamSlots and teamSlots[state.selectedPartySlot]
    local heroId = selectedSlot and selectedSlot.heroId
    local eqData = ClientDispatcher.get("equipment") or PlayerStore.Get("equipment")
    local heroEquipped = nil
    if heroId and eqData and eqData.equipped then
        -- 尝试字符串和数字两种 key
        heroEquipped = EquipmentSystem.getHeroSlots(eqData, heroId)
    end

    -- 诊断日志（每 3 秒打印一次）
    local now = time.elapsedTime or 0
    if now - _equipSlotDbgTimer > 3 then
        _equipSlotDbgTimer = now
        print("[drawEquipSlots] heroId=" .. tostring(heroId)
            .. " eqData=" .. tostring(eqData ~= nil)
            .. " equipped=" .. tostring(eqData and eqData.equipped ~= nil)
            .. " heroEquipped=" .. tostring(heroEquipped ~= nil))
        if eqData and eqData.equipped then
            local keys = {}
            for k, _ in pairs(eqData.equipped) do keys[#keys+1] = tostring(k) .. "(" .. type(k) .. ")" end
            print("[drawEquipSlots] equipped keys: " .. table.concat(keys, ", "))
        end
        if heroEquipped then
            local slots = {}
            for k, v in pairs(heroEquipped) do slots[#slots+1] = k .. "=" .. tostring(v) end
            print("[drawEquipSlots] heroEquipped: " .. table.concat(slots, ", "))
        end
    end

    for i, slotKey in ipairs(EQUIP_SLOT_ORDER) do
        local cx = getEquipSlotCX(i)
        local cy = getEquipSlotCY(i)
        local isSelected = (slotKey == state.selectedEquipSlot)

        -- 选中底图（在槽位背景图后方）
        if isSelected and imgSlotSelected >= 0 then
            drawImageCentered(vg, imgSlotSelected, cx, cy, 234, 234, 1.0)
        end

        -- 槽位背景图
        local bgImg = imgSlotBg[slotKey]
        if bgImg and bgImg >= 0 then
            drawImageCentered(vg, bgImg, cx, cy, EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE, 1.0)
        end

        -- 如果该英雄该槽位有装备，绘制品质底框 + 装备图标
        local seq = heroEquipped and heroEquipped[slotKey]
        local equip = nil
        if seq and eqData and eqData.inventory then
            equip = eqData.inventory[tostring(seq)]
        end
        -- 双手武器镜像：offhand 无装备时检查 weapon 是否双手
        local isTwohandOccupied = false
        if not equip and slotKey == "offhand" and heroEquipped and eqData and eqData.inventory then
            local weaponSeq = heroEquipped["weapon"]
            if weaponSeq then
                local weaponEquip = eqData.inventory[tostring(weaponSeq)]
                if weaponEquip and weaponEquip.grip == "twohand" then
                    equip = weaponEquip
                    isTwohandOccupied = true
                end
            end
        end
        if equip then
            local qIdx = math.max(1, math.min(6, equip.quality or 1))
            DarkIcon.drawQualityBg(vg, qIdx, cx, cy, EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE, 1.0)  -- [暗黑化 P2-A]
            local eqIcon = getEquipIconCached(equip.templateId)
            if eqIcon and eqIcon > 0 then
                DarkIcon.drawIconDark(vg, eqIcon, cx, cy, EQUIP_SLOT_SIZE - 16, EQUIP_SLOT_SIZE - 16, 1.0)  -- [暗黑化 P2-B]
            end
            -- 装备等级角标 "Lv.X"（右下角，16方向描边）
            local eqLv = equip.level or 1
            if eqLv >= 1 then
                local lvlText = "Lv." .. eqLv
                local lvlX = cx + EQUIP_SLOT_SIZE * 0.5 - 8
                local lvlY = cy + EQUIP_SLOT_SIZE * 0.5 - 6
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 40)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, lvlX + math.cos(sa) * 4, lvlY + math.sin(sa) * 4, lvlText, nil)
                end
                nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                nvgText(vg, lvlX, lvlY, lvlText, nil)
            end

            -- 双手武器占用副手槽位时绘制半透明黑色遮罩
            if isTwohandOccupied then
                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    cx - EQUIP_SLOT_SIZE * 0.5,
                    cy - EQUIP_SLOT_SIZE * 0.5,
                    EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE, 24)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
                nvgFill(vg)
            end
        end

        -- 升阶角标（跟着这件装备）
        do
        local enhLv = equip and EquipmentSystem.getAscendLevel(equip) or 0
            if enhLv > 0 then
                local lvX = cx
                local lvY = cy + EQUIP_LV_Y_OFFSET
                drawTextStroke(vg, lvX, lvY, "+" .. enhLv,
                    EQUIP_LV_FONT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    0x67, 0xff, 0x75, 5, { italic = true })
            end
        end

        -- 可强化角标（右上角，该装备槽位满足强化条件时显示）
        if imgIconUp >= 0 and getCachedSlotCanEnhance(state.selectedPartySlot, slotKey) then
            local upSize = 36
            local upX = cx + EQUIP_SLOT_SIZE * 0.5 - upSize * 0.25
            local upY = cy - EQUIP_SLOT_SIZE * 0.5 + upSize * 0.25
            DrawUtil.drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
        end
    end

    end
    return { drawEquipSlots = drawEquipSlots }
end

return M
