-- ============================================================================
-- MonsterInfoPopup - 长按敌方单位属性弹窗
-- 从 BattleScene 抽出，行为与原实现保持一致
-- ============================================================================

local AD = require("systems.AttributeDef")
local MC = require("config.MonsterConfig")
local BattleCombat = require("ui.BattleCombat")

local M = {}

local LONG_PRESS_THRESHOLD = 0.4
local CARD_W, CARD_H = 198, 438
local ENEMY_CARD_CY = 804

local ATK_TYPE_NAMES = {
    [1] = "斩击", [2] = "粉碎", [3] = "穿刺", [4] = "业火",
    [5] = "冥霜", [6] = "雷殛", [7] = "暗影", [8] = "烛照",
}
local ARMOR_TYPE_NAMES = {
    [1] = "皮甲", [2] = "轻甲", [3] = "重甲", [4] = "板甲", [5] = "布甲",
}

local longPress = {
    active = false,
    fired = false,
    startTime = 0,
    startX = 0,
    startY = 0,
    showPopup = false,
    unit = nil,
}

---@type table[]|nil
local enemiesRef = nil

function M.handlePressBegin(dx, dy)
    longPress.active = true
    longPress.fired = false
    longPress.startTime = time.elapsedTime
    longPress.startX = dx
    longPress.startY = dy
    longPress.showPopup = false
    longPress.unit = nil
end

function M.handlePressEnd()
    longPress.active = false
    longPress.fired = false
    if longPress.showPopup then
        longPress.showPopup = false
        longPress.unit = nil
    end
end

---@param enemies table[]|nil
function M.update(enemies)
    if enemies then
        enemiesRef = enemies
    end
    if not longPress.active or longPress.fired then return end
    local elapsed = time.elapsedTime - longPress.startTime
    if elapsed < LONG_PRESS_THRESHOLD then return end

    longPress.fired = true
    local list = enemiesRef
    if not list then return end
    local dx, dy = longPress.startX, longPress.startY

    for i, u in ipairs(list) do
        if u.hp and u.hp > 0 then
            local cx = BattleCombat.getCardCX(list, i)
            local cy = ENEMY_CARD_CY
            if math.abs(dx - cx) <= CARD_W * 0.5 and math.abs(dy - cy) <= CARD_H * 0.5 then
                longPress.unit = u
                longPress.showPopup = true
                print("[MonsterInfoPopup] 长按命中怪物: " .. tostring(u.name))
                return
            end
        end
    end
end

function M.draw(vg)
    if not longPress.showPopup or not longPress.unit then return end
    local u = longPress.unit
    local monCfg = u.monsterId and MC.MONSTERS[u.monsterId]

    local lineCount = 4
    if u.attrs and u.attrs.final then lineCount = lineCount + 1 end
    if monCfg and monCfg.attrs then
        for _ in pairs(monCfg.attrs) do lineCount = lineCount + 1 end
    end
    lineCount = lineCount + 1

    local popCX = 540
    local popH = 100 + lineCount * 48
    local popCY = ENEMY_CARD_CY - CARD_H * 0.5 - popH * 0.5 - 10
    local popW = 600
    local popR = 16

    nvgBeginPath(vg)
    nvgRoundedRect(vg, popCX - popW * 0.5, popCY - popH * 0.5, popW, popH, popR)
    nvgFillColor(vg, nvgRGBA(20, 15, 10, 235))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 150, 80, 200))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, popCX, popCY - popH * 0.5 + 40, u.name or "未知", nil)

    nvgBeginPath(vg)
    nvgMoveTo(vg, popCX - popW * 0.4, popCY - popH * 0.5 + 68)
    nvgLineTo(vg, popCX + popW * 0.4, popCY - popH * 0.5 + 68)
    nvgStrokeColor(vg, nvgRGBA(180, 150, 80, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(230, 225, 210, 255))

    local startY = popCY - popH * 0.5 + 100
    local lineH = 48
    local labelX = popCX - popW * 0.4
    local valueX = popCX + 40
    local line = 0

    local atkTypeName = "未知"
    if monCfg and monCfg.atkType then
        atkTypeName = ATK_TYPE_NAMES[monCfg.atkType] or ("类型" .. monCfg.atkType)
    end
    nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
    nvgText(vg, labelX, startY + line * lineH, "攻击类型", nil)
    nvgFillColor(vg, nvgRGBA(255, 200, 100, 255))
    nvgText(vg, valueX, startY + line * lineH, atkTypeName, nil)
    line = line + 1

    local armorName = "未知"
    if monCfg and monCfg.armorType then
        armorName = ARMOR_TYPE_NAMES[monCfg.armorType] or ("类型" .. monCfg.armorType)
    end
    nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
    nvgText(vg, labelX, startY + line * lineH, "护甲类型", nil)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
    nvgText(vg, valueX, startY + line * lineH, armorName, nil)
    line = line + 1

    if monCfg and monCfg.atkTargets then
        nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
        nvgText(vg, labelX, startY + line * lineH, "攻击目标", nil)
        nvgFillColor(vg, nvgRGBA(230, 225, 210, 255))
        nvgText(vg, valueX, startY + line * lineH, tostring(monCfg.atkTargets) .. "个", nil)
        line = line + 1
    end

    if monCfg and monCfg.atkInterval then
        nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
        nvgText(vg, labelX, startY + line * lineH, "攻击间隔", nil)
        nvgFillColor(vg, nvgRGBA(230, 225, 210, 255))
        nvgText(vg, valueX, startY + line * lineH, string.format("%.1f秒", monCfg.atkInterval), nil)
        line = line + 1
    end

    if u.attrs and u.attrs.final then
        local atkCategory = monCfg and AD.getAtkCategory(monCfg.atkType) or "physical"
        local atkKey = (atkCategory == "magical") and AD.MAG_ATK or AD.PHYS_ATK
        local atkLabel = (atkCategory == "magical") and "魔法攻击" or "物理攻击"
        local atkVal = u.attrs.final[atkKey] or 0
        if atkVal > 0 then
            nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
            nvgText(vg, labelX, startY + line * lineH, atkLabel, nil)
            nvgFillColor(vg, nvgRGBA(255, 130, 80, 255))
            nvgText(vg, valueX, startY + line * lineH, tostring(math.floor(atkVal)), nil)
            line = line + 1
        end
    end

    if monCfg and monCfg.attrs and next(monCfg.attrs) then
        for key, _ in pairs(monCfg.attrs) do
            if not (u.monsterId == 1007 and key == AD.COMBO_RATE) then
                local meta = AD.META and AD.META[key]
                local cnName = meta and meta.name or key
                local dataType = meta and meta.dataType or AD.TYPE_FLOAT
                local val = (u.attrs and u.attrs.final and u.attrs.final[key]) or 0
                local valStr
                if dataType == AD.TYPE_PCT then
                    valStr = tostring(math.floor(val)) .. "%"
                elseif dataType == AD.TYPE_INT then
                    valStr = tostring(math.floor(val))
                else
                    valStr = string.format("%.1f", val)
                end
                nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
                nvgText(vg, labelX, startY + line * lineH, "特殊", nil)
                nvgFillColor(vg, nvgRGBA(200, 100, 255, 255))
                nvgText(vg, valueX, startY + line * lineH, cnName .. " " .. valStr, nil)
                line = line + 1
            end
        end
    end

    if u.hp then
        nvgFillColor(vg, nvgRGBA(180, 170, 150, 255))
        nvgText(vg, labelX, startY + line * lineH, "当前生命", nil)
        nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
        nvgText(vg, valueX, startY + line * lineH, tostring(math.floor(u.hp)), nil)
    end

    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(150, 140, 120, 180))
    nvgText(vg, popCX, popCY + popH * 0.5 - 24, "松开关闭", nil)
end

return M
