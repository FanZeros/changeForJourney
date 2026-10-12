-- 选关行内奖励预览：仅绘制静态数据，不随机、不发奖、不创建额外上下文/字体。
local DrawUtil = require("core.DrawUtil")
local DarkIcon = require("core.DarkIcon")
local NumberUtil = require("core.NumberUtil")
local I18n = require("core.I18n")
local TowerText = require("core.I18nTower")

local function towerText(source, ...)
    return string.format(TowerText.lookup(source, I18n.get()), ...)
end

local M = {}
local images = {} ---@type table<string, integer>
local retryAt = {} ---@type table<string, number>
local imageVg = nil ---@type any

--- 收益直接显示数值，保留不足一件的小数，不附加预估符号。
---@param amount number
---@return string
function M.formatEstimate(amount)
    if amount <= 0 then return "0" end
    if amount >= 10000 then return NumberUtil.format(amount) end
    if amount < 0.0001 then return "<0.0001" end
    local decimals = amount < 0.01 and 4 or (amount < 1 and 3 or 1)
    local text = string.format("%." .. decimals .. "f", amount)
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text
end

---@param vg any
function M.init(vg)
    -- 相同VG仍执行原有显式重置；更换VG只忘记旧句柄，由旧context生命周期释放。
    if imageVg == vg then
        for _, image in pairs(images) do nvgDeleteImage(vg, image) end
    end
    imageVg = vg
    images, retryAt = {}, {}
    print("[StageSelectRewardPreview] 奖励数值与经验初始化；塔首通/重打分列")
end

---@param vg any
---@param path string
---@return integer
local function getImage(vg, path)
    local cachedImages, retries = images, retryAt
    local image = cachedImages[path]
    if image and image >= 0 then return image end
    local now = time.elapsedTime
    if retries[path] and now < retries[path] then return -1 end
    local loaded = nvgCreateImage(vg, path, 0) or -1
    ---@cast loaded integer
    -- 加载可合作式让出；期间重置或换VG后，不发布已经过期的加载结果。
    if imageVg ~= vg or images ~= cachedImages then return -1 end
    if loaded >= 0 then
        cachedImages[path], retries[path] = loaded, nil
        print("[StageSelectRewardPreview] 复用奖励图标: " .. path)
    else
        retries[path] = now + 2
        print("[StageSelectRewardPreview] 图标暂不可用: " .. path)
    end
    return loaded
end

---@param vg any
---@param x number
---@param y number
---@param text string
---@param width number
---@param fontSize number
---@param alpha number
local function drawText(vg, x, y, text, width, fontSize, alpha)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    local measured = nvgTextBounds(vg, 0, 0, I18n.lookup(text))
    local size = measured > width and math.max(16, fontSize * width / measured) or fontSize
    nvgSave(vg)
    nvgIntersectScissor(vg, x, y - 16, width, 32)
    DrawUtil.drawTextStroke(vg, x, y, text, size, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE,
        255, 222, 164, 2, { alpha = alpha })
    nvgRestore(vg)
end

--- 奖励带独立于敌人横滚视口，x/y为已滚动的行坐标。
---@param vg any
---@param reward StageSelectRewardData|nil
---@param x number
---@param y number
---@param width number
---@param height number
---@param locked boolean
function M.draw(vg, reward, x, y, width, height, locked)
    if not reward then return end
    if imageVg ~= vg then M.init(vg) end
    local cachedImages = images
    local image = getImage(vg, reward.iconPath)
    if imageVg ~= vg or images ~= cachedImages then return end
    local alpha = locked and 0.55 or 1
    local cy = y + height * 0.5
    nvgSave(vg)
    nvgIntersectScissor(vg, x, y, width, height)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, width, height, 6)
    nvgFillColor(vg, nvgRGBA(26, 22, 16, locked and 110 or 185))
    nvgFill(vg)
    if reward.runStartFloor then
        -- 塔入口只保留首通奖励摘要，不在选关列表展开概率和经验公式。
        DarkIcon.drawQualityBg(vg, reward.quality, x + 22, cy, 28, 28, alpha)
        if image >= 0 then DrawUtil.drawImageCentered(vg, image, x + 22, cy, 24, 24, alpha) end
        drawText(vg, x + 44, cy, towerText("首通奖励 ×%s",
            NumberUtil.format(reward.firstAmount or 0)), width - 52, 23, alpha)
    else
        -- 三资源共用短标题，为装备关的远征经验保留完整宽度；右侧等级品质独立区。
        drawText(vg, x + 4, cy, "奖励", 44, 18, alpha)
        DarkIcon.drawQualityBg(vg, reward.quality, x + 68, cy, 30, 30, alpha)
        if image >= 0 then DrawUtil.drawImageCentered(vg, image, x + 68, cy, 24, 24, alpha) end
        drawText(vg, x + 90, cy, M.formatEstimate(reward.amount), 70, 22, alpha)
        local expWidth = reward.equipLevel and 202 or (width - 172)
        drawText(vg, x + 168, cy, I18n.format("远征经验 %s", NumberUtil.format(reward.playerExp or 0)),
            expWidth, 18, alpha)
        if reward.equipLevel then
            local detail = I18n.format("随机Lv.%d · 品质%d-%d", reward.equipLevel,
                reward.equipMinQuality or 1, reward.equipMaxQuality or 1)
            drawText(vg, x + 378, cy, detail, width - 382, 18, alpha)
        end
    end
    nvgRestore(vg)
end

return M
