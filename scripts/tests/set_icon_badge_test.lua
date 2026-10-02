-- 套装角标绘制回归：真实 helper + 真实模板归属，依赖/nvg 绘制桩隔离 UI 事件。
-- 运行：.cli/UrhoXRuntime tests/set_icon_badge_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
---@diagnostic disable: undefined-global
local failures, passes = {}, 0
local function check(ok, label)
    if ok then passes = passes + 1; print("[PASS] " .. label)
    else failures[#failures + 1] = label; print("[FAIL] " .. label) end
end
local enabled = true
local calls, images = {}, {}
local fontSize, align = 0, 0
local color, path = {}, {}
local function log(kind, data)
    data.kind = kind
    calls[#calls + 1] = data
end
local function noop() end
local originalRequire = require
local mocks = {}
_G["require"] = function(name) return mocks[name] or originalRequire(name) end
local function preload(name, value)
    -- 引擎的资源 require 不读 package.preload，优先用 require 包装器隔离依赖。
    mocks[name] = value
end
local function reset() calls = {} end
local function find(kind, predicate)
    for i, call in ipairs(calls) do
        if call.kind == kind and (not predicate or predicate(call)) then return call, i end
    end
    return nil, 0
end
local function count(kind)
    local n = 0
    for _, call in ipairs(calls) do if call.kind == kind then n = n + 1 end end
    return n
end
local vg = {}
local realRGBA = nvgRGBA
_G["nvgRGBA"] = function(r, g, b, a)
    color = { r = r, g = g, b = b, a = a }
    return realRGBA(r, g, b, a)
end
for _, name in ipairs({ "nvgSave", "nvgRestore", "nvgScissor", "nvgIntersectScissor",
    "nvgResetScissor", "nvgTranslate", "nvgScale", "nvgGlobalAlpha", "nvgFontFace",
    "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgFillPaint" }) do
    _G[name] = noop
end
_G["nvgBeginPath"] = function() path = {} end
_G["nvgRect"] = function(_, x, y, w, h) path = { x = x, y = y, w = w, h = h } end
_G["nvgRoundedRect"] = _G["nvgRect"]
_G["nvgFillColor"] = noop
_G["nvgFill"] = function()
    log("fill", { x = path.x, y = path.y, w = path.w, h = path.h,
        r = color.r, g = color.g, b = color.b, a = color.a })
end
_G["nvgFontSize"] = function(_, size) fontSize = size end
_G["nvgTextAlign"] = function(_, value) align = value end
_G["nvgText"] = function(_, x, y, text)
    log("text", { x = x, y = y, text = text, fontSize = fontSize, align = align,
        r = color.r, g = color.g, b = color.b, a = color.a })
end
_G["nvgTextBounds"] = function(_, _, _, text) return #text * fontSize * 0.5 end
_G["nvgCreateImage"] = function(_, imagePath)
    local id = #images + 1
    images[id] = imagePath
    return id
end
local DrawUtil = {
    drawImageCentered = function(_, image, cx, cy, w, h)
        local imagePath = images[image] or ""
        local kind = imagePath:find("/SET_", 1, true) and "badge" or "image"
        log(kind, { image = image, cx = cx, cy = cy, w = w, h = h })
    end,
    drawTextStroke = function(_, x, y, text, size, textAlign)
        log("text", { x = x, y = y, text = text, fontSize = size, align = textAlign })
    end,
    drawNineSlice = noop, drawBackChevron = noop, drawImageCover = noop,
    drawShardIcon = noop, hitTest = function() return false end,
    seamSlideX = function() return 0 end,
}
preload("core.DrawUtil", DrawUtil)
preload("core.DarkIcon", { drawQualityBg = function(_, _, cx, cy, w, h)
    log("cell", { cx = cx, cy = cy, w = w, h = h })
end, drawIconDark = noop, drawNine = noop })
preload("ui.hud.popup.SettingsPanel", { isSetIconsEnabled = function() return enabled end })
preload("ui.widget.ImageCache", { getEquipIcon = function() return 900 end, init = noop })
preload("ui.widget.HeroFrame", { draw = function(_, opts)
    log("owner", { cx = opts.cx, cy = opts.cy, size = opts.size })
end })
preload("ui.widget.QualityMark", { init = noop, draw = function() return true end, count = function() return 6 end })
preload("systems.TutorialManager", { isActive = function() return false end })
preload("systems.ButtonFeedback", { begin = function() return false end, finish = noop, trigger = noop })
preload("ui.character.panel.CharacterPanel", { getShards = function() return 0 end })
preload("config.AdvancementConfig", { getDualWieldMode = function() return nil end })
preload("ui.character.detail.EquipmentWearability", {
    getFields = function(equip) return "weapon", "sword", "onehand", equip.level end,
    createChecker = function(data) return function(seq)
        return data.inventory[tostring(seq)].canWear ~= false
    end end,
})
local equipData = { inventory = {}, equipped = {} }
preload("core.PlayerStore", { Get = function(key)
    if key == "equipment" then return equipData end
    if key == "heroes" then return { roster = { [1] = { level = 100 } } } end
end })
preload("systems.EquipmentSystem", { MAX_INVENTORY = 5,
    getAscendLevel = function(equip) return equip.enhanceLevel or 0 end })
preload("ui.character.equip.EquipmentDetail", { init = noop, isOpen = function() return false end,
    calcEquipPower = function() return 100 end, readOnlySize = function() return 500, 600 end })
preload("ui.hud.popup.RewardPopup", {})
preload("ui.character.equip.EquipmentBag", { draw = noop, isOpen = function() return false end })
preload("config.HeroAssetUtil", { ensureCard = function() return -1 end })
preload("ui.character.detail.CharacterDetailAttrs", {})
preload("ui.character.detail.CharacterEquipStats", { LEGACY = {}, drawBackground = noop })
preload("ui.character.detail.CharacterAttributeView", {
    STYLE = { boxW = 400, rowH = 60, boxCX = 300, rowStep = 70 },
    ATTRIBUTE_LAYOUT = { firstY = 1300 },
})
preload("ui.character.hero.AwakeningPanel", {})
preload("runtime.ClientDispatcher", {})
preload("systems.ExtraTalentSystem", {})
preload("core.I18n", { lookup = function(text) return text end, t = function(text) return text end })
preload("ui.widget.KeywordText", { new = function() return { drawPopup = noop } end })
preload("ui.church.ChurchPage", {})
preload("systems.GameSFX", { playUIMove = noop })
preload("ui.town.TownPageChrome", { OPEN_DUR = 0.1, CLOSE_DUR = 0.1,
    slideProgress = function() return 1 end, drawNamePlate = noop, drawBack = noop })
preload("ui.widget.SetFilterDialog", { NONE_KEY = "none", close = noop, draw = noop,
    countSelected = function() return 0 end, isOpen = function() return false end })

local EC = require("config.EquipmentConfig")
local SetConfig = require("config.EquipmentSetConfig")
local SetIcon = require("ui.widget.EquipmentSetIcon")
local setId, plainId
for id, template in pairs(EC.ITEMS) do
    if SetConfig.getSetIdForTemplate(template) then setId = setId or id
    else plainId = plainId or id end
end
local setEquip = { templateId = setId, level = 85, quality = 5, enhanceLevel = 7, locked = true, canWear = false }
local plainEquip = { templateId = plainId, level = 85, quality = 5, enhanceLevel = 7 }
local grids = require("ui.backpack.BackpackGrids").bind({
    GRID = { CELL_SIZE = 160, CELL_RADIUS = 16, GAP = 30, COLS = 5,
        FIRST_ROW_TOP = 470, CLIP_BOTTOM = 1980 },
    CELL_COL_CX = { 160, 350, 540, 730, 920 }, DESIGN_W = 1080,
    state = { scrollY = 0, scrollMax = 0 }, ITEM_DEFS = {},
    getItemIcon = function() return -1 end, getImgLock = function() return 900 end,
    getImgCheckmark = function() return -1 end,
    getImgHeroIcons = function() return { [1] = 901 } end,
    calcScrollMax = function() return 0 end, clampScroll = noop,
    getEquipmentSlotFilter = function() return nil, 1 end,
})
local function putInventory(equip, owner)
    equipData = { inventory = equip and { ["1"] = equip } or {},
        equipped = owner and { [1] = { weapon = 1 } } or {} }
end
local function levelText(call) return call.text == "Lv.85" and call.r ~= 0 end
local function gray(call) return call.r == 38 and call.g == 38 and call.a == 175 end

local function testHelper()
    check(setId ~= nil and plainId ~= nil, "真实模板含有套装/无套装样本")
    enabled = true
    check(SetIcon.hasBadge(setEquip), "默认开启时有效套装有角标")
    check(not SetIcon.hasBadge(plainEquip) and not SetIcon.hasBadge(nil), "无套装与空装备无角标")
    local layout = SetIcon.badgeLayout(160, 550, 160)
    check(layout.size == 44 and layout.x == 192 and layout.y == 582, "160格右下角标44px")
    local level = SetIcon.levelLayout(setEquip, 160, 550, 160)
    check(level.x == 88 and level.y == 624 and level.fontSize == 32
        and level.align == NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM, "套装等级左下32号")
    enabled = false
    check(not SetIcon.hasBadge(setEquip), "关闭开关后套装无角标")
    level = SetIcon.levelLayout(setEquip, 160, 550, 160)
    check(level.x == 232 and level.fontSize == 40
        and level.align == NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM, "关闭后等级恢复右下40号")
    reset()
    check(not SetIcon.drawBadge(vg, setEquip, 160, 550, 160) and count("badge") == 0,
        "关闭后drawBadge不绘制")
    check(SetIcon.draw(vg, SetIcon.setId(setEquip), 100, 100, 44), "套装列表draw不受开关影响")
end

local function testBackpack()
    enabled = true
    putInventory(setEquip, true)
    reset(); grids.drawEquipGrid(vg)
    local level, levelIndex = find("text", levelText)
    local badge, badgeIndex = find("badge")
    local enhancement, enhancementIndex = find("text", function(call)
        return call.text == "+7" and call.g == 255 and call.b == 96
    end)
    local mask, maskIndex = find("fill", gray)
    local lock = find("image", function(call) return call.image == 900 end)
    check(count("badge") == 1, "仓库仅非空有效套装绘制一个角标")
    check(level and level.x == 88 and level.fontSize == 32, "仓库套装等级左下")
    check(enhancement and enhancement.x == 232 and enhancement.y == 478, "仓库升阶仍在右上")
    check(badge and badgeIndex > levelIndex and badgeIndex > enhancementIndex,
        "仓库角标在全部数值后")
    check(mask and maskIndex > badgeIndex, "不可穿戴灰罩最后覆盖套装角标")
    check(lock and lock.cy == 560 and lock.w == 32, "归属装备锁缩至32px避开左下等级")
    local owner = find("owner")
    check(lock and owner and lock.cy - lock.h * 0.5 > owner.cy + owner.size * 0.5,
        "仓库锁与左上归属头像不重叠")
    check(lock and level and lock.cy + lock.h * 0.5 < level.y - level.fontSize,
        "仓库锁与左下等级不重叠")
    setEquip.level = 9999
    reset(); grids.drawEquipGrid(vg)
    local longLevel = find("text", function(call) return call.text == "Lv.9999" and call.r ~= 0 end)
    local badgeLayout = SetIcon.badgeLayout(160, 550, 160)
    check(longLevel and longLevel.fontSize < 32
        and longLevel.x + #longLevel.text * longLevel.fontSize * 0.5 <= badgeLayout.x - 4,
        "长等级缩字号后不碰右下套装角标")
    setEquip.level = 85
    enabled = false
    reset(); grids.drawEquipGrid(vg)
    level = find("text", levelText)
    lock = find("image", function(call) return call.image == 900 end)
    check(count("badge") == 0 and level and level.x == 232 and level.fontSize == 40,
        "仓库关闭角标后恢复等级原位")
    check(lock and lock.cy == 598, "仓库关闭角标后锁恢复原位")
    enabled = true
    putInventory(plainEquip, false)
    reset(); grids.drawEquipGrid(vg)
    check(count("badge") == 0, "仓库无套装不画角标")
    putInventory(nil, false)
    reset(); grids.drawEquipGrid(vg)
    check(count("badge") == 0, "仓库空格不画角标")
end

local function testSixSlots()
    enabled = true
    local Draw = require("ui.character.detail.CharacterDetailDraw")
    putInventory(setEquip, true)
    setEquip.grip = "twohand"
    Draw.setContext({ detailState = { open = true, heroId = 1, tab = "equip", openTime = 0,
        attrScrollVel = 0, attrScrollY = 0, tabSwitchTime = 0, tabFrom = "equip" },
        getOwnedData = function() return { level = 100, exp = 0, maxExp = 5 } end,
        CharacterDetail = { _getEquipIcon = function() return 900 end, _imgIconUp = -1,
            _hasUpgradeForSlot = function() return false end }, clampAttrScroll = noop,
    })
    reset(); Draw.draw(vg)
    local badge, badgeIndex = find("badge", function(call) return call.cx > 700 end)
    local mask, maskIndex = find("fill", function(call)
        return call.x == 675 and call.y == 498 and call.w == 160 and call.a == 128
    end)
    check(count("badge") == 2, "角色主手和双手占用副手都有角标，四空槽无角标")
    check(badge and mask and maskIndex > badgeIndex, "角色双手占位灰罩在角标后")
    local level = find("text", function(call) return levelText(call) and call.x == 683 end)
    check(level and level.fontSize == 32 and level.align == NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM,
        "角色sixslot等级左下32号")
    enabled = false
    reset(); Draw.draw(vg)
    check(count("badge") == 0, "角色关闭开关不画角标")
    setEquip.grip = nil
    enabled = true
    equipData.equipped[1] = { weapon = 1, offhand = 1, armor = 1, helmet = 1, shoes = 1, accessory = 1 }
    reset(); Draw.draw(vg)
    check(count("badge") == 6, "角色六个非空套装槽全部绘制角标")
    equipData.inventory["1"] = plainEquip
    reset(); Draw.draw(vg)
    check(count("badge") == 0, "角色六个无套装槽均不画角标")
end

local function testDecompose()
    local Decompose = require("ui.blacksmith.BlacksmithDecompose")
    Decompose.setContext({ getEquipIconCached = function() return 900 end })
    Decompose.applyProfile("warehouse")
    putInventory(setEquip, false)
    Decompose.onOpen()
    enabled = true
    reset(); Decompose.drawPanel(vg)
    local level, levelIndex = find("text", levelText)
    local badge, badgeIndex = find("badge")
    check(count("badge") == 1 and badge and badge.w == 44, "分解160格角标44，空格无角标")
    check(level and level.fontSize == 32 and level.x == 88 and badgeIndex > levelIndex,
        "分解等级左下并先于角标")
    enabled = false
    reset(); Decompose.drawPanel(vg)
    level = find("text", levelText)
    check(count("badge") == 0 and level and level.fontSize == 40 and level.x == 232,
        "分解关闭后恢复等级右下")
end

local function testLootBox()
    local Loot = require("ui.loot.LootBoxPage")
    enabled = true
    Loot.open({ { equip = setEquip }, { equip = plainEquip }, { count = 1 } })
    reset(); Loot.draw(vg)
    local level = find("text", function(call) return call.text == "Lv.85" and call.fontSize == 28 end)
    check(count("badge") == 1, "遗匣仅套装条目有角标，无套装/待整理无角标")
    check(level and level.x < 181 and level.align == NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM,
        "遗匣174框等级左下28号，不挤正文")
    enabled = false
    reset(); Loot.draw(vg)
    level = find("text", function(call) return call.text == "Lv.85" and call.fontSize == 32 end)
    check(count("badge") == 0 and level and level.x == 181,
        "遗匣关闭角标后保持原底部居中等级")
end

local function testWorkbench()
    local selectedState = {}
    local child = { init = noop, onOpen = noop, updateEnhanceData = noop, updateRefineData = noop,
        setContext = function(ctx) selectedState = ctx.state end }
    preload("ui.blacksmith.BlacksmithEnhance", child)
    preload("ui.blacksmith.BlacksmithRefine", child)
    preload("ui.blacksmith.BlacksmithEnhanceCache", {})
    preload("ui.fx.SpineResultEffect", {})
    preload("core.PlayerStore", { Get = function(key) return key == "equipment" and equipData or nil end,
        Subscribe = noop })
    preload("runtime.ClientDispatcher", { get = function() return nil end })
    preload("config.HeroAssetUtil", { preloadIcons = function(_, icons) icons[1] = 901 end })
    preload("ui.blacksmith.BlacksmithDraw", { bind = function(deps)
        return { drawPageImpl = function(ctx) deps.drawWorkbenchSlot(ctx) end }
    end })
    local Page = require("ui.blacksmith.BlacksmithPage")
    Page.init(vg)
    setEquip.seq = 1
    putInventory(setEquip, true)
    selectedState.selectedEquip = setEquip
    enabled = true
    reset(); Page.draw(vg)
    local owner = find("owner")
    local level = find("text", levelText)
    check(count("badge") == 1 and owner and owner.cx == 486 and owner.cy == 403,
        "工作台套装角标开启时归属头像移至左上")
    check(level and level.x == 463 and level.align == NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM,
        "工作台等级移至左下")
    enabled = false
    reset(); Page.draw(vg)
    owner = find("owner")
    check(count("badge") == 0 and owner and owner.cy == 555,
        "工作台关闭角标后归属头像恢复左下")
    setEquip.seq = nil
end

function Start()
    print("[set_icon_badge_test] start")
    local ok, err = pcall(function()
        testHelper(); testBackpack(); testSixSlots(); testDecompose(); testLootBox(); testWorkbench()
    end)
    if not ok then check(false, "exception: " .. tostring(err)) end
    print("[set_icon_badge_test] " .. (#failures == 0 and "ALL PASS" or "FAILURES=" .. #failures)
        .. " (" .. passes .. " assertions)")
    engine:Exit()
end
