-- ============================================================================
-- SpineCardEffect - 卡片特效 Spine 动画（升级/转职/复活）
-- 底层封装：直接使用 nvgSpineCreate / nvgSpineRender 在 NanoVG 中播放
--
-- 支持多实例同时播放（不同卡片位置），每个 play 调用创建一个独立播放实例。
--
-- 用法：
--   local SpineCardEffect = require("ui.SpineCardEffect")
--   SpineCardEffect.playLevelUp(cx, cy, function() end)   -- 升级
--   SpineCardEffect.playJobChange(cx, cy, function() end)  -- 转职
--   SpineCardEffect.playRevive(cx, cy, function() end)     -- 复活
--   在 NanoVGRender 中调用 SpineCardEffect.draw(vg)
-- ============================================================================

---@diagnostic disable: undefined-global
-- nvgSpineCreate / nvgSpineRender 是引擎内置全局函数（NanoVG Spine 扩展）

local SpineCardEffect = {}

-- Spine 资源路径
local SPINE_JSON = "image/spine/UI_SPINE_KPTX.json"

-- 【约定】所有 Spine 动画统一使用 1:1 缩放（设计稿像素 = Spine 像素），
--        除非有特别说明需要自定义缩放比例。

-- 动画名称映射
local ANIM_LEVEL_UP  = "1"   -- 升级
local ANIM_JOB_CHANGE = "2"  -- 转职
local ANIM_REVIVE    = "3"   -- 复活

-- Spine 骨架原始尺寸（从 JSON skeleton 字段读取）
local DATA_X = -332.96
local DATA_Y = -604.5
local DATA_W = 665.91
local DATA_H = 1209

-- 活跃播放实例列表
-- 每个元素: { inst, cx, cy, lastT, onComplete }
local activeInstances = {}

--- 内部：创建并播放一个 Spine 实例
---@param vg any NanoVG 上下文（可为 nil，延迟到 draw 时加载）
---@param animName string 动画名称 "1"/"2"/"3"
---@param cx number 绘制中心 X
---@param cy number 绘制中心 Y
---@param onComplete? function 播放完成回调
local function playAnim(vg, animName, cx, cy, onComplete)
    local entry = {
        inst        = nil,
        cx          = cx,
        cy          = cy,
        lastT       = time.elapsedTime,
        onComplete  = onComplete,
        animName    = animName,
        loaded      = false,
        finished    = false,
    }
    activeInstances[#activeInstances + 1] = entry

    -- 如果已有 vg 上下文，立刻加载
    if vg then
        local inst = nvgSpineCreate(vg)
        if inst and inst:Load(SPINE_JSON) then
            inst:SetPremultipliedAlpha(true)
            inst:SetSpeed(1.0)
            inst:SetAnimation(0, animName, false)
            ---@diagnostic disable-next-line: param-type-mismatch
            inst:SetCompleteListener(function()
                entry.finished = true
            end)
            entry.inst = inst
            entry.loaded = true
        else
            print("[SpineCardEffect] Failed to load: " .. SPINE_JSON)
        end
    end
end

--- 播放升级动画
---@param cx number 卡片中心 X
---@param cy number 卡片中心 Y
---@param onComplete? function 播放完成回调
function SpineCardEffect.playLevelUp(cx, cy, onComplete)
    playAnim(nil, ANIM_LEVEL_UP, cx, cy, onComplete)
    print("[SpineCardEffect] PlayLevelUp at " .. cx .. "," .. cy)
end

--- 播放转职动画
---@param cx number 卡片中心 X
---@param cy number 卡片中心 Y
---@param onComplete? function 播放完成回调
function SpineCardEffect.playJobChange(cx, cy, onComplete)
    playAnim(nil, ANIM_JOB_CHANGE, cx, cy, onComplete)
    print("[SpineCardEffect] PlayJobChange at " .. cx .. "," .. cy)
end

--- 播放复活动画
---@param cx number 卡片中心 X
---@param cy number 卡片中心 Y
---@param onComplete? function 播放完成回调
function SpineCardEffect.playRevive(cx, cy, onComplete)
    playAnim(nil, ANIM_REVIVE, cx, cy, onComplete)
    print("[SpineCardEffect] PlayRevive at " .. cx .. "," .. cy)
end

--- 是否有任何实例正在播放
---@return boolean
function SpineCardEffect.isPlaying()
    return #activeInstances > 0
end

--- 每帧绘制所有活跃实例（在 NanoVG 渲染函数中调用）
---@param vg any NanoVG 上下文
function SpineCardEffect.draw(vg)
    if #activeInstances == 0 then return end

    local now = time.elapsedTime

    -- 1:1 缩放下的数据中心偏移
    local dataCenterX = DATA_X + DATA_W * 0.5
    local dataCenterY = DATA_Y + DATA_H * 0.5

    -- 从后往前遍历，方便安全删除
    for i = #activeInstances, 1, -1 do
        local e = activeInstances[i]

        -- 懒加载：首次 draw 时创建实例
        if not e.loaded then
            local inst = nvgSpineCreate(vg)
            if inst and inst:Load(SPINE_JSON) then
                inst:SetPremultipliedAlpha(true)
                inst:SetSpeed(1.0)
                inst:SetAnimation(0, e.animName, false)
                ---@diagnostic disable-next-line: param-type-mismatch
                inst:SetCompleteListener(function()
                    e.finished = true
                end)
                e.inst = inst
                e.loaded = true
                e.lastT = now
            else
                -- 加载失败，移除
                print("[SpineCardEffect] Failed to lazy-load: " .. SPINE_JSON)
                table.remove(activeInstances, i)
                if e.onComplete then e.onComplete() end
                goto continue
            end
        end

        -- 播放完成：先 Unload 释放 GPU/内存资源，再移出列表
        if e.finished then
            if e.inst then e.inst:Unload() end
            table.remove(activeInstances, i)
            if e.onComplete then e.onComplete() end
            goto continue
        end

        -- 计算 dt
        local dt = now - e.lastT
        if dt > 0.1 then dt = 0.016 end  -- 防止暂停后大跳
        e.lastT = now

        -- 更新并渲染
        local inst = e.inst
        inst:Update(dt)
        inst:SetScale(1.0, -1.0)

        local posX = e.cx - dataCenterX
        local posY = e.cy + dataCenterY
        inst:SetPosition(posX, posY)

        nvgSpineRender(vg, inst)

        ::continue::
    end
end

--- 预加载 Spine 实例（在 LoadingScreen 阶段调用，避免首次播放卡顿）
--- 创建一个隐藏实例，触发 JSON/atlas/纹理的解析和 GPU 上传
local preloadInst = nil
---@param vg any NanoVG 上下文
function SpineCardEffect.preload(vg)
    if preloadInst then return end
    if not vg then return end
    local inst = nvgSpineCreate(vg)
    if inst and inst:Load(SPINE_JSON) then
        inst:SetPremultipliedAlpha(true)
        preloadInst = inst  -- 持有引用，防止纹理被回收
        print("[SpineCardEffect] Preloaded OK")
    end
end

--- 停止所有播放中的实例，并释放所有 GPU/内存资源
function SpineCardEffect.stopAll()
    for _, e in ipairs(activeInstances) do
        if e.inst then
            e.inst:Unload()  -- 完整释放 GPU/内存，防止面板关闭时泄漏
        end
    end
    activeInstances = {}
end

--- 释放所有资源
function SpineCardEffect.destroy()
    for _, e in ipairs(activeInstances) do
        if e.inst then
            e.inst:Unload()
        end
    end
    activeInstances = {}
end

return SpineCardEffect
