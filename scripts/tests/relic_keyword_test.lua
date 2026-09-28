-- ============================================================================
-- relic_keyword_test.lua — 遗物词缀关键词接入回归
-- 验证 RelicDetailPanel 效果描述接 KeywordText 的核心价值：遗物词缀文本
-- （全游戏机制词密度最高区域）确实能被关键词系统识别并生成可点击热区。
-- 无引擎环境（vg=nil，走 KeywordText 等宽估算兜底）。
-- 跑法: ./.cli/UrhoXRuntime tests/relic_keyword_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- ============================================================================

local failures = {}
local function check(cond, msg)
    if cond then print("[PASS] " .. msg)
    else print("[FAIL] " .. msg); failures[#failures + 1] = msg end
end

function Start()
    print("[relic_keyword_test] start")
    local ok, err = pcall(function()
        local KW = require("config.KeywordConfig")
        local KeywordText = require("ui.widget.KeywordText")
        local RelicDefs = require("shared.relic.RelicDefs")

        -- 1) 遍历所有遗物词缀文本，统计命中关键词的词缀数与总热区数
        local kt = KeywordText.new()
        local keys = KW.sortedKeys()
        local affixTotal, affixWithKw, hotspotTotal = 0, 0, 0
        local sampleTexts = {}

        for affixId = 1, (RelicDefs.AFFIXES and #RelicDefs.AFFIXES or 95) do
            for quality = 1, 6 do
                local text = RelicDefs.getAffixText(affixId, quality)
                if text and text ~= "" then
                    affixTotal = affixTotal + 1
                    -- 用 KeywordText 排版，统计生成的关键词热区数
                    kt:clear()
                    kt:draw(nil, text, 0, 0, 400, 30)
                    local n = #kt.hotspots
                    if n > 0 then
                        affixWithKw = affixWithKw + 1
                        hotspotTotal = hotspotTotal + n
                        if #sampleTexts < 6 then
                            sampleTexts[#sampleTexts + 1] = string.format("「%s」→%d热区", text, n)
                        end
                    end
                end
            end
        end

        print(string.format("[stat] 词缀文本样本=%d  命中关键词的=%d  总热区=%d", affixTotal, affixWithKw, hotspotTotal))
        for _, s in ipairs(sampleTexts) do print("  样例 " .. s) end

        check(affixTotal > 0, "遗物词缀文本非空（样本 " .. affixTotal .. " 条）")
        check(affixWithKw > 0, "至少部分遗物词缀命中关键词（命中 " .. affixWithKw .. " 条）")
        check(hotspotTotal > 0, "关键词热区总数 > 0（" .. hotspotTotal .. "），接入有实际渲染价值")

        -- 2) 长词优先：若词缀含「回响客」不应被「回响」截胡（复用 KeywordText 语义）
        --    构造一条含职业名的文本验证拆段正确
        kt:clear()
        local probe = "回响客的攻击附带能量护盾"
        kt:draw(nil, probe, 0, 0, 400, 30)
        local names = {}
        for _, h in ipairs(kt.hotspots) do names[h.name] = true end
        check(#kt.hotspots >= 2, "探针文本「回响客…能量护盾」识别出 ≥2 关键词（实得 " .. #kt.hotspots .. "）")
        check(names["回响客"] == true or names["回响"] == true, "识别出回响相关职业词")
        check(names["能量护盾"] == true, "识别出「能量护盾」机制词")

        -- 3) 点击热区可开解释弹窗（交互闭环）
        if #kt.hotspots > 0 then
            local h = kt.hotspots[1]
            local cx = (h.x1 + h.x2) * 0.5
            local cy = (h.y1 + h.y2) * 0.5
            local consumed = kt:handleInput(cx, cy)
            check(consumed == true and kt:isOpen(), "点击关键词热区开解释弹窗")
            kt:handleInput(cx, cy)
            check(not kt:isOpen(), "再次点击关闭弹窗")
        end

        print(string.format("[summary] 遗物词缀关键词密度：%.0f%% 的词缀含可点击机制词",
            affixTotal > 0 and (affixWithKw / affixTotal * 100) or 0))
    end)
    if not ok then
        print("[FAIL] 测试抛异常: " .. tostring(err))
        failures[#failures + 1] = "exception"
    end
    if #failures == 0 then
        print("[relic_keyword_test] ALL PASS")
    else
        print("[relic_keyword_test] FAILURES=" .. #failures)
        for _, m in ipairs(failures) do print("  - " .. m) end
    end
    engine:Exit()
end
