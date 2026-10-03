-- 关卡显示边界回归：使用真实词典，模拟绘制与单机战斗依赖。
local failed, passed = 0, 0
local function check(ok, name)
    if ok then passed = passed + 1; print("[PASS] " .. name)
    else failed = failed + 1; print("[FAIL] " .. name) end
end

function Start()
    local I18n = require("core.I18n")
    local SC = require("config.StageConfig")
    local originalRequire = require
    local captured = {}
    local function record(_, _, _, text) captured[#captured + 1] = text end
    local fakeDraw = { drawTextStroke = record, drawImageCentered = function() end,
        drawImageMirrored = function() end }
    local mocks = {
        ["ui.battle.scene.BattleDraw"] = fakeDraw,
        ["ui.battle.stage.StageBerserk"] = { isActive = function() return false end },
        ["core.DarkIcon"] = { drawNine = function() end },
    }
    require = function(name) return mocks[name] or originalRequire(name) end
    nvgSave = function() end
    nvgRestore = function() end
    nvgFontFace = function() end
    nvgFontSize = function() end
    nvgTextAlign = function() end
    nvgFillColor = function() end
    nvgBeginPath = function() end
    nvgRoundedRect = function() end
    nvgFill = function() end
    nvgRGBA = function() return 0 end
    nvgTextBounds = function(_, _, _, text) return utf8.len(text) * 10 end
    nvgText = record
    local Nav = require("ui.battle.stage.BattleStageNav")
    local Transition = require("ui.battle.stage.BattleTransitionHud")
    local Terminal = require("ui.battle.popup.TerminalConfirmDialog")
    local function contains(expected)
        for _, text in ipairs(captured) do if text == expected then return true end end
        return false
    end
    for _, lang in ipairs({ "zh_CN", "zh_TW", "en", "ja", "ko" }) do
        I18n.set(lang)
        captured = {}
        local source = "普通 1-1 至 1-5"
        local cached = Nav.drawStageTitle(nil, { isFirstClear = false, idleRangeText = source,
            stageName = "黑棘林道1-1", maxStageId = 105, battleActive = false,
            getStageConfig = function() return SC end, getRelativeChapter = SC.getRelativeChapter })
        check(cached == source, lang .. "挂机返回源缓存")
        check(contains(I18n.format("%s %s 至 %s", I18n.difficulty("普通"), "1-1", "1-5")),
            lang .. "挂机范围显示正确译文")
        captured = {}
        Nav.drawStageTitle(nil, { isFirstClear = true, stageName = "困难·黑棘林道1-1",
            battleActive = true, firstClearTimeLeft = 9, maxStageId = 2401,
            getStageConfig = function() return SC end, getRelativeChapter = SC.getRelativeChapter })
        check(contains(I18n.lookup("困难·黑棘林道1-1")) and contains(I18n.format("剩余 %d 秒", 9)),
            lang .. "首通名与倒计时翻译")
        captured = {}
        Transition.draw(nil, { battleActive = false, reincarnationTimer = 0.5,
            currentStageId = 999, stageName = "终焉神殿", defeatByTimeout = false,
            getStageConfig = function() return SC end, drawTextStroke = record })
        check(contains(I18n.format("即将进入%s难度...", I18n.difficulty("困难"))), lang .. "轮回下一难度翻译")
    end
    I18n.set("zh_CN")
    require = originalRequire
    print(string.format("[i18n_display_boundary_test] passed=%d failed=%d", passed, failed))
    if failed == 0 then print("I18N DISPLAY BOUNDARY: ALL PASS") end
    engine:Exit()
end
