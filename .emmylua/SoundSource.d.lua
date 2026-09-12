---@meta

--- Auto-generated from Audio/SoundSource


---@class SoundSource : Component
---@field sound Sound
---@field soundType string
---@field timePosition number
---@field frequency number Current absolute playback frequency in Hz, not a pitch multiplier. Set 0 before Play(sound) to use the sound's sample rate.
---@field gain number
---@field attenuation number
---@field panning number
---@field autoRemoveMode AutoRemoveMode
---@field playing boolean
---@field fadingIn boolean
---@field fadingOut boolean
---@field declickEnabled boolean
SoundSource = {}

---@param seekTime number
---@return nil
function SoundSource:Seek(seekTime) end

--- Play a sound. A zero source frequency is initialized from the sound's sample rate; a non-zero source frequency is retained.
---@param sound Sound Sound resource to play
---@return nil
function SoundSource:Play(sound) end

--- Play a sound at an absolute playback frequency.
---@param sound Sound Sound resource to play
---@param frequency number Playback frequency in Hz, not a pitch multiplier; pass 0 to use the sound's sample rate
---@return nil
function SoundSource:Play(sound, frequency) end

--- Play a sound at an absolute playback frequency and gain.
---@param sound Sound Sound resource to play
---@param frequency number Playback frequency in Hz, not a pitch multiplier; pass 0 to use the sound's sample rate
---@param gain number Linear gain where 0 is silence and 1 is full volume
---@return nil
function SoundSource:Play(sound, frequency, gain) end

--- Play a sound at an absolute playback frequency, gain and stereo panning.
---@param sound Sound Sound resource to play
---@param frequency number Playback frequency in Hz, not a pitch multiplier; pass 0 to use the sound's sample rate
---@param gain number Linear gain where 0 is silence and 1 is full volume
---@param panning number Stereo panning from -1 (left) to 1 (right)
---@return nil
function SoundSource:Play(sound, frequency, gain, panning) end

---@return nil
function SoundSource:Stop() end

---@return nil
function SoundSource:StopImmediate() end

---@param enable boolean
---@return nil
function SoundSource:SetDeclickEnabled(enable) end

---@return boolean
function SoundSource:GetDeclickEnabled() end

---@param type string
---@return nil
function SoundSource:SetSoundType(type) end

--- Set the absolute playback frequency. This changes the SoundSource, not the Sound resource.
---@param frequency number Playback frequency in Hz, not a pitch multiplier; 0 is resolved by the next Play(Sound*) call
---@return nil
function SoundSource:SetFrequency(frequency) end

---@param gain number
---@return nil
function SoundSource:SetGain(gain) end

---@param attenuation number
---@return nil
function SoundSource:SetAttenuation(attenuation) end

---@param panning number
---@return nil
function SoundSource:SetPanning(panning) end

---@param mode AutoRemoveMode
---@return nil
function SoundSource:SetAutoRemoveMode(mode) end

---@return Sound
function SoundSource:GetSound() end

---@return string
function SoundSource:GetSoundType() end

---@return number
function SoundSource:GetTimePosition() end

--- Return the current absolute playback frequency of this SoundSource.
---@return number # playback frequency in Hz
function SoundSource:GetFrequency() end

---@return number
function SoundSource:GetGain() end

---@return number
function SoundSource:GetAttenuation() end

---@return number
function SoundSource:GetPanning() end

---@return AutoRemoveMode
function SoundSource:GetAutoRemoveMode() end

--- Return whether is playing. Returns true during fade-in, false during fade-out.
---@return boolean
function SoundSource:IsPlaying() end

--- Return whether a fade-in is in progress.
---@return boolean
function SoundSource:IsFadingIn() end

--- Return whether a fade-out is in progress.
---@return boolean
function SoundSource:IsFadingOut() end

