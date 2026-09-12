---@meta

--- Auto-generated from Engine/Engine

---@class Engine : Object
---@field minFps integer
---@field maxFps integer
---@field maxInactiveFps integer
---@field timeStepSmoothing integer
---@field pauseMinimized boolean
---@field autoExit boolean
---@field initialized boolean
---@field exiting boolean
---@field headless boolean
Engine = {}

---@return nil
function Engine:RunFrame() end

---@return Console
function Engine:CreateConsole() end

---@return DebugHud
function Engine:CreateDebugHud() end

---@param fps integer
---@return nil
function Engine:SetMinFps(fps) end

---@param fps integer
---@return nil
function Engine:SetMaxFps(fps) end

---@param fps integer
---@return nil
function Engine:SetMaxInactiveFps(fps) end

---@param frames integer
---@return nil
function Engine:SetTimeStepSmoothing(frames) end

---@param enable boolean
---@return nil
function Engine:SetPauseMinimized(enable) end

---@param enable boolean
---@return nil
function Engine:SetAutoExit(enable) end

---@return nil
function Engine:Exit() end

---@return nil
function Engine:DumpProfiler() end

---@param dumpFileName? boolean
---@return nil
function Engine:DumpResources(dumpFileName) end

---@return nil
function Engine:DumpMemory() end

---@return nil
function Engine:BeginLongTask() end

---@return nil
function Engine:EndLongTask() end

---@return integer
function Engine:GetMinFps() end

---@return integer
function Engine:GetMaxFps() end

---@return integer
function Engine:GetMaxInactiveFps() end

---@return integer
function Engine:GetTimeStepSmoothing() end

---@return boolean
function Engine:GetPauseMinimized() end

---@return boolean
function Engine:GetAutoExit() end

---@return boolean
function Engine:IsInitialized() end

---@return boolean
function Engine:IsExiting() end

---@return boolean
function Engine:IsHeadless() end


-- Global functions
---@return Engine
function GetEngine() end

-- Global variables
---@type Engine
engine = nil
