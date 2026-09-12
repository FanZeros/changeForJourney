---@meta

--- Auto-generated from Resource/Localization

---@class Localization : Object
---@field numLanguages integer
---@field languageIndex integer
---@field language string
Localization = {}

---@return integer
function Localization:GetNumLanguages() end

---@return integer
function Localization:GetLanguageIndex() end

---@param language string
---@return integer
function Localization:GetLanguageIndex(language) end

---@return string
function Localization:GetLanguage() end

---@param index integer
---@return string
function Localization:GetLanguage(index) end

---@param language string
---@return nil
function Localization:SetLanguage(language) end

---@param index integer
---@return nil
function Localization:SetLanguage(index) end

---@param id string
---@return string
function Localization:Get(id) end

---@return nil
function Localization:Reset() end

---@param source JSONValue
---@return nil
function Localization:LoadJSON(source) end

---@param name string
---@return nil
function Localization:LoadJSONFile(name) end

---@param path string
---@return nil
function Localization:SetUserPrefPath(path) end

---@return string
function Localization:ReadUserPrefLanguage() end

---@param language string
---@return nil
function Localization:SaveUserPrefLanguage(language) end

---@return string
function Localization:GetSystemLanguage() end

---@param lang string
---@return string
function Localization:MatchLanguage(lang) end

---@param lang string
---@param availableLangs string
---@return string
function Localization:MatchLanguage(lang, availableLangs) end


-- Global functions
---@return Localization
function GetLocalization() end

-- Global variables
---@type Localization
localization = nil
