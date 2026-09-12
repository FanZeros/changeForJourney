---@meta

--- Auto-generated from Network_Http/HttpResponse

---@class HttpResponse
---@field statusCode integer 状态码 (等同于 GetStatusCode())
---@field statusText string 状态文本 (等同于 GetStatusText())
---@field success boolean 是否成功 (等同于 IsSuccess())
---@field dataAsString string 响应数据字符串 (等同于 GetDataAsString())
---@field downloadedBytes integer 已下载字节数 (等同于 GetDownloadedBytes())
---@field totalBytes integer 总字节数 (等同于 GetTotalBytes())
---@field progress number 进度 0.0-1.0 (等同于 GetProgress())
HttpResponse = {}

--- 获取状态码
---@return integer
function HttpResponse:GetStatusCode() end

--- 获取状态文本
---@return string
function HttpResponse:GetStatusText() end

--- 判断请求是否成功（2xx）
---@return boolean
function HttpResponse:IsSuccess() end

--- 获取响应数据（字符串形式）
---@return string
function HttpResponse:GetDataAsString() end

--- 获取指定响应头
---@param name string
---@return string
function HttpResponse:GetHeader(name) end

--- 获取已下载字节数
---@return integer
function HttpResponse:GetDownloadedBytes() end

--- 获取总字节数
---@return integer
function HttpResponse:GetTotalBytes() end

--- 获取进度（0.0 - 1.0）
---@return number
function HttpResponse:GetProgress() end

