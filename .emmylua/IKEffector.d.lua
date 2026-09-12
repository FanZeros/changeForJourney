---@meta

--- Auto-generated from IK/IKEffector

---@class IKEffector : Component
---@field targetNode Node
---@field targetName string
---@field targetPosition Vector3
---@field targetRotation Quaternion
---@field chainLength integer
---@field weight number
---@field rotationWeight number
---@field rotationDecay number
---@field WEIGHT_NLERP boolean
---@field INHERIT_PARENT_ROTATION boolean
IKEffector = {}

---@return Node
function IKEffector:GetTargetNode() end

---@param targetNode Node
---@return nil
function IKEffector:SetTargetNode(targetNode) end

---@return string
function IKEffector:GetTargetName() end

---@param nodeName string
---@return nil
function IKEffector:SetTargetName(nodeName) end

---@return Vector3
function IKEffector:GetTargetPosition() end

---@param targetPosition Vector3
---@return nil
function IKEffector:SetTargetPosition(targetPosition) end

---@return Quaternion
function IKEffector:GetTargetRotation() end

---@param targetRotation Quaternion
---@return nil
function IKEffector:SetTargetRotation(targetRotation) end

---@return integer
function IKEffector:GetChainLength() end

---@param chainLength integer
---@return nil
function IKEffector:SetChainLength(chainLength) end

---@return number
function IKEffector:GetWeight() end

---@param weight number
---@return nil
function IKEffector:SetWeight(weight) end

---@return number
function IKEffector:GetRotationWeight() end

---@param weight number
---@return nil
function IKEffector:SetRotationWeight(weight) end

---@return number
function IKEffector:GetRotationDecay() end

---@param decay number
---@return nil
function IKEffector:SetRotationDecay(decay) end

