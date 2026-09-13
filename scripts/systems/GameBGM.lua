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
    other         = { path = "audio/bgm_roster.ogg",   gain = 0.45 },  -- 角色/其他：笛声行进的冒险旅途
    popup         = { path = "audio/bgm_diary.ogg",    gain = 0.40 },  -- 日志：古琴书卷，深夜翻阅
    town          = { path = "audio/bgm_town.ogg",     gain = 0.40 },  -- 城镇：营地市集烟火气
    town_building = { path = "audio/bgm_building.ogg", gain = 0.38 },  -- 建筑内：炉火旁的古琴箫二重奏
    samsara       = { path = "audio/bgm_samsara.ogg",  gain = 0.50 },  -- 终焉神殿/轮回：编钟时间之门
    letter        = { path = "audio/bgm_letter.ogg",   gain = 0.35 },  -- [LetterIntro] 先祖来信：暗黑烛光读信氛围
}

-- ── 淡入淡出配置 ──
local FADE_OUT_TIME = 0.4    -- 旧轨道快速淡出（秒）
local FADE_IN_TIME  = 1.2    -- 新轨道缓慢淡入（秒）

-- ── 内部状态 ──
---@type Scene
local scene_     = nil
---@type Node
local bgmNode_   = nil
local started_   = false
local masterGain_ = 1.0   -- 主音量乘数 0~1（由 SettingsPanel 控制）

-- 已加载的 Sound 资源（key → Sound）
local sounds_    = {}

-- 双通道（A/B 交替使用）
---@type SoundSource
local srcA_      = nil
---@type SoundSource
local srcB_      = nil
local activeSlot_  = "A"       -- 当前活跃的通道
local activeKey_   = "battle"  -- 当前播放的轨道 key

-- 淡入淡出状态
local fading_       = false
local fadeTimer_    = 0
local fadeFromGain_ = 0   -- 淡出通道的起始音量
local fadeToGain_   = 0   -- 淡入通道的目标音量

-- ── 工具函数 ──
local function getActiveSource()
    return activeSlot_ == "A" and srcA_ or srcB_
end

local function getInactiveSource()
    return activeSlot_ == "A" and srcB_ or srcA_
end

-- ── 公开 API ──

---@param scene Scene
function GameBGM.init(scene)
    scene_ = scene
end

function GameBGM.start()
    if started_ then return end
    started_ = true
    if not scene_ then return end

    -- 预加载所有轨道
    for key, info in pairs(TRACKS) do
        local snd = cache:GetResource("Sound", info.path)
        if snd then
            snd.looped = true
            sounds_[key] = snd
        else
            print("[GameBGM] 加载失败: " .. info.path)
        end
    end

    bgmNode_ = scene_:CreateChild("GameBGM", LOCAL)

    -- 创建双通道
    srcA_ = bgmNode_:CreateComponent("SoundSource")
    srcA_.soundType = "Music"
    srcB_ = bgmNode_:CreateComponent("SoundSource")
    srcB_.soundType = "Music"

    -- 播放初始轨道
    local info = TRACKS[activeKey_]
    local snd  = sounds_[activeKey_]
    if snd and info then
        snd.looped = true  -- 确保循环标记生效
        srcA_.gain = info.gain * masterGain_
        srcA_:Play(snd)
    end
    srcB_.gain = 0

    activeSlot_ = "A"
    fading_ = false

    print("[GameBGM] 开始播放 track=" .. activeKey_)
end

--- 切换到指定场景的轨道
---@param sceneName string
---@param opts? { fromStart?: boolean }  fromStart=true 时从头播放，否则按进度同步
function GameBGM.setScene(sceneName, opts)
    if not TRACKS[sceneName] then return end
    if sceneName == activeKey_ then return end
    if not started_ then
        activeKey_ = sceneName
        return
    end

    local newSnd = sounds_[sceneName]
    if not newSnd then return end

    local activeSrc  = getActiveSource()
    local newSrc     = getInactiveSource()
    local newInfo    = TRACKS[sceneName]
    local fromStart  = opts and opts.fromStart

    -- 计算当前进度百分比（fromStart 时跳过）
    local pct = 0
    if not fromStart then
        local curSnd = sounds_[activeKey_]
        if curSnd and activeSrc:IsPlaying() then
            local len = curSnd:GetLength()
            if len > 0 then
                pct = activeSrc:GetTimePosition() / len
            end
        end
    end

    -- 在新通道上播放
    local newLen = newSnd:GetLength()
    newSnd.looped = true  -- 确保循环标记生效
    newSrc.gain = 0
    newSrc:Play(newSnd)
    if not fromStart and newLen > 0 and pct > 0 then
        newSrc:Seek(pct * newLen)
    end

    -- 启动交叉淡入淡出
    fadeFromGain_ = activeSrc.gain
    ---@diagnostic disable-next-line: assign-type-mismatch
    fadeToGain_   = newInfo.gain
    fadeTimer_    = 0
    fading_       = true

    -- 切换活跃通道
    activeKey_  = sceneName
    activeSlot_ = (activeSlot_ == "A") and "B" or "A"
end

---@return string
function GameBGM.getScene()
    return activeKey_
end

--- 每帧更新（处理淡入淡出）
--- 旧轨道快速淡出，新轨道同步缓慢淡入，切换零延迟
---@param dt number
function GameBGM.update(dt)
    if not fading_ then return end

    fadeTimer_ = fadeTimer_ + dt

    local activeSrc = getActiveSource()
    local oldSrc    = getInactiveSource()

    -- 旧轨道：快速淡出
    if fadeTimer_ < FADE_OUT_TIME then
        local t = fadeTimer_ / FADE_OUT_TIME
        oldSrc.gain = fadeFromGain_ * (1 - t) * masterGain_
    else
        oldSrc.gain = 0
    end

    -- 新轨道：同步缓慢淡入（立即开始，无延迟）
    if fadeTimer_ < FADE_IN_TIME then
        local t = fadeTimer_ / FADE_IN_TIME
        activeSrc.gain = fadeToGain_ * t * masterGain_
    else
        activeSrc.gain = fadeToGain_ * masterGain_
    end

    -- 两者都完成后结束
    if fadeTimer_ >= FADE_IN_TIME then
        oldSrc:Stop()
        oldSrc.gain = 0
        activeSrc.gain = fadeToGain_ * masterGain_
        fading_ = false
    end
end

--- 设置主音量乘数（0~1），立即生效
---@param gain number 音量乘数 0.0~1.0
function GameBGM.setMasterGain(gain)
    masterGain_ = math.max(0, math.min(1, gain))
    if not started_ then return end
    -- 立即更新当前活跃通道的音量
    local activeSrc = getActiveSource()
    local info = TRACKS[activeKey_]
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
    if srcA_ then srcA_:Stop() end
    if srcB_ then srcB_:Stop() end
    if bgmNode_ then bgmNode_:Remove() end
    srcA_    = nil
    srcB_    = nil
    bgmNode_ = nil
    started_ = false
    fading_  = false
    sounds_  = {}
end

return GameBGM
