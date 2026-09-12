---@meta

--- Auto-generated from Resource/DownloadManager

---@alias DownloadTaskState
---| integer # DownloadTaskState enum values

---@type DownloadTaskState
DOWNLOAD_PENDING = 0
---@type DownloadTaskState
DOWNLOAD_DOWNLOADING = 1
---@type DownloadTaskState
DOWNLOAD_COMPLETED = 2
---@type DownloadTaskState
DOWNLOAD_FAILED = 3
---@type DownloadTaskState
DOWNLOAD_CANCELLED = 4

---@alias DownloadPriority
---| integer # DownloadPriority enum values

---@type DownloadPriority
DOWNLOAD_PRIORITY_LOW = 0
---@type DownloadPriority
DOWNLOAD_PRIORITY_NORMAL = 50
---@type DownloadPriority
DOWNLOAD_PRIORITY_HIGH = 100
---@type DownloadPriority
DOWNLOAD_PRIORITY_CRITICAL = 200

---@class DownloadTask : RefCounted
DownloadTask = {}

--- Check if download succeeded
---@return boolean
function DownloadTask:IsSuccess() end

--- Check if download failed
---@return boolean
function DownloadTask:IsFailed() end


---@class DownloadManager : Object
---@field concurrency integer
---@field maxRetry integer
---@field timeout integer
---@field defaultDirectory string
---@field compressionEnabled boolean
---@field activeCount integer
---@field pendingCount integer
DownloadManager = {}

--- Set maximum concurrent downloads (default: 5)
---@param count integer
---@return nil
function DownloadManager:SetConcurrency(count) end

--- Get maximum concurrent downloads
---@return integer
function DownloadManager:GetConcurrency() end

--- Set maximum retry count for failed downloads (default: 3)
---@param count integer
---@return nil
function DownloadManager:SetMaxRetry(count) end

--- Get maximum retry count
---@return integer
function DownloadManager:GetMaxRetry() end

--- Set download timeout in milliseconds (default: 30000)
---@param ms integer
---@return nil
function DownloadManager:SetTimeout(ms) end

--- Get download timeout in milliseconds
---@return integer
function DownloadManager:GetTimeout() end

--- Get default download directory
---@return string
function DownloadManager:GetDefaultDirectory() end

--- Enable/disable HTTP compression (gzip/deflate)
--- When enabled, server compresses response data, reducing transfer by 60-90%
--- Default: enabled. Streaming mode does inflate-on-the-fly.
---@param enabled boolean
---@return nil
function DownloadManager:SetCompressionEnabled(enabled) end

--- Check if HTTP compression is enabled
---@return boolean
function DownloadManager:GetCompressionEnabled() end

--- Set streaming download size threshold in bytes (default: 10MB)
--- Resources larger than this are streamed to disk instead of buffered in memory
---@param bytes integer
---@return nil
function DownloadManager:SetStreamThreshold(bytes) end

--- Get streaming download size threshold
---@return integer
function DownloadManager:GetStreamThreshold() end

--- Check if any resolver can handle the resource path
---@param resourcePath string Resource path (uuid://{uuid} or virtualPath)
---@return boolean # true if resolvable
function DownloadManager:CanResolve(resourcePath) end

--- Download a single resource (via resolver)
---@param resourcePath string Resource path (uuid://{uuid} or virtualPath)
---@return nil
function DownloadManager:DownloadResource(resourcePath) end

--- Download multiple resources (via resolver)
---@param resourcePaths StringVector Resource path list
---@return integer # groupId
function DownloadManager:DownloadResources(resourcePaths) end

--- Cancel a resource download task (via resolver)
---@param resourcePath string Resource path (uuid://{uuid} or virtualPath)
---@return boolean # true if cancelled
function DownloadManager:CancelResourceTask(resourcePath) end

--- Cancel a download group by groupId
---@param groupId integer
---@return nil
function DownloadManager:CancelGroup(groupId) end

--- Cancel all downloads
---@return nil
function DownloadManager:CancelAll() end

--- Get resource download state (via resolver)
---@param resourcePath string Resource path (uuid://{uuid} or virtualPath)
---@return DownloadTaskState # download state
function DownloadManager:GetResourceTaskState(resourcePath) end

--- Get number of active downloads
---@return integer
function DownloadManager:GetActiveCount() end

--- Get number of pending downloads
---@return integer
function DownloadManager:GetPendingCount() end

--- Set global download observer callback: function(activeCount, completedTaskBytes)
--- Fires when activeCount changes (task start or complete)
---@return nil
function DownloadManager:SetDownloadObserver() end

--- Clear global download observer
---@return nil
function DownloadManager:ClearDownloadObserver() end


-- Global functions
--- Get the DownloadManager subsystem
---@return DownloadManager
function GetDownloadManager() end
