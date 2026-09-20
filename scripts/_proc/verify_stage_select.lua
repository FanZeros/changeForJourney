-- ============================================================================
-- verify_stage_select.lua — 选关弹窗 v2 布局验证（headless 截图）
-- mock BattleScene 进度（maxStage=305, current=203）→ 打开选关 → 每帧绘制
-- 跑法: ./.cli/UrhoXRuntime scripts/_proc/verify_stage_select.lua -tool_mode \
--   -graphicssurfaceless -screenshot=/abs/xxx.png -screenshot-frame=30 -x 1080 -y 1400
-- ============================================================================

package.loaded["ui.BattleScene"] = {
    getMaxStageId = function() return 305 end,
    getStageId = function() return 203 end,
    gotoStage = function(id) print("[mock] gotoStage " .. tostring(id)) return true end,
}

local StageSelectDialog = require("ui.StageSelectDialog")

local nvg = nil
local vgOk = false

local function onRender(evt, data)
    if not nvg then
        nvg = nvgCreate(1)
        if not nvg then
            print("[verify] ERROR nvgCreate failed")
            return
        end
        nvgCreateFont(nvg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
        StageSelectDialog.init(nvg)
        StageSelectDialog.open()
        vgOk = true
        print("[verify] nvg ready, dialog opened")
    end
    if not vgOk then return end
    local W, H = 1080, 1400
    nvgBeginFrame(nvg, W, H, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, W, H)
    nvgFillColor(nvg, nvgRGBA(16, 16, 22, 255))
    nvgFill(nvg)
    -- 模拟三行页弹窗变换：设计锚点 (540,1195) 对齐窗口中心
    local fit = math.min(W / 1080, H / 1200)
    nvgSave(nvg)
    nvgScissor(nvg, 0, 0, W, H)
    nvgTranslate(nvg, W * 0.5, H * 0.5)
    nvgScale(nvg, fit, fit)
    nvgTranslate(nvg, -540, -1195)
    StageSelectDialog.draw(nvg)
    nvgRestore(nvg)
    nvgEndFrame(nvg)
end

function Start()
    print("[verify_stage_select] start")
    SubscribeToEvent("NanoVGRender", "onRender")
end
