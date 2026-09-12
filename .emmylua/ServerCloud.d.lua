---@meta

--- serverCloud - 服务端云变量 API
--- 子对象风格，AI 友好命名
---
--- 使用方式:
---   serverCloud:Get(uid, key, events)         -- Score 操作（顶层）
---   serverCloud:GetRankList(key, 1, 10, ev)   -- 排行榜（顶层）
---   serverCloud.money:Get(uid, events)         -- 货币操作（子对象）
---   serverCloud.list:Add(uid, key, value)      -- 列表操作（子对象）
---   serverCloud:BatchCommit("desc"):...        -- 事务（顶层）
---
--- 数据类型说明:
---   - scores (回调第一个参数): 通过 Set/BatchSet():Set() 写入的任意类型值
---   - iscores (回调第二个参数): 通过 SetInt/Add/BatchSet():SetInt()/Add() 写入的整数
---   - sscores (回调第三个参数): 已废弃，总是空表

---@class ServerCloudBatchGet 批量读取构建器
local ServerCloudBatchGet = {}

--- 添加查询玩家（多玩家模式）
--- 调用 :Player() 后进入多玩家模式，Fetch 回调变为数组格式
--- 用法: serverCloud:BatchGet():Player(uid1):Player(uid2):Key("k"):Fetch(events)
---@param userId integer 用户 ID
---@return ServerCloudBatchGet
function ServerCloudBatchGet:Player(userId) end

--- 添加要查询的 key
---@param key string 云变量 key
---@return ServerCloudBatchGet
function ServerCloudBatchGet:Key(key) end

--- 执行批量读取
--- 单人模式 (BatchGet(uid)):  ok = function(scores, iscores, sscores)
--- 多人模式 (BatchGet():Player()):  ok = function(results)
---   results[i] = { userId = number, score = {}, iscore = {}, sscore = {} }
---@param events ScoreEvents 回调表
function ServerCloudBatchGet:Fetch(events) end

---@class ServerCloudBatchGetResult 多玩家查询返回项
---@field userId number 用户 ID
---@field score table<string, any> 任意类型云变量
---@field iscore table<string, number> 整数类型云变量
---@field sscore table<string, string> 已废弃，总是空表

---@class ServerCloudRankItem 排行榜条目
---@field userId number 用户 ID（推荐使用）
---@field player number 用户 ID（已废弃，请用 userId）
---@field score table<string, any> 任意类型云变量
---@field iscore table<string, number> 整数类型云变量
---@field sscore table<string, string> 已废弃，总是空表

---@class ServerCloudBatchSet 批量写入构建器
local ServerCloudBatchSet = {}

--- 设置任意类型值
---@param key string 云变量 key
---@param value any 任意类型值
---@return ServerCloudBatchSet
function ServerCloudBatchSet:Set(key, value) end

--- 设置整数值
---@param key string 云变量 key
---@param value integer 整数值
---@return ServerCloudBatchSet
function ServerCloudBatchSet:SetInt(key, value) end

--- 整数增量操作
---@param key string 云变量 key
---@param delta integer 增量
---@return ServerCloudBatchSet
function ServerCloudBatchSet:Add(key, delta) end

--- 删除 key
---@param key string 云变量 key
---@return ServerCloudBatchSet
function ServerCloudBatchSet:Delete(key) end

--- 提交批量写入
---@param description string 操作描述
---@param events? ScoreEvents 回调表
function ServerCloudBatchSet:Save(description, events) end

---@class ServerCloudCommit 事务提交对象
local ServerCloudCommit = {}

--- 提交所有操作
---@param events? ScoreEvents 回调表
function ServerCloudCommit:Commit(events) end

--- 设置任意类型云变量
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param value any 值
---@return ServerCloudCommit
function ServerCloudCommit:ScoreSet(userId, key, value) end

--- 设置整数云变量
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param value integer 整数值
---@return ServerCloudCommit
function ServerCloudCommit:ScoreSetInt(userId, key, value) end

--- 整数增量
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param delta integer 增量
---@return ServerCloudCommit
function ServerCloudCommit:ScoreAddInt(userId, key, delta) end

--- 设置字符串云变量
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param value string 字符串值
---@return ServerCloudCommit
function ServerCloudCommit:ScoreSetStr(userId, key, value) end

--- 删除任意类型云变量
---@param userId integer 用户 ID
---@param key string 云变量 key
---@return ServerCloudCommit
function ServerCloudCommit:ScoreDelete(userId, key) end

--- 删除整数云变量
---@param userId integer 用户 ID
---@param key string 云变量 key
---@return ServerCloudCommit
function ServerCloudCommit:ScoreDeleteInt(userId, key) end

--- 删除字符串云变量
---@param userId integer 用户 ID
---@param key string 云变量 key
---@return ServerCloudCommit
function ServerCloudCommit:ScoreDeleteStr(userId, key) end

--- 增加货币
---@param userId integer 用户 ID
---@param key string 货币 key
---@param amount number 金额
---@return ServerCloudCommit
function ServerCloudCommit:MoneyAdd(userId, key, amount) end

--- 扣除货币
---@param userId integer 用户 ID
---@param key string 货币 key
---@param amount number 金额（必须 > 0）
---@return ServerCloudCommit
function ServerCloudCommit:MoneyCost(userId, key, amount) end

--- 添加列表项
---@param userId integer 用户 ID
---@param key string 列表 key
---@param value any 值
---@return ServerCloudCommit, integer listId
function ServerCloudCommit:ListAdd(userId, key, value) end

--- 修改列表项
---@param listId integer 列表项 ID
---@param value any 新值
---@return ServerCloudCommit
function ServerCloudCommit:ListModify(listId, value) end

--- 修改列表项 key
---@param listId integer 列表项 ID
---@param key string 新 key
---@return ServerCloudCommit
function ServerCloudCommit:ListModifyKey(listId, key) end

--- 删除列表项
---@param listId integer 列表项 ID
---@return ServerCloudCommit
function ServerCloudCommit:ListDelete(listId) end

--- 添加配额计数器（有限次云变量）
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param value integer 增加的值
---@param limit integer 上限
---@param refreshType? string 刷新类型 ("hour"/"day"/"week_monday"/etc.)
---@param refreshCount? integer 刷新周期
---@return ServerCloudCommit
function ServerCloudCommit:QuotaAdd(userId, key, value, limit, refreshType, refreshCount) end

--- 重置配额计数器
---@param userId integer 用户 ID
---@param key string 云变量 key
---@return ServerCloudCommit
function ServerCloudCommit:QuotaReset(userId, key) end

--- 创建命名积分（已废弃）
---@param key string key
---@param name string 名字
---@param value any 值
---@return ServerCloudCommit
function ServerCloudCommit:NameNew(key, name, value) end

--- 删除命名积分（已废弃）
---@param key string key
---@param name string 名字
---@return ServerCloudCommit
function ServerCloudCommit:NameDelete(key, name) end

-- ============================================================================
-- Sub-objects
-- ============================================================================

---@class ServerCloudMoney 货币子对象
local ServerCloudMoney = {}

--- 查询货币余额
--- 回调签名: ok = function(moneys) 其中 moneys = {key = amount, ...}
---@param userId integer 用户 ID
---@param events ScoreEvents 回调表
function ServerCloudMoney:Get(userId, events) end

--- 增加货币
---@param userId integer 用户 ID
---@param key string 货币 key
---@param amount integer 金额
---@param events? ScoreEvents 回调表
function ServerCloudMoney:Add(userId, key, amount, events) end

--- 扣除货币
---@param userId integer 用户 ID
---@param key string 货币 key
---@param amount integer 金额（必须 > 0）
---@param events? ScoreEvents 回调表
function ServerCloudMoney:Cost(userId, key, amount, events) end

---@class ServerCloudList 列表子对象
local ServerCloudList = {}

--- 查询列表
--- 回调签名: ok = function(list) 其中 list = {{user_id, key, value, list_id, time}, ...}
---@param userId integer 用户 ID
---@param key string 列表 key
---@param events ScoreEvents 回调表
function ServerCloudList:Get(userId, key, events) end

--- 通过 list_id 查询列表项
---@param listId integer 列表项 ID
---@param events ScoreEvents 回调表
function ServerCloudList:GetById(listId, events) end

--- 添加列表项
---@param userId integer 用户 ID
---@param key string 列表 key
---@param value any 值
---@param events? ScoreEvents 回调表
---@return integer listId 列表项 ID
function ServerCloudList:Add(userId, key, value, events) end

--- 修改列表项
---@param listId integer 列表项 ID
---@param value any 新值
---@param events? ScoreEvents 回调表
function ServerCloudList:Modify(listId, value, events) end

--- 修改列表项 key
---@param listId integer 列表项 ID
---@param key string 新 key
---@param events? ScoreEvents 回调表
function ServerCloudList:ModifyKey(listId, key, events) end

--- 删除列表项
---@param listId integer 列表项 ID
---@param events? ScoreEvents 回调表
function ServerCloudList:Delete(listId, events) end

---@class ServerCloudItem 道具子对象
local ServerCloudItem = {}

--- 查询道具
---@param userId integer 用户 ID
---@param key? string 道具 key 过滤
---@param events ScoreEvents 回调表
function ServerCloudItem:Get(userId, key, events) end

--- 添加道具
---@param userId integer 用户 ID
---@param key string 道具 key
---@param name string 道具名称
---@param count integer 数量
---@param value any 道具数据
---@param expireType? integer 过期类型
---@param expireTime? string 过期时间
---@param events? ScoreEvents 回调表
---@return integer itemId 道具 ID
function ServerCloudItem:Add(userId, key, name, count, value, expireType, expireTime, events) end

--- 使用道具
---@param userId integer 用户 ID
---@param itemId integer 道具 ID
---@param count? integer 使用数量（默认 1）
---@param events? ScoreEvents 回调表
function ServerCloudItem:Use(userId, itemId, count, events) end

---@class ServerCloudMessageItem 消息查询返回的单条消息
---@field message_id integer 消息 ID
---@field key string 消息类型 key
---@field value any 消息内容
---@field time? string 消息发送时间（由积分服返回）

---@class ServerCloudMessage 消息子对象
local ServerCloudMessage = {}

--- 发送消息
---@param userId integer 发送者 ID
---@param key string 消息类型 key
---@param targetUserId integer 接收者 ID
---@param value any 消息内容
---@param events? ScoreEvents 回调表 { ok = function(errorCode, errorDesc) }
function ServerCloudMessage:Send(userId, key, targetUserId, value, events) end

--- 查询消息
---@param userId integer 用户 ID
---@param key string 消息类型 key
---@param read boolean|false 是否只查已读
---@param events ScoreEvents 回调表 { ok = function(messages: ServerCloudMessageItem[]) }
function ServerCloudMessage:Get(userId, key, read, events) end

--- 标记消息已读
---@param messageId integer 消息 ID
---@param events? ScoreEvents 回调表
function ServerCloudMessage:MarkRead(messageId, events) end

--- 删除消息
---@param messageId integer 消息 ID
---@param events? ScoreEvents 回调表
function ServerCloudMessage:Delete(messageId, events) end

---@class ServerCloudQuota 配额计数器子对象（有限次云变量）
local ServerCloudQuota = {}

--- 查询配额计数器
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param events ScoreEvents 回调表 { ok = function(datas) }
function ServerCloudQuota:Get(userId, key, events) end

--- 增加配额计数
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param value integer 增加的值
---@param limit integer 上限
---@param refreshType? string 刷新类型 ("hour"/"day"/"week_monday"/etc.)
---@param refreshCount? integer 刷新周期
---@param events? ScoreEvents 回调表
function ServerCloudQuota:Add(userId, key, value, limit, refreshType, refreshCount, events) end

--- 重置配额计数器
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param events? ScoreEvents 回调表
function ServerCloudQuota:Reset(userId, key, events) end

-- ============================================================================
-- Main object
-- ============================================================================

---@class ServerCloud 服务端云变量全局对象
---@field mapName string 当前地图名称
---@field money ServerCloudMoney 货币操作
---@field list ServerCloudList 列表操作
---@field item ServerCloudItem 道具操作
---@field message ServerCloudMessage 消息操作
---@field quota ServerCloudQuota 配额计数器操作
local ServerCloud = {}

--- 单个读取
--- 回调签名: ok = function(scores, iscores, sscores)
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param events ScoreEvents 回调表
function ServerCloud:Get(userId, key, events) end

--- 单个写入任意类型值
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param value any 任意类型值
---@param events? ScoreEvents 回调表
function ServerCloud:Set(userId, key, value, events) end

--- 单个写入整数值
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param value integer 整数值
---@param events? ScoreEvents 回调表
function ServerCloud:SetInt(userId, key, value, events) end

--- 单个整数增量
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param delta integer 增量
---@param events? ScoreEvents 回调表
function ServerCloud:Add(userId, key, delta, events) end

--- 单个删除
---@param userId integer 用户 ID
---@param key string 云变量 key
---@param events? ScoreEvents 回调表
function ServerCloud:Delete(userId, key, events) end

--- 批量读取（链式调用）
--- 单人: serverCloud:BatchGet(uid):Key("k1"):Key("k2"):Fetch(events)
---   ok(scores, iscores, sscores)
--- 多人: serverCloud:BatchGet():Player(uid1):Player(uid2):Key("k1"):Fetch(events)
---   ok(results)  -- results[i] = {userId, score, iscore, sscore}
---@param userId? integer 用户 ID（传入则为单人模式，不传则需调用 :Player()）
---@return ServerCloudBatchGet
function ServerCloud:BatchGet(userId) end

--- 批量写入（链式调用）
--- 用法: serverCloud:BatchSet(uid):Set("k",v):SetInt("k",n):Save("desc", events)
---@param userId integer 用户 ID
---@return ServerCloudBatchSet
function ServerCloud:BatchSet(userId) end

--- 创建事务提交对象（可混合多用户、多类型操作）
--- 用法: serverCloud:BatchCommit("desc"):ScoreSet(uid,"k",v):MoneyAdd(uid,"gold",100):Commit(events)
---@param description string 操作描述
---@return ServerCloudCommit
function ServerCloud:BatchCommit(description) end

--- 获取排行榜
--- 回调签名: ok = function(rankList) 其中 rankList = ServerCloudRankItem[]
---@param key string 排序 key
---@param start integer 起始位置（1 开始）
---@param count integer 获取数量
---@param orderAsc boolean true 为升序排列，默认降序
---@param events ScoreEvents 回调表
---@overload fun(self: ServerCloud, key: string, start: integer, count: integer, events: ScoreEvents)
function ServerCloud:GetRankList(key, start, count, orderAsc, events) end

--- 获取用户排名
---@param userId integer 用户 ID
---@param key string 排序 key
---@param events ScoreEvents 回调表 { ok = function(rank, score) }
function ServerCloud:GetUserRank(userId, key, events) end

--- 获取排行榜总人数
---@param key string 排序 key
---@param events ScoreEvents 回调表 { ok = function(total) }
function ServerCloud:GetRankTotal(key, events) end

--- 查询是否为老玩家
---@param userId integer 用户 ID
---@param events ScoreEvents 回调表 { ok = function(isOld: boolean) }
function ServerCloud:IsOldPlayer(userId, events) end

--- 搜索命名积分（已废弃）
---@param key string key
---@param nameSubstr string 名字子串
---@param events? ScoreEvents 回调表
function ServerCloud:NameSearch(key, nameSubstr, events) end

--- 检查名字是否存在（已废弃）
---@param key string key
---@param name string 名字
---@param events? ScoreEvents 回调表
function ServerCloud:NameExist(key, name, events) end

---@type ServerCloud
serverCloud = {}
