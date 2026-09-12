---@meta

--- Auto-generated from IO/Log

---@class Log : Object
---@field level integer
---@field timeStamp boolean
---@field quiet boolean
Log = {}

---@param fileName string
---@return nil
function Log:Open(fileName) end

---@return nil
function Log:Close() end

---@param level integer
---@return nil
function Log:SetLevel(level) end

---@param enable boolean
---@return nil
function Log:SetTimeStamp(enable) end

---@param quiet boolean
---@return nil
function Log:SetQuiet(quiet) end

---@return integer
function Log:GetLevel() end

---@return boolean
function Log:GetTimeStamp() end

---@return string
function Log:GetLastMessage() end

---@return boolean
function Log:IsQuiet() end

---@param level integer
---@param message string
---@return nil
function Log:Write(level, message) end

---@param message string
---@param error? boolean
---@return nil
function Log:WriteRaw(message, error) end


-- Global functions
---@return Log
function GetLog() end

-- Global variables
---@type integer
LOG_TRACE = nil
---@type integer
LOG_DEBUG = nil
---@type integer
LOG_INFO = nil
---@type integer
LOG_WARNING = nil
---@type integer
LOG_ERROR = nil
---@type integer
LOG_NONE = nil
---@type Log
log = nil
