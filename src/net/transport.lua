-- Non-blocking UDP transport over LuaSocket: binds a port (trying a few if taken, so several instances
-- can share one machine), sends unicast and broadcast datagrams, and reports the device's LAN address.
-- The session talks to this interface only, so tests can substitute an in-memory fake.

local socket = require("socket")
local log = require("core.log").new("transport")

local Transport = {}
Transport.__index = Transport

local LIMITED_BROADCAST_ADDRESS = "255.255.255.255"
local LOOPBACK_ADDRESS = "127.0.0.1"
local ROUTE_PROBE_ADDRESS = "8.8.8.8" -- UDP connect() sends nothing; it only makes the OS pick the LAN interface
local ROUTE_PROBE_PORT = 80

-- options: base_port (first port to try), port_count (how many consecutive ports to try)
function Transport.new(options)
  return setmetatable({
    base_port = options.base_port,
    port_count = options.port_count,
    udp_socket = nil,
    bound_port = nil,
    local_ip = nil,
    logged_send_errors = {},
    broadcast_addresses = { LIMITED_BROADCAST_ADDRESS, LOOPBACK_ADDRESS },
  }, Transport)
end

-- socket.udp() creates the OS socket lazily and may pick IPv6, which breaks IPv4 sends and the broadcast
-- option; udp4() creates an IPv4 socket immediately (older LuaSocket builds fall back to udp()).
local function create_ipv4_udp_socket()
  return (socket.udp4 or socket.udp)()
end

function Transport:open()
  self:close()
  self.logged_send_errors = {}

  for port_offset = 0, self.port_count - 1 do
    local candidate_port = self.base_port + port_offset
    local udp_socket = create_ipv4_udp_socket()
    udp_socket:settimeout(0)
    if udp_socket:setsockname("*", candidate_port) then
      -- Set after binding so the OS socket certainly exists.
      local did_enable_broadcast, broadcast_error = udp_socket:setoption("broadcast", true)
      if not did_enable_broadcast then
        log.warn("could not enable broadcast: %s", tostring(broadcast_error))
      end
      self.udp_socket = udp_socket
      self.bound_port = candidate_port
      self:refresh_local_ip()
      log.info("listening on UDP port %d, local ip %s", candidate_port, tostring(self.local_ip))
      return true
    end
    udp_socket:close()
  end

  log.error("no free UDP port in %d-%d", self.base_port, self.base_port + self.port_count - 1)
  return false
end

function Transport:close()
  if self.udp_socket then
    self.udp_socket:close()
    self.udp_socket = nil
    self.bound_port = nil
  end
end

function Transport:is_open()
  return self.udp_socket ~= nil
end

function Transport:get_base_port()
  return self.base_port
end

function Transport:get_bound_port()
  return self.bound_port
end

function Transport:get_local_ip()
  return self.local_ip
end

-- Returns the current LAN IPv4 address, or nil when there is no usable route (e.g. Wi-Fi off).
function Transport:refresh_local_ip()
  local probe_socket = create_ipv4_udp_socket()
  local local_ip
  if probe_socket:setpeername(ROUTE_PROBE_ADDRESS, ROUTE_PROBE_PORT) then
    local_ip = probe_socket:getsockname()
  end
  probe_socket:close()

  if local_ip == "0.0.0.0" then
    local_ip = nil
  end
  self.local_ip = local_ip

  self.broadcast_addresses = { LIMITED_BROADCAST_ADDRESS, LOOPBACK_ADDRESS }
  local subnet_prefix = local_ip and string.match(local_ip, "^(%d+%.%d+%.%d+)%.%d+$")
  if subnet_prefix then
    self.broadcast_addresses[#self.broadcast_addresses + 1] = subnet_prefix .. ".255"
  end
  return local_ip
end

-- is_best_effort suppresses error logging (used by the subnet sweep, where most addresses are empty).
function Transport:send(destination_ip, destination_port, packet_text, is_best_effort)
  if not self.udp_socket then
    return false
  end
  local was_sent, error_message = self.udp_socket:sendto(packet_text, destination_ip, destination_port)
  if not was_sent and not is_best_effort and error_message ~= "timeout" then -- "timeout" = send buffer momentarily full
    -- Warn once per distinct error so a systematic failure is visible without flooding the log.
    if not self.logged_send_errors[error_message] then
      self.logged_send_errors[error_message] = true
      log.warn("send to %s:%s failed: %s", destination_ip, tostring(destination_port), tostring(error_message))
    end
  end
  return was_sent ~= nil
end

-- Sends to every port in the range so other instances on this machine and other devices both hear it.
function Transport:broadcast(packet_text)
  for _, broadcast_address in ipairs(self.broadcast_addresses) do
    for port_offset = 0, self.port_count - 1 do
      self:send(broadcast_address, self.base_port + port_offset, packet_text)
    end
  end
end

-- Returns source_ip, source_port, packet_text, or nil when nothing is waiting.
function Transport:receive()
  if not self.udp_socket then
    return nil
  end
  local packet_text, source_ip, source_port = self.udp_socket:receivefrom()
  if packet_text then
    return source_ip, source_port, packet_text
  end
  return nil
end

return Transport