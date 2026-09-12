---@meta

-- =============================================================================
-- ResourceCache Extensions (Manual Definitions)
-- =============================================================================
-- Manifest query methods: registered via ManifestLuaAPI (C++) onto metatable.
-- Download proxy methods: registered via ResourceCacheExtensions.lua onto metatable.
-- Also available as global functions (deprecated).

--- Resource metadata returned by GetResInfo
---@class ResInfo
---@field uuid string
---@field fsPath string
---@field size integer
---@field source string
---@field ext string
---@field alias? string

-- =============================================================================
-- Manifest Query (C++ ManifestLuaAPI)
-- =============================================================================

--- Get recursive refs for a resource URI or array of URIs (merged, deduplicated)
---@param uri string Resource URI (uuid://, alias://, fs_path)
---@param includeSelf? boolean Include the input URI(s) themselves (default false)
---@return string[] refs Array of uuid:// refs
---@overload fun(self: ResourceCache, uris: string[], includeSelf?: boolean): string[]
function ResourceCache:GetResRefs(uri, includeSelf) end

--- Get resource metadata
---@param uri string Resource URI
---@return ResInfo|nil info Resource info table, or nil if not found
function ResourceCache:GetResInfo(uri) end

--- Get fs_path (virtual path) for a resource URI
---@param uri string Resource URI
---@return string fsPath
function ResourceCache:GetResVirtualPath(uri) end

--- Get raw UUID for a resource
---@param uri string Resource URI (fs_path, alias://, uuid://)
---@return string uuid Raw UUID string (e.g. "B_J0gVyL...")
function ResourceCache:GetResUuid(uri) end

--- Get uuid:// path for a resource
---@param uri string Resource URI (fs_path, alias://, uuid://)
---@return string uuidPath Full UUID path (e.g. "uuid://B_J0gVyL...")
function ResourceCache:GetResUuidPath(uri) end

-- =============================================================================
-- Download Proxy (Lua ResourceCacheExtensions.lua → DownloadManager)
-- =============================================================================

--- Download a single resource
---@param uri string Resource URI (uuid://, alias://, fs_path)
---@param onComplete? fun(success: boolean, errorMessage: string) Completion callback
function ResourceCache:DownloadResource(uri, onComplete) end

--- Download multiple resources
---@param uris string[] Array of resource URIs
---@param onComplete? fun(success: boolean, failedCount: integer) Completion callback
---@param onProgress? fun(completed: integer, total: integer, downloadedBytes: number, totalBytes: number) Progress callback
---@return integer groupId Download group ID
function ResourceCache:DownloadResources(uris, onComplete, onProgress) end

--- Cancel a resource download
---@param uri string Resource URI
---@return boolean cancelled
function ResourceCache:CancelDownload(uri) end

--- Cancel a download group (returned by DownloadResources)
---@param groupId integer Group ID from DownloadResources
function ResourceCache:CancelDownloadGroup(groupId) end

--- Get download state of a resource
---@param uri string Resource URI
---@return DownloadTaskState state
function ResourceCache:GetDownloadState(uri) end

-- =============================================================================
-- Async Loading (Lua ResourceCacheExtensions.lua)
-- =============================================================================

--- Async load a resource (download if needed, clear null-cache, then load).
--- callback(resource) is called with the loaded resource or nil.
---@param typeName string Resource type name (e.g. "JSONFile", "XMLFile", "BinaryFile")
---@param uri string Resource URI (uuid://, alias://, fs_path)
---@param callback fun(resource: Resource|nil) Completion callback
function ResourceCache:GetResourceAsync(typeName, uri, callback) end

-- =============================================================================
-- Download Observer (Lua ResourceCacheExtensions.lua)
-- =============================================================================

--- Start observing background download activity.
--- Monitors activeCount changes and accumulates downloaded bytes.
--- With onComplete: auto-ends when activeCount reaches 0.
--- Without onComplete: persists until StopObservingDownloads is called.
---@param onProgress fun(completedCount: integer, totalCount: integer, completedBytes: number) Progress callback
---@param onComplete? fun(completedBytes: number) Called when activeCount reaches 0 (enables auto-end)
---@return integer observerId Use with StopObservingDownloads to cancel
function ResourceCache:ObserveDownloads(onProgress, onComplete) end

--- Stop observing downloads early (before activeCount reaches 0).
---@param observerId integer ID returned by ObserveDownloads
function ResourceCache:StopObservingDownloads(observerId) end
