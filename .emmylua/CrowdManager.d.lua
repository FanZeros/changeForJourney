---@meta

--- Auto-generated from Navigation/CrowdManager

---@class CrowdManager : Component
---@field maxAgents integer
---@field maxAgentRadius number
---@field navigationMesh NavigationMesh
CrowdManager = {}

---@param depthTest boolean
---@return nil
function CrowdManager:DrawDebugGeometry(depthTest) end

---@param position Vector3
---@param node? Node
---@return nil
function CrowdManager:SetCrowdTarget(position, node) end

---@param velocity Vector3
---@param node? Node
---@return nil
function CrowdManager:SetCrowdVelocity(velocity, node) end

---@param node? Node
---@return nil
function CrowdManager:ResetCrowdTarget(node) end

---@param agentCt integer
---@return nil
function CrowdManager:SetMaxAgents(agentCt) end

---@param maxAgentRadius number
---@return nil
function CrowdManager:SetMaxAgentRadius(maxAgentRadius) end

---@param navMesh NavigationMesh
---@return nil
function CrowdManager:SetNavigationMesh(navMesh) end

---@param queryFilterType integer
---@param flags integer -- unsigned short
---@return nil
function CrowdManager:SetIncludeFlags(queryFilterType, flags) end

---@param queryFilterType integer
---@param flags integer -- unsigned short
---@return nil
function CrowdManager:SetExcludeFlags(queryFilterType, flags) end

---@param queryFilterType integer
---@param areaID integer
---@param cost number
---@return nil
function CrowdManager:SetAreaCost(queryFilterType, areaID, cost) end

---@param obstacleAvoidanceType integer
---@param params CrowdObstacleAvoidanceParams
---@return nil
function CrowdManager:SetObstacleAvoidanceParams(obstacleAvoidanceType, params) end

---@param node? Node
---@param inCrowdFilter? boolean
---@return CrowdAgent[]
function CrowdManager:GetAgents(node, inCrowdFilter) end

---@param point Vector3
---@param queryFilterType integer
---@return Vector3
function CrowdManager:FindNearestPoint(point, queryFilterType) end

---@param start Vector3
---@param end_ Vector3
---@param queryFilterType integer
---@param maxVisited? integer
---@return Vector3
function CrowdManager:MoveAlongSurface(start, end_, queryFilterType, maxVisited) end

---@param start Vector3
---@param end_ Vector3
---@param queryFilterType integer
---@return Vector3[]
function CrowdManager:FindPath(start, end_, queryFilterType) end

---@param queryFilterType integer
---@return Vector3
function CrowdManager:GetRandomPoint(queryFilterType) end

---@param center Vector3
---@param radius number
---@param queryFilterType integer
---@return Vector3
function CrowdManager:GetRandomPointInCircle(center, radius, queryFilterType) end

---@param point Vector3
---@param radius number
---@param queryFilterType integer
---@param hitPos? Vector3
---@param hitNormal? Vector3
---@return number
function CrowdManager:GetDistanceToWall(point, radius, queryFilterType, hitPos, hitNormal) end

---@param start Vector3
---@param end_ Vector3
---@param queryFilterType integer
---@param hitNormal? Vector3
---@return Vector3
function CrowdManager:Raycast(start, end_, queryFilterType, hitNormal) end

---@return integer
function CrowdManager:GetMaxAgents() end

---@return number
function CrowdManager:GetMaxAgentRadius() end

---@return NavigationMesh
function CrowdManager:GetNavigationMesh() end

---@return integer
function CrowdManager:GetNumQueryFilterTypes() end

---@param queryFilterType integer
---@return integer
function CrowdManager:GetNumAreas(queryFilterType) end

---@param queryFilterType integer
---@return integer
function CrowdManager:GetIncludeFlags(queryFilterType) end

---@param queryFilterType integer
---@return integer
function CrowdManager:GetExcludeFlags(queryFilterType) end

---@param queryFilterType integer
---@param areaID integer
---@return number
function CrowdManager:GetAreaCost(queryFilterType, areaID) end

---@return integer
function CrowdManager:GetNumObstacleAvoidanceTypes() end

---@param obstacleAvoidanceType integer
---@return CrowdObstacleAvoidanceParams
function CrowdManager:GetObstacleAvoidanceParams(obstacleAvoidanceType) end

