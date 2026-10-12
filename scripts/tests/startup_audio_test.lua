-- 启动音频懒加载回归：直接读取两份生产源码，在独立 env 中运行。
-- Sound/Scene/SoundSource/cache/math.random 仅本测试替身，不改全局或 package.loaded；
-- 不加载主游戏、玩家档或真实音频。用 Runtime headless 运行，Start 最终 engine:Exit()。
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
        loads = {}, counts = {}, sounds = {}, nodes = {}, sources = {}, plays = {}, randoms = {}, logs = {},
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
                function src:Play(sound)
                    assert(sound, "nil sound must not be played")
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

local function testBGM(source)
    local defs = readDefinitions(source, "TRACKS")
    runCase("BGM start only active track + idempotent", function()
        local m, h = newHarness(source, "GameBGM.lua")
        eq(#h.loads, 0, "init does not fetch sound")
        m.start()
        eq(#h.loads, 1, "start fetches one of seven tracks")
        eq(h.loads[1], "audio/bgm_battle.ogg", "default active battle")
        eq(#h.nodes, 1, "one BGM node")
        eq(#h.sources, 2, "two original channels")
        eq(h.sources[1].soundType, "Music", "channel A Music")
        eq(h.sources[2].soundType, "Music", "channel B Music")
        eq(#h.plays, 1, "start plays A once")
        eq(h.plays[1].source, h.sources[1], "initial channel A")
        eq(h.plays[1].sound.looped, true, "BGM loops")
        near(h.plays[1].gain, 0.50, "battle original gain")
        near(h.sources[2].gain, 0, "inactive channel silent")
        m.start(); m.setScene("battle"); m.setScene("unknown")
        eq(#h.loads, 1, "repeated start/same/unknown no fetch")
        eq(#h.plays, 1, "no replay for same scene")
        eq(#h.randoms, 0, "BGM consumes no random")
        m.stop()
    end)
    runCase("BGM pre-start selection + restart current track", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.setScene("letter", { fromStart = true }); m.setMasterGain(0.4)
        eq(#h.loads, 0, "select before start is metadata only")
        eq(m.getScene(), "letter", "pre-start selection retained")
        m.start()
        eq(#h.loads, 1, "letter start loads one")
        eq(h.loads[1], defs.letter.path, "loads chosen letter not battle")
        near(h.plays[1].gain, defs.letter.gain * 0.4, "pre-start master gain")
        m.stop(); m.stop(); m.update(10)
        eq(h.nodes[1].removed, true, "stop removes node")
        eq(h.sources[1].playing, false, "A stopped")
        eq(h.sources[2].playing, false, "B stopped")
        eq(m.getScene(), "letter", "stop keeps selection")
        near(m.getMasterGain(), 0.4, "stop keeps volume")
        m.setScene("town")
        eq(#h.loads, 1, "stopped select does not fetch")
        m.start()
        eq(#h.loads, 2, "restart only selected track")
        eq(h.loads[2], defs.town.path, "restart loads town")
        eq(#h.sources, 4, "restart creates two fresh channels")
        eq(h.plays[2].source, h.sources[3], "restart starts fresh A")
        near(h.plays[2].gain, defs.town.gain * 0.4, "restart keeps master gain")
        m.stop()
    end)
    runCase("BGM lazy switching + progress + dual fade", function()
        local m, h = newHarness(source, "GameBGM.lua", nil,
            { [defs.battle.path] = 100, [defs.town.path] = 200, [defs.other.path] = 80 })
        m.start()
        h.sources[1].position = 25
        m.setScene("town")
        eq(#h.loads, 2, "switch first loads only town")
        eq(h.loads[2], defs.town.path, "different track lazy path")
        eq(h.plays[2].source, h.sources[2], "switch uses B")
        eq(h.plays[2].sound.looped, true, "lazy track loops")
        near(h.sources[2].position, 50, "25 percent synced to 200s")
        near(h.plays[2].gain, 0, "new track begins silent")
        m.update(0.2)
        near(h.sources[1].gain, 0.25, "old fades across 0.4 seconds")
        near(h.sources[2].gain, 0.4 / 6, "new fades across 1.2 seconds")
        m.update(1.0)
        eq(h.sources[1].playing, false, "old stops after fade")
        near(h.sources[2].gain, 0.4, "new reaches defined gain")
        m.setScene("battle")
        eq(#h.loads, 2, "cached return no resource fetch")
        eq(h.plays[3].source, h.sources[1], "return alternates to A")
        eq(h.plays[3].sound, h.plays[1].sound, "same cached Sound")
        near(h.sources[1].position, 25, "return sync to old battle length")
        m.update(1.2)
        m.setScene("other", { fromStart = true })
        eq(#h.loads, 3, "third distinct track lazy")
        eq(h.sources[2].position, 0, "fromStart does not seek")
        eq(#h.sources[2].seeks, 1, "only earlier town seek recorded")
        m.update(1.2)
        m.setMasterGain(0.5)
        near(h.sources[2].gain, defs.other.gain * 0.5, "live master gain immediately applied")
        m.setMasterGain(2); near(m.getMasterGain(), 1, "BGM high clamp")
        m.setMasterGain(-1); near(h.sources[2].gain, 0, "BGM low clamp")
        m.stop()
    end)
    runCase("BGM all definitions remain lazy and cached", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.start()
        local keys = { "town", "town_building", "popup", "samsara", "letter", "other", "battle" }
        for _, key in ipairs(keys) do
            m.setScene(key); m.update(1.2)
            eq(h.plays[#h.plays].sound.path, defs[key].path, "track path " .. key)
            near(h.plays[#h.plays].source.gain, defs[key].gain, "track gain " .. key)
            eq(h.plays[#h.plays].sound.looped, true, "track loops " .. key)
        end
        eq(#h.loads, 7, "all seven loaded only after visiting")
        for _, info in pairs(defs) do eq(h.counts[info.path], 1, "one fetch " .. info.path) end
        m.setScene("town"); m.update(1.2)
        eq(#h.loads, 7, "all visited track reused")
        m.stop(); m.start()
        eq(#h.loads, 8, "new lifecycle fetches current track only")
        eq(h.loads[8], defs.town.path, "stop clears previous sound cache")
        m.stop()
    end)
    runCase("BGM failures latch once and recover next lifecycle", function()
        local m, h = newHarness(source, "GameBGM.lua", { [defs.town.path] = true })
        m.start()
        for _ = 1, 40 do m.setScene("town") end
        eq(h.counts[defs.town.path], 1, "failed switch tried once")
        eq(countLogs(h, "加载失败: " .. defs.town.path), 1, "failed switch log once")
        eq(m.getScene(), "battle", "failure keeps previous active scene")
        eq(#h.plays, 1, "failure never interrupts current source")
        eq(h.sources[1].playing, true, "previous track still playing")
        h.failures[defs.town.path] = nil
        m.setScene("town")
        eq(h.counts[defs.town.path], 1, "no hot recovery retry in same lifecycle")
        m.setScene("other"); m.update(1.2)
        eq(m.getScene(), "other", "other keys not blocked by failed track")
        m.stop(); m.setScene("town"); m.start()
        eq(h.counts[defs.town.path], 2, "stop clears failure latch")
        eq(h.plays[#h.plays].sound.path, defs.town.path, "restart can recover missing track")
        m.stop()
        local f, fh = newHarness(source, "GameBGM.lua", { [defs.battle.path] = true })
        f.start(); f.start(); f.setScene("battle")
        eq(#fh.loads, 1, "initial failure also once")
        eq(#fh.plays, 0, "initial missing track not played")
        eq(countLogs(fh, "加载失败: " .. defs.battle.path), 1, "initial fail log once")
        f.setScene("town"); f.update(1.2)
        eq(f.getScene(), "town", "silent initial channel can switch successfully")
        eq(fh.sources[2].position, 0, "no progress seek from missing initial sound")
        f.stop()
    end)
    runCase("BGM progress guards + original master fade behavior", function()
        local m, h = newHarness(source, "GameBGM.lua", nil, { [defs.battle.path] = 0 })
        m.start(); h.sources[1].position = 10; m.setScene("town")
        eq(#h.sources[2].seeks, 0, "zero current length avoids division/seek")
        m.update(1.2); h.sources[2].playing = false; m.setScene("other")
        eq(#h.sources[1].seeks, 0, "nonplaying current source does not seek")
        m.stop()
        local v, vh = newHarness(source, "GameBGM.lua")
        v.setMasterGain(0.5); v.start(); v.setScene("town"); v.update(0.2)
        -- 原实现 fadeFromGain 已含 master，淡出时再乘 master；本优化不顺手改音量契约。
        near(vh.sources[1].gain, 0.5 * 0.5 * 0.5 * 0.5, "original fade-out volume retained")
        near(vh.sources[2].gain, 0.4 / 6 * 0.5, "fade-in honors master")
        v.update(1.0); near(vh.sources[2].gain, 0.4 * 0.5, "final fade target honors master")
        v.stop()
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
        testBGM(readSource("systems/GameBGM.lua"))
        testSFX(readSource("systems/GameSFX.lua"))
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
