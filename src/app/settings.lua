-- Persisted user settings: a flat table of strings, numbers and booleans stored as a Lua table
-- in the LÖVE save directory. Unknown keys and mismatched types are discarded on load.

local log = require("core.log").new("settings")

local M = {}

local SETTINGS_FILE_NAME = "settings.lua"
local SETTINGS_FORMAT_VERSION = 1

local DEFAULT_SETTINGS = {
  version = SETTINGS_FORMAT_VERSION,
  player_name = "Player",
}

local current_settings = {}

local function copy_defaults()
  local copied_settings = {}
  for key, default_value in pairs(DEFAULT_SETTINGS) do
    copied_settings[key] = default_value
  end
  return copied_settings
end

function M.load()
  current_settings = copy_defaults()

  if not love.filesystem.getInfo(SETTINGS_FILE_NAME) then
    return M
  end

  local settings_chunk, load_error_message = love.filesystem.load(SETTINGS_FILE_NAME)
  if not settings_chunk then
    log.warn("could not read settings: %s", tostring(load_error_message))
    return M
  end

  setfenv(settings_chunk, {})
  local was_executed, stored_settings = pcall(settings_chunk)
  if not was_executed or type(stored_settings) ~= "table" or stored_settings.version ~= SETTINGS_FORMAT_VERSION then
    log.warn("settings file ignored (corrupt or unsupported version)")
    return M
  end

  for key, default_value in pairs(DEFAULT_SETTINGS) do
    if type(stored_settings[key]) == type(default_value) then
      current_settings[key] = stored_settings[key]
    end
  end
  return M
end

function M.save()
  local serialized_lines = { "return {" }
  for key, value in pairs(current_settings) do
    if type(value) == "string" then
      serialized_lines[#serialized_lines + 1] = string.format("  %s = %q,", key, value)
    else
      serialized_lines[#serialized_lines + 1] = string.format("  %s = %s,", key, tostring(value))
    end
  end
  serialized_lines[#serialized_lines + 1] = "}"

  local was_written, write_error_message = love.filesystem.write(SETTINGS_FILE_NAME, table.concat(serialized_lines, "\n"))
  if not was_written then
    log.error("could not save settings: %s", tostring(write_error_message))
  end
  return was_written
end

function M.get(key)
  return current_settings[key]
end

function M.set(key, value)
  assert(DEFAULT_SETTINGS[key] ~= nil, "unknown setting: " .. tostring(key))
  assert(type(value) == type(DEFAULT_SETTINGS[key]), "wrong type for setting: " .. tostring(key))
  current_settings[key] = value
end

return M
