-- 仓库与配装/锻炉共享持有、临时部位筛选及网格指针接口。
-- 单击仅钉住候选；有效双击/右键经只读预检后走权威穿戴 action。
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
    local SetFilterDialog = deps.SetFilterDialog or SetFilterDialog
    local state, GRID = deps.state, deps.GRID
    local owners = {}
    local clearedPages = {}
    local serial = 0
    local manualHeld, autoSession, suppressed = false, false, false
    local tutorialPrepared = false
    ---@type table|nil
    local manualView = nil
    ---@type string|nil
    local filterSlot = nil
    ---@type number|nil
    local filterHero = nil
    ---@type string|nil
    local hoverSeq = nil
    local hoverSince = 0
    -- 双击历史独立于悬停/钉住状态；调用者仅把确认的 tap 交给 handleEquipClick。
    ---@type {seq:string, hero:number|nil, slot:string|nil, time:number}|nil
    local click = nil
    ---@type {seq:number|string, hero:number, slot:string, time:number}|nil
    local pending = nil
    ---@type {x:number, y:number}|nil
    local dragPress = nil
    local api = {}

    function api.clearQuickClick() click = nil end

    local function toast(text)
        if deps.toast then deps.toast(text)
        else require("core.UiToast").show(text) end
    end
    local function expirePending()
        if pending and time.elapsedTime - pending.time >= 3 then
            pending = nil
            api.clearQuickClick()
            toast("穿戴请求超时，请重试")
        end
    end
    local function getCharacterDetail()
        if deps.getCharacterDetail then return deps.getCharacterDetail() end
        return require("ui.character.detail.CharacterDetail")
    end
    local function currentHero()
        local detail = getCharacterDetail()
        if not detail or not detail.isEquipTab or not detail.isEquipTab() then return nil end
        return tonumber(detail.getHeroId())
    end
    local function getEquipmentData()
        if deps.getEquipmentData then return deps.getEquipmentData() end
        return require("core.PlayerStore").Get("equipment")
    end
    local function getHeroesData()
        if deps.getHeroesData then return deps.getHeroesData() end
        return require("core.PlayerStore").Get("heroes")
    end
    local function wearability()
        return deps.EquipmentWearability or require("ui.character.detail.EquipmentWearability")
    end
    local function equipAction()
        return require("shared.Protocol").ACTION_TYPES.EQUIP_ITEM
    end
    local function targetSlot(equip, heroId)
        -- 临时筛选可能仍属于前一英雄，不能把旧副手槽应用到当前角色。
        if heroId and filterHero == heroId and filterSlot then return filterSlot end
        -- 源存档可能尚未水合，不能借用列表的 canWear/旧职业上下文。
        local equipment = getEquipmentData()
        local inventory = equipment and equipment.inventory
        local source = inventory and (inventory[tostring(equip.seq)] or inventory[equip.seq]) or equip
        local naturalSlot = wearability().getFields(source)
        return naturalSlot
    end
    local function tryQuickEquip(equip, heroId, slot)
        expirePending()
        if not heroId then toast("请先打开角色配装页"); return false end
        if pending then return true end -- 单一在途请求，右键/双击均不重入。
        local equipment = getEquipmentData()
        local ok, reason = wearability().canEquip(equipment, equip.seq, heroId, slot, getHeroesData())
        if not ok then toast(reason or "无法穿戴"); return false end
        local equipped = equipment and equipment.equipped
        local slots = equipped and (equipped[heroId] or equipped[tostring(heroId)])
        if slots and slots[slot] ~= nil and tostring(slots[slot]) == tostring(equip.seq) then
            toast("已装备")
            require("systems.TutorialManager").notifyEvent("equipment_equipped")
            return true -- 快捷穿戴永远不是卸装/切换按钮。
        end
        if not slot then toast("参数缺失"); return false end
        -- 必须在 dispatch 前登记：单机桥可能同步回调 onActionResult。
        pending = { seq = equip.seq, hero = heroId, slot = slot, time = time.elapsedTime }
        local send = deps.sendAction or require("runtime.GameAction").sendAction
        local handled = send(equipAction(), { seq = equip.seq, heroId = heroId, slot = slot })
        -- handled 仅表示路由接收，不代表业务成功；成功提示只由匹配回执触发。
        if handled == false and pending then
            pending = nil
            toast("穿戴请求未处理，请重试")
        end
        return true
    end

    function api.onActionResult(data)
        expirePending()
        if not pending or not data or data.action ~= equipAction() then return end
        if tostring(data.seq) ~= tostring(pending.seq) or tonumber(data.heroId) ~= pending.hero
            or data.slot ~= pending.slot then return end
        local request = pending
        pending = nil
        api.clearQuickClick()
        if data.success == true then
            -- 只关本请求的仓库候选；期间换选的另一件或他栏详情不得被回执误关。
            local selection = EquipmentDetail.getSelection and EquipmentDetail.getSelection()
            if EquipmentDetail.getOwner() == "backpack"
                and (not selection or tostring(selection.seq) == tostring(request.seq)) then
                api.clearCandidate(true)
            end
            if deps.markPanelDirty then deps.markPanelDirty()
            else
                local detail = getCharacterDetail()
                if detail and detail.markPowerDirty then detail.markPowerDirty() end
            end
            toast("已装备")
            require("systems.TutorialManager").notifyEvent("equipment_equipped")
            if deps.GameSFX then deps.GameSFX.play("install")
            else require("systems.GameSFX").play("install") end
        else
            toast(data.reason or "穿戴失败")
        end
    end

    function api.clearCandidate(includePinned)
        api.clearQuickClick()
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
        api.clearQuickClick()
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

    -- 教程显式恢复与普通 acquire 分离：只有此入口可解除同会话手动关仓抑制。
    -- 重复 ensure 不重新 open、不重置滚动，也不持续关闭玩家刚钉住的候选。
    ---@param heroId number|string|nil
    ---@param slot string|nil
    ---@return boolean changed
    function api.ensureTutorialEquipment(heroId, slot)
        local hero = tonumber(heroId)
        local normalized = SLOT_NAMES[slot] and slot or nil
        local changed = not tutorialPrepared or suppressed or not owners.equipment
            or not state.open or state.closing or deps.getHostMode() ~= "left"
            or state.tab ~= "equip" or (state.tabFrom ~= nil and state.tabFrom ~= "equip")
            or filterSlot ~= normalized or filterHero ~= hero
        if deps.clearTutorialFilters and deps.clearTutorialFilters() then changed = true end
        if SetFilterDialog.isOpen() or (deps.itemDetState and deps.itemDetState.open) then changed = true end
        for _, path in ipairs(LEFT_PAGES) do
            local page = getLeftPage(path, false)
            if page and page.isOpen and page.isOpen() then changed = true; break end
        end
        if not changed then return false end

        if not owners.equipment then
            if not next(owners) and state.open and not state.closing and manualHeld then
                manualView = captureView()
            end
            serial = serial + 1
            owners.equipment = { order = serial, heroId = hero, slot = normalized }
        else
            owners.equipment.heroId, owners.equipment.slot = hero, normalized
        end
        suppressed = false
        closeOtherLeftPages()
        if not state.open or state.closing then
            deps.openPage("left", "equip")
            autoSession = true
        elseif deps.getHostMode() ~= "left" and deps.setLeftMode then
            deps.setLeftMode()
        end
        if state.tab ~= "equip" then deps.selectEquipTab() end
        state.tabFrom, state.tabSwitchTime = "equip", 0
        SetFilterDialog.close()
        state.scrollY, state.scrollVel, state.dragging = 0, 0, false
        if deps.itemDetState then deps.itemDetState.open, deps.itemDetState.def = false, nil end
        api.clearCandidate(true)
        applyFilter(normalized, hero)
        tutorialPrepared = true
        return true
    end

    function api.releaseWarehouse(owner)
        api.clearQuickClick()
        if owner == "equipment" then tutorialPrepared = false end
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
        expirePending() -- 关仓/切页后仍回收在途锁，不依赖后续点击。
        if not state.open then
            api.clearQuickClick()
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
    function api.handleEquipClick(dx, dy)
        expirePending()
        if deps.itemDetState and deps.itemDetState.open then api.clearQuickClick(); return false end
        local equip, cx, cy = api.cellAt(dx, dy)
        if not equip then api.clearQuickClick(); return false end
        local heroId = currentHero()
        local slot = targetSlot(equip, heroId)
        local seq, now = tostring(equip.seq), time.elapsedTime
        local double = click and click.seq == seq and click.hero == heroId and click.slot == slot
            and now >= click.time and now - click.time <= 0.35
        if double then
            api.clearQuickClick()
            if heroId then
                if not tryQuickEquip(equip, heroId, slot) then api.openCandidate(equip, cx, cy, true) end
            else
                api.openCandidate(equip, cx, cy, true)
            end
        else
            click = { seq = seq, hero = heroId, slot = slot, time = now }
            api.openCandidate(equip, cx, cy, true)
        end
        return true -- 只 consume 真实筛选网格格子，未命中仍留给原详情/筛选处理。
    end
    function api.handleRightClick(dx, dy)
        api.clearQuickClick()
        expirePending()
        if deps.itemDetState and deps.itemDetState.open then return false end
        local equip = api.cellAt(dx, dy)
        if not equip then return false end
        local heroId = currentHero()
        tryQuickEquip(equip, heroId, targetSlot(equip, heroId))
        return true
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

    function api.haltScroll()
        api.clearQuickClick()
        dragPress = nil
        state.dragging, state.scrollVel = false, 0
    end
    function api.handleDragBegin(dx, dy)
        if not state.open then return false end
        -- 每次按下只记起点，不清双击历史；真实移动/外层拖装 armed 才清。
        dragPress = { x = dx, y = dy }
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
        if dragPress and (math.abs(dx - dragPress.x) > 12 or math.abs(dy - dragPress.y) > 12) then
            api.clearQuickClick()
            dragPress = nil
        end
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
        dragPress = nil
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
        -- 中间留白放显示勾选，不改变筛选、列表或右侧取消部位按钮。
        local enabled = require("ui.widget.EquipmentSetIcon").isEnabled()
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 480, cy - 18, 36, 36, 6)
        nvgFillColor(vg, nvgRGBA(16, 13, 10, 230))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(196, 160, 90, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        if enabled then
            nvgBeginPath(vg)
            nvgMoveTo(vg, 488, cy)
            nvgLineTo(vg, 496, cy + 8)
            nvgLineTo(vg, 509, cy - 9)
            nvgStrokeColor(vg, nvgRGBA(244, 226, 174, 255))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end
        nvgFillColor(vg, nvgRGBA(216, 201, 163, 255))
        nvgText(vg, 530, cy, "套装图标", nil)
        if filterSlot then
            DarkIcon.drawNine(vg, "btn", 780, cy - 24, 220, 48, { accent = "gold" })
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, 890, cy, "取消部位", nil)
        end
    end
    function api.handleFilterInput(dx, dy)
        if state.tab ~= "equip" then return false end
        if DrawUtil.hitTest(dx, dy, 605, filterBarCY(), 250, 48) then
            local settings = require("ui.hud.popup.SettingsPanel")
            settings.setSetIconsEnabled(not settings.isSetIconsEnabled())
            return true
        end
        if not filterSlot then return false end
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
