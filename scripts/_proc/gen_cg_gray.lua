-- ============================================================================
-- gen_cg_gray.lua — 离线生成角色 CG 灰度版（觉醒页"影画"切片未解锁态用）
-- 用法: UrhoXRuntime _proc/gen_cg_gray.lua -tapcode_dir=<项目根> -tool_mode
-- 规则:
--   彩色 CG = image/角色CG/CG_H<id>.png（正式 CG，另行绘制；缺省回退立绘/卡牌）
--   灰度    = CG 源   -> image/角色CG/CG_H<id>_gray.png
--             回退源  -> image/角色CG/FALLBACK_H<id>_gray.png
-- 正式 CG 画好后放进 角色CG/ 再重跑本脚本即可刷新灰度版。
-- ============================================================================

local HERO_IDS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 21, 22, 23 }

local OUT_DIR = "/workspace/assets/image/角色CG"

--- 依次尝试 CG / 立绘 / 卡牌，返回 (resource, kind)
local function resolveSource(id)
    local tries = {
        { string.format("image/角色CG/CG_H%d.png", id),        "CG" },
        { string.format("image/角色立绘/UI_DLH_%d.png", id),   "FALLBACK" },
        { string.format("image/角色卡牌/KP_YX_%d.png", id),    "FALLBACK" },
    }
    for _, t in ipairs(tries) do
        local res = cache:GetResource("Image", t[1])
        if res and res:GetWidth() > 0 then
            return res, t[2], t[1]
        end
    end
    return nil, nil, nil
end

function Start()
    local ok, err = pcall(function()
        os.execute("mkdir -p '" .. OUT_DIR .. "'")
        local made, skipped = 0, 0
        for _, id in ipairs(HERO_IDS) do
            local img, kind, srcPath = resolveSource(id)
            if not img then
                print(string.format("[gen_cg_gray] SKIP %d (no source png)", id))
                skipped = skipped + 1
            else
                local w, h = img:GetWidth(), img:GetHeight()
                local hasAlpha = img:GetComponents() >= 4
                for y = 0, h - 1 do
                    for x = 0, w - 1 do
                        local c = img:GetPixel(x, y)
                        local lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
                        if lum > 1.0 then lum = 1.0 end
                        img:SetPixel(x, y, Color(lum, lum, lum, c.a))
                    end
                end
                local outPath
                if kind == "CG" then
                    outPath = OUT_DIR .. string.format("/CG_H%d_gray.png", id)
                else
                    outPath = OUT_DIR .. string.format("/FALLBACK_H%d_gray.png", id)
                end
                assert(img:SavePNG(outPath), "SavePNG failed: " .. outPath)
                print(string.format("[gen_cg_gray] %d %s %s (%dx%d) -> %s",
                    id, kind, srcPath, w, h, outPath))
                made = made + 1
            end
        end
        print(string.format("[gen_cg_gray] ALL DONE made=%d skipped=%d", made, skipped))
    end)
    if not ok then
        log:Write(LOG_ERROR, "[gen_cg_gray] " .. tostring(err))
        print("[gen_cg_gray] ERROR: " .. tostring(err))
    end
    engine:Exit()
end
