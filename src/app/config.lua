-- Read-only application constants: dev flag, virtual resolution, platform and network tuning.
-- Set DEV to false for release builds.

local util = require("core.util")

local operating_system_name = love.system.getOS()

return util.freeze({
  DEV = true,
  LOG_LEVEL = "debug",

  APP_NAME = "LAN App",
  APP_VERSION = "0.1.0",
  IS_MOBILE = operating_system_name == "Android" or operating_system_name == "iOS",

  VIRTUAL_WIDTH = 390,
  VIRTUAL_HEIGHT = 844,

  NETWORK = {
    SESSION_PORT = 45455,
    SESSION_PORT_COUNT = 4, -- consecutive ports tried, so several instances can share one machine
    MAX_PEERS = 32, -- a SNAPSHOT with 32 members is ~1.2 KB, safely inside one datagram

    HEARTBEAT_INTERVAL_SECONDS = 1,
    ANNOUNCE_INTERVAL_SECONDS = 2,
    HOST_TIMEOUT_SECONDS = 4,
    MEMBER_TIMEOUT_SECONDS = 4,
    SUCCESSION_STEP_SECONDS = 2,

    SEARCH_DURATION_SECONDS = 1.5,
    SEARCH_JITTER_SECONDS = 0.5, -- random extra wait that makes simultaneous hosting unlikely
    SEARCH_PROBE_INTERVAL_SECONDS = 0.5,
    SEARCH_SWEEP_ADDRESSES_PER_SECOND = 254, -- one pass over the local /24 per second
    HOST_SWEEP_ADDRESSES_PER_SECOND = 8, -- slow background pass so hosts still find each other if broadcast is blocked

    JOIN_TIMEOUT_SECONDS = 2,
    JOIN_MAX_ATTEMPTS = 3,
    NETWORK_CHECK_INTERVAL_SECONDS = 3,
  },
})
