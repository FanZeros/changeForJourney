---@meta

-- =============================================================================
-- NanoVG Types (Manual Definitions)
-- =============================================================================
-- These types are referenced by NanoVG.pkg but defined in the nanovg library.

--- NanoVG context wrapper (manages BGFX integration)
--- Inherits from Object so it can be used with SubscribeToEvent
---@class NVGContextWrapper : Object
NVGContextWrapper = {}

--- Deprecated compat alias, use NVGContextWrapper.
---@alias NVGcontext NVGContextWrapper

--- Get or create the global NanoVG context (lazy singleton, AI-friendly alias for nvgCreate).
---@return NVGContextWrapper
function GetNanoVGContext() end
