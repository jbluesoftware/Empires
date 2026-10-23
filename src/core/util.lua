-- Pure Lua helpers with no dependency on love.*: read-only tables, clamping and geometry tests.

local M = {}

-- Returns a read-only view of a table. Nested dictionary tables are frozen too.
-- Array-like tables (colours, lists) are left untouched because ipairs and the LÖVE C API read them raw.
function M.freeze(source_table)
  for key, value in pairs(source_table) do
    if type(value) == "table" and #value == 0 then
      source_table[key] = M.freeze(value)
    end
  end

  return setmetatable({}, {
    __index = source_table,
    __newindex = function(_, key)
      error("attempt to modify read-only table (key '" .. tostring(key) .. "')", 2)
    end,
    __metatable = false,
  })
end

function M.clamp(value, minimum_value, maximum_value)
  return math.max(minimum_value, math.min(maximum_value, value))
end

function M.is_point_in_rectangle(point_x, point_y, rectangle_x, rectangle_y, rectangle_width, rectangle_height)
  return point_x >= rectangle_x
    and point_x <= rectangle_x + rectangle_width
    and point_y >= rectangle_y
    and point_y <= rectangle_y + rectangle_height
end

return M
