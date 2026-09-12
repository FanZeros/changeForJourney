---@meta

--- Auto-generated from Graphics/VideoPlayer

---@alias VideoState
---| integer # VideoState enum values

---@type VideoState
VIDEO_STOPPED = 0
---@type VideoState
VIDEO_PLAYING = 1
---@type VideoState
VIDEO_PAUSED = 2
---@type VideoState
VIDEO_ENDED = 3

---@alias VideoLoadResult
---| integer # VideoLoadResult enum values

---@type VideoLoadResult
--- Loading succeeded
VIDEO_LOAD_SUCCESS = 0
---@type VideoLoadResult
--- Failed to create decoder (platform not supported)
VIDEO_LOAD_ERROR_NO_DECODER = 1
---@type VideoLoadResult
--- Source path could not be resolved
VIDEO_LOAD_ERROR_SOURCE_NOT_FOUND = 2
---@type VideoLoadResult
--- Decoder Open() failed (unsupported codec, corrupt file, etc.)
VIDEO_LOAD_ERROR_OPEN_FAILED = 3
---@type VideoLoadResult
--- Texture initialization failed
VIDEO_LOAD_ERROR_TEXTURE_FAILED = 4
---@type VideoLoadResult
--- Loading was cancelled
VIDEO_LOAD_ERROR_CANCELLED = 5

---@class VideoTexture : Texture2D
---@overload fun(): VideoTexture
---@field videoWidth integer
---@field videoHeight integer
VideoTexture = {}

---@return VideoTexture
function VideoTexture.new() end

---@param width integer
---@param height integer
---@return boolean
function VideoTexture:Initialize(width, height) end

---@return nil
function VideoTexture:NotifyUpdate() end

---@return integer
function VideoTexture:GetVideoWidth() end

---@return integer
function VideoTexture:GetVideoHeight() end


---@class VideoPlayer : Object
---@overload fun(): VideoPlayer
---@field asyncLoading boolean
---@field volume number
---@field playbackRate number
---@field muted boolean
---@field looping boolean
---@field currentTime number
---@field duration number
---@field state VideoState
---@field playing boolean
---@field ready boolean
---@field texture VideoTexture
---@field videoWidth integer
---@field videoHeight integer
VideoPlayer = {}

---@return VideoPlayer
function VideoPlayer.new() end

---@param source string Video source: virtual path (e.g. "videos/intro.mp4"), uuid reference (e.g. "uuid://..."), or https URL
---@param width? integer
---@param height? integer
---@return boolean
function VideoPlayer:Load(source, width, height) end

---@return nil
function VideoPlayer:Play() end

---@return nil
function VideoPlayer:Pause() end

---@return nil
function VideoPlayer:Stop() end

---@param time number
---@return nil
function VideoPlayer:Seek(time) end

---@param volume number
---@return nil
function VideoPlayer:SetVolume(volume) end

---@param muted boolean
---@return nil
function VideoPlayer:SetMuted(muted) end

---@param loop boolean
---@return nil
function VideoPlayer:SetLoop(loop) end

---@param rate number Playback rate (0.25 to 4.0, default 1.0)
---@return nil
function VideoPlayer:SetPlaybackRate(rate) end

---@return number
function VideoPlayer:GetVolume() end

---@return boolean
function VideoPlayer:IsMuted() end

---@return boolean
function VideoPlayer:IsLooping() end

---@return number
function VideoPlayer:GetPlaybackRate() end

---@return number
function VideoPlayer:GetCurrentTime() end

---@return number
function VideoPlayer:GetDuration() end

---@return VideoState
function VideoPlayer:GetState() end

---@return boolean
function VideoPlayer:IsPlaying() end

---@return boolean
function VideoPlayer:IsReady() end

---@return VideoTexture
function VideoPlayer:GetTexture() end

---@return integer
function VideoPlayer:GetVideoWidth() end

---@return integer
function VideoPlayer:GetVideoHeight() end

---@return nil
function VideoPlayer:Update() end

--- Asynchronously load video from URL/path (non-blocking).
--- Loading happens on background thread (native) or natively async (WASM).
---@param source string Video URL or path
---@param width? integer Texture width (default 1920)
---@param height? integer Texture height (default 1080)
---@param callback? fun(result: integer) Completion callback with VideoLoadResult error code (0=success)
---@return boolean # true if async load was successfully started
function VideoPlayer:AsyncLoad(source, width, height, callback) end

---@return boolean
function VideoPlayer:IsAsyncLoading() end

