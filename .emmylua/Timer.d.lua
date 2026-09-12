---@meta

--- Auto-generated from Core/Timer

---@class Time : Object
---@field frameNumber integer
---@field timeStep number
---@field timerPeriod integer
---@field elapsedTime number
Time = {}

---@return integer
function Time:GetFrameNumber() end

---@return number
function Time:GetTimeStep() end

---@return integer
function Time:GetTimerPeriod() end

---@return number
function Time:GetElapsedTime() end

---@return number
function Time:GetFramesPerSecond() end

---@return integer
function Time:GetSystemTime() end

---@return integer
function Time:GetTimeSinceEpoch() end

---@return integer
function Time:GetTimeSinceEpochMs() end

---@return string
function Time:GetTimeStamp() end

---@param mSec integer
---@return nil
function Time:Sleep(mSec) end


-- Global functions
---@return Time
function GetTime() end

-- Global variables
---@type Time
time = nil
