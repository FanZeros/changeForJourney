-- Spine结果特效专项：独立load真实生产源码，不加载main/Boot，不读写玩家存档。
-- 基于现有Runtime测试的Start/Exit入口与NanoVG save/restore生命周期。
-- Spine/NVG替身只存在独立env，不覆写真实全局，也不依赖生产私有字段。
-- 验证故障不外抛/不重试/只报一次/释放资源，以及正常播放/完成/墙钟到期。
-- 运行：tests/spine_result_effect_test.lua -tapcode_dir=. -tool_mode -graphicsheadless
-- 旧版反证：额外资源目录含SpineResultEffect.old.lua，传-spine-source=SpineResultEffect.old.lua。
-- 证据保存在.git/ascend-freeze-validation；本入口不测试真实GPU或平台Spine绑定。

local TAG = "[spine-result-test]"
local result = { passed = 0, failed = 0, cases = 0 }
local sourceText = ""
local sourcePath = "ui/fx/SpineResultEffect.lua"

local function check(condition, label)
    if condition then
        result.passed = result.passed + 1
    else
        result.failed = result.failed + 1
        print(TAG .. " FAIL " .. label)
    end
end

local function equal(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local function readSource(path)
    local file = assert(cache:GetFile(path), "missing readonly test source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

-- 每个fixture重新load同一真实源码；state/监听/计数/故障均按case隔离。
local function fixture(options)
    local opt = options or {}
    local stats = { calls = {}, logs = {}, animations = {}, updates = {}, instances = {},
        phase = "idle", callbacks = 0, callbackPhase = "", depth = 0, saves = 0, restores = 0,
        marker = "host-transform-and-scissor", stack = {}, durationReads = 0 }
    local clock = { elapsedTime = 20.0 }
    local env = {
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next,
        type = type, tostring = tostring, tonumber = tonumber, select = select,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable,
        math = math, string = string, table = table, debug = debug,
        time = clock, os = { clock = function() return clock.elapsedTime end },
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
            stats.logs[#stats.logs + 1] = table.concat(parts, " ")
        end,
    }
    env._G = env
    -- 不从真实_G回退：缺失扩展是nil，不能意外调用宿主Spine/GPU。
    local function invoked(name)
        stats.calls[name] = (stats.calls[name] or 0) + 1
        if opt.throwAt == name then error("INJECTED_SPINE_FAULT " .. name, 0) end
        if opt.falseAt == name then return false end
        return true
    end
    local function newInstance()
        local inst = { listener = nil, animation = "", trackTime = 0, disposed = false }
        function inst:Load(path)
            stats.path = path
            if not invoked("Load") then return false end
            if opt.nilLoad then return nil end
            return true
        end
        function inst:Unload() invoked("Unload") end
        function inst:Dispose()
            self.disposed = true
            invoked("Dispose")
        end
        function inst:SetPremultipliedAlpha(pma)
            stats.pma = pma
            invoked("SetPremultipliedAlpha")
        end
        function inst:SetDefaultMix(mix)
            stats.mix = mix
            invoked("SetDefaultMix")
        end
        function inst:SetSpeed(speed)
            stats.speed = speed
            invoked("SetSpeed")
        end
        function inst:SetCompleteListener(listener)
            self.listener = listener
            invoked("SetCompleteListener")
        end
        function inst:SetAnimation(track, animation, loop)
            stats.animations[#stats.animations + 1] = { track = track, name = animation, loop = loop }
            if not invoked("SetAnimation") then return false end
            self.animation, self.trackTime = animation, 0
            if opt.completeOnSet and self.listener then self.listener(track, animation) end
            return true
        end
        if not opt.missingDuration then
            function inst:GetAnimationDuration(track)
                stats.durationReads = stats.durationReads + 1
                stats.durationTrack = track
                invoked("GetAnimationDuration")
                if opt.durationReturnMode == "false" then return false end
                if opt.durationReturnMode == "nil" then return nil end
                if opt.durationReturnMode == "nan" then return 0 / 0 end
                if opt.durationReturnMode == "infinite" then return math.huge end
                if opt.durationReturnMode == "string" then return "1.75" end
                if opt.durationReturnMode == "zero" then return 0 end
                if opt.durationReturnMode == "negative" then return -1 end
                return self.animation == "2" and (opt.failureDuration or 0.65) or (opt.duration or 1.75)
            end
        end
        function inst:GetTrackTime(_) return self.trackTime end
        function inst:IsAnimationComplete(_) return false end
        function inst:ClearTracks() invoked("ClearTracks") end
        function inst:SetScale(x, y)
            stats.scaleX, stats.scaleY = x, y
            invoked("SetScale")
        end
        function inst:SetPosition(x, y)
            stats.positionX, stats.positionY = x, y
            invoked("SetPosition")
        end
        function inst:Update(dt)
            stats.phase = "update"
            stats.updates[#stats.updates + 1] = dt
            if opt.mutateUpdate then stats.marker = "spine-update-mutated-state" end
            invoked("Update")
            self.trackTime = self.trackTime + dt
            if opt.completeOnUpdate and self.listener then self.listener(0, self.animation) end
            stats.phase = "idle"
        end
        stats.instances[#stats.instances + 1] = inst
        return inst
    end
    env.nvgSave = function(_)
        stats.saves = stats.saves + 1
        stats.stack[#stats.stack + 1] = stats.marker
        stats.depth = stats.depth + 1
        invoked("nvgSave")
    end
    env.nvgRestore = function(_)
        stats.restores = stats.restores + 1
        stats.marker = stats.stack[#stats.stack]
        stats.stack[#stats.stack] = nil
        stats.depth = stats.depth - 1
        invoked("nvgRestore")
    end
    if not opt.missingCreate then
        env.nvgSpineCreate = function(_)
            if not invoked("Create") then return false end
            if opt.nilCreate then return nil end
            return newInstance()
        end
    end
    if not opt.missingRender then
        env.nvgSpineRender = function(_, inst)
            stats.phase = "render"
            if opt.mutateRender then stats.marker = "spine-render-mutated-state" end
            invoked("Render")
            if opt.completeOnRender and inst.listener then inst.listener(0, inst.animation) end
            stats.phase = "idle"
        end
    end
    local effect = assert(load(sourceText, "@" .. sourcePath, "t", env))()
    local f = { stats = stats, clock = clock, effect = effect, options = opt, vg = {} }
    function f:call(name, ...)
        local ok, err = pcall(self.effect[name], ...)
        check(ok, self.label .. " " .. name .. " must not throw: " .. tostring(err))
        return ok
    end
    function f:draw(at)
        if at ~= nil then self.clock.elapsedTime = at end
        return self:call("draw", self.vg, 540, 620, 160)
    end
    function f:callback()
        self.stats.callbacks = self.stats.callbacks + 1
        self.stats.callbackPhase = self.stats.phase
        self.stats.callbackDepth = self.stats.depth
    end
    function f:count(name) return self.stats.calls[name] or 0 end
    return f
end

local function case(label, fn)
    result.cases = result.cases + 1
    local ok, err = pcall(fn, label)
    check(ok, label .. " case must complete: " .. tostring(err))
    print(TAG .. " CASE " .. label .. " cumulative_failed=" .. result.failed)
end

local function stableDisabled(f, allocated)
    check(not f.effect.isPlaying(), f.label .. " fault stops playing")
    check(#f.stats.logs > 0, f.label .. " fault logged")
    local logCount, creates = #f.stats.logs, f:count("Create")
    local loads, updates, renders = f:count("Load"), f:count("Update"), f:count("Render")
    local unloads, disposes = f:count("Unload"), f:count("Dispose")
    for frame = 1, 8 do f:draw(20 + frame * 0.02) end
    f:call("preload", f.vg)
    f:call("play", false, function() f:callback() end)
    f:draw(21)
    equal(#f.stats.logs, logCount, f.label .. " no repeated logs")
    equal(f:count("Create"), creates, f.label .. " no repeated creates")
    equal(f:count("Load"), loads, f.label .. " no repeated loads")
    equal(f:count("Update"), updates, f.label .. " no repeated updates")
    equal(f:count("Render"), renders, f.label .. " no repeated renders")
    equal(f:count("Unload"), unloads, f.label .. " no repeated unloads")
    equal(f:count("Dispose"), disposes, f.label .. " no repeated disposes")
    equal(f.stats.callbacks, 0, f.label .. " fault never completes callback")
    check(not f.effect.isPlaying(), f.label .. " disabled replay stays stopped")
    if allocated then
        equal(unloads, 1, f.label .. " allocated instance unloaded once")
        equal(disposes, 1, f.label .. " allocated instance disposed once")
    end
    equal(f.stats.depth, 0, f.label .. " fault restores NVG save depth")
    equal(f.stats.marker, "host-transform-and-scissor", f.label .. " fault preserves host render state")
end

local function runFaults()
    local faults = {
        { "missing-create", { missingCreate = true }, false },
        { "missing-render", { missingRender = true }, false },
        { "create-nil", { nilCreate = true }, false },
        { "create-false", { falseAt = "Create" }, false },
        { "create-throw", { throwAt = "Create" }, false },
        { "load-false", { falseAt = "Load" }, true },
        { "load-nil", { nilLoad = true }, true },
        { "load-throw", { throwAt = "Load" }, true },
        { "pma-throw", { throwAt = "SetPremultipliedAlpha" }, true },
        { "mix-throw", { throwAt = "SetDefaultMix" }, true },
        { "speed-throw", { throwAt = "SetSpeed" }, true },
        { "listener-throw", { throwAt = "SetCompleteListener" }, true },
    }
    for _, entry in ipairs(faults) do
        case(entry[1], function(label)
            local f = fixture(entry[2]); f.label = label
            f:call("preload", f.vg)
            f:call("play", true, function() f:callback() end)
            f:draw(20)
            stableDisabled(f, entry[3])
        end)
    end
    for _, mode in ipairs({ "false", "throw" }) do
        for _, loading in ipairs({ "preloaded", "lazy" }) do
            case("animation-" .. mode .. "-" .. loading, function(label)
                local opt = {}
                opt[mode == "false" and "falseAt" or "throwAt"] = "SetAnimation"
                local f = fixture(opt); f.label = label
                if loading == "preloaded" then f:call("preload", f.vg) end
                f:call("play", true, function() f:callback() end)
                f:draw(20)
                stableDisabled(f, true)
            end)
        end
    end
    for _, method in ipairs({ "Update", "SetScale", "SetPosition", "Render" }) do
        case(method .. "-throw", function(label)
            local f = fixture({ throwAt = method, mutateRender = true }); f.label = label
            f:call("preload", f.vg)
            f:call("play", true, function() f:callback() end)
            f:draw(20.01)
            stableDisabled(f, true)
        end)
    end
    case("render-throws-after-complete-event", function(label)
        local f = fixture({ completeOnUpdate = true, throwAt = "Render", mutateRender = true }); f.label = label
        f:call("preload", f.vg)
        f:call("play", true, function() f:callback() end)
        f:draw(20.01)
        stableDisabled(f, true)
    end)
end

local function runLifecycle()
    case("normal-preload-play-selection-and-state", function(label)
        local f = fixture({ mutateRender = true }); f.label = label
        f:call("preload", f.vg); f:call("preload", f.vg)
        equal(f:count("Create"), 1, label .. " preload creates once")
        equal(f:count("Load"), 1, label .. " preload loads once")
        check(not f.effect.isPlaying(), label .. " preload does not play")
        equal(f.stats.path, "image/spine/UI_SPINE_QHTX.json", label .. " correct asset path")
        equal(f.stats.pma, true, label .. " pma enabled")
        f:call("play", true, function() f:callback() end)
        f:draw(20.01)
        equal(f.stats.animations[1].name, "1", label .. " success animation")
        equal(f.stats.animations[1].track, 0, label .. " engine zero-based track")
        equal(f.stats.animations[1].loop, false, label .. " one-shot")
        check(f.stats.durationReads > 0, label .. " reads real animation duration")
        equal(f.stats.durationTrack, 0, label .. " duration of selected track")
        check(f.effect.isPlaying(), label .. " no early completion")
        check(f.stats.scaleX > 0 and f.stats.scaleY < 0, label .. " keeps upright NVG projection")
        equal(f.stats.depth, 0, label .. " balanced NVG state")
        equal(f.stats.marker, "host-transform-and-scissor", label .. " normal render protects state")
        check(f.stats.saves > 0 and f.stats.saves == f.stats.restores, label .. " save restore actually called")
        f:call("play", false)
        f:draw(20.02)
        equal(f.stats.animations[2].name, "2", label .. " failure animation")
        equal(f:count("Create"), 1, label .. " replay reuses instance")
        equal(f.stats.callbacks, 0, label .. " superseded callback canceled")
        f:call("destroy")
        equal(f:count("Unload"), 1, label .. " destroy unload")
        equal(f:count("Dispose"), 1, label .. " destroy dispose")
        f:call("destroy")
        equal(f:count("Dispose"), 1, label .. " destroy idempotent")
    end)
    for _, trigger in ipairs({ "update", "render" }) do
        case("completion-deferred-from-" .. trigger, function(label)
            local options = { mutateRender = true }
            options[trigger == "update" and "completeOnUpdate" or "completeOnRender"] = true
            local f = fixture(options); f.label = label
            f:call("preload", f.vg)
            f:call("play", true, function() f:callback() end)
            f:draw(20.01)
            equal(f.stats.callbacks, 1, label .. " callback once")
            equal(f.stats.callbackPhase, "idle", label .. " callback outside Spine update/render")
            equal(f.stats.callbackDepth, 0, label .. " callback after NVG restore")
            check(not f.effect.isPlaying(), label .. " stopped after completion")
            for i = 1, 5 do f:draw(20.02 + i * 0.01) end
            equal(f.stats.callbacks, 1, label .. " no duplicate completion")
        end)
    end
    case("callback-throw-is-contained", function(label)
        local f = fixture({ completeOnUpdate = true }); f.label = label
        f:call("preload", f.vg)
        f:call("play", true, function() f:callback(); error("INJECTED_CALLBACK_FAULT", 0) end)
        f:draw(20.01)
        equal(f.stats.callbacks, 1, label .. " callback attempted once")
        check(not f.effect.isPlaying(), label .. " callback exception does not leave playing")
        f.options.completeOnUpdate = false
        f:call("play", false)
        f:draw(20.02)
        check(f.effect.isPlaying(), label .. " callback error does not poison effect")
        equal(f.stats.depth, 0, label .. " callback error preserves NVG state")
    end)
    case("completion-callback-restarts-animation", function(label)
        local f = fixture({ completeOnUpdate = true }); f.label = label
        f:call("preload", f.vg)
        f:call("play", true, function()
            f:callback()
            f.options.completeOnUpdate = false
            f.effect.play(false, function() f:callback() end)
        end)
        f:draw(20.01)
        equal(f.stats.callbacks, 1, label .. " first callback")
        equal(f.stats.animations[#f.stats.animations].name, "2", label .. " new failure chosen")
        check(f.effect.isPlaying(), label .. " new animation not cleared by old cleanup")
        f:draw(20.02)
        check(f.effect.isPlaying(), label .. " restarted state survives next draw")
        f:draw(21.01)
        check(not f.effect.isPlaying(), label .. " restarted animation has its own duration")
        equal(f.stats.callbacks, 2, label .. " restarted callback completes once")
    end)
    case("stop-cancels-not-completes-and-replay", function(label)
        local f = fixture(); f.label = label
        f:call("preload", f.vg)
        f:call("play", true, function() f:callback() end)
        f:draw(20.01); f:call("stop")
        check(not f.effect.isPlaying(), label .. " stop immediate")
        if f.stats.instances[1].listener then f.stats.instances[1].listener(0, "1") end
        f:draw(30)
        equal(f.stats.callbacks, 0, label .. " stop cancels callback including late completion")
        local oldUpdates = f:count("Update")
        f:call("stop"); f:draw(30.01)
        equal(f:count("Update"), oldUpdates, label .. " stopped draw no update")
        f:call("play", false); f:draw(30.02)
        check(f.effect.isPlaying(), label .. " stop allows replay")
        equal(f:count("Create"), 1, label .. " stop replay reuses instance")
    end)
    case("lazy-play-stop-before-first-draw", function(label)
        local f = fixture(); f.label = label
        f:call("play", true, function() f:callback() end)
        f:call("stop"); f:draw(21)
        equal(f:count("Create"), 0, label .. " canceled pending play not loaded")
        equal(f.stats.callbacks, 0, label .. " canceled pending callback not completed")
        f:call("play", false); f:draw(21.01)
        equal(f:count("Create"), 1, label .. " later lazy replay creates")
        equal(f.stats.animations[1].name, "2", label .. " pending selection retained")
    end)
    case("fault-disabled-until-destroy-then-retry", function(label)
        local f = fixture({ falseAt = "Load" }); f.label = label
        f:call("preload", f.vg); f:call("play", true); f:draw(20)
        local firstCreates = f:count("Create")
        f.options.falseAt = nil
        f:call("play", true); f:draw(20.01)
        equal(f:count("Create"), firstCreates, label .. " repaired capability alone cannot retry")
        f:call("destroy"); f:call("preload", f.vg)
        equal(f:count("Create"), firstCreates + 1, label .. " destroy explicitly allows retry")
        f:call("play", false); f:draw(20.02)
        check(f.effect.isPlaying(), label .. " retry succeeds")
        f:call("destroy")
        equal(f:count("Dispose"), 2, label .. " failed and retried instances both disposed")
    end)
    case("clear-tracks-error-disabled-and-released", function(label)
        local f = fixture({ throwAt = "ClearTracks" }); f.label = label
        f:call("preload", f.vg)
        f:call("play", true, function() f:callback() end)
        f:draw(20.01); f:call("stop")
        stableDisabled(f, true)
    end)
    case("completion-ignores-wrong-track-and-animation", function(label)
        local f = fixture(); f.label = label
        f:call("preload", f.vg); f:call("play", true, function() f:callback() end)
        local listener = f.stats.instances[1].listener
        listener(1, "1"); f:draw(20.01)
        check(f.effect.isPlaying(), label .. " wrong track does not complete")
        listener(0, "2"); f:draw(20.02)
        check(f.effect.isPlaying(), label .. " wrong animation does not complete")
        equal(f.stats.callbacks, 0, label .. " rejected events never call callback")
        listener(0, "1")
        equal(f.stats.callbacks, 0, label .. " accepted listener only marks state")
        f:draw(20.03)
        equal(f.stats.callbacks, 1, label .. " accepted event dispatched by draw")
        check(not f.effect.isPlaying(), label .. " right event completes")
    end)
    case("completion-callback-destroys-and-lazy-replays", function(label)
        local f = fixture({ completeOnUpdate = true }); f.label = label
        f:call("preload", f.vg)
        f:call("play", true, function()
            f:callback()
            f.options.completeOnUpdate = false
            f.effect.destroy()
            f.effect.play(false, function() f:callback() end)
        end)
        f:draw(20.01)
        equal(f:count("Dispose"), 1, label .. " callback safely disposes old instance")
        check(f.effect.isPlaying(), label .. " callback's pending replay not cleared")
        f:draw(20.02)
        equal(f:count("Create"), 2, label .. " next draw creates replay instance")
        equal(f.stats.animations[#f.stats.animations].name, "2", label .. " replay selection retained")
        f:draw(21)
        equal(f.stats.callbacks, 2, label .. " replay own callback completed")
        equal(f.stats.depth, 0, label .. " callback destruction after render restore")
    end)
    for _, release in ipairs({ "Unload", "Dispose" }) do
        case("destroy-" .. release .. "-throw", function(label)
            local f = fixture({ throwAt = release }); f.label = label
            f:call("preload", f.vg); f:call("play", true); f:draw(20.01)
            f:call("destroy")
            check(not f.effect.isPlaying(), label .. " destroy stopped")
            equal(f:count("Unload"), 1, label .. " unload attempted")
            equal(f:count("Dispose"), 1, label .. " dispose attempted despite unload error")
            f:call("destroy")
            equal(f:count("Dispose"), 1, label .. " throwing release still idempotent")
        end)
    end
end

local function runDeadlines()
    local optionalDurationCases = {
        { "missing", { missingDuration = true } },
        { "throw", { throwAt = "GetAnimationDuration" } },
        { "false", { durationReturnMode = "false" } },
        { "nil", { durationReturnMode = "nil" } },
        { "nan", { durationReturnMode = "nan" } },
        { "infinite", { durationReturnMode = "infinite" } },
        { "string", { durationReturnMode = "string" } },
        { "zero", { durationReturnMode = "zero" } },
        { "negative", { durationReturnMode = "negative" } },
    }
    for _, entry in ipairs(optionalDurationCases) do
        for _, success in ipairs({ true, false }) do
            case("optional-duration-" .. entry[1] .. (success and "-success" or "-failure"), function(label)
                local f = fixture(entry[2]); f.label = label
                local fallback = success and 1.6667 or 1.3333
                f:call("preload", f.vg)
                if entry[1] == "missing" then
                    check(f.stats.instances[1].GetAnimationDuration == nil,
                        label .. " missing API is actually absent on instance")
                end
                f:call("play", success, function() f:callback() end)
                f:draw(20.01)
                check(f.effect.isPlaying(), label .. " optional query fault cannot disable effect")
                check(f:count("Render") > 0, label .. " animation still renders")
                equal(f:count("Dispose"), 0, label .. " optional capability does not release valid instance")
                if entry[1] == "missing" then
                    equal(f.stats.durationReads, 0, label .. " absent method not replaced by fallback stub")
                else
                    equal(f.stats.durationReads, 1, label .. " duration queried once per play")
                end
                f:draw(20 + fallback + 0.29)
                check(f.effect.isPlaying(), label .. " exact resource duration plus grace retained")
                equal(f.stats.callbacks, 0, label .. " not prematurely completed")
                f:draw(20 + fallback + 0.31)
                check(not f.effect.isPlaying(), label .. " invalid duration ends using resource fallback")
                equal(f.stats.callbacks, 1, label .. " fallback callback once")
                check(f.stats.callbackPhase == "idle" and f.stats.callbackDepth == 0,
                    label .. " fallback callback outside rendering")
                f:call("play", not success); f:draw(20 + fallback + 0.32)
                check(f.effect.isPlaying(), label .. " duration fallback allows next play")
                equal(f:count("Create"), 1, label .. " optional duration error never forces reload")
            end)
        end
    end
    case("hidden-page-no-draw-wall-deadline", function(label)
        local f = fixture(); f.label = label
        f:call("preload", f.vg)
        f:call("play", true, function() f:callback() end)
        f.clock.elapsedTime = 22.06
        check(not f.effect.isPlaying(), label .. " isPlaying releases expired hidden effect")
        equal(f.stats.callbacks, 1, label .. " hidden effect callback once")
        equal(f:count("Update"), 0, label .. " hidden effect requires no Spine update")
        equal(f:count("Render"), 0, label .. " hidden effect requires no render")
        check(not f.effect.isPlaying(), label .. " repeated query remains stopped")
        equal(f.stats.callbacks, 1, label .. " repeated query cannot duplicate callback")
    end)
    for _, success in ipairs({ true, false }) do
        case(success and "success-duration-and-wall-deadline" or "failure-duration-and-wall-deadline", function(label)
            local f = fixture(); f.label = label
            local duration = success and 1.75 or 0.65
            f:call("preload", f.vg)
            f:call("play", success, function() f:callback() end)
            f:draw(20)
            f:draw(20 + duration + 0.29)
            check(f.effect.isPlaying(), label .. " keeps real duration plus grace")
            equal(f.stats.callbacks, 0, label .. " no premature timeout callback")
            f:draw(20 + duration + 0.31)
            check(not f.effect.isPlaying(), label .. " missed event ends by wall deadline")
            equal(f.stats.callbacks, 1, label .. " deadline callback once")
            equal(f.stats.callbackPhase, "idle", label .. " timeout callback outside render")
            equal(f.stats.callbackDepth, 0, label .. " timeout after restore")
            check(f.stats.durationReads > 0, label .. " uses actual selected duration")
            f:draw(40)
            equal(f.stats.callbacks, 1, label .. " expired draw cannot repeat callback")
        end)
    end
    case("slow-frames-cannot-freeze-playing", function(label)
        local f = fixture({ duration = 0.2 }); f.label = label
        f:call("preload", f.vg)
        f:call("play", true, function() f:callback() end)
        f:draw(20)
        for i = 1, 5 do f:draw(20 + i * 0.11) end
        check(not f.effect.isPlaying(), label .. " wall elapsed ends even if simulation dt clamped")
        equal(f.stats.callbacks, 1, label .. " slow frame completion once")
        equal(f.stats.depth, 0, label .. " slow frame state balanced")
    end)
    case("replay-resets-wall-deadline-and-old-callback", function(label)
        local f = fixture(); f.label = label
        local oldCompleted, newCompleted = 0, 0
        f:call("preload", f.vg)
        f:call("play", true, function() oldCompleted = oldCompleted + 1 end)
        f:draw(20)
        f.clock.elapsedTime = 21.9
        f:call("play", true, function() newCompleted = newCompleted + 1 end)
        f:draw(22.1)
        check(f.effect.isPlaying(), label .. " not ended by original deadline")
        equal(oldCompleted, 0, label .. " old callback canceled")
        f:draw(24)
        check(not f.effect.isPlaying(), label .. " new deadline applies")
        equal(newCompleted, 1, label .. " new callback once")
    end)
end

function Start()
    local sourceDirectory = nil ---@type string|nil
    for _, argument in ipairs(GetArguments()) do
        local override = argument:match("^%-spine%-source=(.+)$")
        if override then sourcePath = override end
        local directory = argument:match("^%-spine%-source%-dir=(.+)$")
        if directory then sourceDirectory = directory end
    end
    if sourceDirectory then assert(cache:AddResourceDir(sourceDirectory), "readonly source directory unavailable") end
    print(TAG .. " SOURCE " .. sourcePath)
    local ok, err = pcall(function()
        sourceText = readSource(sourcePath)
        runFaults()
        runLifecycle()
        runDeadlines()
    end)
    check(ok, "suite completed: " .. tostring(err))
    print(string.format("%s RESULT cases=%d passed=%d failed=%d", TAG, result.cases, result.passed, result.failed))
    print(TAG .. (result.failed == 0 and " ALL PASS" or " RESULT FAIL"))
    engine:Exit()
end
