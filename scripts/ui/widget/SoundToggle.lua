-- ============================================================================
-- SoundToggle - 战斗 HUD 音效快捷开关按钮
-- 样式与选关/统计/扫荡同套（金框整图 + 下方文字标签）
-- 状态源: SettingsPanel.isSoundOn/setSoundOn（与设置面板共用 muted 状态与存档）
-- 运行端: 客户端/单机
-- ============================================================================

local DrawUtil = require("core.DrawUtil")
local BF       = require("systems.ButtonFeedback")
local SettingsPanel = require("ui.hud.popup.SettingsPanel")

local drawImageCentered = DrawUtil.drawImageCentered
local drawTextStroke    = DrawUtil.drawTextStroke

local SoundToggle = {}

-- 设计坐标：与扫荡(971)/统计(815)/选关(659)同排，位于最左（间距 156）
local BTN_CX = 503
local BTN_CY = 2115
local BTN_W  = 130
local BTN_H  = 144

local imgOn  = -1   -- UI_ICON_YX_KQ.png（喇叭+声波，开启态）
local imgOff = -1   -- UI_ICON_YX_GB.png（喇叭+斜杠，关闭态）

--- 加载图片资源（由 BattleTriPage.init 调用）
---@param vg any
function SoundToggle.initImages(vg)
    imgOn  = nvgCreateImage(vg, "image/通用图标/UI_ICON_YX_KQ.png", 0)
    imgOff = nvgCreateImage(vg, "image/通用图标/UI_ICON_YX_GB.png", 0)
    if imgOn < 0  then print("[SoundToggle] WARN: UI_ICON_YX_KQ.png load failed") end
    if imgOff < 0 then print("[SoundToggle] WARN: UI_ICON_YX_GB.png load failed") end
end

--- 绘制入口按钮（由 BattleTriPage.drawHud 在设计空间平移缩放后调用）
---@param vg any
function SoundToggle.drawButton(vg, teamIdx)
    local GameSFX = require("systems.GameSFX")
    local on = teamIdx and (not GameSFX.isTeamMuted(teamIdx)) or (not teamIdx and SettingsPanel.isSoundOn())
    local img = on and imgOn or imgOff
    if not img or img < 0 then return end
    local _ds = BF.begin(vg, "sound_toggle_btn", BTN_CX, BTN_CY, BTN_W, BTN_H)
    drawImageCentered(vg, img, BTN_CX, BTN_CY, BTN_W, BTN_H, 1.0)
    -- 图标下方文字标签（样式与选关/统计/扫荡一致：白色 32px 描边4）
    drawTextStroke(vg, BTN_CX, BTN_CY + BTN_H * 0.42, "音效", 32,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, 255, 255, 255, 4)
    BF.finish(vg, _ds)
end

--- 点击处理（由 BattleTriPage hit test 后调用）
function SoundToggle.handleButtonInput(teamIdx)
    if teamIdx then
        local GameSFX = require("systems.GameSFX")
        GameSFX.setTeamMuted(teamIdx, not GameSFX.isTeamMuted(teamIdx))
        return
    end
    SettingsPanel.setSoundOn(not SettingsPanel.isSoundOn())
end

return SoundToggle
