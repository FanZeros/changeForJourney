-- ============================================================================
-- SettingsPanel - 设置界面
-- 入口：玩家信息界面点击设置按钮
-- 坐标系: 设计分辨率 1080×2400，所有位置为中心点坐标
-- ============================================================================

local cjson = cjson
local DrawUtil = require("core.DrawUtil")
local RedeemCodePanel = require("ui.RedeemCodePanel")
local GameBGM = require("systems.GameBGM")
local I18n = require("core.I18n")

local BF              = require("systems.ButtonFeedback")
local DarkIcon = require("core.DarkIcon")  -- [暗黑化 P1-B3/B5] 矢量九宫格
local drawTextStroke    = DrawUtil.drawTextStroke
local drawImageCentered = DrawUtil.drawImageCentered
local drawNineSlice     = DrawUtil.drawNineSlice
local hitTest           = DrawUtil.hitTest

local SettingsPanel = {}

-- ======================== 状态 ========================

local state = {
    open      = false,
    animTime  = 0,
    closing   = false,
    closeTime = 0,
    -- 音量 0~1
    bgmVolume = 0.8,
    sfxVolume = 0.8,
    -- 音效开关（战斗页 HUD 快捷按钮与设置面板共用；仅静音 SFX，不影响 BGM）
    muted = false,
    showDamageNumbers = true,
    showEffects = true,
    -- 滑块拖拽
    draggingSlider = nil,  -- nil / "bgm" / "sfx"
}

-- ======================== 图片资源句柄 ========================

local img = {
    bg      = -1,   -- UI_TY_EJQRK.png 九宫格弹窗背景
    codeBtn = -1,   -- UI_AN_LV.png 兑换码按钮
}

-- ======================== 布局常量 ========================

-- 动画
local ANIM_OPEN_DUR  = 0.25
local ANIM_CLOSE_DUR = 0.15

-- 1. 全屏黑色遮罩
local MASK_ALPHA = 128  -- 50%

-- 2. 弹窗背景（九宫格）
local BG = {
    CX = 540, CY = 1178, W = 950, H = 785,
    IT = 150, IL = 60, IR = 60, IB = 100,
}

-- 3. 标题 "设置"
local TTL = {
    X = 540, Y = 878, FONT = 60,
    FR = 255, FG = 255, FB = 255,
    SW = 6, SR = 0x59, SG = 0x32, SB = 0x19,
}

-- 4. 设置条目1 背景框 (背景音乐)
-- A=0：嵌入玩家信息页时不再画条目黑底
local ITEM1_BG = {
    CX = 540, CY = 1040, W = 800, H = 90, R = 16,
    A = 0,
}

-- 5. 设置条目文本1 "背景音乐"
local ITEM1_TEXT = {
    X = 177, Y = 1085, FONT = 42,
    FR = 255, FG = 255, FB = 255,
    SW = 6, SR = 0x44, SG = 0x2d, SB = 0x19,
}

-- 6. 滑块背景条（嵌入页用浅描边，不再铺黑底）
local SLIDER = {
    CX = 651, W = 504, H = 24, R = 12,
    A = 0,
    -- 7. 滑块圆形旋钮
    KNOB_SIZE = 36,  -- 直径
    KNOB_SW = 6,
    KNOB_SR = 0x44, KNOB_SG = 0x2d, KNOB_SB = 0x19,
}

-- 8. 设置条目2 (音效) — 间距25px
-- Item1 中心 Y=1085, H=90 → 底边 1130
-- 间距 25px → Item2 顶边 1155 → H=90 → 中心 1200
local ITEM2_CY = 1150
local ITEM3_CY = 1260
local ITEM4_CY = 1370
local ITEM5_CY = 1480

local TOGGLE = {
    CX = 795, W = 150, H = 56, R = 28,
    KNOB_SIZE = 46,
    ON_R = 0x6c, ON_G = 0xd4, ON_B = 0x6c,
    OFF_R = 0x77, OFF_G = 0x66, OFF_B = 0x55,
    TEXT_X = 795, TEXT_FONT = 28,
}

-- 9. 兑换码按钮
local CODE_BTN = {
    CX = 540, CY = 1590, W = 410, H = 100,
}

-- 10. 兑换码文本
local CODE_TXT = {
    X = 540, Y = 1590, FONT = 40,
    A = 179,  -- 纯黑 70%
}

local LANG_CHIP_W, LANG_CHIP_H, LANG_CHIP_GAP = 88, 44, 6

-- ======================== 本地设置持久化 ========================

local SETTINGS_SAVE_FILE = "settings_volume.json"

--- 保存设置到本地文件
local function saveSettings()
    local file = File(SETTINGS_SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        local ok, str = pcall(cjson.encode, {
            bgmVolume = state.bgmVolume,
            sfxVolume = state.sfxVolume,
            muted = state.muted == true,
            showDamageNumbers = state.showDamageNumbers ~= false,
            showEffects = state.showEffects ~= false,
            language = I18n.get(),
        })
        if ok then
            file:WriteString(str)
        end
        file:Close()
    end
end

--- 从本地文件加载设置
local function loadSettings()
    if not fileSystem:FileExists(SETTINGS_SAVE_FILE) then return end
    local file = File(SETTINGS_SAVE_FILE, FILE_READ)
    if not file:IsOpen() then return end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    if ok and data then
        if type(data.bgmVolume) == "number" then
            state.bgmVolume = math.max(0, math.min(1, data.bgmVolume))
        end
        if type(data.sfxVolume) == "number" then
            state.sfxVolume = math.max(0, math.min(1, data.sfxVolume))
        end
        if type(data.muted) == "boolean" then
            state.muted = data.muted
        end
        if type(data.showDamageNumbers) == "boolean" then
            state.showDamageNumbers = data.showDamageNumbers
        end
        if type(data.showEffects) == "boolean" then
            state.showEffects = data.showEffects
        end
        if type(data.language) == "string" then
            I18n.set(data.language)
        end
        print("[SettingsPanel] 已加载本地设置: BGM=" ..
            string.format("%.0f%%", state.bgmVolume * 100) ..
            " SFX=" .. string.format("%.0f%%", state.sfxVolume * 100) ..
            " 伤害数字=" .. tostring(state.showDamageNumbers ~= false) ..
            " 特效=" .. tostring(state.showEffects ~= false))
    end
end

--- 将 BGM 音量同步到 GameBGM 系统
local function applyBgmVolume(vol)
    GameBGM.setMasterGain(vol)
end

--- 将 SFX 音量同步到引擎音频子系统（"Effect" 类型通道）
local function applySfxVolume(vol)
    audio:SetMasterGain("Effect", vol)
end

--- 应用当前音频状态到引擎（muted 仅静音音效 SFX，BGM 不受影响）
local function applyVolumes()
    if state.muted then
        audio:SetMasterGain("Effect", 0)
    else
        applyBgmVolume(state.bgmVolume)
        applySfxVolume(state.sfxVolume)
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 音效开关状态（战斗页 HUD 快捷按钮使用；与设置面板共用同一状态）
---@return boolean  true = 音效开启
function SettingsPanel.isSoundOn()
    return not (state.muted == true)
end

--- 设置音效开关（仅静音 SFX，BGM 不受影响；持久化到本地设置）
---@param on boolean
function SettingsPanel.setSoundOn(on)
    local newMuted = not on
    if state.muted == newMuted then return end
    state.muted = newMuted
    applyVolumes()
    saveSettings()
    print("[SettingsPanel] 音效开关: " .. (on and "开" or "关") .. "（BGM 不受影响）")
end

--- 初始化（加载图片资源，仅调用一次）
function SettingsPanel.init(vg)
    img.bg      = nvgCreateImage(vg, "image/界面底板/通用面板/UI_TY_EJQRK.png", 0)
    img.codeBtn = nvgCreateImage(vg, "image/按钮/UI_AN_LV.png", 0)

    if img.bg < 0 then print("[SettingsPanel] WARN: UI_TY_EJQRK.png load failed") end
    if img.codeBtn < 0 then print("[SettingsPanel] WARN: UI_AN_LV.png load failed") end

    RedeemCodePanel.init(vg)

    -- 加载本地保存的设置并应用（含静音标志）
    loadSettings()
    applyVolumes()

    print("[SettingsPanel] init OK")
end

--- 打开面板
function SettingsPanel.open()
    if state.open then return end
    state.open = true
    state.closing = false
    state.animTime = time.elapsedTime
    state.draggingSlider = nil
    print("[SettingsPanel] 打开")
end

--- 关闭面板
function SettingsPanel.close()
    if not state.open or state.closing then return end
    state.closing = true
    state.closeTime = time.elapsedTime
    state.draggingSlider = nil
    print("[SettingsPanel] 关闭")
end

--- 是否打开
function SettingsPanel.isOpen()
    return state.open
end

function SettingsPanel.isDamageNumbersEnabled()
    return state.showDamageNumbers ~= false
end

function SettingsPanel.isEffectsEnabled()
    return state.showEffects ~= false
end

-- ======================== 滑块交互辅助 ========================

--- 根据 X 坐标计算音量值 (0~1)
local function xToVolume(dx)
    local sliderLeft = SLIDER.CX - SLIDER.W * 0.5
    local sliderRight = SLIDER.CX + SLIDER.W * 0.5
    local v = (dx - sliderLeft) / SLIDER.W
    return math.max(0, math.min(1, v))
end

--- 判断点击是否在某条滑块区域内（含旋钮范围）
local function hitSlider(dx, dy, itemCY)
    -- 扩大检测区域：Y 方向取 item 高度 90，X 方向包含旋钮半径
    local halfKnob = SLIDER.KNOB_SIZE * 0.5
    local sliderLeft = SLIDER.CX - SLIDER.W * 0.5 - halfKnob
    local sliderRight = SLIDER.CX + SLIDER.W * 0.5 + halfKnob
    return dx >= sliderLeft and dx <= sliderRight
       and dy >= itemCY - 45 and dy <= itemCY + 45
end

--- 判断点击是否在某个开关条目内
local function hitToggle(dx, dy, itemCY)
    return hitTest(dx, dy, ITEM1_BG.CX, itemCY, ITEM1_BG.W, ITEM1_BG.H)
end

local function toggleDamageNumbers()
    state.showDamageNumbers = not (state.showDamageNumbers ~= false)
    saveSettings()
    print("[SettingsPanel] 伤害数字显示: " .. tostring(state.showDamageNumbers ~= false))
end

local function toggleEffects()
    state.showEffects = not (state.showEffects ~= false)
    saveSettings()
    print("[SettingsPanel] 特效显示: " .. tostring(state.showEffects ~= false))
end

---@param itemCY number
---@return table[]
local function langChipRects(itemCY)
    local n = #I18n.LANGS
    local total = n * LANG_CHIP_W + (n - 1) * LANG_CHIP_GAP
    local right = ITEM1_BG.CX + ITEM1_BG.W * 0.5 - 12
    local x0 = right - total
    local rects = {}
    for i, lang in ipairs(I18n.LANGS) do
        rects[i] = {
            x = x0 + (i - 1) * (LANG_CHIP_W + LANG_CHIP_GAP),
            y = itemCY - LANG_CHIP_H * 0.5,
            w = LANG_CHIP_W,
            h = LANG_CHIP_H,
            id = lang.id,
            label = lang.label,
        }
    end
    return rects
end

---@param dx number
---@param dy number
---@param itemCY number
---@return boolean
local function hitLanguageChips(dx, dy, itemCY)
    for _, r in ipairs(langChipRects(itemCY)) do
        if dx >= r.x and dx <= r.x + r.w and dy >= r.y and dy <= r.y + r.h then
            if I18n.set(r.id) then
                saveSettings()
                print("[SettingsPanel] language=" .. r.id)
            end
            return true
        end
    end
    return false
end

local function drawLanguageItem(vg, itemCY)
    drawTextStroke(vg, ITEM1_TEXT.X, itemCY, I18n.t("language"),
        ITEM1_TEXT.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        ITEM1_TEXT.FR, ITEM1_TEXT.FG, ITEM1_TEXT.FB, ITEM1_TEXT.SW,
        { strokeColor = { ITEM1_TEXT.SR, ITEM1_TEXT.SG, ITEM1_TEXT.SB } })
    local cur = I18n.get()
    for _, r in ipairs(langChipRects(itemCY)) do
        local on = r.id == cur
        nvgBeginPath(vg)
        nvgRoundedRect(vg, r.x, r.y, r.w, r.h, 10)
        if on then
            nvgFillColor(vg, nvgRGBA(0xC4, 0xA0, 0x5A, 230))
        else
            nvgFillColor(vg, nvgRGBA(0x44, 0x36, 0x28, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, on and 255 or 140))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if on then
            nvgFillColor(vg, nvgRGBA(0x1a, 0x12, 0x0a, 255))
        else
            nvgFillColor(vg, nvgRGBA(244, 237, 224, 230))
        end
        nvgText(vg, r.x + r.w * 0.5, r.y + r.h * 0.5, r.label, nil)
    end
end

--- 点击处理
function SettingsPanel.handleInput(dx, dy)
    if not state.open or state.closing then return true end

    -- RedeemCodePanel 优先拦截（最顶层）
    if RedeemCodePanel.isOpen() then
        RedeemCodePanel.handleInput(dx, dy)
        return true
    end

    -- 同帧保护：防止 open() 同帧的点击事件立即关闭弹窗
    if time.elapsedTime - state.animTime < 0.05 then return true end

    -- 点击弹窗外部 → 关闭
    if not hitTest(dx, dy, BG.CX, BG.CY, BG.W, BG.H) then
        SettingsPanel.close()
        return true
    end

    -- 滑块1 点击（背景音乐）→ 立即跳到该位置
    if hitSlider(dx, dy, ITEM1_BG.CY) then
        state.bgmVolume = xToVolume(dx)
        state.draggingSlider = "bgm"
        applyVolumes()
        saveSettings()
        print("[SettingsPanel] BGM 音量: " .. string.format("%.0f%%", state.bgmVolume * 100))
        return true
    end

    -- 滑块2 点击（音效）
    if hitSlider(dx, dy, ITEM2_CY) then
        state.sfxVolume = xToVolume(dx)
        state.draggingSlider = "sfx"
        applyVolumes()
        saveSettings()
        print("[SettingsPanel] SFX 音量: " .. string.format("%.0f%%", state.sfxVolume * 100))
        return true
    end

    -- 开关3 点击（伤害数字显示）
    if hitToggle(dx, dy, ITEM3_CY) then
        toggleDamageNumbers()
        return true
    end

    -- 开关4 点击（特效显示）
    if hitToggle(dx, dy, ITEM4_CY) then
        toggleEffects()
        return true
    end

    if hitLanguageChips(dx, dy, ITEM5_CY) then
        return true
    end

    -- 兑换码按钮
    if hitTest(dx, dy, CODE_BTN.CX, CODE_BTN.CY, CODE_BTN.W, CODE_BTN.H) then
        BF.trigger("set_code")
        print("[SettingsPanel] 兑换码按钮被点击 → 打开兑换码面板")
        RedeemCodePanel.open()
        return true
    end

    -- 弹窗内部消费事件
    return true
end

--- 拖拽开始
function SettingsPanel.handleDragBegin(dx, dy)
    if not state.open or state.closing then return false end

    -- 检查是否在滑块1区域
    if hitSlider(dx, dy, ITEM1_BG.CY) then
        state.draggingSlider = "bgm"
        state.bgmVolume = xToVolume(dx)
        applyVolumes()
        return true
    end

    -- 检查是否在滑块2区域
    if hitSlider(dx, dy, ITEM2_CY) then
        state.draggingSlider = "sfx"
        state.sfxVolume = xToVolume(dx)
        applyVolumes()
        return true
    end

    return false
end

--- 拖拽移动
function SettingsPanel.handleDragMove(dx, dy)
    if not state.draggingSlider then return false end

    if state.draggingSlider == "bgm" then
        state.bgmVolume = xToVolume(dx)
        applyVolumes()
    elseif state.draggingSlider == "sfx" then
        state.sfxVolume = xToVolume(dx)
        applyVolumes()
    end
    return true
end

--- 拖拽结束
function SettingsPanel.handleDragEnd()
    if not state.draggingSlider then return false end
    saveSettings()
    state.draggingSlider = nil
    return true
end

--- 每帧更新（转发给 RedeemCodePanel）
function SettingsPanel.update(dt)
    if not state.open then return end
    RedeemCodePanel.update(dt)
end

-- ======================== 绘制辅助 ========================

--- 绘制单个设置条目（背景 + 文本 + 滑块）
---@param vg any
---@param itemCY number 条目中心 Y
---@param label string 条目标签
---@param volume number 当前音量 0~1
local function drawSettingsItem(vg, itemCY, label, volume)
    -- 4. 背景框（A=0 时不画黑底）
    if ITEM1_BG.A > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            ITEM1_BG.CX - ITEM1_BG.W * 0.5, itemCY - ITEM1_BG.H * 0.5,
            ITEM1_BG.W, ITEM1_BG.H, ITEM1_BG.R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, ITEM1_BG.A))
        nvgFill(vg)
    end

    -- 5. 条目文本（左对齐）
    drawTextStroke(vg, ITEM1_TEXT.X, itemCY, label,
        ITEM1_TEXT.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        ITEM1_TEXT.FR, ITEM1_TEXT.FG, ITEM1_TEXT.FB, ITEM1_TEXT.SW,
        { strokeColor = { ITEM1_TEXT.SR, ITEM1_TEXT.SG, ITEM1_TEXT.SB } })

    -- 6. 滑块背景条（浅描边轨道，无黑底）
    local sliderLeft = SLIDER.CX - SLIDER.W * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg,
        sliderLeft, itemCY - SLIDER.H * 0.5,
        SLIDER.W, SLIDER.H, SLIDER.R)
    nvgStrokeColor(vg, nvgRGBA(0x8d, 0x5f, 0x41, 180))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 滑块已填充部分（白色 30% 透明度，视觉反馈）
    local fillW = SLIDER.W * volume
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            sliderLeft, itemCY - SLIDER.H * 0.5,
            fillW, SLIDER.H, SLIDER.R)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 77))  -- 30%
        nvgFill(vg)
    end

    -- 7. 滑块旋钮（圆形，白色，描边）
    local knobX = sliderLeft + SLIDER.W * volume
    local knobR = SLIDER.KNOB_SIZE * 0.5

    nvgBeginPath(vg)
    nvgCircle(vg, knobX, itemCY, knobR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgFill(vg)

    -- 旋钮描边
    nvgStrokeColor(vg, nvgRGBA(SLIDER.KNOB_SR, SLIDER.KNOB_SG, SLIDER.KNOB_SB, 255))
    nvgStrokeWidth(vg, SLIDER.KNOB_SW)
    nvgStroke(vg)
end

--- 绘制单个开关条目（背景 + 文本 + 开关）
---@param vg any
---@param itemCY number 条目中心 Y
---@param label string 条目标签
---@param enabled boolean 是否开启
local function drawToggleItem(vg, itemCY, label, enabled)
    if ITEM1_BG.A > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg,
            ITEM1_BG.CX - ITEM1_BG.W * 0.5, itemCY - ITEM1_BG.H * 0.5,
            ITEM1_BG.W, ITEM1_BG.H, ITEM1_BG.R)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, ITEM1_BG.A))
        nvgFill(vg)
    end

    drawTextStroke(vg, ITEM1_TEXT.X, itemCY, label,
        ITEM1_TEXT.FONT, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        ITEM1_TEXT.FR, ITEM1_TEXT.FG, ITEM1_TEXT.FB, ITEM1_TEXT.SW,
        { strokeColor = { ITEM1_TEXT.SR, ITEM1_TEXT.SG, ITEM1_TEXT.SB } })

    local x = TOGGLE.CX - TOGGLE.W * 0.5
    local y = itemCY - TOGGLE.H * 0.5
    local r = enabled and TOGGLE.ON_R or TOGGLE.OFF_R
    local g = enabled and TOGGLE.ON_G or TOGGLE.OFF_G
    local b = enabled and TOGGLE.ON_B or TOGGLE.OFF_B

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, TOGGLE.W, TOGGLE.H, TOGGLE.R)
    nvgFillColor(vg, nvgRGBA(r, g, b, 230))
    nvgFill(vg)

    local knobR = TOGGLE.KNOB_SIZE * 0.5
    local knobX = enabled and (x + TOGGLE.W - TOGGLE.H * 0.5) or (x + TOGGLE.H * 0.5)
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, itemCY, knobR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(SLIDER.KNOB_SR, SLIDER.KNOB_SG, SLIDER.KNOB_SB, 255))
    nvgStrokeWidth(vg, 4)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TOGGLE.TEXT_FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgText(vg, TOGGLE.TEXT_X, itemCY, enabled and I18n.t("on") or I18n.t("off"), nil)
end

-- ============================================================================
-- Draw
-- ============================================================================

function SettingsPanel.draw(vg)
    if not state.open then return end

    -- 动画进度
    local animProgress = 1.0
    if state.closing then
        local elapsed = time.elapsedTime - state.closeTime
        animProgress = 1.0 - math.min(elapsed / ANIM_CLOSE_DUR, 1.0)
        if animProgress <= 0 then
            state.open = false
            state.closing = false
            return
        end
    else
        local elapsed = time.elapsedTime - state.animTime
        animProgress = math.min(elapsed / ANIM_OPEN_DUR, 1.0)
        animProgress = DrawUtil.easeOutBack(animProgress)
    end

    nvgSave(vg)

    -- ── 1. 全屏黑色遮罩 50% ──
    local maskAlpha = math.floor(MASK_ALPHA * (state.closing
        and (1.0 - math.min((time.elapsedTime - state.closeTime) / ANIM_CLOSE_DUR, 1.0))
        or math.min((time.elapsedTime - state.animTime) / ANIM_OPEN_DUR, 1.0)))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, 1080, 2400)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, maskAlpha))
    nvgFill(vg)

    -- 弹窗缩放动画
    nvgTranslate(vg, BG.CX, BG.CY)
    nvgScale(vg, animProgress, animProgress)
    nvgTranslate(vg, -BG.CX, -BG.CY)

    -- ── 2. 弹窗背景框（九宫格）──
    DarkIcon.drawNine(vg, "panel", BG.CX - BG.W * 0.5, BG.CY - BG.H * 0.5, BG.W, BG.H, { titleH = BG.IT })

    -- ── 3. 标题 "设置" ──
    drawTextStroke(vg, TTL.X, TTL.Y, I18n.t("settings"),
        TTL.FONT, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        TTL.FR, TTL.FG, TTL.FB, TTL.SW,
        { strokeColor = { TTL.SR, TTL.SG, TTL.SB } })

    -- ── 4~7. 设置条目1: 背景音乐 ──
    drawSettingsItem(vg, ITEM1_BG.CY, I18n.t("bgm"), state.bgmVolume)

    -- ── 8. 设置条目2: 音效 ──
    drawSettingsItem(vg, ITEM2_CY, I18n.t("sfx"), state.sfxVolume)

    -- ── 8.1 设置条目3: 伤害数字显示 ──
    drawToggleItem(vg, ITEM3_CY, I18n.t("damage_numbers"), state.showDamageNumbers ~= false)

    -- ── 8.2 设置条目4: 特效显示 ──
    drawToggleItem(vg, ITEM4_CY, I18n.t("show_effects"), state.showEffects ~= false)

    -- ── 8.3 语言 ──
    drawLanguageItem(vg, ITEM5_CY)

    -- ── 9. 兑换码按钮 ──
    local _bf1 = BF.begin(vg, "set_code", CODE_BTN.CX, CODE_BTN.CY, CODE_BTN.W, CODE_BTN.H)
    if img.codeBtn >= 0 then
        drawImageCentered(vg, img.codeBtn, CODE_BTN.CX, CODE_BTN.CY, CODE_BTN.W, CODE_BTN.H, 1.0)
    end

    -- ── 10. "兑换码" 文本 ──
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, CODE_TXT.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(244, 237, 224, CODE_TXT.A))
    nvgText(vg, CODE_TXT.X, CODE_TXT.Y, I18n.t("redeem_code"), nil)
    BF.finish(vg, _bf1)

    nvgRestore(vg)

    -- ── RedeemCodePanel 叠加绘制 ──
    RedeemCodePanel.draw(vg)
end

--- 嵌入玩家信息页：设置项 Y 偏移（相对独立设置弹窗）
--- 独立页 ITEM1_CY=1040，经验条在 699，下移到约 820 起排
local EMBED_Y_OFFSET = -220

--- 嵌入绘制：无遮罩、无独立弹窗，仅绘制设置条目 + 兑换码
---@param vg any
---@param yOffset number|nil
function SettingsPanel.drawEmbedded(vg, yOffset)
    local oy = yOffset or EMBED_Y_OFFSET
    nvgSave(vg)
    nvgTranslate(vg, 0, oy)
    drawSettingsItem(vg, ITEM1_BG.CY, I18n.t("bgm"), state.bgmVolume)
    drawSettingsItem(vg, ITEM2_CY, I18n.t("sfx"), state.sfxVolume)
    drawToggleItem(vg, ITEM3_CY, I18n.t("damage_numbers"), state.showDamageNumbers ~= false)
    drawToggleItem(vg, ITEM4_CY, I18n.t("show_effects"), state.showEffects ~= false)
    drawLanguageItem(vg, ITEM5_CY)
    local _bf1 = BF.begin(vg, "set_code", CODE_BTN.CX, CODE_BTN.CY + oy, CODE_BTN.W, CODE_BTN.H)
    if img.codeBtn >= 0 then
        drawImageCentered(vg, img.codeBtn, CODE_BTN.CX, CODE_BTN.CY, CODE_BTN.W, CODE_BTN.H, 1.0)
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, CODE_TXT.FONT)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(244, 237, 224, 230))
    nvgText(vg, CODE_TXT.X, CODE_TXT.Y, I18n.t("redeem_code"), nil)
    BF.finish(vg, _bf1)
    nvgRestore(vg)
    RedeemCodePanel.draw(vg)
end

--- 嵌入点击（坐标已是设计分辨率，内部按 yOffset 对齐）
---@param dx number
---@param dy number
---@param yOffset number|nil
---@return boolean consumed
function SettingsPanel.handleEmbeddedInput(dx, dy, yOffset)
    if RedeemCodePanel.isOpen() then
        RedeemCodePanel.handleInput(dx, dy)
        return true
    end
    local oy = yOffset or EMBED_Y_OFFSET
    local ly = dy - oy
    if hitSlider(dx, ly, ITEM1_BG.CY) then
        state.bgmVolume = xToVolume(dx)
        state.draggingSlider = "bgm"
        applyBgmVolume(state.bgmVolume)
        saveSettings()
        return true
    end
    if hitSlider(dx, ly, ITEM2_CY) then
        state.sfxVolume = xToVolume(dx)
        state.draggingSlider = "sfx"
        applySfxVolume(state.sfxVolume)
        saveSettings()
        return true
    end
    if hitToggle(dx, ly, ITEM3_CY) then
        toggleDamageNumbers()
        return true
    end
    if hitToggle(dx, ly, ITEM4_CY) then
        toggleEffects()
        return true
    end
    if hitLanguageChips(dx, ly, ITEM5_CY) then
        return true
    end
    if hitTest(dx, ly, CODE_BTN.CX, CODE_BTN.CY, CODE_BTN.W, CODE_BTN.H) then
        BF.trigger("set_code")
        RedeemCodePanel.open()
        return true
    end
    return false
end

---@param dx number
---@param dy number
---@param yOffset number|nil
---@return boolean
function SettingsPanel.handleEmbeddedDragBegin(dx, dy, yOffset)
    if RedeemCodePanel.isOpen() then return true end
    local oy = yOffset or EMBED_Y_OFFSET
    local ly = dy - oy
    if hitSlider(dx, ly, ITEM1_BG.CY) then
        state.draggingSlider = "bgm"
        state.bgmVolume = xToVolume(dx)
        applyBgmVolume(state.bgmVolume)
        return true
    end
    if hitSlider(dx, ly, ITEM2_CY) then
        state.draggingSlider = "sfx"
        state.sfxVolume = xToVolume(dx)
        applySfxVolume(state.sfxVolume)
        return true
    end
    return false
end

function SettingsPanel.getEmbedYOffset()
    return EMBED_Y_OFFSET
end

--- 标题页切语言后落盘（不改音量）
function SettingsPanel.persistLanguage()
    saveSettings()
end

return SettingsPanel
