---@meta

--- Auto-generated from GamePlay/CharacterComponent

---@class CharacterComponent : Component
---@overload fun(): CharacterComponent
---@field controls Controls
---@field rotationSpeed number
---@field autoRotateToMoveDir boolean
---@field airControlFactor number
---@field airFriction number
---@field airSpeedRatio number
---@field walkSpeed number
---@field runSpeed number
---@field enableWalkMode boolean
---@field applyRootMotion boolean
---@field applyRootMotionChannels integer
---@field moveSpeed number
---@field moving boolean
---@field onGround boolean
---@field jumping boolean
---@field jumpStarted boolean
---@field localVelocityX number
---@field localVelocityY number
---@field smoothMoveSpeed number
---@field moveDirection number
CharacterComponent = {}

---@return CharacterComponent
function CharacterComponent.new() end

---@param speed number
---@return nil
function CharacterComponent:SetRotationSpeed(speed) end

---@return number
function CharacterComponent:GetRotationSpeed() end

---@param enable boolean
---@return nil
function CharacterComponent:SetAutoRotateToMoveDir(enable) end

---@return boolean
function CharacterComponent:GetAutoRotateToMoveDir() end

---@param factor number
---@return nil
function CharacterComponent:SetAirControlFactor(factor) end

---@return number
function CharacterComponent:GetAirControlFactor() end

---@param friction number
---@return nil
function CharacterComponent:SetAirFriction(friction) end

---@return number
function CharacterComponent:GetAirFriction() end

---@param ratio number
---@return nil
function CharacterComponent:SetAirSpeedRatio(ratio) end

---@return number
function CharacterComponent:GetAirSpeedRatio() end

---@param speed number
---@return nil
function CharacterComponent:SetWalkSpeed(speed) end

---@return number
function CharacterComponent:GetWalkSpeed() end

---@param speed number
---@return nil
function CharacterComponent:SetRunSpeed(speed) end

---@return number
function CharacterComponent:GetRunSpeed() end

---@param enable boolean
---@return nil
function CharacterComponent:SetEnableWalkMode(enable) end

---@return boolean
function CharacterComponent:GetEnableWalkMode() end

---@param enable boolean
---@return nil
function CharacterComponent:SetApplyRootMotion(enable) end

---@return boolean
function CharacterComponent:GetApplyRootMotion() end

---@param channels integer
---@return nil
function CharacterComponent:SetApplyRootMotionChannels(channels) end

---@return integer
function CharacterComponent:GetApplyRootMotionChannels() end

---@return number
function CharacterComponent:GetMoveSpeed() end

---@return boolean
function CharacterComponent:IsMoving() end

---@return boolean
function CharacterComponent:IsOnGround() end

---@return boolean
function CharacterComponent:IsJumping() end

---@return boolean
function CharacterComponent:IsJumpStarted() end

---@return number
function CharacterComponent:GetLocalVelocityX() end

---@return number
function CharacterComponent:GetLocalVelocityY() end

---@return number
function CharacterComponent:GetSmoothMoveSpeed() end

---@return number
function CharacterComponent:GetMoveDirection() end


-- Global variables
---@type integer
CTRL_FORWARD = nil
---@type integer
CTRL_BACK = nil
---@type integer
CTRL_LEFT = nil
---@type integer
CTRL_RIGHT = nil
---@type integer
CTRL_JUMP = nil
---@type integer
CTRL_RUN = nil
---@type number
WALK_SPEED = nil
---@type number
RUN_SPEED = nil
---@type number
WALK_FORCE = nil
---@type number
MOVE_FORCE = nil
---@type number
INAIR_MOVE_FORCE = nil
---@type number
BRAKE_FORCE = nil
---@type number
JUMP_FORCE = nil
---@type number
YAW_SENSITIVITY = nil
---@type number
INAIR_THRESHOLD_TIME = nil
