-- Mobile framework for Android/iOS
-- Gamepad from Ninja Snow War
-- Touches patterns:
--     - 1 finger touch  = pick object through raycast
--     - 1 or 2 fingers drag  = rotate camera
--     - 2 fingers sliding in opposite direction (up/down) = zoom in/out

-- Setup: Call the update function 'UpdateTouches()' from HandleUpdate or equivalent update handler function

-- 加速度计：SDL_HINT_ACCELEROMETER_AS_JOYSTICK=1 把加速度计暴露成虚拟 joystick
-- 真身是模拟量 (-1..+1)，离散按键输出仅作为向后兼容桥
local ACCELEROMETER_THRESHOLD = 0.1
CAMERA_MIN_DIST = 1.0
CAMERA_MAX_DIST = 20.0

local zoom = false
---@type boolean
-- 历史叫法。实际控制加速度计开关——多个 sample 仍引用此名，保留以避免破坏外部脚本
useGyroscope = false
---@type number
cameraDistance = 5.0

-- 缓存 JoystickState：按名字查找比 index 0 抗手柄抢占，但每帧查 + 字面量构造临时 String
-- 有可观成本。命中后缓存，热插拔事件触发重查。
local accelJoystick_ = nil

local function InvalidateAccelCache()
    accelJoystick_ = nil
end

SubscribeToEvent("JoystickConnected", InvalidateAccelCache)
SubscribeToEvent("JoystickDisconnected", InvalidateAccelCache)

local function GetAccelJoystick()
    if accelJoystick_ ~= nil then return accelJoystick_ end
    if input.numJoysticks <= 0 then return nil end
    accelJoystick_ = input:GetJoystickByName("Android Accelerometer")
                  or input:GetJoystickByName("iOS Accelerometer")
    return accelJoystick_
end

--- 读加速度计为模拟向量。轴向跨平台不一致：Android 已按屏幕旋转归一化
--- （见 SDLActivity.onSensorChanged），iOS 为 SDL 原始设备轴向，两端符号可能不同。
--- 按 name 查找避免与真实手柄冲突；命中后缓存到 accelJoystick_。
---@return number sx -- 横向倾斜，-1..+1；死区内返回 0
---@return number sz -- 纵向倾斜，-1..+1；死区内返回 0
function ReadAccelerometer()
    if not useGyroscope then return 0, 0 end
    -- 懒加载：开启体感时确保加速度计已注册（引擎默认 hint=0 不注册）。幂等。
    input:EnableAccelerometer()
    local joystick = GetAccelJoystick()
    if not joystick or joystick.numAxes < 2 then return 0, 0 end
    local ax = joystick:GetAxisPosition(0)
    local ay = joystick:GetAxisPosition(1)
    if math.abs(ax) < ACCELEROMETER_THRESHOLD then ax = 0 end
    if math.abs(ay) < ACCELEROMETER_THRESHOLD then ay = 0 end
    return ax, ay
end

--- 把加速度计模拟量量化成离散按键写入 Controls（向后兼容用，丢失力度信息）
---@param controls Controls
function ApplyAccelerometerToControls(controls)
    local sx, sz = ReadAccelerometer()
    if sx < 0 then controls:Set(CTRL_LEFT, true) end
    if sx > 0 then controls:Set(CTRL_RIGHT, true) end
    if sz < 0 then controls:Set(CTRL_FORWARD, true) end
    if sz > 0 then controls:Set(CTRL_BACK, true) end
end

--- 双指反向滑动 → cameraDistance 缩放。独立于加速度计。
function UpdateZoomGesture()
    zoom = false
    if input.numTouches ~= 2 then return end
    local touch1 = input:GetTouch(0)
    local touch2 = input:GetTouch(1)

    if not touch1.touchedElement and not touch2.touchedElement and ((touch1.delta.y > 0 and touch2.delta.y < 0) or (touch1.delta.y < 0 and touch2.delta.y > 0)) then
        zoom = true
    end

    if zoom then
        local sens
        if Abs(touch1.position.y - touch2.position.y) > Abs(touch1.lastPosition.y - touch2.lastPosition.y) then sens = -1 else sens = 1 end
        cameraDistance = cameraDistance + Abs(touch1.delta.y - touch2.delta.y) * sens * TOUCH_SENSITIVITY / 50
        cameraDistance = Clamp(cameraDistance, CAMERA_MIN_DIST, CAMERA_MAX_DIST)
    end
end

--- 向后兼容入口：缩放 + 加速度计离散位写入。新代码请分别调 UpdateZoomGesture() / ReadAccelerometer()。
---@param controls Controls
function UpdateTouches(controls)
    UpdateZoomGesture()
    ApplyAccelerometerToControls(controls)
end
