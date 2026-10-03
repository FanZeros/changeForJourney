-- 套装角标绘制回归：V3 左下徽记，等级保持右下；真实 helper/模板，nvg 桩隔离 UI。
-- 运行：timeout 60 .cli/UrhoXRuntime tests/set_icon_badge_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
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
_G["nvgTextBox"] = noop
_G["nvgImagePattern"] = function(_, x, y, w, h, _, image)
    log("image", { image = image, cx = x + w * 0.5, cy = y + h * 0.5, w = w, h = h })
    return nil
end
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
preload("core.DarkIcon", { QUALITY_TRIM = { { 255, 255, 255 } },
    drawQualityBg = function(_, _, cx, cy, w, h)
    log("cell", { cx = cx, cy = cy, w = w, h = h })
end, drawIconDark = function(_, image, cx, cy, w, h)
    log("equipIcon", { image = image, cx = cx, cy = cy, w = w, h = h })
end, drawNine = noop })
preload("ui.hud.popup.SettingsPanel", { isSetIconsEnabled = function() return enabled end })
preload("ui.widget.ImageCache", { getEquipIcon = function() return 900 end, init = noop })
preload("ui.widget.HeroFrame", { draw = function(_, opts)
    log("owner", { cx = opts.cx, cy = opts.cy, size = opts.size })
end })
preload("ui.widget.QualityMark", { init = noop, draw = function() return true end, count = function() return 6 end })
preload("systems.TutorialManager", { isActive = function() return false end,
    isBuildingUnlocked = function() return false end })
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
    getAscendLevel = function(equip) return equip.enhanceLevel or 0 end,
    getAscendBoost = function() return 0 end,
    getHeroSlots = function(data, heroId) return data.equipped[heroId] or {} end,
    getFromInventory = function(data, seq) return data.inventory[tostring(seq)] end,
})
preload("systems.EquipmentSetSystem", {
    countSets = function() return {} end, summarize = function() return {} end,
})
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
preload("ui.widget.KeywordText", { new = function()
    return { drawPopup = noop, clear = noop, draw = noop }
end })
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
local function near(a, b) return math.abs(a - b) < 0.001 end
local function sameLevel(a, b)
    return a and b and near(a.x, b.x) and near(a.y, b.y)
        and near(a.fontSize, b.fontSize) and a.align == b.align
end
local function badgeAt(badge, cx, cy, size)
    local layout = SetIcon.badgeLayout(cx, cy, size)
    return badge and near(badge.cx, layout.cx) and near(badge.cy, layout.cy)
        and near(badge.w, layout.size) and badge.cx < cx and badge.cy > cy
end
local function fitsRight(level, cx, cy, size)
    local badge = SetIcon.badgeLayout(cx, cy, size)
    return level and level.fontSize > 0 and level.fontSize <= 40
        and level.align == NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM
        and level.x - #level.text * level.fontSize * 0.5 >= badge.x + badge.size + 8 - 0.001
end
local function separate(a, b)
    return a and b and (a.x + a.w <= b.x or b.x + b.w <= a.x
        or a.y + a.h <= b.y or b.y + b.h <= a.y)
end
local function imageRect(image)
    return image and { x = image.cx - image.w * 0.5, y = image.cy - image.h * 0.5,
        w = image.w, h = image.h }
end
local function ownerRect(owner)
    return owner and { x = owner.cx - owner.size * 0.5, y = owner.cy - owner.size * 0.5,
        w = owner.size, h = owner.size }
end
local function textRect(level)
    local w = level and #level.text * level.fontSize * 0.5 or 0
    return level and { x = level.x - w, y = level.y - level.fontSize, w = w, h = level.fontSize }
end

local function testHelper()
    check(setId ~= nil and plainId ~= nil, "真实模板含有套装/无套装样本")
    enabled = true
    check(SetIcon.hasBadge(setEquip), "默认开启时有效套装有角标")
    check(not SetIcon.hasBadge(plainEquip) and not SetIcon.hasBadge(nil), "无套装与空装备无角标")
    local layout = SetIcon.badgeLayout(160, 550, 160)
    check(layout.size == 44 and layout.x == 84 and layout.y == 582, "160格左下角标44px")
    local level = SetIcon.levelLayout(setEquip, 160, 550, 160)
    check(level.x == 232 and level.y == 624 and level.fontSize == 40
        and level.align == NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM, "套装等级保持右下基础40号")
    local enabledLevel = level
    enabled = false
    check(not SetIcon.hasBadge(setEquip), "关闭开关后套装无角标")
    level = SetIcon.levelLayout(setEquip, 160, 550, 160)
    check(sameLevel(level, enabledLevel), "关闭后等级坐标字号对齐完全不变")
    check(sameLevel(level, SetIcon.levelLayout(plainEquip, 160, 550, 160))
        and sameLevel(level, SetIcon.levelLayout(nil, 160, 550, 160)),
        "无套装/空装备不影响等级布局")
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
    check(level and level.x == 232 and level.y == 624 and fitsRight(level, 160, 550, 160),
        "仓库套装等级右下，按固定右侧宽度缩字")
    local enabledLevel = level
    check(badgeAt(badge, 160, 550, 160), "仓库套装角标位于左下")
    check(enhancement and enhancement.x == 232 and enhancement.y == 478, "仓库升阶仍在右上")
    check(badge and badgeIndex > levelIndex and badgeIndex > enhancementIndex,
        "仓库角标在全部数值后")
    check(mask and maskIndex > badgeIndex, "不可穿戴灰罩最后覆盖套装角标")
    check(lock and lock.cy == 560 and lock.w == 32, "归属装备锁缩至32px避开左下角标")
    local owner = find("owner")
    check(lock and owner and lock.cy - lock.h * 0.5 > owner.cy + owner.size * 0.5,
        "仓库锁与左上归属头像不重叠")
    check(separate(imageRect(lock), textRect(level)), "仓库锁与右下等级不重叠")
    check(separate(imageRect(lock), imageRect(badge))
        and separate(ownerRect(owner), imageRect(badge)), "仓库左下徽记与锁/归属均不重叠")
    setEquip.level = 9999
    reset(); grids.drawEquipGrid(vg)
    local longLevel = find("text", function(call) return call.text == "Lv.9999" and call.r ~= 0 end)
    check(longLevel and longLevel.fontSize < 40 and fitsRight(longLevel, 160, 550, 160),
        "长Lv.9999缩字号后不碰左下套装角标")
    local longMask, longMaskIndex = find("fill", gray)
    local _, longBadgeIndex = find("badge")
    check(longMask and longMaskIndex > longBadgeIndex, "长等级仍由灰罩最后覆盖徽记")
    enabled = false
    reset(); grids.drawEquipGrid(vg)
    local longOff = find("text", function(call) return call.text == "Lv.9999" and call.r ~= 0 end)
    check(sameLevel(longLevel, longOff), "仓库长等级开关前后位置/字号/对齐不变")
    setEquip.level = 85
    reset(); grids.drawEquipGrid(vg)
    level = find("text", levelText)
    lock = find("image", function(call) return call.image == 900 end)
    check(count("badge") == 0 and sameLevel(level, enabledLevel),
        "仓库关闭角标后等级位置/字号/对齐不变")
    check(lock and lock.cy == 598, "仓库关闭角标后锁恢复原位")
    enabled = true
    putInventory(plainEquip, false)
    reset(); grids.drawEquipGrid(vg)
    check(count("badge") == 0, "仓库无套装不画角标")
    check(sameLevel(find("text", levelText), enabledLevel), "仓库同等级无套装布局也不变")
    putInventory(nil, false)
    reset(); grids.drawEquipGrid(vg)
    check(count("badge") == 0, "仓库空格不画角标")
end

local function testSixSlots()
    enabled = true
    local Draw = require("ui.character.detail.CharacterDetailDraw")
    local slots = {}
    for _, slot in ipairs(Draw.DT_SLOTS) do slots[slot.slot] = slot end
    local offhand, slotSize = slots.offhand, Draw.DT_SLOT_SIZE
    local offLayout = SetIcon.levelLayout(setEquip, offhand.cx, offhand.cy, slotSize)
    local expected = {
        helmet = { cx = 540, cy = 165 }, shoes = { cx = 540, cy = 790 },
        armor = { cx = 325, cy = 336 }, accessory = { cx = 755, cy = 336 },
        weapon = { cx = 325, cy = 598 }, offhand = { cx = 755, cy = 598 },
    }
    check(#Draw.DT_SLOTS == 6 and slotSize == 160, "真实六槽表保留六项与160格尺寸")
    for key, center in pairs(expected) do
        local actual = slots[key]
        check(actual and actual.cx == center.cx and actual.cy == center.cy,
            "真实六槽精确中心及不变x: " .. key)
    end
    check(slots.armor.cx + slots.accessory.cx == 2 * slots.helmet.cx
        and slots.weapon.cx + offhand.cx == 2 * slots.shoes.cx
        and slots.armor.cy == slots.accessory.cy and slots.weapon.cy == offhand.cy
        and slots.helmet.cx == slots.shoes.cx, "真实六槽两侧同排围绕x540镜像，上下槽居中")
    putInventory(setEquip, true)
    setEquip.grip = "twohand"
    Draw.setContext({ detailState = { open = true, heroId = 1, tab = "equip", openTime = 0,
        attrScrollVel = 0, attrScrollY = 0, tabSwitchTime = 0, tabFrom = "equip" },
        getOwnedData = function() return { level = 100, exp = 0, maxExp = 5 } end,
        CharacterDetail = { _getEquipIcon = function() return 900 end, _imgIconUp = -1,
            _hasUpgradeForSlot = function() return false end }, clampAttrScroll = noop,
    })
    reset(); Draw.draw(vg)
    local badge, badgeIndex = find("badge", function(call) return badgeAt(call, offhand.cx, offhand.cy, slotSize) end)
    local mask, maskIndex = find("fill", function(call)
        return call.x == offhand.cx - slotSize * 0.5 and call.y == offhand.cy - slotSize * 0.5
            and call.w == slotSize and call.h == slotSize and call.a == 128
    end)
    check(count("badge") == 2, "角色主手和双手占用副手都有角标，四空槽无角标")
    check(badge and mask and maskIndex > badgeIndex, "角色双手占位灰罩在角标后")
    local level = find("text", function(call) return levelText(call) and call.x == offLayout.x end)
    check(level and level.y == offLayout.y and fitsRight(level, offhand.cx, offhand.cy, slotSize),
        "角色sixslot等级右下基础40号，长字按右侧区缩")
    check(badgeAt(badge, offhand.cx, offhand.cy, slotSize), "角色双手占位角标也在左下")
    enabled = false
    reset(); Draw.draw(vg)
    check(count("badge") == 0, "角色关闭开关不画角标")
    local offLevel = find("text", function(call) return levelText(call) and call.x == offLayout.x end)
    check(sameLevel(level, offLevel), "角色同装备开关前后等级位置/字号/对齐不变")
    enabled = true
    setEquip.level = 9999
    reset(); Draw.draw(vg)
    local longLevel = find("text", function(call) return call.text == "Lv.9999" and call.x == offLayout.x and call.r ~= 0 end)
    check(longLevel and longLevel.fontSize < 40 and fitsRight(longLevel, offhand.cx, offhand.cy, slotSize),
        "角色长Lv.9999不撞左下角标")
    setEquip.level = 85
    setEquip.grip = nil
    equipData.equipped[1] = { weapon = 1, offhand = 1, armor = 1, helmet = 1, shoes = 1, accessory = 1 }
    reset(); Draw.draw(vg)
    check(count("badge") == 6, "角色六个非空套装槽全部绘制角标")
    local allLeft, allCenters = true, true
    for _, slot in ipairs(Draw.DT_SLOTS) do
        local expected = SetIcon.badgeLayout(slot.cx, slot.cy, slotSize)
        local cellBadge = find("badge", function(call) return near(call.cx, expected.cx) and near(call.cy, expected.cy) end)
        allLeft = allLeft and badgeAt(cellBadge, slot.cx, slot.cy, slotSize)
        local cell = find("cell", function(call)
            return call.cx == slot.cx and call.cy == slot.cy and call.w == slotSize and call.h == slotSize
        end)
        local icon = find("equipIcon", function(call) return call.cx == slot.cx and call.cy == slot.cy end)
        allCenters = allCenters and cell ~= nil and icon ~= nil
    end
    check(allLeft, "角色六槽全部左下角标")
    check(allCenters and count("cell") == 6, "真实六槽绘制底框与装备图标均落在新槽表中心")
    equipData.inventory["1"] = plainEquip
    reset(); Draw.draw(vg)
    check(count("badge") == 0, "角色六个无套装槽均不画角标")
    check(sameLevel(level, find("text", function(call)
        return levelText(call) and call.x == offLayout.x and call.y == offLayout.y
    end)), "角色同等级无套装不改变等级布局")
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
    check(level and fitsRight(level, 160, 550, 160) and level.x == 232 and badgeIndex > levelIndex,
        "分解等级右下并先于角标")
    check(badgeAt(badge, 160, 550, 160), "分解角标左下")
    enabled = false
    reset(); Decompose.drawPanel(vg)
    local offLevel = find("text", levelText)
    check(count("badge") == 0 and sameLevel(level, offLevel),
        "分解关闭后等级坐标/字号/对齐不变")
    enabled = true
    setEquip.level = 9999
    Decompose.onOpen()
    reset(); Decompose.drawPanel(vg)
    local longLevel = find("text", function(call) return call.text == "Lv.9999" and call.r ~= 0 end)
    check(longLevel and longLevel.fontSize < 40 and fitsRight(longLevel, 160, 550, 160),
        "分解长Lv.9999不碰左下角标")
    setEquip.level = 85
    putInventory(plainEquip, false)
    Decompose.onOpen()
    reset(); Decompose.drawPanel(vg)
    check(count("badge") == 0 and sameLevel(level, find("text", levelText)),
        "分解无套装不画角标且等级布局不变")
end

local function testLootBox()
    local Loot = require("ui.loot.LootBoxPage")
    enabled = true
    Loot.open({ { equip = setEquip }, { equip = plainEquip }, { count = 1 } })
    reset(); Loot.draw(vg)
    local level = find("text", function(call) return call.text == "Lv.85" and call.fontSize == 32 end)
    local badge = find("badge")
    local cell = find("cell")
    check(count("badge") == 1, "遗匣仅套装条目有角标，无套装/待整理无角标")
    check(level and near(level.x, 181 + 174 * 0.45)
        and level.align == NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE,
        "遗匣174框等级固定右下32号，不挤正文")
    check(cell and badgeAt(badge, cell.cx, cell.cy, 174), "遗匣徽记位于左下")
    enabled = false
    reset(); Loot.draw(vg)
    local offLevel = find("text", function(call) return call.text == "Lv.85" and call.fontSize == 32 end)
    check(count("badge") == 0 and sameLevel(level, offLevel),
        "遗匣关闭角标后等级位置/字号/对齐不变")
    enabled = true
    setEquip.level = 9999
    Loot.open({ { equip = setEquip } })
    reset(); Loot.draw(vg)
    local longLevel = find("text", function(call) return call.text == "Lv.9999" end)
    badge = find("badge")
    check(longLevel and badge and longLevel.fontSize < 32
        and longLevel.x - #longLevel.text * longLevel.fontSize * 0.5 >= badge.cx + badge.w * 0.5 + 8 - 0.001,
        "遗匣长Lv.9999不碰左下角标")
    enabled = false
    reset(); Loot.draw(vg)
    check(sameLevel(longLevel, find("text", function(call) return call.text == "Lv.9999" end)),
        "遗匣长等级关闭后也不改变布局")
    setEquip.level = 85
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
    check(level and level.x == 661 and near(level.y, 580.75) and level.fontSize == 40
        and level.align == NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM,
        "工作台等级保持原右下40号")
    local badge = find("badge")
    check(badgeAt(badge, 562, 479, 220), "工作台徽记左下")
    check(separate(ownerRect(owner), imageRect(badge))
        and separate(textRect(level), imageRect(badge)), "工作台归属/等级均不撞徽记")
    enabled = false
    reset(); Page.draw(vg)
    owner = find("owner")
    check(count("badge") == 0 and owner and owner.cy == 555,
        "工作台关闭角标后归属头像恢复左下")
    check(sameLevel(level, find("text", levelText)), "工作台开关不改变等级位置/字号/对齐")
    enabled = true
    setEquip.level = 9999
    reset(); Page.draw(vg)
    local longLevel = find("text", function(call) return call.text == "Lv.9999" and call.r ~= 0 end)
    check(longLevel and longLevel.fontSize < 40 and fitsRight(longLevel, 562, 479, 220),
        "工作台长Lv.9999在右侧区内不撞角标")
    setEquip.level = 85
    setEquip.seq = nil
    putInventory(plainEquip, false)
    selectedState.selectedEquip = plainEquip
    reset(); Page.draw(vg)
    check(count("badge") == 0 and sameLevel(level, find("text", levelText)),
        "工作台无套装等级布局不变")
end

local function testDetailsBadge()
    -- 直接绕过同名详情桩，仅详情自身与 helper 为真实模块。
    local Detail = originalRequire("ui.character.equip.EquipmentDetail")
    Detail.init(vg)
    putInventory(setEquip, true)
    enabled = true
    reset(); Detail.drawReadOnly(vg, setEquip, 0, 0)
    local badge, badgeIndex = find("badge")
    local icon = find("equipIcon")
    local enhancement, enhancementIndex = find("text", function(call) return call.text == "+7" end)
    check(count("badge") == 1 and icon and badgeAt(badge, icon.cx, icon.cy, icon.w),
        "详情compact只读图标徽记左下")
    check(enhancement and badgeIndex > enhancementIndex, "详情compact徽记在右上升阶数值之后")
    local compactLevel = find("text", levelText)
    local lock = find("image", function(call)
        return images[call.image] and images[call.image]:find("UI_ICON_SUO", 1, true)
    end)
    check(separate(imageRect(lock), imageRect(badge)), "详情compact锁与左下徽记不重叠")
    enabled = false
    reset(); Detail.drawReadOnly(vg, setEquip, 0, 0)
    check(count("badge") == 0 and sameLevel(compactLevel, find("text", levelText)),
        "详情compact关闭角标不改变等级文本")
    enabled = true
    setEquip.level = 9999
    reset(); Detail.drawReadOnly(vg, setEquip, 0, 0)
    local longLevel = find("text", function(call) return call.text == "Lv.9999" end)
    badge = find("badge")
    check(longLevel and badge and longLevel.x + #longLevel.text * longLevel.fontSize * 0.5
        < badge.cx - badge.w * 0.5, "详情长Lv.9999位于独立正文区不碰徽记")
    setEquip.level = 85
    Detail.open(1, "weapon", 1, false, "bag")
    reset(); Detail.draw(vg)
    badge = find("badge")
    icon = find("equipIcon")
    check(count("badge") == 1 and icon and badgeAt(badge, icon.cx, icon.cy, icon.w),
        "详情普通面板图标徽记左下")
    local regularLevel = find("text", levelText)
    enabled = false
    reset(); Detail.draw(vg)
    check(count("badge") == 0 and sameLevel(regularLevel, find("text", levelText)),
        "详情普通面板开关也不改变等级文本")
end

local function testSetFilterCounts()
    -- 绕过同名 stub；仅补圆圈/命中桩，沿用已有真实模板/helper与nvg记录器。
    local Dialog = originalRequire("ui.widget.SetFilterDialog")
    local oldHitTest, oldCircle = DrawUtil.hitTest, nvgCircle
    DrawUtil.hitTest = function(x, y, cx, cy, w, h)
        return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
    end
    _G["nvgCircle"] = noop
    local ok, err = pcall(function()
        local counts, selected, getterCalls, changes = {}, {}, 0, 0
        local order = SetConfig.orderedSetIds()
        for index, id in ipairs(order) do counts[id] = index * 7 end
        counts[order[1]], counts[order[2]], counts.none = 0, 123456789012, 0
        local function rowCY(index) return 566 + (index - 1) * 88 + 44 end
        local function isCount(call) return call.x == 879 end
        local function countTexts()
            local n = 0
            for _, call in ipairs(calls) do if call.kind == "text" and isCount(call) then n = n + 1 end end
            return n
        end
        Dialog.open(selected, { getCounts = function()
            getterCalls = getterCalls + 1
            return counts
        end, onChange = function() changes = changes + 1 end })
        reset(); Dialog.draw(vg)
        check(getterCalls == 1 and countTexts() == 13, "真实套装弹窗每帧getter恰一次，绘制13个数量文本")
        local everyRow = true
        for index = 1, #order + 1 do
            local key = order[index] or "none"
            local call = find("text", function(item) return isCount(item) and item.y == rowCY(index) end)
            everyRow = everyRow and call ~= nil and call.text == tostring(counts[key])
                and call.align == NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE
        end
        check(everyRow, "13行套装及none数量在x879按真实顺序逐行右对齐，含0")
        local zero = find("text", function(call) return isCount(call) and call.y == rowCY(1) end)
        local none = find("text", function(call) return isCount(call) and call.y == rowCY(13) end)
        check(zero and none and zero.text == "0" and none.text == "0" and zero.fontSize == 34,
            "数量为0与无套装0不省略，普通数量保持34号")
        local long = find("text", function(call) return isCount(call) and call.y == rowCY(2) end)
        check(long and long.fontSize > 0 and long.fontSize < 34
            and #long.text * long.fontSize * 0.5 <= 164 + 0.001,
            "长数量缩字号装入164px数量区，不碰名称/勾选框")
        counts[order[3]] = 0
        reset(); Dialog.draw(vg)
        local refreshed = find("text", function(call) return isCount(call) and call.y == rowCY(3) end)
        check(getterCalls == 2 and countTexts() == 13 and refreshed and refreshed.text == "0",
            "下一帧getter仍恰一次，库存数量变化立即刷新")
        check(Dialog.handleInput(938, rowCY(1)) and selected[order[1]] == true and changes == 1,
            "0数量套装行仍可勾选，不作为禁用条件")
        check(Dialog.handleInput(938, rowCY(13)) and selected.none == true and changes == 2,
            "none为0也可正常选择")
        check(Dialog.handleInput(938, rowCY(1)) and selected[order[1]] == nil and changes == 3,
            "0数量已选行仍可取消")
        -- 不先close而直接重开，也必须覆盖旧getter。
        Dialog.open({}, {})
        reset(); Dialog.draw(vg)
        check(getterCalls == 2 and countTexts() == 0, "重开无getter不残留前次数量或调用")
        Dialog.close()
        Dialog.open({})
        reset(); Dialog.draw(vg)
        check(getterCalls == 2 and countTexts() == 0, "关闭后不传opts重开同样不残留getter")
        Dialog.close()
        reset(); Dialog.draw(vg)
        check(getterCalls == 2 and #calls == 0, "关闭弹窗不绘制也不求数量")
    end)
    Dialog.close()
    DrawUtil.hitTest, _G["nvgCircle"] = oldHitTest, oldCircle
    if not ok then error(err) end
end

local function testLootBoxCounts()
    -- 独立接入回归，不改原testLootBox：只捕获原有同名stub的open参数。
    local Loot = require("ui.loot.LootBoxPage")
    local stub, chrome = mocks["ui.widget.SetFilterDialog"], mocks["ui.town.TownPageChrome"]
    local oldOpen, oldBack, oldHitTest, oldTime = stub.open, chrome.hitBack, DrawUtil.hitTest, time
    local captured = {}
    stub.open = function(sel, opts) captured = { sel = sel, opts = opts } end
    chrome.hitBack = function() return false end
    DrawUtil.hitTest = function(x, y, cx, cy, w, h)
        return math.abs(x - cx) <= w * 0.5 and math.abs(y - cy) <= h * 0.5
    end
    time = { elapsedTime = oldTime.elapsedTime + 10 }
    local ok, err = pcall(function()
        local secondId
        local firstSet = SetIcon.setId(setEquip)
        for id, tpl in pairs(EC.ITEMS) do
            local set = SetConfig.getSetIdForTemplate(tpl)
            if set and set ~= firstSet then secondId = id; break end
        end
        check(secondId ~= nil, "遗匣计数夹具包含不同套装")
        local second = { templateId = secondId, quality = 1, level = 85 }
        Loot.open({ { equip = setEquip }, { equip = setEquip }, { equip = plainEquip },
            { equip = second }, { count = 17 } })
        time.elapsedTime = time.elapsedTime + 1
        check(Loot.handleInput(190, 286) and type(captured.opts.getCounts) == "function",
            "遗匣套装入口传入真实getCounts getter")
        local counts = captured.opts.getCounts()
        local secondSet = SetConfig.getSetIdForTemplate(EC.ITEMS[secondId])
        local total = 0
        for _, value in pairs(counts) do total = total + value end
        check(counts[firstSet] == 2 and counts[secondSet] == 1 and counts.none == 1 and total == 4,
            "遗匣按确定装备实例计数，待整理17件不冒充none")
        captured.sel[firstSet] = true
        captured.opts.onChange()
        counts = captured.opts.getCounts()
        check(counts[firstSet] == 2 and counts[secondSet] == 1 and counts.none == 1,
            "遗匣套装勾选不限制其他行数量")
        Loot.handleInput(565 + 4 * 82, 286) -- 选用品质5，保留两件套装与一件none。
        counts = captured.opts.getCounts()
        check(counts[firstSet] == 2 and counts[secondSet] == 0 and counts.none == 1,
            "遗匣品质筛选限制计数，仍忽略套装勾选")
        Loot.refresh({ { equip = plainEquip }, { count = 9 } })
        counts = captured.opts.getCounts()
        check(counts[firstSet] == 0 and counts.none == 1, "遗匣refresh无需重开即可更新数量")
    end)
    Loot.forceClose()
    stub.open, chrome.hitBack, DrawUtil.hitTest, time = oldOpen, oldBack, oldHitTest, oldTime
    if not ok then error(err) end
end

function Start()
    print("[set_icon_badge_test] start")
    local ok, err = pcall(function()
        testHelper(); testBackpack(); testSixSlots(); testDecompose(); testLootBox(); testWorkbench(); testDetailsBadge()
        testSetFilterCounts(); testLootBoxCounts()
    end)
    if not ok then check(false, "exception: " .. tostring(err)) end
    print("[set_icon_badge_test] " .. (#failures == 0 and "ALL PASS" or "FAILURES=" .. #failures)
        .. " (" .. passes .. " assertions)")
    engine:Exit()
end
