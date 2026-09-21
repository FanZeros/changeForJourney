-- ============================================================================
-- BattleTransitionHud - 寻怪 / 战败 / 轮回 / 胜利 过渡层绘制
-- 从 BattleScene.draw 抽出，不拥有计时状态
-- ============================================================================

local M = {}

local SEARCH_ENEMY_DURATION = 3.0
local REINCARNATION_DELAY = 2.0

---@class BattleTransitionHudCtx
---@field battleActive boolean
---@field reincarnationTimer number|nil
---@field searchingTimer number|nil
---@field defeatTimer number|nil
---@field defeatByTimeout boolean
---@field stageName string
---@field currentStageId number
---@field getStageConfig fun(): table
---@field drawTextStroke fun(...)

--- 战斗未进行时的中央提示（轮回/寻怪/失败/胜利）
---@param vg userdata
---@param ctx BattleTransitionHudCtx
function M.draw(vg, ctx)
    if ctx.battleActive then return end

    local drawTextStroke = ctx.drawTextStroke

    if ctx.reincarnationTimer ~= nil then
        local progress = math.min(1, ctx.reincarnationTimer / REINCARNATION_DELAY)
        local pulse = 0.6 + 0.4 * math.sin(ctx.reincarnationTimer * 4)
        local alpha = math.floor(180 * pulse)
        drawTextStroke(vg, 540, 1170, "轮回", 80,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 160, 255, 6)
        local BAR_W, BAR_H = 360, 28
        local BAR_X = 540 - BAR_W * 0.5
        local BAR_Y = 1230
        nvgBeginPath(vg)
        nvgRoundedRect(vg, BAR_X, BAR_Y, BAR_W, BAR_H, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)
        if progress > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, BAR_X + 2, BAR_Y + 2, (BAR_W - 4) * progress, BAR_H - 4, 5)
            nvgFillColor(vg, nvgRGBA(180, 140, 255, alpha))
            nvgFill(vg)
        end
        local stageConfig = ctx.getStageConfig()
        local nextTargetId = stageConfig.getReincarnationTarget(stageConfig.getDifficulty(ctx.currentStageId))
        local nextDiff = nextTargetId and stageConfig.getDifficulty(nextTargetId) or nil
        local diffName = nextDiff and stageConfig.getDifficultyDisplayName(nextDiff) or "未知"
        drawTextStroke(vg, 540, BAR_Y + BAR_H + 20, "即将进入" .. diffName .. "难度...", 30,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 200, 255, 3)
    elseif ctx.searchingTimer ~= nil then
        local progress = math.min(1, ctx.searchingTimer / SEARCH_ENEMY_DURATION)
        local BAR_W, BAR_H = 400, 36
        local BAR_X = 540 - BAR_W * 0.5
        local BAR_Y = 1190
        nvgBeginPath(vg)
        nvgRoundedRect(vg, BAR_X, BAR_Y, BAR_W, BAR_H, 8)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)
        if progress > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, BAR_X + 3, BAR_Y + 3, (BAR_W - 6) * progress, BAR_H - 6, 6)
            nvgFillColor(vg, nvgRGBA(100, 200, 255, 220))
            nvgFill(vg)
        end
        drawTextStroke(vg, 540, BAR_Y + BAR_H * 0.5, "寻怪中...", 32,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 3)
    elseif ctx.defeatTimer ~= nil then
        local failText = ctx.defeatByTimeout and "时间到\!" or "失败..."
        drawTextStroke(vg, 540, 1190, failText, 72,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 200, 80, 80, 6)
        drawTextStroke(vg, 540, 1250, ctx.stageName, 36,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 220, 220, 220, 4)
    else
        drawTextStroke(vg, 540, 1190, "胜利\!", 72,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 220, 50, 6)
        drawTextStroke(vg, 540, 1250, ctx.stageName, 36,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 220, 220, 220, 4)
    end
end

return M
