-- ============================================================================
-- BackpackGrids - 背包装备/道具网格绘制（玩法不变）
-- ============================================================================

local DarkIcon        = require("core.DarkIcon")
local DrawUtil        = require("core.DrawUtil")
local ImageCache      = require("ui.widget.ImageCache")
local NumberUtil      = require("core.NumberUtil")
local PlayerStore     = require("core.PlayerStore")
local EquipmentConfig = require("config.EquipmentConfig")
local HeroConfig      = require("config.HeroConfig")
local CharacterPanel  = require("ui.character.panel.CharacterPanel")

local M = {}

function M.bind(deps)
    local GRID = deps.GRID
    local CELL_COL_CX = deps.CELL_COL_CX
    local CLIP_TOP = deps.CLIP_TOP
    local CLIP_H = deps.CLIP_H
    local DESIGN_W = deps.DESIGN_W
    local DarkIcon = deps.DarkIcon or DarkIcon
    local DrawUtil = deps.DrawUtil or DrawUtil
    local state = deps.state
    local decomposeState = deps.decomposeState
    local ITEM_DEFS = deps.ITEM_DEFS
    local getItemIcon = deps.getItemIcon
    local getImgCheckmark = deps.getImgCheckmark
    local getImgLock = deps.getImgLock
    local getImgHeroIcons = deps.getImgHeroIcons
    local calcScrollMax = deps.calcScrollMax
    local clampScroll = deps.clampScroll

    local function getEquipList()
        local equipData = PlayerStore.Get("equipment")
        if not equipData or not equipData.inventory then return {} end

        local equippedByHero = {}
        if equipData.equipped then
            for hid, heroSlots in pairs(equipData.equipped) do
                if type(heroSlots) == "table" then
                    for _, eqSeq in pairs(heroSlots) do
                        equippedByHero[tostring(eqSeq)] = hid
                    end
                end
            end
        end

        local list = {}
        for seqStr, equip in pairs(equipData.inventory) do
            local tpl = EquipmentConfig.ITEMS[equip.templateId]
            if tpl then
                list[#list + 1] = {
                    seq = tonumber(seqStr) or 0,
                    templateId = equip.templateId,
                    level = equip.level or 1,
                    quality = equip.quality or tpl.quality or 1,
                    name = tpl.name or "",
                    type = equip.type or tpl.type or "",
                    enhanceLevel = equip.enhanceLevel or 0,
                    equippedByHeroId = equippedByHero[seqStr] or nil,
                    locked = equip.locked or nil,
                }
            end
        end

        table.sort(list, function(a, b)
            if a.quality ~= b.quality then return a.quality > b.quality end
            return a.level > b.level
        end)

        return list
    end

    local function drawEquipGrid(vg)
        local equipList = getEquipList()
        local totalSlots = math.max(#equipList, 35)
        state.scrollMax = calcScrollMax(totalSlots)
        clampScroll()

        nvgSave(vg)
        nvgScissor(vg, 0, CLIP_TOP, DESIGN_W, CLIP_H)
        nvgTranslate(vg, 0, -state.scrollY)

        for idx = 1, totalSlots do
            local col = ((idx - 1) % GRID.COLS) + 1
            local row = math.floor((idx - 1) / GRID.COLS)
            local cx = CELL_COL_CX[col]
            local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5

            local screenY = cy - state.scrollY

            if idx == 1 then
                local _TM = require("systems.TutorialManager")
                if _TM.isActive() then
                    _TM.registerHotspot("equip_item_gifted", cx, screenY, GRID.CELL_SIZE, GRID.CELL_SIZE, "right")
                end
            end

            if screenY < CLIP_TOP - GRID.CELL_SIZE then
                goto continue_equip
            end
            if screenY > GRID.CLIP_BOTTOM + GRID.CELL_SIZE then
                break
            end

            local equip = equipList[idx]
            if equip then
                DarkIcon.drawQualityBg(vg, equip.quality, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE, 1.0)

                local icon = ImageCache.getEquipIcon(equip.templateId)
                if icon and icon >= 0 then
                    DarkIcon.drawIconDark(vg, icon, cx, cy, GRID.CELL_SIZE - 10, GRID.CELL_SIZE - 10, 1.0)
                end

                do
                    local lvlText = "Lv." .. (equip.level or 1)
                    local lvlX = cx + GRID.CELL_SIZE * 0.5 - 8
                    local lvlY = cy + GRID.CELL_SIZE * 0.5 - 6
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

                if equip.enhanceLevel and equip.enhanceLevel > 0 then
                    local enhText = "+" .. equip.enhanceLevel
                    local enhX = cx + GRID.CELL_SIZE * 0.5 - 8
                    local enhY = cy - GRID.CELL_SIZE * 0.5 + 8
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, 36)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, enhX + math.cos(sa) * 3, enhY + math.sin(sa) * 3, enhText, nil)
                    end
                    nvgFillColor(vg, nvgRGBA(0x00, 0xff, 0x60, 255))
                    nvgText(vg, enhX, enhY, enhText, nil)
                end

                if equip.equippedByHeroId then
                    local imgHeroIcons = getImgHeroIcons()
                    local ownerIcon = imgHeroIcons[equip.equippedByHeroId]
                    if ownerIcon and ownerIcon >= 0 then
                        local badgeSize = 66
                        local badgeX = cx - GRID.CELL_SIZE * 0.5 + badgeSize * 0.5 + 1
                        local badgeY = cy - GRID.CELL_SIZE * 0.5 + badgeSize * 0.5 + 1
                        nvgSave(vg)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, badgeX - badgeSize * 0.5, badgeY - badgeSize * 0.5, badgeSize, badgeSize, 6)
                        nvgFillPaint(vg, nvgImagePattern(vg, badgeX - badgeSize * 0.5, badgeY - badgeSize * 0.5, badgeSize, badgeSize, 0, ownerIcon, 1.0))
                        nvgFill(vg)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, badgeX - badgeSize * 0.5, badgeY - badgeSize * 0.5, badgeSize, badgeSize, 6)
                        nvgStrokeColor(vg, nvgRGBA(0xff, 0xff, 0xff, 200))
                        nvgStrokeWidth(vg, 2)
                        nvgStroke(vg)
                        nvgRestore(vg)
                    end
                end

                if decomposeState.active and decomposeState.selectedItems[idx] then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
                        GRID.CELL_SIZE, GRID.CELL_SIZE, GRID.CELL_RADIUS)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 128))
                    nvgFill(vg)
                    DrawUtil.drawImageCentered(vg, getImgCheckmark(), cx, cy, 80, 80, 1.0)
                end

                if equip.locked and getImgLock() >= 0 then
                    local lockSize = 56
                    local lockX = cx - GRID.CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                    local lockY
                    if equip.equippedByHeroId then
                        lockY = cy + GRID.CELL_SIZE * 0.5 - lockSize * 0.5 - 4
                    else
                        lockY = cy - GRID.CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                    end
                    DrawUtil.drawImageCentered(vg, getImgLock(), lockX, lockY, lockSize, lockSize, 1.0)
                end
            else
                nvgBeginPath(vg)
                nvgRoundedRect(vg,
                    cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
                    GRID.CELL_SIZE, GRID.CELL_SIZE, GRID.CELL_RADIUS + 6)
                nvgFillColor(vg, nvgRGBA(210, 186, 140, 70))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(232, 204, 140, 210))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)
            end
            ::continue_equip::
        end

        nvgRestore(vg)
    end

    local function buildItemList()
        local list = {}
        for _, def in ipairs(ITEM_DEFS) do
            local count = def.getter and def.getter() or 0
            if count > 0 then
                list[#list + 1] = def
            end
        end
        local HC = HeroConfig
        local qualityToGridQuality = { [1] = 1, [2] = 3, [3] = 5, [4] = 6 }
        for _, heroId in ipairs(HC.getAllIds()) do
            local shards = CharacterPanel.getShards(heroId)
            if shards > 0 then
                local heroCfg = HC.get(heroId)
                local heroName = heroCfg and heroCfg.name or ("英雄" .. heroId)
                local heroQuality = heroCfg and heroCfg.quality or 1
                local gridQuality = qualityToGridQuality[heroQuality] or 1
                local hid = heroId
                list[#list + 1] = {
                    key = "shard_" .. heroId,
                    quality = gridQuality,
                    name = heroName .. "碎片",
                    source = "抽卡获得",
                    desc = "用于激活远征队员或进行远征队员觉醒",
                    isShard = true,
                    heroId = heroId,
                    getter = function() return CharacterPanel.getShards(hid) end,
                }
            end
        end
        return list
    end

    local function drawItemGrid(vg)
        local itemList = buildItemList()
        local totalSlots = #itemList
        state.scrollMax = calcScrollMax(totalSlots)
        clampScroll()

        nvgSave(vg)
        nvgScissor(vg, 0, CLIP_TOP, DESIGN_W, CLIP_H)
        nvgTranslate(vg, 0, -state.scrollY)

        for idx, def in ipairs(itemList) do
            local col = ((idx - 1) % GRID.COLS) + 1
            local row = math.floor((idx - 1) / GRID.COLS)
            local cx = CELL_COL_CX[col]
            local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5

            DarkIcon.drawQualityBg(vg, def.quality, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE, 1.0)

            if def.isShard and def.heroId then
                DrawUtil.drawShardIcon(vg, def.heroId, cx, cy, GRID.CELL_SIZE - 10, 1.0)
            else
                local icon = getItemIcon(def)
                if icon and icon >= 0 then
                    DrawUtil.drawImageCentered(vg, icon, cx, cy, GRID.CELL_SIZE - 10, GRID.CELL_SIZE - 10, 1.0)
                end
            end

            local amount = def.getter()
            if amount and amount > 0 then
                local amtText = def.amountTextGetter and def.amountTextGetter() or ("×" .. NumberUtil.format(amount))
                local amtX = cx + GRID.CELL_SIZE * 0.5 - 8
                local amtY = cy + GRID.CELL_SIZE * 0.5 - 8
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 40)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                local sStep = math.pi * 2 / 16
                for si = 0, 15 do
                    local sa = si * sStep
                    nvgText(vg, amtX + math.cos(sa) * 4, amtY + math.sin(sa) * 4, amtText, nil)
                end
                nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                nvgText(vg, amtX, amtY, amtText, nil)
            end
        end

        nvgRestore(vg)
    end

    return {
        getEquipList = getEquipList,
        drawEquipGrid = drawEquipGrid,
        buildItemList = buildItemList,
        drawItemGrid = drawItemGrid,
    }
end

return M
