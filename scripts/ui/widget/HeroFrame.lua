-- ============================================================================
-- HeroFrame - 统一角色框组件（feat926/unified-character-frame）
-- ----------------------------------------------------------------------------
-- 全游戏"英雄头像/卡牌"框体的唯一绘制入口，替代散落在 20+ 文件中的
-- 13 种框风格。视觉基准 = 原编队头像框（CharacterPanelDraw2.drawAvatarSlot）：
--   圆角深底 + 品质色描边 + 等级徽章/职业图标/碎片条/队伍标签角标 + 交互高亮
--
-- 品质色唯一色源：HeroConfig.QUALITY_INFO（普通灰/稀有紫蓝/史诗金/传说橙红）。
-- 装备品质框（DarkIcon.drawQualityBg / ZBBJ 贴图 1~6）仅用于装备与道具，不复用。
--
-- 用法：
--   local HeroFrame = require("ui.widget.HeroFrame")
--   HeroFrame.initImages(vg)            -- 每个 vg 生命周期一次（角标贴图）
--   HeroFrame.draw(vg, { cx=..., cy=..., size=148, heroId=3, showLevel=true, level=12 })
-- ============================================================================

local HC = require("config.HeroConfig")
local HeroAssetUtil = require("config.HeroAssetUtil")
local DrawUtil = require("core.DrawUtil")

local drawImageCentered = DrawUtil.drawImageCentered
local drawTextStroke    = DrawUtil.drawTextStroke

local M = {}

-- ======================== 统一色板 ========================

--- 框体统一金（非品质元素：队伍标签、选中态等）
M.GOLD     = { 212, 175, 90 }
M.GOLD_HI  = { 255, 214, 102 }   -- 选中/拖拽高亮金
M.GREEN_HI = { 99, 255, 132 }    -- 拖拽放置目标绿
M.BASE_BG  = { 20, 16, 12 }      -- 有角色时的框底
M.EMPTY_BG_A, M.LOCK_BG_A = 60, 90
M.EMPTY_BORDER = { 120, 100, 70 }

--- 职业 classId → 职业图标序号（全局唯一定义，替代各面板本地副本）
M.CLASS_ICON_MAP = {
    knight = 1, seal = 1,
    warrior = 2, spoil = 2,
    mage = 3, rift = 3,
    ranger = 4, echo = 4,
    assassin = 5, mask = 5,
    priest = 6, debt = 6,
}

--- 英雄品质(1~4) → RGB。唯一映射入口，禁止调用方自维护色表。
---@param quality number
---@return number r, number g, number b
function M.qualityColor(quality)
    return HC.getQualityColorRGB(quality)
end

-- ======================== 角标贴图（全局一份） ========================

---@class HeroFrameImages
---@field vg any
---@field lvlBadge integer
---@field lock integer
---@field plus integer
---@field iconUp integer
---@field shardSp integer
---@field classIcons table<integer, integer>

---@type HeroFrameImages
local img = {
    vg = nil,
    lvlBadge = -1,
    lock = -1,
    plus = -1,
    iconUp = -1,
    shardSp = -1,
    classIcons = {},
}
local imgReadyVg = nil

--- 加载角标贴图（幂等：同一 vg 只加载一次）
---@param vg any
function M.initImages(vg)
    if imgReadyVg == vg then return end
    imgReadyVg = vg
    img.vg = vg
    if img.lvlBadge < 0 then
        img.lvlBadge  = nvgCreateImage(vg, "image/界面底板/角色与觉醒/UI_JSJM_DJ.png", 0) or -1
        img.lock      = nvgCreateImage(vg, "image/通用图标/UI_ICON_SUO.png", 0) or -1
        img.plus      = nvgCreateImage(vg, "image/通用图标/UI_ICON_JIA.png", 0) or -1
        img.iconUp    = nvgCreateImage(vg, "image/通用图标/ICON_UP.png", 0) or -1
        img.shardSp   = nvgCreateImage(vg, "image/货币道具/ICON_SP.png", 0) or -1
        for i = 1, 6 do
            img.classIcons[i] = nvgCreateImage(vg, "image/通用图标/ICON_ZY_" .. i .. ".png", 0) or -1
        end
    end
end

--- 共享句柄（供仍自行绘制徽章的旧面板过渡复用）
---@return HeroFrameImages
function M.getImages()
    return img
end

-- ======================== opts 类型 ========================

---@class HeroFrameOpts
---@field cx number 中心 X
---@field cy number 中心 Y
---@field size number|nil 正方形边长（与 w/h 二选一）
---@field w number|nil 宽（卡牌模式）
---@field h number|nil 高（卡牌模式）
---@field radius number|nil 圆角，默认 min(w,h)*0.09
---@field heroId number|nil 有则自动取头像与品质
---@field iconHandle integer|nil 已加载头像句柄（优先于内部缓存）
---@field state string|nil "owned"|"unowned"|"empty"|"locked"，默认按 heroId/owned 推断
---@field owned boolean|nil heroId 存在时是否已拥有（默认 true）
---@field quality number|nil 覆盖品质
---@field showLevel boolean|nil 左下等级徽章
---@field level number|nil 等级数值
---@field showClass boolean|nil 右下职业图标（需 heroId 或 classId）
---@field classId string|nil 职业 id（无 heroId 时供职业图标用）
---@field showShards boolean|nil 未拥有时底部碎片进度条
---@field shards number|nil 当前碎片数
---@field shardMax number|nil 合成所需碎片（默认 10）
---@field showTeamTag boolean|nil 左上队伍标签
---@field teamTag string|nil 标签文字（默认 "队"）
---@field showUpgrade boolean|nil 右上可提升角标
---@field selected boolean|nil 金色选中高亮
---@field dragSource boolean|nil 拖拽源：半透明头像 + 金高亮
---@field hoverTarget boolean|nil 拖拽放置目标绿框
---@field lockOverlay boolean|nil 未拥有时叠加黑罩+锁图标（头像选择格用）
---@field posLabel string|nil 顶部站位名
---@field nameLabel string|nil 底部名字
---@field frameOnly boolean|nil 只画品质描边与角标，不画底与头像（整卡卡面叠加用）
---@field borderOverride table|nil {r,g,b,a,width} 覆盖描边（如他人已装备白边）
---@field alpha number|nil 整体透明度，默认 1

-- ======================== 绘制 ========================

--- 圆角裁剪内画头像（cover 充满）
local function drawIconClipped(vg, icon, x, y, w, h, r, alpha)
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgIntersectScissor(vg, x, y, w, h)
    drawImageCentered(vg, icon, x + w * 0.5, y + h * 0.5, w, h, alpha)
    nvgRestore(vg)
end

--- 统一角色框绘制主入口
---@param vg any
---@param opts HeroFrameOpts
function M.draw(vg, opts)
    local alpha = opts.alpha or 1
    if alpha <= 0.01 then return end
    M.initImages(vg)

    local cx, cy = opts.cx, opts.cy
    local w = opts.w or opts.size or 0
    local h = opts.h or opts.size or 0
    if w <= 0 or h <= 0 then return end
    local x, y = cx - w * 0.5, cy - h * 0.5
    local side = math.min(w, h)
    local r = opts.radius or math.floor(side * 0.09)

    local heroId = opts.heroId
    local state = opts.state
    if not state then
        if not heroId then
            state = "empty"
        elseif opts.owned == false then
            state = "unowned"
        else
            state = "owned"
        end
    end
    local occupied = state == "owned" or state == "unowned"

    -- 品质：显式覆盖 > 查配置 > 默认灰
    local quality = opts.quality
    if not quality and heroId then
        local cfg = HC.get(heroId)
        quality = cfg and cfg.quality or 1
    end
    quality = quality or 1
    local qr, qg, qb = M.qualityColor(quality)

    -- ① 交互高亮（框体外扩描边，先画在底层）
    if opts.dragSource or opts.selected then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - 4, y - 4, w + 8, h + 8, r + 4)
        nvgStrokeColor(vg, nvgRGBA(M.GOLD_HI[1], M.GOLD_HI[2], M.GOLD_HI[3], math.floor(alpha * 255)))
        nvgStrokeWidth(vg, 5)
        nvgStroke(vg)
    elseif opts.hoverTarget then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - 3, y - 3, w + 6, h + 6, r + 3)
        nvgStrokeColor(vg, nvgRGBA(M.GREEN_HI[1], M.GREEN_HI[2], M.GREEN_HI[3], math.floor(alpha * 230)))
        nvgStrokeWidth(vg, 4)
        nvgStroke(vg)
    end

    if not opts.frameOnly then
        -- ② 底
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, r)
        if occupied then
            nvgFillColor(vg, nvgRGBA(M.BASE_BG[1], M.BASE_BG[2], M.BASE_BG[3], math.floor(alpha * 255)))
        elseif state == "locked" then
            nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * M.LOCK_BG_A)))
        else
            nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * M.EMPTY_BG_A)))
        end
        nvgFill(vg)

        -- ③ 头像 / 空位符号
        if occupied and heroId then
            local icon = opts.iconHandle
            if (not icon or icon < 0) then
                icon = HeroAssetUtil.ensureIcon(img.vg or vg, M._iconCache, heroId)
            end
            if icon and icon >= 0 then
                local iconAlpha = alpha * (state == "unowned" and 0.45 or 1)
                if opts.dragSource then iconAlpha = alpha * 0.45 end
                drawIconClipped(vg, icon, x, y, w, h, r, iconAlpha)
            end
            if opts.lockOverlay and state == "unowned" then
                nvgSave(vg)
                nvgIntersectScissor(vg, x, y, w, h)
                nvgBeginPath(vg)
                nvgRect(vg, x, y, w, h)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 100)))
                nvgFill(vg)
                nvgRestore(vg)
                if img.lock >= 0 then
                    drawImageCentered(vg, img.lock, cx, cy, side * 0.31, side * 0.31, alpha * 0.9)
                end
            end
        elseif state == "locked" then
            if img.lock >= 0 then
                drawImageCentered(vg, img.lock, cx, cy, side * 0.36, side * 0.36, alpha * 0.85)
            end
        elseif state == "empty" then
            if img.plus >= 0 then
                drawImageCentered(vg, img.plus, cx, cy, side * 0.36, side * 0.36, alpha * 0.9)
            else
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, side * 0.32)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(160, 145, 120, math.floor(alpha * 200)))
                nvgText(vg, cx, cy, "+", nil)
            end
        end
    end

    -- ④ 描边：品质色（occupied）/ 暗棕（空与锁）/ 覆盖色
    local bw = math.max(2, side * 0.02)
    if opts.borderOverride then
        local bo = opts.borderOverride
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, r)
        nvgStrokeColor(vg, nvgRGBA(bo[1], bo[2], bo[3], math.floor(alpha * (bo[4] or 200))))
        nvgStrokeWidth(vg, bo[5] or 2)
        nvgStroke(vg)
    elseif occupied then
        local ba = state == "owned" and 230 or 90
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, r)
        nvgStrokeColor(vg, nvgRGBA(qr, qg, qb, math.floor(alpha * ba)))
        nvgStrokeWidth(vg, state == "owned" and math.max(3, bw) or 2)
        nvgStroke(vg)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, r)
        nvgStrokeColor(vg, nvgRGBA(M.EMPTY_BORDER[1], M.EMPTY_BORDER[2], M.EMPTY_BORDER[3],
            math.floor(alpha * (state == "locked" and 90 or 160))))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- ⑤ 角标（occupied 才画业务角标）
    if occupied then
        -- 等级徽章（左下）
        if opts.showLevel then
            local bs = side * 0.30
            local bcx = x + side * 0.115
            local bcy = y + h - side * 0.115
            if img.lvlBadge >= 0 then
                drawImageCentered(vg, img.lvlBadge, bcx, bcy, bs, bs, alpha)
            else
                nvgBeginPath(vg)
                nvgCircle(vg, bcx, bcy, bs * 0.5)
                nvgFillColor(vg, nvgRGBA(18, 14, 10, math.floor(alpha * 220)))
                nvgFill(vg)
            end
            drawTextStroke(vg, bcx, bcy, tostring(opts.level or 1),
                math.floor(side * 0.15), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                255, 255, 255, 3, { alpha = alpha })
        end

        -- 职业图标（右下）
        if opts.showClass then
            local classId = opts.classId
            if not classId and heroId then
                local cfg = HC.get(heroId)
                classId = cfg and cfg.classId or nil
            end
            local idx = classId and M.CLASS_ICON_MAP[classId] or nil
            local cicon = idx and img.classIcons[idx] or nil
            if cicon and cicon >= 0 then
                local cs = side * 0.30
                drawImageCentered(vg, cicon, x + w - side * 0.115, y + h - side * 0.115, cs, cs, alpha)
            end
        end

        -- 碎片进度条（未拥有，底部内嵌）
        if opts.showShards and state == "unowned" then
            local shards = opts.shards or 0
            if shards > 0 then
                local shardMax = opts.shardMax or HC.SHARD_SYNTHESIZE_COST or 10
                local canSynth = shards >= shardMax
                local barW, barH = side * 0.62, side * 0.12
                local barCX = cx + side * 0.095
                local barCY = y + h - side * 0.11
                nvgBeginPath(vg)
                nvgRoundedRect(vg, barCX - barW * 0.5, barCY - barH * 0.5, barW, barH, barH * 0.33)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 170)))
                nvgFill(vg)
                local fillW = (barW - 4) * math.min(1, shards / shardMax)
                if fillW > 0 then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, barCX - barW * 0.5 + 2, barCY - barH * 0.5 + 2,
                        fillW, barH - 4, (barH - 4) * 0.33)
                    if canSynth then
                        nvgFillColor(vg, nvgRGBA(0x44, 0xff, 0x5e, math.floor(alpha * 230)))
                    else
                        nvgFillColor(vg, nvgRGBA(0xc9, 0x97, 0x3b, math.floor(alpha * 230)))
                    end
                    nvgFill(vg)
                end
                if img.shardSp >= 0 then
                    drawImageCentered(vg, img.shardSp, x + side * 0.11, barCY, side * 0.175, side * 0.175, alpha)
                end
                drawTextStroke(vg, barCX, barCY, shards .. "/" .. shardMax,
                    math.floor(side * 0.11), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                    255, 255, 255, 2, { alpha = alpha })
                if canSynth then
                    drawTextStroke(vg, cx, y + side * 0.135, "可合成",
                        math.floor(side * 0.135), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                        0x44, 0xff, 0x5e, 3, { alpha = alpha })
                end
            end
        end

        -- 队伍标签（左上）
        if opts.showTeamTag then
            local tag = opts.teamTag or "队"
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.floor(side * 0.13))
            local tw = nvgTextBounds(vg, 0, 0, tag)
            local th = side * 0.19
            local tx, ty = x + 4, y + 4
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx, ty, tw + 12, th, 7)
            nvgFillColor(vg, nvgRGBA(18, 14, 10, math.floor(alpha * 220)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(M.GOLD_HI[1], M.GOLD_HI[2], M.GOLD_HI[3], math.floor(alpha * 230)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 214, 102, math.floor(alpha * 255)))
            nvgText(vg, tx + 6, ty + th * 0.5, tag, nil)
        end

        -- 可提升角标（右上）
        if opts.showUpgrade and img.iconUp >= 0 then
            local us = side * 0.24
            drawImageCentered(vg, img.iconUp, x + w - us * 0.5 - 2, y + us * 0.5 + 2, us, us, alpha)
        end
    end

    -- ⑥ 站位名（顶部）/ 名字（底部）
    if opts.posLabel then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(side * 0.115))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 214, 120, math.floor(alpha * (occupied and 235 or 170))))
        nvgText(vg, cx, y - side * 0.09, opts.posLabel, nil)
    end
    if opts.nameLabel then
        drawTextStroke(vg, cx, y + h + side * 0.15, opts.nameLabel,
            math.floor(side * 0.135), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
            255, 255, 255, 3, { alpha = alpha })
    end
end

--- 头像按需缓存（HeroFrame 自有，独立于各面板缓存）
---@type table<number, integer>
M._iconCache = {}

--- 命中检测（矩形）
---@param px number
---@param py number
---@param cx number
---@param cy number
---@param w number
---@param h number
---@return boolean
function M.hitTest(px, py, cx, cy, w, h)
    return DrawUtil.hitTest(px, py, cx, cy, w, h)
end

return M
