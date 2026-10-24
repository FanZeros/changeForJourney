-- 剧情专项辅助：仅显式调用时校验或安装夹具，不自动运行，不访问I/O，无Start入口。
local M = {}

-- 纯源树入口；读取者只接收18个固定相对路径，宿主须令success=false非零退出。
function M.validateSourceMetadata(readMetadata, decode)
    assert(type(readMetadata) == "function" and type(decode) == "function", "metadata reader/JSON decoder required")
    local report = { total = 18, checked = 0, missing = 0, invalid = 0, duplicates = 0,
        title = { checked = false, success = false }, failures = {}, success = false }
    local uuids = {}
    for index = 1, report.total do
        local imagePath = index <= 17 and string.format("image/剧情/背景/STORY_BG_%02d.png", index)
            or "image/界面底板/标题与加载/UI_TITLE_BG_GATE.png"
        local path = "assets/" .. imagePath .. ".meta"
        local readOk, text = pcall(readMetadata, path)
        if not readOk or type(text) ~= "string" or text == "" then
            report.missing = report.missing + 1
            report.failures[#report.failures + 1] = "missing source metadata " .. path
        else
            report.checked = report.checked + 1
            local decoded, meta = pcall(decode, text)
            if not decoded or type(meta) ~= "table" or type(meta.uuid) ~= "string" or meta.uuid == "" then
                report.invalid = report.invalid + 1
                report.failures[#report.failures + 1] = "invalid source metadata UUID " .. path
            else
                if uuids[meta.uuid] then
                    report.duplicates = report.duplicates + 1
                    report.failures[#report.failures + 1] = "duplicate source metadata UUID " .. path .. " / " .. uuids[meta.uuid]
                end
                uuids[meta.uuid] = path
                if index == 18 then
                    report.title.checked = true
                    report.title.success = meta.uuid == "BQ8tKQY6Tzcboc1rDEFdRu5F"
                    if not report.title.success then
                        report.failures[#report.failures + 1] = "title original metadata UUID changed " .. path
                    end
                end
            end
        end
    end
    report.success = #report.failures == 0 and report.checked == report.total and report.title.success
    return report
end

---@param ctx any 独立夹具计数，不共享宿主_G
---@param env any 待安装的独立运行环境
---@param eq fun(actual:any, expected:any, message:string) 主测试计数断言
function M.installIoBoundary(ctx, env, eq)
    local function blockedFile()
        if ctx.boundaryProbe then ctx.expectedFileBlocks = ctx.expectedFileBlocks + 1
        else ctx.fileAttempts = ctx.fileAttempts + 1 end
        error("isolated test forbids player File/FileSystem IO", 0)
    end
    local function blockedCloud()
        if ctx.boundaryProbe then ctx.expectedCloudBlocks = ctx.expectedCloudBlocks + 1
        else ctx.cloudAttempts = ctx.cloudAttempts + 1 end
        error("isolated test forbids cloud/network dispatch", 0)
    end
    env._G = env
    env.File, env.FileSystem, env.GetFileSystem = blockedFile, blockedFile, blockedFile
    env.loadfile, env.dofile = blockedFile, blockedFile
    env.fileSystem = setmetatable({}, { __index = function() return blockedFile end })
    env.clientCloud = setmetatable({}, { __index = function() return blockedCloud end })
    env.serverCloud, env.network = env.clientCloud, env.clientCloud
    env.cache = { GetResource = function() error("no audio/GPU resources in semantic test") end,
        GetFile = blockedFile }
    -- 只在夹具初始化中做预期反例；生产稍后即使pcall吞异常也累计unexpected计数。
    ctx.boundaryProbe = true
    local fileProbes = {
        function() env.File("forbidden-probe") end,
        function() env._G.File("forbidden-probe") end,
        function() env.FileSystem() end, function() env._G.FileSystem() end,
        function() env.GetFileSystem() end, function() env._G.GetFileSystem() end,
        function() env.fileSystem:FileExists("forbidden-probe") end,
        function() env._G.fileSystem:FileExists("forbidden-probe") end,
        function() env.loadfile("forbidden-probe") end, function() env._G.loadfile("forbidden-probe") end,
        function() env.dofile("forbidden-probe") end, function() env._G.dofile("forbidden-probe") end,
        function() env.cache:GetFile("forbidden-probe") end,
    }
    for index, probe in ipairs(fileProbes) do
        local before = ctx.expectedFileBlocks
        eq(pcall(probe), false, "File/FS隔离反例拒绝 " .. index)
        eq(ctx.expectedFileBlocks, before + 1, "File/FS隔离反例恰好计数 " .. index)
    end
    for index, target in ipairs({ env.clientCloud, env.serverCloud, env.network,
        env._G.clientCloud, env._G.serverCloud, env._G.network }) do
        local before = ctx.expectedCloudBlocks
        eq(pcall(function() target:SendEvent("forbidden-probe") end), false, "网络隔离反例拒绝 " .. index)
        eq(ctx.expectedCloudBlocks, before + 1, "网络隔离反例恰好计数 " .. index)
    end
    ctx.boundaryProbe = false
    eq(env._G, env, "独立_G不能回退宿主")
end

return M
