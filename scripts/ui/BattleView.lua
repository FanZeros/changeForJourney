-- ============================================================================
-- BattleView - 单场战斗的条带渲染组件（三行并行战斗）
-- 职责: 在 948x360 条带设计空间（窗口像素 1:1）内渲染一场战斗:
--       地图底带 + 我方/敌方线后侧阴影 + 我4/敌4 单线卡组 + 飘字/特效/投射物
-- 约定: 调用前须 BattleLayout.setMode("strip") 并 mount 该战斗的状态
--       （BattleCombat/ProjectileSystem/BattleEffects/SEM/ThreatManager/TAL）。
--       卡面/血条贴图由 BattleDraw 共享上下文提供（BattleScene.init 已注入）。
-- ============================================================================

local BattleDraw       = require("ui.BattleDraw")
local BattleEffects    = require("ui.BattleEffects")
local ProjectileSystem = require("ui.ProjectileSystem")
local BattleCombat     = require("ui.BattleCombat")
local BattleLayout     = require("core.BattleLayout")

local BattleView = {}

local STRIP_W = BattleLayout.STRIP_W   -- 948
local STRIP_H = BattleLayout.STRIP_H   -- 360

-- ---- 贴图（幂等）----
local img = { loaded = false, map = -1, shadow = -1, enemyTag = -1 }

--- 初始化贴图（幂等）
---@param vg any
function BattleView.init(vg)
    if img.loaded then return end
    img.loaded   = true
    img.map      = nvgCreateImage(vg, "image/关卡地图/MAP_1.png", 0)
    img.shadow   = nvgCreateImage(vg, "image/UI_YWJM_MAPYY.png", 0)
    img.enemyTag = nvgCreateImage(vg, "image/ICON_ZY_XG.png", 0)
end

--- 绘制一条战斗条带（b = { allies, enemies }；条带设计坐标 948x360）
---@param vg any
---@param b table { allies, enemies }
function BattleView.draw(vg, b)
    local allies = b.allies or {}
    local enemies = b.enemies or {}

    -- 1) 地图底带（拉伸铺满条带）
    if img.map >= 0 then
        local paint = nvgImagePattern(vg, 0, 0, STRIP_W, STRIP_H, 0, img.map, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, STRIP_W, STRIP_H)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, STRIP_W, STRIP_H)
        nvgFillColor(vg, nvgRGBA(28, 30, 38, 255))
        nvgFill(vg)
    end

    -- 2) 两侧阵营底影（各覆盖己方/敌方卡线区域）
    if img.shadow >= 0 then
        local shH = BattleLayout.CARD_H * BattleLayout.CARD_SCALE + 24   -- ≈234
        local shY = BattleLayout.STRIP_CY - shH * 0.5
        local sides = {
            { x = 0,                                     w = BattleLayout.STRIP_W * 0.5 },
            { x = BattleLayout.STRIP_W * 0.5,            w = BattleLayout.STRIP_W * 0.5 },
        }
        for _, sd in ipairs(sides) do
            local paint = nvgImagePattern(vg, sd.x, shY, sd.w, shH, 0, img.shadow, 0.85)
            nvgBeginPath(vg)
            nvgRect(vg, sd.x, shY, sd.w, shH)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    end

    -- 3) 卡组（我左单线 / 敌右单线；卡内 UI 偏移沿用 BattleScene 常量）
    BattleDraw.drawCardGroup(vg, enemies, nil,
        -215, 90, 153, 135, 181, 215, img.enemyTag, false)
    BattleDraw.drawCardGroup(vg, allies, nil,
        -215, 85, 153, 135, 181, 215, nil, true)

    -- 4) 飘字 / 特效 / 投射物 / 星门（均为 mounted 状态内容；坐标即条带坐标）
    BattleDraw.drawFloatingTexts(vg)
    BattleEffects.draw(vg)
    ProjectileSystem.draw(vg)
    ProjectileSystem.drawStarGates(vg, allies, BattleLayout.STRIP_CY,
        BattleCombat.getCardCX, true, BattleCombat.getCardCY)
    ProjectileSystem.drawStarGates(vg, enemies, BattleLayout.STRIP_CY,
        BattleCombat.getCardCX, false, BattleCombat.getCardCY)
end

return BattleView
