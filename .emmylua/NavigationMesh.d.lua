---@meta

--- Auto-generated from Navigation/NavigationMesh

---@alias NavmeshPartitionType
---| integer # NavmeshPartitionType enum values

---@type NavmeshPartitionType
NAVMESH_PARTITION_WATERSHED = 0
---@type NavmeshPartitionType
NAVMESH_PARTITION_MONOTONE = 1

---@class NavigationGeometryInfo
---@field component Component
---@field lodLevel integer
---@field transform Matrix3x4
---@field boundingBox BoundingBox
NavigationGeometryInfo = {}


---@class NavigationMesh : Component
---@field tileSize integer
---@field cellSize number
---@field cellHeight number
---@field agentHeight number
---@field agentRadius number
---@field agentMaxClimb number
---@field agentMaxSlope number
---@field regionMinSize number
---@field regionMergeSize number
---@field edgeMaxLength number
---@field edgeMaxError number
---@field detailSampleDistance number
---@field detailSampleMaxError number
---@field padding Vector3
---@field partitionType NavmeshPartitionType
---@field drawOffMeshConnections boolean
---@field drawNavAreas boolean
---@field initialized boolean
---@field boundingBox BoundingBox
---@field worldBoundingBox BoundingBox
---@field numTiles IntVector2
NavigationMesh = {}

---@param size integer
---@return nil
function NavigationMesh:SetTileSize(size) end

---@param size number
---@return nil
function NavigationMesh:SetCellSize(size) end

---@param height number
---@return nil
function NavigationMesh:SetCellHeight(height) end

---@param height number
---@return nil
function NavigationMesh:SetAgentHeight(height) end

---@param radius number
---@return nil
function NavigationMesh:SetAgentRadius(radius) end

---@param maxClimb number
---@return nil
function NavigationMesh:SetAgentMaxClimb(maxClimb) end

---@param maxSlope number
---@return nil
function NavigationMesh:SetAgentMaxSlope(maxSlope) end

---@param size number
---@return nil
function NavigationMesh:SetRegionMinSize(size) end

---@param size number
---@return nil
function NavigationMesh:SetRegionMergeSize(size) end

---@param length number
---@return nil
function NavigationMesh:SetEdgeMaxLength(length) end

---@param error number
---@return nil
function NavigationMesh:SetEdgeMaxError(error) end

---@param distance number
---@return nil
function NavigationMesh:SetDetailSampleDistance(distance) end

---@param error number
---@return nil
function NavigationMesh:SetDetailSampleMaxError(error) end

---@param padding Vector3
---@return nil
function NavigationMesh:SetPadding(padding) end

---@param areaID integer
---@param cost number
---@return nil
function NavigationMesh:SetAreaCost(areaID, cost) end

---@param boundingBox BoundingBox
---@param maxTiles integer
---@return boolean
function NavigationMesh:Allocate(boundingBox, maxTiles) end

---@return boolean
function NavigationMesh:Build() end

---@param boundingBox BoundingBox
---@return boolean
function NavigationMesh:Build(boundingBox) end

---@param from IntVector2
---@param to IntVector2
---@return boolean
function NavigationMesh:Build(from, to) end

---@param tile IntVector2
---@return VectorBuffer
function NavigationMesh:GetTileData(tile) end

---@param tileData VectorBuffer
---@return boolean
function NavigationMesh:AddTile(tileData) end

---@param tile IntVector2
---@return nil
function NavigationMesh:RemoveTile(tile) end

---@return nil
function NavigationMesh:RemoveAllTiles() end

---@param tile IntVector2
---@return boolean
function NavigationMesh:HasTile(tile) end

---@param tile IntVector2
---@return BoundingBox
function NavigationMesh:GetTileBoudningBox(tile) end

---@param position Vector3
---@return IntVector2
function NavigationMesh:GetTileIndex(position) end

---@param aType NavmeshPartitionType
---@return nil
function NavigationMesh:SetPartitionType(aType) end

---@param enable boolean
---@return nil
function NavigationMesh:SetDrawOffMeshConnections(enable) end

---@param enable boolean
---@return nil
function NavigationMesh:SetDrawNavAreas(enable) end

---@param point Vector3
---@param extents? Vector3
---@return Vector3
function NavigationMesh:FindNearestPoint(point, extents) end

---@param start Vector3
---@param end_ Vector3
---@param extents? Vector3
---@param maxVisited? integer
---@return Vector3
function NavigationMesh:MoveAlongSurface(start, end_, extents, maxVisited) end

---@param start Vector3
---@param end_ Vector3
---@param extents? Vector3
---@return Vector3[]
function NavigationMesh:FindPath(start, end_, extents) end

---@return Vector3
function NavigationMesh:GetRandomPoint() end

---@param center Vector3
---@param radius number
---@param extents? Vector3
---@return Vector3
function NavigationMesh:GetRandomPointInCircle(center, radius, extents) end

---@param point Vector3
---@param radius number
---@param extents? Vector3
---@return number
function NavigationMesh:GetDistanceToWall(point, radius, extents) end

---@param start Vector3
---@param end_ Vector3
---@param extents? Vector3
---@return Vector3
function NavigationMesh:Raycast(start, end_, extents) end

---@param depthTest boolean
---@return nil
function NavigationMesh:DrawDebugGeometry(depthTest) end

---@return integer
function NavigationMesh:GetTileSize() end

---@return number
function NavigationMesh:GetCellSize() end

---@return number
function NavigationMesh:GetCellHeight() end

---@return number
function NavigationMesh:GetAgentHeight() end

---@return number
function NavigationMesh:GetAgentRadius() end

---@return number
function NavigationMesh:GetAgentMaxClimb() end

---@return number
function NavigationMesh:GetAgentMaxSlope() end

---@return number
function NavigationMesh:GetRegionMinSize() end

---@return number
function NavigationMesh:GetRegionMergeSize() end

---@return number
function NavigationMesh:GetEdgeMaxLength() end

---@return number
function NavigationMesh:GetEdgeMaxError() end

---@return number
function NavigationMesh:GetDetailSampleDistance() end

---@return number
function NavigationMesh:GetDetailSampleMaxError() end

---@return Vector3
function NavigationMesh:GetPadding() end

---@param areaID integer
---@return number
function NavigationMesh:GetAreaCost(areaID) end

---@return boolean
function NavigationMesh:IsInitialized() end

---@return BoundingBox
function NavigationMesh:GetBoundingBox() end

---@return BoundingBox
function NavigationMesh:GetWorldBoundingBox() end

---@return IntVector2
function NavigationMesh:GetNumTiles() end

---@return NavmeshPartitionType
function NavigationMesh:GetPartitionType() end

---@return boolean
function NavigationMesh:GetDrawOffMeshConnections() end

---@return boolean
function NavigationMesh:GetDrawNavAreas() end

