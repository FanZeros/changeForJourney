--- @meta

-- Fix "type lua_Function not found" errors in Spine callback registrations
---@alias lua_Function function

--- Override nvgTextBounds: ending and bounds are optional in the Lua binding
---@overload fun(vg: any, x: number, y: number, str: string): number
---@overload fun(vg: any, x: number, y: number, str: string, ending: string|nil): number
---@overload fun(vg: any, x: number, y: number, str: string, ending: string|nil, bounds: number[]): number
---@param vg any NanoVG context
---@param x number X coordinate
---@param y number Y coordinate
---@param string string Text to measure
---@param ending? string|nil Optional end pointer
---@param bounds? number[] Float array [4] for bounds
---@return number width
function nvgTextBounds(vg, x, y, string, ending, bounds) end
