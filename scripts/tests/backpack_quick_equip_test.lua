-- 快捷装配回归：只注入 UI/发送边界，穿戴预检仍使用真实 EquipmentWearability。
-- .cli/UrhoXRuntime tests/backpack_quick_equip_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
local passes, failures = 0, 0
local function check(ok, label)
    if ok then passes = passes + 1; print("[PASS] " .. label)
    else failures = failures + 1; print("[FAIL] " .. label) end
end
local clock = { elapsedTime = 10 }
time = clock
local function stub(path, value)
    package.loaded[path] = value
    package.preload[path] = function() return value end
end
local Draw = { hitTest = function(x, y, cx, cy, w, h)
    return math.abs(x - cx) <= w / 2 and math.abs(y - cy) <= h / 2
end }
stub("core.DrawUtil", Draw)
stub("core.DarkIcon", {})
local modal = { open = false }
stub("ui.widget.SetFilterDialog", { isOpen = function() return modal.open end })
stub("ui.character.equip.EquipmentDetail", {})
local Link = require("ui.backpack.BackpackEquipLink")
local Wearability = require("ui.character.detail.EquipmentWearability")
local AT = require("shared.Protocol").ACTION_TYPES
local GRID = { FIRST_ROW_TOP = 470, CLIP_BOTTOM = 1980, CELL_SIZE = 160, GAP = 30, COLS = 5 }
local X, Y = 160, 550

local function fixture(useDefaultToast)
    clock.elapsedTime, modal.open = 10, false
    ---@type number|string
    local firstSeq = 11
    local f = {
        state = { open = true, closing = false, tab = "equip", scrollY = 0, scrollVel = 0 },
        current = { hero = 1, equipTab = true },
        equipment = { inventory = {
            ["11"] = { templateId = "W1", level = 85, quality = 1 },
            ["12"] = { templateId = "W13", level = 85, quality = 1 },
            ["13"] = { templateId = "W31", level = 85, quality = 1 },
        }, equipped = {} },
        heroes = { roster = { [1] = { level = 100 }, [2] = { level = 100 } } },
        list = { { seq = firstSeq, slot = "weapon", canWear = false, cannotEquipReason = "stale" },
            { seq = 12, slot = "weapon" } },
        detail = { open = false, pinned = false },
        itemDetState = { open = false },
        sent = {}, toasts = {}, sfx = {}, dirty = 0, opens = 0, closes = 0, validations = {},
        handled = true,
    }
    local detail = {
        getOwner = function() return f.detail.owner end,
        getSelection = function()
            if not f.detail.open then return nil end
            return { seq = f.detail.seq, owner = f.detail.owner }
        end,
        isOpen = function() return f.detail.open end,
        isPinned = function() return f.detail.pinned end,
        open = function(seq, slot, hero, _, owner)
            f.opens = f.opens + 1
            f.detail = { open = true, seq = seq, slot = slot, hero = hero, owner = owner }
        end,
        pin = function() f.detail.pinned = true end,
        close = function() f.closes = f.closes + 1; f.detail.open = false end,
        dismissHover = function(owner)
            if f.detail.owner == owner and not f.detail.pinned then f.detail.open = false end
        end,
        handleDragBegin = function() return true end,
        handleDragMove = function() return true end,
        handleDragEnd = function() return true end,
    }
    local character = {
        getHeroId = function() return f.current.hero end,
        isEquipTab = function() return f.current.equipTab end,
    }
    local toastSink = function(text) f.toasts[#f.toasts + 1] = text end
    f.api = Link.bind({ state = f.state, GRID = GRID, CELL_COL_CX = { 160, 350, 540, 730, 920 },
        EquipmentDetail = detail, DrawUtil = Draw, itemDetState = f.itemDetState,
        SetFilterDialog = { isOpen = function() return modal.open end },
        getEquipList = function() return f.list end,
        getCharacterDetail = function() return character end,
        getEquipmentData = function() return f.equipment end,
        getHeroesData = function() return f.heroes end,
        EquipmentWearability = {
            getFields = Wearability.getFields,
            canEquip = function(equipment, seq, hero, slot, heroes)
                f.validations[#f.validations + 1] = { seq = seq, hero = hero, slot = slot }
                check(equipment == f.equipment and heroes == f.heroes, "precheck receives current full snapshots")
                return Wearability.canEquip(equipment, seq, hero, slot, heroes)
            end,
        },
        sendAction = function(action, params)
            f.sent[#f.sent + 1] = { action = action, seq = params.seq, heroId = params.heroId, slot = params.slot }
            if f.onSend then f.onSend(params) end
            return f.handled
        end,
        toast = not useDefaultToast and toastSink or nil,
        markPanelDirty = function() f.dirty = f.dirty + 1 end,
        GameSFX = { play = function(name) f.sfx[#f.sfx + 1] = name end },
        getLeftPage = function() return nil end, getHostMode = function() return "left" end,
        clampScroll = function() end, SCROLL_WHEEL_STEP = 60,
    })
    return f
end
local function tap(f, delay, x, y)
    clock.elapsedTime = clock.elapsedTime + (delay or 0)
    return f.api.handleEquipClick(x or X, y or Y)
end
local function ack(f, success, reason)
    local request = f.sent[#f.sent]
    f.api.onActionResult({ action = request.action, seq = tostring(request.seq),
        heroId = tostring(request.heroId), slot = request.slot, success = success, reason = reason })
end
local function lastToast(f) return f.toasts[#f.toasts] end

local function runClicks()
    local f = fixture()
    check(tap(f) and #f.sent == 0 and f.opens == 1 and f.detail.pinned,
        "single actual-cell tap pins candidate and never sends")
    check(f.detail.slot == nil and f.detail.hero == nil, "candidate remains a read-only warehouse detail")
    check(tap(f, 0.35) and #f.sent == 1 and f.opens == 1, "same seq/hero/slot double at 0.35s sends exactly once")
    check(f.sent[1].action == AT.EQUIP_ITEM and f.sent[1].seq == 11
        and f.sent[1].heroId == 1 and f.sent[1].slot == "weapon", "double uses authoritative action and natural main slot")
    check(#f.toasts == 0 and #f.sfx == 0 and f.dirty == 0 and f.detail.open,
        "handled=true is not success: no immediate toast/sound/close/dirty")
    f.api.handleRightClick(X, Y); tap(f, 0.01); tap(f, 0.01)
    check(#f.sent == 1, "pending prevents right/double reentry")

    f = fixture(); f.api.handleRightClick(X, Y)
    check(#f.sent == 1 and f.opens == 0 and #f.toasts == 0, "one right click sends without opening candidate or premature success")
    check(#f.validations == 1, "stale canWear=false does not suppress current full validation")

    f = fixture(); tap(f); tap(f, 0.1, 350); check(#f.sent == 0, "different sequence is a new single tap")
    tap(f, 0.1, 350); check(#f.sent == 1 and f.sent[1].seq == 12, "second sequence needs its own second tap")
    f = fixture(); tap(f); f.current.hero = 2; tap(f, 0.1)
    check(#f.sent == 0 and f.opens == 2, "hero change cannot combine taps")
    f = fixture(); tap(f); f.api.setEquipmentSlotFilter("offhand", 1); tap(f, 0.1)
    check(#f.sent == 0, "slot-filter change cannot combine taps")
    f = fixture(); tap(f); tap(f, 0.351)
    check(#f.sent == 0 and f.opens == 2, "after 0.35s second tap is a new single")
    f = fixture(); tap(f); f.list[1].seq = "11"; tap(f, 0.1)
    check(#f.sent == 1, "numeric/string sequence identities normalize consistently")
end

local function runNoRoleAndRefusals()
    local f = fixture(); f.current.equipTab = false
    check(f.api.handleRightClick(X, Y) and #f.sent == 0 and lastToast(f) == "请先打开角色配装页",
        "no current equip tab consumes actual right cell and guides player")
    check(not f.api.handleRightClick(1040, Y) and #f.toasts == 1, "no role right click outside actual cell is not consumed/toasted")
    tap(f); tap(f, 0.1)
    check(#f.sent == 0 and f.opens == 2 and f.detail.pinned and #f.toasts == 1,
        "no role single/double still pin normally without wearing or extra toast")
    f.current.equipTab, f.current.hero = true, nil
    f.api.handleRightClick(X, Y)
    check(#f.sent == 0 and lastToast(f) == "请先打开角色配装页", "nil hero cannot wear")

    f = fixture(); f.heroes.roster[1].level = 1
    f.list[1].canWear, f.list[1].cannotEquipReason = true, "stale"
    f.api.handleRightClick(X, Y)
    check(#f.sent == 0 and lastToast(f) == "角色等级不足，需要等级 85", "right grey item shows live level refusal, not stale list flag/reason")
    f.heroes.roster[1].level = 100
    f.api.handleRightClick(X, Y)
    check(#f.sent == 1, "after live level recovery next right can wear without reopening")
    f = fixture(); f.list[1].seq = 13
    f.api.handleRightClick(X, Y)
    check(#f.sent == 0 and lastToast(f) == "该英雄无法穿戴此类型装备", "class refusal uses true rule reason")
    tap(f); tap(f, 0.1)
    check(#f.sent == 0 and f.opens == 2 and f.detail.pinned, "nonwearable double retains pin and does not send")
    f = fixture(); f.equipment.inventory["11"] = nil
    f.api.handleRightClick(X, Y)
    check(#f.sent == 0 and lastToast(f) == "装备不存在", "inventory deletion between draw and click is refused")
end

local function runAck()
    local f = fixture(); tap(f); tap(f, 0.1)
    for _, bad in ipairs({
        { action = AT.UNEQUIP_ITEM, seq = 11, heroId = 1, slot = "weapon", success = true },
        { action = AT.EQUIP_ITEM, seq = 12, heroId = 1, slot = "weapon", success = true },
        { action = AT.EQUIP_ITEM, seq = 11, heroId = 2, slot = "weapon", success = true },
        { action = AT.EQUIP_ITEM, seq = 11, heroId = 1, slot = "offhand", success = true },
        { action = AT.EQUIP_ITEM, success = false, reason = "unmatched" },
    }) do f.api.onActionResult(bad) end
    check(f.dirty == 0 and #f.toasts == 0 and #f.sfx == 0, "wrong action/seq/hero/slot and unkeyed fail leave pending untouched")
    f.api.handleRightClick(X, Y); check(#f.sent == 1, "unmatched ack does not unlock pending")
    ack(f, false, "服务器拒绝")
    check(lastToast(f) == "服务器拒绝" and f.detail.open and f.dirty == 0 and #f.sfx == 0,
        "matched fail clears pending, toasts reason, keeps candidate")
    f.api.handleRightClick(X, Y); check(#f.sent == 2, "fail immediately permits retry")
    ack(f, true)
    check(not f.detail.open and f.closes == 1 and f.dirty == 1 and lastToast(f) == "已装备"
        and #f.sfx == 1 and f.sfx[1] == "install", "matched success closes own candidate, marks dirty and celebrates once")
    ack(f, true); check(f.dirty == 1 and #f.sfx == 1, "duplicate success ack is ignored")

    f = fixture(); tap(f); tap(f, 0.1); tap(f, 0.1, 350); ack(f, true)
    check(f.detail.open and f.detail.seq == 12 and f.closes == 0, "success never closes a newer different candidate")
    f = fixture(); tap(f); tap(f, 0.1); f.detail.owner = "character"; ack(f, true)
    check(f.detail.open and f.closes == 0, "success never closes another panel's detail")
    f = fixture(); f.onSend = function() ack(f, true) end
    f.api.handleRightClick(X, Y)
    check(f.dirty == 1 and #f.sfx == 1 and lastToast(f) == "已装备", "synchronous dispatch ack observes pending registered before send")
end

local function runTimeoutAndResets()
    local f = fixture(); f.api.handleRightClick(X, Y)
    clock.elapsedTime = 12.999; f.api.update(); f.api.handleRightClick(X, Y)
    check(#f.sent == 1 and #f.toasts == 0, "pending remains locked before 3s")
    clock.elapsedTime = 13; f.state.open = false; f.api.update()
    check(lastToast(f) == "穿戴请求超时，请重试", "hard 3s timeout also recovers while warehouse is closed")
    ack(f, true); check(f.dirty == 0 and #f.sfx == 0, "late success after timeout is ignored")
    f.state.open = true; f.api.handleRightClick(X, Y)
    check(#f.sent == 2, "timeout permits a new right request")
    f = fixture(); f.handled = false; f.api.handleRightClick(X, Y); f.api.handleRightClick(X, Y)
    check(#f.sent == 2 and lastToast(f) == "穿戴请求未处理，请重试" and #f.sfx == 0,
        "unhandled dispatch recovers immediately, never interpreted as success")

    for _, reset in ipairs({
        function(api) api.clearQuickClick() end,
        function(api) api.clearCandidate(false) end,
        function(api) api.haltScroll() end,
        function(api) api.onManualOpen() end,
        function(api) api.releaseWarehouse("equipment") end,
        function(api) api.setEquipmentSlotFilter(nil, 1) end,
    }) do
        f = fixture(); tap(f); reset(f.api); tap(f, 0.1)
        check(#f.sent == 0, "history reset prevents next single from wearing")
    end
    f = fixture(); tap(f); check(not tap(f, 0.1, 1040), "outside cell returns false and clears history")
    tap(f, 0.1); check(#f.sent == 0, "outside click between taps prevents double")
    f = fixture(); tap(f); f.api.handleDragBegin(X, Y); f.api.handleDragMove(X + 2, Y + 2)
    f.api.handleDragEnd(X, Y); tap(f, 0.1)
    check(#f.sent == 1, "pointer begin/small jitter do not break a genuine double")
    f = fixture(); tap(f); f.api.handleDragBegin(X, Y); f.api.handleDragMove(X + 30, Y)
    f.api.handleDragEnd(X, Y); tap(f, 0.1)
    check(#f.sent == 0, "actual drag movement clears history before detail delegation")
    f = fixture(); modal.open = true
    check(not f.api.handleEquipClick(X, Y) and not f.api.handleRightClick(X, Y), "set modal blocks actual-cell shortcut")
    modal.open = false; f.state.tab = "item"
    check(not f.api.handleEquipClick(X, Y) and not f.api.handleRightClick(X, Y), "non-equip warehouse tab cannot quick wear")
    f.state.tab, f.state.scrollY = "equip", 190
    check(not f.api.handleRightClick(X, Y), "hit target uses same scroll-transformed filtered grid, no phantom cell")
end

local function runSlots()
    local f = fixture()
    f.heroes.roster[1].advBranch = { first = 104, second = 207 }
    f.equipment.equipped["1"] = { weapon = "11" }
    f.api.setEquipmentSlotFilter("offhand", 1)
    f.api.handleRightClick(350, Y)
    check(#f.sent == 1 and f.sent[1].seq == 12 and f.sent[1].slot == "offhand", "explicit dual offhand sends weapon to selected offhand")
    f = fixture(); f.heroes.roster[1].advBranch = { first = 104, second = 207 }
    f.equipment.equipped[1] = { weapon = 11 }; f.api.setEquipmentSlotFilter("offhand", 1)
    f.api.handleRightClick(X, Y)
    check(#f.sent == 0 and lastToast(f) == "武器精通：副手必须装备不同类型的武器", "dual same-type offhand refusal is preserved")
    f = fixture(); f.api.setEquipmentSlotFilter("offhand", 1); f.api.handleRightClick(X, Y)
    check(#f.sent == 0 and lastToast(f) == "槽位不匹配", "ordinary hero cannot wear weapon as offhand")
    f = fixture(); f.equipment.equipped["1"] = { weapon = "11" }
    f.api.handleRightClick(X, Y); tap(f); tap(f, 0.1)
    check(#f.sent == 0 and lastToast(f) == "已装备" and #f.sfx == 0, "same equipped seq/slot right and double are no-op, never unequip")
    check(f.equipment.inventory["11"].type == nil and f.equipment.inventory["11"].slot == nil,
        "all preflight uses readonly projection and never hydrates source")
end

local function runContextGuards()
    for _, doubleTap in ipairs({ false, true }) do
        local f = fixture()
        f.api.setEquipmentSlotFilter("offhand", 1)
        f.current.hero, f.list[1].seq = 2, 13 -- 黄桃龙可穿 W31 法杖，避免职业拒绝遮住槽位断言。
        if doubleTap then tap(f); tap(f, 0.1) else f.api.handleRightClick(X, Y) end
        check(#f.sent == 1 and f.sent[1].heroId == 2 and f.sent[1].slot == "weapon",
            "stale filter hero never redirects current hero's right/double to old offhand")
    end

    local f = fixture(); tap(f); f.itemDetState.open = true
    check(not tap(f, 0.1) and not f.api.handleRightClick(X, Y) and #f.sent == 0 and f.opens == 1,
        "item detail modal blocks left/right shortcut without sending or pinning")
    f.itemDetState.open = false; tap(f, 0.1)
    check(#f.sent == 0 and f.opens == 2, "item modal interruption clears double history")

    f = fixture(true); f.current.equipTab = false
    local uiToast = require("core.UiToast")
    local originalShow = uiToast.show
    uiToast.show = function(text) f.toasts[#f.toasts + 1] = text end
    f.api.handleRightClick(X, Y)
    uiToast.show = originalShow
    check(#f.sent == 0 and lastToast(f) == "请先打开角色配装页",
        "default toast directly uses core.UiToast.show")
end

function Start()
    local ok, err = pcall(function()
        runClicks(); runNoRoleAndRefusals(); runAck(); runTimeoutAndResets(); runSlots(); runContextGuards()
    end)
    if not ok then failures = failures + 1; print("[FAIL] exception: " .. tostring(err)) end
    print("[backpack_quick_equip_test] " .. (failures == 0 and "ALL PASS" or "FAILURES=" .. failures)
        .. " (" .. passes .. " assertions)")
    engine:Exit()
end
