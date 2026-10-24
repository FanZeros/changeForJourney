-- 旧同步列表contract的绘制/hover/peek差分；CPU边界，不加载真实GPU图片。
local M = {}
function M.run(ctx)
    local context, grids, deepCopy, fake, Link, gridState, GRID, cells, Draw, Detail, detailStateOf, clock, check, deepEqual, ES, heroes, seqByTemplate, hasWearability, setFilter, setHero, setDrawing, equipProbe =
        ctx.context, ctx.grids, ctx.deepCopy, ctx.fake, ctx.Link, ctx.gridState, ctx.GRID, ctx.cells, ctx.Draw, ctx.Detail, ctx.detailState, ctx.clock, ctx.check, ctx.deepEqual, ctx.ES, ctx.heroes, ctx.seqByTemplate, ctx.hasWearability, ctx.setFilter, ctx.setHero, ctx.setDrawing, ctx.equipProbe
    context(1, "armor", nil)
    setFilter("A31")
    local list, before = grids.getEquipList(), deepCopy(fake)
    local pointer = Link.bind({ state = gridState, GRID = GRID, CELL_COL_CX = cells,
        EquipmentDetail = Detail, DrawUtil = Draw, getEquipList = grids.getEquipList })
    local x, y = cells[1], GRID.FIRST_ROW_TOP + GRID.CELL_SIZE * 0.5
    local cell = pointer.cellAt(x, y)
    local peek = pointer.peekEquipAt(x, y)
    check(#list == 1 and cell and peek and cell.seq == list[1].seq and peek.seq == list[1].seq,
        "cellAt/peek share filtered grid list")
    pointer.openCandidate(cell, x, y, true)
    check(detailStateOf().seq == list[1].seq and Detail.isPinned(), "click/open candidate resolves same filtered item")
    Detail.close()
    pointer.handleHover(x, y); clock.elapsedTime = clock.elapsedTime + 1; pointer.handleHover(x, y)
    check(detailStateOf().seq == list[1].seq and Detail.isOpen(), "hover resolves same filtered item")
    Detail.close()
    check(pointer.cellAt(cells[2], y) == nil and pointer.peekEquipAt(cells[2], y) == nil,
        "structurally filtered-out cell has no click/peek target")

    -- native nvgRGBA 保留：只在 fillColor stub 读取 NVGcolor。
    local painted, events, masks = {}, {}, {}
    local pathRect = {}
    local greyFill = false
    local function record(kind) events[#events + 1] = kind end
    local iconCache = require("ui.widget.ImageCache")
    iconCache.getEquipIcon = function(tid) painted[#painted + 1] = tid; record("icon"); return 1 end
    local dark = require("core.DarkIcon")
    dark.drawQualityBg = function() record("quality") end
    dark.drawIconDark = function() record("iconDraw") end
    Draw.drawImageCentered = function() record("lock") end
    local heroFrame = require("ui.widget.HeroFrame")
    heroFrame.draw = function() record("ownerBadge") end
    package.preload["systems.TutorialManager"] = function() return { isActive = function() return false end } end
    nvgSave, nvgRestore, nvgScissor, nvgTranslate = function() end, function() end, function() end, function() end
    nvgBeginPath = function() pathRect = {} end
    nvgRoundedRect = function(_, rx, ry, w, h, radius)
        pathRect = { x = rx, y = ry, w = w, h = h, radius = radius }
    end
    ---@param color NVGcolor
    nvgFillColor = function(_, color)
        greyFill = math.abs(color.r * 255 - 38) < 0.01 and math.abs(color.g * 255 - 38) < 0.01
            and math.abs(color.b * 255 - 38) < 0.01 and math.abs(color.a * 255 - 175) < 0.01
    end
    nvgFill = function()
        if greyFill then record("greyMask"); masks[#masks + 1] = { rect = pathRect, eventIndex = #events } end
    end
    nvgStroke, nvgStrokeColor, nvgStrokeWidth = function() end, function() end, function() end
    nvgFontFace, nvgFontSize, nvgTextAlign = function() end, function() end, function() end
    nvgText = function() record("text") end
    nvgTextBounds = function(_, _, _, text) return #text * 12 end
    nvgCreateImage = function() return -1 end
    local function drawOnce()
        grids.getEquipList() -- 显式同步准备完整列表；Render不整库评分。
        painted, events, masks = {}, {}, {}
        pathRect, greyFill = {}, false
        grids.drawEquipGrid({})
    end
    drawOnce()
    check(#painted == 1 and painted[1] == list[1].templateId and #masks == 0,
        "wearable A31 draw matches click/hover/peek and has no grey overlay")
    check(deepEqual(fake, before), "draw/click/hover/peek do not hydrate or change source")

    setFilter("A55")
    list = grids.getEquipList()
    cell, peek = pointer.cellAt(x, y), pointer.peekEquipAt(x, y)
    check(#list == 1 and cell and cell.canWear == false and peek and peek.seq == list[1].seq,
        "unwearable A55 remains cellAt/peek target with grey flag")
    pointer.openCandidate(cell, x, y, true)
    check(detailStateOf().seq == list[1].seq and Detail.isPinned(), "unwearable grey item can open and pin detail")
    Detail.close()
    pointer.handleHover(x, y); clock.elapsedTime = clock.elapsedTime + 1; pointer.handleHover(x, y)
    check(detailStateOf().seq == list[1].seq and Detail.isOpen(), "unwearable grey item can hover-open detail")
    Detail.close()
    local actualOk, actualErr = ES.applyEquip(equipProbe(fake, list[1].seq, 1), list[1].seq, 1, "armor", heroes)
    check(actualOk == false and actualErr == list[1].cannotEquipReason,
        "grey display never relaxes real applyEquip rejection")
    check(deepEqual(fake, before), "unwearable click/hover/peek and applyEquip probe leave source unchanged")

    local greySeq = list[1].seq
    fake.inventory[tostring(greySeq)].locked = true
    fake.inventory[tostring(greySeq)].enhanceLevel = 5
    fake.equipped[99].armor = greySeq
    setDrawing({ [99] = 1 }, 1)
    before = deepCopy(fake)
    drawOnce()
    check(#painted == 1 and painted[1] == "A55" and #masks == 1,
        "unwearable A55 draws exactly one RGBA(38,38,38,175) grey mask")
    local mask = masks[1]
    local rect = mask and mask.rect
    check(rect and rect.x == x - GRID.CELL_SIZE * 0.5 and rect.y == GRID.FIRST_ROW_TOP
        and rect.w == GRID.CELL_SIZE and rect.h == GRID.CELL_SIZE and rect.radius == GRID.CELL_RADIUS + 6,
        "grey mask covers full cell with same rounded corners")
    local positions = {}
    for index, event in ipairs(events) do positions[event] = index end
    if not positions.ownerBadge or not positions.lock then print("[greyMask order] " .. table.concat(events, ",")) end
    check(mask and positions.quality and positions.iconDraw and positions.text and positions.ownerBadge and positions.lock
        and mask.eventIndex > positions.quality and mask.eventIndex > positions.iconDraw
        and mask.eventIndex > positions.text and mask.eventIndex > positions.ownerBadge and mask.eventIndex > positions.lock,
        "full-card grey mask is drawn after icon, level/enhance text, owner badge and lock")
    check(deepEqual(fake, before), "grey draw never modifies nested equipment source")
    setHero(nil)
    drawOnce()
    check(#painted == 1 and painted[1] == "A55" and hasWearability(greySeq, true) and #masks == 0,
        "manual no-hero A55 draw has no grey mask, even with lock and owner badge")
    setHero(1); setFilter("A31")
    heroes.roster["1"].level = 84
    drawOnce()
    check(hasWearability(seqByTemplate.A31, false) and #masks == 1, "level-gated A31 draws grey before upgrade")
    heroes.roster["1"].level = 85
    drawOnce()
    check(hasWearability(seqByTemplate.A31, true) and #masks == 0, "upgrade refresh removes A31 grey mask without reopening")
    check(deepEqual(fake, before), "manual and upgrade redraws leave inventory unchanged")
end
return M
