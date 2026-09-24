---@meta
--- ============================================================
--- ProxyTransport.lua — 单机空传输
--- 不发 HTTP，不读云。
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
    print("[GameAlgoSDK] local skip url=" .. tostring(request.url))
    callback("单机不访问云", {
        id = id,
        status = 0,
        success = false,
        body = "",
        error = "local only",
    })
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
