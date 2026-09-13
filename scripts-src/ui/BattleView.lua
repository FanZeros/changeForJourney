-- ============================================================================
-- BattleView - 单场战斗的战场渲染组件（Phase 2c / 三栏并行战斗）
-- 职责: 在 1080x2400 设计坐标系内渲染一场战斗的"战场部分"
--       （地图底 + 左右列阴影 + 我4/敌4 卡组 + 飘字 + 特效 + 投射物）
-- 约定: 调用前须 mount 该战斗的状态（BattleCombat/ProjectileSystem/
--       BattleEffects/SEM/ThreatManager/TAL 的 mount），绘制内容即为该战斗。
--       卡面/血条等贴图由 BattleDraw 的共享上下文提供（BattleScene.init 已注入）。
-- 列变换由调用方负责（BattleTriPage 对每栏做 translate/scale/scissor）。
-- ============================================================================

local BattleDraw       = require("ui.BattleDraw")
local BattleEffects    = require("ui.BattleEffects")
local ProjectileSystem = require("ui.ProjectileSystem")
local BattleCombat     = require("ui.BattleCombat")
local BattleLayout     = require("core.BattleLayout")

local BattleView = {}

-- ---- 设计坐标 ----
local DESIGN_W = 1080
local FIELD_TOP = BattleLayout.FIELD_TOP              -- 300（首卡上边缘）
local FIELD_BAND_H = 1830                             -- 战场带高度（与阴影一致）

-- ---- 贴图（仅本组件自有的背景类；幂等）----
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

--- 绘制战场（b = { allies, enemies }；设计坐标系）
---@param vg any
---@param b table { allies, enemies }
function BattleView.draw(vg, b)
    local allies = b.allies or {}
    local enemies = b.enemies or {}

    -- 1) 地图底（覆盖战场带）
    local y0 = FIELD_TOP - 240
    local h0 = FIELD_BAND_H + 480
    if img.map >= 0 then
        local paint = nvgImagePattern(vg, 0, y0, DESIGN_W, h0, 0, img.map, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, y0, DESIGN_W, h0)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, y0, DESIGN_W, h0)
        nvgFillColor(vg, nvgRGBA(28, 30, 38, 255))
        nvgFill(vg)
    end

    -- 2) 左右列阴影
    if img.shadow >= 0 then
        local SH_W = 340
        for _, cx in ipairs({ BattleLayout.ALLY_COL_X, BattleLayout.ENEMY_COL_X }) do
            local sy = BattleLayout.FIELD_CY - FIELD_BAND_H * 0.5
            local paint = nvgImagePattern(vg, cx - SH_W * 0.5, sy, SH_W, FIELD_BAND_H, 0, img.shadow, 0.9)
            nvgBeginPath(vg)
            nvgRect(vg, cx - SH_W * 0.5, sy, SH_W, FIELD_BAND_H)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    end

    -- 3) 卡组（卡内 UI 偏移与 BattleScene 常量一致；baseCY 参数列阵下不使用）
    BattleDraw.drawCardGroup(vg, enemies, nil,
        -215, 90, 153, 135, 181, 215, img.enemyTag, false)
    BattleDraw.drawCardGroup(vg, allies, nil,
        -215, 85, 153, 135, 181, 215, nil, true)

    -- 4) 飘字 / 特效 / 投射物 / 星门（均为 mounted 状态内容）
    BattleDraw.drawFloatingTexts(vg)
    BattleEffects.draw(vg)
    ProjectileSystem.draw(vg)
    ProjectileSystem.drawStarGates(vg, allies, BattleLayout.FIELD_CY,
        BattleCombat.getCardCX, true, BattleCombat.getCardCY)
    ProjectileSystem.drawStarGates(vg, enemies, BattleLayout.FIELD_CY,
        BattleCombat.getCardCX, false, BattleCombat.getCardCY)
end

return BattleView
