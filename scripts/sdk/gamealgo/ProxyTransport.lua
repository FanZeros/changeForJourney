---@meta
--- ============================================================
--- ProxyTransport.lua — 单机直接 HTTP transport
--- 不再经过 RemoteEvent / 服务端代理。
--- ============================================================

local cjson = require("cjson")

local ProxyTransport = {}

local nextId_ = 1
local pending_ = {}
local started_ = false

local METHOD_MAP = {
    GET = HTTP_GET,
    POST = HTTP_POST,
    PUT = HTTP_PUT,
    DELETE = HTTP_DELETE,
    PATCH = HTTP_PATCH,
}

local function nowMs()
    return math.floor(os.time() * 1000)
end

local function nextRequestId()
    local id = "ga_lua_" .. tostring(os.time()) .. "_" .. tostring(nextId_)
    nextId_ = nextId_ + 1
    return id
end

local function finish(id, err, response)
    local item = pending_[id]
    if not item or item.done then return end
    item.done = true
    pending_[id] = nil
    item.callback(err, response)
end

---@param cfg? table
function ProxyTransport.Start(cfg)
    if started_ then return end
    started_ = true
    if cfg and cfg.eventPrefix then
        print("[GameAlgoSDK] standalone ignores eventPrefix=" .. tostring(cfg.eventPrefix))
    end
end

---@param request table
---@param callback fun(error:string|nil,response:table|nil)
function ProxyTransport.Request(request, callback)
    if not started_ then ProxyTransport.Start() end
    callback = callback or function() end

    local id = request.id or nextRequestId()
    local timeoutMs = request.timeoutMs or 10000
    local methodName = string.upper(tostring(request.method or "GET"))
    local httpMethod = METHOD_MAP[methodName] or HTTP_GET
    local headers = request.headers or {}
    local body = request.body or ""

    pending_[id] = {
        callback = callback,
        expiresAt = nowMs() + timeoutMs,
        done = false,
    }

    if not http then
        finish(id, "单机运行时 HTTP 不可用", {
            id = id,
            status = 0,
            success = false,
            body = "",
            error = "http unavailable",
        })
        return id
    end

    local client = http:Create()
        :SetUrl(tostring(request.url or ""))
        :SetMethod(httpMethod)
        :SetTimeout(timeoutMs)

    for key, value in pairs(headers) do
        client:AddHeader(tostring(key), tostring(value))
    end
    if headers["Content-Type"] then
        client:SetContentType(tostring(headers["Content-Type"]))
    end
    if body ~= "" and (httpMethod == HTTP_POST or httpMethod == HTTP_PUT or httpMethod == HTTP_PATCH) then
        client:SetBody(body)
    end

    client
        :OnSuccess(function(_, response)
            local payload = {
                id = id,
                status = response and response.statusCode or 0,
                success = response and response.success == true,
                body = response and response.dataAsString or "",
            }
            if payload.success then
                finish(id, nil, payload)
            else
                finish(id, "HTTP " .. tostring(payload.status), payload)
            end
        end)
        :OnError(function(_, statusCode, error)
            finish(id, error or ("HTTP " .. tostring(statusCode or 0)), {
                id = id,
                status = statusCode or 0,
                success = false,
                body = "",
                error = error,
            })
        end)
        :Send()

    return id
end

function ProxyTransport.Update()
    local now = nowMs()
    local expired = {}
    for id, item in pairs(pending_) do
        if item.expiresAt <= now then
            expired[#expired + 1] = id
        end
    end
    for i = 1, #expired do
        finish(expired[i], "proxy timeout", nil)
    end
end

function ProxyTransport.PendingCount()
    local count = 0
    for _, _ in pairs(pending_) do count = count + 1 end
    return count
end

function ProxyTransport.OutboxCount()
    return 0
end

return ProxyTransport
