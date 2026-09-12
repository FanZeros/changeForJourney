---@meta

--- Auto-generated from Network/Network

---@class Network
---@field updateFps integer
---@field simulatedLatency integer
---@field simulatedPacketLoss number
---@field clientConnectionTimeout integer
---@field serverConnectionTimeout integer
---@field pausedTimeout integer
---@field serverConnection Connection
---@field serverRunning boolean
---@field packageCacheDir string
Network = {}

---@param address string
---@param port integer -- unsigned short
---@param scene? Scene
---@param identity? VariantMap
---@return boolean
function Network:Connect(address, port, scene, identity) end

---@param address string
---@param port integer -- unsigned short
---@param scene Scene
---@param protocol TransportProtocol
---@param identity? VariantMap
---@return boolean
function Network:ConnectWithTransport(address, port, scene, protocol, identity) end

---@param waitMSec? integer
---@return nil
function Network:Disconnect(waitMSec) end

---@param port integer -- unsigned short
---@return boolean
function Network:StartServer(port) end

---@param port integer -- unsigned short
---@param protocol TransportProtocol
---@return boolean
function Network:StartServerWithTransport(port, protocol) end

---@param port integer -- unsigned short
---@param protocol TransportProtocol
---@return boolean
function Network:AddServerTransport(port, protocol) end

---@param protocol TransportProtocol
---@return boolean
function Network:StopServerTransport(protocol) end

---@return nil
function Network:StopServer() end

---@return TransportProtocol
function Network:GetTransportProtocol() end

---@return integer[]
function Network:GetServerTransportProtocols() end

---@param protocol TransportProtocol
---@return boolean
function Network:IsServerTransportRunning(protocol) end

---@param protocol TransportProtocol
---@return nil
function Network:SetPreferredTransport(protocol) end

---@param msgID integer
---@param reliable boolean
---@param inOrder boolean
---@param msg VectorBuffer
---@param contentID? integer
---@return nil
function Network:BroadcastMessage(msgID, reliable, inOrder, msg, contentID) end

---@param eventType StringHash|string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Network:BroadcastRemoteEvent(eventType, inOrder, eventData) end

---@param eventType string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Network:BroadcastRemoteEvent(eventType, inOrder, eventData) end

---@param scene Scene
---@param eventType StringHash|string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Network:BroadcastRemoteEvent(scene, eventType, inOrder, eventData) end

---@param scene Scene
---@param eventType string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Network:BroadcastRemoteEvent(scene, eventType, inOrder, eventData) end

---@param node Node
---@param eventType StringHash|string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Network:BroadcastRemoteEvent(node, eventType, inOrder, eventData) end

---@param node Node
---@param eventType string
---@param inOrder boolean
---@param eventData? VariantMap
---@return nil
function Network:BroadcastRemoteEvent(node, eventType, inOrder, eventData) end

---@param fps integer
---@return nil
function Network:SetUpdateFps(fps) end

---@param ms integer
---@return nil
function Network:SetSimulatedLatency(ms) end

---@param loss number
---@return nil
function Network:SetSimulatedPacketLoss(loss) end

---@param timeoutMs integer
---@return nil
function Network:SetClientConnectionTimeout(timeoutMs) end

---@return integer
function Network:GetClientConnectionTimeout() end

---@param timeoutMs integer
---@return nil
function Network:SetServerConnectionTimeout(timeoutMs) end

---@return integer
function Network:GetServerConnectionTimeout() end

---@param timeoutMs integer
---@return nil
function Network:SetPausedTimeout(timeoutMs) end

---@return integer
function Network:GetPausedTimeout() end

---@param eventType StringHash|string
---@return nil
function Network:RegisterRemoteEvent(eventType) end

---@param eventType string
---@return nil
function Network:RegisterRemoteEvent(eventType) end

---@param eventType StringHash|string
---@return nil
function Network:UnregisterRemoteEvent(eventType) end

---@param eventType string
---@return nil
function Network:UnregisterRemoteEvent(eventType) end

---@return nil
function Network:UnregisterAllRemoteEvents() end

---@param path string
---@return nil
function Network:SetPackageCacheDir(path) end

---@param scene Scene
---@param package PackageFile
---@return nil
function Network:SendPackageToClients(scene, package) end

---@param url string
---@param verb? string
---@param headers? string[]
---@return HttpRequest
function Network:MakeHttpRequest(url, verb, headers) end

---@return integer
function Network:GetUpdateFps() end

---@return integer
function Network:GetSimulatedLatency() end

---@return number
function Network:GetSimulatedPacketLoss() end

---@return Connection
function Network:GetServerConnection() end

---@return boolean
function Network:IsReconnectSession() end

---@return string
function Network:GetSessionId() end

---@return boolean
function Network:IsServerRunning() end

---@param eventType StringHash|string
---@return boolean
function Network:CheckRemoteEvent(eventType) end

---@return string
function Network:GetPackageCacheDir() end

---@return Connection[]
function Network:GetClientConnections() end

---@param password string
---@return nil
function Network:SetPassword(password) end

---@return nil
function Network:StartNATClient() end

---@return string
function Network:GetGUID() end

---@param port integer
---@return nil
function Network:DiscoverHosts(port) end

---@param data VariantMap
---@return nil
function Network:SetDiscoveryBeacon(data) end

---@param address string
---@param port integer -- unsigned short
---@return nil
function Network:SetNATServerInfo(address, port) end

---@param guid string
---@param scene? Scene
---@param identity? VariantMap
---@return nil
function Network:AttemptNATPunchtrough(guid, scene, identity) end


-- Global functions
---@return Network
function GetNetwork() end

-- Global variables
---@type boolean
NETWORK_AUTO_SEND_IDENTITY = nil
---@type Network
network = nil
