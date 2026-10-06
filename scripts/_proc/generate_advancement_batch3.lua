-- 第三批回响客＋换面人。基于既有Start/pcall/Exit烘焙脚手架，独立于第一批共用入口。
-- 默认替换4、5、213–220共十图；-review-only只生成。107–110仅代码复用，不安装。
-- UrhoXRuntime _proc/generate_advancement_batch3.lua -tapcode_dir=/workspace -tool_mode -graphicsheadless
local ROOT = "/workspace/assets/image/职业图标/"
local OUT = "/workspace/.git/advancement-batch3-validation/generated/"
local BACKUP = "/workspace/.git/advancement-batch3-validation/originals/"
local ORDER = {4,5,213,214,215,216,217,218,219,220}
---@type Image[]
local images = {}

function Start()
    local ok, err = pcall(function()
        local reviewOnly = false
        for _,arg in ipairs(GetArguments()) do
            if arg == "-review-only" then reviewOnly = true
            elseif arg == "-install" then
                -- 已有安装授权；保留显式参数兼容，但它不能扩大白名单。
            elseif arg == "-first-review" or arg == "-seal-review" or arg == "-batch1" or arg == "-batch2" then
                error("第三批独立入口不能选择其他批次")
            end
        end
        local raster = require("_proc.advancement.Batch3Raster")
        local echo = require("_proc.advancement.BatchEcho")
        local mask = require("_proc.advancement.BatchMask")
        assert(fileSystem:CreateDir(OUT),"创建第三批生成目录失败")
        -- 全批烘焙成功后才允许覆盖正式图；母图/调试图只保留于.git内部。
        for _,id in ipairs(ORDER) do
            print("[adv-batch3] " .. id .. " 开始程序绘制")
            local drawer = (id == 4 or (id >= 213 and id <= 216)) and echo or mask
            local master = raster.render(drawer,id,images)
            local small = raster.reduce(master,images)
            assert(master:SavePNG(OUT .. "UI_icon_ZY_" .. id .. "_560.png"),"保存第三批母图失败")
            assert(small:SavePNG(OUT .. "UI_icon_ZY_" .. id .. ".png"),"保存第三批成图失败")
            -- 当前图已落盘立即释放，十图也不累积原生图像内存。
            for _,image in ipairs(images) do image:Dispose() end
            images = {}
            print("[adv-batch3] " .. id .. " 280×280 RGBA已保存")
        end
        if not reviewOnly then
            assert(fileSystem:CreateDir(BACKUP),"创建第三批备份失败")
            local rollback = BACKUP .. "current/"
            assert(fileSystem:CreateDir(rollback),"创建本次第三批恢复目录失败")
            for _,id in ipairs(ORDER) do
                local name = "UI_icon_ZY_" .. id .. ".png"
                assert(fileSystem:FileExists(ROOT .. name),"缺少正式原图：" .. name)
                assert(fileSystem:FileExists(ROOT .. name .. ".meta"),"缺少原meta：" .. name)
                if not fileSystem:FileExists(BACKUP .. name) then
                    assert(fileSystem:Copy(ROOT .. name,BACKUP .. name),"备份第三批旧图失败")
                end
                assert(fileSystem:Copy(ROOT .. name,rollback .. name),"备份本次第三批安装前图片失败")
            end
            local installed = {}
            local copied, copyError = pcall(function()
                for _,id in ipairs(ORDER) do
                    local name = "UI_icon_ZY_" .. id .. ".png"
                    installed[#installed+1] = name
                    assert(fileSystem:Copy(OUT .. name,ROOT .. name),"安装第三批图片失败：" .. name)
                    print("[adv-batch3] 已安装 " .. name .. "，原.meta保持不变")
                end
            end)
            if not copied then
                local restored = true
                for _,name in ipairs(installed) do
                    local restoreOK, result = pcall(function() return fileSystem:Copy(rollback .. name,ROOT .. name) end)
                    if not restoreOK or not result then restored = false end
                end
                error(tostring(copyError) .. (restored and "；已恢复第三批原图" or "；恢复失败需核对备份"))
            end
        end
        print("[adv-batch3] ALL PASS：10枚回响客＋换面人，模式=" .. (reviewOnly and "仅生成" or "安装"))
    end)
    for _,image in ipairs(images) do image:Dispose() end
    images = {}
    if not ok then log:Write(LOG_ERROR,"[adv-batch3] " .. tostring(err)) end
    engine:Exit()
end
