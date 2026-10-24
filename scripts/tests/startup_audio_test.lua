-- 启动音频懒加载回归：直接读取两份生产源码，在独立 env 中运行。
-- 音频管理器在独立 env 中使用 Sound/Scene/SoundSource/cache/math.random 替身；
-- 末尾另用真实 cache 校验三首战斗/四段神器 OGG 的解码信息，不创建音源或播放音频。
-- 不加载主游戏或玩家档。用 Runtime headless 运行，Start 最终 engine:Exit()。
local totals = { assertions = 0, failures = 0, cases = 0 }
local TAG = "[startup_audio_test]"
local ROOT = "/workspace/changeForJourney"
for _, argument in ipairs(type(GetArguments) == "function" and GetArguments() or {}) do
    local directory = argument:match("^%-tapcode_dir=(.+)$")
    if directory then ROOT = directory:gsub("/+$", "") end
end
local SOURCE_PATHS = { ["systems/GameBGM.lua"] = true, ["systems/GameSFX.lua"] = true,
    ["boot/StartupQueue.lua"] = true }
local nativeCache = cache
local sourceCache = {} ---@type table<string, string>
local CUE_KEYS = { "artifact_draw_charge", "artifact_draw_reveal", "artifact_draw_legendary", "artifact_draw_settle" }
local function shallowCopy(value)
    local result = {}
    for key, child in pairs(value) do result[key] = child end
    return result
end

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
    assert(SOURCE_PATHS[path], "source read outside fixed Lua whitelist " .. tostring(path))
    assert(ROOT:sub(1, 1) == "/" and not ROOT:find("..", 1, true), "unsafe -tapcode_dir")
    if sourceCache[path] then return sourceCache[path] end
    local file = assert(nativeCache:GetFile(path), "missing production source " .. ROOT .. "/scripts/" .. path)
    local ok, text = pcall(function()
        local lines = {}
        while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
        return table.concat(lines, "\n")
    end)
    file:Dispose()
    assert(ok, text)
    sourceCache[path] = text
    return text
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
        tostring = tostring, pairs = pairs, ipairs = ipairs, table = shallowCopy(table), string = shallowCopy(string),
        setmetatable = setmetatable, getmetatable = getmetatable, select = select, next = next,
        rawget = rawget, rawset = rawset,
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
            if h.failures[path] == "throw" then error("isolated Sound loader exception " .. path) end
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
                function src:Play(sound, ...)
                    assert(sound, "nil sound must not be played")
                    local argc = select("#", ...)
                    local frequency, gain = ...
                    assert(argc >= 0 and argc <= 2, "audio Play only accepts sound/frequency/explicit gain")
                    self.frequency = frequency
                    -- 两参Play沿用旧self.gain；三参Play采用指定gain（原生API会重置音源gain）。
                    if argc == 2 then self.gain = gain end
                    self.playing = true
                    self.position = 0
                    self.sound = sound
                    h.plays[#h.plays + 1] = { source = self, sound = sound, gain = self.gain,
                        frequency = frequency, gainArg = gain, argc = argc + 1 }
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
    env._G = env
    h.forbidden = {}
    local function denied(name)
        return function()
            h.forbidden[#h.forbidden + 1] = name
            error("isolated audio forbids " .. name)
        end
    end
    env.File, env.loadfile, env.dofile = denied("File"), denied("loadfile"), denied("dofile")
    for _, name in ipairs({ "network", "clientCloud", "serverCloud", "fileSystem", "io", "os", "package", "engine", "sdk" }) do
        env[name] = setmetatable({}, { __index = function(_, key) return denied(name .. "." .. tostring(key)) end })
    end
    setmetatable(env, { __index = function(_, key) return denied("global " .. tostring(key))() end })
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
        local f, fh = newHarness(source, "GameBGM.lua", {
            [defs.battle.path] = true,
            ["audio/bgm_battle_march.ogg"] = true,
            ["audio/bgm_battle_moon.ogg"] = true,
        })
        f.start(); f.start(); f.setScene("battle")
        eq(#fh.loads, 3, "all initial battle candidates attempted only once")
        eq(#fh.plays, 0, "initial missing track not played")
        eq(countLogs(fh, "加载失败: " .. defs.battle.path), 1, "initial fail log once")
        f.setScene("town"); f.update(1.2)
        eq(f.getScene(), "town", "silent initial channel can switch successfully")
        eq(fh.sources[2].position, 0, "no progress seek from missing initial sound")
        f.stop()
    end)
    runCase("BGM progress guards + master envelope", function()
        local m, h = newHarness(source, "GameBGM.lua", nil, { [defs.battle.path] = 0 })
        m.start(); h.sources[1].position = 10; m.setScene("town")
        eq(#h.sources[2].seeks, 0, "zero current length avoids division/seek")
        m.update(1.2); h.sources[2].playing = false; m.setScene("other")
        eq(#h.sources[1].seeks, 0, "nonplaying current source does not seek")
        m.stop()
        local v, vh = newHarness(source, "GameBGM.lua")
        v.setMasterGain(0.5); v.start(); v.setScene("town"); v.update(0.2)
        near(vh.sources[1].gain, 0.5 * 0.5 * 0.5, "fade-out applies master exactly once")
        near(vh.sources[2].gain, 0.4 / 6 * 0.5, "fade-in honors master")
        v.update(1.0); near(vh.sources[2].gain, 0.4 * 0.5, "final fade target honors master")
        v.stop()
    end)
end

local function testBattlePlaylist(source)
    local original = readDefinitions(source, "TRACKS").battle.path
    local additions = readDefinitions(source, "BATTLE_TRACKS")
    local march, moon = additions[1].path, additions[2].path
    runCase("battle playlist cycles three tracks without scene change or RNG", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.start()
        m.update(10000)
        eq(#h.plays, 1, "large gameplay dt alone does not finish a sound")
        h.sources[1].position = 99.59; m.update(0.01)
        eq(#h.loads, 1, "next track not loaded before ending")
        h.sources[1].position = 99.6; m.update(0.01)
        eq(#h.plays, 2, "ending starts next track")
        eq(h.plays[2].sound.path, march, "first addition follows original")
        eq(h.sources[2].position, 0, "natural transition begins at start")
        eq(h.sources[1].frequency, 0, "initial play restores sound sample rate")
        eq(h.sources[2].frequency, 0, "reused channel restores sound sample rate")
        eq(#h.sources[2].seeks, 0, "natural transition never percentage seeks")
        eq(m.getScene(), "battle", "public scene remains battle")
        for _ = 1, 100 do m.setScene("battle"); m.update(0.001) end
        eq(#h.plays, 2, "per-frame same scene does not reset track or fade")
        m.update(1.2)
        for i = 1, 12 do
            local active = h.plays[#h.plays].source
            active.position = 99.8
            m.update(0.01)
            local expected = ({ moon, original, march })[(i - 1) % 3 + 1]
            eq(h.plays[#h.plays].sound.path, expected, "stable full rotation " .. i)
            m.update(1.2)
            eq(h.plays[#h.plays - 1].source.playing, false, "outgoing channel stopped " .. i)
        end
        eq(#h.sources, 2, "playlist reuses only two sources")
        eq(#h.loads, 3, "each battle file loaded once")
        eq(#h.randoms, 0, "playlist never touches gameplay random")
        m.stop()
    end)
    runCase("battle playlist handles mixer wrap and stopped source", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.start(); h.sources[1].position = 90; m.update(0.1)
        h.sources[1].position = 0.1; m.update(0.1)
        eq(h.plays[2].sound.path, march, "missed ending frame detected by real wrap")
        m.update(1.2)
        h.sources[2].playing = false; m.update(0.1)
        eq(h.plays[3].sound.path, moon, "stopped active source advances once")
        m.update(0.1)
        eq(#h.plays, 3, "new source not skipped during fade")
        m.stop()
    end)
    runCase("battle playlist skips unavailable tracks and retains audible fallback", function()
        local m, h = newHarness(source, "GameBGM.lua", { [march] = true })
        m.start(); h.sources[1].position = 99.8; m.update(0.1)
        eq(h.plays[2].sound.path, moon, "missing second track skipped")
        eq(h.sources[1].playing, true, "old keeps playing during successful fade")
        eq(countLogs(h, "加载失败: " .. march), 1, "missing track logged once")
        m.update(1.2); h.sources[2].position = 99.8; m.update(0.1); m.update(1.2)
        h.sources[1].position = 99.8; m.update(0.1)
        eq(h.counts[march], 1, "missing candidate not retried on later rotations")
        eq(h.plays[#h.plays].sound.path, moon, "two available files alternate")
        m.stop()
        local f, fh = newHarness(source, "GameBGM.lua", { [march] = true, [moon] = true })
        f.start(); fh.sources[1].position = 99.8
        for _ = 1, 20 do f.update(0.1) end
        eq(#fh.plays, 1, "all additions missing never interrupts original")
        eq(fh.sources[1].playing, true, "original loops as fallback")
        eq(fh.counts[march], 1, "failed first addition bounded")
        eq(fh.counts[moon], 1, "failed second addition bounded")
        fh.sources[1].position = 0.1; f.update(0.1)
        eq(#fh.plays, 1, "fallback wrap does not duplicate replay")
        fh.failures[march] = nil
        f.stop(); f.start(); fh.sources[3].position = 99.8; f.update(0.1)
        eq(fh.plays[#fh.plays].sound.path, march, "restart clears failure latch")
        f.stop()
    end)
    runCase("battle playlist keeps scene boundaries and volume envelopes", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.start(); h.sources[1].position = 99.8; m.update(0.01)
        m.update(0.2)
        m.setMasterGain(0)
        near(h.sources[1].gain, 0, "mute outgoing too")
        near(h.sources[2].gain, 0, "mute incoming too")
        m.setMasterGain(0.5)
        near(h.sources[1].gain, 0.5 * 0.5 * 0.5, "unmute restores outgoing envelope")
        near(h.sources[2].gain, 0.5 / 6 * 0.5, "unmute does not skip fade")
        m.setScene("samsara", { fromStart = true }); m.update(1.2)
        local plays = #h.plays
        h.plays[plays].source.position = 99.8; m.update(200)
        eq(#h.plays, plays, "terminal scene does not enter battle pool")
        eq(m.getScene(), "samsara", "terminal scene retained")
        m.setScene("battle", { fromStart = true }); m.update(1.2)
        eq(h.plays[#h.plays].sound.path, march, "return retains current battle track")
        m.setMasterGain(0)
        h.plays[#h.plays].source.position = 99.8; m.update(0.1)
        eq(h.plays[#h.plays].sound.path, moon, "mute still rotates playlist")
        near(h.plays[#h.plays].source.gain, 0, "new muted track stays silent")
        m.stop(); local stoppedPlays = #h.plays; m.update(1000)
        eq(#h.plays, stoppedPlays, "stop cancels all playlist work")
        m.start()
        eq(h.plays[#h.plays].sound.path, moon, "restart retains current selection")
        m.stop()
    end)
    runCase("battle wrap during scene fade is retained until fade completes", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.setScene("town"); m.start(); h.sources[1].position = 99
        m.setScene("battle")
        near(h.sources[2].position, 99, "legacy scene synchronization retained")
        h.sources[2].position = 99.1; m.update(0.1)
        h.sources[2].position = 0.05; m.update(0.1)
        eq(#h.plays, 2, "wrap does not interrupt unfinished fade")
        h.sources[2].position = 0.2; m.update(1.0)
        eq(#h.plays, 3, "latched wrap advances after fade")
        eq(h.plays[3].sound.path, march, "wrapped first battle advances to march")
        eq(h.plays[3].source.position, 0, "latched transition also starts at zero")
        m.stop()
        local early, eh = newHarness(source, "GameBGM.lua")
        early.setScene("town"); early.start(); eh.sources[1].position = 99.99
        early.setScene("battle")
        eh.sources[2].position = 0.01; early.update(0.1)
        eq(#eh.plays, 2, "first-sample wrap waits for scene fade")
        early.update(1.1)
        eq(eh.plays[#eh.plays].sound.path, march, "seek provides baseline before first update")
        early.stop()
    end)
    runCase("retained battle track missing on restart or scene return falls back", function()
        local m, h = newHarness(source, "GameBGM.lua")
        m.start(); h.sources[1].position = 99.8; m.update(0.1); m.update(1.2)
        eq(h.plays[2].sound.path, march, "prepare retained march")
        m.stop(); h.failures[march] = true; m.start()
        eq(h.plays[3].sound.path, moon, "restart skips missing retained track")
        eq(h.plays[3].source.playing, true, "fallback is playing not silent")
        m.setScene("town"); m.update(1.2); m.stop()
        h.failures[moon] = true; m.start(); m.setScene("battle", { fromStart = true })
        eq(h.plays[#h.plays].sound.path, original, "scene return skips both missing additions")
        eq(m.getScene(), "battle", "fallback retains public battle scene")
        m.stop()
    end)
    runCase("short and unknown-length additions never storm transitions", function()
        local m, h = newHarness(source, "GameBGM.lua", nil, { [march] = 0, [moon] = 0.5 })
        m.start(); h.sources[1].position = 99.8
        for _ = 1, 60 do m.update(1) end
        eq(#h.plays, 1, "invalid durations preserve original")
        eq(#h.loads, 3, "invalid candidates cached rather than polled")
        eq(#h.randoms, 0, "duration failure does not use RNG")
        m.stop()
    end)
end

local function testSFX(source)
    local defs = readDefinitions(source, "SFX_DEFS")
    runCase("SFX start zero sounds + original six source pool", function()
        local m, h = newHarness(source, "GameSFX.lua")
        m.play("hit"); eq(#h.loads, 0, "not started does not fetch")
        eq(#h.randoms, 0, "not started does not random")
        m.start()
        eq(#h.loads, 0, "SFX start loads zero of 67 files")
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
    runCase("SFX all 64 keys / 67 paths preserve 60 random legacy keys", function()
        local m, h = newHarness(source, "GameSFX.lua")
        local keys, pathCount, legacyCount, cueCount = {}, 0, 0, 0
        local expectedCues = {}
        for _, key in ipairs(CUE_KEYS) do expectedCues[key] = true end
        for key, def in pairs(defs) do
            keys[#keys + 1] = key; pathCount = pathCount + #def.paths
            if def.deterministic == true then
                cueCount = cueCount + 1
                check(expectedCues[key], "only four artifact cues bypass RNG " .. key)
                eq(#def.paths, 1, "artifact cue has one deterministic candidate " .. key)
            else legacyCount = legacyCount + 1 end
        end
        table.sort(keys)
        eq(#keys, 64, "60 original + four cue definitions")
        eq(pathCount, 67, "63 original + four cue paths")
        eq(legacyCount, 60, "all original 60 keys remain nondeterministic")
        eq(cueCount, 4, "exactly four deterministic keys")
        m.start()
        local expectedLoads, expectedRandoms = 0, 0
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
            if def.deterministic == true then
                eq(#h.randoms, expectedRandoms, "cue consumes zero RNG " .. key)
                eq(h.plays[i].sound.path, def.paths[1], "fixed cue candidate " .. key)
                eq(h.plays[i].frequency, 0, "cue Play restores asset sample rate " .. key)
                eq(h.plays[i].argc, 3, "cue uses explicit gain Play overload " .. key)
                near(h.plays[i].gainArg, def.gain, "cue gain passed as third argument " .. key)
            else
                expectedRandoms = expectedRandoms + 1
                eq(#h.randoms, expectedRandoms, "one random per legacy play " .. key)
                eq(h.randoms[expectedRandoms].high, #def.paths, "unchanged list size " .. key)
                eq(h.randoms[expectedRandoms].loads, expectedLoads, "complete candidates precede random " .. key)
                eq(h.plays[i].sound.path, def.paths[h.randoms[expectedRandoms].chosen], "ordered selection " .. key)
                eq(h.plays[i].argc, 1, "old sound-only Play remains unchanged " .. key)
                eq(h.plays[i].frequency, nil, "old optional frequency remains absent " .. key)
            end
            near(h.plays[i].gain, def.gain, "defined gain " .. key)
        end
        for _, key in ipairs(keys) do m.play(key) end
        eq(#h.loads, 67, "all candidate lists fetched only once")
        eq(#h.randoms, 120, "only two plays of 60 legacy keys consume RNG")
        for _, path in ipairs(h.loads) do eq(h.counts[path], 1, "one fetch per lifecycle " .. path) end
        eq(#h.sources, 12, "pool caps at original twelve")
        eq(#h.forbidden, 0, "all-key pass stays inside audio source sandbox")
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

local function testArtifactCues(source)
    local defs = readDefinitions(source, "SFX_DEFS")
    local gains = { 0.60, 0.65, 0.70, 0.55 }
    runCase("artifact cue definitions / native-rate explicit-gain / no RNG", function()
        local m, h = newHarness(source, "GameSFX.lua")
        check(type(m.stopCue) == "function", "real manager exports stopCue")
        for i, key in ipairs(CUE_KEYS) do
            local def = assert(defs[key], "missing real deterministic cue " .. key)
            eq(def.deterministic, true, "explicit deterministic metadata " .. key)
            eq(#def.paths, 1, "one authored OGG per cue " .. key)
            eq(def.paths[1], "audio/sfx/" .. key .. ".ogg", "fixed resource path " .. key)
            near(def.gain, gains[i], "independent authored gain oracle " .. key)
            m.play(key); m.stopCue(key)
        end
        eq(#h.loads + #h.plays + #h.randoms, 0, "unstarted cue/stopCue does no work")
        m.setMasterGain(0.25); m.start()
        for i, key in ipairs(CUE_KEYS) do
            for _, src in ipairs(h.sources) do src.frequency, src.gain = 22050, 0.98 end
            m.play(key)
            local play = h.plays[#h.plays]
            eq(play.source, h.sources[1], "stopped cue reuses first source " .. key)
            eq(play.frequency, 0, "stale source frequency always restored " .. key)
            eq(play.argc, 3, "three argument Play(sound,0,gain) " .. key)
            near(play.gainArg, gains[i] * 0.25, "master applied once in Play argument " .. key)
            near(play.gain, gains[i] * 0.25, "fake models native explicit-gain overload " .. key)
            m.stopCue(key)
            eq(play.source.playing, false, "stopCue stops owned source " .. key)
            eq(play.source.stops, i, "one stop per active cue on reused first source " .. key)
            m.stopCue(key); eq(play.source.stops, i, "repeated stopCue does not stop idle source " .. key)
        end
        eq(#h.loads, 4, "four cue assets lazy loaded once")
        eq(#h.randoms, 0, "four cue plays never consume RNG")
        local beforeStops = h.sources[1].stops
        m.stopCue(nil); m.stopCue(false); m.stopCue({}); m.stopCue("unknown")
        eq(h.sources[1].stops, beforeStops, "invalid/unknown cue never touches source")
        m.stop()
    end)
    runCase("artifact prewarm and team mute keep deterministic lazy boundaries", function()
        local m, h = newHarness(source, "GameSFX.lua")
        for _, key in ipairs(CUE_KEYS) do m.preload(key); m.preload(key) end
        eq(#h.loads, 4, "prestart preload caches four exact candidates")
        eq(#h.plays + #h.sources + #h.randoms, 0, "cue prewarm creates no source/play/RNG")
        m.start(); m.setTeamMuted(2, true)
        for _, key in ipairs(CUE_KEYS) do m.play(key, "2") end
        eq(#h.loads, 4, "muted preloaded cues no extra IO")
        eq(#h.plays + #h.randoms, 0, "muted cues no play/RNG")
        m.setTeamMuted(2, false)
        for _, key in ipairs(CUE_KEYS) do m.play(key, 2) end
        eq(#h.plays, 4, "unmuted complete cache plays each cue")
        eq(#h.loads, 4, "unmuted plays reuse prewarmed assets")
        m.stop(); m.start(); m.setTeamMuted(2, true)
        for _, key in ipairs(CUE_KEYS) do m.play(key, 2) end
        eq(#h.loads, 4, "muted cold lifecycle does not load cue")
        m.setMasterGain(0); m.play(CUE_KEYS[1])
        eq(#h.loads, 5, "global gain zero retains original silent-play loading semantics")
        near(h.plays[5].gainArg, 0, "silent cue uses explicit zero gain")
        eq(h.plays[5].frequency, 0, "silent cue retains asset sample rate")
        eq(#h.randoms, 0, "mute/prewarm/silent cue never consumes RNG")
        m.setMasterGain(0.5)
        near(h.plays[5].source.gain, 0, "old SFX master-change only-next-play behavior retained")
        m.play(CUE_KEYS[1]); near(h.plays[6].gainArg, 0.30, "next cue uses latest master exactly once")
        m.stop()
    end)
    runCase("cue stopCue does not cancel unfinished prewarm but stop clears lifecycle", function()
        local queue = { checkpoint = function() coroutine.yield("isolated checkpoint") end }
        local m, h = newHarness(source, "GameSFX.lua", nil, nil, queue)
        m.start()
        local worker = coroutine.create(function() m.preload(CUE_KEYS[1]) end)
        check(coroutine.resume(worker), "prewarm enters suspended loading token")
        eq(#h.loads, 0, "suspended cue has not loaded its only path")
        m.stopCue(CUE_KEYS[1]); m.play(CUE_KEYS[1])
        eq(#h.loads + #h.plays + #h.randoms, 0, "stopCue neither publishes nor reloads incomplete cue")
        check(coroutine.resume(worker), "stopCue leaves cooperative prewarm alive")
        eq(coroutine.status(worker), "dead", "prewarm completed")
        eq(#h.loads, 1, "completed cue publishes its one candidate")
        m.play(CUE_KEYS[1]); eq(#h.plays, 1, "completed cue may subsequently play")
        local stale = coroutine.create(function() m.preload(CUE_KEYS[2]) end)
        check(coroutine.resume(stale), "second cue preload suspended")
        m.stop(); m.start()
        check(coroutine.resume(stale), "stale cue worker returns after stop")
        eq(#h.loads, 1, "old-lifecycle worker does not fetch its pending path")
        local fresh = coroutine.create(function() m.preload(CUE_KEYS[2]) end)
        check(coroutine.resume(fresh), "fresh lifecycle can load same key")
        check(coroutine.resume(fresh), "fresh key completes")
        m.play(CUE_KEYS[2]); eq(#h.plays, 2, "fresh lifecycle publishes usable cue only")
        eq(#h.randoms, 0, "all cooperative cue paths bypass RNG")
        m.stop()
    end)
    runCase("stopCue only latest source ownership including concurrent instances", function()
        local m, h = newHarness(source, "GameSFX.lua")
        m.start(); m.play(CUE_KEYS[1]); m.play(CUE_KEYS[1]); m.play(CUE_KEYS[2]); m.play("click")
        local first, second, other, legacy = h.sources[1], h.sources[2], h.sources[3], h.sources[4]
        m.stopCue(CUE_KEYS[1])
        eq(first.stops, 1, "first concurrent owner stopped")
        eq(second.stops, 1, "second concurrent owner stopped")
        check(other.playing and legacy.playing, "other cue and legacy key not stopped")
        eq(other.stops + legacy.stops, 0, "foreign owner never receives Stop")
        first.frequency = 16000; m.play(CUE_KEYS[3])
        eq(h.plays[5].source, first, "idle source reused by different cue")
        eq(first.frequency, 0, "reuse still restores new cue rate")
        m.stopCue(CUE_KEYS[1])
        eq(first.stops, 1, "old cue cannot stop reused different cue source")
        check(first.playing, "new owner survives stale stopCue")
        first.playing = false
        m.stopCue(CUE_KEYS[3]); eq(first.stops, 1, "naturally finished owner only cleared, not Stop")
        m.play("hit"); eq(h.plays[6].source, first, "legacy key reuses naturally idle cue source")
        m.stopCue(CUE_KEYS[3]); check(first.playing, "stale cue cannot stop reused legacy key")
        eq(first.stops, 1, "legacy reuse source receives no stale Stop")
        eq(#h.randoms, 2, "only click and hit use legacy RNG")
        m.stop()
    end)
    runCase("stopCue ownership survives full pool replacement and lifecycle reset", function()
        local m, h = newHarness(source, "GameSFX.lua")
        m.start()
        for _ = 1, 12 do m.play(CUE_KEYS[1]) end
        eq(#h.sources, 12, "cue expands original six only to original cap twelve")
        local last = h.sources[12]
        m.play(CUE_KEYS[2]); eq(h.plays[13].source, last, "full pool overwrites last source")
        m.stopCue(CUE_KEYS[1])
        for i = 1, 11 do eq(h.sources[i].stops, 1, "all still-owned full-pool instances stopped " .. i) end
        eq(last.stops, 0, "replaced last source is not stopped by old owner")
        check(last.playing, "new last-source cue stays playing")
        for i = 1, 11 do h.sources[i].playing = true end
        m.play("click"); eq(h.plays[14].source, last, "legacy full-pool overwrite also updates ownership")
        m.stopCue(CUE_KEYS[2]); eq(last.stops, 0, "old cue cannot stop legacy-overwritten last source")
        eq(last.sound.path, defs.click.paths[1], "legacy last-source sound still intact")
        eq(#h.randoms, 1, "only legacy full-pool click consumes RNG")
        m.stop(); m.start(); local before = #h.plays
        m.stopCue(CUE_KEYS[1]); m.stopCue(CUE_KEYS[2])
        for i = 13, 18 do eq(h.sources[i].stops, 0, "restart has no stale source owner " .. i) end
        eq(#h.plays, before, "stopCue never triggers another play")
        m.play(CUE_KEYS[4]); eq(h.plays[#h.plays].source, h.sources[13], "new lifecycle first source usable")
        m.stopCue(CUE_KEYS[4]); eq(h.sources[13].stops, 1, "new lifecycle owns its source only")
        m.stop()
    end)
    runCase("cue nil/throw loading latches safely; legacy exceptions still propagate", function()
        for _, failure in ipairs({ true, "throw" }) do
            for _, key in ipairs(CUE_KEYS) do
                local path = defs[key].paths[1]
                local m, h = newHarness(source, "GameSFX.lua", { [path] = failure })
                m.start()
                local success = pcall(function()
                    for _ = 1, 40 do m.preload(key); m.play(key); m.stopCue(key) end
                end)
                check(success, "new cue loader failure never throws " .. key .. " " .. tostring(failure))
                eq(h.counts[path], 1, "failed cue is latched once " .. key)
                eq(#h.plays + #h.randoms, 0, "failed cue never plays or consumes RNG " .. key)
                eq(countLogs(h, failure == "throw" and ("加载异常: " .. key) or ("加载失败: " .. path)), 1,
                    "failed cue logs once " .. key)
                h.failures[path] = nil; m.play(key)
                eq(h.counts[path], 1, "repair does not poll same-lifecycle failed asset " .. key)
                m.play(CUE_KEYS[key == CUE_KEYS[4] and 1 or 4])
                eq(#h.plays, 1, "one failed cue does not block other cue")
                m.stop(); m.start(); m.play(key)
                eq(h.counts[path], 2, "fresh lifecycle retries cue " .. key)
                eq(h.plays[#h.plays].sound.path, path, "fresh lifecycle cue recovered " .. key)
                eq(#h.randoms, 0, "failure/recovery other cues remain zero RNG")
                m.stop()
            end
        end
        local old, h = newHarness(source, "GameSFX.lua", { [defs.click.paths[1]] = "throw" })
        old.start()
        eq(pcall(function() old.play("click") end), false, "old key loader exception is not silently swallowed")
        eq(#h.randoms + #h.plays, 0, "throw occurs before legacy selection/play")
        old.stop()
        local absent, ah = newHarness(source, "GameSFX.lua")
        absent.init(nil); absent.start(); absent.play(CUE_KEYS[1]); absent.stopCue(CUE_KEYS[1])
        eq(#ah.sources + #ah.plays + #ah.randoms, 0, "no-scene cue never invents source or consumes RNG")
        absent.stop()
    end)
end

function Start()
    local globalRandom = math.random
    local globalCache = cache
    local loadedBGM = package.loaded["systems.GameBGM"]
    local loadedSFX = package.loaded["systems.GameSFX"]
    local ok, why = pcall(function()
        testBGM(readSource("systems/GameBGM.lua"))
        testBattlePlaylist(readSource("systems/GameBGM.lua"))
        testSFX(readSource("systems/GameSFX.lua"))
        testArtifactCues(readSource("systems/GameSFX.lua"))
        runCase("artifact four OGG decode metadata without real source or playback", function()
            local lengths = { 1.536, 0.720, 1.824, 0.624 }
            for i, key in ipairs(CUE_KEYS) do
                local path = "audio/sfx/" .. key .. ".ogg"
                local sound = nativeCache:GetResource("Sound", path)
                check(sound ~= nil, "real authored cue Sound exists " .. path)
                if sound then
                    check(math.abs(sound:GetLength() - lengths[i]) < 0.025, "authored cue duration " .. key)
                    eq(sound:GetIntFrequency(), 48000, "authored cue native sample rate " .. key)
                    check(sound:IsStereo(), "authored cue stereo channels " .. key)
                    print(TAG .. " REAL_SOUND " .. ROOT .. "/assets/" .. path .. " seconds=" .. tostring(sound:GetLength()))
                end
            end
        end)
        runCase("battle OGG assets load with real engine metadata", function()
            local paths = { "audio/bgm_battle.ogg", "audio/bgm_battle_march.ogg", "audio/bgm_battle_moon.ogg" }
            local expectedLengths = { 90.024, 202.260979, 157.140979 }
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
    if totals.failures > 0 then error(TAG .. " audio regression failures=" .. totals.failures, 0) end
end
