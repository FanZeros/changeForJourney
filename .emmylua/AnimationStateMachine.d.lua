---@meta

--- Auto-generated from Animation/AnimationStateMachine

---@alias RootMotionChannel
---| integer # RootMotionChannel enum values

---@type RootMotionChannel
ROOT_MOTION_POSITION_X = 1
---@type RootMotionChannel
ROOT_MOTION_POSITION_Y = 2
---@type RootMotionChannel
ROOT_MOTION_POSITION_Z = 4
---@type RootMotionChannel
ROOT_MOTION_ROTATION = 8
---@type RootMotionChannel
ROOT_MOTION_DEFAULT_CHANNELS = 13
---@type RootMotionChannel
ROOT_MOTION_ALL_CHANNELS = 15

---@class RootMotionDelta
---@field translation Vector3
---@field rotation Quaternion
---@field positionWeights Vector3
---@field rotationWeight number
---@field channels integer
---@field duration number
---@field sequence integer
RootMotionDelta = {}

---@return boolean
function RootMotionDelta:IsIdentity() end


---@class AnimationStateMachine : Component
---@field name string
---@field numLayers integer
---@field parameterContext ParameterContext
---@field rootMotionDelta boolean
AnimationStateMachine = {}

---@param json JSONValue
---@return boolean
function AnimationStateMachine:LoadFromJSON(json) end

---@param file JSONFile
---@return boolean
function AnimationStateMachine:LoadFromJSONFile(file) end

---@param name string
---@return nil
function AnimationStateMachine:SetName(name) end

---@return string
function AnimationStateMachine:GetName() end

---@param stateName string
---@return nil
function AnimationStateMachine:SetDefaultState(stateName) end

---@param time number
---@return nil
function AnimationStateMachine:SetDefaultBlendTime(time) end

---@return nil
function AnimationStateMachine:Start() end

---@return integer
function AnimationStateMachine:GetNumLayers() end

---@param layerIndex integer
---@param weight number
---@return nil
function AnimationStateMachine:SetLayerWeight(layerIndex, weight) end

---@param layerIndex integer
---@return number
function AnimationStateMachine:GetLayerWeight(layerIndex) end

---@param stateName string
---@param animationPath string
---@param loop? boolean
---@param speed? number
---@return nil
function AnimationStateMachine:AddStateFromPath(stateName, animationPath, loop, speed) end

---@param fromState string
---@param toState string
---@param condition string
---@param priority? integer
---@param blendTime? number
---@return nil
function AnimationStateMachine:AddTransition(fromState, toState, condition, priority, blendTime) end

---@param fromState string
---@param toState string
---@param condition string
---@return nil
function AnimationStateMachine:AddTransitionSimple(fromState, toState, condition) end

---@param name string
---@param defaultValue? number
---@param min? number
---@param max? number
---@return nil
function AnimationStateMachine:DefineFloat(name, defaultValue, min, max) end

---@param name string
---@param defaultValue? integer
---@param min? number
---@param max? number
---@return nil
function AnimationStateMachine:DefineInt(name, defaultValue, min, max) end

---@param name string
---@param defaultValue? boolean
---@return nil
function AnimationStateMachine:DefineBool(name, defaultValue) end

---@param name string
---@return nil
function AnimationStateMachine:DefineTrigger(name) end

---@return ParameterContext
function AnimationStateMachine:GetParameterContext() end

---@param context ParameterContext
---@return nil
function AnimationStateMachine:SetParameterContext(context) end

---@param name string
---@param value number
---@return nil
function AnimationStateMachine:SetFloat(name, value) end

---@param name string
---@param value integer
---@return nil
function AnimationStateMachine:SetInt(name, value) end

---@param name string
---@param value boolean
---@return nil
function AnimationStateMachine:SetBool(name, value) end

---@param name string
---@return nil
function AnimationStateMachine:SetTrigger(name) end

---@param name string
---@return number
function AnimationStateMachine:GetFloat(name) end

---@param name string
---@return integer
function AnimationStateMachine:GetInt(name) end

---@param name string
---@return boolean
function AnimationStateMachine:GetBool(name) end

---@param layerIndex? integer
---@return string
function AnimationStateMachine:GetCurrentState(layerIndex) end

---@param layerIndex? integer
---@return string
function AnimationStateMachine:GetPreviousState(layerIndex) end

---@param stateName string
---@param layerIndex? integer
---@return boolean
function AnimationStateMachine:IsInState(stateName, layerIndex) end

---@param layerIndex? integer
---@return number
function AnimationStateMachine:GetStateTime(layerIndex) end

---@param layerIndex? integer
---@return number
function AnimationStateMachine:GetNormalizedTime(layerIndex) end

---@param layerIndex? integer
---@return boolean
function AnimationStateMachine:IsAnimationFinished(layerIndex) end

---@param stateName string
---@param layerIndex? integer
---@return nil
function AnimationStateMachine:ForceState(stateName, layerIndex) end

---@param layerIndex? integer
---@return boolean
function AnimationStateMachine:IsTransitioning(layerIndex) end

---@param timeStep number
---@return nil
function AnimationStateMachine:Update(timeStep) end

---@return boolean
function AnimationStateMachine:HasRootMotionDelta() end

---@param duration number
---@return RootMotionDelta
function AnimationStateMachine:PeekRootMotionDelta(duration) end

---@param duration number
---@return RootMotionDelta
function AnimationStateMachine:ConsumeRootMotionDelta(duration) end

---@return nil
function AnimationStateMachine:ClearRootMotionDeltas() end

---@return nil
function AnimationStateMachine:DebugPrintParameters() end

---@return nil
function AnimationStateMachine:DebugPrintState() end

---@return nil
function AnimationStateMachine:DebugPrintTransitions() end

---@return nil
function AnimationStateMachine:DebugPrintLayers() end

---@param condition string
---@return nil
function AnimationStateMachine:DebugEvaluateCondition(condition) end

---@return nil
function AnimationStateMachine:DebugPrintSkeleton() end

---@return nil
function AnimationStateMachine:DebugPrintBlendSpaceTracks() end

