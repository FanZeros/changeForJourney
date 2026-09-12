---@meta

--- Auto-generated from Network/Connection

---@alias SceneSyncMode
---| integer # SceneSyncMode enum values

---@type SceneSyncMode
SCENE_SYNC_DEFAULT = 0
---@type SceneSyncMode
SCENE_SYNC_SERVER_REPLICATED = 1

---@class RemoteEvent
---@field senderID integer
---@field eventType StringHash|string
---@field eventData VariantMap
---@field inOrder boolean
RemoteEvent = {}


---@class Connection : Object
---@field identity VariantMap
---@field scene Scene
---@field controls Controls
---@field timeStamp number -- unsigned char
---@field position Vector3
---@field rotation Quaternion
---@field client boolean
---@field connected boolean
---@field connectPending boolean
---@field sceneLoaded boolean
---@field logStatistics boolean
---@field address string
---@field port integer -- unsigned short
---@field roundTripTime number
---@field lastHeardTime number
---@field bytesInPerSec number
---@field bytesOutPerSec number
---@field packetsInPerSec number
---@field packetsOutPerSec number
---@field numDownloads integer
---@field downloadName string
---@field downloadProgress number
---@field pulseButtonMask integer
Connection = {}

---@param msgID integer
---@param reliable boolean
---@param inOrder boolean
---@param msg VectorBuffer
---@return nil
function Connection:SendMessage(msgID, reliable, inOrder, msg) end

---@param eventType StringHash|string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Connection:SendRemoteEvent(eventType, inOrder, eventData) end

---@param eventType string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Connection:SendRemoteEvent(eventType, inOrder, eventData) end

---@param node Node
---@param eventType StringHash|string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Connection:SendRemoteEvent(node, eventType, inOrder, eventData) end

---@param node Node
---@param eventType string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Connection:SendRemoteEvent(node, eventType, inOrder, eventData) end

---@param newScene Scene
---@return nil
function Connection:SetScene(newScene) end

---@param newScene Scene
---@param mode SceneSyncMode
---@return nil
function Connection:SetScene(newScene, mode) end

---@return SceneSyncMode
function Connection:GetSceneSyncMode() end

---@param identity VariantMap
---@return nil
function Connection:SetIdentity(identity) end

---@param newControls Controls
---@return nil
function Connection:SetControls(newControls) end

---@param position Vector3
---@return nil
function Connection:SetPosition(position) end

---@param rotation Quaternion
---@return nil
function Connection:SetRotation(rotation) end

---@param connectPending boolean
---@return nil
function Connection:SetConnectPending(connectPending) end

---@param enable boolean
---@return nil
function Connection:SetLogStatistics(enable) end

---@param waitMSec? integer
---@return nil
function Connection:Disconnect(waitMSec) end

---@param package PackageFile
---@return nil
function Connection:SendPackageToClient(package) end

---@param mask integer
---@return nil
function Connection:SetPulseButtonMask(mask) end

---@return integer
function Connection:GetPulseButtonMask() end

---@return VariantMap
function Connection:GetIdentity() end

---@return Scene
function Connection:GetScene() end

---@return Controls
function Connection:GetControls() end

---@return number
function Connection:GetTimeStamp() end

---@return Vector3
function Connection:GetPosition() end

---@return Quaternion
function Connection:GetRotation() end

---@return boolean
function Connection:IsClient() end

---@return boolean
function Connection:IsConnected() end

---@return boolean
function Connection:IsConnectPending() end

---@return boolean
function Connection:IsSceneLoaded() end

---@return boolean
function Connection:GetLogStatistics() end

---@return string
function Connection:GetAddress() end

---@return integer
function Connection:GetPort() end

---@return number
function Connection:GetRoundTripTime() end

---@return number
function Connection:GetLastHeardTime() end

---@return number
function Connection:GetBytesInPerSec() end

---@return number
function Connection:GetBytesOutPerSec() end

---@return number
function Connection:GetPacketsInPerSec() end

---@return number
function Connection:GetPacketsOutPerSec() end

---@return string
function Connection:ToString() end

---@return integer
function Connection:GetNumDownloads() end

---@return string
function Connection:GetDownloadName() end

---@return number
function Connection:GetDownloadProgress() end

