-- 通用按钮真实源码专项：只隔离时间、绘图及音效边界，不启动游戏或读取玩家档。
local TAG = "[button_motion_test]"
local checks, cases, failures = 0, 0, 0
local function check(value, why)
    checks = checks + 1
    assert(value, why)
end
local function near(value, expected, why)
    check(math.abs(value - expected) < .000001, why .. " " .. tostring(value) .. "/" .. tostring(expected))
end
local function source()
    local file = assert(cache:GetFile("systems/ButtonFeedback.lua"))
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end
local function fixture()
    local f = { clock = { elapsedTime = 100 }, depth = 0, sounds = 0, scales = {}, translations = {}, denied = 0 }
    local function deny() f.denied = f.denied + 1; error("禁止存档/随机访问") end
    local env = setmetatable({ time = f.clock, File = deny, FileSystem = deny,
        math = setmetatable({ random = deny, randomseed = deny }, { __index = math }) }, { __index = _G })
    env._G = env
    env.require = function(name)
        check(name == "systems.GameSFX", "只依赖已有点击音效")
        return { playUIClick = function(kind) check(kind == 2, "原点击音效类型"); f.sounds = f.sounds + 1 end }
    end
    env.nvgSave = function() f.depth = f.depth + 1 end
    env.nvgRestore = function() f.depth = f.depth - 1; check(f.depth >= 0, "栈不下溢") end
    env.nvgScale = function(_, sx, sy) near(sx, sy, "按钮保持等比"); f.scales[#f.scales + 1] = sx end
    env.nvgTranslate = function(_, x, y) f.translations[#f.translations + 1] = { x, y } end
    f.button = assert(load(source(), "@button-motion/production", "t", env))()
    function f:draw(key)
        local drawn = self.button.begin({}, key or "test", 400, 300, 200, 80)
        local scale = drawn and self.scales[#self.scales] or 1
        self.button.finish({}, drawn)
        check(self.depth == 0, "宿主栈完整恢复")
        if drawn then
            local a, b = self.translations[#self.translations - 1], self.translations[#self.translations]
            near(a[1] + b[1], 0, "中心X不漂移"); near(a[2] + b[2], 0, "中心Y不漂移")
        end
        return scale, drawn
    end
    return f
end
local function run(name, fn)
    cases = cases + 1
    local ok, caught = xpcall(fn, debug.traceback)
    if ok then print(TAG .. " PASS " .. name)
    else failures = failures + 1; print(TAG .. " FAIL " .. name .. ": " .. tostring(caught)) end
end
function Start()
    run("快收轻弹与原寿命端点", function()
        local f = fixture()
        f.button.onPress(400, 300)
        near(f:draw(), 1, "按下首帧无跳变")
        f.clock.elapsedTime = 100.03
        near(f:draw(), .93, "半程快速收至接近压下值")
        f.clock.elapsedTime = 100.061
        near(f:draw(), .92, "原0.06秒压下终值")
        f.button.onRelease(); f.button.trigger("test")
        near(f:draw(), .92, "释放首帧接续压下")
        f.clock.elapsedTime = 100.145
        local peak = f:draw()
        check(peak > 1 and peak <= 1.002, "克制回弹不过度放大")
        local same = f:draw(); near(same, peak, "同时间绘制不推进")
        f.clock.elapsedTime = 100.182
        local value, drawn = f:draw()
        near(value, 1, "原0.12秒恢复终值"); check(not drawn, "结束后不额外变换")
        check(f.sounds == 1 and f.denied == 0, "一声反馈且无存档/RNG")
    end)
    run("短按释放从当前缩放平滑接续", function()
        local f = fixture()
        f.button.onPress(400, 300); f:draw()
        f.clock.elapsedTime = 100.015
        local before = f:draw()
        f.button.onRelease(); f.button.trigger("test")
        near(f:draw(), before, "不能释放时跳到最小缩放")
        f.clock.elapsedTime = 100.136
        near(f:draw(), 1, "短按原释放时长完成")
        check(f.sounds == 1 and f.denied == 0, "短按不重播音效")
    end)
    run("未触发松开与边界命中保持原契约", function()
        local f = fixture()
        check(not select(2, f:draw()), "未按下不创建表现")
        f.button.onPress(501, 300)
        check(not select(2, f:draw()), "边界外不响应")
        f.button.onRelease()
        f.button.onPress(300, 260); f:draw()
        f.clock.elapsedTime = 100.07; near(f:draw(), .92, "边界命中压下")
        f.button.onRelease(); near(f:draw(), .92, "拖出松开沿原路径恢复")
        f.clock.elapsedTime = 100.191
        near(f:draw(), 1, "无业务trigger仍回位")
        check(f.sounds == 1 and f.denied == 0, "命中音效仍只一声")
    end)
    run("快捷触发和不同按钮互不串扰", function()
        local f = fixture()
        f.button.trigger("shortcut")
        near(f:draw("shortcut"), .92, "无按下记录沿原快速反馈")
        near(f:draw("other"), 1, "其他按钮不跟着弹")
        f.clock.elapsedTime = 100.13
        near(f:draw("shortcut"), 1, "快捷反馈结束")
        check(f.sounds == 1 and f.denied == 0, "快捷触发原音效无副作用")
    end)
    print(string.format("%s %s cases=%d assertions=%d failures=%d", TAG,
        failures == 0 and "ALL PASS" or "FAILED", cases, checks, failures))
    engine:Exit()
end
