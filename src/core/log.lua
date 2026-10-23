-- Leveled, tagged logging. Output goes to stdout (terminal on desktop, adb logcat on Android).
-- Usage: local log = require("core.log").new("host"); log.info("listening on port %d", port)

local M = {}

local LEVEL_VALUES_BY_NAME = { debug = 1, info = 2, warn = 3, error = 4 }

local minimum_level_value = LEVEL_VALUES_BY_NAME.info

function M.set_minimum_level(level_name)
  minimum_level_value = LEVEL_VALUES_BY_NAME[level_name] or error("unknown log level: " .. tostring(level_name), 2)
end

function M.new(tag)
  local logger = {}

  for level_name, level_value in pairs(LEVEL_VALUES_BY_NAME) do
    logger[level_name] = function(message_format, ...)
      if level_value < minimum_level_value then
        return
      end
      local message = select("#", ...) > 0 and string.format(message_format, ...) or tostring(message_format)
      print(string.format("[%s][%s] %s", level_name:upper(), tag, message))
    end
  end

  return logger
end

return M
