-- 觉醒说明下移布局回归：正文、关键词热区同步移动，CG/标题/按钮保留位置。
local engineRequire = require
local mocks = {}
rawset(_G, "require", function(name) return mocks[name] or engineRequire(name) end)
local noop = function() end
mocks["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop }
mocks["core.DrawUtil"] = { drawTextStroke = noop, drawImageCentered = noop,
    drawShardIcon = noop, hitTest = function() return false end }
mocks["core.I18n"] = { lookup = function(text) return text end }
for _, name in ipairs({ "nvgBeginPath", "nvgMoveTo", "nvgLineTo", "nvgClosePath", "nvgFill",
    "nvgStroke", "nvgFillColor", "nvgStrokeColor", "nvgStrokeWidth", "nvgFontFace",
    "nvgTextAlign", "nvgSave", "nvgRestore" }) do rawset(_G, name, noop) end
rawset(_G, "nvgCreateImage", function() return -1 end)
local fontSize = 36
rawset(_G, "nvgFontSize", function(_, size) fontSize = size end)
rawset(_G, "nvgTextBounds", function(_, _, _, text)
    local width = 0
    for _, cp in utf8.codes(text) do width = width + (cp > 127 and fontSize or fontSize * 0.55) end
    return width
end)
local titles = {}
rawset(_G, "nvgText", function(_, x, y, text) titles[#titles + 1] = { x = x, y = y, text = text } end)

function Start()
    local ok, err = pcall(function()
        local Panel = require("ui.character.hero.AwakeningPanel")
        local Config = require("config.AwakeningConfig")
        local KeywordText = require("ui.widget.KeywordText")
        local realDraw = Panel.kwText.draw
        local expectedY = 1963 - 139 * 0.5
        local draws = 0
        local checks = 0
        Panel.kwText.draw = function(self, vg, text, x, y, width, size, lineHeight, center)
            assert(y == expectedY, "觉醒说明应整体下移33设计像素")
            assert(width == 910 and size == 36 and center == 540, "说明宽度字号及居中保持")
            draws = draws + 1
            return realDraw(self, vg, text, x, y, width, size, lineHeight, center)
        end
        Panel.setOwnedDataGetter(function() return { shards = 150, awakening = {} } end)
        for _, heroId in ipairs({ 1, 6, 12 }) do
            Panel.reset(heroId)
            Panel.draw({}, heroId)
            checks = checks + 1
        end
        -- 所有英雄和节点的热区跟随正文锚点；不用单独补输入偏移。
        local helper = KeywordText.new()
        for heroId = 1, 25 do
            for node = 1, Config.NODE_COUNT do
                local text = Config.getNodeEffect(heroId, node)
                if text then
                    helper:draw({}, text, 85, expectedY, 910, 36, nil, 540)
                    for _, hit in ipairs(helper.hotspots) do
                        assert(hit.y1 >= expectedY, "关键词热区必须跟随新正文位置")
                        assert(hit.y2 <= 2110, "关键词热区不得覆盖嵌合按钮")
                        checks = checks + 1
                    end
                end
            end
        end
        local nodeTitle = false
        for _, text in ipairs(titles) do
            if text.text:find("初醒", 1, true) and text.y == 1860 then nodeTitle = true end
        end
        assert(nodeTitle and Panel.BTN_CY == 2160, "阶段标题与嵌合按钮保持原位")
        assert(draws == 3, "必须真实调用觉醒正文绘制")
        print("[awakening_text_layout_test] ALL PASS checks=" .. checks)
    end)
    if not ok then log:Write(LOG_ERROR, "[awakening_text_layout_test] " .. tostring(err)) end
    engine:Exit()
end
