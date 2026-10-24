-- ============================================================================
-- GameBGM - 常规游玩单曲循环；仅开场与终焉叙事切换，双通道淡入淡出。
-- 菜单别名共用主曲，不轮播、不按其他曲目的播放百分比跳播、不消费玩法 RNG。
-- ============================================================================

local GameBGM = {}

-- 常规三栏同时存在，查看城镇、角色、装备或奖励不应改变整局音乐。
local TRACKS = {
    battle        = { path = "audio/bgm_dark_embers.ogg", gain = 0.40 },
    other         = { path = "audio/bgm_dark_embers.ogg", gain = 0.40 },
    popup         = { path = "audio/bgm_dark_embers.ogg", gain = 0.40 },
    town          = { path = "audio/bgm_dark_embers.ogg", gain = 0.40 },
    town_building = { path = "audio/bgm_dark_embers.ogg", gain = 0.40 },
    samsara       = { path = "audio/bgm_samsara.ogg", gain = 0.40 },
    letter        = { path = "audio/bgm_letter.ogg", gain = 0.30 },
}
-- 对称淡变避免旧曲已静音、新曲还只有三分之一音量的明显凹陷。
local FADE_OUT_TIME = 1.6
local FADE_IN_TIME = 1.6

---@type Scene?
local scene_ = nil
---@type Node?
local bgmNode_ = nil
---@type SoundSource?
local srcA_ = nil
---@type SoundSource?
local srcB_ = nil
local started_ = false
local masterGain_ = 1.0
---@type table<string, Sound>
local sounds_ = {}
local failedSounds_ = {}
---@type table<string, number>
local positions_ = {}
local activeSlot_ = "A"
local activeKey_ = "battle"
---@type table<string, number>
local sourceGains_ = { A = 0, B = 0 }
local fading_ = false
local fadeTimer_ = 0
---@type number
local fadeFromGain_ = 0
---@type number
local fadeToGain_ = 0

local function canonicalScene(key)
    if not TRACKS[key] then return nil end
    if key == "letter" or key == "samsara" then return key end
    return "battle"
end

---@param key string
---@return Sound?
local function ensureSound(key)
    local info = TRACKS[key]
    if sounds_[info.path] then return sounds_[info.path] end
    if failedSounds_[info.path] then return nil end
    local snd = cache:GetResource("Sound", info.path)
    if snd then
        snd.looped = true
        sounds_[info.path] = snd
    else
        failedSounds_[info.path] = true
        print("[GameBGM] 加载失败: " .. info.path)
    end
    return snd
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

-- 包络不含主音量，静音/调音量时既不重播，也不破坏当前淡变。
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

local function switchTrack(key, fromStart)
    -- 先确认新曲可用，加载失败不打断仍可听的旧曲。
    local snd = ensureSound(key)
    if not snd then return false end
    local activeSrc = getActiveSource()
    local newSrc = getInactiveSource()
    if not activeSrc or not newSrc then return false end
    if activeSrc:IsPlaying() then
        positions_[activeKey_] = math.max(0, activeSrc:GetTimePosition())
    end
    local info = TRACKS[key]
    local position = not fromStart and positions_[key] or 0
    local length = snd:GetLength()
    if not position or position < 0 or length <= 0 or position >= length then position = 0 end
    local nextSlot = inactiveSlot()
    setSourceGain(nextSlot, 0)
    -- 复用音源时显式恢复当前素材采样率，不继承其他曲目的播放频率。
    newSrc:Play(snd, 0)
    if position > 0 then newSrc:Seek(position) end
    fadeFromGain_ = sourceGains_[activeSlot_]
    fadeToGain_ = info.gain
    fadeTimer_ = 0
    fading_ = true
    activeKey_, activeSlot_ = key, nextSlot
    print("[GameBGM] 叙事切换 scene=" .. key .. " position=" .. position .. " track=" .. info.path)
    return true
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
    local snd = ensureSound(activeKey_)
    local info = TRACKS[activeKey_]
    if snd then
        setSourceGain("A", info.gain)
        srcA_:Play(snd, 0)
    else
        setSourceGain("A", 0)
    end
    fading_ = false
    print("[GameBGM] 单曲循环 scene=" .. activeKey_ .. " track=" .. info.path)
end

---@param sceneName string
---@param opts? { fromStart?: boolean }
function GameBGM.setScene(sceneName, opts)
    local key = canonicalScene(sceneName)
    if not key or key == activeKey_ then return end
    if not started_ then
        activeKey_ = key
        return
    end
    switchTrack(key, opts and opts.fromStart)
end

---@return string
function GameBGM.getScene()
    return activeKey_
end

---@param dt number
function GameBGM.update(dt)
    if not started_ or not fading_ then return end
    fadeTimer_ = fadeTimer_ + math.max(0, dt)
    applyFade()
    if fadeTimer_ >= FADE_IN_TIME then
        local src = getInactiveSource()
        if src then src:Stop() end
        fading_ = false
    end
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
    sounds_, failedSounds_, positions_ = {}, {}, {}
end

return GameBGM
