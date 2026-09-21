-- ============================================================================
-- proc_seambar.lua — 黑底返回条 → 亮度抠图 → 裁剪 → 压到运行时比例 → 覆盖 UI_SEAMBAR
-- 用法: UrhoXRuntime _proc/proc_seambar.lua -tapcode_dir=<项目根> -tool_mode
-- 运行时 drawBackSeamBar 以 w = h*0.0888 满高拉伸，故成品宽高比必须 = 0.0888。
-- ============================================================================

local SRC = "/workspace/assets/image/SEAMBAR黑底B括号脊点_20260921060411.png"
local DST = "/workspace/assets/image/界面底板/通用面板/UI_SEAMBAR.png"

local ASPECT   = 0.0888   -- 运行时条宽/条高
local LO, RNG  = 0.04, 0.06  -- 亮度抠图(0~1量纲): alpha = clamp((lum-LO)/RNG)，黑底→透明，暗铁填充(≈0.13)→不透明

function Start()
    local ok, err = pcall(function()
        local img = Image()
        assert(img:Load(SRC), "load fail " .. SRC)
        local w, h = img:GetWidth(), img:GetHeight()

        -- 1) 亮度抠图（黑底→透明，含软边），同时求内容 bbox
        local minX, minY, maxX, maxY = w, h, -1, -1
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local c = img:GetPixel(x, y)
                local lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
                local a = (lum - LO) / RNG
                if a < 0 then a = 0 end
                if a > 1 then a = 1 end
                img:SetPixel(x, y, Color(c.r, c.g, c.b, a))
                if a > 0.02 then
                    if x < minX then minX = x end
                    if x > maxX then maxX = x end
                    if y < minY then minY = y end
                    if y > maxY then maxY = y end
                end
            end
        end
        assert(maxX >= 0, "no content")
        print(string.format("[seambar] content (%d,%d)-(%d,%d) src %dx%d",
            minX, minY, maxX, maxY, w, h))

        -- 2) 裁到内容框
        local cw, ch = maxX - minX + 1, maxY - minY + 1
        local cropped = Image()
        cropped:SetSize(cw, ch, 4)
        for y = 0, ch - 1 do
            for x = 0, cw - 1 do
                cropped:SetPixel(x, y, img:GetPixel(minX + x, minY + y))
            end
        end

        -- 3) 非等比拉伸到运行时比例（高不变，宽 = h*ASPECT）
        local outW = math.floor(h * ASPECT + 0.5)
        cropped:Resize(outW, h)

        -- 4) 右对齐贴边（内容右缘 = 直边 = 画布右边界）
        local canvas = Image()
        canvas:SetSize(outW, h, 4)
        canvas:Clear(Color(0, 0, 0, 0))
        for y = 0, h - 1 do
            for x = 0, outW - 1 do
                canvas:SetPixel(x, y, cropped:GetPixel(x, y))
            end
        end

        assert(canvas:SavePNG(DST), "save fail " .. DST)
        print(string.format("[seambar] saved %s (%dx%d, aspect %.4f)", DST, outW, h, outW / h))
    end)
    if not ok then
        log:Write(LOG_ERROR, "[seambar] " .. tostring(err))
        print("[seambar] ERROR: " .. tostring(err))
    end
    engine:Exit()
end
