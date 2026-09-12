---@meta

--- Auto-generated from Audio/Sound

---@class Sound : ResourceWithMetadata
---@overload fun(): Sound
---@field length number
---@field dataSize integer
---@field sampleSize integer
---@field frequency number Default sample rate in Hz as a float.
---@field intFrequency integer Default sample rate in Hz as an integer.
---@field looped boolean
---@field sixteenBit boolean
---@field stereo boolean
---@field compressed boolean
Sound = {}

---@return Sound
function Sound.new() end

---@param source Deserializer
---@return boolean
function Sound:LoadRaw(source) end

---@param fileName string
---@return boolean
function Sound:LoadRaw(fileName) end

---@param source Deserializer
---@return boolean
function Sound:LoadWav(source) end

---@param fileName string
---@return boolean
function Sound:LoadWav(fileName) end

---@param source Deserializer
---@return boolean
function Sound:LoadOggVorbis(source) end

---@param fileName string
---@return boolean
function Sound:LoadOggVorbis(fileName) end

---@param source Deserializer
---@return boolean
function Sound:LoadMp3(source) end

---@param fileName string
---@return boolean
function Sound:LoadMp3(fileName) end

---@param dataSize integer
---@return nil
function Sound:SetSize(dataSize) end

-- Method SetData is not supported (uses void* pointer)

--- Set uncompressed sound data format.
---@param frequency integer Sample rate in Hz
---@param sixteenBit boolean Whether samples use 16-bit encoding
---@param stereo boolean Whether samples have two channels
---@return nil
function Sound:SetFormat(frequency, sixteenBit, stereo) end

---@param enable boolean
---@return nil
function Sound:SetLooped(enable) end

---@param repeatOffset integer
---@param endOffset integer
---@return nil
function Sound:SetLoop(repeatOffset, endOffset) end

---@return nil
function Sound:FixInterpolation() end

---@return number
function Sound:GetLength() end

---@return integer
function Sound:GetDataSize() end

---@return integer
function Sound:GetSampleSize() end

--- Return the sound resource's default sample rate without changing it.
---@return number # sample rate in Hz
function Sound:GetFrequency() end

--- Return the sound resource's default sample rate as an integer without changing it.
---@return integer # sample rate in Hz
function Sound:GetIntFrequency() end

---@return boolean
function Sound:IsLooped() end

---@return boolean
function Sound:IsSixteenBit() end

---@return boolean
function Sound:IsStereo() end

---@return boolean
function Sound:IsCompressed() end

