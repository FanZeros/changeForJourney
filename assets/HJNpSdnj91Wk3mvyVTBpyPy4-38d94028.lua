-- ChurchArtifactPanel.lua
-- 教堂神器子模块：槽位装配 + 神器背包
-- 从 ChurchPage.lua 拆分，坐标系 1080×2400

---@diagnostic disable: undefined-global

local GameConfig          = require("config.GameConfig")
local DrawUtil            = require("core.DrawUtil")
local PlayerStore         = require("client.data.PlayerStore")
local ArtifactDefs        = require("shared.artifact.ArtifactDefs")
local ArtifactSchema      = require("shared.artifact.ArtifactSchema")
local ArtifactDetailPanel = require("ui.ArtifactDetailPanel")
local ImageCache          = require("ui.ImageCache")
local ArtifactAssetUtil   = require("config.ArtifactAssetUtil")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格

local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest

local DESIGN_W = GameConfig.Design.WIDTH   -- 1080
local DESIGN_H = GameConfig.Design.HEIGHT  -- 2400

local M = {}

-- ======================== 布局常量 ========================

-- 顶部背景 UI_JTSQ_BJ：素材实际大小 1080×1349，顶端对齐、X 居中
local TOP_BG = {
    CX = 540,
    CY = 674.5,
    W = 1080,
    H = 1349,
}

-- 提示文字
local HINT = {
    X = 540, Y = 235,
    FONT = 38,
    TEXT = "在对应槽位装配神器对该位置角色进行加成",
}

-- 出战槽位（1~4 号位）
local SLOT = {
    CX_LIST   = { 115, 327, 540, 750, 962 },
    LABEL_Y   = 346,
    GRID_CY   = 624,
    SIZE      = 160,
    SUB_SIZE  = 130,
    SUB_GAP   = 16,
    LOCK_FONT = 26,
    LABEL_FONT = 38,
}

-- 下半部分背景 UI_TJP_1（九宫格，与背包/遗物背包一致）
local LOWER_PANEL = {
    CX = 540, CY = 1689, W = 1080, H = 1422,
    IT = 200, IR = 10, IB = 200, IL = 10,
}

-- 标题装饰 + 文字
local TITLE = {
    DECO_CX = 540, DECO_CY = 1135, DECO_W = 660, DECO_H = 60,
    TEXT_X = 540, TEXT_Y = 1135,
    FONT = 40,
    R = 0x45, G = 0x45, B = 0x45,
    TEXT = "神器背包",
}

local REROLL_BTN = {
    CX = 310, CY = 2129,
    W = 410, H = 100,
    FONT = 40,
}

local MERGE_BTN = {
    CX = 773, CY = 2129,
    W = 410, H = 100,
    FONT = 40,
    NP_T = 20, NP_R = 20, NP_B = 20, NP_L = 20,
    TEXT_R = 0x25, TEXT_G = 0x55, TEXT_B = 0x3d,
}

-- 背包网格
local GRID = {
    CELL_SIZE = 160,
    CELL_RADIUS = 24,
    GAP = 30,
    COLS = 5,
    MARGIN_LEFT = 80,  -- (1080 - 5*160 - 4*30) / 2
    CLIP_TOP = 1200,
    CLIP_BOTTOM = 2020,
    FIRST_ROW_TOP = 1200,
}

GRID.CLIP_H = GRID.CLIP_BOTTOM - GRID.CLIP_TOP

local CELL_COL_CX = {}
for c = 1, GRID.COLS do
    CELL_COL_CX[c] = GRID.MARGIN_LEFT + (c - 1) * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5
end

-- 空格子背景：纯黑 10%
-- [B-方案] 原空格平涂常量已废弃（格子底改用 DarkIcon.drawNine "slot" 暗铁凹槽）

-- 滚动参数
local SCROLL_FRICTION   = 0.90
local SCROLL_MIN_VEL    = 0.5
local SCROLL_WHEEL_STEP = 60

-- 背包至少显示的空格数
local BAG_DISPLAY_SLOTS = 20

local ctx_ = nil

-- ======================== 图片句柄 ========================

local img = {
    topBg   = -1,  -- UI_JTSQ_BJ.png
    slotGrid = -1, -- UI_JTSQ_GZ.png
    lowerBg = -1,  -- UI_TJP_1.png
    titleDeco = -1, -- UI_JJC_BTBJ.png
    mergeBtn = -1, -- UI_AN_LV.png
    rerollBtn = -1, -- UI_AN_HUANG.png
    iconUp   = -1, -- ICON_UP.png 可提升角标
}

-- ======================== 状态 ========================

local state = {
    scrollY      = 0,
    scrollMax    = 0,
    dragging     = false,
    lastDragY    = 0,
    scrollVel    = 0,
    selectedSlot = nil,   -- 1~5 | nil
    selectedSubSlot = nil, -- 1~3 | nil
    selectedBagIdx = nil, -- 背包格子索引 | nil
    pendingEquipArtifactId = nil, -- 从详情点击装备后等待选择槽位
    equipRequestPending = false, -- 安装请求等待服务端结果
    rerollMode = false,
    rerollSelectedIds = {}, -- 置换模式下选择的2个神器 id
}

-- ======================== 辅助 ========================

local function clampScroll()
    state.scrollY = math.max(0, math.min(state.scrollMax, state.scrollY))
end

local function calcScrollMax(totalSlots)
    local rows = math.ceil(totalSlots / GRID.COLS)
    local contentH = rows * GRID.CELL_SIZE + math.max(0, rows - 1) * GRID.GAP
    return math.max(0, contentH - GRID.CLIP_H)
end

local function isInGridScrollArea(dx, dy)
    return dx >= 0 and dx <= DESIGN_W
        and dy >= GRID.CLIP_TOP and dy <= GRID.CLIP_BOTTOM
end

local function getArtifactData()
    return PlayerStore.Get("artifacts") or { bag = {}, equipped = {}, pityRare = 0, pityEpic = 0 }
end

local function getBag()
    local data = getArtifactData()
    return data.bag or {}
end

local function isArtifactEquippedId(id)
    id = tostring(id or "")
    local data = getArtifactData()
    return ArtifactSchema.findEquippedSlot(data, id) ~= nil
end

local function getVisibleBag()
    local visible = {}
    for _, artifact in ipairs(getBag()) do
        if not isArtifactEquippedId(artifact.id) then
            visible[#visible + 1] = artifact
        end
    end
    return visible
end

local function findArtifactById(id)
    id = tostring(id or "")
    for _, artifact in ipairs(getBag()) do
        if tostring(artifact.id) == id then return artifact end
    end
    return nil
end

local function getPlayerLevel()
    return tonumber(PlayerStore.GetField("player", "level")) or 1
end

local function getUnlockedSubSlotCount()
    return ArtifactSchema.getUnlockedSubSlotCount(getPlayerLevel())
end

local function getSlotCell(slot, subSlot)
    local cx = SLOT.CX_LIST[slot]
    local totalH = ArtifactSchema.SUB_SLOT_COUNT * SLOT.SUB_SIZE
        + (ArtifactSchema.SUB_SLOT_COUNT - 1) * SLOT.SUB_GAP
    local firstCy = SLOT.GRID_CY - totalH * 0.5 + SLOT.SUB_SIZE * 0.5
    return cx, firstCy + (subSlot - 1) * (SLOT.SUB_SIZE + SLOT.SUB_GAP), SLOT.SUB_SIZE
end

local function getEquippedArtifact(slot, subSlot)
    local data = getArtifactData()
    local id = ArtifactSchema.getEquippedId(data, slot, subSlot or 1)
    if not id then return nil end
    return findArtifactById(id)
end

local function hasSameTypeInSlot(slot, artifact, ignoreSubSlot)
    if not artifact then return false end
    local artifactType = tonumber(artifact.artifactId) or tonumber(artifact.type) or 0
    if artifactType <= 0 then return false end
    local artifactInstanceId = tostring(artifact.id or "")
    for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
        if subSlot ~= ignoreSubSlot then
            local equipped = getEquippedArtifact(slot, subSlot)
            local equippedType = equipped and (tonumber(equipped.artifactId) or tonumber(equipped.type) or 0) or 0
            if equipped and equippedType == artifactType and tostring(equipped.id or "") ~= artifactInstanceId then
                return true
            end
        end
    end
    return false
end

local function getBagSlotCount()
    return math.max(BAG_DISPLAY_SLOTS, #getVisibleBag())
end

local function findBagIndexById(id)
    id = tostring(id or "")
    for idx, artifact in ipairs(getVisibleBag()) do
        if tostring(artifact.id) == id then return idx end
    end
    return nil
end

local function findMergeCandidates()
    local groups = {}
    for _, artifact in ipairs(getVisibleBag()) do
        local q = tonumber(artifact.quality) or 1
        if q < 6 then
            local artifactId = tonumber(artifact.artifactId) or tonumber(artifact.type) or 0
            if artifactId > 0 and ArtifactDefs.getRange(artifactId, q + 1) then
                local key = tostring(artifactId) .. "_" .. tostring(q)
                if not groups[key] then groups[key] = { artifactId = artifactId, quality = q, list = {} } end
                groups[key].list[#groups[key].list + 1] = artifact
            end
        end
    end

    local candidates = {}
    for _, group in pairs(groups) do
        if #group.list >= 3 then
            table.sort(group.list, function(a, b)
                local aid = tonumber(a.id) or 0
                local bid = tonumber(b.id) or 0
                return aid < bid
            end)
            local mergeCount = math.floor(#group.list / 3)
            for i = 1, mergeCount do
                local base = (i - 1) * 3
                candidates[#candidates + 1] = {
                    artifactId = group.artifactId,
                    quality = group.quality,
                    ids = {
                        group.list[base + 1].id,
                        group.list[base + 2].id,
                        group.list[base + 3].id,
                    },
                    count = #group.list,
                }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.artifactId < b.artifactId
    end)
    return candidates
end

local function isArtifactMergeable(artifact)
    if not artifact or isArtifactEquippedId(artifact.id) then return false end
    local q = tonumber(artifact.quality) or 1
    if q >= 6 then return false end
    local artifactId = tonumber(artifact.artifactId) or tonumber(artifact.type) or 0
    if artifactId <= 0 or not ArtifactDefs.getRange(artifactId, q + 1) then return false end

    local sameCount = 0
    for _, other in ipairs(getVisibleBag()) do
        if tonumber(other.artifactId) == artifactId and tonumber(other.quality) == q then
            sameCount = sameCount + 1
            if sameCount >= 3 then return true end
        end
    end
    return false
end

function M.canUpgradeAnyArtifact()
    return #findMergeCandidates() > 0
end

function M.getArtifactBadgeInfo()
    if M.canUpgradeAnyArtifact() then
        return true, nil
    end
    return false, nil
end

local showFloat

local function clearPendingEquip()
    state.pendingEquipArtifactId = nil
    state.equipRequestPending = false
end

local function clearRerollSelection()
    state.rerollSelectedIds = {}
end

local function isRerollSelected(id)
    id = tostring(id or "")
    for _, selectedId in ipairs(state.rerollSelectedIds or {}) do
        if tostring(selectedId) == id then return true end
    end
    return false
end

local function getRerollSelectedArtifacts()
    local list = {}
    for _, id in ipairs(state.rerollSelectedIds or {}) do
        local artifact = findArtifactById(id)
        if artifact then list[#list + 1] = artifact end
    end
    return list
end

local function toggleRerollSelect(artifact)
    if not artifact then return end
    local id = tostring(artifact.id)
    for i, selectedId in ipairs(state.rerollSelectedIds) do
        if tostring(selectedId) == id then
            table.remove(state.rerollSelectedIds, i)
            return
        end
    end
    if #state.rerollSelectedIds >= 2 then
        showFloat("最多选择2个神器", 540, 1120)
        return
    end
    if #state.rerollSelectedIds == 1 then
        local first = findArtifactById(state.rerollSelectedIds[1])
        if first and tonumber(first.quality) ~= tonumber(artifact.quality) then
            showFloat("请选择同品质神器", 540, 1120)
            return
        end
    end
    state.rerollSelectedIds[#state.rerollSelectedIds + 1] = id
end

local function canConfirmReroll()
    local selected = getRerollSelectedArtifacts()
    if #selected ~= 2 then return false end
    return tonumber(selected[1].quality) == tonumber(selected[2].quality)
end

local function getPendingEquipArtifact()
    if not state.pendingEquipArtifactId then return nil end
    return findArtifactById(state.pendingEquipArtifactId)
end

showFloat = function(text, x, y)
    if ctx_ and ctx_.state then
        ctx_.state.floatText = text
        ctx_.state.floatTextX = x or 540
        ctx_.state.floatTextY = y or 980
        ctx_.state.floatTextTime = time.elapsedTime
    else
        print("[ChurchArtifactPanel] " .. tostring(text))
    end
end

local function sendAction(action, params)
    if ctx_ and ctx_.getClient then
        ctx_.getClient().sendAction(action, params or {})
        return true
    end
    showFloat("网络未连接")
    return false
end

local function drawArtifactIcon(vg, artifact, cx, cy, size, selected)
    ArtifactAssetUtil.drawIcon(vg, artifact, cx, cy, size, {
        selected = selected,
    })
end

local function updateScrollInertia()
    if state.dragging then return end
    if math.abs(state.scrollVel) > SCROLL_MIN_VEL then
        state.scrollY = state.scrollY + state.scrollVel
        state.scrollVel = state.scrollVel * SCROLL_FRICTION
        clampScroll()
    else
        state.scrollVel = 0
    end
end

-- ======================== Public API ========================

function M.setContext(ctx)
    ctx_ = ctx
end

function M.init(vg)
    ImageCache.init(vg)
    ArtifactAssetUtil.preloadIcons()

    img.topBg     = nvgCreateImage(vg, "image/UI_JTSQ_BJ.png", 0)
    -- [暗黑化 P1-B5] 原 image/UI_TJP_1.png 贴图加载已移除（矢量绘制替代）
    img.lowerBg   = nvgCreateImage(vg, "image/UI_TJP_1.png", 0)
    img.titleDeco = nvgCreateImage(vg, "image/UI_JJC_BTBJ.png", 0)
    img.mergeBtn  = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    img.rerollBtn = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    img.iconUp    = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    ArtifactDetailPanel.init(vg)
    ArtifactDetailPanel.setOnEquip(function(artifact, location, slot, subSlot)
        if location == "slot" then
            local Protocol = ctx_ and ctx_.getProtocol and ctx_.getProtocol() or nil
            if Protocol and slot then
                sendAction(Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP, { slot = slot, subSlot = subSlot or 1 })
                showFloat("正在卸下神器", SLOT.CX_LIST[slot] or 540, SLOT.GRID_CY - 120)
            end
            clearPendingEquip()
            state.selectedSlot = nil
            state.selectedSubSlot = nil
            state.selectedBagIdx = nil
        else
            state.pendingEquipArtifactId = tostring(artifact.id)
            state.selectedBagIdx = findBagIndexById(artifact.id)
            state.selectedSlot = nil
            state.selectedSubSlot = nil
            showFloat("请选择上方槽位安装神器", 540, 430)
        end
        ArtifactDetailPanel.hide()
    end)
    ArtifactDetailPanel.setOnRefine(function(artifact)
        local Protocol = ctx_ and ctx_.getProtocol and ctx_.getProtocol() or nil
        if not Protocol then
            showFloat("网络未连接", 540, 1430)
            return
        end
        sendAction(Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE, { artifactId = artifact.id })
        showFloat("正在洗练神器数值", 540, 1430)
    end)

    if img.topBg < 0 then
        print("[ChurchArtifactPanel] WARN: UI_JTSQ_BJ.png load failed")
    end
    print("[ChurchArtifactPanel] init OK (topBg " .. TOP_BG.W .. "x" .. TOP_BG.H .. ")")
end

function M.reset()
    state.scrollY = 0
    state.scrollMax = 0
    state.dragging = false
    state.scrollVel = 0
    state.selectedSlot = nil
    state.selectedSubSlot = nil
    state.selectedBagIdx = nil
    state.rerollMode = false
    clearRerollSelection()
    clearPendingEquip()
    ArtifactDetailPanel.hide()
end

--- 绘制神器 Tab 全屏背景（在 Tab 内容下层）
function M.drawBg(vg)
    if img.topBg >= 0 then
        drawImageCentered(vg, img.topBg, TOP_BG.CX, TOP_BG.CY, TOP_BG.W, TOP_BG.H, 1.0)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, TOP_BG.H)
        nvgFillColor(vg, nvgRGBA(44, 42, 48, 255))
        nvgFill(vg)
    end

    DarkIcon.drawNine(vg, "plain", LOWER_PANEL.CX - LOWER_PANEL.W * 0.5, LOWER_PANEL.CY - LOWER_PANEL.H * 0.5, LOWER_PANEL.W, LOWER_PANEL.H)
end

--- 绘制神器 Tab 交互内容
function M.drawContent(vg)
    updateScrollInertia()

    -- 提示文字（白字黑描边）
    drawTextStroke(vg, HINT.X, HINT.Y, HINT.TEXT, HINT.FONT,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 5)

    -- 出战槽位标签 + 格子
    local unlockedSubSlots = getUnlockedSubSlotCount()
    for i = 1, 5 do
        local cx = SLOT.CX_LIST[i]
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, SLOT.LABEL_FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, cx, SLOT.LABEL_Y, i .. "号位", nil)

        local pending = state.pendingEquipArtifactId and true or false
        for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
            local subCx, subCy, subSize = getSlotCell(i, subSlot)
            local equipped = getEquippedArtifact(i, subSlot)
            local selected = state.selectedSlot == i and state.selectedSubSlot == subSlot
            local locked = subSlot > unlockedSubSlots
            drawImageCentered(vg, img.slotGrid, subCx, subCy, subSize, subSize, 1.0)
            nvgGlobalAlpha(vg, locked and 0.45 or 1.0)
            drawArtifactIcon(vg, equipped, subCx, subCy, subSize, selected or pending)
            nvgGlobalAlpha(vg, 1.0)
            if locked then
                local unlockLevel = ArtifactSchema.getSubSlotUnlockLevel(subSlot)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, subCx - subSize * 0.5, subCy - subSize * 0.5, subSize, subSize, 18)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 110))
                nvgFill(vg)
                drawTextStroke(vg, subCx, subCy, tostring(unlockLevel) .. "级", SLOT.LOCK_FONT,
                    NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 3)
            end
        end
    end

    -- 标题装饰 + 文字
    drawImageCentered(vg, img.titleDeco, TITLE.DECO_CX, TITLE.DECO_CY, TITLE.DECO_W, TITLE.DECO_H, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TITLE.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(TITLE.R, TITLE.G, TITLE.B, 255))
    nvgText(vg, TITLE.TEXT_X, TITLE.TEXT_Y, TITLE.TEXT, nil)

    -- 背包网格（可滚动）
    local bag = getVisibleBag()
    local totalSlots = getBagSlotCount()
    state.scrollMax = calcScrollMax(totalSlots)
    clampScroll()

    nvgSave(vg)
    nvgScissor(vg, 0, GRID.CLIP_TOP, DESIGN_W, GRID.CLIP_H)
    nvgTranslate(vg, 0, -state.scrollY)

    for idx = 1, totalSlots do
        local col = ((idx - 1) % GRID.COLS) + 1
        local row = math.floor((idx - 1) / GRID.COLS)
        local cx = CELL_COL_CX[col]
        local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5

        local screenY = cy - state.scrollY
        if screenY < GRID.CLIP_TOP - GRID.CELL_SIZE then
            goto continue_bag
        end
        if screenY > GRID.CLIP_BOTTOM + GRID.CELL_SIZE then
            break
        end

        -- 格子底：暗铁凹槽（[B-方案] 古卷化，与其他格子界面一致）
        DarkIcon.drawNine(vg, "slot",
            cx - GRID.CELL_SIZE * 0.5, cy - GRID.CELL_SIZE * 0.5,
            GRID.CELL_SIZE, GRID.CELL_SIZE, { radius = GRID.CELL_RADIUS })

        local artifact = bag[idx]
        local selected = state.selectedBagIdx == idx or (artifact and isRerollSelected(artifact.id))
        drawArtifactIcon(vg, artifact, cx, cy, GRID.CELL_SIZE, selected)
        if artifact and state.rerollMode and isRerollSelected(artifact.id) then
            local order = 0
            for si, sid in ipairs(state.rerollSelectedIds) do
                if tostring(sid) == tostring(artifact.id) then order = si break end
            end
            drawTextStroke(vg, cx + GRID.CELL_SIZE * 0.5 - 28, cy - GRID.CELL_SIZE * 0.5 + 28,
                tostring(order), 30, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 4)
        end
        if artifact and (not state.rerollMode) and isArtifactMergeable(artifact) then
            local mTxtX = cx - GRID.CELL_SIZE * 0.5 + 8
            local mTxtY = cy + GRID.CELL_SIZE * 0.5 - 6
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            local step = math.pi * 2 / 12
            for si = 0, 11 do
                local a = si * step
                nvgText(vg, mTxtX + math.cos(a) * 2, mTxtY + math.sin(a) * 2, "可合成", nil)
            end
            nvgFillColor(vg, nvgRGBA(0x4c, 0xfa, 0x4c, 255))
            nvgText(vg, mTxtX, mTxtY, "可合成", nil)

            if img.iconUp >= 0 then
                local upSize = 40
                local upX = cx + GRID.CELL_SIZE * 0.5 - upSize * 0.5 - 2
                local upY = cy - GRID.CELL_SIZE * 0.5 + upSize * 0.5 + 2
                drawImageCentered(vg, img.iconUp, upX, upY, upSize, upSize, 1.0)
            end
        end

        ::continue_bag::
    end

    nvgRestore(vg)

    local candidates = findMergeCandidates()
    local rerollSelectedCount = #state.rerollSelectedIds

    local rerollBtnX = REROLL_BTN.CX - REROLL_BTN.W * 0.5
    local rerollBtnY = REROLL_BTN.CY - REROLL_BTN.H * 0.5
    local _bfReroll = require("systems.ButtonFeedback").begin(vg, "artifactBagReroll", REROLL_BTN.CX, REROLL_BTN.CY, REROLL_BTN.W, REROLL_BTN.H)
    drawImageCentered(vg, img.rerollBtn, REROLL_BTN.CX, REROLL_BTN.CY, REROLL_BTN.W, REROLL_BTN.H, 1.0)
    require("systems.ButtonFeedback").finish(vg, _bfReroll)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, REROLL_BTN.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(MERGE_BTN.TEXT_R, MERGE_BTN.TEXT_G, MERGE_BTN.TEXT_B, 255))
    nvgText(vg, REROLL_BTN.CX, REROLL_BTN.CY, state.rerollMode and "退出置换" or "神器置换", nil)

    local btnX = MERGE_BTN.CX - MERGE_BTN.W * 0.5
    local btnY = MERGE_BTN.CY - MERGE_BTN.H * 0.5
    local enabled = state.rerollMode and canConfirmReroll() or (#candidates > 0)
    nvgGlobalAlpha(vg, enabled and 1.0 or 0.45)
    local _bfMerge = require("systems.ButtonFeedback").begin(vg, "artifactBagMerge", MERGE_BTN.CX, MERGE_BTN.CY, MERGE_BTN.W, MERGE_BTN.H)
    drawImageCentered(vg, img.mergeBtn, MERGE_BTN.CX, MERGE_BTN.CY, MERGE_BTN.W, MERGE_BTN.H, 1.0)
    require("systems.ButtonFeedback").finish(vg, _bfMerge)
    nvgGlobalAlpha(vg, 1.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, MERGE_BTN.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(MERGE_BTN.TEXT_R, MERGE_BTN.TEXT_G, MERGE_BTN.TEXT_B, enabled and 255 or 180))
    local label
    if state.rerollMode then
        label = "确认置换" .. tostring(rerollSelectedCount) .. "/2"
    else
        label = enabled and ("一键合成(" .. tostring(#candidates) .. ")") or "一键合成"
    end
    nvgText(vg, MERGE_BTN.CX, MERGE_BTN.CY, label, nil)

    ArtifactDetailPanel.draw(vg)
end

--- Tab 内点击
---@return boolean consumed
function M.handleTabInput(dx, dy)
    if ArtifactDetailPanel.handleTap(dx, dy) then
        return true
    end

    local Protocol = ctx_ and ctx_.getProtocol and ctx_.getProtocol() or nil

    local candidates = findMergeCandidates()
    if hitTest(dx, dy, REROLL_BTN.CX, REROLL_BTN.CY, REROLL_BTN.W, REROLL_BTN.H) then
        require("systems.ButtonFeedback").trigger("artifactBagReroll")
        state.rerollMode = not state.rerollMode
        clearPendingEquip()
        state.selectedSlot = nil
        state.selectedSubSlot = nil
        state.selectedBagIdx = nil
        clearRerollSelection()
        ArtifactDetailPanel.hide()
        showFloat(state.rerollMode and "请选择2个同品质神器" or "已退出置换", REROLL_BTN.CX, REROLL_BTN.CY - 120)
        return true
    end

    if hitTest(dx, dy, MERGE_BTN.CX, MERGE_BTN.CY, MERGE_BTN.W, MERGE_BTN.H) then
        require("systems.ButtonFeedback").trigger("artifactBagMerge")
        if state.rerollMode then
            if not canConfirmReroll() then
                showFloat("请选择2个同品质神器", MERGE_BTN.CX, MERGE_BTN.CY - 120)
            elseif Protocol then
                sendAction(Protocol.ACTION_TYPES.ARTIFACT_REROLL, { artifactIds = { state.rerollSelectedIds[1], state.rerollSelectedIds[2] } })
                showFloat("正在置换神器", MERGE_BTN.CX, MERGE_BTN.CY - 120)
                clearRerollSelection()
                state.selectedBagIdx = nil
            else
                showFloat("网络未连接", MERGE_BTN.CX, MERGE_BTN.CY - 120)
            end
        elseif #candidates == 0 then
            showFloat("暂无可合成神器", MERGE_BTN.CX, MERGE_BTN.CY - 120)
        elseif Protocol then
            local groups = {}
            for _, candidate in ipairs(candidates) do
                groups[#groups + 1] = candidate.ids
            end
            sendAction(Protocol.ACTION_TYPES.ARTIFACT_MERGE, { artifactIdGroups = groups })
            clearPendingEquip()
            state.selectedBagIdx = nil
            showFloat("正在合成" .. tostring(#groups) .. "组神器", MERGE_BTN.CX, MERGE_BTN.CY - 120)
        else
            showFloat("网络未连接", MERGE_BTN.CX, MERGE_BTN.CY - 120)
        end
        return true
    end

    -- 出战槽位点击
    local unlockedSubSlots = getUnlockedSubSlotCount()
    for i = 1, 5 do
        for subSlot = 1, ArtifactSchema.SUB_SLOT_COUNT do
            local cx, cy, size = getSlotCell(i, subSlot)
            if hitTest(dx, dy, cx, cy, size, size) then
                local pendingArtifact = getPendingEquipArtifact()
                local equipped = getEquippedArtifact(i, subSlot)
                local locked = subSlot > unlockedSubSlots
                if locked and pendingArtifact then
                    local unlockLevel = ArtifactSchema.getSubSlotUnlockLevel(subSlot)
                    showFloat("冒险等级达到" .. tostring(unlockLevel) .. "级解锁", cx, cy - 80)
                elseif locked and not equipped then
                    local unlockLevel = ArtifactSchema.getSubSlotUnlockLevel(subSlot)
                    showFloat("冒险等级达到" .. tostring(unlockLevel) .. "级解锁", cx, cy - 80)
                elseif pendingArtifact and hasSameTypeInSlot(i, pendingArtifact, subSlot) then
                    showFloat("同一槽位不能佩戴相同类型神器", cx, cy - 80)
                elseif pendingArtifact and Protocol then
                    if state.equipRequestPending then
                        showFloat("正在安装神器", cx, cy - 80)
                    else
                        local sent = sendAction(Protocol.ACTION_TYPES.ARTIFACT_EQUIP, {
                            artifactId = pendingArtifact.id,
                            slot = i,
                            subSlot = subSlot,
                        })
                        if sent then
                            showFloat("正在安装神器", cx, cy - 80)
                            state.equipRequestPending = true
                            state.selectedSlot = i
                            state.selectedSubSlot = subSlot
                            state.selectedBagIdx = findBagIndexById(pendingArtifact.id)
                        end
                    end
                elseif pendingArtifact then
                    showFloat("网络未连接", cx, cy - 80)
                elseif equipped then
                    ArtifactDetailPanel.show(equipped, "slot", i, subSlot)
                    state.selectedSlot = i
                    state.selectedSubSlot = subSlot
                    state.selectedBagIdx = nil
                else
                    if state.selectedSlot == i and state.selectedSubSlot == subSlot then
                        state.selectedSlot = nil
                        state.selectedSubSlot = nil
                    else
                        state.selectedSlot = i
                        state.selectedSubSlot = subSlot
                    end
                    showFloat("先在背包神器详情中点击安装", cx, cy - 80)
                end
                print("[ChurchArtifactPanel] slot click " .. i .. ":" .. subSlot)
                return true
            end
        end
    end

    -- 背包格子点击
    if isInGridScrollArea(dx, dy) then
        local bag = getVisibleBag()
        local totalSlots = getBagSlotCount()
        for idx = 1, totalSlots do
            local col = ((idx - 1) % GRID.COLS) + 1
            local row = math.floor((idx - 1) / GRID.COLS)
            local cx = CELL_COL_CX[col]
            local cy = GRID.FIRST_ROW_TOP + row * (GRID.CELL_SIZE + GRID.GAP) + GRID.CELL_SIZE * 0.5 - state.scrollY
            if hitTest(dx, dy, cx, cy, GRID.CELL_SIZE, GRID.CELL_SIZE) then
                local artifact = bag[idx]
                if not artifact then
                    state.selectedBagIdx = nil
                    clearPendingEquip()
                    return true
                end
                if state.rerollMode then
                    toggleRerollSelect(artifact)
                    state.selectedBagIdx = idx
                    state.selectedSlot = nil
                    state.selectedSubSlot = nil
                    ArtifactDetailPanel.hide()
                    return true
                end
                state.selectedBagIdx = idx
                state.selectedSlot = nil
                state.selectedSubSlot = nil
                ArtifactDetailPanel.show(artifact, "bag")
                print("[ChurchArtifactPanel] bag click " .. idx)
                return true
            end
        end
        return true
    end

    return false
end

function M.onArtifactEquipResult(success)
    state.equipRequestPending = false
    if success then
        clearPendingEquip()
    end
end

function M.onArtifactRerollResult(success)
    if success then
        state.rerollMode = false
        clearRerollSelection()
        state.selectedBagIdx = nil
        state.selectedSlot = nil
        state.selectedSubSlot = nil
        clearPendingEquip()
        ArtifactDetailPanel.hide()
    end
end

function M.onArtifactRefineValueResult(success, artifactId)
    if success then
        local artifact = findArtifactById(artifactId)
        if artifact then
            ArtifactDetailPanel.refreshArtifact(artifact)
        end
        showFloat("洗练成功", 540, 1430)
    end
end

---@return boolean consumed
function M.handleDragBegin(dx, dy)
    if ArtifactDetailPanel.isVisible() then return false end
    if not isInGridScrollArea(dx, dy) then return false end
    state.dragging = true
    state.lastDragY = dy
    state.scrollVel = 0
    return true
end

---@return boolean consumed
function M.handleDragMove(dx, dy)
    if not state.dragging then return false end
    local delta = state.lastDragY - dy
    state.scrollY = state.scrollY + delta
    state.lastDragY = dy
    state.scrollVel = delta
    clampScroll()
    return true
end

function M.handleDragEnd(_dx, _dy)
    if not state.dragging then return end
    state.dragging = false
end

---@param wheel number
function M.handleScroll(wheel)
    if ArtifactDetailPanel.isVisible() then return end
    state.scrollY = state.scrollY - wheel * SCROLL_WHEEL_STEP
    state.scrollVel = 0
    clampScroll()
end

return M
