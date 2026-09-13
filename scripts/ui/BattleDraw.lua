-- ============================================================================
-- BattleDraw - 战斗场景渲染模块（卡片组/浮动文字/工具绘制函数）
-- 从 BattleScene.lua 提取
-- ============================================================================

local SEM = require("systems.StatusEffectManager")
local TAL = require("systems.TalentManager")
local NumberUtil = require("core.NumberUtil")
local BattleLayout = require("core.BattleLayout")

local BattleDraw = {}

-- ======================== 常量 ========================

local DESIGN_W = 1080

-- 卡片尺寸
local CARD_W, CARD_H = 198, 438
local CARD_SPACING   = 7

-- 职业标签
local TAG_SIZE = 64

-- 血条
local HP_BAR_W, HP_BAR_H = 168, 28
local HP_BAR_PADDING = 4

-- 攻击进度条
local ATK_BAR_W, ATK_BAR_H = 168, 14
local ATK_BAR_PADDING = 4

-- 浮动文字
local FLOAT_TOTAL_FRAMES = 20
local FLOAT_MOVE_DIST    = 240

-- 职业图标映射
local CLASS_ICON_MAP = {
    knight   = 1,
    warrior  = 2,
    mage     = 3,
    ranger   = 4,
    assassin = 5,
    priest   = 6,
}

-- 外部引用（由 setContext 注入）
local combat = nil  -- BattleCombat 模块引用
local imgCtx = {}   -- 图片句柄

-- ======================== 注入上下文 ========================

--- 注入依赖
---@param context table { combat, imgHeroCards, imgMonsterCards, imgHpBg, imgHpFill, imgAtkBg, imgAtkFill, imgAllyTags, imgDeath }
function BattleDraw.setContext(context)
    combat = context.combat
    imgCtx = context
end

-- ======================== 工具绘制函数 ========================

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
BattleDraw.drawImageCentered = drawImageCentered

--- 水平镜像绘制图片
local function drawImageMirrored(vg, img, cx, cy, w, h, alpha)
    if img < 0 or alpha <= 0.01 then return end
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, -1, 1)
    local paint = nvgImagePattern(vg, -w * 0.5, -h * 0.5, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, -w * 0.5, -h * 0.5, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
end
BattleDraw.drawImageMirrored = drawImageMirrored

--- 16 向描边文字
local drawTextStroke = require("core.DrawUtil").drawTextStroke
BattleDraw.drawTextStroke = drawTextStroke

--- 绘制进度条
local function drawProgressBar(vg, imgBg, imgFill, cx, cy, bgW, bgH, padding, progress)
    drawImageCentered(vg, imgBg, cx, cy, bgW, bgH, 1.0)
    local fillW = bgW - padding * 2
    local fillH = bgH - padding * 2
    local fillX = cx - bgW * 0.5 + padding
    local fillY = cy - bgH * 0.5 + padding
    local clipW = fillW * math.max(0, math.min(1, progress))
    if clipW > 0 and imgFill >= 0 then
        nvgSave(vg)
        nvgScissor(vg, fillX, fillY, clipW, fillH)
        local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, imgFill, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, fillX, fillY, fillW, fillH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end
end
BattleDraw.drawProgressBar = drawProgressBar

-- ======================== 卡片组渲染 ========================

--- 绘制卡片组（敌方或己方）
function BattleDraw.drawCardGroup(vg, units, baseCY,
    tagOffY, nameOffY, hpBgOffY, hpValOffY, atkBgOffY, lvlOffY,
    tagImg, isAllyGroup)

    local count = #units
    if count == 0 then return end

    local group = isAllyGroup and "ally" or "enemy"
    local stripMode = (BattleLayout.MODE == "strip")
    local stripCardScale = stripMode and BattleLayout.CARD_SCALE or 1.0

    for idx = 1, count do
        local unit = units[idx]
        local animOff = combat.getCardAnimOffsetY(unit) + combat.getChargeOffsetY(unit, isAllyGroup)
        local cx, cy
        if stripMode then
            -- [三行并行] 条带坐标: 我左/敌右单线, 朝向敌方轴映射到 X
            cx, cy = BattleLayout.cardPos(group, idx)
            cx = cx - animOff
        else
            -- classic: 原竖屏行阵, 朝向敌方轴为 Y
            cx, cy = BattleLayout.cardPos(group, idx, count)
            cy = cy + animOff
        end

        -- 条带内卡牌整体缩放（外层；内层远程蓄力缩放嵌套其上）
        if stripCardScale ~= 1.0 then
            nvgSave(vg)
            nvgTranslate(vg, cx, cy)
            nvgScale(vg, stripCardScale, stripCardScale)
            nvgTranslate(vg, -cx, -cy)
        end

        -- 远程角色卡片缩放（蓄力缩小/攻击放大）
        local cardScale = combat.getCardScale(unit, isAllyGroup)
        local hasScale = math.abs(cardScale - 1.0) > 0.001
        if hasScale then
            nvgSave(vg)
            nvgTranslate(vg, cx, cy)
            nvgScale(vg, cardScale, cardScale)
            nvgTranslate(vg, -cx, -cy)
        end

        local animState = combat.getAnimState(unit)
        local isDying = animState == "dying"
        local isGone = animState == "gone"
        local isTombstoneIn = animState == "tombstone_in"
        local isDead  = unit.hp <= 0
        local isReviving = animState == "reviving"
        local isEntering = animState == "entering"
        local transAlpha = combat.getTransitionAlpha(unit)

        if isGone then
            -- [死亡即补位] 空位期：完全隐藏，等待新怪从右补入
        elseif isDying then
            -- 死亡淡出：显示原卡牌向上/向下滑出
            local cardBgImg
            if unit.heroId then
                cardBgImg = imgCtx.imgHeroCards[unit.heroId] or imgCtx.imgHeroCards[1]
            elseif unit.monsterId then
                cardBgImg = imgCtx.imgMonsterCards[unit.monsterId] or imgCtx.imgMonsterCards[1]
            else
                cardBgImg = imgCtx.imgHeroCards[1]
            end
            drawImageCentered(vg, cardBgImg, cx, cy, CARD_W, CARD_H, transAlpha)

        elseif isDead then
            -- 墓碑渲染
            local tombAlpha = isTombstoneIn and transAlpha or 1.0
            drawImageCentered(vg, imgCtx.imgDeath, cx, cy, CARD_W, CARD_H, tombAlpha)
            if not isAllyGroup and not isTombstoneIn then
                local reviveProg = unit.atkProgress or 0
                drawProgressBar(vg, imgCtx.imgAtkBg, imgCtx.imgAtkFill, cx, cy + atkBgOffY,
                    ATK_BAR_W, ATK_BAR_H, ATK_BAR_PADDING, reviveProg)
            end
        else
            -- 正常存活渲染
            local alpha = (isReviving or isEntering) and transAlpha or 1.0

            -- 1) 卡片背景
            local cardBgImg
            if unit.heroId then
                cardBgImg = imgCtx.imgHeroCards[unit.heroId] or imgCtx.imgHeroCards[1]
            elseif unit.monsterId then
                cardBgImg = imgCtx.imgMonsterCards[unit.monsterId] or imgCtx.imgMonsterCards[1]
            else
                cardBgImg = imgCtx.imgHeroCards[1]
            end
            drawImageCentered(vg, cardBgImg, cx, cy, CARD_W, CARD_H, alpha)

            -- 受击闪烁
            if not isReviving and not isEntering then
                local flashAlpha = combat.getHitFlashAlpha(unit)
                if flashAlpha > 0 then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, cx - CARD_W * 0.5 + 4, cy - CARD_H * 0.5 + 4,
                        CARD_W - 8, CARD_H - 8, 8)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, flashAlpha))
                    nvgFill(vg)
                end
            end

            -- 2) 职业标签
            local actualTag = tagImg
            if isAllyGroup and unit.classId then
                local iconIdx = CLASS_ICON_MAP[unit.classId]
                if iconIdx and imgCtx.imgAllyTags[iconIdx] then
                    actualTag = imgCtx.imgAllyTags[iconIdx]
                end
            end
            drawImageCentered(vg, actualTag, cx, cy + tagOffY, TAG_SIZE, TAG_SIZE, alpha)

            -- 3) 单位名称
            drawTextStroke(vg, cx, cy + nameOffY, unit.name,
                32, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

            -- 4+5) 血条（含白色缓冲拖尾）
            local hpProgress = (unit.maxHp > 0) and (math.max(0, unit.hp) / unit.maxHp) or 0
            local bufProgress = combat.getHpBuffer(unit) or hpProgress
            do
                local bCx, bCy = cx, cy + hpBgOffY
                drawImageCentered(vg, imgCtx.imgHpBg, bCx, bCy, HP_BAR_W, HP_BAR_H, 1.0)

                local fillW = HP_BAR_W - HP_BAR_PADDING * 2
                local fillH = HP_BAR_H - HP_BAR_PADDING * 2
                local fillX = bCx - HP_BAR_W * 0.5 + HP_BAR_PADDING
                local fillY = bCy - HP_BAR_H * 0.5 + HP_BAR_PADDING

                if bufProgress > hpProgress then
                    local bufClipW = fillW * math.max(0, math.min(1, bufProgress))
                    if bufClipW > 0 then
                        nvgBeginPath(vg)
                        nvgRect(vg, fillX, fillY, bufClipW, fillH)
                        nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
                        nvgFill(vg)
                    end
                end

                local clipW = fillW * math.max(0, math.min(1, hpProgress))
                if clipW > 0 and imgCtx.imgHpFill >= 0 then
                    nvgSave(vg)
                    nvgScissor(vg, fillX, fillY, clipW, fillH)
                    local paint = nvgImagePattern(vg, fillX, fillY, fillW, fillH, 0, imgCtx.imgHpFill, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, fillX, fillY, fillW, fillH)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                    nvgResetScissor(vg)
                    nvgRestore(vg)
                end

                -- 能量护盾：血条尾部延伸段（不叠加在血量上）——
                -- [HP 段][常规 ES 青段][临时 ES 亮青段][空]，均按 maxHp 百分比刻度；
                -- 盾+血未满时盾跟在血量后面，总宽不超过整条
                local esMax = unit.attrs and (unit.attrs.final["energyShield"] or 0) or 0
                if esMax > 0 and imgCtx.imgEsFill and imgCtx.imgEsFill >= 0 then
                    local esCur = unit.attrs.energyShield or 0
                    local tempCur = unit.attrs.tempEnergyShield or 0
                    local barScale = (unit.maxHp > 0) and unit.maxHp or esMax
                    local hpClipW = fillW * math.max(0, math.min(1, hpProgress))
                    local esClipW = fillW * math.max(0, math.min(1, esCur / barScale))
                    local esRoom = fillW - hpClipW
                    if esClipW > esRoom then esClipW = esRoom end
                    if esClipW > 0 then
                        local esX = fillX + hpClipW
                        nvgSave(vg)
                        nvgScissor(vg, esX, fillY, esClipW, fillH)
                        local esPaint = nvgImagePattern(vg, esX, fillY, esClipW, fillH, 0, imgCtx.imgEsFill, 0.85)
                        nvgBeginPath(vg)
                        nvgRect(vg, esX, fillY, esClipW, fillH)
                        nvgFillPaint(vg, esPaint)
                        nvgFill(vg)
                        nvgResetScissor(vg)
                        nvgRestore(vg)
                    end
                    -- 临时护盾跟在常规护盾之后（更亮的青色，同一刻度，同样不越界）
                    if tempCur > 0 then
                        local tempClipW = fillW * math.max(0, math.min(1, tempCur / barScale))
                        local tempX = fillX + hpClipW + esClipW
                        local tempRoom = fillW - hpClipW - esClipW
                        if tempClipW > tempRoom then tempClipW = tempRoom end
                        if tempClipW > 1 then
                            nvgSave(vg)
                            nvgScissor(vg, tempX, fillY, tempClipW, fillH)
                            nvgBeginPath(vg)
                            nvgRect(vg, tempX, fillY, fillW, fillH)
                            nvgFillColor(vg, nvgRGBA(160, 255, 255, 150))
                            nvgFill(vg)
                            nvgResetScissor(vg)
                            nvgRestore(vg)
                        end
                    end
                end
            end

            -- 6) 血量数值 + 能量护盾数值（常规 ES + 临时 ES 分色）
            local hpText = NumberUtil.format(math.max(0, unit.hp))
            local esCur = unit.attrs and (unit.attrs.energyShield or 0) or 0
            local tempCur = unit.attrs and (unit.attrs.tempEnergyShield or 0) or 0
            local esMaxVal = unit.attrs and (unit.attrs.final["energyShield"] or 0) or 0
            if esMaxVal > 0 and (esCur > 0 or tempCur > 0) then
                local esText = esCur > 0 and ("+" .. NumberUtil.format(math.floor(esCur))) or ""
                local tempText = tempCur > 0 and ("+" .. NumberUtil.format(math.floor(tempCur))) or ""
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 28)
                local hpW = nvgTextBounds(vg, 0, 0, hpText)
                local esW = esText ~= "" and nvgTextBounds(vg, 0, 0, esText) or 0
                local tempW = tempText ~= "" and nvgTextBounds(vg, 0, 0, tempText) or 0
                local totalW = hpW + esW + tempW
                local startX = cx - totalW * 0.5
                drawTextStroke(vg, startX + hpW * 0.5, cy + hpValOffY, hpText,
                    28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
                local shieldX = startX + hpW
                if esText ~= "" then
                    drawTextStroke(vg, shieldX + esW * 0.5, cy + hpValOffY, esText,
                        28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 0x45, 0xEF, 0xFE, 4)
                    shieldX = shieldX + esW
                end
                if tempText ~= "" then
                    drawTextStroke(vg, shieldX + tempW * 0.5, cy + hpValOffY, tempText,
                        28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 120, 255, 255, 4)
                end
            else
                drawTextStroke(vg, cx, cy + hpValOffY, hpText,
                    28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
            end

            -- 7+8) 攻击进度条
            local attackProg = unit.atkProgressVisual
            if attackProg == nil then attackProg = unit.atkProgress end
            drawProgressBar(vg, imgCtx.imgAtkBg, imgCtx.imgAtkFill, cx, cy + atkBgOffY,
                ATK_BAR_W, ATK_BAR_H, ATK_BAR_PADDING, attackProg)

            -- 9) 等级文本
            drawTextStroke(vg, cx, cy + lvlOffY, "Lv." .. tostring(unit.level),
                32, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)

            -- 10) 状态效果视觉指示
            local visuals = SEM.getVisuals(unit)
            if #visuals > 0 then
                local v1 = visuals[1]
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - CARD_W * 0.5 + 4, cy - CARD_H * 0.5 + 4,
                    CARD_W - 8, CARD_H - 8, 8)
                nvgFillColor(vg, nvgRGBA(v1.r, v1.g, v1.b, 40))
                nvgFill(vg)
                for vi, vis in ipairs(visuals) do
                    drawTextStroke(vg, cx - CARD_W * 0.5 + 28, cy - CARD_H * 0.5 + 28 + (vi - 1) * 36,
                        vis.icon, 28, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, vis.r, vis.g, vis.b, 3)
                end
            end

            -- 11) 征服层数（叠甲怪）
            local conqStacks = TAL.getConquerStacks(unit)
            if conqStacks > 0 then
                drawTextStroke(vg, cx + CARD_W * 0.5 - 28, cy - CARD_H * 0.5 + 28,
                    "征" .. tostring(conqStacks), 24, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 200, 50, 3)
            end
        end

        -- 关闭远程角色缩放变换
        if hasScale then
            nvgRestore(vg)
        end
        -- 关闭条带整体卡牌缩放
        if stripCardScale ~= 1.0 then
            nvgRestore(vg)
        end
    end
end

-- ======================== 浮动文字渲染 ========================

function BattleDraw.drawFloatingTexts(vg)
    local texts = combat.getFloatingTexts()
    for _, ft in ipairs(texts) do
        local frame = (ft.timer / ft.duration) * FLOAT_TOTAL_FRAMES
        local t = frame / FLOAT_TOTAL_FRAMES

        local drawX = ft.x + ft.dirX * FLOAT_MOVE_DIST * t
        local drawY = ft.y + ft.dirY * FLOAT_MOVE_DIST * t

        local scale = 1.0 - 0.75 * t
        local fontSize = math.max(1, math.floor(ft.fontSize * scale))

        local alpha
        if frame <= 10 then
            alpha = math.floor(255 * (frame / 10))
        elseif frame <= 15 then
            alpha = 255
        else
            alpha = math.floor(255 * (1.0 - (frame - 15) / 5))
        end
        alpha = math.max(0, math.min(255, alpha))

        if alpha > 0 then
            nvgSave(vg)
            nvgGlobalAlpha(vg, alpha / 255)
            drawTextStroke(vg, drawX, drawY, ft.text,
                fontSize, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
                ft.color[1], ft.color[2], ft.color[3], 5)
            nvgRestore(vg)
        end
    end
end

return BattleDraw
