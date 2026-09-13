-- ============================================================================
-- TownScene - 城镇界面
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local GameState  = require("core.GameState")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库
local HorizonBg      = require("core.HorizonBg")  -- [横屏三联] 左右共享大背景
local ExpTable   = require("config.ExpTable")
local BF         = require("systems.ButtonFeedback")

local TownScene = {}

-- ======================== 图片句柄 ========================

local imgBg       = -1   -- 城镇背景
local imgChurch   = -1   -- 教堂建筑
local imgTavern   = -1   -- 酒馆建筑
local imgMarket   = -1   -- 市场建筑

local imgIconChurch = -1 -- 教堂图标
local imgIconTavern = -1 -- 酒馆图标
local imgIconMarket = -1 -- 市场图标

local imgIconUp   = -1   -- ICON_UP.png 可转职角标
local imgLock     = -1   -- UI_ICON_SUO.png 锁图标
local imgRedDot   = -1   -- ICON_HD.png 红点图标

-- ======================== 外部驱动标志 ========================
local smithDecomposeRedDot = false  -- 铁匠铺分解红点（背包满时）
local marketPrivRedDot     = false  -- 市场特权红点（有可观看广告时）
local arenaTicketRedDot    = false  -- 竞技场红点（有竞技券时）

-- 上方建筑
local imgSmith    = -1   -- 铁匠铺
local imgArena    = -1   -- 竞技场
local imgIconSmith = -1  -- 铁匠铺图标
local imgIconArena = -1  -- 竞技场图标

-- ======================== 布局常量 ========================

-- 背景: X540, Y顶部与屏幕顶端对齐, 1080×2290
local BG_CX, BG_W, BG_H = 540, 1080, 2290
local BG_CY = BG_H * 0.5  -- 顶端对齐 → 中心Y = 高度/2

-- 九宫格 inset（上0→改10, 右100, 下0→改10, 左100）
local LABEL_INSET_TOP    = 10
local LABEL_INSET_RIGHT  = 100
local LABEL_INSET_BOTTOM = 10
local LABEL_INSET_LEFT   = 100

-- ---- 上方建筑 ----

-- 冒险者公会

-- 铁匠铺
local SMITH_CX,  SMITH_CY  = 525,  477
local SMITH_W,   SMITH_H   = 366,  405
local SMITH_LBL_CX, SMITH_LBL_CY = 534, 372
local SMITH_LBL_W,  SMITH_LBL_H  = 361, 113
local SMITH_ICON_CX, SMITH_ICON_CY = 444, 366
local SMITH_ICON_SZ = 64
local SMITH_TEXT_X,  SMITH_TEXT_Y  = 569, 366

-- 竞技场
local ARENA_CX,  ARENA_CY  = 878,  684
local ARENA_W,   ARENA_H   = 380,  421
local ARENA_LBL_CX, ARENA_LBL_CY = 871, 654
local ARENA_LBL_W,  ARENA_LBL_H  = 361, 113
local ARENA_ICON_CX, ARENA_ICON_CY = 781, 648
local ARENA_ICON_SZ = 64
local ARENA_TEXT_X,  ARENA_TEXT_Y  = 907, 648

-- ---- 下方建筑 ----

-- 教堂
local CHURCH_CX,  CHURCH_CY  = 171,  1186
local CHURCH_W,   CHURCH_H   = 344,  688
local CHURCH_LBL_CX, CHURCH_LBL_CY = 198, 1506
local CHURCH_LBL_W,  CHURCH_LBL_H  = 361, 113
local CHURCH_ICON_CX, CHURCH_ICON_CY = 125, 1500
local CHURCH_ICON_SZ = 64
local CHURCH_TEXT_X,  CHURCH_TEXT_Y  = 232, 1500

-- 酒馆
local TAVERN_CX,  TAVERN_CY  = 832,  1474
local TAVERN_W,   TAVERN_H   = 397,  387
local TAVERN_LBL_CX, TAVERN_LBL_CY = 837, 1598
local TAVERN_LBL_W,  TAVERN_LBL_H  = 361, 113
local TAVERN_ICON_CX, TAVERN_ICON_CY = 764, 1598
local TAVERN_ICON_SZ = 64
local TAVERN_TEXT_X,  TAVERN_TEXT_Y  = 871, 1598

-- 市场
local MARKET_CX,  MARKET_CY  = 895,  1094
local MARKET_W,   MARKET_H   = 369,  454
local MARKET_LBL_CX, MARKET_LBL_CY = 909, 1220
local MARKET_LBL_W,  MARKET_LBL_H  = 361, 113
local MARKET_ICON_CX, MARKET_ICON_CY = 836, 1220
local MARKET_ICON_SZ = 64
local MARKET_TEXT_X,  MARKET_TEXT_Y  = 943, 1220

-- 文字
local LABEL_FONT_SIZE   = 38
local LABEL_STROKE_WIDTH = 4

-- ======================== 点击反馈动画 ========================

local CLICK_ANIM_DURATION = 0.25   -- 闪白动画时长（秒）

--- 每个建筑的点击动画状态 { startTime=number }（用于闪白效果）
local clickAnim = {}

--- 计算点击闪白 alpha（缩小阶段快速亮起，然后淡出）
local FLASH_PEAK_ALPHA = 0.45      -- 闪白峰值透明度
local function getClickFlashAlpha(buildingKey)
    local anim = clickAnim[buildingKey]
    if not anim then return 0 end
    local elapsed = time.elapsedTime - anim.startTime
    if elapsed >= CLICK_ANIM_DURATION then return 0 end
    local t = elapsed / CLICK_ANIM_DURATION
    -- 前 15% 快速亮起到峰值，后 85% 淡出到 0
    if t < 0.15 then
        return FLASH_PEAK_ALPHA * (t / 0.15)
    else
        local fadeT = (t - 0.15) / 0.85
        -- easeOutQuad 淡出
        return FLASH_PEAK_ALPHA * (1.0 - fadeT * fadeT)
    end
end

--- 延迟回调队列：点击动画播放一段后再触发页面打开
local CLICK_CALLBACK_DELAY = 0.15  -- 回调延迟（秒），让闪白+缩放可见
local deferredActions = {}         -- { { fireAt=number, fn=function }, ... }

local function deferAction(delay, fn)
    table.insert(deferredActions, { fireAt = time.elapsedTime + delay, fn = fn })
end

local function processDeferredActions()
    local i = 1
    while i <= #deferredActions do
        if time.elapsedTime >= deferredActions[i].fireAt then
            deferredActions[i].fn()
            table.remove(deferredActions, i)
        else
            i = i + 1
        end
    end
end

--- 触发建筑点击动画
local function triggerClickAnim(buildingKey)
    clickAnim[buildingKey] = { startTime = time.elapsedTime }
end

-- ======================== 工具函数 ========================

--- 居中绘制图片
local function drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制建筑闪白叠加层（加法混合：用建筑图片自身形状发光）
local function drawFlashOverlay(vg, img, cx, cy, w, h, alpha)
    if alpha <= 0.01 or img < 0 then return end
    nvgSave(vg)
    nvgGlobalCompositeOperation(vg, NVG_LIGHTER)
    drawImageCentered(vg, img, cx, cy, w, h, alpha)
    nvgRestore(vg)
end

--- 绘制建筑黑色剪影（未解锁时叠加）
--- 原理：先正常画建筑，再用自定义混合将建筑不透明区域压暗为黑色
--- RGB: dst * (1 - src_alpha * darkness) → 建筑区域变黑
--- Alpha: 保持不变 → 不会产生透明孔洞
--- @param darkness number 0.0=不变, 1.0=纯黑
local function drawImageSilhouette(vg, img, cx, cy, w, h, darkness)
    if img < 0 or darkness <= 0.01 then return end
    -- 第一步：正常绘制建筑图（保留原始形状和颜色）
    drawImageCentered(vg, img, cx, cy, w, h, 1.0)
    -- 第二步：用同一张图做遮罩，将建筑区域压暗
    -- blend: rgb = src*0 + dst*(1-src_a) = dst*(1-src_a),  alpha = dst_a 不变
    nvgSave(vg)
    nvgGlobalCompositeBlendFuncSeparate(vg,
        NVG_ZERO, NVG_ONE_MINUS_SRC_ALPHA,   -- RGB: dst darkened by src alpha
        NVG_ZERO, NVG_ONE)                    -- Alpha: keep destination
    drawImageCentered(vg, img, cx, cy, w, h, darkness)
    nvgRestore(vg)
end

--- [暗黑替换] 建筑压暗绘制：nvgImagePatternTinted 乘法叠色（暖褐 ×≈0.57）
local function drawImageDarkTint(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePatternTinted(vg, x, y, w, h, 0, img,
        nvgRGBA(150, 138, 122, math.floor(255 * alpha)))
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 九宫格绘制（复用 EquipmentDetail 已验证的实现）
--- 参数: 目标区域左上角(dx,dy)、宽高(dw,dh)、四边 inset
local function drawNineSlice(vg, img, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if img < 0 then return end

    local srcW, srcH = nvgImageSize(vg, img)
    if srcW <= 0 or srcH <= 0 then return end

    local sL = iLeft
    local sR = iRight
    local sT = iTop
    local sB = iBottom
    local sMW = srcW - sL - sR
    local sMH = srcH - sT - sB

    local dL = math.min(iLeft, dw * 0.5)
    local dR = math.min(iRight, dw * 0.5)
    local dT = math.min(iTop, dh * 0.5)
    local dB = math.min(iBottom, dh * 0.5)

    if sMW <= 0 or sMH <= 0 then
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, img, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, dx, dy, dw, dh)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        return
    end

    -- 整数分界点
    local ix0 = math.floor(dx + 0.5)
    local iy0 = math.floor(dy + 0.5)
    local ix1 = math.floor(dx + dL + 0.5)
    local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5)
    local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5)
    local iy3 = math.floor(dy + dh + 0.5)

    -- 9个patch: {destX, destY, destW, destH, srcX, srcY, srcW, srcH}
    local OV = 1  -- 重叠像素消缝隙
    local patches = {
        -- 中心
        { ix1 - OV, iy1 - OV, ix2 - ix1 + OV * 2, iy2 - iy1 + OV * 2, sL, sT, sMW, sMH },
        -- 四条边
        { ix1 - OV, iy0,      ix2 - ix1 + OV * 2, iy1 - iy0 + OV,     sL,       0,        sMW, sT  },
        { ix1 - OV, iy2 - OV, ix2 - ix1 + OV * 2, iy3 - iy2 + OV,     sL,       sT + sMH, sMW, sB  },
        { ix0,      iy1 - OV, ix1 - ix0 + OV,     iy2 - iy1 + OV * 2, 0,        sT,       sL,  sMH },
        { ix2 - OV, iy1 - OV, ix3 - ix2 + OV,     iy2 - iy1 + OV * 2, sL + sMW, sT,       sR,  sMH },
        -- 四个角
        { ix0,      iy0,      ix1 - ix0 + OV, iy1 - iy0 + OV, 0,        0,        sL, sT  },
        { ix2 - OV, iy0,      ix3 - ix2 + OV, iy1 - iy0 + OV, sL + sMW, 0,        sR, sT  },
        { ix0,      iy2 - OV, ix1 - ix0 + OV, iy3 - iy2 + OV, 0,        sT + sMH, sL, sB  },
        { ix2 - OV, iy2 - OV, ix3 - ix2 + OV, iy3 - iy2 + OV, sL + sMW, sT + sMH, sR, sB  },
    }

    nvgShapeAntiAlias(vg, 0)
    for _, p in ipairs(patches) do
        local px, py, pw, ph = p[1], p[2], p[3], p[4]
        local sx, sy, sw, sh = p[5], p[6], p[7], p[8]
        if pw > 0 and ph > 0 and sw > 0 and sh > 0 then
            local scaleX = pw / sw
            local scaleY = ph / sh
            local paint = nvgImagePattern(vg,
                px - sx * scaleX,
                py - sy * scaleY,
                srcW * scaleX,
                srcH * scaleY,
                0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, px, py, pw, ph)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    end
    nvgShapeAntiAlias(vg, 1)
end

--- 描边文字
local drawTextStroke = require("core.DrawUtil").drawTextStroke

---@type table ChurchPage 模块（懒加载，避免循环依赖）
local ChurchPage_ = nil
local function getChurchPage()
    if not ChurchPage_ then ChurchPage_ = require("ui.ChurchPage") end
    return ChurchPage_
end

---@type table BlacksmithPage 模块（懒加载，避免循环依赖）
local BlacksmithPage_ = nil
local function getBlacksmithPage()
    if not BlacksmithPage_ then BlacksmithPage_ = require("ui.BlacksmithPage") end
    return BlacksmithPage_
end

--- 绘制一个建筑标签（九宫格标签背景 + 图标 + 文字）
local function drawBuildingLabel(vg, lblCx, lblCy, lblW, lblH,
                                 iconCx, iconCy, iconSz, iconImg,
                                 textX, textY, text)
    -- 使用九宫格绘制标签背景（drawNineSlice 接收左上角坐标）
    local lx = lblCx - lblW * 0.5
    local ly = lblCy - lblH * 0.5
    DarkIcon.drawNine(vg, "plain", lx, ly, lblW, lblH)
    drawImageCentered(vg, iconImg, iconCx, iconCy, iconSz, iconSz, 1.0)
    drawTextStroke(vg, textX, textY, text,
        LABEL_FONT_SIZE, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, LABEL_STROKE_WIDTH)
end

-- ======================== 建筑锁定遮罩 ========================

local LOCK_ICON_SIZE = 100

--- 绘制建筑锁定遮罩（锁图标，等级解锁型附带解锁等级文字）
--- @param tutorialControlled boolean|nil  true=由引导解锁（不显示等级文字），nil/false=显示等级文字
local function drawBuildingLockOverlay(vg, cx, cy, buildingKey, tutorialControlled)
    drawImageCentered(vg, imgLock, cx, cy - 15, LOCK_ICON_SIZE, LOCK_ICON_SIZE, 0.85)
    if not tutorialControlled then
        local unlockLv = ExpTable.getBuildingUnlockLevel(buildingKey)
        local label
        if unlockLv <= 0 then
            label = "暂未开放"
        else
            label = "Lv." .. unlockLv .. " 解锁"
        end
        drawTextStroke(vg, cx, cy + 50, label,
            30, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 220, 120, 3)
    end
end

-- ======================== Public API ========================

function TownScene.init(vg)
    imgBg          = nvgCreateImage(vg, "image/UI_CZ_BJ.png", 0)
    imgLabelBg     = nvgCreateImage(vg, "image/UI_CZ_BQ.png", 0)

    -- 上方建筑
    imgSmith       = nvgCreateImage(vg, "image/UI_CZ_TJP.png", 0)
    imgArena       = nvgCreateImage(vg, "image/UI_CZ_JJC.png", 0)
    imgIconSmith   = nvgCreateImage(vg, "image/ICON_CZ_TJP.png", 0)
    imgIconArena   = nvgCreateImage(vg, "image/ICON_CZ_JJC.png", 0)

    -- 下方建筑
    imgChurch      = nvgCreateImage(vg, "image/UI_CZ_JT.png", 0)
    imgTavern      = nvgCreateImage(vg, "image/UI_CZ_JG.png", 0)
    imgMarket      = nvgCreateImage(vg, "image/UI_CZ_SJ.png", 0)
    imgIconChurch  = nvgCreateImage(vg, "image/ICON_CZ_JT.png", 0)
    imgIconTavern  = nvgCreateImage(vg, "image/ICON_CZ_JG.png", 0)
    imgIconMarket  = nvgCreateImage(vg, "image/ICON_CZ_SC.png", 0)

    imgIconUp      = nvgCreateImage(vg, "image/ICON_UP.png", 0)
    imgLock        = nvgCreateImage(vg, "image/UI_ICON_SUO.png", 0)
end

function TownScene.draw(vg)
    -- 0) 处理延迟回调
    processDeferredActions()

    -- 新手引导热点管理器（仅引导激活时使用）
    local _TM = require("systems.TutorialManager")
    local _tmActive = _TM.isActive()

    -- 1) 背景 [横屏三联：共享大背景左半；竖屏保持原版（用户已专门制作暗黑背景，P3-12a 回退）]
    ---@diagnostic disable-next-line: undefined-global
    if H_TRI_L0 then
        -- [三行并行] L0 整套大背景已铺营地场景, 不再叠画
    elseif HORIZON_MODE then
        HorizonBg.draw(vg, 0, 1.0)
    else
        drawImageCentered(vg, imgBg, BG_CX, BG_CY, BG_W, BG_H, 1.0)
    end

    -- ---- 上方建筑（从后到前，带点击缩放动画）----

    -- 2) 铁匠铺（中间偏上）
    local smithLocked = not _TM.isBuildingUnlocked("smith")
    local _bfSmith = (not smithLocked) and BF.begin(vg, "town_smith", SMITH_CX, SMITH_CY, SMITH_W, SMITH_H) or false
    if smithLocked then
        drawImageSilhouette(vg, imgSmith, SMITH_CX, SMITH_CY, SMITH_W, SMITH_H, 0.85)
    else
        drawImageDarkTint(vg, imgSmith, SMITH_CX, SMITH_CY, SMITH_W, SMITH_H, 1.0)
        drawFlashOverlay(vg, imgSmith, SMITH_CX, SMITH_CY, SMITH_W, SMITH_H, getClickFlashAlpha("smith"))
        drawBuildingLabel(vg,
            SMITH_LBL_CX, SMITH_LBL_CY, SMITH_LBL_W, SMITH_LBL_H,
            SMITH_ICON_CX, SMITH_ICON_CY, SMITH_ICON_SZ, imgIconSmith,
            SMITH_TEXT_X, SMITH_TEXT_Y, "狱火锻炉")
    end
    if smithLocked then
        drawBuildingLockOverlay(vg, SMITH_CX, SMITH_CY, "smith", true)
    end
    -- 铁匠铺红点（背包满→提示去分解）
    if not smithLocked and smithDecomposeRedDot then
        local rdSz = 40
        local rdX = SMITH_LBL_CX + SMITH_LBL_W * 0.5 - rdSz * 0.3
        local rdY = SMITH_LBL_CY - SMITH_LBL_H * 0.5 + rdSz * 0.3
        DarkIcon.draw(vg, "reddot", rdX, rdY, rdSz, 1.0)end
    -- 铁匠铺可强化角标（任意槽位满足强化消耗条件）
    if not smithLocked and not smithDecomposeRedDot and imgIconUp >= 0 then
        local ok, canEnh = pcall(function() return getBlacksmithPage().canEnhanceAny() end)
        if ok and canEnh then
            local upSize = 40
            local upX = SMITH_LBL_CX + SMITH_LBL_W * 0.5 - upSize * 0.3
            local upY = SMITH_LBL_CY - SMITH_LBL_H * 0.5 + upSize * 0.3
            drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
        end
    end
    BF.finish(vg, _bfSmith)
    if _tmActive and not smithLocked then _TM.registerHotspot("building_smith", SMITH_CX, SMITH_CY, SMITH_W, SMITH_H) end

    -- [公会功能已移除] 城镇不再渲染冒险者公会建筑（单机版无公会玩法）

    -- 4) 竞技场（右侧）
    local arenaLocked = not _TM.isBuildingUnlocked("arena")
    local _bfArena = (not arenaLocked) and BF.begin(vg, "town_arena", ARENA_CX, ARENA_CY, ARENA_W, ARENA_H) or false
    if arenaLocked then
        drawImageSilhouette(vg, imgArena, ARENA_CX, ARENA_CY, ARENA_W, ARENA_H, 0.85)
    else
        drawImageDarkTint(vg, imgArena, ARENA_CX, ARENA_CY, ARENA_W, ARENA_H, 1.0)
        drawFlashOverlay(vg, imgArena, ARENA_CX, ARENA_CY, ARENA_W, ARENA_H, getClickFlashAlpha("arena"))
        drawBuildingLabel(vg,
            ARENA_LBL_CX, ARENA_LBL_CY, ARENA_LBL_W, ARENA_LBL_H,
            ARENA_ICON_CX, ARENA_ICON_CY, ARENA_ICON_SZ, imgIconArena,
            ARENA_TEXT_X, ARENA_TEXT_Y, "血砂斗场")
    end
    if arenaLocked then
        drawBuildingLockOverlay(vg, ARENA_CX, ARENA_CY, "arena", true)
    end
    -- 竞技场红点（有竞技券时）
    if not arenaLocked and arenaTicketRedDot then
        local rdSz = 40
        local rdX = ARENA_LBL_CX + ARENA_LBL_W * 0.5 - rdSz * 0.3
        local rdY = ARENA_LBL_CY - ARENA_LBL_H * 0.5 + rdSz * 0.3
        DarkIcon.draw(vg, "reddot", rdX, rdY, rdSz, 1.0)end
    BF.finish(vg, _bfArena)
    if _tmActive and not arenaLocked then _TM.registerHotspot("building_arena", ARENA_CX, ARENA_CY, ARENA_W, ARENA_H) end

    -- ---- 下方建筑 ----

    -- 5) 市场建筑（后层）
    local marketLocked = not ExpTable.isBuildingUnlocked("market", GameState.getLevel())
    local _bfMarket = (not marketLocked) and BF.begin(vg, "town_market", MARKET_CX, MARKET_CY, MARKET_W, MARKET_H) or false
    if marketLocked then
        drawImageSilhouette(vg, imgMarket, MARKET_CX, MARKET_CY, MARKET_W, MARKET_H, 0.85)
    else
        drawImageDarkTint(vg, imgMarket, MARKET_CX, MARKET_CY, MARKET_W, MARKET_H, 1.0)
        drawFlashOverlay(vg, imgMarket, MARKET_CX, MARKET_CY, MARKET_W, MARKET_H, getClickFlashAlpha("market"))
        drawBuildingLabel(vg,
            MARKET_LBL_CX, MARKET_LBL_CY, MARKET_LBL_W, MARKET_LBL_H,
            MARKET_ICON_CX, MARKET_ICON_CY, MARKET_ICON_SZ, imgIconMarket,
            MARKET_TEXT_X, MARKET_TEXT_Y, "月蚀黑市")
    end
    if marketLocked then
        drawBuildingLockOverlay(vg, MARKET_CX, MARKET_CY, "market", false)
    end
    -- 市场特权红点（有可观看广告时）
    if not marketLocked and marketPrivRedDot then
        local rdSz = 40
        local rdX = MARKET_LBL_CX + MARKET_LBL_W * 0.5 - rdSz * 0.3
        local rdY = MARKET_LBL_CY - MARKET_LBL_H * 0.5 + rdSz * 0.3
        DarkIcon.draw(vg, "reddot", rdX, rdY, rdSz, 1.0)end
    BF.finish(vg, _bfMarket)

    -- 6) 教堂建筑
    local churchLocked = not _TM.isBuildingUnlocked("church")
    local _bfChurch = (not churchLocked) and BF.begin(vg, "town_church", CHURCH_CX, CHURCH_CY, CHURCH_W, CHURCH_H) or false
    if churchLocked then
        drawImageSilhouette(vg, imgChurch, CHURCH_CX, CHURCH_CY, CHURCH_W, CHURCH_H, 0.85)
    else
        drawImageDarkTint(vg, imgChurch, CHURCH_CX, CHURCH_CY, CHURCH_W, CHURCH_H, 1.0)
        drawFlashOverlay(vg, imgChurch, CHURCH_CX, CHURCH_CY, CHURCH_W, CHURCH_H, getClickFlashAlpha("church"))
        drawBuildingLabel(vg,
            CHURCH_LBL_CX, CHURCH_LBL_CY, CHURCH_LBL_W, CHURCH_LBL_H,
            CHURCH_ICON_CX, CHURCH_ICON_CY, CHURCH_ICON_SZ, imgIconChurch,
            CHURCH_TEXT_X, CHURCH_TEXT_Y, "缄默礼拜堂")
    end
    if churchLocked then
        drawBuildingLockOverlay(vg, CHURCH_CX, CHURCH_CY, "church", true)
    end
    -- 教堂角标（标签右上角）：天赋可用 或 转职可用
    if not churchLocked and imgIconUp >= 0 and getChurchPage().hasAnyChurchBadge() then
        local upSize = 40
        local upX = CHURCH_LBL_CX + CHURCH_LBL_W * 0.5 - upSize * 0.3
        local upY = CHURCH_LBL_CY - CHURCH_LBL_H * 0.5 + upSize * 0.3
        drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
    end
    BF.finish(vg, _bfChurch)
    if _tmActive and not churchLocked then _TM.registerHotspot("building_church", CHURCH_CX, CHURCH_CY, CHURCH_W, CHURCH_H) end

    -- 7) 酒馆建筑（前层）
    local tavernLocked = not _TM.isBuildingUnlocked("tavern")
    local _bfTavern = (not tavernLocked) and BF.begin(vg, "town_tavern", TAVERN_CX, TAVERN_CY, TAVERN_W, TAVERN_H) or false
    if tavernLocked then
        drawImageSilhouette(vg, imgTavern, TAVERN_CX, TAVERN_CY, TAVERN_W, TAVERN_H, 0.85)
    else
        drawImageDarkTint(vg, imgTavern, TAVERN_CX, TAVERN_CY, TAVERN_W, TAVERN_H, 1.0)
        drawFlashOverlay(vg, imgTavern, TAVERN_CX, TAVERN_CY, TAVERN_W, TAVERN_H, getClickFlashAlpha("tavern"))
        drawBuildingLabel(vg,
            TAVERN_LBL_CX, TAVERN_LBL_CY, TAVERN_LBL_W, TAVERN_LBL_H,
            TAVERN_ICON_CX, TAVERN_ICON_CY, TAVERN_ICON_SZ, imgIconTavern,
            TAVERN_TEXT_X, TAVERN_TEXT_Y, "腐鸦酒馆")
    end
    if tavernLocked then
        drawBuildingLockOverlay(vg, TAVERN_CX, TAVERN_CY, "tavern", true)
    end
    BF.finish(vg, _bfTavern)
    if _tmActive and not tavernLocked then _TM.registerHotspot("building_tavern", TAVERN_CX, TAVERN_CY, TAVERN_W, TAVERN_H) end
end

--- 回调：点击铁匠铺
local onSmithClick = nil

function TownScene.setOnSmithClick(fn)
    onSmithClick = fn
end

--- 回调：点击教堂
local onChurchClick = nil

function TownScene.setOnChurchClick(fn)
    onChurchClick = fn
end

--- 回调：点击酒馆
local onTavernClick = nil

function TownScene.setOnTavernClick(fn)
    onTavernClick = fn
end

--- 回调：点击竞技场
local onArenaClick = nil

function TownScene.setOnArenaClick(fn)
    onArenaClick = fn
end

--- 回调：点击市场
local onMarketClick = nil

function TownScene.setOnMarketClick(fn)
    onMarketClick = fn
end

--- 回调：点击冒险者公会
local onGuildClick = nil

function TownScene.setOnGuildClick(fn)
    onGuildClick = fn
end

function TownScene.handleInput(dx, dy)
    local _TM = require("systems.TutorialManager")
    -- 铁匠铺点击检测
    if dx >= SMITH_CX - SMITH_W * 0.5 and dx <= SMITH_CX + SMITH_W * 0.5
       and dy >= SMITH_CY - SMITH_H * 0.5 and dy <= SMITH_CY + SMITH_H * 0.5 then
        if not _TM.isBuildingUnlocked("smith") then
            print("[TownScene] 铁匠铺未被引导解锁")
            return true
        end
        print("[TownScene] 点击铁匠铺")
        BF.trigger("town_smith")
        triggerClickAnim("smith")
        if onSmithClick then deferAction(CLICK_CALLBACK_DELAY, onSmithClick) end
        return true
    end

    -- 竞技场点击检测
    if dx >= ARENA_CX - ARENA_W * 0.5 and dx <= ARENA_CX + ARENA_W * 0.5
       and dy >= ARENA_CY - ARENA_H * 0.5 and dy <= ARENA_CY + ARENA_H * 0.5 then
        if not _TM.isBuildingUnlocked("arena") then
            print("[TownScene] 竞技场未被引导解锁")
            return true
        end
        print("[TownScene] 点击竞技场")
        BF.trigger("town_arena")
        triggerClickAnim("arena")
        if onArenaClick then deferAction(CLICK_CALLBACK_DELAY, onArenaClick) end
        return true
    end

    -- 教堂点击检测
    if dx >= CHURCH_CX - CHURCH_W * 0.5 and dx <= CHURCH_CX + CHURCH_W * 0.5
       and dy >= CHURCH_CY - CHURCH_H * 0.5 and dy <= CHURCH_CY + CHURCH_H * 0.5 then
        if not _TM.isBuildingUnlocked("church") then
            print("[TownScene] 教堂未被引导解锁")
            return true
        end
        print("[TownScene] 点击教堂")
        BF.trigger("town_church")
        triggerClickAnim("church")
        if onChurchClick then deferAction(CLICK_CALLBACK_DELAY, onChurchClick) end
        return true
    end

    -- 市场点击检测
    if dx >= MARKET_CX - MARKET_W * 0.5 and dx <= MARKET_CX + MARKET_W * 0.5
       and dy >= MARKET_CY - MARKET_H * 0.5 and dy <= MARKET_CY + MARKET_H * 0.5 then
        if not ExpTable.isBuildingUnlocked("market", GameState.getLevel()) then
            print("[TownScene] 市场未解锁，需要冒险等级 Lv." .. ExpTable.getBuildingUnlockLevel("market"))
            return true
        end
        print("[TownScene] 点击市场")
        BF.trigger("town_market")
        triggerClickAnim("market")
        if onMarketClick then deferAction(CLICK_CALLBACK_DELAY, onMarketClick) end
        return true
    end

    -- 酒馆点击检测
    if dx >= TAVERN_CX - TAVERN_W * 0.5 and dx <= TAVERN_CX + TAVERN_W * 0.5
       and dy >= TAVERN_CY - TAVERN_H * 0.5 and dy <= TAVERN_CY + TAVERN_H * 0.5 then
        if not _TM.isBuildingUnlocked("tavern") then
            print("[TownScene] 酒馆未被引导解锁")
            return true
        end
        print("[TownScene] 点击酒馆")
        BF.trigger("town_tavern")
        triggerClickAnim("tavern")
        if onTavernClick then deferAction(CLICK_CALLBACK_DELAY, onTavernClick) end
        return true
    end

    return false
end

--- 设置铁匠铺分解红点（背包满时由外部驱动）
---@param show boolean
function TownScene.setSmithRedDot(show)
    smithDecomposeRedDot = show
end

--- 设置市场特权红点（有可观看广告时由外部驱动）
---@param show boolean
function TownScene.setMarketRedDot(show)
    marketPrivRedDot = show
end

--- 设置竞技场红点（有竞技券时由外部驱动）
---@param show boolean
function TownScene.setArenaRedDot(show)
    arenaTicketRedDot = show
end

--- 设置公会遗物角标（公会功能已移除，保留空实现兼容旧调用）
---@param show boolean
---@param style string|nil 忽略
function TownScene.setGuildRelicBadge(show, style)
    -- no-op: 公会功能已从城镇移除
end

return TownScene
