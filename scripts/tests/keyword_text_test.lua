-- ============================================================================
-- keyword_text_test.lua — 关键词系统回归
-- 覆盖：
--   1) KeywordConfig：长词优先排序、词条完整性
--   2) KeywordText.splitSegments 行为（经 draw 布局间接验证）：
--      "回响客" 不被 "回响" 截胡；普通文本/关键词交替拆段
--   3) 折行与热区：热区数量=关键词出现次数，坐标随行推进
--   4) handleInput：命中关键词开弹窗、再点关闭、空白处不消费
-- 跑法: ./.cli/UrhoXRuntime tests/keyword_text_test.lua -tool_mode -graphicssurfaceless
-- ============================================================================

local failures = {}

local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        print("[FAIL] " .. msg)
        failures[#failures + 1] = msg
    end
end

function Start()
    local KW = require("config.KeywordConfig")
    local KeywordText = require("ui.widget.KeywordText")

    -- ── 1) 词表与排序 ──
    check(KW.get("回响") ~= nil, "词表包含「回响」")
    check(KW.get("回响客") ~= nil, "词表包含「回响客」")
    check(KW.get("能量护盾") ~= nil, "词表包含「能量护盾」")
    check(KW.get("不存在词条") == nil, "未知词返回 nil")

    local keys = KW.sortedKeys()
    local idxEcho, idxEchoist = nil, nil
    for i, k in ipairs(keys) do
        if k == "回响" then idxEcho = i end
        if k == "回响客" then idxEchoist = i end
    end
    check(idxEchoist and idxEcho and idxEchoist < idxEcho, "长词「回响客」排在「回响」之前")

    -- 词条字段完整
    local allOk = true
    for _, def in pairs(KW.KEYWORDS) do
        if type(def.title) ~= "string" or def.title == ""
           or type(def.desc) ~= "string" or def.desc == "" then
            allOk = false
        end
    end
    check(allOk, "所有词条 title/desc 非空")

    -- ── 2/3) 布局与热区（无引擎环境走等宽估算兜底）──
    local kt = KeywordText.new()
    local text = "普通攻击留下回响，1.2秒后造成伤害；回响客职业回响次数更多。"
    local h = kt:draw(nil, text, 0, 0, 900, 30)
    check(h > 0, "draw 返回正高度")

    -- 文本含独立「回响」x2 +「回响客」x1（长词优先不被拆开）= 3 个热区
    local countEcho, countEchoist = 0, 0
    for _, spot in ipairs(kt.hotspots) do
        if spot.name == "回响" then countEcho = countEcho + 1 end
        if spot.name == "回响客" then countEchoist = countEchoist + 1 end
    end
    check(countEcho == 2, "「回响」命中 2 次（实际 " .. countEcho .. "）")
    check(countEchoist == 1, "「回响客」长词优先命中 1 次（实际 " .. countEchoist .. "）")

    -- 热区坐标合法：x2 > x1，且按文本顺序递增（同行或换行）
    local ordered = true
    local prevIdx = 0
    for _, spot in ipairs(kt.hotspots) do
        if spot.x2 <= spot.x1 or spot.y2 <= spot.y1 then ordered = false end
        if spot.y1 < prevIdx then ordered = false end -- y 不减小（允许换行向下）
        prevIdx = spot.y1
    end
    check(ordered, "热区坐标合法且按阅读顺序排列")

    -- ── 4) 输入交互 ──
    local spot1 = kt.hotspots[1]
    local cx = (spot1.x1 + spot1.x2) * 0.5
    local cy = (spot1.y1 + spot1.y2) * 0.5
    check(kt:handleInput(cx, cy), "点击关键词消费事件")
    check(kt:isOpen(), "点击后弹窗打开")
    check(kt.popup and kt.popup.name ~= nil and kt.popup.desc ~= nil, "弹窗带 title/desc")
    check(kt:handleInput(cx, cy), "弹窗开着时点击仍消费事件（关闭）")
    check(not kt:isOpen(), "再次点击后弹窗关闭")

    -- 空白处点击不消费
    check(not kt:handleInput(-500, -500), "空白处点击不消费事件")

    -- clear 清状态
    kt:handleInput(cx, cy)
    kt:clear()
    check(not kt:isOpen() and #kt.hotspots == 0, "clear 清空弹窗与热区")

    -- ── 换行场景：窄宽度下热区仍全部保留（2 回响 + 1 回响客）──
    local kt2 = KeywordText.new()
    kt2:draw(nil, text, 0, 0, 120, 30)
    check(#kt2.hotspots == 3, "窄宽度折行后仍有 3 个关键词热区（实际 " .. #kt2.hotspots .. "）")

    -- ── 行宽不超容器（回归：字符宽度曾被双重计入导致提前折行/行宽虚高）──
    local layout = kt:_layout(nil, text, 900, 30)
    local widthOk = true
    for _, line in ipairs(layout.lines) do
        if line.width > 900 + 0.01 then widthOk = false end
    end
    check(widthOk, "所有行宽不超过容器宽度")
    -- 单行文本 + 宽容器 → 必须只有一行
    local layout1 = kt:_layout(nil, "回响客的回响", 900, 30)
    check(#layout1.lines == 1, "宽容器下短文本不折行（实际 " .. #layout1.lines .. " 行）")

    -- ── 显式换行符 ──
    local kt3 = KeywordText.new()
    kt3:draw(nil, "第一行回响\n第二行回响", 0, 0, 900, 30)
    check(#kt3.hotspots == 2, "显式 \\n 两侧关键词均命中")
    if #kt3.hotspots == 2 then
        check(kt3.hotspots[2].y1 > kt3.hotspots[1].y1, "\\n 后第二行 Y 更大")
    end

    if #failures == 0 then
        print("KEYWORD TESTS: ALL PASS (" .. "ok" .. ")")
    else
        print("KEYWORD TESTS: " .. #failures .. " FAILURES")
    end
end
