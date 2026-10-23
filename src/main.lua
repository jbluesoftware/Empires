-- Entry point: enables strict globals in development, boots the application and installs LÖVE callbacks.
-- Launch arguments: `love src host` or `love src client` skips the menu (used by scripts/run-pair.sh).

local config = require("app.config")

if config.DEV then
  require("core.strict").enable()
end

local boot = require("app.boot")
local callbacks = require("core.callbacks")

function love.load(command_line_arguments)
  local context = boot.initialise(command_line_arguments)
  callbacks.install(context)
end
