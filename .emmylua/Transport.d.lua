---@meta

--- Auto-generated from Network/Transport

---@alias TransportProtocol
---| integer # TransportProtocol enum values

---@type TransportProtocol
TRANSPORT_SLIKENET = 0
---@type TransportProtocol
TRANSPORT_WEBSOCKET = 1
---@type TransportProtocol
TRANSPORT_KCP = 2

-- Global functions
---@param protocol TransportProtocol
---@return boolean
function TransportIsSupported(protocol) end
