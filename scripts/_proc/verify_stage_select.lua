-- 选关真实离屏验收：使用正式字体/卡面/章节图，不修改存档或战斗规则。
-- -review-stage=32301 -review-offset=160 -review-lang=en 可冻结要验收的页面状态。
local Dialog = require("ui.battle.stage.StageSelectDialog")
local I18n = require("core.I18n")

---@type NVGContextWrapper|nil
local vg = nil
local stageId, offset, language = 32301, 0, "zh_CN"
local section = "main"
local opened = false

function Start()
    for _, argument in ipairs(GetArguments()) do
        stageId = tonumber(argument:match("^%-review%-stage=(%d+)$")) or stageId
        offset = tonumber(argument:match("^%-review%-offset=(%d+)$")) or offset
        language = argument:match("^%-review%-lang=(.+)$") or language
        section = argument:match("^%-review%-section=(.+)$") or section
    end
    local originalRequire = require
    local battle = {
        getMaxStageId = function() return 32305 end,
        getStageId = function() return stageId end,
        getClearedStages = function() return {} end,
        gotoStage = function(id) print("[verify_stage_select] 意外切关: " .. tostring(id)); return false end,
    }
    require = function(name)
        if name == "ui.battle.scene.BattleScene" then return battle end
        return originalRequire(name)
    end
    I18n.set(language)
    vg = nvgCreate(1)
    assert(vg, "选关验收图形上下文创建失败")
    local font = nvgCreateFont(vg, "sans", "Fonts/ResourceHanRoundedCN-Heavy.ttf")
    assert(font >= 0, "选关验收字体加载失败")
    I18n.installDrawHook()
    Dialog.init(vg)
    Dialog.open()
    if section == "dungeon" then Dialog.handleInput(635, 686) end
    if offset > 0 then
        local rowY = 790 + 4 * 178 + 62
        Dialog.handleDragBegin(700, rowY)
        Dialog.handleDragMove(700 - offset, rowY)
        Dialog.handleDragEnd()
    end
    opened = true
    SubscribeToEvent("NanoVGRender", "HandleStageSelectReviewRender")
    print(string.format("[verify_stage_select] 页面=%d 偏移=%d 语言=%s", stageId, offset, language))
end

function HandleStageSelectReviewRender()
    if not vg or not opened then return end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(vg, width, height, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(16, 16, 22, 255))
    nvgFill(vg)
    -- 与三行页同一设计空间和中心锚点；保留父窗口DPR，使用contain缩放。
    local fit = math.min(width / 1080, height / 1200)
    nvgSave(vg)
    nvgScissor(vg, 0, 0, width, height)
    nvgTranslate(vg, width * 0.5, height * 0.5)
    nvgScale(vg, fit, fit)
    nvgTranslate(vg, -540, -1195)
    Dialog.draw(vg)
    nvgRestore(vg)
    nvgEndFrame(vg)
end

function Stop()
    Dialog.close()
    if vg then nvgDelete(vg); vg = nil end
end
