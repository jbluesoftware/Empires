-- Wire protocol: message types, compact text encoding and strict decoding. Pure Lua, no love.* dependency.
-- Packet layout: LANAPP|version|TYPE|sender_peer_id|session_id|epoch|payload fields...
-- A SNAPSHOT roster is comma separated entries of peer_id/ip/port/lights, where lights is three 0/1 digits (RGB).

local M = {}

M.PROTOCOL_VERSION = 1

M.MESSAGE_TYPES = {
  HELLO = "HELLO", -- "is anyone hosting?" (broadcast and subnet sweep)
  ANNOUNCE = "ANNOUNCE", -- host advertises its session
  JOIN = "JOIN", -- peer asks a host to add it to the roster
  SNAPSHOT = "SNAPSHOT", -- host sends the full ordered roster; doubles as heartbeat
  STATE = "STATE", -- peer reports its own lights; doubles as heartbeat
  LEAVE = "LEAVE", -- peer says goodbye
  CLOSE = "CLOSE", -- host is shutting down; members start succession immediately
  REDIRECT = "REDIRECT", -- stepping-down host tells members which host to join instead
}

local PACKET_MAGIC = "LANAPP"
local NO_SESSION = "-"
local FIELD_SEPARATOR = "|"
local ENTRY_SEPARATOR = ","
local ENTRY_FIELD_SEPARATOR = "/"
local MAXIMUM_ROSTER_ENTRIES = 64
local IPV4_PATTERN = "^%d+%.%d+%.%d+%.%d+$"

local FIRST_PAYLOAD_FIELD_INDEX = 7

local function split_plain(text, separator)
  local parts = {}
  local search_start = 1
  while true do
    local separator_start = string.find(text, separator, search_start, true)
    if not separator_start then
      parts[#parts + 1] = string.sub(text, search_start)
      return parts
    end
    parts[#parts + 1] = string.sub(text, search_start, separator_start - 1)
    search_start = separator_start + #separator
  end
end

local function encode_lights(lights)
  return (lights.red and "1" or "0") .. (lights.green and "1" or "0") .. (lights.blue and "1" or "0")
end

local function decode_lights(text)
  if type(text) ~= "string" or not string.match(text, "^[01][01][01]$") then
    return nil
  end
  return {
    red = string.sub(text, 1, 1) == "1",
    green = string.sub(text, 2, 2) == "1",
    blue = string.sub(text, 3, 3) == "1",
  }
end

local function encode_roster(roster)
  local encoded_entries = {}
  for entry_index, member in ipairs(roster) do
    encoded_entries[entry_index] = table.concat({
      member.peer_id,
      member.ip,
      member.port,
      encode_lights(member.lights),
    }, ENTRY_FIELD_SEPARATOR)
  end
  return table.concat(encoded_entries, ENTRY_SEPARATOR)
end

local function decode_roster(text)
  local roster = {}
  if text == nil or text == "" then
    return roster
  end

  for _, entry_text in ipairs(split_plain(text, ENTRY_SEPARATOR)) do
    local entry_fields = split_plain(entry_text, ENTRY_FIELD_SEPARATOR)
    local port_number = tonumber(entry_fields[3])
    local lights = decode_lights(entry_fields[4])
    local is_valid_entry = #entry_fields == 4
      and entry_fields[1] ~= ""
      and string.match(entry_fields[2], IPV4_PATTERN) ~= nil
      and port_number ~= nil
      and lights ~= nil
    if not is_valid_entry or #roster >= MAXIMUM_ROSTER_ENTRIES then
      return nil
    end
    roster[#roster + 1] = { peer_id = entry_fields[1], ip = entry_fields[2], port = port_number, lights = lights }
  end
  return roster
end

local function write_nothing() end

local function read_nothing()
  return true
end

local PAYLOAD_CODECS = {
  [M.MESSAGE_TYPES.HELLO] = { write = write_nothing, read = read_nothing },
  [M.MESSAGE_TYPES.LEAVE] = { write = write_nothing, read = read_nothing },
  [M.MESSAGE_TYPES.CLOSE] = { write = write_nothing, read = read_nothing },

  [M.MESSAGE_TYPES.ANNOUNCE] = {
    write = function(message, fields)
      fields[#fields + 1] = message.member_count
    end,
    read = function(fields, message)
      message.member_count = tonumber(fields[FIRST_PAYLOAD_FIELD_INDEX])
      return message.member_count ~= nil and message.member_count >= 1
    end,
  },

  [M.MESSAGE_TYPES.JOIN] = {
    write = function(message, fields)
      fields[#fields + 1] = encode_lights(message.lights)
    end,
    read = function(fields, message)
      message.lights = decode_lights(fields[FIRST_PAYLOAD_FIELD_INDEX])
      return message.lights ~= nil
    end,
  },

  [M.MESSAGE_TYPES.STATE] = {
    write = function(message, fields)
      fields[#fields + 1] = encode_lights(message.lights)
    end,
    read = function(fields, message)
      message.lights = decode_lights(fields[FIRST_PAYLOAD_FIELD_INDEX])
      return message.lights ~= nil
    end,
  },

  [M.MESSAGE_TYPES.SNAPSHOT] = {
    write = function(message, fields)
      fields[#fields + 1] = message.version
      fields[#fields + 1] = encode_roster(message.roster)
    end,
    read = function(fields, message)
      message.version = tonumber(fields[FIRST_PAYLOAD_FIELD_INDEX])
      message.roster = decode_roster(fields[FIRST_PAYLOAD_FIELD_INDEX + 1])
      return message.version ~= nil and message.roster ~= nil
    end,
  },

  [M.MESSAGE_TYPES.REDIRECT] = {
    write = function(message, fields)
      fields[#fields + 1] = message.target_ip
      fields[#fields + 1] = message.target_port
    end,
    read = function(fields, message)
      message.target_ip = fields[FIRST_PAYLOAD_FIELD_INDEX]
      message.target_port = tonumber(fields[FIRST_PAYLOAD_FIELD_INDEX + 1])
      return message.target_ip ~= nil
        and string.match(message.target_ip, IPV4_PATTERN) ~= nil
        and message.target_port ~= nil
    end,
  },
}

-- message: { type, sender_peer_id, session_id (optional), epoch (optional), ...payload fields }
function M.encode(message)
  local codec = PAYLOAD_CODECS[message.type]
  assert(codec, "unknown message type: " .. tostring(message.type))

  local fields = {
    PACKET_MAGIC,
    M.PROTOCOL_VERSION,
    message.type,
    message.sender_peer_id,
    message.session_id or NO_SESSION,
    message.epoch or 0,
  }
  codec.write(message, fields)
  return table.concat(fields, FIELD_SEPARATOR)
end

-- Returns a message table, or nil if the packet is malformed, foreign or from another protocol version.
function M.decode(packet_text)
  if type(packet_text) ~= "string" then
    return nil
  end

  local fields = split_plain(packet_text, FIELD_SEPARATOR)
  if fields[1] ~= PACKET_MAGIC or tonumber(fields[2]) ~= M.PROTOCOL_VERSION then
    return nil
  end

  local codec = PAYLOAD_CODECS[fields[3]]
  local sender_peer_id = fields[4]
  local epoch = tonumber(fields[6])
  if not codec or not sender_peer_id or sender_peer_id == "" or not epoch then
    return nil
  end

  local message = {
    type = fields[3],
    sender_peer_id = sender_peer_id,
    session_id = fields[5] ~= NO_SESSION and fields[5] or nil,
    epoch = epoch,
  }
  if not codec.read(fields, message) then
    return nil
  end
  return message
end

return M
