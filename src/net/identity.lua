-- Per-launch identity: a uniquely seeded random source and a short random peer id.
-- LÖVE seeds its default generator with whole seconds, so two instances started together would collide;
-- this seeds from microsecond time plus a memory address instead.

local socket = require("socket")

local M = {}

local SEED_MODULUS = 4294967296
local HALF_PEER_ID_MAXIMUM = 65535

-- Returns a function that yields floats in [0, 1).
function M.create_random_source()
  local microsecond_time_seed = math.floor(socket.gettime() * 1000000) % SEED_MODULUS
  local memory_address_text = string.match(tostring({}), "0x(%x+)")
  local memory_address_seed = (memory_address_text and tonumber(memory_address_text, 16) or 0) % SEED_MODULUS

  local generator = love.math.newRandomGenerator(microsecond_time_seed, memory_address_seed)
  return function()
    return generator:random()
  end
end

-- Returns an 8 character hex string.
function M.generate_peer_id(random_source)
  local first_half = math.floor(random_source() * (HALF_PEER_ID_MAXIMUM + 1))
  local second_half = math.floor(random_source() * (HALF_PEER_ID_MAXIMUM + 1))
  return string.format("%04x%04x", first_half, second_half)
end

return M
