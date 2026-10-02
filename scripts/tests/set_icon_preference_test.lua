-- 套装图标开关与共享徽记回归：显示偏好持久化，不影响筛选与套装正文图标。
function Start()
    local originalRequire, originalFile, originalFs, originalAudio = require, File, fileSystem, audio
    local native = {}
    local noop = function() end
    local saved = nil
    local changes = 0
    local iconDraws, loaded = {}, {}
    local mods = {
        ["core.I18n"] = { get = function() return "zh_CN" end, set = noop, lookup = function(s) return s end },
        ["systems.GameBGM"] = { setMasterGain = noop },
        ["ui.hud.popup.RedeemCodePanel"] = { init = noop },
        ["systems.GameSFX"] = { playUIMove = noop },
        ["systems.ButtonFeedback"] = { begin = function() return false end, finish = noop, trigger = noop },
        ["core.DrawUtil"] = {
            hitTest = function(x, y, cx, cy, w, h)
                return x >= cx-w/2 and x <= cx+w/2 and y >= cy-h/2 and y <= cy+h/2
            end,
            drawImageCentered = function(_, image, cx, cy, w, h)
                iconDraws[#iconDraws + 1] = { image = image, cx = cx, cy = cy, w = w, h = h }
            end,
            drawTextStroke = noop,
        },
        ["core.DarkIcon"] = { drawNine = noop },
    }
    require = function(name) return mods[name] or originalRequire(name) end
    File = function(_, mode)
        return { IsOpen = function() return true end, Close = noop,
            WriteString = function(_, value) saved = value; return true end,
            ReadString = function() return saved end }
    end
    fileSystem = { FileExists = function() return saved ~= nil end }
    audio = { SetMasterGain = noop }
    local count = 0
    local function check(value, message) assert(value, message); count = count + 1 end
    local ok, err = pcall(function()
        local Settings = originalRequire("ui.hud.popup.SettingsPanel")
        mods["ui.hud.popup.SettingsPanel"] = Settings
        local Icon = originalRequire("ui.widget.EquipmentSetIcon")
        mods["ui.widget.EquipmentSetIcon"] = Icon
        local Link = originalRequire("ui.backpack.BackpackEquipLink")
        local state = { open = true, tab = "equip", scrollY = 125, scrollVel = 0 }
        local grid = { FIRST_ROW_TOP = 470 }
        local api = Link.bind({ state = state, GRID = grid,
            getHostMode = function() return "left" end, getEquipList = function() return {} end,
            getLeftPage = function() return nil end, EquipmentDetail = { getOwner = function() return nil end,
                dismissHover = noop }, DrawUtil = mods["core.DrawUtil"],
        })
        check(Settings.isSetIconsEnabled(), "旧档默认显示套装角标")
        api.setEquipmentSlotFilter("armor", 1)
        state.scrollY = 125
        check(api.handleFilterInput(605, 416), "勾选条命中并消费")
        check(not Settings.isSetIconsEnabled(), "勾选关闭立即生效")
        check(api.getEquipmentSlotFilter() == "armor" and state.scrollY == 125,
            "显示开关不改变部位筛选或列表滚动")
        check(cjson.decode(saved).showSetIcons == false, "关闭偏好写入已有设置文件")
        grid.FIRST_ROW_TOP = 740
        check(api.handleFilterInput(605, 686) and Settings.isSetIconsEnabled(), "布局切换后勾选热区跟随活坐标")
        check(cjson.decode(saved).showSetIcons == true, "开启偏好可保存")
        Settings.setSetIconsEnabled(false)
        local falseSave = saved
        Settings.setSetIconsEnabled(true)
        saved = falseSave
        Settings.init({})
        check(not Settings.isSetIconsEnabled(), "重新加载设置恢复关闭状态")
        local Sets = originalRequire("config.EquipmentSetConfig")
        local EC = originalRequire("config.EquipmentConfig")
        local template
        for id, def in pairs(EC.ITEMS) do
            if Sets.getSetIdForTemplate(def) then template = id; break end
        end
        check(template ~= nil, "存在真实套装模板")
        check(not Icon.hasBadge({ templateId = template }), "关闭时装备角标隐藏")
        check(not Icon.hasBadge(nil) and not Icon.hasBadge({ templateId = "missing" }), "空装备与无套装不画角标")
        native.createImage = nvgCreateImage
        nvgCreateImage = function(_, path) loaded[#loaded + 1] = path; return #loaded end
        check(Icon.draw({}, "carapace", 100, 100, 46, 1), "套装正文图标不受角标关闭影响")
        Icon.draw({}, "carapace", 100, 100, 46, 1)
        check(#loaded == 1 and loaded[1] == "image/套装图标/v3/SET_carapace.png", "采用V3且不逐帧加载重复图片")
        check(not Icon.draw({}, "missing", 100, 100, 46, 1), "未知套装安全跳过")
        Settings.setSetIconsEnabled(true)
        check(Icon.hasBadge({ templateId = template }), "开启时真实套装角标可见")
        local badge = Icon.badgeLayout(80, 80, 160)
        local equip = { templateId = template, level = 9999 }
        local level = Icon.levelLayout(equip, 80, 80, 160)
        check(badge.size == 44 and badge.x == 4 and badge.y == 112, "160格套装角标占左下44像素")
        check(level.x == 152 and level.y == 154 and level.fontSize == 40
            and level.align == NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM, "显示角标时等级固定右下40号")
        Settings.setSetIconsEnabled(false)
        local offLevel = Icon.levelLayout(equip, 80, 80, 160)
        check(not Icon.hasBadge(equip) and offLevel.x == level.x and offLevel.y == level.y
            and offLevel.fontSize == level.fontSize and offLevel.align == level.align,
            "关闭偏好同装备Lv.9999布局完全不变")
        local plainLevel = Icon.levelLayout({ templateId = "missing", level = 9999 }, 80, 80, 160)
        check(plainLevel.x == level.x and plainLevel.y == level.y
            and plainLevel.fontSize == level.fontSize and plainLevel.align == level.align,
            "无套装不改变等级位置/字号/对齐")
        local drawCount = #iconDraws
        check(not Icon.drawBadge({}, equip, 80, 80, 160) and #iconDraws == drawCount,
            "关闭偏好drawBadge安全跳过")
        Settings.setSetIconsEnabled(true)
        check(Icon.drawBadge({}, equip, 80, 80, 160), "开启偏好drawBadge可绘制真实装备")
        local actual = iconDraws[#iconDraws]
        check(actual.cx == badge.cx and actual.cy == badge.cy and actual.w == 44,
            "drawBadge实际使用左下布局")
        local Filter = originalRequire("ui.widget.SetFilterDialog")
        Filter.open({}, { onChange = function() changes = changes + 1 end })
        Filter.handleInput(540, 610)
        check(changes == 1 and Filter.countSelected() == 1, "套装选择逻辑不被徽记接入改动")
        Filter.close()
    end)
    require, File, fileSystem, audio = originalRequire, originalFile, originalFs, originalAudio
    if native.createImage then nvgCreateImage = native.createImage end
    if ok then print("[set_icon_preference_test] ALL PASS: " .. count .. " assertions")
    else print("[set_icon_preference_test] FAIL: " .. tostring(err)) end
    engine:Exit()
end
