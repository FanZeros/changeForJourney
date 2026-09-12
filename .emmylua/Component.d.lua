---@meta

--- Auto-generated from Scene/Component

---@alias AutoRemoveMode
---| integer # AutoRemoveMode enum values

---@type AutoRemoveMode
REMOVE_DISABLED = 0
---@type AutoRemoveMode
REMOVE_COMPONENT = 1
---@type AutoRemoveMode
REMOVE_NODE = 2

---@class Component : Animatable
---@field ID integer
---@field replicated boolean
---@field enabled boolean
---@field enabledEffective boolean
---@field node Node
---@field scene Scene
---@field GetComponent __union_func__type_str__ret_ComponentT
Component = {}

---@param enable boolean
---@return nil
function Component:SetEnabled(enable) end

---@return nil
function Component:Remove() end

---@return nil
function Component:Dispose() end

---@param debug DebugRenderer
---@param depthTest boolean
---@return nil
function Component:DrawDebugGeometry(debug, depthTest) end

---@return integer
function Component:GetID() end

---@return boolean
function Component:IsReplicated() end

---@return Node
function Component:GetNode() end

---@return Scene
function Component:GetScene() end

---@return boolean
function Component:IsEnabled() end

---@return boolean
function Component:IsEnabledEffective() end

