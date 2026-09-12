-- Common sample initialization as a framework for all samples.
--    - Create Urho3D logo at screen
--    - Set custom window title and icon
--    - Create Console and Debug HUD, and use F1 and F2 key to toggle them
--    - Use F3 key to toggle RuntimeDebugger (if available)
--    - Toggle rendering options from the keys 1-8
--    - Take screenshots with key 9
--    - Handle Esc key down to hide Console or exit application
--    - Init touch input on mobile platform

local logoSprite = nil
local _sampleNode = nil
local _sampleEventReceiver = nil

-- ScriptObject for event handling (prevents global event conflicts)
_SampleEventReceiver = ScriptObject()

-- Global variables (for scripts that require this file)
---@type Scene
scene_ = nil
---@type boolean
touchEnabled = false
---@type boolean
paused = false
---@type boolean
drawDebug = false
---@type Node
cameraNode = nil
---@type number
yaw = 0
---@type number
pitch = 0
---@type number
TOUCH_SENSITIVITY = 2
---@type number
useMouseMode_ = MM_ABSOLUTE

function SampleStart()
    -- Create detached node for ScriptObject (not attached to any scene)
    _sampleNode = Node()
    _sampleEventReceiver = _sampleNode:CreateScriptObject("_SampleEventReceiver")

    if GetPlatform() == "Android" or GetPlatform() == "iOS" or input.touchEmulation then
        -- On mobile platform, enable touch by adding virtual controls
        InitTouchInput()
    elseif input:GetNumJoysticks() == 0 then
        -- On desktop platform, do not detect touch when we already got a joystick
        _sampleEventReceiver:SubscribeToEvent("TouchBegin", "_SampleEventReceiver:HandleTouchBegin")
    end
    
    -- No longer create logo
    -- CreateLogo()

    -- Set custom window Title & Icon
    SetWindowTitleAndIcon()

    -- Create console and debug HUD
    CreateConsoleAndDebugHud()

    -- Subscribe key down event
    _sampleEventReceiver:SubscribeToEvent("KeyDown", "_SampleEventReceiver:HandleKeyDown")

    -- Subscribe key up event
    _sampleEventReceiver:SubscribeToEvent("KeyUp", "_SampleEventReceiver:HandleKeyUp")

    -- Subscribe scene update event
    _sampleEventReceiver:SubscribeToEvent("SceneUpdate", "_SampleEventReceiver:HandleSceneUpdate")
end

function InitTouchInput()
    touchEnabled = true
end

function SampleInitMouseMode(mode)
    useMouseMode_ = mode
    if mode == MM_FREE then
        input.mouseVisible = true
    end
    if mode ~= MM_ABSOLUTE then
        input.mouseMode = mode
    end
    -- Runtime mouse lock state is handled by InputExtensions.lua
end

function SetLogoVisible(enable)
    if logoSprite ~= nil then
        logoSprite.visible = enable
    end
end

function CreateLogo()
    -- Get logo texture
    local logoTexture = cache:GetResource("Texture2D", "Textures/Logo.png")
    if logoTexture == nil then
        return
    end

    -- Create logo sprite and add to the UI layout
    logoSprite = ui.root:CreateChild("Sprite")

    -- Set logo sprite texture
    logoSprite:SetTexture(logoTexture)

    local textureWidth = logoTexture.width
    local textureHeight = logoTexture.height

    -- Set logo sprite scale
    logoSprite:SetScale(graphics.width / 16 / textureWidth)

    -- Set logo sprite size
    logoSprite:SetSize(textureWidth, textureHeight)

    -- Set logo sprite hot spot
    logoSprite.hotSpot = IntVector2(textureWidth, textureHeight)

    -- Set logo sprite alignment
    logoSprite:SetAlignment(HA_RIGHT, VA_BOTTOM)

    -- Make logo not fully opaque to show the scene underneath
    logoSprite.opacity = 0.4

    -- Set a low priority for the logo so that other UI elements can be drawn on top
    logoSprite.priority = -100
end

function SetWindowTitleAndIcon()
    local icon = cache:GetResource("Image", "Textures/icon.png")
    graphics:SetWindowIcon(icon)
    graphics.windowTitle = "Urho3D Sample"
end

function CreateConsoleAndDebugHud()
    -- Get default style
    local uiStyle = cache:GetResource("XMLFile", "UI/DefaultStyle.xml")
    if uiStyle == nil then
        return
    end

    -- Create console
    engine:CreateConsole()
    console.defaultStyle = uiStyle
    console.background.opacity = 0.8

    -- Create debug HUD
    engine:CreateDebugHud()
    debugHud.defaultStyle = uiStyle
end

function _SampleEventReceiver:HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    -- Close console (if open) when ESC is pressed
    -- Mouse state is handled by InputExtensions.lua
    if key == KEY_ESCAPE then
        if console:IsVisible() then
            console:SetVisible(false)
        end
    end
end

function _SampleEventReceiver:HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_F1 then
        console:Toggle()

    elseif key == KEY_F2 then
        debugHud:ToggleAll()

    elseif key == KEY_F3 then
        -- Toggle RuntimeDebugger (if available)
        if runtimeDebugger then
            runtimeDebugger:Toggle()
        end
    end
end

function _SampleEventReceiver:HandleSceneUpdate(eventType, eventData)
    -- Move the camera by touch, if the camera node is initialized by descendant sample class
    if touchEnabled and cameraNode then
        for i=0, input:GetNumTouches()-1 do
            local state = input:GetTouch(i)
            -- Exclude touches occupied by virtual controls (if VirtualControls is loaded)
            local isOccupied = VirtualControls and VirtualControls.IsTouchOccupied(state.touchID) or false
            if not state.touchedElement and not isOccupied then -- Touch on empty space
                if state.delta.x or state.delta.y then
                    local camera = cameraNode:GetComponent("Camera")
                    if not camera then return end

                    yaw = yaw + TOUCH_SENSITIVITY * camera.fov / graphics.height * state.delta.x
                    pitch = pitch + TOUCH_SENSITIVITY * camera.fov / graphics.height * state.delta.y

                    -- Construct new orientation for the camera scene node from yaw and pitch; roll is fixed to zero
                    cameraNode:SetRotation(Quaternion(pitch, yaw, 0))
                else
                    -- Move the cursor to the touch position
                    local cursor = ui:GetCursor()
                    if cursor and cursor:IsVisible() then cursor:SetPosition(state.position) end
                end
            end
        end
    end
end

function _SampleEventReceiver:HandleTouchBegin(eventType, eventData)
    -- On some platforms like Windows the presence of touch input can only be detected dynamically
    InitTouchInput()
    _sampleEventReceiver:UnsubscribeFromEvent("TouchBegin")
end

-- Mouse mode handling moved to InputExtensions.lua
