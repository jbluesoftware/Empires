-- Play scene: automatically joins (or starts) the session on the local network and shows every device's
-- RGB lights. Top half: other players' lights. Lower third: own combined light and the R/G/B toggle buttons.
-- Desktop testing shortcut: press R, G or B to toggle the matching light.

local Scene = require("core.scene")
local Button = require("ui.widgets.button")
local Light = require("ui.widgets.light")
local ToggleButton = require("ui.widgets.toggle_button")
local fonts = require("ui.fonts")
local theme = require("ui.theme")
local identity = require("net.identity")
local Session = require("net.session")
local Transport = require("net.transport")
local Textbox = require("ui.widgets.textbox")

local STATUS = Session.STATUS

local BACK_BUTTON_WIDTH = 76
local BACK_BUTTON_HEIGHT = 36
local TOGGLE_BUTTON_HEIGHT = 140
local OWN_LIGHT_RADIUS = 56
local REMOTE_LIGHT_MAXIMUM_CELL_SIZE = 88
local REMOTE_LIGHT_RADIUS_RATIO = 0.36
local WAITING_TEXT_OFFSET = 40

local LIGHT_CHANNELS = {
  { name = "red", muted_color = theme.colors.red_muted, bright_color = theme.colors.red_bright, shortcut_key = "r" },
  { name = "green", muted_color = theme.colors.green_muted, bright_color = theme.colors.green_bright, shortcut_key = "g" },
  { name = "blue", muted_color = theme.colors.blue_muted, bright_color = theme.colors.blue_bright, shortcut_key = "b" },
}

local STATUS_TEXT_BY_SESSION_STATUS = {
  [STATUS.OFFLINE] = "No network",
  [STATUS.SUSPENDED] = "Paused",
  [STATUS.SEARCHING] = "Searching...",
  [STATUS.JOINING] = "Joining...",
  [STATUS.HOSTING] = "Hosting",
  [STATUS.CONNECTED] = "Connected",
  [STATUS.RECOVERING] = "Reconnecting...",
}

-- Picks the column count that makes square cells as large as possible inside the area.
local function compute_grid_layout(item_count, area_width, area_height, maximum_cell_size)
  local best_column_count = 1
  local best_cell_size = 0
  for column_count = 1, item_count do
    local row_count = math.ceil(item_count / column_count)
    local cell_size = math.min(area_width / column_count, area_height / row_count, maximum_cell_size)
    if cell_size > best_cell_size then
      best_cell_size = cell_size
      best_column_count = column_count
    end
  end
  return best_column_count, best_cell_size
end

local PlayScene = Scene.extend()

function PlayScene:enter(context)
  self.context = context
  self.displayed_status = nil
  self.displayed_player_count = nil
  self.status_text = ""

  self:build_layout(context)
  self:start_session(context)
end

function PlayScene:build_layout(context)
  local virtual_width, virtual_height = context.screen.get_size()
  local safe_left, safe_top, safe_right, safe_bottom = context.screen.safe_area()
  local margin = theme.spacing.medium
  local content_left = safe_left + margin
  local content_right = safe_right - margin
  local header_top = safe_top + margin

  self.virtual_width = virtual_width
  self.status_text_x = content_left
  self.status_text_y = header_top + (BACK_BUTTON_HEIGHT - fonts.get("small"):getHeight()) / 2

  self.back_button = Button.new("Back", {
    x = content_right - BACK_BUTTON_WIDTH,
    y = header_top,
    width = BACK_BUTTON_WIDTH,
    height = BACK_BUTTON_HEIGHT,
  }, function()
    context.scenes.switch("menu")
  end)

  local remote_area_top = header_top + BACK_BUTTON_HEIGHT + margin
  self.remote_area = {
    x = content_left,
    y = remote_area_top,
    width = content_right - content_left,
    height = virtual_height / 2 - margin - remote_area_top,
  }

  local toggle_button_gap = margin
  local toggle_button_width = (content_right - content_left - toggle_button_gap * 2) / #LIGHT_CHANNELS
  local toggle_buttons_top = safe_bottom - theme.spacing.large - TOGGLE_BUTTON_HEIGHT

  self.toggle_buttons = {}
  for channel_index, channel in ipairs(LIGHT_CHANNELS) do
    self.toggle_buttons[channel_index] = ToggleButton.new({
      x = content_left + (channel_index - 1) * (toggle_button_width + toggle_button_gap),
      y = toggle_buttons_top,
      width = toggle_button_width,
      height = TOGGLE_BUTTON_HEIGHT,
    }, channel.muted_color, channel.bright_color, function(is_on)
      self.session:set_light(channel.name, is_on)
    end)
  end

  self.own_light_center_x = virtual_width / 2
  self.own_light_center_y = toggle_buttons_top - theme.spacing.large - OWN_LIGHT_RADIUS

  self.textbox = Textbox.new({
      x = virtual_width / 2, 
      y = virtual_height / 2,
      width = virtual_width * 3 / 4,
      height = virtual_width / 9,
      alignment = "CENTRE"
    }, {
      placeholder_text = "Hi",
      maximum_character_count = 100
    })


end

function PlayScene:start_session(context)
  local network_config = context.config.NETWORK
  local random_source = identity.create_random_source()

  self.session = Session.new({
    transport = Transport.new({
      base_port = network_config.SESSION_PORT,
      port_count = network_config.SESSION_PORT_COUNT,
    }),
    clock = love.timer.getTime,
    random = random_source,
    peer_id = identity.generate_peer_id(random_source),
    timing = network_config,
  })

  self.suspend_listener = function()
    self.session:suspend()
  end
  self.resume_listener = function()
    self.session:resume()
  end
  context.events.on(context.events.APP_SUSPENDED, self.suspend_listener)
  context.events.on(context.events.APP_RESUMED, self.resume_listener)

  self.session:start()
end

function PlayScene:leave(context)
  context.events.off(context.events.APP_SUSPENDED, self.suspend_listener)
  context.events.off(context.events.APP_RESUMED, self.resume_listener)
  self.session:leave()
  self.session = nil
  self.textbox:blur()
end

function PlayScene:update(delta_time_seconds)
  self.session:update()
  self.textbox:update(delta_time_seconds)
end

function PlayScene:refresh_status_text()
  local session_status = self.session:get_status()
  local player_count = self.session:get_player_count()
  if session_status == self.displayed_status and player_count == self.displayed_player_count then
    return
  end

  self.displayed_status = session_status
  self.displayed_player_count = player_count
  self.status_text = STATUS_TEXT_BY_SESSION_STATUS[session_status] or session_status
  if session_status == STATUS.HOSTING or session_status == STATUS.CONNECTED then
    self.status_text = string.format("%s - %d %s", self.status_text, player_count, player_count == 1 and "player" or "players")
  end
end

function PlayScene:draw_remote_lights()
  local remote_members = self.session:get_remote_members()
  local remote_member_count = #remote_members
  local area = self.remote_area

  if remote_member_count == 0 then
    local session_status = self.session:get_status()
    if session_status == STATUS.HOSTING or session_status == STATUS.CONNECTED then
      love.graphics.setColor(theme.colors.text_dim)
      love.graphics.setFont(fonts.get("body"))
      love.graphics.printf("Waiting for other players...", area.x, area.y + WAITING_TEXT_OFFSET, area.width, "center")
    end
    return
  end

  local column_count, cell_size =
    compute_grid_layout(remote_member_count, area.width, area.height, REMOTE_LIGHT_MAXIMUM_CELL_SIZE)
  local light_radius = cell_size * REMOTE_LIGHT_RADIUS_RATIO

  for member_index, member in ipairs(remote_members) do
    local row_index = math.floor((member_index - 1) / column_count)
    local column_index = (member_index - 1) % column_count
    local members_in_row = math.min(column_count, remote_member_count - row_index * column_count)
    local row_left = area.x + (area.width - members_in_row * cell_size) / 2

    Light.draw(row_left + (column_index + 0.5) * cell_size, area.y + (row_index + 0.5) * cell_size, light_radius, member.lights)
  end

end

function PlayScene:draw()
  self:refresh_status_text()

  love.graphics.setColor(theme.colors.text_dim)
  love.graphics.setFont(fonts.get("small"))
  love.graphics.print(self.status_text, self.status_text_x, self.status_text_y)
  self.back_button:draw()
  self.textbox:draw()

  self:draw_remote_lights()

  Light.draw(self.own_light_center_x, self.own_light_center_y, OWN_LIGHT_RADIUS, self.session:get_my_lights())
  for _, toggle_button in ipairs(self.toggle_buttons) do
    toggle_button:draw()
  end
end

function PlayScene:pointerpressed(virtual_x, virtual_y)
  self.back_button:pointerpressed(virtual_x, virtual_y)
  self.textbox:pointerpressed(virtual_x, virtual_y)
  for _, toggle_button in ipairs(self.toggle_buttons) do
    toggle_button:pointerpressed(virtual_x, virtual_y)
  end
end

function PlayScene:pointerreleased(virtual_x, virtual_y)
  self.back_button:pointerreleased(virtual_x, virtual_y)
  for _, toggle_button in ipairs(self.toggle_buttons) do
    toggle_button:pointerreleased(virtual_x, virtual_y)
  end
end

function PlayScene:keypressed(key)
  -- for channel_index, channel in ipairs(LIGHT_CHANNELS) do
  --   if key == channel.shortcut_key then
  --     self.toggle_buttons[channel_index]:toggle()
  --     return true
  --   end
  -- end
  self.textbox:keypressed(key)
  return false
end

function PlayScene:textinput(incoming_text)
  self.textbox:textinput(incoming_text)
end

function PlayScene:back()
  self.context.scenes.switch("menu")
  return true
end

return PlayScene
