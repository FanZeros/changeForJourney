---@meta

--- Auto-generated from Resource/ResourceCache

---@class ResourceCache
---@field totalMemoryUse integer
---@field autoReloadResources boolean
---@field returnFailedResources boolean
---@field searchPackagesFirst boolean
---@field numBackgroundLoadResources integer
---@field resourceDirs string[]
---@field finishBackgroundResourcesMs integer
---@field GetResource __union_func__type_str__name_str__sendEventOnFailure_bool_opt__ret_ResourceT
ResourceCache = {}

---@param pathName string
---@param append? boolean
---@return boolean
function ResourceCache:AddResourceDir(pathName, append) end

---@param force? boolean
---@return nil
function ResourceCache:ReleaseAllResources(force) end

---@param resource Resource
---@return boolean
function ResourceCache:ReloadResource(resource) end

---@param fileName string
---@return nil
function ResourceCache:ReloadResourceWithDependencies(fileName) end

---@param type StringHash|string
---@param budget integer
---@return nil
function ResourceCache:SetMemoryBudget(type, budget) end

---@param type string
---@param budget integer
---@return nil
function ResourceCache:SetMemoryBudget(type, budget) end

---@param enable boolean
---@return nil
function ResourceCache:SetAutoReloadResources(enable) end

---@param enable boolean
---@return nil
function ResourceCache:SetReturnFailedResources(enable) end

---@param value boolean
---@return nil
function ResourceCache:SetSearchPackagesFirst(value) end

---@param ms integer
---@return nil
function ResourceCache:SetFinishBackgroundResourcesMs(ms) end

---@param name string
---@return File
function ResourceCache:GetFile(name) end

---@param type string
---@param name string
---@param sendEventOnFailure? boolean
---@return Resource
function ResourceCache:GetResourceAsyncEx(type, name, sendEventOnFailure) end

---@param type string
---@param name string
---@return Resource
function ResourceCache:GetExistingResource(type, name) end

---@param type string
---@param name string
---@param sendEventOnFailure? boolean
---@return boolean
function ResourceCache:BackgroundLoadResource(type, name, sendEventOnFailure) end

---@return integer
function ResourceCache:GetNumBackgroundLoadResources() end

---@return string[]
function ResourceCache:GetResourceDirs() end

---@param name string
---@return boolean
function ResourceCache:Exists(name) end

---@param type StringHash|string
---@return integer
function ResourceCache:GetMemoryBudget(type) end

---@param type StringHash|string
---@return integer
function ResourceCache:GetMemoryUse(type) end

---@return integer
function ResourceCache:GetTotalMemoryUse() end

---@param name string
---@return string
function ResourceCache:GetResourceFileName(name) end

---@return boolean
function ResourceCache:GetAutoReloadResources() end

---@return boolean
function ResourceCache:GetReturnFailedResources() end

---@return boolean
function ResourceCache:GetSearchPackagesFirst() end

---@return integer
function ResourceCache:GetFinishBackgroundResourcesMs() end

---@param path string
---@return string
function ResourceCache:GetPreferredResourceDir(path) end

---@param name string
---@return string
function ResourceCache:SanitateResourceName(name) end

---@param name string
---@return string
function ResourceCache:SanitateResourceDirName(name) end

---@param type string
---@param name string
---@param force? boolean
---@return nil
function ResourceCache:ReleaseResource(type, name, force) end


-- Global functions
---@return ResourceCache
function GetCache() end

-- Global variables
---@type ResourceCache
cache = nil
