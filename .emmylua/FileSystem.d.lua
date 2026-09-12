---@meta

--- Auto-generated from IO/FileSystem

---@class FileSystem : Object
FileSystem = {}

---@param pathName string
---@return boolean
function FileSystem:SetCurrentDir(pathName) end

---@param pathName string
---@return boolean
function FileSystem:CreateDir(pathName) end

---@param enable boolean
---@return nil
function FileSystem:SetExecuteConsoleCommands(enable) end

---@param commandLine string
---@param redirectStdOutToLog? boolean
---@return integer
function FileSystem:SystemCommand(commandLine, redirectStdOutToLog) end

---@param fileName string
---@param arguments string[]
---@return integer
function FileSystem:SystemRun(fileName, arguments) end

---@param commandLine string
---@return integer
function FileSystem:SystemCommandAsync(commandLine) end

---@param fileName string
---@param arguments string[]
---@return integer
function FileSystem:SystemRunAsync(fileName, arguments) end

---@param fileName string
---@param mode? string
---@return boolean
function FileSystem:SystemOpen(fileName, mode) end

---@param srcFileName string
---@param destFileName string
---@return boolean
function FileSystem:Copy(srcFileName, destFileName) end

---@param srcFileName string
---@param destFileName string
---@return boolean
function FileSystem:Rename(srcFileName, destFileName) end

---@param fileName string
---@return boolean
function FileSystem:Delete(fileName) end

---@param fileName string
---@param newTime integer
---@return boolean
function FileSystem:SetLastModifiedTime(fileName, newTime) end

---@return string
function FileSystem:GetCurrentDir() end

---@return boolean
function FileSystem:GetExecuteConsoleCommands() end

---@return boolean
function FileSystem:HasRegisteredPaths() end

---@param pathName string
---@return boolean
function FileSystem:CheckAccess(pathName) end

---@param fileName string
---@return integer
function FileSystem:GetLastModifiedTime(fileName) end

---@param fileName string
---@return boolean
function FileSystem:FileExists(fileName) end

---@param pathName string
---@return boolean
function FileSystem:DirExists(pathName) end

---@param pathName string
---@param filter string
---@param flags integer
---@param recursive boolean
---@return string[]
function FileSystem:ScanDir(pathName, filter, flags, recursive) end

---@return string
function FileSystem:GetProgramDir() end

---@return string
function FileSystem:GetUserDocumentsDir() end

---@param org string
---@param app string
---@return string
function FileSystem:GetAppPreferencesDir(org, app) end

---@return string
function FileSystem:GetTemporaryDir() end

---@return boolean
function FileSystem:HasPersistentFS() end


-- Global functions
---@param fullPath string
---@return string
function GetPath(fullPath) end

---@param fullPath string
---@return string
function GetFileName(fullPath) end

---@param fullPath string
---@param lowercaseExtension? boolean
---@return string
function GetExtension(fullPath, lowercaseExtension) end

---@param fullPath string
---@param lowercaseExtension? boolean
---@return string
function GetFileNameAndExtension(fullPath, lowercaseExtension) end

---@param fullPath string
---@param newExtension string
---@return string
function ReplaceExtension(fullPath, newExtension) end

---@param pathName string
---@return string
function AddTrailingSlash(pathName) end

---@param pathName string
---@return string
function RemoveTrailingSlash(pathName) end

---@param pathName string
---@return string
function GetParentPath(pathName) end

---@param pathName string
---@return string
function GetInternalPath(pathName) end

---@param pathName string
---@return string
function GetNativePath(pathName) end

---@param pathName string
---@return boolean
function IsAbsolutePath(pathName) end

---@param memorySize integer
---@return string
function GetFileSizeString(memorySize) end

---@return FileSystem
function GetFileSystem() end

-- Global variables
---@type integer
SCAN_FILES = nil
---@type integer
SCAN_DIRS = nil
---@type integer
SCAN_HIDDEN = nil
---@type FileSystem
fileSystem = nil
