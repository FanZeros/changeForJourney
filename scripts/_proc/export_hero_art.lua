-- 离线导出:把 KTX 私有格式的角色图标/卡牌/立绘解码为真 PNG
local HC = require("config.HeroConfig")
local function portraitPath(id)
    local cfg = HC.get and HC.get(id) or nil
    if cfg and cfg.name then
        return "image/角色立绘/" .. cfg.name .. "_透明立绘.png"
    end
    return string.format("image/角色立绘/UI_DLH_%d.png", id)
end
function Start()
    local ok, err = pcall(function()
        local outDir = "/workspace/.tmp/roster_export"
        local ids = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,20,21,22,23}
        local hasPortrait = {}
        for _, hid in ipairs(ids) do hasPortrait[hid] = true end

        local function exportOne(kind, srcPath, dstPath)
            local tex = cache:GetResource("Texture2D", srcPath)
            if not tex then
                print("[export] MISS tex " .. kind .. " " .. srcPath)
                return
            end
            local img = tex:GetImage()
            if not img then
                print("[export] MISS img " .. kind .. " " .. srcPath)
                return
            end
            if img:SavePNG(dstPath) then
                print(string.format("[export] OK %s %dx%d -> %s",
                    kind, img:GetWidth(), img:GetHeight(), dstPath))
            else
                print("[export] SAVE-FAIL " .. kind .. " " .. dstPath)
            end
        end

        for _, id in ipairs(ids) do
            exportOne("icon",
                string.format("image/角色图标/UI_icon_hero_%d.png", id),
                outDir .. "/icons/" .. id .. ".png")
            exportOne("card",
                string.format("image/角色卡牌/KP_YX_%d.png", id),
                outDir .. "/cards/" .. id .. ".png")
            if hasPortrait[id] then
                exportOne("portrait",
                    portraitPath(id),
                    outDir .. "/portraits/" .. id .. ".png")
            end
        end
        print("[export] ALL DONE")
    end)
    if not ok then
        log:Write(LOG_ERROR, "[export] " .. tostring(err))
    end
    engine:Exit()
end
