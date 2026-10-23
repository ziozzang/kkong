-- Execute the upstream hostname regression cases against the image's Lua modules.
-- This small runner implements only the describe/it/assert methods used by that file.
local lua_assert = assert
local checks = 0
assert = setmetatable({
  is_true = function(v, message) lua_assert(v == true, message) end,
  is_false = function(v, message) lua_assert(v == false, message) end,
}, { __call = function(_, ...) return lua_assert(...) end })
describe = function(_, f) f() end
it = function(name, f)
  local ok, err = pcall(f)
  lua_assert(ok, name .. ': ' .. tostring(err))
  checks = checks + 1
end
dofile('/tests/spec/01-unit/33-tools_hostname_spec.lua')
print('PASS: ' .. checks .. ' upstream hostname validation cases')
