-- 启动音频懒加载回归：生产音频源码在独立 env 中运行。
-- 音频管理器使用 Sound/Scene/SoundSource/cache/math.random 替身；
-- SettingsPanel / Standalone 仅提取音频精确片段，不执行整个模块或玩家档。
-- 末尾真实 cache 校验最终主曲和三首保留战斗 OGG，不创建真实音源。
-- 仅由独立测试入口启动；Start 最终 engine:Exit()。
local totals = { assertions = 0, failures = 0, cases = 0 }
local TAG = "[startup_audio_test]"

local function check(ok, label)
    totals.assertions = totals.assertions + 1
    if not ok then
        totals.failures = totals.failures + 1
        print(TAG .. " FAIL " .. label)
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local function near(actual, expected, label)
    check(type(actual) == "number" and math.abs(actual - expected) < 1e-9,
        label .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end

local function runCase(label, fn)
    totals.cases = totals.cases + 1
    local before = totals.failures
    local ok, why = pcall(fn)
    if not ok then check(false, label .. " exception=" .. tostring(why)) end
    print(TAG .. " " .. label .. " " .. (totals.failures == before and "PASS" or "FAIL"))
end

local function readSource(path)
    local file = assert(cache:GetFile(path), "missing production source " .. path)
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Dispose()
    return table.concat(lines, "\n")
end

-- 参考候选直接取生产定义；不重写 play/start，不暴露/改写其私有状态。
local function readDefinitions(source, name)
    local literal = assert(source:match("local " .. name .. " = (%b{})"), "missing " .. name)
    return assert(load("return " .. literal, "@audio-definition/" .. name, "t", {}))()
end

local function countLogs(h, fragment)
    local n = 0
    for _, line in ipairs(h.logs) do
        if line:find(fragment, 1, true) then n = n + 1 end
    end
    return n
end

local function newHarness(source, label, failures, lengths, startupQueue)
    local h = {
        loads = {}, counts = {}, sounds = {}, nodes = {}, sources = {}, plays = {}, randoms = {}, seeds = {}, logs = {},
        failures = failures or {}, lengths = lengths or {}, timeline = {},
    }
    local env = {
        LOCAL = LOCAL, assert = assert, error = error, type = type, tonumber = tonumber, pcall = pcall,
        tostring = tostring, pairs = pairs, ipairs = ipairs, table = table, string = string,
        require = function(name)
            assert(name == "boot.StartupQueue", "only startup checkpoint dependency")
            return startupQueue or { checkpoint = function() end }
        end,
        print = function(line) h.logs[#h.logs + 1] = tostring(line) end,
    }
    -- 独立 math 表，绝不替换引擎全局 math.random 或 randomseed。
    ---@type table<string, any>
    local isolatedMath = {}
    for key, value in pairs(math) do isolatedMath[key] = value end
    env.math = isolatedMath
    isolatedMath.random = function(low, high)
        assert(low == 1 and type(high) == "number" and high >= 1, "expected random(1,#list)")
        local chosen = 1 + (#h.randoms % high)
        h.randoms[#h.randoms + 1] = { low = low, high = high, chosen = chosen, loads = #h.loads }
        h.timeline[#h.timeline + 1] = "random"
        return chosen
    end
    isolatedMath.randomseed = function(...)
        h.seeds[#h.seeds + 1] = { ... }
    end
    env.cache = {
        GetResource = function(_, kind, path)
            assert(kind == "Sound", "audio manager must only request Sound")
            h.loads[#h.loads + 1] = path
            h.counts[path] = (h.counts[path] or 0) + 1
            h.timeline[#h.timeline + 1] = path
            if h.failures[path] then return nil end
            if not h.sounds[path] then
                h.sounds[path] = {
                    path = path, looped = nil, length = h.lengths[path] or 100,
                    GetLength = function(self) return self.length end,
                }
            end
            return h.sounds[path]
        end,
    }
    h.scene = {
        CreateChild = function(_, name, mode)
            assert(mode == LOCAL, "audio nodes remain LOCAL")
            local node = { name = name, sources = {}, removed = false }
            function node:CreateComponent(kind)
                assert(kind == "SoundSource", "unexpected component")
                local src = { playing = false, gain = 1, position = 0, stops = 0, seeks = {}, soundType = "" }
                function src:IsPlaying() return self.playing end
                function src:GetTimePosition() return self.position end
                function src:Play(sound, frequency)
                    assert(sound, "nil sound must not be played")
                    self.frequency = frequency
                    self.playing = true
                    self.position = 0
                    self.sound = sound
                    h.plays[#h.plays + 1] = { source = self, sound = sound, gain = self.gain }
                end
                function src:Seek(position)
                    self.position = position
                    self.seeks[#self.seeks + 1] = position
                end
                function src:Stop()
                    self.playing = false
                    self.stops = self.stops + 1
                end
                self.sources[#self.sources + 1] = src
                h.sources[#h.sources + 1] = src
                return src
            end
            function node:Remove() self.removed = true end
            h.nodes[#h.nodes + 1] = node
            return node
        end,
    }
    local manager = assert(load(source, "@production/" .. label, "t", env))()
    manager.init(h.scene)
    return manager, h
end

local REGULAR_SCENES = { "battle", "other", "popup", "town", "town_building" }
local INDEPENDENT_TRACKS = { "battle", "letter", "samsara" }
-- 最新冻结需求：双通道对称 1.6s，不从生产常量推导以免错误时长自证。
local FADE_SECONDS = 1.6

local function assertNoRNG(h, label)
    eq(#h.randoms, 0, label .. " no random")
    eq(#h.seeds, 0, label .. " no randomseed")
end

local function testBGM(source)
    local defs = readDefinitions(source, "TRACKS")
    runCase("BGM seven definitions expose three independent tracks without playlist", function()
        local count = 0
        for _ in pairs(defs) do count = count + 1 end
        eq(count, 7, "public scene definition count remains seven")
        for _, key in ipairs(REGULAR_SCENES) do
            eq(defs[key].path, defs.battle.path, "regular alias same resource " .. key)
            near(defs[key].gain, defs.battle.gain, "regular alias same gain " .. key)
        end
        check(defs.letter.path ~= defs.battle.path, "letter remains independent")
        check(defs.samsara.path ~= defs.battle.path, "samsara remains independent")
        check(defs.samsara.path ~= defs.letter.path, "narrative tracks remain distinct")
        check(not source:find("BATTLE_TRACKS", 1, true), "obsolete battle candidate structure deleted")
        check(not source:match("math%.random%s*%(") and not source:match("math%.randomseed%s*%("),
            "production BGM contains no gameplay RNG call")
    end)
    runCase("BGM start loads only main track and remains idempotent", function()
        local m, h = newHarness(source, "GameBGM.lua")
        eq(#h.loads, 0, "init does not fetch sound")
        m.update(10000)
        eq(#h.sources, 0, "update before start creates nothing")
        m.start()
        eq(#h.loads, 1, "start fetches only active main track")
        eq(h.loads[1], defs.battle.path, "default active battle resource")
        eq(m.getScene(), "battle", "default canonical scene")
        eq(#h.nodes, 1, "one BGM node")
        eq(#h.sources, 2, "two original channels")
        for _, src in ipairs(h.sources) do eq(src.soundType, "Music", "BGM channel Music") end
        eq(#h.plays, 1, "start plays A once")
        eq(h.plays[1].source, h.sources[1], "initial channel A")
        eq(h.plays[1].sound.looped, true, "main BGM loops")
        eq(h.sources[1].frequency, 0, "initial play explicitly restores sample rate")
        near(h.plays[1].gain, defs.battle.gain, "main defined gain")
        near(h.sources[2].gain, 0, "inactive channel silent")
        h.sources[1].position = 42.75
        m.start(); m.setScene("battle", { fromStart = true }); m.setScene("unknown")
        eq(#h.loads, 1, "repeated start/same/unknown no fetch")
        eq(#h.plays, 1, "same scene including fromStart does not replay")
        near(h.sources[1].position, 42.75, "same key never resets playhead")
        eq(#h.sources[1].seeks, 0, "same key never seeks")
        assertNoRNG(h, "start/idempotence")
        m.stop()
    end)
    runCase("BGM all regular aliases stay continuous across UI and pre-start selection", function()
        for _, initial in ipairs(REGULAR_SCENES) do
            local m, h = newHarness(source, "GameBGM.lua")
            m.setScene(initial, { fromStart = true })
            eq(m.getScene(), "battle", "pre-start canonical alias " .. initial)
            eq(#h.loads, 0, "pre-start alias metadata only " .. initial)
            m.start()
            h.sources[1].position = 37.625
            for round = 1, 3 do
                for _, key in ipairs(REGULAR_SCENES) do
                    m.setScene(key, { fromStart = round == 2 }); m.update(0.01)
                    eq(m.getScene(), "battle", "UI alias canonical " .. initial .. "/" .. key)
                    near(h.sources[1].position, 37.625, "UI alias never scrubs " .. key)
                    near(h.sources[1].gain, defs.battle.gain, "UI alias never fades " .. key)
                    eq(h.sources[1].playing, true, "UI alias stays audible " .. key)
                end
            end
            eq(#h.loads, 1, "all regular UI transitions share one load " .. initial)
            eq(#h.plays, 1, "all regular UI transitions share one Play " .. initial)
            eq(#h.sources[1].seeks + #h.sources[2].seeks, 0, "UI aliases never Seek " .. initial)
            eq(h.sources[1].stops + h.sources[2].stops, 0, "UI aliases never Stop " .. initial)
            assertNoRNG(h, "regular aliases " .. initial)
            m.stop()
        end
    end)
    runCase("BGM narrative switches restore each track own departure seconds not percentages", function()
        local m, h = newHarness(source, "GameBGM.lua", nil,
            { [defs.battle.path] = 100, [defs.letter.path] = 200, [defs.samsara.path] = 80 })
        m.start(); h.sources[1].position = 25.375
        m.setScene("letter")
        eq(#h.loads, 2, "first narrative lazy load")
        near(h.sources[2].position, 0, "unvisited letter starts at zero not 25 percent of 200s")
        eq(#h.sources[2].seeks, 0, "first narrative needs no Seek")
        -- 离开后旧音源还会淡出；记录必须是离开时的快照，不是淡出后的游标。
        h.sources[1].position = 26.875
        m.update(FADE_SECONDS); h.sources[2].position = 61.125
        m.setScene("samsara")
        near(h.sources[1].position, 0, "unvisited samsara does not inherit letter progress")
        eq(h.plays[3].sound.path, defs.samsara.path, "samsara distinct resource")
        m.update(FADE_SECONDS); h.sources[1].position = 8.875
        m.setScene("popup")
        near(h.sources[2].position, 25.375, "regular alias returns to battle departure seconds")
        eq(m.getScene(), "battle", "narrative return canonicalizes popup")
        m.update(FADE_SECONDS); h.sources[2].position = 73.5
        m.setScene("letter")
        near(h.sources[1].position, 61.125, "letter resumes own seconds, not battle fraction")
        m.update(FADE_SECONDS); h.sources[1].position = 64.25
        m.setScene("samsara")
        near(h.sources[2].position, 8.875, "samsara resumes its own independent seconds")
        m.update(FADE_SECONDS); m.setScene("town_building")
        near(h.sources[1].position, 73.5, "latest battle departure replaces prior snapshot")
        eq(#h.loads, 3, "only three distinct resources loaded")
        for _, key in ipairs(INDEPENDENT_TRACKS) do
            eq(h.counts[defs[key].path], 1, "one load for independent track " .. key)
        end
        for _, play in ipairs(h.plays) do
            eq(play.sound.looped, true, "all narrative and main tracks loop")
            eq(play.source.frequency, 0, "reused source resets frequency")
        end
        assertNoRNG(h, "independent resumes")
        m.stop()
    end)
    runCase("BGM explicit fromStart resets only a different track; current key is idempotent", function()
        for i, target in ipairs(INDEPENDENT_TRACKS) do
            local other = INDEPENDENT_TRACKS[i % #INDEPENDENT_TRACKS + 1]
            local m, h = newHarness(source, "GameBGM.lua")
            m.setScene(target); m.start(); h.sources[1].position = 17.25
            m.setScene(other); m.update(FADE_SECONDS)
            h.sources[2].position = 43.75
            m.setScene(target, { fromStart = true })
            near(h.sources[1].position, 0, "explicit changed target starts at zero " .. target)
            m.update(FADE_SECONDS); h.sources[1].position = 9.5
            local plays, loads, seeks = #h.plays, #h.loads, #h.sources[1].seeks
            m.setScene(target, { fromStart = true }); m.update(0.8)
            eq(#h.plays, plays, "same key fromStart no replay " .. target)
            eq(#h.loads, loads, "same key fromStart no IO " .. target)
            eq(#h.sources[1].seeks, seeks, "same key fromStart no Seek " .. target)
            near(h.sources[1].position, 9.5, "same key fromStart keeps playhead " .. target)
            m.setScene(other, { fromStart = true }); m.update(FADE_SECONDS)
            near(h.sources[2].position, 0, "explicit changed other clears its old seconds " .. other)
            m.setScene(target)
            near(h.sources[1].position, 9.5, "later default resumes new post-restart seconds " .. target)
            assertNoRNG(h, "fromStart " .. target)
            m.stop()
        end
    end)
    runCase("BGM resume bounds use target length and never modulo or percentage", function()
        local samples = {
            { length = 100, position = -2, expected = 0 },
            { length = 100, position = 0, expected = 0 },
            { length = 100, position = 99.75, expected = 99.75 },
            { length = 100, position = 100, expected = 0 },
            { length = 100, position = 107.5, expected = 0 },
            { length = 0, position = 12, expected = 0 },
            { length = -1, position = 12, expected = 0 },
        }
        for _, target in ipairs(INDEPENDENT_TRACKS) do
            local other = target == "letter" and "battle" or "letter"
            for _, sample in ipairs(samples) do
                local m, h = newHarness(source, "GameBGM.lua", nil, { [defs[target].path] = sample.length })
                m.setScene(target); m.start(); h.sources[1].position = sample.position
                m.setScene(other); m.update(FADE_SECONDS)
                h.sources[2].position = 55
                m.setScene(target)
                near(h.sources[1].position, sample.expected,
                    "bounded resume " .. target .. " length=" .. sample.length .. " position=" .. sample.position)
                eq(#h.sources[1].seeks, sample.expected > 0 and 1 or 0, "invalid/zero resume never seeks")
                eq(#h.loads, 2, "bounds do not probe more candidates")
                assertNoRNG(h, "resume bounds")
                m.stop()
            end
        end
    end)
    runCase("BGM stopped source does not replace a valid saved departure", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.start(); h.sources[1].position = 19.75
        m.setScene("letter"); m.update(FADE_SECONDS)
        m.setScene("battle"); m.update(FADE_SECONDS)
        h.sources[1].position = 99.9; h.sources[1].playing = false
        m.setScene("letter"); m.update(FADE_SECONDS); m.setScene("battle")
        near(h.sources[1].position, 19.75, "stopped mixer cursor cannot overwrite last playing departure")
        m.stop()
    end)
    runCase("BGM symmetric 1.6 second fades and master volume preserve envelopes", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.setMasterGain(0.5); m.start(); m.setScene("letter")
        near(h.plays[2].gain, 0, "incoming starts silent")
        near(h.sources[1].gain, defs.battle.gain * 0.5, "old starts at current master")
        m.update(0); m.update(-5)
        near(h.sources[2].gain, 0, "nonpositive dt never advances incoming")
        near(h.sources[1].gain, defs.battle.gain * 0.5, "negative dt never reverses fade")
        m.update(0.8)
        near(h.sources[1].gain, defs.battle.gain * 0.5 * 0.5, "half-time outgoing 50 percent")
        near(h.sources[2].gain, defs.letter.gain * 0.5 * 0.5, "half-time incoming 50 percent")
        m.setMasterGain(0)
        near(h.sources[1].gain, 0, "mute old channel too")
        near(h.sources[2].gain, 0, "mute new channel too")
        m.setMasterGain(0.75)
        near(h.sources[1].gain, defs.battle.gain * 0.5 * 0.75, "unmute keeps outgoing envelope")
        near(h.sources[2].gain, defs.letter.gain * 0.5 * 0.75, "unmute keeps incoming envelope")
        m.setScene("letter", { fromStart = true }); m.update(0.4)
        near(h.sources[1].gain, defs.battle.gain * 0.25 * 0.75, "same key does not reset fading timer")
        near(h.sources[2].gain, defs.letter.gain * 0.75 * 0.75, "incoming continues uninterrupted")
        m.update(0.4)
        near(h.sources[1].gain, 0, "old reaches zero at 1.6 seconds")
        near(h.sources[2].gain, defs.letter.gain * 0.75, "new full at 1.6 seconds")
        eq(h.sources[1].playing, false, "outgoing stopped at fade completion")
        local stopped = h.sources[1].stops
        m.update(10000)
        eq(h.sources[1].stops, stopped, "completed envelope does not repeatedly stop")
        eq(#h.plays, 2, "volume updates never replay")
        m.setMasterGain(2); near(m.getMasterGain(), 1, "BGM high clamp")
        near(h.sources[2].gain, defs.letter.gain, "high clamp applied live")
        m.setMasterGain(-1); near(m.getMasterGain(), 0, "BGM low clamp")
        near(h.sources[2].gain, 0, "low clamp applied live")
        assertNoRNG(h, "volume fade")
        m.stop()
    end)
    runCase("BGM rapid narrative changes reuse two sources without stale fades", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.start(); h.sources[1].position = 27.25
        m.setScene("letter"); m.update(0.8); h.sources[2].position = 11.625
        m.setMasterGain(0.4)
        m.setScene("samsara")
        eq(#h.sources, 2, "rapid second switch reuses original channels")
        near(h.sources[1].gain, 0, "reused former outgoing source begins silent")
        near(h.sources[1].position, 0, "new samsara does not inherit old battle/letter cursor")
        m.update(0.8)
        near(h.sources[2].gain, defs.letter.gain * 0.5 * 0.5 * 0.4,
            "interrupted incoming fades out from actual envelope")
        near(h.sources[1].gain, defs.samsara.gain * 0.5 * 0.4, "new incoming half envelope")
        h.sources[1].position = 6.5
        m.setScene("town")
        near(h.sources[2].position, 27.25, "rapid alias return preserves original battle seconds")
        near(h.sources[2].gain, 0, "rapid return also starts new fade silent")
        m.update(FADE_SECONDS)
        eq(h.sources[1].playing, false, "only final outgoing stopped")
        eq(h.sources[2].playing, true, "latest battle source remains playing")
        near(h.sources[2].gain, defs.battle.gain * 0.4, "latest main gain has no stale envelope")
        m.setScene("letter"); near(h.sources[1].position, 11.625, "interrupted letter retains its own seconds")
        m.update(FADE_SECONDS); m.setScene("samsara")
        near(h.sources[2].position, 6.5, "interrupted samsara retains its own seconds")
        m.update(FADE_SECONDS)
        eq(#h.loads, 3, "rapid switching loads only three independent resources")
        eq(#h.sources, 2, "rapid transitions never expand source pool")
        assertNoRNG(h, "rapid transitions")
        m.stop()
    end)
    runCase("BGM pre-start choice and stop restart reset resources positions and pending fades", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.setScene("letter", { fromStart = true }); m.setMasterGain(0.4)
        eq(#h.loads, 0, "pre-start narrative select no IO")
        eq(m.getScene(), "letter", "pre-start selection retained")
        m.start()
        eq(h.loads[1], defs.letter.path, "letter starts without loading main")
        near(h.plays[1].gain, defs.letter.gain * 0.4, "pre-start master honored")
        h.sources[1].position = 22.75
        m.setScene("samsara"); m.update(0.8)
        m.stop(); m.stop(); m.update(10000)
        eq(h.nodes[1].removed, true, "stop removes node")
        for _, src in ipairs(h.sources) do eq(src.playing, false, "all stopped despite unfinished fade") end
        eq(m.getScene(), "samsara", "stop preserves selected canonical scene")
        near(m.getMasterGain(), 0.4, "stop preserves master")
        eq(#h.loads, 2, "stopped update no IO")
        eq(#h.plays, 2, "stopped update no replay")
        m.start()
        eq(#h.sources, 4, "restart creates two fresh channels")
        eq(h.plays[3].source, h.sources[3], "fresh lifecycle channel A")
        eq(h.loads[3], defs.samsara.path, "restart fetches selected only")
        near(h.sources[3].gain, defs.samsara.gain * 0.4, "restart starts full envelope not stale fade")
        near(h.sources[4].gain, 0, "restart inactive channel silent")
        m.setScene("letter")
        near(h.sources[4].position, 0, "stop clears saved letter seconds")
        eq(h.counts[defs.letter.path], 2, "stop clears successful resource cache")
        m.stop(); m.setScene("town_building")
        eq(m.getScene(), "battle", "stopped alias selection canonical")
        eq(#h.loads, 4, "stopped selection no IO")
        m.start()
        eq(h.loads[5], defs.battle.path, "restart follows stopped alias selection")
        near(h.sources[5].position, 0, "new lifecycle never resurrects old cursor")
        assertNoRNG(h, "lifecycle")
        m.stop()
    end)
    runCase("BGM missing narrative or main retains old audible track and latches only failed resource", function()
        for i, bad in ipairs(INDEPENDENT_TRACKS) do
            local good = INDEPENDENT_TRACKS[i % #INDEPENDENT_TRACKS + 1]
            local third = INDEPENDENT_TRACKS[(i + 1) % #INDEPENDENT_TRACKS + 1]
            local m, h = newHarness(source, "GameBGM.lua", { [defs[bad].path] = true })
            m.setScene(good); m.start(); h.sources[1].position = 31.25
            local badKeys = bad == "battle" and REGULAR_SCENES or { bad }
            for _ = 1, 20 do
                for _, key in ipairs(badKeys) do m.setScene(key, { fromStart = true }) end
                m.update(10000)
            end
            eq(h.counts[defs[bad].path], 1, "failed target once per lifecycle " .. bad)
            eq(#h.loads, 2, "failure never scans old battle candidates " .. bad)
            eq(countLogs(h, "加载失败: " .. defs[bad].path), 1, "failed resource log once " .. bad)
            eq(m.getScene(), good, "failed switch retains canonical old scene " .. bad)
            eq(#h.plays, 1, "failed switch never replays either channel " .. bad)
            eq(h.sources[1].playing, true, "old audible source retained " .. bad)
            near(h.sources[1].gain, defs[good].gain, "failure never starts fade-out " .. bad)
            near(h.sources[1].position, 31.25, "failure leaves old cursor intact " .. bad)
            h.failures[defs[bad].path] = nil
            m.setScene(bad)
            eq(h.counts[defs[bad].path], 1, "no hot retry after asset appears " .. bad)
            m.setScene(third); m.update(FADE_SECONDS)
            eq(m.getScene(), third, "other independent target not blocked " .. bad)
            m.stop(); m.setScene(bad); m.start()
            eq(h.counts[defs[bad].path], 2, "stop clears failed resource latch " .. bad)
            eq(h.plays[#h.plays].sound.path, defs[bad].path, "next lifecycle recovers failed target " .. bad)
            near(h.plays[#h.plays].source.position, 0, "recovered lifecycle starts zero " .. bad)
            assertNoRNG(h, "failure " .. bad)
            m.stop()
        end
    end)
    runCase("BGM missing initial main is silent not playlist fallback and can enter narrative", function()
        local m, h = newHarness(source, "GameBGM.lua", { [defs.battle.path] = true })
        m.start(); m.start()
        for _, key in ipairs(REGULAR_SCENES) do m.setScene(key); m.update(10000) end
        eq(#h.loads, 1, "initial failure tries only final main path, never old pool")
        eq(#h.plays, 0, "nil initial resource never played")
        near(h.sources[1].gain, 0, "failed initial channel silent")
        near(h.sources[2].gain, 0, "unused channel silent")
        eq(countLogs(h, "加载失败: " .. defs.battle.path), 1, "initial main failure logs once")
        m.setScene("letter"); m.update(FADE_SECONDS)
        eq(m.getScene(), "letter", "initial silence can recover to independent narrative")
        near(h.sources[2].position, 0, "silence never supplies progress to letter")
        m.setScene("popup")
        eq(m.getScene(), "letter", "failed alias return keeps narrative")
        eq(#h.loads, 2, "failed canonical main remains latched")
        eq(h.sources[2].playing, true, "old narrative stays audible on failed main return")
        assertNoRNG(h, "initial failure")
        m.stop()
    end)
    runCase("BGM failed target during fade does not reset successful envelope", function()
        local m, h = newHarness(source, "GameBGM.lua", { [defs.samsara.path] = true })
        m.start(); m.setScene("letter"); m.update(0.8)
        m.setScene("samsara"); m.update(0.4)
        eq(m.getScene(), "letter", "failure retains incoming letter")
        near(h.sources[1].gain, defs.battle.gain * 0.25, "outgoing keeps original fade timer")
        near(h.sources[2].gain, defs.letter.gain * 0.75, "incoming keeps original fade timer")
        eq(#h.plays, 2, "failure during fade no replay")
        m.update(0.4)
        eq(h.sources[1].playing, false, "original fade completes after failed request")
        near(h.sources[2].gain, defs.letter.gain, "successful incoming reaches full gain")
        assertNoRNG(h, "failed during fade")
        m.stop()
    end)
end

local function testNoAutoAdvance(source)
    runCase("BGM never auto advances at 90 percent ending wrap stopped or large dt", function()
        local defs = readDefinitions(source, "TRACKS")
        for _, key in ipairs(INDEPENDENT_TRACKS) do
            for _, gain in ipairs({ 0, 1 }) do
                local m, h = newHarness(source, "GameBGM.lua")
                m.setScene(key); m.setMasterGain(gain); m.start()
                local src = h.sources[1]
                for _, position in ipairs({ 90, 99.59, 99.6, 99.99, 0.05, 100, 120, 0 }) do
                    src.position = position
                    for _, dt in ipairs({ 0, -1, 0.01, 0.8, 10000 }) do m.update(dt) end
                    eq(#h.loads, 1, "no automatic next resource " .. key .. " at " .. position)
                    eq(#h.plays, 1, "no automatic replay/advance " .. key .. " at " .. position)
                    near(src.position, position, "manager never estimates cursor from dt")
                    eq(m.getScene(), key, "no automatic scene change")
                end
                src.playing = false
                for _ = 1, 10 do m.update(10000); m.setScene(key, { fromStart = true }) end
                eq(#h.loads, 1, "stopped source never starts candidate search")
                eq(#h.plays, 1, "stopped source never replayed by update or same key")
                eq(src.playing, false, "external mixer stop remains stopped")
                eq(#src.seeks, 0, "no auto Seek at ending/wrap/stopped")
                near(src.gain, defs[key].gain * gain, "no playlist envelope or gain changes")
                assertNoRNG(h, "ending/wrap/stopped " .. key)
                m.stop(); m.update(10000)
                eq(#h.plays, 1, "lifecycle stop cancels all update work")
            end
        end
    end)
    runCase("BGM wrap during narrative fade never queues a later automatic transition", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.setScene("letter"); m.start(); m.setScene("battle")
        h.sources[2].position = 90; m.update(0.4)
        h.sources[2].position = 0.05; m.update(0.4)
        h.sources[2].playing = false; m.update(0.8); m.update(10000)
        eq(#h.loads, 2, "fade wrap never loads old battle pool")
        eq(#h.plays, 2, "no latched wrap/stopped advance after fade")
        eq(m.getScene(), "battle", "fade wrap stays canonical main")
        assertNoRNG(h, "fade wrap")
        m.stop()
    end)
end

-- 只提取明确的音频片段，缺失锚点即失败；绝不 load 整个 UI/Standalone 模块。
local function exactFragment(source, first, after)
    local a = assert(source:find(first, 1, true), "missing fragment start " .. first)
    local b = assert(source:find(after, a + #first, true), "missing fragment end " .. after)
    return source:sub(a, b - 1)
end

local function testProductionFragments(bgmSource)
    runCase("SettingsPanel actual applyVolumes keeps BGM independent of SFX muted", function()
        local source = readSource("ui/hud/popup/SettingsPanel.lua")
        local fragment = exactFragment(source, "local function applyBgmVolume(vol)",
            "-- ============================================================================")
        local state = { muted = false, bgmVolume = 1, sfxVolume = 1 }
        local calls = { bgm = {}, effect = {} }
        local apply = assert(load(fragment .. "\nreturn applyVolumes", "@settings-fragment", "t", {
            state = state,
            GameBGM = { setMasterGain = function(v) calls.bgm[#calls.bgm + 1] = v end },
            audio = { SetMasterGain = function(_, kind, v)
                eq(kind, "Effect", "SFX mute touches only Effect not Music")
                calls.effect[#calls.effect + 1] = v
            end },
        }))()
        for _, muted in ipairs({ false, true }) do
            for _, bgm in ipairs({ 0, 0.35, 1 }) do
                for _, sfx in ipairs({ 0, 0.6, 1 }) do
                    state.muted, state.bgmVolume, state.sfxVolume = muted, bgm, sfx
                    local n = #calls.bgm
                    apply()
                    eq(#calls.bgm, n + 1, "BGM applied exactly once regardless of SFX mute")
                    near(calls.bgm[#calls.bgm], bgm, "BGM independent slider including muted startup")
                    near(calls.effect[#calls.effect], muted and 0 or sfx * 0.05, "unchanged SFX pack scaling")
                end
            end
        end
    end)
    runCase("Standalone actual sweep guard and early BGM update cover all later early returns", function()
        local source = readSource("boot/Standalone.lua")
        local fragment = exactFragment(source, "function HandleUpdate(eventType, eventData)",
            "    SidePanelBattlePause.refresh()")
        local _, updates = source:gsub("GameBGM%.update%s*%(%s*dt%s*%)", "")
        eq(updates, 1, "Standalone contains exactly one BGM update, no later duplicate")
        local calls = { update = 0, sweep = 0, paused = 0 }
        local pending = false
        local env = {
            GameBGM = { update = function(dt) calls.update = calls.update + 1; near(dt, 0.125, "real unscaled dt") end },
            LocalActionBridge = {
                isSweepPending = function() return pending end,
                updateSweep = function() calls.sweep = calls.sweep + 1 end,
            },
            require = function(name)
                eq(name, "ui.battle.combat.BattleClock", "prefix only dependency is sweep clock")
                return { setPaused = function(v) eq(v, true, "sweep pauses clock"); calls.paused = calls.paused + 1 end }
            end,
        }
        local update = assert(load(fragment .. "\nend\nreturn HandleUpdate", "@standalone-fragment", "t", env))()
        local event = { TimeStep = { GetFloat = function() return 0.125 end } }
        update("Update", event)
        eq(calls.update, 1, "BGM advances before prewarm/opening/error return sites")
        pending = true; update("Update", event)
        eq(calls.update, 1, "sweep-exclusive frame does not advance audio")
        eq(calls.sweep, 1, "sweep worker not starved")
        eq(calls.paused, 1, "sweep guard runs before BGM")
        pending = false; update("Update", event)
        eq(calls.update, 2, "next regular frame resumes one audio update")
    end)
    runCase("Standalone actual narrative route ignores UI tabs and preserves narrative guards", function()
        local source = readSource("boot/Standalone.lua")
        local fragment = exactFragment(source,
            "    if not (LetterIntro.isOpen() or IntroCutscene.isActive() or ScenarioDialogue.isActive()) then",
            "    -- [LetterIntro] 先祖来信更新")
        check(not fragment:find("BottomNav", 1, true), "route has no tab dependency")
        check(not fragment:find("GameBGM.update", 1, true), "route does not duplicate frame update")
        local flags = { letter = false, intro = false, dialogue = false, terminal = false, raid = false }
        local m, h = newHarness(bgmSource, "GameBGM.lua")
        m.start(); h.sources[1].position = 33.75
        local route = assert(load(fragment, "@standalone-fragment", "t", {
            GameBGM = m,
            LetterIntro = { isOpen = function() return flags.letter end },
            IntroCutscene = { isActive = function() return flags.intro end },
            ScenarioDialogue = { isActive = function() return flags.dialogue end },
            BattleScene = { isInTerminalTemple = function() return flags.terminal end },
            BattleTriPage = { isTerminalRaidActive = function() return flags.raid end },
        }))
        for _, key in ipairs(REGULAR_SCENES) do m.setScene(key); route() end
        eq(#h.loads, 1, "ordinary UI route never loads another track")
        eq(#h.plays, 1, "ordinary UI route never replays")
        near(h.sources[1].position, 33.75, "ordinary UI route remains continuous")
        for _, terminal in ipairs({ false, true }) do
            for _, raid in ipairs({ false, true }) do
                flags.terminal, flags.raid = terminal, raid
                route(); m.update(FADE_SECONDS)
                eq(m.getScene(), (terminal or raid) and "samsara" or "battle", "either terminal host controls narrative")
            end
        end
        for _, guard in ipairs({ "letter", "intro", "dialogue" }) do
            flags[guard] = true
            m.setScene("letter"); m.update(FADE_SECONDS)
            local plays, loads = #h.plays, #h.loads
            route()
            eq(m.getScene(), "letter", "narrative guard preserves letter " .. guard)
            eq(#h.plays, plays, "narrative guard no replay " .. guard)
            eq(#h.loads, loads, "narrative guard no load " .. guard)
            flags[guard] = false
        end
        assertNoRNG(h, "actual UI route")
        m.stop()
    end)
    runCase("Standalone Stop actual audio prefix releases pending fade", function()
        local source = readSource("boot/Standalone.lua")
        local fragment = exactFragment(source, "function Standalone.Stop()",
            "    require(\"core.PerformanceMonitor\").stop()")
        local m, h = newHarness(bgmSource, "GameBGM.lua")
        m.start(); m.setScene("letter"); m.update(0.4)
        local stop = assert(load(fragment .. "\nend\nreturn Standalone.Stop", "@standalone-fragment", "t",
            { Standalone = {}, GameBGM = m }))()
        stop(); m.update(10000)
        eq(h.nodes[1].removed, true, "Standalone audio prefix removes audio node")
        for _, src in ipairs(h.sources) do eq(src.playing, false, "Standalone audio stop releases both channels") end
        eq(#h.plays, 2, "post-stop update never restarts sound")
    end)
end

local function testSFX(source)
    local defs = readDefinitions(source, "SFX_DEFS")
    runCase("SFX start zero sounds + original six source pool", function()
        local m, h = newHarness(source, "GameSFX.lua")
        m.play("hit"); eq(#h.loads, 0, "not started does not fetch")
        eq(#h.randoms, 0, "not started does not random")
        m.start()
        eq(#h.loads, 0, "SFX start loads zero of 63 files")
        eq(#h.sources, 6, "original pool starts with six")
        eq(#h.plays, 0, "start plays nothing")
        for _, src in ipairs(h.sources) do eq(src.soundType, "Effect", "pool Effect channel") end
        m.start(); eq(#h.sources, 6, "start idempotent")
        eq(#h.randoms, 0, "start consumes no random")
        m.stop()
    end)
    runCase("SFX prewarm never plays or consumes random and keeps complete candidates", function()
        local m, h = newHarness(source, "GameSFX.lua")
        m.preload("hit"); m.preload("hit"); m.preload("unknown")
        eq(#h.loads, 2, "before start prewarm loads the complete hit group only once")
        eq(#h.randoms, 0, "prewarm never consumes random")
        eq(#h.plays, 0, "prewarm never plays")
        eq(#h.sources, 0, "prewarm never creates sources")
        m.start(); m.play("hit")
        eq(#h.loads, 2, "first attack reuses prepared candidates without resource IO")
        eq(h.randoms[1].high, 2, "first attack still selects among both original candidates")
        m.stop(); m.preload("hit")
        eq(#h.loads, 4, "stop clears prewarm cache for a fresh lifecycle")
    end)
    runCase("SFX cooperative prewarm publishes only complete current lifecycle", function()
        local queue = assert(load(readSource("boot/StartupQueue.lua"), "@audio-startup-queue", "t", {
            setmetatable = setmetatable, coroutine = coroutine, time = { elapsedTime = 0 },
        }))()
        local m, h = newHarness(source, "GameSFX.lua", nil, nil, queue)
        m.start()
        local worker = queue.new({ { "hit", function() m.preload("hit") end } },
            { maxImages = 1, clock = function() return 0 end })
        eq(worker:pump(), false, "two candidate prewarm suspends after first IO")
        eq(#h.loads, 1, "first pump fetched only first candidate")
        m.preload("hit"); m.play("hit")
        eq(#h.loads, 1, "reentry does not reload unfinished group")
        eq(#h.randoms, 0, "unfinished group cannot select truncated candidate list")
        eq(#h.plays, 0, "unfinished group cannot play partial list")
        eq(worker:pump(), true, "second pump completes group")
        eq(#h.loads, 2, "second pump fetches remaining candidate")
        m.play("hit")
        eq(h.randoms[1].high, 2, "completion publishes both original candidates")
        eq(h.randoms[1].loads, 2, "complete group available before random")
        m.stop(); m.start()
        local stale = queue.new({ { "old", function() m.preload("hit") end } },
            { maxImages = 1, clock = function() return 0 end })
        eq(stale:pump(), false, "old lifecycle suspended")
        m.stop(); m.start()
        m.preload("hit")
        eq(#h.loads, 5, "new lifecycle loads complete group independently")
        eq(stale:pump(), true, "old suspended worker exits cleanly")
        eq(#h.loads, 5, "stale worker does not fetch or publish old remainder")
        m.play("hit")
        eq(h.randoms[2].high, 2, "new lifecycle retains complete group")
        local stopped = queue.new({ { "stopped", function() m.preload("ui_pick") end } },
            { maxImages = 1, clock = function() return 0 end })
        eq(stopped:pump(), false, "another preload suspended")
        m.stop(); eq(stopped:pump(), true, "stop cancels stale preload without restart")
        m.start(); m.preload("ui_pick")
        eq(h.counts[defs.ui_pick.paths[1]], 2, "fresh lifecycle reloads first candidate")
        eq(h.counts[defs.ui_pick.paths[2]], 1, "stale second candidate never fetched")
        m.stop()
    end)
    runCase("SFX complete candidates before one random + reuse", function()
        local m, h = newHarness(source, "GameSFX.lua")
        m.start(); m.play("hit")
        eq(#h.loads, 2, "first hit loads both candidates")
        eq(h.loads[1], defs.hit.paths[1], "candidate order first")
        eq(h.loads[2], defs.hit.paths[2], "candidate order second")
        eq(#h.randoms, 1, "one random for first hit")
        eq(h.randoms[1].low, 1, "original random lower bound")
        eq(h.randoms[1].high, 2, "original random complete list size")
        eq(h.randoms[1].loads, 2, "all paths fetched before random")
        eq(h.timeline[3], "random", "no random path-first loading")
        eq(h.plays[1].sound, h.sounds[defs.hit.paths[1]], "first selected candidate")
        near(h.plays[1].gain, defs.hit.gain, "hit original gain")
        for _, path in ipairs(defs.hit.paths) do eq(h.sounds[path].looped, false, "SFX not looped") end
        m.play("hit")
        eq(#h.loads, 2, "second hit reuses complete list")
        eq(#h.randoms, 2, "repeated play still consumes one random")
        eq(h.plays[2].sound, h.sounds[defs.hit.paths[2]], "second selected candidate in same list")
        eq(#h.sources, 6, "play reuses pool")
        h.sources[1].playing = false; m.play("click")
        eq(#h.loads, 3, "single-candidate key lazy")
        eq(h.randoms[3].high, 1, "single candidate still random(1,1)")
        eq(h.plays[3].source, h.sources[1], "first idle source reused")
        m.stop()
    end)
    runCase("SFX muted gate + unmuted lazy + global call", function()
        local m, h = newHarness(source, "GameSFX.lua")
        m.setTeamMuted(2, true); m.start()
        for _ = 1, 40 do m.play("ui_pick", 2); m.play("unknown", 2) end
        eq(#h.loads, 0, "muted known/unknown never load")
        eq(#h.randoms, 0, "muted never consumes random")
        eq(countLogs(h, "未知音效"), 0, "muted unknown not logged")
        check(m.isTeamMuted("2"), "numeric string team matches")
        check(not m.isTeamMuted(1), "other team unmuted")
        m.play("ui_pick", 1)
        eq(#h.loads, 2, "unmuted other team loads full candidates")
        m.play("ui_pick", 2)
        eq(#h.randoms, 1, "muted cached key also no random")
        m.play("ui_pick")
        eq(#h.randoms, 2, "no team preserves global playback")
        m.setTeamMuted("2", false); m.play("ui_pick", 2)
        eq(#h.loads, 2, "unmute uses already cached list")
        eq(#h.randoms, 3, "unmuted play random once")
        m.setTeamMuted(3, true); m.stop(); m.start(); m.play("install", 3)
        eq(#h.loads, 2, "team mute remains across stop/restart")
        m.setTeamMuted(3, false); m.play("install", 3)
        eq(#h.loads, 3, "unmute after restart permits lazy load")
        m.stop()
    end)
    runCase("SFX all 60 keys / 63 paths retain gain and random lists", function()
        local m, h = newHarness(source, "GameSFX.lua")
        local keys, pathCount = {}, 0
        for key, def in pairs(defs) do keys[#keys + 1] = key; pathCount = pathCount + #def.paths end
        table.sort(keys)
        eq(#keys, 60, "original definition count")
        eq(pathCount, 63, "original path count")
        m.start()
        local expectedLoads = 0
        for i, key in ipairs(keys) do
            local def = defs[key]
            local previousLoads = #h.loads
            m.play(key)
            expectedLoads = expectedLoads + #def.paths
            eq(#h.loads, expectedLoads, "only requested candidates " .. key)
            for j, path in ipairs(def.paths) do
                eq(h.loads[previousLoads + j], path, "ordered full candidate " .. key .. "#" .. j)
                eq(h.sounds[path].looped, false, "nonlooping " .. key .. "#" .. j)
            end
            eq(#h.randoms, i, "one random per valid play " .. key)
            eq(h.randoms[i].high, #def.paths, "unchanged list size " .. key)
            eq(h.randoms[i].loads, expectedLoads, "complete candidates precede random " .. key)
            eq(h.plays[i].sound.path, def.paths[h.randoms[i].chosen], "ordered selection " .. key)
            near(h.plays[i].gain, def.gain, "original gain " .. key)
        end
        for _, key in ipairs(keys) do m.play(key) end
        eq(#h.loads, 63, "all candidate lists fetched only once")
        eq(#h.randoms, 120, "two plays of each key consume 120 random calls")
        for _, path in ipairs(h.loads) do eq(h.counts[path], 1, "one fetch per lifecycle " .. path) end
        eq(#h.sources, 12, "pool caps at original twelve")
        m.stop()
    end)
    runCase("SFX failed list + partial list + bounded hot logs", function()
        local m, h = newHarness(source, "GameSFX.lua", {
            [defs.hit.paths[1]] = true, [defs.hit.paths[2]] = true, [defs.ui_pick.paths[1]] = true,
        })
        m.start()
        for _ = 1, 40 do m.play("hit") end
        eq(#h.loads, 2, "all-failed key complete list attempted once")
        eq(#h.randoms, 0, "empty successful list consumes no random")
        eq(#h.plays, 0, "empty list never acquires/plays")
        for _, path in ipairs(defs.hit.paths) do
            eq(h.counts[path], 1, "failed path latched " .. path)
            eq(countLogs(h, "加载失败: " .. path), 1, "failed path logged once " .. path)
        end
        local previousLogs = #h.logs
        for _ = 1, 40 do m.play("hit") end
        eq(#h.logs, previousLogs, "known empty key no hot log spam")
        m.play("ui_pick")
        eq(#h.loads, 4, "partial key tries every original candidate")
        eq(h.randoms[1].high, 1, "partial failure random over successes as before")
        eq(h.plays[1].sound.path, defs.ui_pick.paths[2], "successful candidate order preserved")
        h.failures[defs.ui_pick.paths[1]] = nil
        m.play("ui_pick")
        eq(#h.loads, 4, "partial failure does not retry missing candidate")
        eq(h.randoms[2].high, 1, "cached successful list does not expand mid-lifecycle")
        for _ = 1, 40 do m.play("unknown_a"); m.play("unknown_b") end
        eq(countLogs(h, "未知音效"), 2, "unknown logs once per key")
        eq(#h.loads, 4, "unknown never requests resource")
        eq(#h.randoms, 2, "unknown never consumes random")
        h.failures[defs.hit.paths[1]] = nil; h.failures[defs.hit.paths[2]] = nil
        m.play("hit"); eq(#h.loads, 4, "all-failed stays latched until stop")
        m.stop(); m.start(); eq(#h.loads, 4, "restart still no preloading")
        m.play("hit")
        eq(h.counts[defs.hit.paths[1]], 2, "restart resets failed list")
        eq(h.counts[defs.hit.paths[2]], 2, "restart retries complete list")
        eq(h.randoms[3].high, 2, "recovered list restores two candidates")
        m.play("ui_pick"); eq(h.randoms[4].high, 2, "restart resets partial list")
        m.stop()
    end)
    runCase("SFX pool cap + master gain + stop restart + UI wrappers", function()
        local m, h = newHarness(source, "GameSFX.lua")
        m.setMasterGain(0.25); m.start()
        for _ = 1, 13 do m.play("click") end
        eq(#h.loads, 1, "concurrent plays share one Sound")
        eq(#h.sources, 12, "six expands only to twelve")
        eq(h.plays[12].source, h.sources[12], "twelfth uses last expanded source")
        eq(h.plays[13].source, h.sources[12], "full pool reuses last source")
        near(h.plays[1].gain, defs.click.gain * 0.25, "pre-start master honored")
        m.setMasterGain(0.5)
        near(h.sources[1].gain, defs.click.gain * 0.25, "existing SFX gain behavior unchanged")
        m.play("click"); near(h.plays[14].gain, defs.click.gain * 0.5, "new play uses latest master")
        m.setMasterGain(4); near(m.getMasterGain(), 1, "SFX high clamp")
        m.setMasterGain(-2); m.play("click")
        near(h.plays[15].gain, 0, "SFX low clamp still plays silently")
        eq(#h.randoms, 15, "gain zero not a new random gate")
        m.stop(); m.stop()
        eq(h.nodes[1].removed, true, "stop removes SFX node")
        for _, src in ipairs(h.sources) do eq(src.playing, false, "all pooled sources stopped") end
        m.play("hit")
        eq(#h.loads, 1, "stopped play no loading")
        eq(#h.randoms, 15, "stopped play no random")
        m.setMasterGain(0.3); m.start()
        eq(#h.loads, 1, "restart creates pool only")
        eq(#h.sources, 18, "restart rebuilds original six")
        m.play("click")
        eq(#h.loads, 2, "stop cleared successful sound list")
        eq(h.plays[16].source, h.sources[13], "fresh pool first source")
        near(h.plays[16].gain, defs.click.gain * 0.3, "restart retains master")
        m.playUIClick(); eq(h.loads[#h.loads], defs.ui_click_2.paths[1], "default UI click remains level2")
        m.playUIClick(-2); eq(h.loads[#h.loads], defs.ui_click_1.paths[1], "UI click low clamp")
        m.playUIClick(9); eq(h.loads[#h.loads], defs.ui_click_4.paths[1], "UI click high clamp")
        m.playUIMove(); eq(h.loads[#h.loads], defs.ui_move_2.paths[1], "default UI move remains level2")
        m.playUIMove(-2); eq(h.loads[#h.loads], defs.ui_move_1.paths[1], "UI move low clamp")
        m.playUIMove(9); eq(h.loads[#h.loads], defs.ui_move_4.paths[1], "UI move high clamp")
        m.stop()
    end)
end

function Start()
    local globalRandom = math.random
    local globalCache = cache
    local loadedBGM = package.loaded["systems.GameBGM"]
    local loadedSFX = package.loaded["systems.GameSFX"]
    local ok, why = pcall(function()
        local bgmSource = readSource("systems/GameBGM.lua")
        testBGM(bgmSource)
        testNoAutoAdvance(bgmSource)
        testProductionFragments(bgmSource)
        testSFX(readSource("systems/GameSFX.lua"))
        runCase("final main and retained battle OGG assets decode with real engine metadata", function()
            local defs = readDefinitions(bgmSource, "TRACKS")
            eq(defs.battle.path, "audio/bgm_dark_embers.ogg", "frozen final main candidate")
            local paths = { defs.battle.path, "audio/bgm_battle.ogg", "audio/bgm_battle_march.ogg", "audio/bgm_battle_moon.ogg" }
            local expectedLengths = { 179.988979, 90.024, 202.260979, 157.140979 }
            for i, path in ipairs(paths) do
                local sound = cache:GetResource("Sound", path)
                check(sound ~= nil, "real Sound exists " .. path)
                if sound then
                    check(math.abs(sound:GetLength() - expectedLengths[i]) < 0.1, "real duration " .. path)
                    eq(sound:GetIntFrequency(), 48000, "real sample rate " .. path)
                    check(sound:IsStereo(), "real stereo " .. path)
                    print(TAG .. " REAL_SOUND " .. path .. " seconds=" .. tostring(sound:GetLength()))
                end
            end
        end)
        eq(math.random, globalRandom, "global random untouched")
        eq(cache, globalCache, "global cache untouched")
        eq(package.loaded["systems.GameBGM"], loadedBGM, "real BGM require cache untouched")
        eq(package.loaded["systems.GameSFX"], loadedSFX, "real SFX require cache untouched")
    end)
    if not ok then check(false, "harness exception=" .. tostring(why)) end
    print(string.format("%s %s cases=%d assertions=%d failures=%d", TAG,
        totals.failures == 0 and "ALL PASS" or "FAIL", totals.cases, totals.assertions, totals.failures))
    engine:Exit()
end
