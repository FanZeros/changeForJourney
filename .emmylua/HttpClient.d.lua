---@meta

--- Auto-generated from Network_Http/HttpClient

---@alias HttpMethod
---| integer # HttpMethod enum values

---@type HttpMethod
HTTP_GET = 0
---@type HttpMethod
HTTP_POST = 1
---@type HttpMethod
HTTP_PUT = 2
---@type HttpMethod
HTTP_DELETE = 3
---@type HttpMethod
HTTP_PATCH = 4

---@class HttpClient : RefCounted
HttpClient = {}

---@param url string
---@return HttpClient
function HttpClient:SetUrl(url) end

---@param method HttpMethod
---@return HttpClient
function HttpClient:SetMethod(method) end

---@param key string
---@param value string
---@return HttpClient
function HttpClient:AddQuery(key, value) end

---@param key string
---@param value string
---@return HttpClient
function HttpClient:AddHeader(key, value) end

---@param data string
---@return HttpClient
function HttpClient:SetBody(data) end

---@param contentType string
---@return HttpClient
function HttpClient:SetContentType(contentType) end

---@param msecs integer
---@return HttpClient
function HttpClient:SetTimeout(msecs) end

---@param callback fun(client: HttpClient, response: HttpResponse)
---@return HttpClient
function HttpClient:OnSuccess(callback) end

---@param callback fun(client: HttpClient, statusCode: integer, error: string)
---@return HttpClient
function HttpClient:OnError(callback) end

---@param callback fun(client: HttpClient, downloaded: integer, total: integer)
---@return HttpClient
function HttpClient:OnProgress(callback) end

---@return nil
function HttpClient:Send() end

---@return nil
function HttpClient:Cancel() end

---@return Context
function HttpClient:GetContext() end

