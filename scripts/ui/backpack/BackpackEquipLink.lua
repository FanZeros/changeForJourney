-- 仓库与配装/锻炉共享持有、临时部位筛选及网格指针接口。
-- 不驱动角色穿戴：详情仍以 slot=nil 打开，所有候选来自 getEquipList。
local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local SetFilterDialog = require("ui.widget.SetFilterDialog")
local M = {}
local LEFT_PAGES = {
    "ui.loot.LootBoxPage", "ui.story.task.TaskPage", "ui.church.talent.TalentPage",
    "ui.church.ChurchPage", "ui.tavern.TavernPage", "ui.market.MarketPage",
}
local SLOT_NAMES = { weapon = "主手", offhand = "副手", armor = "护甲",
    helmet = "头盔", shoes = "鞋子", accessory = "饰品" }

function M.bind(deps)
    local EquipmentDetail = deps.EquipmentDetail or EquipmentDetail
    local DrawUtil = deps.DrawUtil or DrawUtil
    local state, GRID = deps.state, deps.GRID
    local owners = {}
    local clearedPages = {}
    local serial = 0
    local manualHeld, autoSession, suppressed = false, false, false
    ---@type table|nil
    local manualView = nil
    ---@type string|nil
    local filterSlot = nil
    ---@type number|nil
    local filterHero = nil
    ---@type string|nil
    local hoverSeq = nil
    local hoverSince = 0
    local api = {}

    function api.clearCandidate(includePinned)
        hoverSeq, hoverSince = nil, 0
        if includePinned and EquipmentDetail.getOwner() == "backpack" then
            EquipmentDetail.close()
        elseif EquipmentDetail.dismissHover then
            EquipmentDetail.dismissHover("backpack")
        end
    end

    function api.getEquipmentSlotFilter() return filterSlot, filterHero end
    local function applyFilter(slot, heroId)
        local normalized = SLOT_NAMES[slot] and slot or nil
        local hero = tonumber(heroId)
        if filterSlot == normalized and filterHero == hero then return end
        local clearPinned = normalized ~= nil or filterHero ~= hero
        filterSlot, filterHero = normalized, hero
        state.scrollY, state.scrollVel, state.dragging = 0, 0, false
        -- 取消部位到全部、且仍是同一英雄时，钉住候选依然合法。
        api.clearCandidate(clearPinned)
    end
    function api.setEquipmentSlotFilter(slot, heroId)
        if owners.equipment then
            owners.equipment.slot = SLOT_NAMES[slot] and slot or nil
            owners.equipment.heroId = tonumber(heroId)
        end
        applyFilter(slot, heroId)
    end

    local function captureView()
        return { mode = deps.getHostMode(), tab = state.tab, scrollY = state.scrollY,
            scrollMax = state.scrollMax, slot = filterSlot, heroId = filterHero }
    end
    local function getLeftPage(path, load)
        if deps.getLeftPage then return deps.getLeftPage(path, load) end
        if load then return require(path) end
        return package.loaded[path]
    end
    local function closeOtherLeftPages()
        for _, path in ipairs(LEFT_PAGES) do
            local ok, page = pcall(function() return getLeftPage(path, true) end)
            if ok and page.isOpen and page.isOpen() then
                if page.forceClose then
                    page.forceClose()
                else
                    page.close()
                    -- Task 等仅动画关闭的页先容许它收尾；若被再次打开则视为玩家导航。
                    clearedPages[path] = page.getSeamAnim and { page.getSeamAnim() } or true
                end
            end
        end
        local talent = getLeftPage("ui.church.talent.TalentPage", false)
        if talent and talent.resetHorizonLayout then talent.resetHorizonLayout() end
    end
    local function latestOwner()
        local latest = nil
        for _, holder in pairs(owners) do
            if not latest or holder.order > latest.order then latest = holder end
        end
        return latest
    end

    -- 仅 acquire 的进入边沿开仓；重复 acquire 与筛选刷新均不重新 open。
    function api.acquireWarehouse(owner, heroId, slot)
        if owners[owner] then
            if owner == "equipment" then api.setEquipmentSlotFilter(slot, heroId) end
            return state.open and not state.closing
        end
        local first = not next(owners)
        if first and state.open and not state.closing and manualHeld then manualView = captureView() end
        serial = serial + 1
        owners[owner] = { order = serial, heroId = tonumber(heroId), slot = SLOT_NAMES[slot] and slot or nil }
        if suppressed then return false end
        closeOtherLeftPages()
        if state.closing and autoSession then
            -- 自动 release 的关仓动画可由新持有者接续；手动 close 不可取消。
            state.closing, state.closeTime = false, 0
        elseif not state.open then
            deps.openPage("left", "equip")
            autoSession = true
        elseif state.closing then
            suppressed = true
            return false
        end
        if deps.getHostMode() ~= "left" then
            if deps.setLeftMode then deps.setLeftMode() end
        end
        deps.selectEquipTab()
        api.clearCandidate(true)
        local holder = owners[owner]
        applyFilter(holder.slot, holder.heroId)
        print("[BackpackEquipLink] acquire " .. tostring(owner) .. " manual=" .. tostring(manualHeld))
        return true
    end

    function api.releaseWarehouse(owner)
        if not owners[owner] then return end
        owners[owner] = nil
        local nextHolder = latestOwner()
        if nextHolder then
            applyFilter(nextHolder.slot, nextHolder.heroId)
            return
        end
        api.clearCandidate(true)
        if manualHeld and manualView and not suppressed and state.open and not state.closing then
            local view = manualView
            applyFilter(view.slot, view.heroId)
            deps.restoreView(view)
        else
            api.setEquipmentSlotFilter(nil, nil)
            if autoSession and state.open and not state.closing and not suppressed then deps.closePage() end
        end
        manualView, suppressed = nil, false
        print("[BackpackEquipLink] release " .. tostring(owner))
    end

    function api.onManualOpen()
        manualHeld, autoSession, suppressed = true, false, false
        -- 自动期间玩家明确打开仓库即接管，不把配装的临时 slot 变成用户筛选。
        applyFilter(nil, nil)
        manualView = next(owners) and captureView() or nil
        api.clearCandidate(true)
    end
    function api.onManualClose()
        manualHeld, autoSession = false, false
        manualView = nil
        suppressed = next(owners) ~= nil
        api.clearCandidate(true)
    end
    function api.onManualTabChange()
        api.clearCandidate(true)
        if manualHeld and manualView then
            manualView.tab, manualView.scrollY, manualView.scrollMax = state.tab, 0, 0
        end
    end
    function api.update()
        if not state.open then
            autoSession = false
            return
        end
        if state.closing or deps.getHostMode() ~= "left" then return end
        -- 其他左页由玩家打开后不要压在其上，也不在后续帧自动重开。
        for _, path in ipairs(LEFT_PAGES) do
            local page = getLeftPage(path, false)
            local wasCleared = clearedPages[path]
            if page and page.isOpen and page.isOpen() then
                if wasCleared then
                    local stillClosing = wasCleared == true
                    if type(wasCleared) == "table" and page.getSeamAnim then
                        local ot, ct = page.getSeamAnim()
                        stillClosing = ot == wasCleared[1] and ct == wasCleared[2]
                    end
                    if stillClosing then goto continue_page end
                    clearedPages[path] = nil
                end
                api.onManualClose()
                deps.closePage()
                return
            else
                clearedPages[path] = nil
            end
            ::continue_page::
        end
    end

    function api.cellAt(dx, dy)
        if not state.open or state.closing or state.tab ~= "equip" or SetFilterDialog.isOpen() then return nil end
        if dy < GRID.FIRST_ROW_TOP or dy > GRID.CLIP_BOTTOM then return nil end
        for idx, equip in ipairs(deps.getEquipList()) do
            local col = ((idx - 1) % GRID.COLS) + 1
            local row = math.floor((idx - 1) / GRID.COLS)
            local cx = deps.CELL_COL_CX[col]
            local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5 - state.scrollY
            if DrawUtil.hitTest(dx, dy, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE) then
                return equip, cx, cy
            end
        end
        return nil
    end
    function api.clickItem(dx, dy)
        if state.tab ~= "item" or dy < GRID.FIRST_ROW_TOP or dy > GRID.CLIP_BOTTOM then return false end
        for idx, def in ipairs(deps.buildItemList()) do
            local col = ((idx - 1) % GRID.COLS) + 1
            local row = math.floor((idx - 1) / GRID.COLS)
            local cx = deps.CELL_COL_CX[col]
            local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5 - state.scrollY
            if DrawUtil.hitTest(dx, dy, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE) then
                deps.itemDetState.open, deps.itemDetState.def = true, def
                deps.itemDetState.openTime = time.elapsedTime
                return true
            end
        end
        return false
    end

    function api.peekEquipAt(dx, dy)
        local equip = api.cellAt(dx, dy)
        if not equip then return nil end
        return { seq = equip.seq, templateId = equip.templateId, quality = equip.quality or 1,
            slot = equip.slot, grip = equip.grip, equipType = equip.type }
    end
    function api.openCandidate(equip, cx, cy, pinned)
        EquipmentDetail.open(equip.seq, nil, nil, true, "backpack",
            cx + GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5)
        if pinned and EquipmentDetail.pin then EquipmentDetail.pin() end
    end
    function api.handleHover(dx, dy)
        if state.open and not state.closing and state.tab == "decompose" and not SetFilterDialog.isOpen() then
            deps.ensureDecomposeReady()
            deps.BlacksmithDecompose.handleHover(dx, dy)
            return
        end
        local equip, cx, cy = api.cellAt(dx, dy)
        if not equip then api.clearCandidate(false); return end
        local seq = tostring(equip.seq)
        if hoverSeq ~= seq then
            hoverSeq, hoverSince = seq, time.elapsedTime
            if EquipmentDetail.dismissHover then EquipmentDetail.dismissHover("backpack") end
            return
        end
        if time.elapsedTime - hoverSince < 0.3 then return end
        if EquipmentDetail.isOpen() then
            if EquipmentDetail.getOwner() ~= "backpack" or EquipmentDetail.isPinned() then return end
            EquipmentDetail.setAnchor(cx + GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5)
            return
        end
        api.openCandidate(equip, cx, cy, false)
    end

    function api.haltScroll() state.dragging, state.scrollVel = false, 0 end
    function api.handleDragBegin(dx, dy)
        if not state.open then return false end
        if SetFilterDialog.isOpen() or deps.itemDetState.open then return true end
        if EquipmentDetail.isOpen() then return EquipmentDetail.handleDragBegin(dx, dy) end
        if state.tab == "decompose" then deps.BlacksmithDecompose.handleDragBegin(dx, dy); return true end
        if dy >= GRID.FIRST_ROW_TOP and dy <= GRID.CLIP_BOTTOM then
            state.dragging, state.lastDragY, state.scrollVel = true, dy, 0
        end
        return true
    end
    function api.handleDragMove(dx, dy)
        if not state.open then return false end
        if SetFilterDialog.isOpen() or deps.itemDetState.open then return true end
        if EquipmentDetail.isOpen() then return EquipmentDetail.handleDragMove(dx, dy) end
        if state.tab == "decompose" then deps.BlacksmithDecompose.handleDragMove(dx, dy); return true end
        if state.dragging then
            local delta = state.lastDragY - dy
            state.scrollY, state.scrollVel, state.lastDragY = state.scrollY + delta, delta, dy
            deps.clampScroll()
        end
        return true
    end
    function api.handleDragEnd(dx, dy)
        if not state.open then return false end
        if SetFilterDialog.isOpen() or deps.itemDetState.open then return true end
        if EquipmentDetail.isOpen() then return EquipmentDetail.handleDragEnd(dx, dy) end
        if state.tab == "decompose" then deps.BlacksmithDecompose.handleDragEnd(dx, dy); return true end
        state.dragging = false
        return true
    end
    function api.handleScroll(wheel, dx, dy)
        if not state.open then return false end
        if SetFilterDialog.isOpen() or deps.itemDetState.open then return true end
        if EquipmentDetail.isOpen() and (dx == nil or EquipmentDetail.containsPoint(dx, dy)) then
            return EquipmentDetail.handleScroll(wheel, dx, dy)
        end
        if state.tab == "decompose" then deps.BlacksmithDecompose.handleScroll(wheel, dx, dy); return true end
        state.scrollY = state.scrollY - wheel * deps.SCROLL_WHEEL_STEP
        deps.clampScroll()
        return true
    end

    -- 利用品质条和网格之间的留白，不移动/覆盖现有筛选与 Tab。
    local function filterBarCY() return GRID.FIRST_ROW_TOP - 54 end
    function api.drawFilterHint(vg)
        if state.tab ~= "equip" then return end
        local label = filterSlot and ("部位筛选 · " .. SLOT_NAMES[filterSlot]) or "部位筛选 · 全部"
        local cy = filterBarCY()
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
        nvgText(vg, 80, cy, label, nil)
        if filterSlot then
            DarkIcon.drawNine(vg, "btn", 780, cy - 24, 220, 48, { accent = "gold" })
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, 890, cy, "取消部位", nil)
        end
    end
    function api.handleFilterInput(dx, dy)
        if state.tab ~= "equip" or not filterSlot then return false end
        if not DrawUtil.hitTest(dx, dy, 890, filterBarCY(), 220, 48) then return false end
        api.setEquipmentSlotFilter(nil, filterHero)
        if deps.onClearEquipmentSlot then
            deps.onClearEquipmentSlot()
        else
            local detail = require("ui.character.detail.CharacterDetail")
            if detail.clearEquipmentSlot then detail.clearEquipmentSlot() end
        end
        return true
    end
    return api
end
return M
