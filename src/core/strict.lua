-- Development guard: raises an error when code reads or writes an undeclared global variable.
-- Globals assigned at the top level of a file (main chunk) count as declared.

local M = {}

function M.enable(allowed_global_names)
  local declared_global_names = {}
  for _, global_name in ipairs(allowed_global_names or {}) do
    declared_global_names[global_name] = true
  end

  local globals_metatable = getmetatable(_G) or {}
  setmetatable(_G, globals_metatable)

  -- Level 3 is the code that triggered the metamethod (1 = this helper, 2 = the metamethod).
  local function is_declaring_context()
    local caller_kind = debug.getinfo(3, "S").what
    return caller_kind == "main" or caller_kind == "C"
  end

  globals_metatable.__newindex = function(globals_table, global_name, assigned_value)
    if not declared_global_names[global_name] and not is_declaring_context() then
      error("assignment to undeclared global '" .. tostring(global_name) .. "'", 2)
    end
    declared_global_names[global_name] = true
    rawset(globals_table, global_name, assigned_value)
  end

  globals_metatable.__index = function(_, global_name)
    if not declared_global_names[global_name] and not is_declaring_context() then
      error("read of undeclared global '" .. tostring(global_name) .. "'", 2)
    end
    return nil
  end
end

return M
