-- ============================================================================
-- BackpackGrids - 背包装备/道具网格绘制（玩法不变）
-- ============================================================================

local DarkIcon        = require("core.DarkIcon")
local DrawUtil        = require("core.DrawUtil")
local ImageCache      = require("ui.widget.ImageCache")
local NumberUtil      = require("core.NumberUtil")
local PlayerStore     = require("core.PlayerStore")
local EquipmentConfig = require("config.EquipmentConfig")
local EquipmentSetConfig = require("config.EquipmentSetConfig")
local EquipmentWearability = require("ui.character.detail.EquipmentWearability")
local EquipmentPower = require("systems.EquipmentPower")
local AdvancementConfig = require("config.AdvancementConfig")
local HeroConfig      = require("config.HeroConfig")
local CharacterPanel  = require("ui.character.panel.CharacterPanel")
local HeroFrame = require("ui.widget.HeroFrame")
local EquipmentSetIcon = require("ui.widget.EquipmentSetIcon")

local M = {}

function M.bind(deps)
    local GRID = deps.GRID
    local CELL_COL_CX = deps.CELL_COL_CX
    local DESIGN_W = deps.DESIGN_W
    -- 裁剪常量从 GRID 表取活值：宿主 applyLayout 切换 inline/left 布局时会改写
    -- GRID.FIRST_ROW_TOP / GRID.CLIP_BOTTOM，bind 时按值快照会拿到过期布局。
    local function clipTop() return GRID.FIRST_ROW_TOP end
    local function clipH() return GRID.CLIP_BOTTOM - GRID.FIRST_ROW_TOP end
    local DarkIcon = deps.DarkIcon or DarkIcon
    local DrawUtil = deps.DrawUtil or DrawUtil
    local state = deps.state
    local decomposeState = deps.decomposeState
    local ITEM_DEFS = deps.ITEM_DEFS
    local getItemIcon = deps.getItemIcon
    local getImgCheckmark = deps.getImgCheckmark
    local getImgLock = deps.getImgLock
    local qualityChecked = deps.qualityChecked or function() return true end
    -- 套装筛选（装备 tab 显示过滤）：空集合=不限制
    local setChecked = deps.setChecked or function() return true end
    local getImgHeroIcons = deps.getImgHeroIcons
    local calcScrollMax = deps.calcScrollMax
    local clampScroll = deps.clampScroll
    local getEquipmentSlotFilter = deps.getEquipmentSlotFilter or function() return nil, nil end
    local function isLeftMode()
        if deps.isLeftMode then return deps.isLeftMode() end
        return require("ui.backpack.BackpackPanel").isLeftMode()
    end

    local function filterContext()
        local slotFilter, filterHeroId = getEquipmentSlotFilter()
        local heroes = filterHeroId ~= nil and PlayerStore.Get("heroes") or nil
        local hero = heroes and heroes.roster
            and (heroes.roster[filterHeroId] or heroes.roster[tostring(filterHeroId)])
        local dualMode = AdvancementConfig.getDualWieldMode(hero and hero.advBranch)
        return slotFilter, filterHeroId, heroes, dualMode
    end

    -- 列表与数量共用品质/部位规则；可穿戴状态只灰显，不改变候选数量。
    local function matchesBaseFilter(equip, slotFilter, dualMode)
        local tpl = EquipmentConfig.ITEMS[equip.templateId]
        local naturalSlot, equipType, grip, level = EquipmentWearability.getFields(equip)
        local quality = equip.quality or (tpl and tpl.quality) or 1
        local slotOk = not slotFilter or naturalSlot == slotFilter
        if slotFilter == "offhand" and dualMode and naturalSlot == "weapon" and grip == "onehand" then
            slotOk = true
        end
        return tpl ~= nil and qualityChecked(quality) and slotOk,
            tpl, naturalSlot, equipType, grip, level, quality
    end

    --- 按当前品质/部位统计套装实例，忽略套装勾选，避免其他可选行被计成零。
    ---@return table<string, integer>
    local function getSetCounts()
        local counts = { none = 0 }
        for _, setId in ipairs(EquipmentSetConfig.orderedSetIds()) do counts[setId] = 0 end
        local equipData = PlayerStore.Get("equipment")
        if not equipData or not equipData.inventory then return counts end
        local slotFilter, _, _, dualMode = filterContext()
        for _, equip in pairs(equipData.inventory) do
            local matches, tpl = matchesBaseFilter(equip, slotFilter, dualMode)
            if matches then
                local setId = EquipmentSetConfig.getSetIdForTemplate(tpl) or "none"
                counts[setId] = (counts[setId] or 0) + 1
            end
        end
        return counts
    end

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
        local slotFilter, filterHeroId, _, dualMode = filterContext()
        -- 一次列表复用角色上下文；评分器缓存单件模拟，不逐帧逐件重建 HeroCombat。
        local powerContext = filterHeroId ~= nil and EquipmentPower.getContext(filterHeroId) or nil
        for seqStr, equip in pairs(equipData.inventory) do
            local matches, tpl, naturalSlot, equipType, grip, level, quality =
                matchesBaseFilter(equip, slotFilter, dualMode)
            -- 部位、品质与套装决定列表；不能穿的保留在同一绘制/点击/hover/peek真源内。
            if matches and setChecked(equip.templateId) then
                local preview = powerContext and EquipmentPower.evaluate(powerContext, seqStr, slotFilter)
                -- 保留完整装备（词条/腐化/套装等），仅在列表副本附加显示字段，绝不改 inventory。
                local entry = {}
                for key, value in pairs(equip) do entry[key] = value end
                entry.seq = tonumber(seqStr) or 0
                entry.level, entry.quality = level, quality
                entry.name = tpl.name or ""
                entry.type, entry.slot, entry.grip = equipType or "", naturalSlot, grip
                entry.enhanceLevel = equip.enhanceLevel or 0
                entry.equippedByHeroId = equippedByHero[tostring(seqStr)] or nil
                entry.canWear = filterHeroId == nil or (preview ~= nil and preview.valid == true)
                entry.cannotEquipReason = not entry.canWear and (preview and preview.error or "角色数据未就绪") or nil
                entry.power = EquipmentPower.score(equip, filterHeroId, slotFilter)
                entry.upgrade = preview ~= nil and preview.valid == true and preview.gain > 1e-6
                list[#list + 1] = entry
            end
        end

        table.sort(list, function(a, b)
            if a.quality ~= b.quality then return a.quality > b.quality end
            if a.power ~= b.power then return a.power > b.power end
            if a.level ~= b.level then return a.level > b.level end
            if a.enhanceLevel ~= b.enhanceLevel then return a.enhanceLevel > b.enhanceLevel end
            return a.seq < b.seq
        end)

        return list
    end

    local function drawEquipGrid(vg)
        local equipList = getEquipList()
        local totalSlots = math.max(#equipList, 35)
        state.scrollMax = calcScrollMax(totalSlots)
        clampScroll()
        local tutorial = require("systems.TutorialManager")
        local slotFilter, filterHeroId = getEquipmentSlotFilter()
        local canGuideWeapon = tutorial.isActive() and slotFilter == "weapon"
            and filterHeroId ~= nil and not state.closing and isLeftMode()
        local guidedWeapon = false

        nvgSave(vg)
        nvgScissor(vg, 0, clipTop(), DESIGN_W, clipH())
        nvgTranslate(vg, 0, -state.scrollY)

        for idx = 1, totalSlots do
            local col = ((idx - 1) % GRID.COLS) + 1
            local row = math.floor((idx - 1) / GRID.COLS)
            local cx = CELL_COL_CX[col]
            local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5

            local screenY = cy - state.scrollY

            if screenY < clipTop() - GRID.CELL_SIZE then
                goto continue_equip
            end
            if screenY > GRID.CLIP_BOTTOM + GRID.CELL_SIZE then
                break
            end

            -- 边缘半格裁剪由外层 nvgScissor（屏幕坐标，translate 之前设置）统一负责。
            -- ⚠️ 不要在这里加逐格 nvgIntersectScissor：cy 是 translate 后的内容坐标，
            -- 与屏幕坐标 CLIP_TOP/CLIP_BOTTOM 比较必然错位，滚动后会把可见格子裁空
            -- （历史 bug：仓库只显示第一页，下滑全空白）。

            local equip = equipList[idx]
            if equip then
                -- 教程只指向真实可穿武器；首个完整可见格优先，热点不伸出裁剪区。
                local halfCell = GRID.CELL_SIZE * 0.5
                if canGuideWeapon and not guidedWeapon and equip.slot == "weapon" and equip.canWear == true
                    and screenY - halfCell >= clipTop() and screenY + halfCell <= GRID.CLIP_BOTTOM
                    and cx - halfCell >= 0 and cx + halfCell <= DESIGN_W then
                    tutorial.registerHotspot("equip_item_gifted", cx, screenY,
                        GRID.CELL_SIZE, GRID.CELL_SIZE, "left")
                    guidedWeapon = true
                end
                DarkIcon.drawQualityBg(vg, equip.quality, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE, 1.0)

                local icon = ImageCache.getEquipIcon(equip.templateId)
                if icon and icon >= 0 then
                    DarkIcon.drawIconDark(vg, icon, cx, cy, GRID.CELL_SIZE - 10, GRID.CELL_SIZE - 10, 1.0)
                end

                -- 复用角色槽的升级图标；头像/锁仍占原左上角，不相互覆盖。
                if equip.upgrade and not equip.equippedByHeroId and not equip.locked then
                    local detail = package.loaded["ui.character.detail.CharacterDetail"]
                    local upIcon = detail and detail._imgIconUp or -1
                    if upIcon >= 0 then
                        local upSize = 40
                        DrawUtil.drawImageCentered(vg, upIcon,
                            cx - GRID.CELL_SIZE * 0.5 + upSize * 0.5 + 2,
                            cy - GRID.CELL_SIZE * 0.5 + upSize * 0.5 + 2, upSize, upSize, 1.0)
                    end
                end

                do
                    local lvlText = "Lv." .. (equip.level or 1)
                    local lvl = EquipmentSetIcon.levelLayout(equip, cx, cy, GRID.CELL_SIZE)
                    local lvlX, lvlY = lvl.x, lvl.y
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, lvl.fontSize)
                    -- 固定预留左下角标位，显示开关不让等级移位或忽大忽小。
                    local badge = EquipmentSetIcon.badgeLayout(cx, cy, GRID.CELL_SIZE)
                    local availableW = lvlX - (badge.x + badge.size) - 8
                    local textW = nvgTextBounds(vg, 0, 0, lvlText)
                    if textW > availableW then
                        nvgFontSize(vg, lvl.fontSize * availableW / textW)
                    end
                    nvgTextAlign(vg, lvl.align)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                    local sStep = math.pi * 2 / 16
                    for si = 0, 15 do
                        local sa = si * sStep
                        nvgText(vg, lvlX + math.cos(sa) * 4, lvlY + math.sin(sa) * 4, lvlText, nil)
                    end
                    nvgFillColor(vg, nvgRGBA(0xff, 0xff, 0xff, 255))
                    nvgText(vg, lvlX, lvlY, lvlText, nil)
                end

                -- 单件贡献用战力图标加数值显示，等级与套装徽记仍保留原位。
                do
                    local powerText = tostring(equip.power or 0)
                    local powerFont = 26
                    local powerIconSize, powerGap = 24, 4
                    local rightX = cx + GRID.CELL_SIZE * 0.45
                    local powerY = cy + GRID.CELL_SIZE * 0.15
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, powerFont)
                    local textW = nvgTextBounds(vg, 0, 0, powerText) or 0
                    local maxW = GRID.CELL_SIZE * 0.62
                    if textW + powerIconSize + powerGap > maxW and textW > 0 then
                        powerFont = powerFont * (maxW - powerIconSize - powerGap) / textW
                    end
                    nvgFontSize(vg, powerFont)
                    textW = nvgTextBounds(vg, 0, 0, powerText) or 0
                    DrawUtil.drawTextStroke(vg, rightX, powerY,
                        powerText, powerFont, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
                        244, 237, 224, 3)
                    DarkIcon.draw(vg, "power", rightX - textW - powerGap - powerIconSize * 0.5,
                        powerY, powerIconSize, 1.0)
                end

                if equip.enhanceLevel and equip.enhanceLevel > 0 then
                    local enhText = "+" .. equip.enhanceLevel
                    local enhX = cx + GRID.CELL_SIZE * 0.5 - 8
                    local enhY = cy - GRID.CELL_SIZE * 0.5 - 4
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
                        -- [统一角色框] 已装备头像角标（白描边变体）
                        ---@type number
                        local ownerHeroId = equip.equippedByHeroId
                        HeroFrame.draw(vg, {
                            cx = badgeX, cy = badgeY, size = badgeSize, radius = 6,
                            heroId = ownerHeroId,
                            iconHandle = ownerIcon,
                            state = "owned",
                            borderOverride = { 255, 255, 255, 200, 2 },
                        })
                    end
                end

                -- [分解入仓 0929] 旧"批量分解模式"选中遮罩已移除（分解迁移到独立 tab）

                if equip.locked and getImgLock() >= 0 then
                    local hasSetBadge = equip.equippedByHeroId and EquipmentSetIcon.hasBadge(equip)
                    -- 三角标同存时缩小锁，放于头像与左下套装徽记之间。
                    local lockSize = hasSetBadge and 32 or 56
                    local lockX = cx - GRID.CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                    local lockY
                    if hasSetBadge then
                        lockY = cy + GRID.CELL_SIZE * (10 / 160)
                    elseif equip.equippedByHeroId then
                        lockY = cy + GRID.CELL_SIZE * 0.5 - lockSize * 0.5 - 4
                    else
                        lockY = cy - GRID.CELL_SIZE * 0.5 + lockSize * 0.5 + 4
                    end
                    DrawUtil.drawImageCentered(vg, getImgLock(), lockX, lockY, lockSize, lockSize, 1.0)
                end

                -- 套装角标在数值/归属/锁之后，不可穿戴灰罩之前绘制。
                EquipmentSetIcon.drawBadge(vg, equip, cx, cy, GRID.CELL_SIZE, 1.0)

                -- 最后覆盖整格，品质、图标和角标一起灰显，但仍可查看详情。
                if equip.canWear == false then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
                        GRID.CELL_SIZE, GRID.CELL_SIZE, GRID.CELL_RADIUS + 6)
                    nvgFillColor(vg, nvgRGBA(38, 38, 38, 175))
                    nvgFill(vg)
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
        nvgScissor(vg, 0, clipTop(), DESIGN_W, clipH())
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
        getSetCounts = getSetCounts,
        drawEquipGrid = drawEquipGrid,
        buildItemList = buildItemList,
        drawItemGrid = drawItemGrid,
    }
end

return M
