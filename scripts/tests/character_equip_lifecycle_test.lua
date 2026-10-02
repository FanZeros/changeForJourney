-- 配装入口联动回归：生命周期、取消部位、浮选与右栏属性滚动不互相抢事件。
function Start()
    local originalRequire = require
    local originalTime = time
    local calls = { acquire = 0, release = 0, slot = 0, move = 0, finish = 0, wheel = 0, reset = 0 }
    local slot, linkedHero = nil, nil
    local equipDetailOpen = false
    local owned = { [1] = true, [2] = true }
    local function noop() end
    local function module(fields)
        return setmetatable(fields or {}, { __index = function() return noop end })
    end
    local keyword = { clear = noop, isOpen = function() return false end }
    local draw = module({
        talentKwText = keyword,
        DT_SLOT_SIZE = 160,
        DT_SLOTS = { { slot = "helmet", cx = 540, cy = 185 }, { slot = "weapon", cx = 325, cy = 578 } },
        BTN_TAB_SLIDER_W = 180, BTN_TAB_SLIDER_H = 140,
        BTN_TAB_ATTR_CX = 255, BTN_TAB_ATTR_CY = 2308,
        BTN_TAB_EQUIP_CX = 445, BTN_TAB_EQUIP_CY = 2308,
        BTN_TAB_CLASS_CX = 635, BTN_TAB_CLASS_CY = 2308,
        BTN_TAB_AWAKEN_CX = 825, BTN_TAB_AWAKEN_CY = 2308,
        BTN_BACK_CX = 122, BTN_BACK_CY = 1150, BTN_BACK_W = 184, BTN_BACK_H = 143,
        BTN_UNEQUIP_CX = 211, BTN_UNEQUIP_CY = 105,
        BTN_EQUIP_CX = 869, BTN_EQUIP_CY = 105, BTN_BATCH_W = 304, BTN_BATCH_H = 100,
        SIDE_CARD_W = 180, SIDE_CARD_H = 300, ARROW_CY = 500,
        ARROW_BG_LEFT_CX = 300, ARROW_BG_RIGHT_CX = 780,
        ATTR_BOX_W = 440, ATTR_BOX_H = 60, ATTR_ROW_GAP = 9,
        ATTR_CLIP_TOP = 1264, ATTR_CLIP_HEIGHT = 552,
    })
    local panel = module({
        reset = function() calls.reset = calls.reset + 1 end,
        handleDragBegin = function(x, y) return x > 40 and y > 1050 and y < 2200 end,
        handleDragMove = function() calls.move = calls.move + 1; return true end,
        handleDragEnd = function() calls.finish = calls.finish + 1; return true end,
        handleSideScroll = function(_, x, y)
            if x > 40 and y > 1050 and y < 2200 then calls.wheel = calls.wheel + 1; return true end
            return false
        end,
        handleInput = function() return true end,
    })
    local warehouse = module({
        acquireForEquipment = function(heroId, s) calls.acquire = calls.acquire + 1; linkedHero, slot = heroId, s end,
        releaseForEquipment = function() calls.release = calls.release + 1; linkedHero, slot = nil, nil end,
        setEquipmentSlotFilter = function(s, heroId) calls.slot = calls.slot + 1; slot, linkedHero = s, heroId end,
    })
    local mods = {
        ["config.GameConfig"] = { Design = { WIDTH = 1080, HEIGHT = 2400 } },
        ["config.HeroConfig"] = { get = function(id) return { name = tostring(id) } end },
        ["ui.character.detail.CharacterDetailDraw"] = draw,
        ["ui.character.detail.CharacterDetailAttrs"] = module({ STAT_LAYOUT = {} }),
        ["ui.character.detail.CharacterDetailEquip"] = panel,
        ["ui.character.equip.EquipmentDetail"] = module({
            isOpen = function() return equipDetailOpen end,
            isCompactCorner = function() return true end,
            containsPoint = function() return false end,
            handleInput = function() error("浮选详情不应抢右栏页签") end,
            handleDragBegin = function() error("浮选详情不应抢右栏拖拽") end,
            handleDragMove = function() error("浮选详情不应抢属性移动") end,
            handleDragEnd = function() error("浮选详情不应抢属性释放") end,
            handleScroll = function() error("浮选详情不应抢右栏滚轮") end,
        }),
        ["ui.character.equip.EquipmentBag"] = module({ isOpen = function() return false end }),
        ["ui.character.hero.AwakeningPanel"] = module({ kwText = keyword }),
        ["ui.character.hero.HeroScenario"] = module(),
        ["ui.backpack.BackpackPanel"] = warehouse,
        ["ui.character.panel.CharacterPanel"] = { getOwnedHero = function(id) return owned[id] end },
    }
    require = function(name)
        if not mods[name] then mods[name] = module() end
        return mods[name]
    end
    time = { elapsedTime = 100 }
    local detail = originalRequire("ui.character.detail.CharacterDetail")
    local ok, err = pcall(function()
        detail.setContext({ getHeroRoster = function()
            return { { heroId = 1, owned = true }, { heroId = 2, owned = true }, { heroId = 3, owned = false } }
        end })
        detail.open(1, "attr")
        assert(calls.acquire == 0 and not detail.isEquipTab(), "属性入口不得自动开仓")
        detail.handleInput(445, 2308)
        assert(calls.acquire == 1 and linkedHero == 1 and slot == nil, "切配装即申请全部装备仓库")
        detail.handleInput(445, 2308)
        assert(calls.acquire == 1, "重复点配装不能重开仓库")
        detail.handleEquipmentSlotTap(540, 185)
        assert(slot == "helmet", "头盔槽同步部位")
        detail.handleEquipmentSlotTap(70, 1200)
        assert(slot == nil, "非槽点击取消部位")
        detail.handleEquipmentSlotTap(325, 578)
        assert(slot == "weapon", "主手槽同步部位")
        detail.clearEquipmentSlot()
        assert(slot == nil, "仓库取消按钮统一清部位")
        equipDetailOpen = true
        detail.handleDragBegin(80, 1300)
        detail.handleDragMove(80, 1200)
        detail.handleDragEnd(80, 1200)
        detail.handleScroll(-1, 80, 1400)
        assert(calls.move == 1 and calls.finish == 1 and calls.wheel == 1, "浮选打开时属性/套装仍能拖拽滚动")
        detail.handleInput(255, 2308)
        assert(calls.release == 1 and not detail.isEquipTab(), "离开配装立即释放仓库，不被浮选阻挡")
        equipDetailOpen = false
        detail.open(1, "equip")
        assert(calls.acquire == 2 and linkedHero == 1, "直接打开配装申请仓库")
        detail._switchHero(1)
        assert(linkedHero == 2 and calls.acquire == 2, "配装切换角色只更新上下文，不重新开仓")
        detail._switchHero(1)
        assert(calls.release == 2 and not detail.isEquipTab(), "未获得角色退属性并释放仓库")
        detail.open(1, "equip")
        detail.close()
        assert(calls.release == 3 and not detail.isEquipTab(), "关闭动画起始即释放仓库")
        detail.forceClose()
        assert(calls.release == 3, "关闭后 forceClose 不重复释放")
        detail.open(1, "equip")
        detail.forceClose()
        assert(calls.release == 4 and detail.getHeroId() == nil, "跨页强制关闭释放自动仓库")
    end)
    require, time = originalRequire, originalTime
    if ok then print("[character_equip_lifecycle_test] ALL PASS")
    else print("[character_equip_lifecycle_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
