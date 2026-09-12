---@meta

--- Auto-generated from Resource/JSONFile

---@class JSONFile : Resource
---@overload fun(): JSONFile
JSONFile = {}

---@return JSONFile
function JSONFile.new() end

---@param source string
---@return boolean
function JSONFile:FromString(source) end

---@param indendation? string
---@return string
function JSONFile:ToString(indendation) end

---@return JSONValue
function JSONFile:GetRoot() end

---@param fileName string
---@param indentation? string
---@return boolean
function JSONFile:Save(fileName, indentation) end

