-- ============================================================================
-- GameBGM - 场景音乐与战斗曲池，双 SoundSource 交叉淡入淡出
-- 战斗曲按顺序轮播，不使用玩法 RNG；其他场景仍保留原进度同步切换。
-- ============================================================================

local GameBGM = {}

-- ── 轨道定义 ──
-- 山海经暗黑古卷世界观·东方古风配乐。
local TRACKS = {
    battle        = { path = "audio/bgm_battle.ogg",   gain = 0.50 },
    other         = { path = "audio/bgm_roster.ogg",   gain = 0.45 },
    popup         = { path = "audio/bgm_diary.ogg",    gain = 0.40 },
    town          = { path = "audio/bgm_town.ogg",     gain = 0.40 },
    town_building = { path = "audio/bgm_building.ogg", gain = 0.38 },
    samsara       = { path = "audio/bgm_samsara.ogg",  gain = 0.50 },
    letter        = { path = "audio/bgm_letter.ogg",   gain = 0.35 },
}

-- 首首沿用原战斗曲；新增曲在实际轮到时才加载。
---@type { path: string, gain: number }[]
local BATTLE_TRACKS = {
    { path = "audio/bgm_battle_march.ogg", gain = 0.50 },  -- 幽关行军
    { path = "audio/bgm_battle_moon.ogg",  gain = 0.50 },  -- 残月破阵
}
local FADE_OUT_TIME = 0.4
local FADE_IN_TIME = 1.2

---@type Scene
local scene_ = nil
---@type Node
local bgmNode_ = nil
---@type SoundSource
local srcA_ = nil
---@type SoundSource
local srcB_ = nil
local started_ = false
local masterGain_ = 1.0

---@type table<string, Sound>
local sounds_ = {}
local failedSounds_ = {}
local activeSlot_ = "A"
local activeKey_ = "battle"
local battleIndex_ = 1
local sourceGains_ = { A = 0, B = 0 }
---@type number|nil
local lastBattlePosition_ = nil
local battleEndHandled_ = false
local battleWrapped_ = false
local fading_ = false
local fadeTimer_ = 0
local fadeFromGain_ = 0
local fadeToGain_ = 0

local function trackInfo(key, battleIndex)
    if key == "battle" and battleIndex > 1 then return BATTLE_TRACKS[battleIndex - 1] end
    return TRACKS[key]
end

---@param key string
---@param battleIndex number
---@return Sound|nil
local function ensureSound(key, battleIndex)
    local info = trackInfo(key, battleIndex)
    if not info then return nil end
    if sounds_[info.path] then return sounds_[info.path] end
    if failedSounds_[info.path] then return nil end
    local snd = cache:GetResource("Sound", info.path)
    if snd then
        -- 保留循环兜底：下一首缺失时继续旧曲，不让曲池故障造成静音。
        snd.looped = true
        sounds_[info.path] = snd
    else
        failedSounds_[info.path] = true
        print("[GameBGM] 加载失败: " .. info.path)
    end
    return snd
end

local function availableBattleTrack(preferred)
    for offset = 0, #BATTLE_TRACKS do
        local index = (preferred - 1 + offset) % (#BATTLE_TRACKS + 1) + 1
        local snd = ensureSound("battle", index)
        if snd then return snd, index end
    end
    return nil, preferred
end

local function getActiveSource()
    return activeSlot_ == "A" and srcA_ or srcB_
end

local function getInactiveSource()
    return activeSlot_ == "A" and srcB_ or srcA_
end

local function inactiveSlot()
    return activeSlot_ == "A" and "B" or "A"
end

-- 通道包络不含主音量，避免淡出二次乘音量，以及拖动音量滑条时跳过淡入。
local function setSourceGain(slot, gain)
    sourceGains_[slot] = gain
    local src = slot == "A" and srcA_ or srcB_
    if src then src.gain = gain * masterGain_ end
end

local function applyFade()
    local out = math.max(0, 1 - fadeTimer_ / FADE_OUT_TIME)
    local incoming = math.min(1, fadeTimer_ / FADE_IN_TIME)
    setSourceGain(inactiveSlot(), fadeFromGain_ * out)
    setSourceGain(activeSlot_, fadeToGain_ * incoming)
end

local function switchTrack(key, index, fromStart)
    local snd = ensureSound(key, index)
    if not snd and key == "battle" then snd, index = availableBattleTrack(index) end
    if not snd then return false end
    local activeSrc = getActiveSource()
    local newSrc = getInactiveSource()
    local info = trackInfo(key, index)
    local pct = 0
    if not fromStart then
        local currentInfo = trackInfo(activeKey_, battleIndex_)
        local current = sounds_[currentInfo.path]
        if current and activeSrc:IsPlaying() and current:GetLength() > 0 then
            pct = activeSrc:GetTimePosition() / current:GetLength()
        end
    end
    local nextSlot = inactiveSlot()
    setSourceGain(nextSlot, 0)
    -- 每次恢复素材原采样率，复用通道不继承上一首的播放频率。
    newSrc:Play(snd, 0)
    if not fromStart and snd:GetLength() > 0 and pct > 0 then newSrc:Seek(pct * snd:GetLength()) end
    fadeFromGain_ = sourceGains_[activeSlot_]
    fadeToGain_ = info.gain
    fadeTimer_ = 0
    fading_ = true
    activeKey_ = key
    if key == "battle" then battleIndex_ = index end
    activeSlot_ = nextSlot
    lastBattlePosition_ = newSrc:GetTimePosition()
    battleEndHandled_ = false
    battleWrapped_ = false
    print("[GameBGM] 切换 scene=" .. key .. " track=" .. info.path)
    return true
end

local function updateBattlePlaylist()
    if activeKey_ ~= "battle" then return end
    local src = getActiveSource()
    local info = trackInfo("battle", battleIndex_)
    local snd = sounds_[info.path]
    if not snd then return end
    local length = snd:GetLength()
    if length <= FADE_IN_TIME then return end
    local position = src:GetTimePosition()
    local wrapped = lastBattlePosition_ ~= nil and position < lastBattlePosition_
    lastBattlePosition_ = position
    if wrapped then
        battleEndHandled_ = false
        battleWrapped_ = true
    end
    if fading_ or battleEndHandled_ then return end
    -- 用实际播放位置而非战斗 dt 计时；静音照常轮播，玩法暂停不伪推进音频。
    if position < length - FADE_OUT_TIME and not battleWrapped_ and src:IsPlaying() then return end
    battleWrapped_ = false
    battleEndHandled_ = true
    for offset = 1, #BATTLE_TRACKS do
        local index = (battleIndex_ - 1 + offset) % (#BATTLE_TRACKS + 1) + 1
        local nextSound = ensureSound("battle", index)
        if nextSound and nextSound:GetLength() > FADE_IN_TIME then
            -- 自然换曲从头开始，不把旧曲的尾部百分比传给下一首。
            switchTrack("battle", index, true)
            return
        end
    end
end

---@param scene Scene
function GameBGM.init(scene)
    scene_ = scene
end

function GameBGM.start()
    if started_ or not scene_ then return end
    started_ = true
    bgmNode_ = scene_:CreateChild("GameBGM", LOCAL)
    srcA_ = bgmNode_:CreateComponent("SoundSource")
    srcA_.soundType = "Music"
    srcB_ = bgmNode_:CreateComponent("SoundSource")
    srcB_.soundType = "Music"
    activeSlot_ = "A"
    sourceGains_ = { A = 0, B = 0 }
    setSourceGain("B", 0)
    local snd = ensureSound(activeKey_, battleIndex_)
    if not snd and activeKey_ == "battle" then snd, battleIndex_ = availableBattleTrack(battleIndex_) end
    local info = trackInfo(activeKey_, battleIndex_)
    if snd then
        setSourceGain("A", info.gain)
        srcA_:Play(snd, 0)
    else
        setSourceGain("A", 0)
    end
    fading_ = false
    lastBattlePosition_ = nil
    battleEndHandled_ = false
    battleWrapped_ = false
    print("[GameBGM] 开始播放 scene=" .. activeKey_ .. " track=" .. info.path)
end

---@param sceneName string
---@param opts? { fromStart?: boolean }
function GameBGM.setScene(sceneName, opts)
    if not TRACKS[sceneName] or sceneName == activeKey_ then return end
    if not started_ then
        activeKey_ = sceneName
        return
    end
    switchTrack(sceneName, battleIndex_, opts and opts.fromStart)
end

---@return string
function GameBGM.getScene()
    return activeKey_
end

---@param dt number
function GameBGM.update(dt)
    if not started_ then return end
    if fading_ then
        fadeTimer_ = fadeTimer_ + math.max(0, dt)
        applyFade()
        if fadeTimer_ >= FADE_IN_TIME then
            getInactiveSource():Stop()
            fading_ = false
        end
    end
    updateBattlePlaylist()
end

---@param gain number
function GameBGM.setMasterGain(gain)
    masterGain_ = math.max(0, math.min(1, gain))
    if not started_ then return end
    setSourceGain("A", sourceGains_.A)
    setSourceGain("B", sourceGains_.B)
end

---@return number
function GameBGM.getMasterGain()
    return masterGain_
end

function GameBGM.stop()
    if srcA_ then srcA_:Stop() end
    if srcB_ then srcB_:Stop() end
    if bgmNode_ then bgmNode_:Remove() end
    srcA_, srcB_, bgmNode_ = nil, nil, nil
    started_ = false
    fading_ = false
    sourceGains_ = { A = 0, B = 0 }
    lastBattlePosition_ = nil
    battleEndHandled_ = false
    battleWrapped_ = false
    sounds_ = {}
    failedSounds_ = {}
end

return GameBGM
