---@meta

--- Auto-generated from Database/DbConnection

---@class DbConnection : Object
---@field connectionString string
---@field connected boolean
DbConnection = {}

---@return nil
function DbConnection:Finalize() end

---@param sql string
---@param useCursorEvent? boolean
---@return DbResult
function DbConnection:Execute(sql, useCursorEvent) end

---@return string
function DbConnection:GetConnectionString() end

---@return boolean
function DbConnection:IsConnected() end

