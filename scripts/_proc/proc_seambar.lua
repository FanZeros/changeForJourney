-- ============================================================================
-- proc_seambar.lua — 黑底返回条 → 边界泛洪抠图 → 裁剪 → 压到运行时比例 → 覆盖
-- 用法: UrhoXRuntime _proc/proc_seambar.lua -tapcode_dir=<项目根> -tool_mode
-- 抠图规则（防内部空洞）：只有"与画布边缘连通的暗色区域"才算背景抠透明；
-- 条身内部再暗的像素也保留不透明。金边（亮度高）会挡住泛洪。
-- ============================================================================

local SRC = "/workspace/assets/image/SEAMBAR黑底B2_20260921074601.png"
local DST = "/workspace/assets/image/界面底板/通用面板/UI_SEAMBAR.png"

local ASPECT  = 0.0888   -- 运行时条宽/条高（drawBackSeamBar: w = h*0.0888）
local T_JOIN  = 0.35     -- 泛洪可穿越的最大亮度（低于它才蔓延）
local EDGE_LO = 0.02     -- 背景邻接内容的软边亮度下限
local EDGE_HI = 0.10     -- 软边亮度上限（超过即不透明）

function Start()
    local ok, err = pcall(function()
        local img = Image()
        assert(img:Load(SRC), "load fail " .. SRC)
        local w, h = img:GetWidth(), img:GetHeight()
        local n = w * h

        -- 1) 预计算亮度表
        local lum = {}
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local c = img:GetPixel(x, y)
                lum[y * w + x + 1] = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
            end
        end

        -- 2) 从画布四边泛洪：连通暗区 = 背景
        local isBg = {}
        local queue = {}
        local head, tail = 1, 0
        local function push(i)
            if not isBg[i] and lum[i] < T_JOIN then
                isBg[i] = true
                tail = tail + 1
                queue[tail] = i
            end
        end
        for x = 0, w - 1 do
            push(x + 1)             -- 顶行
            push((h - 1) * w + x + 1) -- 底行
        end
        for y = 0, h - 1 do
            push(y * w + 1)         -- 左列
            push(y * w + w)         -- 右列
        end
        while head <= tail do
            local i = queue[head]
            head = head + 1
            local x = (i - 1) % w
            local y = math.floor((i - 1) / w)
            if x > 0     then push(i - 1) end
            if x < w - 1 then push(i + 1) end
            if y > 0     then push(i - w) end
            if y < h - 1 then push(i + w) end
        end

        -- 3) 写 alpha：背景→0（邻接内容处留软边），内容→1
        local minX, minY, maxX, maxY = w, h, -1, -1
        local bgCount = 0
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local i = y * w + x + 1
                local c = img:GetPixel(x, y)
                local a
                if isBg[i] then
                    bgCount = bgCount + 1
                    -- 软边：背景中紧邻内容的像素按亮度留半透明
                    local near = false
                    if x > 0 and not isBg[i - 1] then near = true end
                    if not near and x < w - 1 and not isBg[i + 1] then near = true end
                    if not near and y > 0 and not isBg[i - w] then near = true end
                    if not near and y < h - 1 and not isBg[i + w] then near = true end
                    a = near and math.min(1, math.max(0, (lum[i] - EDGE_LO) / (EDGE_HI - EDGE_LO))) or 0
                else
                    a = 1
                end
                img:SetPixel(x, y, Color(c.r, c.g, c.b, a))
                if a > 0.5 then
                    if x < minX then minX = x end
                    if x > maxX then maxX = x end
                    if y < minY then minY = y end
                    if y > maxY then maxY = y end
                end
            end
        end
        assert(maxX >= 0, "no content")
        print(string.format("[seambar] content(%d,%d)-(%d,%d) bg=%d/%d (%.1f%%)",
            minX, minY, maxX, maxY, bgCount, n, bgCount * 100 / n))

        -- 4) 裁内容框 → 非等比拉伸到运行时比例 → 右贴边画布
        local cw, ch = maxX - minX + 1, maxY - minY + 1
        local cropped = Image()
        cropped:SetSize(cw, ch, 4)
        for y = 0, ch - 1 do
            for x = 0, cw - 1 do
                cropped:SetPixel(x, y, img:GetPixel(minX + x, minY + y))
            end
        end
        local outW = math.floor(h * ASPECT + 0.5)
        cropped:Resize(outW, h)
        assert(cropped:SavePNG(DST), "save fail " .. DST)
        print(string.format("[seambar] saved %s (%dx%d, aspect %.4f)", DST, outW, h, outW / h))
    end)
    if not ok then
        log:Write(LOG_ERROR, "[seambar] " .. tostring(err))
        print("[seambar] ERROR: " .. tostring(err))
    end
    engine:Exit()
end
