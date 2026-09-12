---@meta

--- Auto-generated from Database/Database

---@alias DBAPI
---| integer # DBAPI enum values

---@type DBAPI
DBAPI_SQLITE = 0
---@type DBAPI
DBAPI_ODBC = 1

---@class Database : Object
---@field pooling boolean
---@field poolSize integer
Database = {}

---@param connectionString string
---@return DbConnection
function Database:Connect(connectionString) end

---@param connection DbConnection
---@return nil
function Database:Disconnect(connection) end

---@return boolean
function Database:IsPooling() end

---@return integer
function Database:GetPoolSize() end

---@param poolSize integer
---@return nil
function Database:SetPoolSize(poolSize) end


-- Global functions
---@return DBAPI
function GetDBAPI() end

---@return Database
function GetDatabase() end

-- Global variables
---@type Database
database = nil
