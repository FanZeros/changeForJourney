---@meta

--- Auto-generated from IK/IKSolver

---@class IKSolver : Component
---@field algorithm Algorithm
---@field maximumIterations integer
---@field tolerance number
---@field JOINT_ROTATIONS boolean
---@field TARGET_ROTATIONS boolean
---@field UPDATE_ORIGINAL_POSE boolean
---@field UPDATE_ACTIVE_POSE boolean
---@field USE_ORIGINAL_POSE boolean
---@field CONSTRAINTS boolean
---@field AUTO_SOLVE boolean
---@field ONE_BONE integer # Algorithm enum value (static)
---@field TWO_BONE integer # Algorithm enum value (static)
---@field FABRIK integer # Algorithm enum value (static)
IKSolver = {}

---@return nil
function IKSolver:RebuildChainTrees() end

---@return nil
function IKSolver:RecalculateSegmentLengths() end

---@return nil
function IKSolver:CalculateJointRotations() end

---@return nil
function IKSolver:Solve() end

---@return nil
function IKSolver:ApplyOriginalPoseToScene() end

---@return nil
function IKSolver:ApplySceneToOriginalPose() end

---@return nil
function IKSolver:ApplyActivePoseToScene() end

---@return nil
function IKSolver:ApplySceneToActivePose() end

---@return nil
function IKSolver:ApplyOriginalPoseToActivePose() end

---@param depthTest boolean
---@return nil
function IKSolver:DrawDebugGeometry(depthTest) end

