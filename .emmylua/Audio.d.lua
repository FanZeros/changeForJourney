---@meta

--- Auto-generated from Audio/Audio

---@class Audio : Object
---@field sampleSize integer
---@field mixRate integer
---@field interpolation boolean
---@field stereo boolean
---@field playing boolean
---@field initialized boolean
---@field listener SoundListener
Audio = {}

---@param bufferLengthMSec integer
---@param mixRate integer
---@param stereo boolean
---@param interpolation? boolean
---@return boolean
function Audio:SetMode(bufferLengthMSec, mixRate, stereo, interpolation) end

---@return boolean
function Audio:Play() end

---@return nil
function Audio:Stop() end

---@param type string
---@param gain number
---@return nil
function Audio:SetMasterGain(type, gain) end

---@param type string
---@return nil
function Audio:PauseSoundType(type) end

---@param type string
---@return nil
function Audio:ResumeSoundType(type) end

---@return nil
function Audio:ResumeAll() end

---@param listener SoundListener
---@return nil
function Audio:SetListener(listener) end

---@param sound Sound
---@return nil
function Audio:StopSound(sound) end

---@return integer
function Audio:GetSampleSize() end

---@return integer
function Audio:GetMixRate() end

---@return boolean
function Audio:GetInterpolation() end

---@return boolean
function Audio:IsStereo() end

---@return boolean
function Audio:IsPlaying() end

---@return boolean
function Audio:IsInitialized() end

---@param type string
---@return boolean
function Audio:HasMasterGain(type) end

---@param type string
---@return number
function Audio:GetMasterGain(type) end

---@param type string
---@return boolean
function Audio:IsSoundTypePaused(type) end

---@return SoundListener
function Audio:GetListener() end

---@return SoundSource[]
function Audio:GetSoundSources() end

---@param soundSource SoundSource
---@return nil
function Audio:AddSoundSource(soundSource) end

---@param soundSource SoundSource
---@return nil
function Audio:RemoveSoundSource(soundSource) end

-- Method MixOutput is not supported (uses void* pointer)


-- Global functions
---@return Audio
function GetAudio() end

-- Global variables
---@type string
SOUND_MASTER = nil
---@type string
SOUND_EFFECT = nil
---@type string
SOUND_AMBIENT = nil
---@type string
SOUND_VOICE = nil
---@type string
SOUND_MUSIC = nil
---@type Audio
audio = nil
