---@meta

--- Auto-generated from Network_Http/HttpManager

---@class HttpManager : Object
---@field activeRequestCount integer
HttpManager = {}

---@return HttpClient
function HttpManager:Create() end

--- 取消所有进行中的请求
---@return nil
function HttpManager:CancelAllRequests() end

--- 获取当前活动的请求数量
---@return integer
function HttpManager:GetActiveRequestCount() end


-- Global functions
---@return HttpManager
function GetHttp() end

-- Global variables
---@type HttpManager
http = nil
