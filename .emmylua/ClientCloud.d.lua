---@meta

--- clientCloud - 客户端云变量 API
--- 面向对象风格，AI 友好命名
---
--- 数据类型说明:
---   - values (回调第一个参数): 通过 Set/BatchSet():Set() 写入的任意类型值
---   - iscores (回调第二个参数): 通过 SetInt/Add/BatchSet():SetInt()/Add() 写入的整数
---   - 注意: sscores 参数已废弃，不再使用

---@class ClientCloudRankItem GetRankList 返回的排行榜项
---@field userId number 用户 ID（推荐使用）
---@field player number 用户 ID（已废弃，请用 userId）
---@field iscore table<string, number> 整数类型云变量（通过 SetInt/Add 写入）
---@field score table<string, any> 任意类型云变量（通过 Set 写入）
---@field sscore table<string, string> 已废弃，总是空表

---@class ClientCloudBatchGet 批量读取构建器
local ClientCloudBatchGet = {}

---@param key string 云变量 key
---@return ClientCloudBatchGet
function ClientCloudBatchGet:Key(key) end

--- 执行批量读取
---@param events ScoreEvents 回调表 { ok = function(values, iscores), error = function(code, reason) }
function ClientCloudBatchGet:Fetch(events) end

---@class ClientCloudBatchSet 批量写入构建器
local ClientCloudBatchSet = {}

--- 设置任意类型值 (写入到 values 表)
---@param key string 云变量 key
---@param value any 任意类型值
---@return ClientCloudBatchSet
function ClientCloudBatchSet:Set(key, value) end

--- 设置整数值 (写入到 iscores 表，可参与排行榜排序)
---@param key string 云变量 key
---@param value integer 整数值
---@return ClientCloudBatchSet
function ClientCloudBatchSet:SetInt(key, value) end

--- 整数增量操作 (写入到 iscores 表)
---@param key string 云变量 key
---@param delta integer 增量（可为负数）
---@return ClientCloudBatchSet
function ClientCloudBatchSet:Add(key, delta) end

---@param key string 云变量 key
---@return ClientCloudBatchSet
function ClientCloudBatchSet:Delete(key) end

---@param description string 操作描述
---@param events? ScoreEvents 回调表
function ClientCloudBatchSet:Save(description, events) end

---@class ClientCloud 客户端云变量全局对象
---@field userId number 当前用户 ID
---@field mapName string 当前地图名称
local ClientCloud = {}

--- 单个读取
--- 回调签名: ok = function(values, iscores)
---   - values: 通过 Set 写入的任意类型值
---   - iscores: 通过 SetInt/Add 写入的整数值
---@param key string 云变量 key
---@param events ScoreEvents 回调表 { ok = function(values, iscores) }
function ClientCloud:Get(key, events) end

--- 单个写入任意类型值 (写入到 values 表)
--- 支持 string, number, boolean, table 等任意 Lua 类型
---@param key string 云变量 key
---@param value any 任意类型值
---@param events? ScoreEvents 回调表
function ClientCloud:Set(key, value, events) end

--- 单个写入整数值 (写入到 iscores 表，可参与排行榜排序)
---@param key string 云变量 key
---@param value integer 整数值
---@param events? ScoreEvents 回调表
function ClientCloud:SetInt(key, value, events) end

--- 单个整数增量操作 (写入到 iscores 表)
---@param key string 云变量 key
---@param delta integer 增量（可为负数）
---@param events? ScoreEvents 回调表
function ClientCloud:Add(key, delta, events) end

--- 批量读取（链式调用）
---@return ClientCloudBatchGet
function ClientCloud:BatchGet() end

--- 批量写入（链式调用）
---@return ClientCloudBatchSet
function ClientCloud:BatchSet() end

--- 获取排行榜
--- 可选 orderAsc 参数控制排序方向（默认降序），events 之后可传入额外 key 名称
---@param key string 排序 key (必须是 iscores 中的 key)
---@param start number 起始位置（0 开始）
---@param count number 获取数量
---@param orderAsc boolean true 为升序排列，默认降序
---@param events ScoreEvents 回调表 { ok = function(rankList: ClientCloudRankItem[]) }
---@param ... string 可选的附加字段名
---@overload fun(self: ClientCloud, key: string, start: number, count: number, events: ScoreEvents, ...: string)
function ClientCloud:GetRankList(key, start, count, orderAsc, events, ...) end

--- 获取用户排名
---@param userId number 用户 ID
---@param key string 排序 key (必须是 iscores 中的 key)
---@param events ScoreEvents 回调表 { ok = function(rank: number|nil, scoreValue: number) }
function ClientCloud:GetUserRank(userId, key, events) end

--- 获取排行榜总人数
---@param key string 排序 key (必须是 iscores 中的 key)
---@param events ScoreEvents 回调表 { ok = function(total: number) }
function ClientCloud:GetRankTotal(key, events) end

---@type ClientCloud
clientCloud = {}

--- @deprecated 为兼容老项目保留，推荐使用 clientCloud
---@type ClientCloud
clientScore = {}
