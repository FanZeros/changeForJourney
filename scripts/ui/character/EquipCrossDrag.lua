-- ============================================================================
-- EquipCrossDrag - 左栏装备拖到右栏槽位穿戴
-- 会话用屏幕逻辑坐标，指针离开左栏也不会把拖拽交给别的面板。
-- ============================================================================

local Viewport         = require("core.Viewport")
local EquipmentSystem  = require("systems.EquipmentSystem")
local PlayerStore      = require("core.PlayerStore")
local ImageCache       = require("ui.widget.ImageCache")
local DarkIcon         = require("core.DarkIcon")

local EquipCrossDrag = {}

local DRAG_PX = 14

local session = {
    armed = false,
    dragging = false,
    seq = nil,
    templateId = nil,
    quality = 1,
    slot = nil,
    grip = nil,
    equipType = nil,
    source = nil,
    startSX = 0,
    startSY = 0,
    sx = 0,
    sy = 0,
}

local function clearSession()
    session.armed = false
    session.dragging = false
    session.seq = nil
    session.templateId = nil
    session.slot = nil
    session.grip = nil
    session.equipType = nil
    session.source = nil
end

local function haltSource()
    if session.source == "backpack" then
        local Panel = require("ui.backpack.BackpackPanel")
        if Panel.haltScroll then Panel.haltScroll() end
    elseif session.source == "bag" or session.source == "overlay" then
        local Bag = require("ui.character.equip.EquipmentBag")
        if Bag.haltScroll then Bag.haltScroll() end
    end
end

local function closeDetail()
    local EquipmentDetail = require("ui.character.equip.EquipmentDetail")
    if EquipmentDetail.isOpen and EquipmentDetail.isOpen() then
        if EquipmentDetail.handleDragEnd then EquipmentDetail.handleDragEnd() end
        EquipmentDetail.close()
    end
end

---@param sx number
---@param sy number
---@return number|nil dx
---@return number|nil dy
local function rightDesign(sx, sy)
    local note = Viewport.getNote("right")
    if not note then return nil, nil end
    local panel = Viewport.PANELS.right
    local cs = note.s * Viewport.DS
    if cs == 0 then return nil, nil end
    local dx = (sx - (note.ox + panel.bx * note.s)) / cs
    local dy = (sy - (note.oy + panel.by * note.s)) / cs
    return dx, dy
end

--- [锻炉双页 0929] 中栏设计坐标（锻炉工作台所在面板）
---@param sx number
---@param sy number
---@return number|nil dx
---@return number|nil dy
local function centerDesign(sx, sy)
    local note = Viewport.getNote("center")
    if not note then return nil, nil end
    local panel = Viewport.PANELS.center
    local cs = note.s * Viewport.DS
    if cs == 0 then return nil, nil end
    local dx = (sx - (note.ox + panel.bx * note.s)) / cs
    local dy = (sy - (note.oy + panel.by * note.s)) / cs
    return dx, dy
end

--- [锻炉双页 0929] 拖拽是否落在锻炉工作台槽上（锻炉页打开时）
---@return boolean overWorkbench 指针在锻炉工作台命中区
---@return boolean smithOpen 锻炉页是否打开
local function overBlacksmithWorkbench(sx, sy)
    local ok, BlacksmithPage = pcall(require, "ui.blacksmith.BlacksmithPage")
    if not ok or not BlacksmithPage.isOpen or not BlacksmithPage.isOpen() then
        return false, false
    end
    local wb = BlacksmithPage.WORKBENCH
    if not wb then return false, true end
    local dx, dy = centerDesign(sx, sy)
    if not dx or not dy then return false, true end
    local half = wb.size * 0.5
    local hit = math.abs(dx - wb.cx) <= half and math.abs(dy - wb.cy) <= half
    return hit, true
end

---@param equipSlot string|nil
---@param grip string|nil
---@param target string
---@return boolean
local function slotAccepts(equipSlot, grip, target)
    if not equipSlot or not target then return false end
    if equipSlot == target then return true end
    return target == "offhand" and equipSlot == "weapon" and grip == "onehand"
end

--- 等级穿戴门槛：角色等级低于装备等级不可拖入穿戴
---@param heroId number|string
---@return boolean ok
---@return number|nil requiredLevel
local function checkDropLevelGate(heroId)
    local seq = tonumber(session.seq)
    if not seq then return true, nil end
    local equipData = PlayerStore.Get("equipment")
    local equip = equipData and equipData.inventory
        and (equipData.inventory[tostring(seq)] or equipData.inventory[seq])
    if not equip then return true, nil end
    local heroesData = PlayerStore.Get("heroes")
    local heroLevel = EquipmentSystem.getHeroLevel(heroesData, heroId)
    local ok, requiredLevel = EquipmentSystem.checkLevelGate(heroLevel, equip)
    return ok, requiredLevel
end

---@param heroId number|string
---@param equipType string|nil
---@param equipSlot string|nil
---@param grip string|nil
---@param target string
---@return boolean
local function canDrop(heroId, equipType, equipSlot, grip, target)
    if not slotAccepts(equipSlot, grip, target) then return false end
    if not (checkDropLevelGate(heroId)) then return false end
    if target == "offhand" and equipSlot == "weapon" and grip == "onehand" then
        local heroes = PlayerStore.Get("heroes")
        local roster = heroes and heroes.roster
        local hd = roster and (roster[heroId] or roster[tostring(heroId)])
        local AVC = require("config.AdvancementConfig")
        if not AVC.getDualWieldMode(hd and hd.advBranch) then return false end
        local weaponSet = EquipmentSystem.getWearableTypeSet(heroId, "weapon")
        if weaponSet and equipType and not weaponSet[equipType] then return false end
        return true
    end
    local set = EquipmentSystem.getWearableTypeSet(heroId, target)
    if set and equipType and not set[equipType] then return false end
    return true
end

---@param dx number
---@param dy number
---@return string|nil
local function hitSlot(dx, dy)
    local Draw = require("ui.character.detail.CharacterDetailDraw")
    local size = Draw.DT_SLOT_SIZE
    for _, s in ipairs(Draw.DT_SLOTS) do
        if dx >= s.cx - size * 0.5 and dx <= s.cx + size * 0.5
            and dy >= s.cy - size * 0.5 and dy <= s.cy + size * 0.5 then
            return s.slot
        end
    end
    return nil
end

---@param info table
---@param sx number
---@param sy number
---@param source string
function EquipCrossDrag.arm(info, sx, sy, source)
    if not info or not info.seq then return end
    session.armed = true
    session.dragging = false
    session.seq = info.seq
    session.templateId = info.templateId
    session.quality = info.quality or 1
    session.slot = info.slot
    session.grip = info.grip
    session.equipType = info.equipType
    session.source = source
    session.startSX = sx
    session.startSY = sy
    session.sx = sx
    session.sy = sy
end

---@return boolean
function EquipCrossDrag.isArmed()
    return session.armed == true
end

---@return string|nil
function EquipCrossDrag.getSource()
    if not session.armed then return nil end
    return session.source
end

---@return boolean
function EquipCrossDrag.isDragging()
    return session.dragging == true
end

---@param sx number
---@param sy number
---@return boolean
function EquipCrossDrag.move(sx, sy)
    if not session.armed then return false end
    session.sx = sx
    session.sy = sy
    if session.dragging then return true end
    local dist = math.abs(sx - session.startSX) + math.abs(sy - session.startSY)
    if dist < DRAG_PX then return false end
    session.dragging = true
    haltSource()
    closeDetail()
    print("[EquipCrossDrag] 开始拖 seq=" .. tostring(session.seq)
        .. " slot=" .. tostring(session.slot) .. " from=" .. tostring(session.source))
    return true
end

local function reject(reason)
    local Toast = require("core.UiToast")
    Toast.show(reason)
    require("systems.GameSFX").playUIClick(1)
    require("systems.ButtonFeedback").trigger("equip_deny")
    print("[EquipCrossDrag] 拒绝穿戴 " .. tostring(reason))
end

local function tryDrop()
    -- [锻炉双页 0929] 锻炉工作台优先：拖到中栏锻炉工作台槽 → 放入工作台（强化/洗练）
    local overWB, smithOpen = overBlacksmithWorkbench(session.sx, session.sy)
    if smithOpen and overWB then
        local BlacksmithPage = require("ui.blacksmith.BlacksmithPage")
        if BlacksmithPage.setEquipBySeq(session.seq) then
            require("systems.GameSFX").playUIClick(1)
            print("[EquipCrossDrag] 放入锻炉工作台 seq=" .. tostring(session.seq))
        end
        return
    end
    local CharacterDetail = require("ui.character.detail.CharacterDetail")
    local heroId = CharacterDetail.getHeroId and CharacterDetail.getHeroId() or nil
    if not heroId then
        -- [锻炉双页 0929] 锻炉开着但没投中工作台：给明确提示而不是"请先打开角色"
        if smithOpen then
            require("core.UiToast").show("拖到锻炉工作台或角色装备槽")
            print("[EquipCrossDrag] 锻炉打开但未命中工作台")
            return
        end
        reject("请先打开角色")
        return
    end
    -- 仅配装页可拖入：属性/转职/觉醒页时装备槽不绘制，禁止不可见穿装
    if not (CharacterDetail.isEquipTab and CharacterDetail.isEquipTab()) then
        reject("请先切到配装页")
        return
    end
    local dx, dy = rightDesign(session.sx, session.sy)
    if not dx or not dy then
        print("[EquipCrossDrag] 右栏坐标不可用")
        return
    end
    local target = hitSlot(dx, dy)
    if not target then
        print("[EquipCrossDrag] 未投到槽位")
        return
    end
    if not canDrop(heroId, session.equipType, session.slot, session.grip, target) then
        -- 等级穿戴门槛：等级不足时给出专用提示
        local levelOk, requiredLevel = checkDropLevelGate(heroId)
        if not levelOk then
            reject(require("core.I18n").t("level_not_enough_equip", tostring(requiredLevel or 1)))
        else
            reject(require("core.I18n").t("cannot_wear"))
        end
        return
    end
    local Client = require("runtime.GameAction")
    local Protocol = require("shared.Protocol")
    Client.sendAction(Protocol.ACTION_TYPES.EQUIP_ITEM, {
        seq    = tonumber(session.seq),
        heroId = heroId,
        slot   = target,
    })
    require("systems.GameSFX").play("install")
    require("systems.ButtonFeedback").trigger("equip_quick")
    require("core.UiToast").show(require("core.I18n").t("equipped_ok"))
    local EquipPanel = require("ui.character.detail.CharacterDetailEquip")
    if EquipPanel.markDirty then EquipPanel.markDirty() end
    print("[EquipCrossDrag] 穿戴 seq=" .. tostring(session.seq)
        .. " hero=" .. tostring(heroId) .. " slot=" .. tostring(target))
end

---@param sx number
---@param sy number
---@return boolean consumed
function EquipCrossDrag.finish(sx, sy)
    if not session.armed then return false end
    session.sx = sx
    session.sy = sy
    local dragging = session.dragging == true
    if dragging then
        tryDrop()
        clearSession()
        return true
    end
    clearSession()
    return false
end

---@param vg any
function EquipCrossDrag.draw(vg)
    if not session.dragging then return end
    nvgSave(vg)
    nvgResetScissor(vg)

    -- [锻炉双页 0929] 锻炉工作台高亮：拖拽经过中栏工作台槽时画金色呼吸框
    local overWB, smithOpen = overBlacksmithWorkbench(session.sx, session.sy)
    if smithOpen then
        local note = Viewport.getNote("center")
        local okBS, BlacksmithPage = pcall(require, "ui.blacksmith.BlacksmithPage")
        local wb = okBS and BlacksmithPage.WORKBENCH or nil
        if note and wb then
            local panel = Viewport.PANELS.center
            local cs = note.s * Viewport.DS
            nvgSave(vg)
            nvgTranslate(vg, note.ox + panel.bx * note.s, note.oy + panel.by * note.s)
            nvgScale(vg, note.scaleX or cs, cs)
            local half = wb.size * 0.5
            nvgBeginPath(vg)
            nvgRoundedRect(vg, wb.cx - half - 10, wb.cy - half - 10, wb.size + 20, wb.size + 20, 28)
            nvgStrokeWidth(vg, overWB and 9 or 5)
            if overWB then
                nvgStrokeColor(vg, nvgRGBA(255, 214, 102, 235))
            else
                nvgStrokeColor(vg, nvgRGBA(255, 214, 102, 110))
            end
            nvgStroke(vg)
            nvgRestore(vg)
        end
    end

    local dx, dy = rightDesign(session.sx, session.sy)
    local note = Viewport.getNote("right")
    if dx and dy and note then
        local panel = Viewport.PANELS.right
        local CharacterDetail = require("ui.character.detail.CharacterDetail")
        local heroId = CharacterDetail.getHeroId and CharacterDetail.getHeroId() or nil
        if heroId and CharacterDetail.isEquipTab and CharacterDetail.isEquipTab() then
            local target = hitSlot(dx, dy)
            local Draw = require("ui.character.detail.CharacterDetailDraw")
            nvgSave(vg)
            nvgTranslate(vg, note.ox + panel.bx * note.s, note.oy + panel.by * note.s)
            nvgScale(vg, note.s * Viewport.DS, note.s * Viewport.DS)
            for _, s in ipairs(Draw.DT_SLOTS) do
                if canDrop(heroId, session.equipType, session.slot, session.grip, s.slot) then
                    nvgBeginPath(vg)
                    nvgCircle(vg, s.cx, s.cy, Draw.DT_SLOT_SIZE * 0.5 + 8)
                    nvgStrokeWidth(vg, 7)
                    nvgStrokeColor(vg, nvgRGBA(255, 214, 102, 235))
                    nvgStroke(vg)
                end
            end
            for _, s in ipairs(Draw.DT_SLOTS) do
                if s.slot == target
                    and not canDrop(heroId, session.equipType, session.slot, session.grip, target) then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, s.cx - 88, s.cy - 88, 176, 176, 20)
                    nvgStrokeWidth(vg, 6)
                    nvgStrokeColor(vg, nvgRGBA(180, 70, 70, 220))
                    nvgStroke(vg)
                    break
                end
            end
            nvgRestore(vg)
        end
    end

    local icon = session.templateId and ImageCache.getEquipIcon(session.templateId) or -1
    DarkIcon.drawQualityBg(vg, session.quality or 1, session.sx, session.sy, 78, 78, 0.95)
    if icon and icon >= 0 then
        DarkIcon.drawIconDark(vg, icon, session.sx, session.sy, 66, 66, 0.95)
    end
    nvgRestore(vg)
end

return EquipCrossDrag
