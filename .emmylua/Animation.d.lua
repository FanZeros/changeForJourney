---@meta

--- Auto-generated from Graphics/Animation

---@class AnimationKeyFrame
---@field time number
---@field position Vector3
---@field rotation Quaternion
---@field scale Vector3
AnimationKeyFrame = {}


---@class AnimationTrack
---@field name string
---@field nameHash StringHash|string
---@field channelMask number -- unsigned char
---@field keyFrames AnimationKeyFrame[]
---@field numKeyFrames integer
AnimationTrack = {}

---@param index integer
---@param keyFrame AnimationKeyFrame
---@return nil
function AnimationTrack:SetKeyFrame(index, keyFrame) end

---@param keyFrame AnimationKeyFrame
---@return nil
function AnimationTrack:AddKeyFrame(keyFrame) end

---@param index integer
---@param keyFrame AnimationKeyFrame
---@return nil
function AnimationTrack:InsertKeyFrame(index, keyFrame) end

---@param index integer
---@return nil
function AnimationTrack:RemoveKeyFrame(index) end

---@return nil
function AnimationTrack:RemoveAllKeyFrames() end

---@param index integer
---@return AnimationKeyFrame
function AnimationTrack:GetKeyFrame(index) end

---@return integer
function AnimationTrack:GetNumKeyFrames() end


---@class AnimationTriggerPoint
---@overload fun(): AnimationTriggerPoint
---@field time number
---@field data Variant
AnimationTriggerPoint = {}

---@return AnimationTriggerPoint
function AnimationTriggerPoint.new() end


---@class Animation : ResourceWithMetadata
---@overload fun(): Animation
---@field animationName string
---@field length number
---@field numTracks integer
---@field numTriggers integer
Animation = {}

---@return Animation
function Animation.new() end

---@param name string
---@return nil
function Animation:SetAnimationName(name) end

---@param length number
---@return nil
function Animation:SetLength(length) end

---@param name string
---@return AnimationTrack
function Animation:CreateTrack(name) end

---@param name string
---@return boolean
function Animation:RemoveTrack(name) end

---@return nil
function Animation:RemoveAllTracks() end

---@param index integer
---@param trigger AnimationTriggerPoint
---@return nil
function Animation:SetTrigger(index, trigger) end

---@param trigger AnimationTriggerPoint
---@return nil
function Animation:AddTrigger(trigger) end

---@param time number
---@param timeIsNormalized boolean
---@param data Variant
---@return nil
function Animation:AddTrigger(time, timeIsNormalized, data) end

---@param index integer
---@return nil
function Animation:RemoveTrigger(index) end

---@return nil
function Animation:RemoveAllTriggers() end

---@param cloneName? string
---@return Animation
function Animation:Clone(cloneName) end

---@return string
function Animation:GetAnimationName() end

---@return number
function Animation:GetLength() end

---@return integer
function Animation:GetNumTracks() end

---@param name string
---@return AnimationTrack
function Animation:GetTrack(name) end

---@param nameHash StringHash|string
---@return AnimationTrack
function Animation:GetTrack(nameHash) end

---@param index integer
---@return AnimationTrack
function Animation:GetTrack(index) end

---@return integer
function Animation:GetNumTriggers() end

---@param index integer
---@return AnimationTriggerPoint
function Animation:GetTrigger(index) end


-- Global variables
---@type number -- unsigned char
CHANNEL_POSITION = nil
---@type number -- unsigned char
CHANNEL_ROTATION = nil
---@type number -- unsigned char
CHANNEL_SCALE = nil
