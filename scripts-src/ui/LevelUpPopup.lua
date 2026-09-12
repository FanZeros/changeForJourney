-- ============================================================================
-- LevelUpPopup - 冒险等级提升全屏弹窗
-- ============================================================================
--
-- 【使用说明】
--   local LevelUpPopup = require("ui.LevelUpPopup")
--   LevelUpPopup.init(vg)                      -- 初始化（仅一次）
--   LevelUpPopup.show(newLevel, unlocks)        -- 展示弹窗
--   LevelUpPopup.update(dt)                     -- 每帧更新
--   LevelUpPopup.draw(vg)                       -- NanoVGRender 中绘制
--   LevelUpPopup.handleInput(dx, dy)            -- 点击处理
--   LevelUpPopup.isOpen()                       -- 是否打开
--
-- 【布局设计】（设计分辨率 1080×2400）
--   1. Spine 全屏背景 UI_SPINE_DJTS（播完停留最后一帧）
--   2. "冒险等级提升" 标题 (X540 Y575, size 70)
--   3. 等级数字 (X540 Y723, size 120)
--   4. 文本背景框 UI_JJC_BTBJ (X540 Y1036, 660×60)
--   5. "天赋点" 文本 (X540 Y1035, size 70)
--   6. "+1" 文本 (X540 Y1122, size 60)
--   7. 分割线 (X540 Y1200, 990×4)
--   8. 解锁内容列表（动态）
--   9. "-点击继续-" (X540 Y2040, size 60)
-- ============================================================================

---@diagnostic disable: undefined-global

local ExpTable = require("config.ExpTable")

local LevelUpPopup = {}

-- ======================== 设计常量 ========================

local DESIGN_W = 1080
local DESIGN_H = 2400

-- Spine 资源
local SPINE_JSON = "image/spine/UI_SPINE_DJTS.json"
local SPINE_ANIM = "1"

-- Spine 骨架原始数据（从 JSON skeleton 字段）
local SPINE_DATA_X = -540
local SPINE_DATA_Y = -1200
local SPINE_DATA_W = 1080
local SPINE_DATA_H = 2400

-- 标题 "冒险等级提升"
local TITLE_X, TITLE_Y = 540, 575
local TITLE_SIZE = 70
-- 标题描边
local TITLE_STROKE = 6
local TITLE_STROKE_SAMPLES = 16

-- 等级数字
local LEVEL_X, LEVEL_Y = 540, 723
local LEVEL_SIZE = 120
local LEVEL_STROKE = 8
local LEVEL_STROKE_SAMPLES = 16

-- 文本背景框
local TEXT_BG_X, TEXT_BG_Y = 540, 1036
local TEXT_BG_W, TEXT_BG_H = 660, 60

-- "天赋点" 文本
local TALENT_X, TALENT_Y = 540, 1035
local TALENT_SIZE = 70

-- "+1" 文本
local PLUS_X, PLUS_Y = 540, 1122
local PLUS_SIZE = 60

-- 分割线
local DIVIDER_X, DIVIDER_Y = 540, 1200
local DIVIDER_W, DIVIDER_H = 990, 4

-- 解锁内容
local UNLOCK_START_Y = 1312    -- 第一个解锁项的中心 Y
local UNLOCK_ITEM_H  = 80     -- 每项高度
local UNLOCK_ITEM_GAP = 23    -- 项间距
local UNLOCK_BG_W, UNLOCK_BG_H = 732, 80
local UNLOCK_BG_RADIUS = 40
local UNLOCK_BG_ALPHA = 25     -- 白色 10% 不透明度 = 255 * 0.1 ≈ 25

-- 解锁文本 "解锁" — X 右居中 473
local UNLOCK_TEXT_X = 473
local UNLOCK_TEXT_SIZE = 40

-- 箭头图片
local ARROW_X = 540
local ARROW_W, ARROW_H = 89, 82

-- "已开放" 文本
local OPENED_X = 666
local OPENED_SIZE = 40

-- "-点击继续-"
local HINT_X, HINT_Y = 540, 2040
local HINT_SIZE = 60

-- ======================== 动画常量 ========================

local ENTER_DELAY    = 0.3   -- 入场延迟（等 Spine 背景先渐显）
local ENTER_DURATION = 0.4   -- 内容从左侧滑入时长
local EXIT_DURATION  = 0.3   -- 出场动画时长
local AUTO_CLOSE_SEC = 5     -- idle 阶段自动关闭倒计时（秒）

-- ======================== 颜色常量 ========================

local COLOR_WHITE     = { 255, 255, 255, 255 }
local COLOR_STROKE_BK = { 0, 0, 0, 255 }
local COLOR_YELLOW    = { 0xff, 0xeb, 0x65, 255 }   -- #ffeb65
local COLOR_LV_STROKE = { 0x3d, 0x32, 0x24, 255 }   -- #3d3224
local COLOR_GREEN     = { 0x8d, 0xff, 0x88, 255 }   -- #8dff88
local COLOR_DIVIDER   = { 0xa1, 0x81, 0x58, 255 }   -- #a18158

-- ======================== 缓动函数 ========================

--- ease-out cubic: 快速减速到位
local function easeOutCubic(t)
    local t1 = t - 1
    return t1 * t1 * t1 + 1
end

--- ease-in cubic: 缓慢加速离开
local function easeInCubic(t)
    return t * t * t
end

-- ======================== 状态 ========================

local state = {
    open       = false,
    newLevel   = 1,
    unlocks    = nil,     -- { { unlockName = "教堂" }, ... } 或 nil
    -- Spine
    spineInst  = nil,
    spineLoaded = false,
    spineFinished = false,  -- 动画是否已播完
    spineLastTime = 0,
    -- 图片
    imgTextBg  = -1,      -- UI_JJC_BTBJ.png
    imgArrow   = -1,      -- UI_HSJT.png
    -- 缓存
    cachedVg   = nil,
    -- 闪烁效果
    hintTimer  = 0,
    -- 动画
    animPhase  = nil,      -- "enter" | "idle" | "exit"
    animTimer  = 0,
    -- 自动关闭倒计时
    autoCloseTimer = 0,
}

-- ======================== 工具函数 ========================

--- 绘制描边文本（16 点圆形采样描边 + 填充）
---@param vg any
---@param x number 文本 X
---@param y number 文本 Y
---@param text string
---@param fontSize number
---@param fillColor table {r,g,b,a}
---@param strokeColor table {r,g,b,a}
---@param strokeWidth number
local function drawStrokedText(vg, x, y, text, fontSize, fillColor, strokeColor, strokeWidth)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 描边层
    if strokeWidth > 0 then
        nvgFillColor(vg, nvgRGBA(strokeColor[1], strokeColor[2], strokeColor[3], strokeColor[4]))
        local step = math.pi * 2 / TITLE_STROKE_SAMPLES
        for i = 0, TITLE_STROKE_SAMPLES - 1 do
            local angle = i * step
            nvgText(vg, x + math.cos(angle) * strokeWidth, y + math.sin(angle) * strokeWidth, text, nil)
        end
    end

    -- 填充层
    nvgFillColor(vg, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4]))
    nvgText(vg, x, y, text, nil)
end

--- 绘制图片居中
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 then return end
    local ix = cx - w * 0.5
    local iy = cy - h * 0.5
    local paint = nvgImagePattern(vg, ix, iy, w, h, 0, img, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, ix, iy, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- ======================== Spine 管理 ========================

local function ensureSpineLoaded(vg)
    if state.spineLoaded and state.spineInst then return true end
    if not vg then return false end

    state.spineInst = nvgSpineCreate(vg)
    if not state.spineInst then
        print("[LevelUpPopup] nvgSpineCreate failed")
        return false
    end

    if not state.spineInst:Load(SPINE_JSON) then
        print("[LevelUpPopup] Failed to load: " .. SPINE_JSON)
        state.spineInst = nil
        return false
    end

    -- 使用 normal 混合模式（关闭预乘 Alpha）
    state.spineInst:SetPremultipliedAlpha(false)
    state.spineInst:SetSpeed(1.0)

    -- 动画完成回调：标记停止更新（停留最后一帧）
    state.spineInst:SetCompleteListener(function(track, anim)
        state.spineFinished = true
        print("[LevelUpPopup] Spine animation complete, paused on last frame")
    end)

    state.spineLoaded = true
    print("[LevelUpPopup] Spine loaded OK")
    return true
end

-- ======================== Public API ========================

--- 预加载 Spine 资源（在 LoadingScreen.init 中调用，提前解析 JSON/atlas + 上传 GPU 纹理）
---@param vg any NanoVG 上下文
function LevelUpPopup.preload(vg)
    if state.spineLoaded then return end
    if not vg then return end
    ensureSpineLoaded(vg)
end

--- 初始化（加载图片资源，仅调用一次）
---@param vg any NanoVG 上下文
function LevelUpPopup.init(vg)
    state.cachedVg = vg
    state.imgTextBg = nvgCreateImage(vg, "image/UI_JJC_BTBJ.png", 0)
    state.imgArrow  = nvgCreateImage(vg, "image/UI_HSJT.png", 0)
    if state.imgTextBg < 0 then print("[LevelUpPopup] WARN: UI_JJC_BTBJ.png load failed") end
    if state.imgArrow  < 0 then print("[LevelUpPopup] WARN: UI_HSJT.png load failed") end
end

--- 展示等级提升弹窗
---@param newLevel number 新等级
---@param unlocks table[]|nil 解锁内容列表（来自 ExpTable.getLevelUnlocks）
function LevelUpPopup.show(newLevel, unlocks)
    require("systems.GameSFX").play("level_up")
    state.newLevel = newLevel
    state.unlocks = unlocks
    state.open = true
    state.spineFinished = false
    state.hintTimer = 0
    state.spineLastTime = time.elapsedTime

    -- 入场动画
    state.animPhase = "enter"
    state.animTimer = 0
    state.autoCloseTimer = AUTO_CLOSE_SEC

    -- 启动 Spine 动画
    if state.spineLoaded and state.spineInst then
        state.spineInst:SetAnimation(0, SPINE_ANIM, false)
        state.spineFinished = false
    end

    print("[LevelUpPopup] show: level=" .. newLevel
        .. " unlocks=" .. (unlocks and #unlocks or 0))
end

--- 关闭弹窗（内部调用，动画结束后执行）
local function doClose()
    state.open = false
    state.animPhase = nil
    if state.spineInst then
        state.spineInst:ClearTracks()
    end
    print("[LevelUpPopup] closed")
end

--- 是否打开
---@return boolean
function LevelUpPopup.isOpen()
    return state.open
end

--- 每帧更新
---@param dt number
function LevelUpPopup.update(dt)
    if not state.open then return end

    -- idle 阶段：闪烁计时 + 自动关闭倒计时
    if state.animPhase == "idle" then
        state.hintTimer = state.hintTimer + dt
        state.autoCloseTimer = state.autoCloseTimer - dt
        if state.autoCloseTimer <= 0 then
            state.animPhase = "exit"
            state.animTimer = 0
            return
        end
    end

    -- 动画计时
    if state.animPhase == "enter" then
        state.animTimer = state.animTimer + dt
        if state.animTimer >= ENTER_DELAY + ENTER_DURATION then
            state.animPhase = "idle"
            state.animTimer = 0
        end
    elseif state.animPhase == "exit" then
        state.animTimer = state.animTimer + dt
        if state.animTimer >= EXIT_DURATION then
            doClose()
            return
        end
    end

    -- Spine 动画更新（播完后不再更新，停留最后一帧）
    if state.spineLoaded and state.spineInst and not state.spineFinished then
        local now = time.elapsedTime
        local spineDt = now - state.spineLastTime
        if spineDt > 0.1 then spineDt = 0.016 end
        state.spineLastTime = now
        state.spineInst:Update(spineDt)
    end
end

--- 处理点击（点击任意位置关闭）
---@param dx number 设计空间 X
---@param dy number 设计空间 Y
---@return boolean 是否消费事件
function LevelUpPopup.handleInput(dx, dy)
    if not state.open then return false end
    -- 入场/出场动画中拦截但不响应
    if state.animPhase == "enter" or state.animPhase == "exit" then return true end
    -- 触发出场动画
    state.animPhase = "exit"
    state.animTimer = 0
    return true
end

-- ======================== 动画计算 ========================

--- 计算当前帧的内容偏移和透明度
---@return number offsetX, number contentAlpha, number spineAlpha
local function calcAnimValues()
    if state.animPhase == "enter" then
        -- 入场：延迟后从左侧滑入
        local elapsed = state.animTimer - ENTER_DELAY
        if elapsed <= 0 then
            -- 延迟期间内容完全在左侧屏幕外
            return -DESIGN_W, 0, 1.0
        end
        local t = math.min(elapsed / ENTER_DURATION, 1.0)
        local eased = easeOutCubic(t)
        return -DESIGN_W * (1 - eased), eased, 1.0

    elseif state.animPhase == "exit" then
        -- 出场：向右滑出 + 淡出
        local t = math.min(state.animTimer / EXIT_DURATION, 1.0)
        local eased = easeInCubic(t)
        local alpha = 1.0 - t
        return DESIGN_W * eased, alpha, alpha

    else
        -- idle：正常显示
        return 0, 1.0, 1.0
    end
end

-- ======================== 绘制 ========================

--- 绘制弹窗（在设计空间内调用）
---@param vg any NanoVG 上下文
function LevelUpPopup.draw(vg)
    if not state.open then return end

    local offsetX, contentAlpha, spineAlpha = calcAnimValues()

    -- 1) Spine 全屏背景
    if ensureSpineLoaded(vg) then
        local dataCenterX = SPINE_DATA_X + SPINE_DATA_W * 0.5  -- 0
        local dataCenterY = SPINE_DATA_Y + SPINE_DATA_H * 0.5  -- 0
        local cx = DESIGN_W * 0.5   -- 540
        local cy = DESIGN_H * 0.5   -- 1200

        state.spineInst:SetScale(1.0, -1.0)
        local posX = cx - dataCenterX   -- 540
        local posY = cy + dataCenterY   -- 1200
        state.spineInst:SetPosition(posX, posY)

        -- 出场时 Spine 也淡出
        if spineAlpha < 1.0 then
            nvgSave(vg)
            nvgGlobalAlpha(vg, math.max(spineAlpha, 0))
            nvgSpineRender(vg, state.spineInst)
            nvgRestore(vg)
        else
            nvgSpineRender(vg, state.spineInst)
        end
    end

    -- 入场延迟期间不绘制内容
    if contentAlpha <= 0 then return end

    -- ── 内容层：统一应用平移 + 透明度 ──
    nvgSave(vg)
    nvgTranslate(vg, offsetX, 0)
    if contentAlpha < 1.0 then
        nvgGlobalAlpha(vg, math.max(contentAlpha, 0))
    end

    -- 2) "冒险等级提升" 标题
    drawStrokedText(vg, TITLE_X, TITLE_Y, "冒险等级提升",
        TITLE_SIZE, COLOR_WHITE, COLOR_STROKE_BK, TITLE_STROKE)

    -- 3) 等级数字
    local levelText = "Lv." .. tostring(state.newLevel)
    drawStrokedText(vg, LEVEL_X, LEVEL_Y, levelText,
        LEVEL_SIZE, COLOR_YELLOW, COLOR_LV_STROKE, LEVEL_STROKE)

    -- 4) 文本背景框
    drawImageCentered(vg, state.imgTextBg, TEXT_BG_X, TEXT_BG_Y, TEXT_BG_W, TEXT_BG_H, 1.0)

    -- 5) "天赋点" 文本（黄色，无描边）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, TALENT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(COLOR_YELLOW[1], COLOR_YELLOW[2], COLOR_YELLOW[3], COLOR_YELLOW[4]))
    nvgText(vg, TALENT_X, TALENT_Y, "天赋点", nil)

    -- 6) "+1" 文本（绿色）
    nvgFontSize(vg, PLUS_SIZE)
    nvgFillColor(vg, nvgRGBA(COLOR_GREEN[1], COLOR_GREEN[2], COLOR_GREEN[3], COLOR_GREEN[4]))
    nvgText(vg, PLUS_X, PLUS_Y, "+1", nil)

    -- 7) 分割线
    nvgBeginPath(vg)
    nvgRect(vg, DIVIDER_X - DIVIDER_W * 0.5, DIVIDER_Y - DIVIDER_H * 0.5,
        DIVIDER_W, DIVIDER_H)
    nvgFillColor(vg, nvgRGBA(COLOR_DIVIDER[1], COLOR_DIVIDER[2], COLOR_DIVIDER[3], COLOR_DIVIDER[4]))
    nvgFill(vg)

    -- 8) 解锁内容列表（动态）
    local unlocks = state.unlocks
    if unlocks and #unlocks > 0 then
        for i, unlock in ipairs(unlocks) do
            local itemCY = UNLOCK_START_Y + (i - 1) * (UNLOCK_ITEM_H + UNLOCK_ITEM_GAP)

            -- 8a) 圆角背景（白色 10% 不透明度）
            nvgBeginPath(vg)
            nvgRoundedRect(vg,
                DESIGN_W * 0.5 - UNLOCK_BG_W * 0.5,
                itemCY - UNLOCK_BG_H * 0.5,
                UNLOCK_BG_W, UNLOCK_BG_H, UNLOCK_BG_RADIUS)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, UNLOCK_BG_ALPHA))
            nvgFill(vg)

            -- 8b) 解锁内容名称（X 右居中 473）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, UNLOCK_TEXT_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, UNLOCK_TEXT_X, itemCY, unlock.unlockName, nil)

            -- 8c) 箭头图片（居中 X540）
            drawImageCentered(vg, state.imgArrow, ARROW_X, itemCY, ARROW_W, ARROW_H, 1.0)

            -- 8d) "已开放" 文本
            nvgFontSize(vg, OPENED_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(COLOR_GREEN[1], COLOR_GREEN[2], COLOR_GREEN[3], COLOR_GREEN[4]))
            nvgText(vg, OPENED_X, itemCY, "已开放", nil)
        end
    end

    -- 9) 倒计时 + 点击继续 提示
    local remaining = math.ceil(math.max(state.autoCloseTimer, 0))
    local hintText = remaining .. "秒后自动关闭  点击跳过"
    local hintAlpha = 0.5 + 0.5 * math.sin(state.hintTimer * 3.0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, HINT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * hintAlpha)))
    nvgText(vg, HINT_X, HINT_Y, hintText, nil)

    nvgRestore(vg)
end

--- 释放资源
function LevelUpPopup.destroy()
    if state.spineInst then
        state.spineInst:Unload()
        state.spineInst = nil
    end
    state.spineLoaded = false
    state.open = false
    state.animPhase = nil
end

return LevelUpPopup
