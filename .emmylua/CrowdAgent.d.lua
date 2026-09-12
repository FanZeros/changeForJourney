---@meta

--- Auto-generated from Navigation/CrowdAgent

---@alias CrowdAgentRequestedTarget
---| integer # CrowdAgentRequestedTarget enum values

---@type CrowdAgentRequestedTarget
CA_REQUESTEDTARGET_NONE = 0
---@type CrowdAgentRequestedTarget
CA_REQUESTEDTARGET_POSITION = 1
---@type CrowdAgentRequestedTarget
CA_REQUESTEDTARGET_VELOCITY = 2

---@alias CrowdAgentTargetState
---| integer # CrowdAgentTargetState enum values

---@type CrowdAgentTargetState
CA_TARGET_NONE = 0
---@type CrowdAgentTargetState
CA_TARGET_FAILED = 1
---@type CrowdAgentTargetState
CA_TARGET_VALID = 2
---@type CrowdAgentTargetState
CA_TARGET_REQUESTING = 3
---@type CrowdAgentTargetState
CA_TARGET_WAITINGFORQUEUE = 4
---@type CrowdAgentTargetState
CA_TARGET_WAITINGFORPATH = 5
---@type CrowdAgentTargetState
CA_TARGET_VELOCITY = 6

---@alias CrowdAgentState
---| integer # CrowdAgentState enum values

---@type CrowdAgentState
CA_STATE_INVALID = 0
---@type CrowdAgentState
CA_STATE_WALKING = 1
---@type CrowdAgentState
CA_STATE_OFFMESH = 2

---@alias NavigationQuality
---| integer # NavigationQuality enum values

---@type NavigationQuality
NAVIGATIONQUALITY_LOW = 0
---@type NavigationQuality
NAVIGATIONQUALITY_MEDIUM = 1
---@type NavigationQuality
NAVIGATIONQUALITY_HIGH = 2

---@alias NavigationPushiness
---| integer # NavigationPushiness enum values

---@type NavigationPushiness
NAVIGATIONPUSHINESS_LOW = 0
---@type NavigationPushiness
NAVIGATIONPUSHINESS_MEDIUM = 1
---@type NavigationPushiness
NAVIGATIONPUSHINESS_HIGH = 2
---@type NavigationPushiness
NAVIGATIONPUSHINESS_NONE = 3

---@class CrowdAgent : Component
---@field targetPosition Vector3
---@field targetVelocity Vector3
---@field updateNodePosition boolean
---@field maxAccel number
---@field maxSpeed number
---@field radius number
---@field height number
---@field queryFilterType integer
---@field obstacleAvoidanceType integer
---@field navigationQuality NavigationQuality
---@field navigationPushiness NavigationPushiness
---@field position Vector3
---@field desiredVelocity Vector3
---@field actualVelocity Vector3
---@field requestedTargetType CrowdAgentRequestedTarget
---@field agentState CrowdAgentState
---@field targetState CrowdAgentTargetState
---@field requestedTarget boolean
---@field arrived boolean
---@field inCrowd boolean
CrowdAgent = {}

---@param depthTest boolean
---@return nil
function CrowdAgent:DrawDebugGeometry(depthTest) end

---@param position Vector3
---@return nil
function CrowdAgent:SetTargetPosition(position) end

---@param velocity Vector3
---@return nil
function CrowdAgent:SetTargetVelocity(velocity) end

---@return nil
function CrowdAgent:ResetTarget() end

---@param unodepos boolean
---@return nil
function CrowdAgent:SetUpdateNodePosition(unodepos) end

---@param maxAccel number
---@return nil
function CrowdAgent:SetMaxAccel(maxAccel) end

---@param maxSpeed number
---@return nil
function CrowdAgent:SetMaxSpeed(maxSpeed) end

---@param radius number
---@return nil
function CrowdAgent:SetRadius(radius) end

---@param height number
---@return nil
function CrowdAgent:SetHeight(height) end

---@param queryFilterType integer
---@return nil
function CrowdAgent:SetQueryFilterType(queryFilterType) end

---@param obstacleOvoidanceType integer
---@return nil
function CrowdAgent:SetObstacleAvoidanceType(obstacleOvoidanceType) end

---@param val NavigationQuality
---@return nil
function CrowdAgent:SetNavigationQuality(val) end

---@param val NavigationPushiness
---@return nil
function CrowdAgent:SetNavigationPushiness(val) end

---@return Vector3
function CrowdAgent:GetPosition() end

---@return Vector3
function CrowdAgent:GetDesiredVelocity() end

---@return Vector3
function CrowdAgent:GetActualVelocity() end

---@return Vector3
function CrowdAgent:GetTargetPosition() end

---@return Vector3
function CrowdAgent:GetTargetVelocity() end

---@return CrowdAgentRequestedTarget
function CrowdAgent:GetRequestedTargetType() end

---@return CrowdAgentState
function CrowdAgent:GetAgentState() end

---@return CrowdAgentTargetState
function CrowdAgent:GetTargetState() end

---@return boolean
function CrowdAgent:GetUpdateNodePosition() end

---@return number
function CrowdAgent:GetMaxAccel() end

---@return number
function CrowdAgent:GetMaxSpeed() end

---@return number
function CrowdAgent:GetRadius() end

---@return number
function CrowdAgent:GetHeight() end

---@return integer
function CrowdAgent:GetQueryFilterType() end

---@return integer
function CrowdAgent:GetObstacleAvoidanceType() end

---@return NavigationQuality
function CrowdAgent:GetNavigationQuality() end

---@return NavigationPushiness
function CrowdAgent:GetNavigationPushiness() end

---@return boolean
function CrowdAgent:HasRequestedTarget() end

---@return boolean
function CrowdAgent:HasArrived() end

---@return boolean
function CrowdAgent:IsInCrowd() end

