---@meta

--- Auto-generated from Input/Input

---@alias MouseMode
---| integer # MouseMode enum values

---@type MouseMode
MM_ABSOLUTE = 0
---@type MouseMode
MM_RELATIVE = 1
---@type MouseMode
MM_WRAP = 2
---@type MouseMode
MM_FREE = 3

---@class TouchState
---@field touchID integer
---@field position IntVector2
---@field lastPosition IntVector2
---@field delta IntVector2
---@field pressure number
---@field touchedElement UIElement
TouchState = {}

---@return UIElement
function TouchState:GetTouchedElement() end


---@class JoystickState
---@field name string
---@field joystickID integer
---@field controller boolean
---@field numButtons integer
---@field numAxes integer
---@field numHats integer
JoystickState = {}

---@return boolean
function JoystickState:IsController() end

---@return integer
function JoystickState:GetNumButtons() end

---@return integer
function JoystickState:GetNumAxes() end

---@return integer
function JoystickState:GetNumHats() end

---@param index integer
---@return boolean
function JoystickState:GetButtonDown(index) end

---@param index integer
---@return boolean
function JoystickState:GetButtonPress(index) end

---@param index integer
---@return number
function JoystickState:GetAxisPosition(index) end

---@param index integer
---@return integer
function JoystickState:GetHatPosition(index) end


---@class Input : Object
---@field qualifiers integer
---@field mousePosition IntVector2
---@field mouseMove IntVector2
---@field mouseMoveX integer
---@field mouseMoveY integer
---@field mouseMoveWheel integer
---@field inputScale Vector2
---@field numTouches integer
---@field numJoysticks integer
---@field toggleFullscreen boolean
---@field screenKeyboardSupport boolean
---@field mouseMode MouseMode
---@field screenKeyboardVisible boolean
---@field touchEmulation boolean
---@field mouseVisible boolean
---@field mouseGrabbed boolean
---@field mouseLocked boolean
---@field focus boolean
---@field minimized boolean
Input = {}

---@param enable boolean
---@return nil
function Input:SetToggleFullscreen(enable) end

---@param enable boolean
---@param suppressEvent? boolean
---@return nil
function Input:SetMouseVisible(enable, suppressEvent) end

---@return nil
function Input:ResetMouseVisible() end

---@param grab boolean
---@param suppressEvent? boolean
---@return nil
function Input:SetMouseGrabbed(grab, suppressEvent) end

---@return nil
function Input:ResetMouseGrabbed() end

---@param mode MouseMode
---@param suppressEvent? boolean
---@return nil
function Input:SetMouseMode(mode, suppressEvent) end

---@return nil
function Input:ResetMouseMode() end

---@return boolean
function Input:IsMouseLocked() end

---@param layoutFile? XMLFile
---@param styleFile? XMLFile
---@return integer
function Input:AddScreenJoystick(layoutFile, styleFile) end

---@param id integer
---@return boolean
function Input:RemoveScreenJoystick(id) end

---@param id integer
---@param enable boolean
---@return nil
function Input:SetScreenJoystickVisible(id, enable) end

---@param enable boolean
---@return nil
function Input:SetScreenKeyboardVisible(enable) end

---@param enable boolean
---@return nil
function Input:SetTouchEmulation(enable) end

---@return nil
function Input:EnableAccelerometer() end

---@return nil
function Input:DisableAccelerometer() end

---@return boolean
function Input:IsAccelerometerEnabled() end

---@return boolean
function Input:RecordGesture() end

---@param dest File
---@return boolean
function Input:SaveGestures(dest) end

---@param fileName string
---@return boolean
function Input:SaveGestures(fileName) end

---@param dest File
---@param gestureID integer
---@return boolean
function Input:SaveGesture(dest, gestureID) end

---@param fileName string
---@param gestureID integer
---@return boolean
function Input:SaveGesture(fileName, gestureID) end

---@param source File
---@return integer
function Input:LoadGestures(source) end

---@param fileName string
---@return integer
function Input:LoadGestures(fileName) end

---@param gestureID integer
---@return boolean
function Input:RemoveGesture(gestureID) end

---@return nil
function Input:RemoveAllGestures() end

---@param position IntVector2
---@return nil
function Input:SetMousePosition(position) end

---@return nil
function Input:CenterMousePosition() end

---@param name string
---@return Key
function Input:GetKeyFromName(name) end

---@param scancode Scancode
---@return Key
function Input:GetKeyFromScancode(scancode) end

---@param key Key
---@return string
function Input:GetKeyName(key) end

---@param key Key
---@return Scancode
function Input:GetScancodeFromKey(key) end

---@param name string
---@return Scancode
function Input:GetScancodeFromName(name) end

---@param scancode Scancode
---@return string
function Input:GetScancodeName(scancode) end

---@param key Key
---@return boolean
function Input:GetKeyDown(key) end

---@param key Key
---@return boolean
function Input:GetKeyPress(key) end

---@param key Key
---@return boolean
function Input:GetKeyRelease(key) end

---@param scancode Scancode
---@return boolean
function Input:GetScancodeDown(scancode) end

---@param scancode Scancode
---@return boolean
function Input:GetScancodePress(scancode) end

---@param scancode Scancode
---@return boolean
function Input:GetScancodeRelease(scancode) end

---@param button MouseButton
---@return boolean
function Input:GetMouseButtonDown(button) end

---@param button MouseButton
---@return boolean
function Input:GetMouseButtonPress(button) end

---@param button MouseButton
---@return boolean
function Input:GetMouseButtonRelease(button) end

---@param qualifier Qualifier
---@return boolean
function Input:GetQualifierDown(qualifier) end

---@param qualifier Qualifier
---@return boolean
function Input:GetQualifierPress(qualifier) end

---@param qualifier Qualifier
---@return boolean
function Input:GetQualifierRelease(qualifier) end

---@return integer
function Input:GetQualifiers() end

---@return IntVector2
function Input:GetMousePosition() end

---@return IntVector2
function Input:GetMouseMove() end

---@return integer
function Input:GetMouseMoveX() end

---@return integer
function Input:GetMouseMoveY() end

---@return integer
function Input:GetMouseMoveWheel() end

---@return Vector2
function Input:GetInputScale() end

---@return integer
function Input:GetNumTouches() end

---@param index integer
---@return TouchState
function Input:GetTouch(index) end

---@return integer
function Input:GetNumJoysticks() end

---@param id integer
---@return JoystickState
function Input:GetJoystick(id) end

---@param index integer
---@return JoystickState
function Input:GetJoystickByIndex(index) end

---@param name string
---@return JoystickState
function Input:GetJoystickByName(name) end

---@return boolean
function Input:GetToggleFullscreen() end

---@return boolean
function Input:GetScreenKeyboardSupport() end

---@param id integer
---@return boolean
function Input:IsScreenJoystickVisible(id) end

---@return boolean
function Input:IsScreenKeyboardVisible() end

---@return boolean
function Input:GetTouchEmulation() end

---@return boolean
function Input:IsMouseVisible() end

---@return boolean
function Input:IsMouseGrabbed() end

---@return MouseMode
function Input:GetMouseMode() end

---@return boolean
function Input:HasFocus() end

---@return boolean
function Input:IsMinimized() end


-- Global functions
---@return Input
function GetInput() end

-- Global variables
---@type Input
input = nil
