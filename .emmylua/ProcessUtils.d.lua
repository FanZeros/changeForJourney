---@meta

--- Auto-generated from Core/ProcessUtils

-- Global functions
---@param title string
---@param message string
---@return nil
function ErrorDialog(title, message) end

---@param message? string
---@param exitCode? integer
---@return nil
function ErrorExit(message, exitCode) end

---@return nil
function OpenConsoleWindow() end

---@param str string
---@param error? boolean
---@return nil
function PrintLine(str, error) end

---@param str string
---@param error? boolean
---@return nil
function PrintLine(str, error) end

---@return string[]
function GetArguments() end

---@return string
function GetConsoleInput() end

---@return string
function GetPlatform() end

---@return string
function GetNativePlatform() end

---@return integer
function GetNumPhysicalCPUs() end

---@return integer
function GetNumLogicalCPUs() end

---@param pathName string
---@return nil
function SetMiniDumpDir(pathName) end

---@return string
function GetMiniDumpDir() end

---@return integer
function GetTotalMemory() end

---@return string
function GetLoginName() end

---@return string
function GetHostName() end

---@return string
function GetOSVersion() end
