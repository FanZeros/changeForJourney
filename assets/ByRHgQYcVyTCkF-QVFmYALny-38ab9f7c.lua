-- ============================================================================
-- DrawUtil  —— 全局文本/图形绘制工具
-- 统一 drawTextStroke，避免各 UI 模块重复定义
-- ============================================================================

local DrawUtil = {}

-- ============================================================================
-- 斜体常量
-- ============================================================================

--- 斜体倾斜角度（弧度），约 -12°
--- NanoVG nvgSkewX 正值使底部右移（向左倾），取负值使顶部右移（CSS italic 方向）
local ITALIC_SKEW = -math.tan(math.rad(12))   -- ≈ -0.2126

-- ============================================================================
-- drawTextStroke  —— 带 8 方向圆形描边的文字绘制
-- ============================================================================

--- 绘制带描边的文本（8 方向圆形偏移，性能优化版）。
--- @param vg       any
--- @param x        number    绘制锚点 X
--- @param y        number    绘制锚点 Y
--- @param text     string    文字内容
--- @param fontSize number    字号（设计分辨率下的 px）
--- @param align    number    NVG 对齐标志，如 NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE
--- @param fr       number    填充色 R (0-255)
--- @param fg       number    填充色 G (0-255)
--- @param fb       number    填充色 B (0-255)
--- @param sw       number    描边宽度（px）
--- @param opts     table|nil 可选参数表 { alpha = 0~1, italic = bool, strokeColor = {r,g,b} }
function DrawUtil.drawTextStroke(vg, x, y, text, fontSize, align, fr, fg, fb, sw, opts)
    local alpha  = 255
    local italic = false
    local sr, sg, sb = 0, 0, 0   -- 描边颜色默认黑色

    if opts then
        if opts.alpha then
            if opts.alpha <= 0.01 then return end
            alpha = math.floor(opts.alpha * 255 + 0.5)
        end
        if opts.italic then italic = true end
        if opts.strokeColor then
            sr, sg, sb = opts.strokeColor[1], opts.strokeColor[2], opts.strokeColor[3]
        end
    end

    -- 应用斜体变换：save → skewX → 绘制 → restore
    if italic then
        nvgSave(vg)
        -- 以锚点为中心做 skew：先平移到锚点，skew，再移回
        nvgTranslate(vg, x, y)
        nvgSkewX(vg, ITALIC_SKEW)
        nvgTranslate(vg, -x, -y)
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, align)

    -- 描边层（8 方向圆形偏移）
    nvgFillColor(vg, nvgRGBA(sr, sg, sb, alpha))
    nvgText(vg, x - sw, y, text, nil)
    nvgText(vg, x + sw, y, text, nil)
    nvgText(vg, x, y - sw, text, nil)
    nvgText(vg, x, y + sw, text, nil)
    local d = sw * 0.707
    nvgText(vg, x - d, y - d, text, nil)
    nvgText(vg, x + d, y - d, text, nil)
    nvgText(vg, x - d, y + d, text, nil)
    nvgText(vg, x + d, y + d, text, nil)

    -- 填充层
    nvgFillColor(vg, nvgRGBA(fr, fg, fb, alpha))
    nvgText(vg, x, y, text, nil)

    if italic then
        nvgRestore(vg)
    end
end

--- 向后兼容：alpha 作为第 11 个位置参数的快捷写法（仅 BottomNav 需要）
--- drawTextStrokeAlpha(vg, x, y, text, fontSize, align, fr, fg, fb, sw, alpha)
function DrawUtil.drawTextStrokeAlpha(vg, x, y, text, fontSize, align, fr, fg, fb, sw, alpha)
    DrawUtil.drawTextStroke(vg, x, y, text, fontSize, align, fr, fg, fb, sw, { alpha = alpha })
end

-- ============================================================================
-- drawImageCentered  —— 以中心点绘制图片
-- ============================================================================

--- 以 (cx, cy) 为中心绘制图片。
---@param vg any      NanoVG context
---@param img number  图片句柄（nvgCreateImage 返回值）
---@param cx number   中心 X
---@param cy number   中心 Y
---@param w number    绘制宽度
---@param h number    绘制高度
---@param alpha number 透明度 0.0~1.0
function DrawUtil.drawImageCentered(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    local x = cx - w * 0.5
    local y = cy - h * 0.5
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- ============================================================================
-- drawNineSlice  —— 九宫格绘制
-- ============================================================================

--- 九宫格绘制（带 AntiAlias 保护，避免 patch 接缝）。
---@param vg any      NanoVG context
---@param img number  图片句柄
---@param dx number   目标区域左上角 X
---@param dy number   目标区域左上角 Y
---@param dw number   目标区域宽度
---@param dh number   目标区域高度
---@param iTop number    上边距切片像素
---@param iRight number  右边距切片像素
---@param iBottom number 下边距切片像素
---@param iLeft number   左边距切片像素
function DrawUtil.drawNineSlice(vg, img, dx, dy, dw, dh, iTop, iRight, iBottom, iLeft)
    if img < 0 then return end

    local srcW, srcH = nvgImageSize(vg, img)
    if srcW <= 0 or srcH <= 0 then return end

    local sL, sR, sT, sB = iLeft, iRight, iTop, iBottom
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

    local ix0 = math.floor(dx + 0.5)
    local iy0 = math.floor(dy + 0.5)
    local ix1 = math.floor(dx + dL + 0.5)
    local iy1 = math.floor(dy + dT + 0.5)
    local ix2 = math.floor(dx + dw - dR + 0.5)
    local iy2 = math.floor(dy + dh - dB + 0.5)
    local ix3 = math.floor(dx + dw + 0.5)
    local iy3 = math.floor(dy + dh + 0.5)

    local OV = 1
    local patches = {
        { ix1 - OV, iy1 - OV, ix2 - ix1 + OV * 2, iy2 - iy1 + OV * 2, sL, sT, sMW, sMH },
        { ix1 - OV, iy0,      ix2 - ix1 + OV * 2, iy1 - iy0 + OV,     sL,       0,        sMW, sT  },
        { ix1 - OV, iy2 - OV, ix2 - ix1 + OV * 2, iy3 - iy2 + OV,     sL,       sT + sMH, sMW, sB  },
        { ix0,      iy1 - OV, ix1 - ix0 + OV,     iy2 - iy1 + OV * 2, 0,        sT,       sL,  sMH },
        { ix2 - OV, iy1 - OV, ix3 - ix2 + OV,     iy2 - iy1 + OV * 2, sL + sMW, sT,       sR,  sMH },
        { ix0,      iy0,      ix1 - ix0 + OV,     iy1 - iy0 + OV,     0,        0,        sL,  sT  },
        { ix2 - OV, iy0,      ix3 - ix2 + OV,     iy1 - iy0 + OV,     sL + sMW, 0,        sR,  sT  },
        { ix0,      iy2 - OV, ix1 - ix0 + OV,     iy3 - iy2 + OV,     0,        sT + sMH, sL,  sB  },
        { ix2 - OV, iy2 - OV, ix3 - ix2 + OV,     iy3 - iy2 + OV,     sL + sMW, sT + sMH, sR,  sB  },
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

-- ============================================================================
-- hitTest  —— 矩形碰撞检测（中心坐标）
-- ============================================================================

--- 矩形点击检测（中心坐标 + 宽高）。
---@param px number 点击位置 X
---@param py number 点击位置 Y
---@param cx number 矩形中心 X
---@param cy number 矩形中心 Y
---@param w number  矩形宽度
---@param h number  矩形高度
---@return boolean
function DrawUtil.hitTest(px, py, cx, cy, w, h)
    return px >= cx - w * 0.5 and px <= cx + w * 0.5
       and py >= cy - h * 0.5 and py <= cy + h * 0.5
end

-- ============================================================================
-- drawRoundedRectCentered  —— 以中心点绘制圆角矩形
-- ============================================================================

--- 以 (cx, cy) 为中心绘制带圆角的纯色矩形。
---@param vg any       NanoVG context
---@param cx number    中心 X
---@param cy number    中心 Y
---@param w number     宽度
---@param h number     高度
---@param r number     圆角半径
---@param rr number    填充色 R (0-255)
---@param gg number    填充色 G (0-255)
---@param bb number    填充色 B (0-255)
---@param aa number    填充色 A (0-255)
function DrawUtil.drawRoundedRectCentered(vg, cx, cy, w, h, r, rr, gg, bb, aa)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - w * 0.5, cy - h * 0.5, w, h, r)
    nvgFillColor(vg, nvgRGBA(rr, gg, bb, aa))
    nvgFill(vg)
end

-- ============================================================================
-- drawShardIcon  —— 碎片图标统一绘制（英雄头像 + 左上角碎片角标）
-- ============================================================================

--- 碎片角标图片句柄缓存（模块级，init 时加载）
---@type number
DrawUtil._shardBadgeImg = -1

--- 英雄头像图片句柄缓存（模块级，init 时加载）
---@type table<number, number>
DrawUtil._heroIconImgs = {}

--- 初始化碎片图标资源（在主初始化时调用一次）
---@param vg any NanoVG context
function DrawUtil.initShardAssets(vg)
    if DrawUtil._shardBadgeImg >= 0 then return end  -- 已初始化
    DrawUtil._shardBadgeImg = nvgCreateImage(vg, "image/ICON_SP.png", 0)
    local HeroAssetUtil = require("config.HeroAssetUtil")
    for _, i in ipairs(HeroAssetUtil.getAssetIds()) do
        local path = HeroAssetUtil.getIconPath(i)
        local img = nvgCreateImage(vg, path, 0)
        if img >= 0 then
            DrawUtil._heroIconImgs[i] = img
        end
    end
end

--- 绘制碎片图标（英雄头像为主图标 + ICON_SP 左上角 53×53 角标）。
--- 资源配置规范：主图 = 英雄头像，左上角角标 = 碎片标记。
---@param vg any       NanoVG context
---@param heroId number 英雄 ID
---@param cx number    中心 X
---@param cy number    中心 Y
---@param size number  整体尺寸（正方形边长）
---@param alpha number 透明度 0.0~1.0
function DrawUtil.drawShardIcon(vg, heroId, cx, cy, size, alpha)
    if alpha <= 0.01 then return end

    -- 1) 主图标：英雄头像
    local heroImg = DrawUtil._heroIconImgs[heroId]
    if heroImg and heroImg >= 0 then
        DrawUtil.drawImageCentered(vg, heroImg, cx, cy, size, size, alpha)
    end

    -- 2) 左上角碎片角标（53×53 按比例缩放）
    local badgeImg = DrawUtil._shardBadgeImg
    if badgeImg and badgeImg >= 0 then
        -- 角标尺寸：基准 53/160 ≈ 0.33 的 size 比例
        local badgeSize = math.floor(size * 53 / 160 + 0.5)
        local badgeX = cx - size * 0.5 + badgeSize * 0.5
        local badgeY = cy - size * 0.5 + badgeSize * 0.5
        DrawUtil.drawImageCentered(vg, badgeImg, badgeX, badgeY, badgeSize, badgeSize, alpha)
    end
end

-- ============================================================================
-- 缓动函数
-- ============================================================================

--- easeOutBack 缓动（回弹效果）
---@param t number 0~1
---@return number
function DrawUtil.easeOutBack(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

-- ============================================================================
-- drawResonanceMark  —— 共鸣加成小标识（等级徽章右下角）
-- ============================================================================

--- 在等级徽章右下角绘制青色圆点 + “共”字，表示有效等级高于真实等级。
---@param vg any
---@param badgeCX number 等级徽章中心 X
---@param badgeCY number 等级徽章中心 Y
---@param badgeSize number 等级徽章边长
function DrawUtil.drawResonanceMark(vg, badgeCX, badgeCY, badgeSize)
    local markR = badgeSize * 0.22
    local markCX = badgeCX + badgeSize * 0.32
    local markCY = badgeCY + badgeSize * 0.32
    nvgBeginPath(vg)
    nvgCircle(vg, markCX, markCY, markR)
    nvgFillColor(vg, nvgRGBA(64, 160, 240, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    DrawUtil.drawTextStroke(vg, markCX, markCY, "共",
        math.max(12, math.floor(markR * 1.25)),
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        255, 255, 255, 2)
end

return DrawUtil
