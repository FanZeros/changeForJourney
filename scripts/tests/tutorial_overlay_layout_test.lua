-- 纯布局与 NanoVG mock 回归，可由 Runtime Start() 或独立 Lua 执行。
local Overlay = require("ui.tutorial.TutorialOverlay")

local function overlaps(a, b)
    return b and math.abs(a.cx - b.cx) < (a.w + b.w) * 0.5
        and math.abs(a.cy - b.cy) < (a.h + b.h) * 0.5
end

local function run()
    local assertions = 0
    local function check(value, message)
        assertions = assertions + 1
        assert(value, "[tutorial_overlay_layout_test] " .. message)
    end
    local function inScreen(box, width, height, label)
        check(box.w > 0 and box.h > 0, label .. " positive size")
        check(box.cx - box.w * 0.5 >= -0.001 and box.cx + box.w * 0.5 <= width + 0.001,
            label .. " horizontal bounds")
        check(box.cy - box.h * 0.5 >= -0.001 and box.cy + box.h * 0.5 <= height + 0.001,
            label .. " vertical bounds")
    end
    local resolutions = { { 1920, 1080 }, { 1280, 720 }, { 960, 540 }, { 844, 390 } }
    for _, size in ipairs(resolutions) do
        local width, height = size[1], size[2]
        local targets = {
            { cx = width * 0.12, cy = height * 0.5, w = 100, h = 100 },
            { cx = width * 0.5, cy = height * 0.5, w = 110, h = 90 },
            { cx = width * 0.9, cy = height * 0.5, w = 100, h = 100 },
            { cx = width * 0.5, cy = 34, w = 200, h = 60 },
            { cx = width * 0.5, cy = height - 34, w = 200, h = 60 },
            { cx = width - 76, cy = height - 38, w = 110, h = 60 },
            { cx = 18, cy = height * 0.5, w = 80, h = 100 },
        }
        for _, target in ipairs(targets) do
            for _, textWidth in ipairs({ 180, 620, 2400 }) do
                local result = Overlay.layout(width, height, target, textWidth)
                inScreen(result.bubble, width, height, "bubble")
                inScreen(result.skip, width, height, "skip")
                check(result.bubble.w <= math.min(520, width - 32) + 0.001, "responsive max width")
                check(not overlaps(result.bubble, result.hole), "bubble avoids target including visual pad")
                check(not overlaps(result.bubble, result.skip), "bubble avoids skip")
                check(not overlaps(result.skip, result.hole), "skip avoids target")
                check(result.hs ~= nil and result.hs.w <= target.w and result.hs.h <= target.h,
                    "interactive target is not expanded by visual padding")
                local again = Overlay.layout(width, height, target, textWidth)
                check(result.skip.cx == again.skip.cx and result.skip.cy == again.skip.cy,
                    "skip position is stable, no elapsed-time float")
            end
        end
        local missing = Overlay.layout(width, height, nil, 400)
        inScreen(missing.bubble, width, height, "missing target bubble")
        inScreen(missing.skip, width, height, "missing target skip")
        check(missing.hs == nil and not overlaps(missing.bubble, missing.skip), "missing target recoverable")
        local outside = Overlay.layout(width, height, { cx = -200, cy = -200, w = 20, h = 20 })
        check(outside.hs == nil, "fully offscreen target uses recovery")
    end
    -- 矮屏幕中目标接近全高时，提示应改放侧边，不可强制夹入目标。
    local side = Overlay.layout(360, 160, { cx = 180, cy = 80, w = 44, h = 130 }, 200)
    inScreen(side.bubble, 360, 160, "side bubble")
    check(not overlaps(side.bubble, side.hole) and not overlaps(side.bubble, side.skip), "side fallback stays clear")

    -- 无需真实 NanoVG 上下文或字体；测试失败也必须恢复所有替换的全局函数。
    local names = {
        "nvgSave", "nvgRestore", "nvgResetScissor", "nvgScissor", "nvgFontFace", "nvgFontSize",
        "nvgTextAlign", "nvgTextBounds", "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgPathWinding",
        "nvgFillColor", "nvgRGBA", "nvgFill", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke",
        "nvgIntersectScissor", "nvgText",
    }
    ---@type table<string, any>
    local saved = {}
    local calls, textCalls, holes = {}, {}, {}
    local fontSize, depth = 20, 0
    for _, name in ipairs(names) do
        saved[name] = _G[name]
        _G[name] = function(...) calls[#calls + 1] = { name = name, args = { ... } } end
    end
    _G.nvgSave = function() depth = depth + 1 end
    _G.nvgRestore = function() depth = depth - 1 end
    _G.nvgFontSize = function(_, value) fontSize = value end
    _G.nvgRGBA = function(r, g, b, a) return { r, g, b, a } end
    _G.nvgTextBounds = function(_, _, _, text)
        local width = 0
        for _, cp in utf8.codes(text) do width = width + (cp < 128 and fontSize * 0.55 or fontSize) end
        return width
    end
    _G.nvgText = function(_, x, y, text)
        textCalls[#textCalls + 1] = { x = x, y = y, text = text }
    end
    _G.nvgPathWinding = function(_, direction)
        check(calls[#calls].name == "nvgRoundedRect", "hole winding follows its rounded subpath")
        check(direction == NVG_HOLE, "hole uses NVG_HOLE")
        holes[#holes + 1] = calls[#calls].args
    end
    local ok, err = pcall(function()
        local longText = string.rep("点击右侧队伍中的角色查看详情，装备新武器。", 10)
        for _, size in ipairs(resolutions) do
            local width, height = size[1], size[2]
            local target = { cx = width * 0.5, cy = height * 0.5, w = 96, h = 80 }
            local result = Overlay.draw({}, width, height, target, longText, 0, 0.9, 1)
            check(not result.skipVisible, "skip hidden before one second")
            check(result.lines and #result.lines > 1, "long Chinese text wraps by UTF8 codepoints")
            inScreen(result.bubble, width, height, "draw bubble")
            check(not overlaps(result.bubble, result.hole) and not overlaps(result.bubble, result.skip),
                "measured draw layout does not obscure controls")
            for _, line in ipairs(result.lines or {}) do
                check(utf8.len(line) ~= nil, "wrapped line is valid UTF8")
                check(nvgTextBounds({}, 0, 0, line) <= result.bubble.w - result.padding * 2 + 0.001,
                    "each measured line fits bubble")
            end
            local later = Overlay.draw({}, width, height, target, "短提示", 25, 1, 1)
            check(later.skipVisible, "skip visible at one second")
            check(result.skip.cx == later.skip.cx and result.skip.cy == later.skip.cy,
                "draw skip never floats or changes with text")
            check(later.bubble.h < result.bubble.h, "height follows measured wrapped text")
        end
        local missing = Overlay.draw({}, 844, 390, nil, "", 1, 2, 1)
        check(missing.skipVisible and missing.lines and #missing.lines > 0, "missing target displays recovery and skip")
        check(table.concat(missing.lines or {}, ""):find("跳过", 1, true) ~= nil, "recovery explains available escape")
        local newlines = Overlay.draw({}, 844, 390, nil, "", 1, 2, 0)
        check(newlines.skip.cx == missing.skip.cx and newlines.skip.cy == missing.skip.cy, "alpha leaves hit geometry stable")
        check(#holes >= #resolutions * 2, "all visible target masks mark a hole")
        local beforeCalls, beforeTexts, beforeHoles = #calls, #textCalls, #holes
        local invisible = Overlay.draw({}, 844, 390, nil, "", 3, 2, 1, true)
        check(invisible.skipVisible and #textCalls == beforeTexts + 1, "隐形步骤只绘制跳过文字")
        check(textCalls[#textCalls].text == "跳过 >", "隐形步骤不绘制缺目标气泡")
        check(#holes == beforeHoles, "隐形步骤不绘制目标或遮罩洞")
        local roundedCount, screenRectCount = 0, 0
        for i = beforeCalls + 1, #calls do
            if calls[i].name == "nvgRoundedRect" then roundedCount = roundedCount + 1 end
            if calls[i].name == "nvgRect" then screenRectCount = screenRectCount + 1 end
        end
        check(roundedCount == 1 and screenRectCount == 0, "隐形步骤只画跳过按钮，不画全屏遮罩")
        check(depth == 0, "draw balances all save/restore calls")
    end)
    for _, name in ipairs(names) do _G[name] = saved[name] end
    if not ok then error(err) end
    print("[tutorial_overlay_layout_test] ALL PASS: " .. assertions .. " assertions")
end

function Start()
    run()
    if engine then engine:Exit() end
end

-- 独立 Lua 可调用 dofile(...).run()；Runtime 调用 Start()。
return { run = run }
