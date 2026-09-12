-- ============================================================================
-- RelicDetailPanel - 遗物详情弹窗
-- 点击遗物背包中的遗物图标时弹出，展示遗物详细信息和操作按钮
-- 坐标系: 设计分辨率 1080x2400
-- ============================================================================

local DrawUtil          = require("core.DrawUtil")
local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest
local BF                = require("systems.ButtonFeedback")
local RelicSystem       = require("systems.RelicSystem")
local RelicDefs         = require("data.RelicDefs")

local RelicDetailPanel = {}

-- ======================== 动画常量 ========================

local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.18

local function easeOutCubic(t)
    local u = 1 - t; return 1 - u * u * u
end

local function easeInCubic(t)
    return t * t * t
end

-- ======================== 布局常量 ========================

-- 背景面板（与道具详情相同素材和九宫格切法）
local BG = {
    CX = 540, CY = 1146,
    W  = 530, H  = 894,
    -- 九宫格切割（同道具详情 UI_ZBTS）
    IT = 400, IR = 93, IB = 93, IL = 93,
}

-- 遗物名称 - 左对齐 X316 Y759
local NAME = {
    X = 316, Y = 759,
    FONT = 40,
    STROKE = 4,
}

-- 文本"遗物" - 左对齐 X316 Y840 字号30 纯白
local TYPE_LABEL = {
    X = 316, Y = 840,
    FONT = 30,
}

-- 品质文本 - 左对齐 X316 Y995 字号30 颜色fff600 描边282828大小4
local QUALITY = {
    X = 316, Y = 995,
    FONT = 30,
    -- 颜色/描边固定
    R = 0xff, G = 0xf6, B = 0x00,
    STROKE = 4,
    STROKE_R = 0x28, STROKE_G = 0x28, STROKE_B = 0x28,
}

-- 战力图标+文本 - 左对齐 X316 Y1051
local POWER = {
    ICON_X = 316, ICON_Y = 1051,   -- 图标左上角
    ICON_W = 40, ICON_H = 40,
    TEXT_X = 360, TEXT_Y = 1051,    -- 图标右侧留4px间距
    FONT = 30,
    TEXT_R = 0xf7, TEXT_G = 0xfe, TEXT_B = 0x77,
    STROKE = 4,
    STROKE_R = 0x23, STROKE_G = 0x23, STROKE_B = 0x23,
    -- 可提升角标
    UP_W = 40, UP_H = 40,
}

-- 文本"遗物效果" - X403 Y1129 字号34 颜色918f88
local EFFECT_LABEL = {
    X = 403, Y = 1129,
    FONT = 34,
    R = 0x91, G = 0x8f, B = 0x88,
}

-- 效果描述区域背景 - X540 Y1283 460*250 纯黑5% 圆角14
local DESC_BG = {
    CX = 540, CY = 1283,
    W = 460, H = 250,
    R = 14,
    FILL_R = 0, FILL_G = 0, FILL_B = 0, FILL_A = 13,  -- 纯黑 5% (255*0.05≈13)
}

-- 效果描述文字 - 内间距30 字号34 颜色725850
local DESC_TEXT = {
    PADDING = 30,
    FONT = 34,
    LINE_H = 44,
    R = 0x72, G = 0x58, B = 0x50,
}

-- 遗物图标 - X629 Y943 使用ICON_YWX小图标原大小256x256
local RELIC_ICON = {
    CX = 629, CY = 943,
    W = 256, H = 256,
}

-- "洗练"按钮（九宫格参数同角色详情面板：上下15 左右60）
local BTN_REFORGE = {
    CX = 427, CY = 1496,
    W = 210, H = 100,
    NP_T = 15, NP_R = 60, NP_B = 15, NP_L = 60,
    FONT = 38,
    TEXT_R = 0, TEXT_G = 0, TEXT_B = 0, TEXT_A = 191,
}

-- "装备"按钮（九宫格参数同角色详情面板：上下15 左右60）
local BTN_EQUIP = {
    CX = 653, CY = 1496,
    W = 210, H = 100,
    NP_T = 15, NP_R = 60, NP_B = 15, NP_L = 60,
    FONT = 38,
    TEXT_R = 0, TEXT_G = 0, TEXT_B = 0, TEXT_A = 191,
}

-- ======================== 图片资源 ========================

local imgBg        = {}  -- [1..5] 品质背景
local imgBtnHuang  = -1  -- UI_AN_HUANG.png
local imgBtnLv     = -1  -- UI_AN_LV.png
local imgPowerIcon = -1  -- ICON_ZDL.png（战力图标）
local imgUpBig     = -1  -- ICON_UP_big.png（可提升角标）
local imgLock      = -1  -- UI_ICON_SUO.png（锁定图标，与装备详情一致）
local imgRelicIcon = {}  -- [1..5] 遗物图标 (ICON_YWX_*)

-- ======================== 状态 ========================

local state = {
    visible   = false,
    opening   = false,
    closing   = false,
    openTime  = 0,
    closeTime = 0,
    relic     = nil,   -- 当前展示的遗物数据
    location  = nil,   -- "bag" 或 "grid"
    lockHotspot = nil, -- 锁定图标点击热区
}

local onReforgeCallback_ = nil
local onEquipCallback_   = nil
local onCloseCallback_   = nil

--- 从 PlayerStore 刷新当前遗物引用（重进游戏 / pushModule 后保持锁定态一致）
local function syncRelicFromStore()
    if not state.relic or state.relic.id == nil then return end
    local fresh, loc = RelicSystem.findById(state.relic.id)
    if fresh then
        state.relic = fresh
        if loc then state.location = loc end
    end
end

-- ======================== 初始化 ========================

function RelicDetailPanel.init(vg)
    -- 品质背景 (UI_ZBTS_1~6)
    for i = 1, 6 do
        imgBg[i] = nvgCreateImage(vg, "image/UI_ZBTS_" .. i .. ".png", 0)
    end
    -- 按钮
    imgBtnHuang = nvgCreateImage(vg, "image/UI_AN_HUANG.png", 0)
    imgBtnLv    = nvgCreateImage(vg, "image/UI_AN_LV.png", 0)
    -- 战力图标 + 可提升角标
    imgPowerIcon = nvgCreateImage(vg, "image/ICON_ZDL.png", 0)
    imgUpBig     = nvgCreateImage(vg, "image/ICON_UP_big.png", 0)
    imgLock      = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)
    -- 遗物图标 (ICON_YWX_*)
    local iconKeys = { "GUI", "SHE", "LU", "LANG", "YING" }
    for i, key in ipairs(iconKeys) do
        imgRelicIcon[i] = nvgCreateImage(vg, "image/ICON_YWX_" .. key .. ".png", 0)
    end
    print("[RelicDetailPanel] init OK")
end

-- ======================== 显示/隐藏 ========================

--- 打开详情面板
---@param relic table 遗物数据 { id, type, quality, affixId, locked, ... }
---@param location string|nil "bag" 或 "grid"
function RelicDetailPanel.show(relic, location)
    if not relic then return end
    state.relic    = relic
    state.location = location or "bag"
    syncRelicFromStore()
    state.visible  = true
    state.opening  = true
    state.closing  = false
    state.openTime = time.elapsedTime
end

--- 关闭详情面板
function RelicDetailPanel.hide()
    if not state.visible then return end
    state.closing   = true
    state.opening   = false
    state.closeTime = time.elapsedTime
end

--- 是否可见
function RelicDetailPanel.isVisible()
    return state.visible
end

--- 设置回调
function RelicDetailPanel.setOnReforge(fn)
    onReforgeCallback_ = fn
end

function RelicDetailPanel.setOnEquip(fn)
    onEquipCallback_ = fn
end

function RelicDetailPanel.setOnClose(fn)
    onCloseCallback_ = fn
end

-- ======================== 内部动画驱动 ========================

local function internalUpdate()
    if not state.visible then return end
    local now = time.elapsedTime

    if state.opening then
        local elapsed = now - state.openTime
        if elapsed >= ANIM_OPEN_DUR then
            state.opening = false
        end
    elseif state.closing then
        local elapsed = now - state.closeTime
        if elapsed >= ANIM_CLOSE_DUR then
            state.closing = false
            state.visible = false
            state.relic   = nil
            if onCloseCallback_ then onCloseCallback_() end
        end
    end
end

--- 外部 update 接口（兼容）
function RelicDetailPanel.update(dt)
end

-- ======================== 绘制 ========================

function RelicDetailPanel.draw(vg)
    if not state.visible then return end
    syncRelicFromStore()
    if not state.relic then return end

    -- 自驱动动画
    internalUpdate()
    if not state.visible then return end

    local relic = state.relic
    state.lockHotspot = nil

    -- 计算动画进度
    local now = time.elapsedTime
    local progress = 1.0
    if state.opening then
        local t = math.min((now - state.openTime) / ANIM_OPEN_DUR, 1.0)
        progress = easeOutCubic(t)
    elseif state.closing then
        local t = math.min((now - state.closeTime) / ANIM_CLOSE_DUR, 1.0)
        progress = 1.0 - easeInCubic(t)
    end

    -- 全屏遮罩（纯黑 50%）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(128 * progress)))
    nvgFill(vg)

    -- 缩放动画
    local scale = 0.8 + 0.2 * progress
    nvgSave(vg)
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -BG.CX, -BG.CY)
    nvgGlobalAlpha(vg, progress)

    -- 1) 背景九宫格
    local q = math.min(relic.quality or 1, 5)
    local bgImg = imgBg[q] or imgBg[1]
    drawNineSlice(vg, bgImg,
        BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5,
        BG.W, BG.H,
        BG.IT, BG.IR, BG.IB, BG.IL)

    -- 1.5) 遗物图标 - X629 Y943 160x160（原大图320缩放50%）
    local relicImg = imgRelicIcon[relic.type] or imgRelicIcon[1]
    if relicImg and relicImg >= 0 then
        drawImageCentered(vg, relicImg,
            RELIC_ICON.CX, RELIC_ICON.CY,
            RELIC_ICON.W, RELIC_ICON.H, 1.0)
    end

    -- 2) 遗物名称 - 左对齐 X316 Y759
    local typeDef = RelicDefs.TYPES[relic.type]
    local qualityDef = RelicDefs.QUALITIES[relic.quality]
    local relicName = typeDef and typeDef.name or "未知遗物"
    drawTextStroke(vg, NAME.X, NAME.Y, relicName,
        NAME.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 255, 255, NAME.STROKE)

    -- 2.1) 锁定图标 - 名称右侧（可点击切换）
    if imgLock >= 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, NAME.FONT)
        local nameW = nvgTextBounds(vg, 0, 0, relicName)
        local LOCK_SIZE = 48
        local LOCK_GAP  = 14
        local lockCX = NAME.X + nameW + LOCK_GAP + LOCK_SIZE * 0.5
        local locked = RelicSystem.isLocked(relic)
        drawImageCentered(vg, imgLock, lockCX, NAME.Y, LOCK_SIZE, LOCK_SIZE,
            locked and 1.0 or 0.4)
        state.lockHotspot = {
            cx = lockCX, cy = NAME.Y,
            w  = LOCK_SIZE + 24, h = LOCK_SIZE + 24,
        }
    end

    -- 3) 文本"遗物" - 左对齐 X316 Y840 字号30 纯白
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TYPE_LABEL.FONT)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, TYPE_LABEL.X, TYPE_LABEL.Y, "遗物", nil)

    -- 4) 品质文本 - 左对齐 X316 Y995 字号30 颜色fff600 描边282828大小4
    local qualityName = qualityDef and qualityDef.name or "普通"
    local qColor = qualityDef and qualityDef.color or "fff600"
    local qualityR = tonumber(qColor:sub(1, 2), 16) or 0xff
    local qualityG = tonumber(qColor:sub(3, 4), 16) or 0xf6
    local qualityB = tonumber(qColor:sub(5, 6), 16) or 0x00
    drawTextStroke(vg, QUALITY.X, QUALITY.Y, qualityName,
        QUALITY.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        qualityR, qualityG, qualityB, QUALITY.STROKE,
        { strokeColor = { QUALITY.STROKE_R, QUALITY.STROKE_G, QUALITY.STROKE_B } })

    -- 5) 战力图标+文本 - 左对齐 X316 Y1051
    local strength = qualityDef and qualityDef.strength or 0
    local powerStr = tostring(math.floor(strength))

    -- 战力图标（左对齐，垂直居中于Y1051）
    if imgPowerIcon >= 0 then
        drawImageCentered(vg, imgPowerIcon,
            POWER.ICON_X + POWER.ICON_W * 0.5,
            POWER.ICON_Y,
            POWER.ICON_W, POWER.ICON_H, 1.0)
    end

    -- 战力数值文本
    drawTextStroke(vg, POWER.TEXT_X, POWER.TEXT_Y, powerStr,
        POWER.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        POWER.TEXT_R, POWER.TEXT_G, POWER.TEXT_B, POWER.STROKE,
        { strokeColor = { POWER.STROKE_R, POWER.STROKE_G, POWER.STROKE_B } })

    -- 可提升角标（品质<6时显示）
    if relic.quality and relic.quality < 6 and imgUpBig >= 0 then
        -- 计算文本宽度以确定角标位置
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, POWER.FONT)
        local textW = nvgTextBounds(vg, 0, 0, powerStr, nil, nil)
        local upX = POWER.TEXT_X + textW + 4 + POWER.UP_W * 0.5
        drawImageCentered(vg, imgUpBig, upX, POWER.TEXT_Y,
            POWER.UP_W, POWER.UP_H, 1.0)
    end

    -- 6) 文本"遗物效果" - 居中 Y1129 字号34 颜色918f88
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, EFFECT_LABEL.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(EFFECT_LABEL.R, EFFECT_LABEL.G, EFFECT_LABEL.B, 255))
    nvgText(vg, BG.CX, EFFECT_LABEL.Y, "遗物效果", nil)

    -- 7) 文本背景区域 - X540 Y1283 460*250 纯黑5% 圆角14
    DrawUtil.drawRoundedRectCentered(vg,
        DESC_BG.CX, DESC_BG.CY,
        DESC_BG.W, DESC_BG.H,
        DESC_BG.R,
        DESC_BG.FILL_R, DESC_BG.FILL_G, DESC_BG.FILL_B, DESC_BG.FILL_A)

    -- 8) 段落文本描述 - 内间距30 字号34 颜色725850
    local affixText = RelicSystem.getRelicAffixText(relic)
    if affixText and affixText ~= "" then
        local textX = DESC_BG.CX - DESC_BG.W * 0.5 + DESC_TEXT.PADDING
        local textY = DESC_BG.CY - DESC_BG.H * 0.5 + DESC_TEXT.PADDING
        local maxW  = DESC_BG.W - DESC_TEXT.PADDING * 2

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, DESC_TEXT.FONT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(DESC_TEXT.R, DESC_TEXT.G, DESC_TEXT.B, 255))
        nvgTextBox(vg, textX, textY, maxW, affixText, nil)
    end

    -- 按钮区域：grid 模式只显示居中"取下"，bag 模式显示"洗练"+"装备"
    if state.location == "grid" then
        -- 已安装遗物：只显示居中的"取下"按钮
        ---@diagnostic disable-next-line: assign-type-mismatch
        local btnCX = BG.CX  -- 540 居中
        local _bfEq = BF.begin(vg, "relic_detail_equip", btnCX, BTN_EQUIP.CY, BTN_EQUIP.W, BTN_EQUIP.H)
        drawNineSlice(vg, imgBtnLv,
            btnCX - BTN_EQUIP.W * 0.5,
            BTN_EQUIP.CY - BTN_EQUIP.H * 0.5,
            BTN_EQUIP.W, BTN_EQUIP.H,
            BTN_EQUIP.NP_T, BTN_EQUIP.NP_R, BTN_EQUIP.NP_B, BTN_EQUIP.NP_L)
        BF.finish(vg, _bfEq)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_EQUIP.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_EQUIP.TEXT_R, BTN_EQUIP.TEXT_G, BTN_EQUIP.TEXT_B, BTN_EQUIP.TEXT_A))
        nvgText(vg, btnCX, BTN_EQUIP.CY, "取下", nil)
    else
        -- 背包遗物：显示"洗练"+"装备/替换"双按钮
        local canReforge, _ = RelicSystem.canReforge(relic)
        local reforgeAlpha = canReforge and 255 or 120

        nvgGlobalAlpha(vg, progress * (reforgeAlpha / 255))
        local _bfRef = BF.begin(vg, "relic_detail_reforge", BTN_REFORGE.CX, BTN_REFORGE.CY, BTN_REFORGE.W, BTN_REFORGE.H)
        drawNineSlice(vg, imgBtnHuang,
            BTN_REFORGE.CX - BTN_REFORGE.W * 0.5,
            BTN_REFORGE.CY - BTN_REFORGE.H * 0.5,
            BTN_REFORGE.W, BTN_REFORGE.H,
            BTN_REFORGE.NP_T, BTN_REFORGE.NP_R, BTN_REFORGE.NP_B, BTN_REFORGE.NP_L)
        BF.finish(vg, _bfRef)
        nvgGlobalAlpha(vg, progress)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_REFORGE.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_REFORGE.TEXT_R, BTN_REFORGE.TEXT_G, BTN_REFORGE.TEXT_B, BTN_REFORGE.TEXT_A))
        nvgText(vg, BTN_REFORGE.CX, BTN_REFORGE.CY, "洗练", nil)

        -- "装备/替换"按钮 — 存在可替换目标时显示"替换"
        local replaceTarget = RelicSystem.findReplaceTarget(relic)
        local equipLabel = replaceTarget and "替换" or "装备"

        local _bfEq = BF.begin(vg, "relic_detail_equip", BTN_EQUIP.CX, BTN_EQUIP.CY, BTN_EQUIP.W, BTN_EQUIP.H)
        drawNineSlice(vg, imgBtnLv,
            BTN_EQUIP.CX - BTN_EQUIP.W * 0.5,
            BTN_EQUIP.CY - BTN_EQUIP.H * 0.5,
            BTN_EQUIP.W, BTN_EQUIP.H,
            BTN_EQUIP.NP_T, BTN_EQUIP.NP_R, BTN_EQUIP.NP_B, BTN_EQUIP.NP_L)
        BF.finish(vg, _bfEq)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, BTN_EQUIP.FONT)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(BTN_EQUIP.TEXT_R, BTN_EQUIP.TEXT_G, BTN_EQUIP.TEXT_B, BTN_EQUIP.TEXT_A))
        nvgText(vg, BTN_EQUIP.CX, BTN_EQUIP.CY, equipLabel, nil)
    end

    nvgRestore(vg)
end

-- ======================== 点击处理 ========================

--- 处理点击（返回 true 表示已消费）
function RelicDetailPanel.handleTap(tx, ty)
    if not state.visible then return false end
    if state.opening or state.closing then return true end  -- 动画中吞掉点击

    syncRelicFromStore()
    local relic = state.relic
    if not relic then return true end

    -- 点击锁定图标 → 切换锁定（锁定后无法参与一键/手动合成）
    if state.lockHotspot
       and hitTest(tx, ty, state.lockHotspot.cx, state.lockHotspot.cy,
                   state.lockHotspot.w, state.lockHotspot.h) then
        BF.trigger("relic_detail_lock")
        local willLock = not RelicSystem.isLocked(relic)
        RelicSystem.requestToggleLock(relic.id)
        if willLock then
            relic.locked = true
        else
            relic.locked = nil
        end
        print("[RelicDetailPanel] toggle lock relicId=" .. tostring(relic.id)
            .. " locked=" .. tostring(willLock))
        return true
    end

    if state.location == "grid" then
        -- grid 模式：只有居中的"取下"按钮
        local btnCX = BG.CX  -- 540
        if hitTest(tx, ty, btnCX, BTN_EQUIP.CY, BTN_EQUIP.W, BTN_EQUIP.H) then
            BF.trigger("relic_detail_equip")
            if onEquipCallback_ then
                onEquipCallback_(relic, state.location)
            end
            return true
        end
    else
        -- bag 模式："洗练"按钮
        if hitTest(tx, ty, BTN_REFORGE.CX, BTN_REFORGE.CY, BTN_REFORGE.W, BTN_REFORGE.H) then
            BF.trigger("relic_detail_reforge")
            local canReforge, reason = RelicSystem.canReforge(relic)
            if canReforge then
                if onReforgeCallback_ then
                    onReforgeCallback_(relic)
                end
            else
                print("[RelicDetailPanel] cannot reforge: " .. (reason or "unknown"))
            end
            return true
        end

        -- bag 模式："装备/替换"按钮
        if hitTest(tx, ty, BTN_EQUIP.CX, BTN_EQUIP.CY, BTN_EQUIP.W, BTN_EQUIP.H) then
            BF.trigger("relic_detail_equip")
            if onEquipCallback_ then
                local replaceTarget = RelicSystem.findReplaceTarget(relic)
                if replaceTarget then
                    onEquipCallback_(relic, "replace", replaceTarget)
                else
                    onEquipCallback_(relic, state.location)
                end
            end
            return true
        end
    end

    -- 点击面板外部关闭
    if not hitTest(tx, ty, BG.CX, BG.CY, BG.W, BG.H) then
        RelicDetailPanel.hide()
        return true
    end

    -- 点击面板内部（消费事件但不做特殊处理）
    return true
end

return RelicDetailPanel
