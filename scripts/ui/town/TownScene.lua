-- ============================================================================
-- TownScene - 城镇界面
-- 坐标系: 设计分辨率 1080x2400，所有位置为中心点坐标
-- ============================================================================

local GameState  = require("core.GameState")
local DarkIcon       = require("core.DarkIcon")  -- [暗黑化 P0] 矢量图标库
local HorizonBg      = require("core.HorizonBg")  -- [横屏三联] 左右共享大背景
local ExpTable   = require("config.ExpTable")
local BF         = require("systems.ButtonFeedback")
local LootBox    = require("ui.loot.LootBox")

local TownScene = {}

-- ======================== 图片句柄 ========================

local imgBg       = -1   -- 城镇背景
local imgChurch   = -1   -- 教堂建筑
local imgTree     = -1   -- 终焉古树（天赋入口）
local imgTavern   = -1   -- 酒馆建筑
local imgMarket   = -1   -- 市场建筑
local imgWarehouse = -1  -- 仓库建筑（背包入口）
local imgIconWarehouse = -1 -- 仓库图标
local imgLootBox = -1       -- 遗匣地点立绘 UI_CZ_YX
local imgIconLoot = -1      -- 遗匣名牌图标 ICON_CZ_YX
local imgTask = -1          -- 功绩地点立绘 UI_CZ_GJ
local imgIconTask = -1      -- 功绩名牌图标 ICON_CZ_GJ

local imgIconChurch = -1 -- 教堂图标
local imgIconTree   = -1 -- 古树图标
local imgIconTavern = -1 -- 酒馆图标
local imgIconMarket = -1 -- 市场图标

local imgIconUp   = -1   -- ICON_UP.png 可转职角标
local imgLock     = -1   -- UI_ICON_SUO.png 锁图标
local imgRedDot   = -1   -- ICON_HD.png 红点图标

-- ======================== 外部驱动标志 ========================
local smithDecomposeRedDot = false  -- 铁匠铺分解红点（背包满时）

-- 上方建筑
local imgSmith    = -1   -- 铁匠铺
local imgIconSmith = -1  -- 铁匠铺图标

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

-- 铁匠铺（上移，给古树让出中轴）
local SMITH_CX,  SMITH_CY  = 525,  390
local SMITH_W,   SMITH_H   = 330,  365
local SMITH_LBL_CX, SMITH_LBL_CY = 534, 285
local SMITH_LBL_W,  SMITH_LBL_H  = 361, 113
local SMITH_ICON_CX, SMITH_ICON_CY = 444, 279
local SMITH_ICON_SZ = 64
local SMITH_TEXT_X,  SMITH_TEXT_Y  = 569, 279

-- 终焉古树（天赋入口，画面中轴；尺寸避开仓库/酒馆热区）
local TREE_CX,  TREE_CY  = 540,  1040
local TREE_W,   TREE_H   = 250,  430
local TREE_LBL_CX, TREE_LBL_CY = 540, 1235
local TREE_LBL_W,  TREE_LBL_H  = 361, 113
local TREE_ICON_CX, TREE_ICON_CY = 450, 1229
local TREE_ICON_SZ = 64
local TREE_TEXT_X,  TREE_TEXT_Y  = 585, 1229


-- ---- 下方建筑 ----

-- 教堂（略向右，避免贴死左缘）
local CHURCH_CX,  CHURCH_CY  = 211,  1400
local CHURCH_W,   CHURCH_H   = 344,  688
local CHURCH_LBL_CX, CHURCH_LBL_CY = 238, 1720
local CHURCH_LBL_W,  CHURCH_LBL_H  = 361, 113
local CHURCH_ICON_CX, CHURCH_ICON_CY = 148, 1714
local CHURCH_ICON_SZ = 64
local CHURCH_TEXT_X,  CHURCH_TEXT_Y  = 292, 1714

-- 酒馆
local TAVERN_CX,  TAVERN_CY  = 832,  1400
local TAVERN_W,   TAVERN_H   = 397,  387
local TAVERN_LBL_CX, TAVERN_LBL_CY = 837, 1524
local TAVERN_LBL_W,  TAVERN_LBL_H  = 361, 113
local TAVERN_ICON_CX, TAVERN_ICON_CY = 764, 1524
local TAVERN_ICON_SZ = 64
local TAVERN_TEXT_X,  TAVERN_TEXT_Y  = 871, 1524

-- 仓库（背包入口）—— 右中空位：酒馆正上方，与左侧月蚀黑市同高对称
local WAREHOUSE_CX,  WAREHOUSE_CY  = 832,  720
local WAREHOUSE_W,   WAREHOUSE_H   = 360,  430
local WAREHOUSE_LBL_CX, WAREHOUSE_LBL_CY = 837,  870
local WAREHOUSE_LBL_W,  WAREHOUSE_LBL_H  = 361, 113
local WAREHOUSE_ICON_CX, WAREHOUSE_ICON_CY = 764, 864
local WAREHOUSE_ICON_SZ = 64
local WAREHOUSE_TEXT_X,  WAREHOUSE_TEXT_Y  = 871, 864

-- 市场（月蚀黑市）—— 布局重排：移至左侧，与右侧竞技场同高对称
local MARKET_CX,  MARKET_CY  = 211,  720
local MARKET_W,   MARKET_H   = 369,  454
local MARKET_LBL_CX, MARKET_LBL_CY = 225, 846
local MARKET_LBL_W,  MARKET_LBL_H  = 361, 113
local MARKET_ICON_CX, MARKET_ICON_CY = 152, 846
local MARKET_ICON_SZ = 64
local MARKET_TEXT_X,  MARKET_TEXT_Y  = 259, 846

-- 遗匣：下方偏右。热区随立绘右移，避开教堂底缘与酒馆底缘。
local LOOT_SHIFT_X = 70
local LOOT_CX, LOOT_CY, LOOT_W, LOOT_H = 540 + LOOT_SHIFT_X, 1940, 260, 260
local LOOT_LBL_CY = 2090
local LOOT_HIT_CX, LOOT_HIT_CY, LOOT_HIT_W, LOOT_HIT_H = 540 + LOOT_SHIFT_X, 2010, 380, 440
-- 功绩：左下角地点，整体右移，避开教堂热区和遗匣热区。
local TASK_SHIFT_X = 50
local TASK_CX, TASK_CY, TASK_W, TASK_H = 180 + TASK_SHIFT_X, 2050, 270, 270
local TASK_LBL_CY = 2240
local TASK_HIT_CX, TASK_HIT_CY, TASK_HIT_W, TASK_HIT_H = 180 + TASK_SHIFT_X, 2100, 420, 420

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
    if not ChurchPage_ then ChurchPage_ = require("ui.church.ChurchPage") end
    return ChurchPage_
end

---@type table TalentPage 模块（懒加载）
local TalentPage_ = nil
local function getTalentPage()
    if not TalentPage_ then TalentPage_ = require("ui.church.talent.TalentPage") end
    return TalentPage_
end

---@type table BlacksmithPage 模块（懒加载，避免循环依赖）
local BlacksmithPage_ = nil
local function getBlacksmithPage()
    if not BlacksmithPage_ then BlacksmithPage_ = require("ui.blacksmith.BlacksmithPage") end
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

local townVg_ = nil
local townImgsLoaded_ = false

function TownScene.init(vg)
    townVg_ = vg
end

local function ensureTownImages(vg)
    if townImgsLoaded_ then return end
    local ctx = vg or townVg_
    if not ctx then return end
    townImgsLoaded_ = true
    -- 遗匣用专属立绘，功绩用日记入口图。
    imgBg          = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_BJ.png", 0)
    imgLootBox     = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_YX.png", 0) or -1
    imgIconLoot    = nvgCreateImage(ctx, "image/通用图标/ICON_CZ_YX.png", 0) or -1
    imgTask        = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_GJ.png", 0) or -1
    imgIconTask    = nvgCreateImage(ctx, "image/通用图标/ICON_CZ_GJ.png", 0) or -1
    imgSmith       = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_TJP.png", 0)
    imgIconSmith   = nvgCreateImage(ctx, "image/通用图标/ICON_CZ_TJP.png", 0)
    imgChurch      = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_JT.png", 0)
    imgTree        = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_TREE.png", 0)
    imgTavern      = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_JG.png", 0)
    imgMarket      = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_SJ.png", 0)
    imgWarehouse   = nvgCreateImage(ctx, "image/界面底板/城镇世界/UI_CZ_CK.png", 0)
    imgIconWarehouse = nvgCreateImage(ctx, "image/通用图标/ICON_CZ_CK.png", 0)
    imgIconChurch  = nvgCreateImage(ctx, "image/通用图标/ICON_CZ_JT.png", 0)
    imgIconTree    = nvgCreateImage(ctx, "image/通用图标/ICON_CZ_TREE.png", 0)
    imgIconTavern  = nvgCreateImage(ctx, "image/通用图标/ICON_CZ_JG.png", 0)
    imgIconMarket  = nvgCreateImage(ctx, "image/通用图标/ICON_CZ_SC.png", 0)
    imgIconUp      = nvgCreateImage(ctx, "image/通用图标/ICON_UP.png", 0)
    imgLock        = nvgCreateImage(ctx, "image/通用图标/UI_ICON_SUO.png", 0)
end

function TownScene.draw(vg)
    ensureTownImages(vg)
    -- 0) 处理延迟回调
    processDeferredActions()

    -- 新手引导热点管理器（仅引导激活时使用）
    local _TM = require("systems.TutorialManager")
    local _tmActive = _TM.isActive()

    -- 1) 背景 [横屏三联：共享大背景左半]
    ---@diagnostic disable-next-line: undefined-global
    if H_TRI_L0 then
        -- [三行并行] L0 整套大背景已铺营地场景, 不再叠画
    else
        HorizonBg.draw(vg, 0, 1.0)
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
    if _tmActive and not smithLocked then _TM.registerHotspot("building_smith", SMITH_CX, SMITH_CY, SMITH_W, SMITH_H, "left") end

    -- 2b) 终焉古树（天赋入口，中轴）
    local treeLocked = not _TM.isBuildingUnlocked("church")
    local _bfTree = (not treeLocked) and BF.begin(vg, "town_tree", TREE_CX, TREE_CY, TREE_W, TREE_H) or false
    if treeLocked then
        drawImageSilhouette(vg, imgTree, TREE_CX, TREE_CY, TREE_W, TREE_H, 0.85)
    else
        drawImageDarkTint(vg, imgTree, TREE_CX, TREE_CY, TREE_W, TREE_H, 1.0)
        drawFlashOverlay(vg, imgTree, TREE_CX, TREE_CY, TREE_W, TREE_H, getClickFlashAlpha("tree"))
        drawBuildingLabel(vg,
            TREE_LBL_CX, TREE_LBL_CY, TREE_LBL_W, TREE_LBL_H,
            TREE_ICON_CX, TREE_ICON_CY, TREE_ICON_SZ, imgIconTree,
            TREE_TEXT_X, TREE_TEXT_Y, "终焉古树")
    end
    if treeLocked then
        drawBuildingLockOverlay(vg, TREE_CX, TREE_CY, "church", true)
    end
    if not treeLocked and imgIconUp >= 0 then
        local okUnused, unused = pcall(function() return getTalentPage().hasAnyUnusedTalent() end)
        if okUnused and unused then
            local upSize = 40
            local upX = TREE_LBL_CX + TREE_LBL_W * 0.5 - upSize * 0.15
            local upY = TREE_LBL_CY - TREE_LBL_H * 0.5 - upSize * 0.15
            drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
        end
    end
    BF.finish(vg, _bfTree)
    if _tmActive and not treeLocked then
        _TM.registerHotspot("talent_toggle", TREE_CX, TREE_CY, TREE_W, TREE_H, "left")
        _TM.registerHotspot("building_tree", TREE_CX, TREE_CY, TREE_W, TREE_H, "left")
    end

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
    BF.finish(vg, _bfMarket)

    -- 5b) 仓库建筑（背包入口，与市场同层；无解锁门槛）
    local _bfWarehouse = BF.begin(vg, "town_warehouse", WAREHOUSE_CX, WAREHOUSE_CY, WAREHOUSE_W, WAREHOUSE_H)
    drawImageDarkTint(vg, imgWarehouse, WAREHOUSE_CX, WAREHOUSE_CY, WAREHOUSE_W, WAREHOUSE_H, 1.0)
    drawFlashOverlay(vg, imgWarehouse, WAREHOUSE_CX, WAREHOUSE_CY, WAREHOUSE_W, WAREHOUSE_H, getClickFlashAlpha("warehouse"))
    drawBuildingLabel(vg,
        WAREHOUSE_LBL_CX, WAREHOUSE_LBL_CY, WAREHOUSE_LBL_W, WAREHOUSE_LBL_H,
        WAREHOUSE_ICON_CX, WAREHOUSE_ICON_CY, WAREHOUSE_ICON_SZ, imgIconWarehouse,
        WAREHOUSE_TEXT_X, WAREHOUSE_TEXT_Y, "尘封仓库")
    BF.finish(vg, _bfWarehouse)

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
    -- 教堂角标：转职/神器（天赋角标已移到古树）
    if not churchLocked and imgIconUp >= 0 and getChurchPage().hasAnyChurchBadge() then
        local upSize = 40
        local upX = CHURCH_LBL_CX + CHURCH_LBL_W * 0.5 - upSize * 0.15
        local upY = CHURCH_LBL_CY - CHURCH_LBL_H * 0.5 - upSize * 0.15
        drawImageCentered(vg, imgIconUp, upX, upY, upSize, upSize, 1.0)
    end
    BF.finish(vg, _bfChurch)
    if _tmActive and not churchLocked then _TM.registerHotspot("building_church", CHURCH_CX, CHURCH_CY, CHURCH_W, CHURCH_H, "left") end

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
    if _tmActive and not tavernLocked then _TM.registerHotspot("building_tavern", TAVERN_CX, TAVERN_CY, TAVERN_W, TAVERN_H, "left") end
    -- 城镇总览热点（引导组4）：左栏顶部空白带，不与建筑点击重叠
    if _tmActive then _TM.registerHotspot("town_overview", 540, 150, 900, 220, "left") end

    -- 第7个地点：遗匣（没有等级/引导门槛）。立绘与名牌图标分开，名牌沿用地点图标尺寸。
    local lootFeedback = BF.begin(vg, "town_lootbox", LOOT_HIT_CX, LOOT_HIT_CY, LOOT_HIT_W, LOOT_HIT_H)
    DarkIcon.drawNine(vg, "plain", 390 + LOOT_SHIFT_X, 2010, 300, 64)
    drawImageDarkTint(vg, imgLootBox, LOOT_CX, LOOT_CY, LOOT_W, LOOT_H, 1.0)
    drawFlashOverlay(vg, imgLootBox, LOOT_CX, LOOT_CY, LOOT_W, LOOT_H, getClickFlashAlpha("lootbox"))
    drawBuildingLabel(vg, 540 + LOOT_SHIFT_X, LOOT_LBL_CY, 361, 113,
        450 + LOOT_SHIFT_X, LOOT_LBL_CY - 6, 64, -1, 585 + LOOT_SHIFT_X, LOOT_LBL_CY - 6, "遗匣")
    DarkIcon.draw(vg, "relicbox", 450 + LOOT_SHIFT_X + 32, LOOT_LBL_CY - 6, 64, 1.0)
    local count = LootBox.getCount()
    if count > 0 then
        DarkIcon.draw(vg, "reddot", 709 + LOOT_SHIFT_X, LOOT_LBL_CY - 45, 44, 1.0)
        drawTextStroke(vg, 540 + LOOT_SHIFT_X, 1798, "待领取 " .. require("core.NumberUtil").format(count) .. " 件", 30,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 238, 216, 161, 3)
    end
    LootBox.drawRates(vg, 540 + LOOT_SHIFT_X, 2170)
    BF.finish(vg, lootFeedback)

    local taskFeedback = BF.begin(vg, "town_task", TASK_HIT_CX, TASK_HIT_CY, TASK_HIT_W, TASK_HIT_H)
    drawImageDarkTint(vg, imgTask, TASK_CX, TASK_CY, TASK_W, TASK_H, 1.0)
    drawFlashOverlay(vg, imgTask, TASK_CX, TASK_CY, TASK_W, TASK_H, getClickFlashAlpha("task"))
    drawBuildingLabel(vg, 180 + TASK_SHIFT_X, TASK_LBL_CY, 420, 135,
        15 + TASK_SHIFT_X, TASK_LBL_CY - 6, 78, -1, 225 + TASK_SHIFT_X, TASK_LBL_CY - 6, "功绩")
    DarkIcon.draw(vg, "merit", 15 + TASK_SHIFT_X + 39, TASK_LBL_CY - 6, 78, 1.0)
    local taskOk, TaskPage = pcall(require, "ui.story.task.TaskPage")
    if taskOk and TaskPage.hasClaimable and TaskPage.hasClaimable() then
        DarkIcon.draw(vg, "reddot", 300 + TASK_SHIFT_X, TASK_LBL_CY - 36, 36, 1.0)
    end
    BF.finish(vg, taskFeedback)
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

--- 回调：点击终焉古树
local onTreeClick = nil

function TownScene.setOnTreeClick(fn)
    onTreeClick = fn
end

--- 回调：点击酒馆
local onTavernClick = nil

function TownScene.setOnTavernClick(fn)
    onTavernClick = fn
end


--- 回调：点击市场
local onMarketClick = nil

function TownScene.setOnMarketClick(fn)
    onMarketClick = fn
end

--- 回调：点击仓库（背包入口）
local onWarehouseClick = nil

function TownScene.setOnWarehouseClick(fn)
    onWarehouseClick = fn
end

---@type fun()|nil
local onLootBoxClick = nil
local onTaskClick = nil

function TownScene.setOnLootBoxClick(fn)
    onLootBoxClick = fn
end

function TownScene.setOnTaskClick(fn)
    onTaskClick = fn
end

function TownScene.handleInput(dx, dy)
    -- 整个地点含名牌与收益文字；不再保留左下角全局箱子热区。
    if math.abs(dx - LOOT_HIT_CX) <= LOOT_HIT_W * 0.5
        and math.abs(dy - LOOT_HIT_CY) <= LOOT_HIT_H * 0.5 then
        BF.trigger("town_lootbox")
        triggerClickAnim("lootbox")
        if onLootBoxClick then deferAction(CLICK_CALLBACK_DELAY, onLootBoxClick) end
        return true
    end
    if math.abs(dx - TASK_HIT_CX) <= TASK_HIT_W * 0.5
        and math.abs(dy - TASK_HIT_CY) <= TASK_HIT_H * 0.5 then
        BF.trigger("town_task")
        triggerClickAnim("task")
        print("[TownScene] 点击功绩")
        if onTaskClick then deferAction(CLICK_CALLBACK_DELAY, onTaskClick) end
        return true
    end
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

    -- 古树点击检测
    if dx >= TREE_CX - TREE_W * 0.5 and dx <= TREE_CX + TREE_W * 0.5
       and dy >= TREE_CY - TREE_H * 0.5 and dy <= TREE_CY + TREE_H * 0.5 then
        if not _TM.isBuildingUnlocked("church") then
            print("[TownScene] 古树未被引导解锁")
            return true
        end
        print("[TownScene] 点击终焉古树")
        BF.trigger("town_tree")
        triggerClickAnim("tree")
        if onTreeClick then deferAction(CLICK_CALLBACK_DELAY, onTreeClick) end
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
            print("[TownScene] 市场未解锁，需要远征等级 Lv." .. ExpTable.getBuildingUnlockLevel("market"))
            return true
        end
        print("[TownScene] 点击市场")
        BF.trigger("town_market")
        triggerClickAnim("market")
        if onMarketClick then deferAction(CLICK_CALLBACK_DELAY, onMarketClick) end
        return true
    end

    -- 仓库点击检测（背包入口，无解锁门槛）
    if dx >= WAREHOUSE_CX - WAREHOUSE_W * 0.5 and dx <= WAREHOUSE_CX + WAREHOUSE_W * 0.5
       and dy >= WAREHOUSE_CY - WAREHOUSE_H * 0.5 and dy <= WAREHOUSE_CY + WAREHOUSE_H * 0.5 then
        print("[TownScene] 点击仓库")
        BF.trigger("town_warehouse")
        triggerClickAnim("warehouse")
        if onWarehouseClick then deferAction(CLICK_CALLBACK_DELAY, onWarehouseClick) end
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


return TownScene
