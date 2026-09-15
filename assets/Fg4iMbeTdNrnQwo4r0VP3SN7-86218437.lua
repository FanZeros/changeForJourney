---@meta
--- ============================================================
--- ProxyServer.lua — 通用 HTTP 代理转发服务端
--- ============================================================

local cjson = require("cjson")

local ProxyServer = {}

local EVENT_REQUEST  = "HttpProxy_Request"
local EVENT_RESPONSE = "HttpProxy_Response"

local config_ = {
    allowedHosts        = {},
    allowedPathPrefixes = nil,
    defaultHeaders      = {},
    timeout             = 10000,
    maxBodySize         = 65536,
    eventPrefix         = "HttpProxy",
    allowHttp           = false,
}

local HOP_BY_HOP_HEADERS = {
    ["connection"] = true,
    ["host"] = true,
    ["content-length"] = true,
    ["transfer-encoding"] = true,
}

local function parseUrl(url)
    local scheme, rest = tostring(url or ""):match("^(https?)://(.+)$")
    if not scheme or not rest then return "", "", "" end
    local host = rest:match("^([^/:?#]+)") or ""
    local path = rest:match("^[^/?#]*(/[^?#]*)") or "/"
    return scheme, host, path
end

local function isHostAllowed(host)
    for _, h in ipairs(config_.allowedHosts) do
        if h == host then return true end
    end
    return false
end

local function isPathAllowed(path)
    if not config_.allowedPathPrefixes or #config_.allowedPathPrefixes == 0 then
        return true
    end
    for _, prefix in ipairs(config_.allowedPathPrefixes) do
        if path:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function normalizedHeaderName(name)
    return tostring(name or ""):lower()
end

local function isProtectedHeader(name)
    local key = normalizedHeaderName(name)
    if HOP_BY_HOP_HEADERS[key] then return true end
    for defaultName, _ in pairs(config_.defaultHeaders) do
        if normalizedHeaderName(defaultName) == key then return true end
    end
    return false
end

local METHOD_MAP = {
    GET    = HTTP_GET,
    POST   = HTTP_POST,
    PUT    = HTTP_PUT,
    DELETE = HTTP_DELETE,
    PATCH  = HTTP_PATCH,
}

function ProxyServer.HandleRequest(eventType, eventData)
    local connectionValue = eventData and eventData["Connection"]
    local connection = connectionValue and connectionValue:GetPtr("Connection")
    if not connection then
        print("[ProxyServer] ERROR: no connection in event")
        return
    end

    local payloadValue = eventData["Payload"]
    local payload = payloadValue and payloadValue:GetString()
    if not payload or #payload == 0 then
        ProxyServer.SendError(connection, "empty_request", "Empty payload", "")
        return
    end

    local ok, req = pcall(cjson.decode, payload)
    if not ok or type(req) ~= "table" then
        ProxyServer.SendError(connection, "parse_error", "Invalid JSON", "")
        return
    end

    local requestId = req.id or ""
    local url       = req.url or ""
    local method    = tostring(req.method or "GET")
    local headers   = type(req.headers) == "table" and req.headers or {}
    local body      = tostring(req.body or "")

    local scheme, host, path = parseUrl(url)
    if scheme == "" then
        ProxyServer.SendError(connection, requestId, "Invalid URL", url)
        return
    end
    if scheme ~= "https" and not config_.allowHttp then
        ProxyServer.SendError(connection, requestId, "Only HTTPS is allowed", url)
        return
    end
    if not isHostAllowed(host) then
        print("[ProxyServer] BLOCKED host: " .. host .. " url: " .. url)
        ProxyServer.SendError(connection, requestId, "Host not allowed: " .. host, url)
        return
    end
    if not isPathAllowed(path) then
        print("[ProxyServer] BLOCKED path: " .. path .. " url: " .. url)
        ProxyServer.SendError(connection, requestId, "Path not allowed: " .. path, url)
        return
    end

    if #body > config_.maxBodySize then
        ProxyServer.SendError(connection, requestId, "Body too large", url)
        return
    end

    local httpMethod = METHOD_MAP[method:upper()] or HTTP_GET
    local client = http:Create()
        :SetUrl(url)
        :SetMethod(httpMethod)
        :SetTimeout(config_.timeout)

    for k, v in pairs(headers) do
        if not isProtectedHeader(k) then
            client:AddHeader(tostring(k), tostring(v))
        end
    end

    for k, v in pairs(config_.defaultHeaders) do
        client:AddHeader(tostring(k), tostring(v))
    end

    if body ~= "" and (httpMethod == HTTP_POST or httpMethod == HTTP_PUT or httpMethod == HTTP_PATCH) then
        client:SetContentType(headers["Content-Type"] or "application/json")
        client:SetBody(body)
    end

    client
        :OnSuccess(function(_, response)
            local respData = VariantMap()
            respData["Payload"] = Variant(cjson.encode({
                id         = requestId,
                status     = response.statusCode,
                success    = response.success,
                body       = response.dataAsString,
            }))
            connection:SendRemoteEvent(EVENT_RESPONSE, true, respData)
        end)
        :OnError(function(_, statusCode, error)
            local respData = VariantMap()
            respData["Payload"] = Variant(cjson.encode({
                id         = requestId,
                status     = statusCode,
                success    = false,
                body       = "",
                error      = error,
            }))
            connection:SendRemoteEvent(EVENT_RESPONSE, true, respData)
        end)
        :Send()
end

function ProxyServer.SendError(connection, requestId, errorMsg, url)
    local respData = VariantMap()
    respData["Payload"] = Variant(cjson.encode({
        id      = requestId,
        status  = 0,
        success = false,
        body    = "",
        error   = errorMsg,
    }))
    connection:SendRemoteEvent(EVENT_RESPONSE, true, respData)
end

---@param cfg table
function ProxyServer.Start(cfg)
    assert(cfg and cfg.allowedHosts and #cfg.allowedHosts > 0,
        "[ProxyServer] allowedHosts is required and must not be empty")

    config_.allowedHosts        = cfg.allowedHosts
    config_.allowedPathPrefixes = cfg.allowedPathPrefixes
    config_.defaultHeaders      = cfg.defaultHeaders or {}
    config_.timeout             = cfg.timeout or 10000
    config_.maxBodySize         = cfg.maxBodySize or 65536
    config_.allowHttp           = cfg.allowHttp == true

    if cfg.eventPrefix then
        EVENT_REQUEST  = cfg.eventPrefix .. "_Request"
        EVENT_RESPONSE = cfg.eventPrefix .. "_Response"
    end

    network:RegisterRemoteEvent(EVENT_REQUEST)
    network:RegisterRemoteEvent(EVENT_RESPONSE)
    SubscribeToEvent(EVENT_REQUEST, "HandleProxyRequest")

    print("[ProxyServer] Started. Allowed hosts: " .. table.concat(config_.allowedHosts, ", "))
end

return ProxyServer
