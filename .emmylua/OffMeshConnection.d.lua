---@meta

--- Auto-generated from Navigation/OffMeshConnection

---@class OffMeshConnection : Component
---@field endPoint Node
---@field radius number
---@field bidirectional boolean
---@field mask integer
---@field areaID integer
OffMeshConnection = {}

---@param node Node
---@return nil
function OffMeshConnection:SetEndPoint(node) end

---@param radius number
---@return nil
function OffMeshConnection:SetRadius(radius) end

---@param enabled boolean
---@return nil
function OffMeshConnection:SetBidirectional(enabled) end

---@param newMask integer
---@return nil
function OffMeshConnection:SetMask(newMask) end

---@param newAreaID integer
---@return nil
function OffMeshConnection:SetAreaID(newAreaID) end

---@return Node
function OffMeshConnection:GetEndPoint() end

---@return number
function OffMeshConnection:GetRadius() end

---@return boolean
function OffMeshConnection:IsBidirectional() end

---@return integer
function OffMeshConnection:GetMask() end

---@return integer
function OffMeshConnection:GetAreaID() end

