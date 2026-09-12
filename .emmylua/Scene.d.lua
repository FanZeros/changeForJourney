---@meta

--- Auto-generated from Scene/Scene

---@alias LoadMode
---| integer # LoadMode enum values

---@type LoadMode
LOAD_RESOURCES_ONLY = 0
---@type LoadMode
LOAD_SCENE = 1
---@type LoadMode
LOAD_SCENE_AND_RESOURCES = 2

---@class Scene : Node
---@overload fun(): Scene
---@field updateEnabled boolean
---@field asyncLoading boolean
---@field asyncProgress number
---@field asyncLoadMode LoadMode
---@field fileName string
---@field checksum integer
---@field timeScale number
---@field elapsedTime number
---@field smoothingConstant number
---@field snapThreshold number
---@field asyncLoadingMs integer
---@field threadedUpdate boolean
---@field varNamesAttr string
---@field GetComponent __union_func__type_str__recursive_bool_opt__ret_ComponentT
Scene = {}

---@return Scene
function Scene.new() end

---@param source File
---@return boolean
function Scene:Load(source) end

---@param fileName string
---@return boolean
function Scene:Load(fileName) end

---@param dest File
---@return boolean
function Scene:Save(dest) end

---@param fileName string
---@return boolean
function Scene:Save(fileName) end

---@param source File
---@return boolean
function Scene:LoadXML(source) end

---@param source XMLElement
---@return boolean
function Scene:LoadXML(source) end

---@param fileName string
---@return boolean
function Scene:LoadXML(fileName) end

---@param dest File
---@param indentation? string
---@return boolean
function Scene:SaveXML(dest, indentation) end

---@param fileName string
---@param indentation? string
---@return boolean
function Scene:SaveXML(fileName, indentation) end

---@param source File
---@return boolean
function Scene:LoadJSON(source) end

---@param fileName string
---@return boolean
function Scene:LoadJSON(fileName) end

---@param dest File
---@param indentation? string
---@return boolean
function Scene:SaveJSON(dest, indentation) end

---@param fileName string
---@param indentation? string
---@return boolean
function Scene:SaveJSON(fileName, indentation) end

---@param source File
---@param position Vector3
---@param rotation Quaternion
---@param mode? CreateMode
---@return Node
function Scene:Instantiate(source, position, rotation, mode) end

---@param fileName string
---@param position Vector3
---@param rotation Quaternion
---@param mode? CreateMode
---@return Node
function Scene:Instantiate(fileName, position, rotation, mode) end

---@param source File
---@param position Vector3
---@param rotation Quaternion
---@param mode? CreateMode
---@return Node
function Scene:InstantiateXML(source, position, rotation, mode) end

---@param fileName string
---@param position Vector3
---@param rotation Quaternion
---@param mode? CreateMode
---@return Node
function Scene:InstantiateXML(fileName, position, rotation, mode) end

---@param source XMLElement
---@param position Vector3
---@param rotation Quaternion
---@param mode? CreateMode
---@return Node
function Scene:InstantiateXML(source, position, rotation, mode) end

---@param source File
---@param position Vector3
---@param rotation Quaternion
---@param mode? CreateMode
---@return Node
function Scene:InstantiateJSON(source, position, rotation, mode) end

---@param fileName string
---@param position Vector3
---@param rotation Quaternion
---@param mode? CreateMode
---@return Node
function Scene:InstantiateJSON(fileName, position, rotation, mode) end

---@param file File
---@param mode? LoadMode
---@return boolean
function Scene:LoadAsync(file, mode) end

---@param fileName string
---@param mode? LoadMode
---@return boolean
function Scene:LoadAsync(fileName, mode) end

---@param file File
---@param mode? LoadMode
---@return boolean
function Scene:LoadAsyncXML(file, mode) end

---@param fileName string
---@param mode? LoadMode
---@return boolean
function Scene:LoadAsyncXML(fileName, mode) end

---@return nil
function Scene:StopAsyncLoading() end

---@param clearReplicated? boolean
---@param clearLocal? boolean
---@return nil
function Scene:Clear(clearReplicated, clearLocal) end

---@param enable boolean
---@return nil
function Scene:SetUpdateEnabled(enable) end

---@param scale number
---@return nil
function Scene:SetTimeScale(scale) end

---@param time number
---@return nil
function Scene:SetElapsedTime(time) end

---@param constant number
---@return nil
function Scene:SetSmoothingConstant(constant) end

---@param threshold number
---@return nil
function Scene:SetSnapThreshold(threshold) end

---@param ms integer
---@return nil
function Scene:SetAsyncLoadingMs(ms) end

---@param id integer
---@return Node
function Scene:GetNode(id) end

---@param id integer
---@return boolean
function Scene:IsReplicatedID(id) end

---@return boolean
function Scene:IsUpdateEnabled() end

---@return boolean
function Scene:IsAsyncLoading() end

---@return number
function Scene:GetAsyncProgress() end

---@return LoadMode
function Scene:GetAsyncLoadMode() end

---@return string
function Scene:GetFileName() end

---@return integer
function Scene:GetChecksum() end

---@return number
function Scene:GetTimeScale() end

---@return number
function Scene:GetElapsedTime() end

---@return number
function Scene:GetSmoothingConstant() end

---@return number
function Scene:GetSnapThreshold() end

---@return integer
function Scene:GetAsyncLoadingMs() end

---@param hash StringHash|string
---@return string
function Scene:GetVarName(hash) end

---@param timeStep number
---@return nil
function Scene:Update(timeStep) end

---@return nil
function Scene:BeginThreadedUpdate() end

---@return nil
function Scene:EndThreadedUpdate() end

---@param component Component
---@return nil
function Scene:DelayedMarkedDirty(component) end

---@return boolean
function Scene:IsThreadedUpdate() end

---@param mode CreateMode
---@return integer
function Scene:GetFreeNodeID(mode) end

---@param mode CreateMode
---@return integer
function Scene:GetFreeComponentID(mode) end

---@param node Node
---@return nil
function Scene:NodeAdded(node) end

---@param node Node
---@return nil
function Scene:NodeRemoved(node) end

---@param component Component
---@return nil
function Scene:ComponentAdded(component) end

---@param component Component
---@return nil
function Scene:ComponentRemoved(component) end

---@param value string
---@return nil
function Scene:SetVarNamesAttr(value) end

---@return string
function Scene:GetVarNamesAttr() end

---@return nil
function Scene:PrepareNetworkUpdate() end

---@param connection Connection
---@return nil
function Scene:CleanupConnection(connection) end

---@param node Node
---@return nil
function Scene:MarkNetworkUpdate(node) end

---@param component Component
---@return nil
function Scene:MarkNetworkUpdate(component) end

---@param node Node
---@return nil
function Scene:MarkReplicationDirty(node) end

---@param tag string
---@return Node[]
function Scene:GetNodesWithTag(tag) end


-- Global variables
---@type integer
FIRST_REPLICATED_ID = nil
---@type integer
LAST_REPLICATED_ID = nil
---@type integer
FIRST_LOCAL_ID = nil
---@type integer
LAST_LOCAL_ID = nil
