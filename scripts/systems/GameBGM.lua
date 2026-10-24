-- ============================================================================
-- GameBGM  - 游戏内背景音乐管理（多轨进度同步切换）
-- 策略: 同一首曲子的不同氛围版本，切换时按进度百分比同步
--        使用双 SoundSource 交叉淡入淡出，实现无缝过渡
-- ============================================================================

local GameBGM = {}

-- ── 轨道定义 ──
-- [BGM v2] 全套重制：山海经暗黑古卷世界观·东方古风配乐，与 letter 轨同源风格
local TRACKS = {
    battle        = { path = "audio/bgm_battle.ogg",   gain = 0.50 },  -- 战斗：战鼓琵琶二胡，紧张古雅
    other         = { path = "audio/bgm_roster.ogg",   gain = 0.45 },  -- 角色/其他：笛声行进的远征旅途
    popup         = { path = "audio/bgm_diary.ogg",    gain = 0.40 },  -- 日志：古琴书卷，深夜翻阅
    town          = { path = "audio/bgm_town.ogg",     gain = 0.40 },  -- 城镇：营地市集烟火气
    town_building = { path = "audio/bgm_building.ogg", gain = 0.38 },  -- 建筑内：炉火旁的古琴箫二重奏
    samsara       = { path = "audio/bgm_samsara.ogg",  gain = 0.50 },  -- 终焉神殿/轮回：编钟时间之门
    letter        = { path = "audio/bgm_letter.ogg",   gain = 0.35 },  -- [LetterIntro] 先祖来信：暗黑烛光读信氛围
}

-- ── 淡入淡出配置 ──
local FADE_OUT_TIME = 0.4    -- 旧轨道快速淡出（秒）
local FADE_IN_TIME  = 1.2    -- 新轨道缓慢淡入（秒）

-- ── 播放器生命周期与资源 ──
---@type Scene
local scene_ = nil
---@type Node
local bgmNode_ = nil
local started_ = false
local masterGain_ = 1.0
local sounds_ = {}

-- 通道身份稳定，active 只决定下一次切换时谁接收新曲。
---@class BGMChannel
---@field source SoundSource?
---@type { A: BGMChannel, B: BGMChannel, active: string, key: string }
local channels_ = { A = {}, B = {}, active = "A", key = "battle" }

-- 每次切轨替换整个会话；中途切换直接复用另一通道，不先 Stop 旧会话。
---@class BGMFadeSession
---@field outgoing SoundSource
---@field incoming SoundSource
---@field elapsed number
---@field fromGain number 已含切换瞬间的主音量，更新时仍再乘一次（保持旧语义）
---@field toGain number 轨道原始目标音量
---@type BGMFadeSession?
local fade_ = nil

local function getActiveSource()
    return channels_.active == "A" and channels_.A.source or channels_.B.source
end

local function getInactiveSource()
    return channels_.active == "A" and channels_.B.source or channels_.A.source
end

local function preloadTracks()
    for key, info in pairs(TRACKS) do
        local snd = cache:GetResource("Sound", info.path)
        if snd then
            snd.looped = true
            sounds_[key] = snd
        else
            print("[GameBGM] 加载失败: " .. info.path)
        end
    end
end

-- 新曲播放/Seek 完成后才采样淡出起点，随后提交会话与活跃通道。
---@param outgoing SoundSource
---@param incoming SoundSource
---@param key string
local function beginFade(outgoing, incoming, key)
    local fromGain = outgoing.gain
    fade_ = {
        outgoing = outgoing, incoming = incoming,
        elapsed = 0, fromGain = fromGain, toGain = TRACKS[key].gain,
    }
    channels_.key = key
    channels_.active = channels_.active == "A" and "B" or "A"
end

---@param session BGMFadeSession
local function applyFade(session)
    -- 保持写入顺序：旧轨音量 → 新轨音量 → 完成帧 Stop/旧轨归零/新轨再写。
    -- 不钳制 elapsed，负 dt 与回退时间仍按原线性公式外推。
    if session.elapsed < FADE_OUT_TIME then
        local t = session.elapsed / FADE_OUT_TIME
        session.outgoing.gain = session.fromGain * (1 - t) * masterGain_
    else
        session.outgoing.gain = 0
    end

    if session.elapsed < FADE_IN_TIME then
        local t = session.elapsed / FADE_IN_TIME
        session.incoming.gain = session.toGain * t * masterGain_
    else
        session.incoming.gain = session.toGain * masterGain_
    end

    if session.elapsed >= FADE_IN_TIME then
        session.outgoing:Stop()
        session.outgoing.gain = 0
        session.incoming.gain = session.toGain * masterGain_
        fade_ = nil
    end
end

-- ── 公开 API ──

---@param scene Scene
function GameBGM.init(scene)
    scene_ = scene
end

function GameBGM.start()
    if started_ then return end
    -- 无 scene 也记 started；后续 init/start 不补启动，需显式 stop 后再试。
    started_ = true
    if not scene_ then return end

    preloadTracks()
    bgmNode_ = scene_:CreateChild("GameBGM", LOCAL)
    channels_.A.source = bgmNode_:CreateComponent("SoundSource")
    channels_.A.source.soundType = "Music"
    channels_.B.source = bgmNode_:CreateComponent("SoundSource")
    channels_.B.source.soundType = "Music"

    local info = TRACKS[channels_.key]
    local snd = sounds_[channels_.key]
    if snd and info then
        snd.looped = true
        channels_.A.source.gain = info.gain * masterGain_
        channels_.A.source:Play(snd)
    end
    channels_.B.source.gain = 0
    channels_.active = "A"
    fade_ = nil
    print("[GameBGM] 开始播放 track=" .. channels_.key)
end

--- 切换到指定场景的轨道
---@param sceneName string
---@param opts? { fromStart?: boolean }  fromStart=true 时从头播放，否则按进度同步
function GameBGM.setScene(sceneName, opts)
    if not TRACKS[sceneName] then return end
    if sceneName == channels_.key then return end
    if not started_ then
        channels_.key = sceneName
        return
    end

    local newSnd = sounds_[sceneName]
    if not newSnd then return end

    local activeSrc = getActiveSource()
    local newSrc = getInactiveSource()
    local fromStart = opts and opts.fromStart
    local pct = 0
    if not fromStart then
        local curSnd = sounds_[channels_.key]
        if curSnd and activeSrc:IsPlaying() then
            local len = curSnd:GetLength()
            if len > 0 then
                pct = activeSrc:GetTimePosition() / len
            end
        end
    end

    local newLen = newSnd:GetLength()
    newSnd.looped = true
    newSrc.gain = 0
    newSrc:Play(newSnd)
    if not fromStart and newLen > 0 and pct > 0 then
        newSrc:Seek(pct * newLen)
    end
    beginFade(activeSrc, newSrc, sceneName)
end

---@return string
function GameBGM.getScene()
    return channels_.key
end

--- 每帧更新：会话持有参与淡变的两个通道，不再由多组平行标志拼接状态。
---@param dt number
function GameBGM.update(dt)
    local session = fade_
    if not session then return end
    session.elapsed = session.elapsed + dt
    applyFade(session)
end

--- 设置主音量乘数（0~1），立即生效
---@param gain number 音量乘数 0.0~1.0
function GameBGM.setMasterGain(gain)
    masterGain_ = math.max(0, math.min(1, gain))
    if not started_ then return end
    -- 即便正在淡变，也仅立即写活跃通道，不重算会话起点/进度。
    local activeSrc = getActiveSource()
    local info = TRACKS[channels_.key]
    if activeSrc and info then
        activeSrc.gain = info.gain * masterGain_
    end
end

--- 获取当前主音量乘数
---@return number
function GameBGM.getMasterGain()
    return masterGain_
end

function GameBGM.stop()
    if channels_.A.source then channels_.A.source:Stop() end
    if channels_.B.source then channels_.B.source:Stop() end
    if bgmNode_ then bgmNode_:Remove() end
    channels_.A.source = nil
    channels_.B.source = nil
    bgmNode_ = nil
    started_ = false
    fade_ = nil
    sounds_ = {}
    -- 保留 scene、主音量、active 身份和 key；重启仍在 A 播放最后选择的曲目。
end

return GameBGM
