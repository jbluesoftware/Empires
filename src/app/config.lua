-- Read-only application constants: dev flag, virtual resolution, platform and network settings.
-- Set DEV to false for release builds.

local util = require("core.util")

local operating_system_name = love.system.getOS()

return util.freeze({
  DEV = true,
  LOG_LEVEL = "debug",

  APP_NAME = "Empires",
  APP_VERSION = "0.1.0",
  IS_MOBILE = operating_system_name == "Android" or operating_system_name == "iOS",

  VIRTUAL_WIDTH = 390,
  VIRTUAL_HEIGHT = 844,

  NETWORK = {
    PROTOCOL_VERSION = 1,
    DISCOVERY_PORT = 45454,
    SESSION_PORT = 45455,
    DISCOVERY_INTERVAL_SECONDS = 1,
  },
})
