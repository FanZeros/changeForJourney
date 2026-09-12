---@meta

--- Auto-generated from Resource/XMLFile

---@class XMLFile : Resource
---@overload fun(): XMLFile
XMLFile = {}

---@return XMLFile
function XMLFile.new() end

---@param source string
---@return boolean
function XMLFile:FromString(source) end

---@param name? string
---@return XMLElement
function XMLFile:CreateRoot(name) end

---@param name? string
---@return XMLElement
function XMLFile:GetOrCreateRoot(name) end

---@param name? string
---@return XMLElement
function XMLFile:GetRoot(name) end

---@param indentation? string
---@return string
function XMLFile:ToString(indentation) end

---@param patchFile XMLFile
---@return nil
function XMLFile:Patch(patchFile) end

---@param patchElement XMLElement
---@return nil
function XMLFile:Patch(patchElement) end

---@param fileName string
---@param indentation? string
---@return boolean
function XMLFile:Save(fileName, indentation) end

