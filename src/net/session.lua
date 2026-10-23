-- Zero-configuration LAN session. On start it searches for a host; if one exists it joins, otherwise it
-- becomes host. "Host" is only a role: every peer holds the full ordered roster from the last snapshot, so
-- when the host disappears the first surviving peer in roster order takes over without losing state.
--
-- Roles / status:  searching -> joining -> connected (client)
--                  searching -> hosting
--                  connected -> recovering -> hosting (promoted) or connected (new host found)
--
-- Conflict rules: a higher epoch wins within a session; between sessions the larger one wins, then the lower
-- session id. The loser redirects its members and joins the winner, so duplicate hosts merge automatically.
--
-- The session is driven by update(); it never blocks. Transport, clock and randomness are injected for testing.

local protocol = require("net.protocol")
local log = require("core.log").new("session")

local TYPES = protocol.MESSAGE_TYPES

local STATUS = {
  SUSPENDED = "suspended",
  OFFLINE = "offline",
  SEARCHING = "searching",
  JOINING = "joining",
  HOSTING = "hosting",
  CONNECTED = "connected",
  RECOVERING = "recovering",
}

local MAXIMUM_PACKETS_PER_UPDATE = 64
local MAXIMUM_SWEEP_ELAPSED_SECONDS = 0.25
local SUBNET_HOST_COUNT = 254
local UNKNOWN_IP = "0.0.0.0"

local Session = {}
Session.__index = Session
Session.STATUS = STATUS

----------------------------------------------------------------------
-- Pure helpers
----------------------------------------------------------------------

local function find_member(roster, peer_id)
  for _, member in ipairs(roster) do
    if member.peer_id == peer_id then
      return member
    end
  end
  return nil
end

local function lights_are_equal(first_lights, second_lights)
  return first_lights.red == second_lights.red
    and first_lights.green == second_lights.green
    and first_lights.blue == second_lights.blue
end

local function copy_lights_into(destination_lights, source_lights)
  destination_lights.red = source_lights.red
  destination_lights.green = source_lights.green
  destination_lights.blue = source_lights.blue
end

-- Returns true when `candidate` should replace `current`. Both: session_id, epoch, host_peer_id, member_count.
function Session.session_outranks(candidate, current)
  if candidate.session_id == current.session_id then
    if candidate.epoch ~= current.epoch then
      return candidate.epoch > current.epoch
    end
    return candidate.host_peer_id < current.host_peer_id
  end
  if candidate.member_count ~= current.member_count then
    return candidate.member_count > current.member_count
  end
  return candidate.session_id < current.session_id
end

----------------------------------------------------------------------
-- Construction and lifecycle
----------------------------------------------------------------------

-- options: transport, clock (function -> seconds), random (function -> [0,1)), peer_id, timing (config.NETWORK)
function Session.new(options)
  return setmetatable({
    transport = options.transport,
    clock = options.clock,
    random = options.random,
    peer_id = options.peer_id,
    timing = options.timing,

    status = STATUS.SUSPENDED,
    my_lights = { red = false, green = false, blue = false },

    session_id = nil,
    epoch = 0,
    version = 0,
    roster = {},

    host_peer_id = nil,
    host_ip = nil,
    host_port = nil,
    last_host_heard = 0,

    next_heartbeat_at = 0,
    next_announce_at = 0,
    next_probe_at = 0,
    next_network_check_at = 0,
    search_ends_at = 0,
    last_update_at = 0,

    join_target_ip = nil,
    join_target_port = nil,
    join_target_session_id = nil,
    join_deadline = 0,
    join_attempts = 0,

    succession = nil,

    sweep_cursor = 0,
    sweep_credit = 0,

    remote_members = {},
    remote_members_are_stale = true,

    hello_text = protocol.encode({ type = TYPES.HELLO, sender_peer_id = options.peer_id }),
  }, Session)
end

function Session:now()
  return self.clock()
end

function Session:start()
  if not self.transport:open() then
    self:enter_offline()
    return
  end
  self.last_update_at = self:now()
  self.next_network_check_at = self:now() + self.timing.NETWORK_CHECK_INTERVAL_SECONDS
  self:begin_searching()
end

-- Tells the other peers we are going away (best effort), then releases the socket.
function Session:suspend()
  if self.status == STATUS.SUSPENDED then
    return
  end

  if self.status == STATUS.HOSTING then
    local close_text = self:encode_message(TYPES.CLOSE)
    for _, member in ipairs(self.roster) do
      if member.peer_id ~= self.peer_id then
        self.transport:send(member.ip, member.port, close_text)
      end
    end
  elseif self.status == STATUS.CONNECTED then
    self:send_to(self.host_ip, self.host_port, TYPES.LEAVE)
  end

  self.transport:close()
  self:reset_session_state()
  self.status = STATUS.SUSPENDED
end

function Session:leave()
  self:suspend()
end

function Session:resume()
  if self.status == STATUS.SUSPENDED then
    self:start()
  end
end

function Session:reset_session_state()
  self.session_id = nil
  self.epoch = 0
  self.version = 0
  self.roster = {}
  self.host_peer_id = nil
  self.host_ip = nil
  self.host_port = nil
  self.succession = nil
  self.remote_members_are_stale = true
end

----------------------------------------------------------------------
-- Public state for the UI
----------------------------------------------------------------------

function Session:get_status()
  return self.status
end

function Session:get_player_count()
  return math.max(1, #self.roster)
end

function Session:get_my_lights()
  return self.my_lights
end

-- Returns the roster without this device, in join order. The returned table is reused between calls.
function Session:get_remote_members()
  if self.remote_members_are_stale then
    local remote_members = self.remote_members
    for index = #remote_members, 1, -1 do
      remote_members[index] = nil
    end
    for _, member in ipairs(self.roster) do
      if member.peer_id ~= self.peer_id then
        remote_members[#remote_members + 1] = member
      end
    end
    self.remote_members_are_stale = false
  end
  return self.remote_members
end

function Session:set_light(channel_name, is_on)
  assert(self.my_lights[channel_name] ~= nil, "unknown light channel: " .. tostring(channel_name))
  if self.my_lights[channel_name] == is_on then
    return
  end
  self.my_lights[channel_name] = is_on

  if self.status == STATUS.HOSTING then
    self:bump_version_and_publish()
  elseif self.status == STATUS.CONNECTED then
    self:send_state()
  end
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------

function Session:encode_message(message_type, extra_fields)
  local message = extra_fields or {}
  message.type = message_type
  message.sender_peer_id = self.peer_id
  message.session_id = self.session_id
  message.epoch = self.epoch
  return protocol.encode(message)
end

function Session:send_to(destination_ip, destination_port, message_type, extra_fields)
  self.transport:send(destination_ip, destination_port, self:encode_message(message_type, extra_fields))
end

function Session:send_state()
  self:send_to(self.host_ip, self.host_port, TYPES.STATE, { lights = self.my_lights })
  self.next_heartbeat_at = self:now() + self.timing.HEARTBEAT_INTERVAL_SECONDS
end

function Session:send_join()
  self.join_attempts = self.join_attempts + 1
  self.join_deadline = self:now() + self.timing.JOIN_TIMEOUT_SECONDS
  self:send_to(self.join_target_ip, self.join_target_port, TYPES.JOIN, { lights = self.my_lights })
end

-- Sends the session advertisement to one address, or by broadcast when no address is given.
function Session:announce(destination_ip, destination_port)
  local announce_text = self:encode_message(TYPES.ANNOUNCE, { member_count = #self.roster })
  if destination_ip then
    self.transport:send(destination_ip, destination_port, announce_text)
  else
    self.transport:broadcast(announce_text)
  end
end

function Session:update_own_member_address()
  local own_member = find_member(self.roster, self.peer_id)
  if own_member then
    own_member.ip = self.transport:get_local_ip() or UNKNOWN_IP
    own_member.port = self.transport:get_bound_port() or 0
  end
end

function Session:publish_snapshot()
  self:update_own_member_address()
  local snapshot_text = self:encode_message(TYPES.SNAPSHOT, { version = self.version, roster = self.roster })
  for _, member in ipairs(self.roster) do
    if member.peer_id ~= self.peer_id then
      self.transport:send(member.ip, member.port, snapshot_text)
    end
  end
  self.next_heartbeat_at = self:now() + self.timing.HEARTBEAT_INTERVAL_SECONDS
end

function Session:bump_version_and_publish()
  self.version = self.version + 1
  self:publish_snapshot()
end

function Session:redirect_members_to(target_ip, target_port)
  local redirect_text = self:encode_message(TYPES.REDIRECT, { target_ip = target_ip, target_port = target_port })
  for _, member in ipairs(self.roster) do
    if member.peer_id ~= self.peer_id then
      self.transport:send(member.ip, member.port, redirect_text)
    end
  end
end

----------------------------------------------------------------------
-- State transitions
----------------------------------------------------------------------

function Session:enter_offline()
  self:reset_session_state()
  self.status = STATUS.OFFLINE
  log.warn("no network")
end

function Session:begin_searching()
  self:reset_session_state()
  if not self.transport:get_local_ip() then
    self:enter_offline()
    return
  end

  local now = self:now()
  self.status = STATUS.SEARCHING
  self.next_probe_at = now
  self.search_ends_at = now + self.timing.SEARCH_DURATION_SECONDS + self.random() * self.timing.SEARCH_JITTER_SECONDS
  self.sweep_cursor = 0
  self.sweep_credit = 0
  log.info("searching for a session")
end

function Session:begin_joining(target_ip, target_port, target_session_id)
  if self.status == STATUS.CONNECTED then
    self:send_to(self.host_ip, self.host_port, TYPES.LEAVE)
  end

  self.status = STATUS.JOINING
  self.join_target_ip = target_ip
  self.join_target_port = target_port
  self.join_target_session_id = target_session_id
  self.join_attempts = 0
  self.succession = nil
  log.info("joining %s:%s", target_ip, tostring(target_port))
  self:send_join()
end

-- seed_members: ordered roster entries to start from (may be empty; this device is added if missing).
function Session:become_host(new_epoch, new_version, seed_members)
  local now = self:now()
  self.status = STATUS.HOSTING
  self.epoch = new_epoch
  self.version = new_version
  self.host_peer_id = self.peer_id
  self.succession = nil

  self.roster = {}
  local has_own_member = false
  for _, seed_member in ipairs(seed_members) do
    seed_member.last_heard = now
    if seed_member.peer_id == self.peer_id then
      seed_member.lights = self.my_lights
      has_own_member = true
    end
    self.roster[#self.roster + 1] = seed_member
  end
  if not has_own_member then
    self.roster[#self.roster + 1] = {
      peer_id = self.peer_id,
      ip = UNKNOWN_IP,
      port = 0,
      lights = self.my_lights,
      last_heard = now,
    }
  end

  self.remote_members_are_stale = true
  self.next_announce_at = now + self.timing.ANNOUNCE_INTERVAL_SECONDS
  self.sweep_credit = 0
  log.info("hosting session %s, epoch %d, %d member(s)", tostring(self.session_id), new_epoch, #self.roster)

  self:publish_snapshot()
  self:announce()
end

function Session:start_new_session()
  self.session_id = self.peer_id
  self:become_host(1, 1, {})
end

function Session:begin_succession()
  local candidates = {}
  for _, member in ipairs(self.roster) do
    if member.peer_id ~= self.host_peer_id then
      candidates[#candidates + 1] = member
    end
  end

  self.status = STATUS.RECOVERING
  self.succession = {
    candidates = candidates,
    candidate_index = 1,
    base_epoch = self.epoch,
    step_deadline = self:now() + self.timing.SUCCESSION_STEP_SECONDS,
  }
  log.warn("host lost, starting succession with %d candidate(s)", #candidates)
  self:resolve_succession_step()
end

-- Promotes this device when it is the current candidate; gives up to a fresh search when candidates run out.
function Session:resolve_succession_step()
  local succession = self.succession
  local candidate = succession.candidates[succession.candidate_index]
  if not candidate then
    self:begin_searching()
    return
  end

  if candidate.peer_id == self.peer_id then
    local seed_members = {}
    for candidate_index = succession.candidate_index, #succession.candidates do
      seed_members[#seed_members + 1] = succession.candidates[candidate_index]
    end
    self:become_host(succession.base_epoch + succession.candidate_index, self.version + 1, seed_members)
  end
end

function Session:adopt_snapshot(message, source_ip, source_port)
  self.status = STATUS.CONNECTED
  self.session_id = message.session_id
  self.epoch = message.epoch
  self.version = message.version
  self.roster = message.roster
  self.host_peer_id = message.sender_peer_id
  self.host_ip = source_ip
  self.host_port = source_port
  self.last_host_heard = self:now()
  self.next_heartbeat_at = self:now() + self.timing.HEARTBEAT_INTERVAL_SECONDS
  self.succession = nil
  self.remote_members_are_stale = true

  local own_member = find_member(self.roster, self.peer_id)
  if not own_member then
    self.join_target_ip, self.join_target_port = source_ip, source_port
    self.join_attempts = 0
    self:send_join()
  elseif not lights_are_equal(own_member.lights, self.my_lights) then
    self:send_state()
  end
end

function Session:describe_current_session()
  return {
    session_id = self.session_id,
    epoch = self.epoch,
    host_peer_id = self.host_peer_id,
    member_count = #self.roster,
  }
end

-- Adds or refreshes a roster member (host only). Returns member, did_change; nil when the roster is full.
function Session:upsert_member(peer_id, member_ip, member_port, lights)
  local now = self:now()
  local member = find_member(self.roster, peer_id)
  if not member then
    if #self.roster >= self.timing.MAX_PEERS then
      return nil, false
    end
    member = {
      peer_id = peer_id,
      ip = member_ip,
      port = member_port,
      lights = { red = lights.red, green = lights.green, blue = lights.blue },
      last_heard = now,
    }
    self.roster[#self.roster + 1] = member
    self.remote_members_are_stale = true
    return member, true
  end

  member.ip = member_ip
  member.port = member_port
  member.last_heard = now
  if not lights_are_equal(member.lights, lights) then
    copy_lights_into(member.lights, lights)
    return member, true
  end
  return member, false
end

----------------------------------------------------------------------
-- Discovery sweep: unicast HELLO across the local /24 so discovery works even where broadcast is filtered
----------------------------------------------------------------------

function Session:advance_sweep(elapsed_seconds, addresses_per_second)
  local local_ip = self.transport:get_local_ip()
  local subnet_prefix = local_ip and string.match(local_ip, "^(%d+%.%d+%.%d+)%.%d+$")
  if not subnet_prefix then
    return
  end

  self.sweep_credit = self.sweep_credit + math.min(elapsed_seconds, MAXIMUM_SWEEP_ELAPSED_SECONDS) * addresses_per_second
  while self.sweep_credit >= 1 do
    self.sweep_credit = self.sweep_credit - 1
    self.sweep_cursor = self.sweep_cursor % SUBNET_HOST_COUNT + 1
    local target_ip = subnet_prefix .. "." .. self.sweep_cursor
    if target_ip ~= local_ip then
      self.transport:send(target_ip, self.transport:get_base_port(), self.hello_text)
    end
  end
end

function Session:check_network(now)
  if now < self.next_network_check_at then
    return
  end
  self.next_network_check_at = now + self.timing.NETWORK_CHECK_INTERVAL_SECONDS

  local previous_ip = self.transport:get_local_ip()
  local current_ip = self.transport:refresh_local_ip()

  if not current_ip then
    if self.status ~= STATUS.OFFLINE then
      self:enter_offline()
    end
  elseif self.status == STATUS.OFFLINE then
    if self.transport:is_open() or self.transport:open() then
      self:begin_searching()
    end
  elseif current_ip ~= previous_ip then
    log.info("network changed, searching again")
    self:begin_searching()
  end
end

----------------------------------------------------------------------
-- Packet handlers
----------------------------------------------------------------------

local PACKET_HANDLERS = {}

PACKET_HANDLERS[TYPES.HELLO] = function(self, _, source_ip, source_port)
  if self.status == STATUS.HOSTING then
    self:announce(source_ip, source_port)
  end
end

PACKET_HANDLERS[TYPES.ANNOUNCE] = function(self, message, source_ip, source_port)
  local status = self.status
  if status == STATUS.SEARCHING then
    if message.member_count < self.timing.MAX_PEERS then
      self:begin_joining(source_ip, source_port, message.session_id)
    end
    return
  end

  if status ~= STATUS.HOSTING and status ~= STATUS.CONNECTED and status ~= STATUS.RECOVERING then
    return
  end

  local is_full_foreign_session = message.session_id ~= self.session_id
    and message.member_count >= self.timing.MAX_PEERS
  local candidate = {
    session_id = message.session_id,
    epoch = message.epoch,
    host_peer_id = message.sender_peer_id,
    member_count = message.member_count,
  }
  if not is_full_foreign_session and Session.session_outranks(candidate, self:describe_current_session()) then
    if status == STATUS.HOSTING then
      self:redirect_members_to(source_ip, source_port)
    end
    self:begin_joining(source_ip, source_port, message.session_id)
  end
end

PACKET_HANDLERS[TYPES.JOIN] = function(self, message, source_ip, source_port)
  if self.status ~= STATUS.HOSTING then
    return
  end
  local member, did_change = self:upsert_member(message.sender_peer_id, source_ip, source_port, message.lights)
  if not member then
    return
  end
  if did_change then
    self:bump_version_and_publish()
  else
    self:publish_snapshot()
  end
end

PACKET_HANDLERS[TYPES.STATE] = function(self, message, source_ip, source_port)
  if self.status ~= STATUS.HOSTING or message.session_id ~= self.session_id or message.epoch > self.epoch then
    return
  end
  local member, did_change = self:upsert_member(message.sender_peer_id, source_ip, source_port, message.lights)
  if member and did_change then
    self:bump_version_and_publish()
  end
end

PACKET_HANDLERS[TYPES.LEAVE] = function(self, message)
  if self.status ~= STATUS.HOSTING or message.session_id ~= self.session_id then
    return
  end
  local member = find_member(self.roster, message.sender_peer_id)
  if member and member.peer_id ~= self.peer_id then
    for roster_index, roster_member in ipairs(self.roster) do
      if roster_member == member then
        table.remove(self.roster, roster_index)
        break
      end
    end
    self.remote_members_are_stale = true
    self:bump_version_and_publish()
  end
end

PACKET_HANDLERS[TYPES.SNAPSHOT] = function(self, message, source_ip, source_port)
  local status = self.status

  if status == STATUS.JOINING then
    local is_expected_sender = (source_ip == self.join_target_ip and source_port == self.join_target_port)
      or (self.join_target_session_id ~= nil and message.session_id == self.join_target_session_id)
    if is_expected_sender and find_member(message.roster, self.peer_id) then
      self:adopt_snapshot(message, source_ip, source_port)
    end

  elseif status == STATUS.CONNECTED or status == STATUS.RECOVERING then
    if message.session_id ~= self.session_id or message.epoch < self.epoch then
      return
    end
    if message.epoch == self.epoch and message.sender_peer_id ~= self.host_peer_id then
      return
    end
    if message.epoch == self.epoch and message.version < self.version then
      self.last_host_heard = self:now()
      return
    end
    self:adopt_snapshot(message, source_ip, source_port)

  elseif status == STATUS.HOSTING then
    local is_same_session = message.session_id == self.session_id
    local sender_has_precedence = message.epoch > self.epoch
      or (message.epoch == self.epoch and message.sender_peer_id < self.peer_id)
    if is_same_session and sender_has_precedence then
      self:begin_joining(source_ip, source_port, message.session_id)
    end
  end
end

PACKET_HANDLERS[TYPES.CLOSE] = function(self, message)
  if self.status == STATUS.CONNECTED and message.sender_peer_id == self.host_peer_id then
    self:begin_succession()
  end
end

PACKET_HANDLERS[TYPES.REDIRECT] = function(self, message)
  if self.status == STATUS.CONNECTED and message.sender_peer_id == self.host_peer_id then
    self:begin_joining(message.target_ip, message.target_port, nil)
  end
end

function Session:receive_packets()
  for _ = 1, MAXIMUM_PACKETS_PER_UPDATE do
    local source_ip, source_port, packet_text = self.transport:receive()
    if not source_ip then
      return
    end
    local message = protocol.decode(packet_text)
    if message and message.sender_peer_id ~= self.peer_id then
      local handler = PACKET_HANDLERS[message.type]
      if handler then
        handler(self, message, source_ip, source_port)
      end
    end
  end
end

----------------------------------------------------------------------
-- Per-status updates
----------------------------------------------------------------------

function Session:update_searching(now, elapsed_seconds)
  if now >= self.next_probe_at then
    self.transport:broadcast(self.hello_text)
    self.next_probe_at = now + self.timing.SEARCH_PROBE_INTERVAL_SECONDS
  end
  self:advance_sweep(elapsed_seconds, self.timing.SEARCH_SWEEP_ADDRESSES_PER_SECOND)
  if now >= self.search_ends_at then
    self:start_new_session()
  end
end

function Session:update_joining(now)
  if now < self.join_deadline then
    return
  end
  if self.join_attempts >= self.timing.JOIN_MAX_ATTEMPTS then
    self:begin_searching()
  else
    self:send_join()
  end
end

function Session:update_hosting(now, elapsed_seconds)
  local did_remove_member = false
  for roster_index = #self.roster, 1, -1 do
    local member = self.roster[roster_index]
    if member.peer_id ~= self.peer_id and now - member.last_heard > self.timing.MEMBER_TIMEOUT_SECONDS then
      table.remove(self.roster, roster_index)
      did_remove_member = true
      log.info("member %s timed out", member.peer_id)
    end
  end

  if did_remove_member then
    self.remote_members_are_stale = true
    self:bump_version_and_publish()
  elseif now >= self.next_heartbeat_at then
    self:publish_snapshot()
  end

  if now >= self.next_announce_at then
    self:announce()
    self.next_announce_at = now + self.timing.ANNOUNCE_INTERVAL_SECONDS
  end
  self:advance_sweep(elapsed_seconds, self.timing.HOST_SWEEP_ADDRESSES_PER_SECOND)
end

function Session:update_connected(now)
  if now - self.last_host_heard > self.timing.HOST_TIMEOUT_SECONDS then
    self:begin_succession()
  elseif now >= self.next_heartbeat_at then
    self:send_state()
  end
end

function Session:update_recovering(now)
  local succession = self.succession
  if now >= succession.step_deadline then
    succession.candidate_index = succession.candidate_index + 1
    succession.step_deadline = now + self.timing.SUCCESSION_STEP_SECONDS
    self:resolve_succession_step()
  end
end

local STATUS_UPDATERS = {
  [STATUS.SEARCHING] = Session.update_searching,
  [STATUS.JOINING] = Session.update_joining,
  [STATUS.HOSTING] = Session.update_hosting,
  [STATUS.CONNECTED] = Session.update_connected,
  [STATUS.RECOVERING] = Session.update_recovering,
}

-- Call once per frame.
function Session:update()
  if self.status == STATUS.SUSPENDED then
    return
  end

  local now = self:now()
  local elapsed_seconds = now - self.last_update_at
  self.last_update_at = now

  self:check_network(now)
  if self.status == STATUS.SUSPENDED or self.status == STATUS.OFFLINE then
    return
  end

  self:receive_packets()

  local status_updater = STATUS_UPDATERS[self.status]
  if status_updater then
    status_updater(self, now, elapsed_seconds)
  end
end

return Session