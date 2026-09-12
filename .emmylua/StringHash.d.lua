---@meta

--- Auto-generated from Math/StringHash

---@class StringHash
---@overload fun(rhs: StringHash|string): StringHash
---@overload fun(str: string): StringHash
---@overload fun(): StringHash
---@field ZERO StringHash|string
---@field value integer
---@operator add(StringHash|string): StringHash|string
---@operator eq(StringHash|string): boolean
---@operator lt(StringHash|string): boolean
StringHash = {}

---@overload fun(self: StringHash, rhs: StringHash|string): StringHash
---@overload fun(rhs: StringHash|string): StringHash
---@overload fun(self: StringHash, str: string): StringHash
---@overload fun(str: string): StringHash
---@return StringHash
function StringHash.new() end

---@return integer
function StringHash:Value() end

---@return string
function StringHash:ToString() end

---@return integer
function StringHash:ToHash() end

---@param str string
---@param hash? integer
---@return integer
function StringHash:Calculate(str, hash) end

