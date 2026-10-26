-- Single-line text box that uses the device's native keyboard (on-screen keyboard on phones, physical on desktop).
-- Holds a UTF-8 string limited to a configurable number of characters; shows a placeholder, a blinking caret
-- and a used/limit counter while focused. Text is append and backspace only (no caret movement).
--
-- A scene using it must forward: update, pointerpressed, textinput and keypressed to the textbox,
-- call textbox:blur() in leave(), and in back() close the keyboard first when textbox:is_focused() is true.

local screen = require("core.screen")
local util = require("core.util")
local fonts = require("ui.fonts")
local theme = require("ui.theme")
local utf8 = require("utf8")

local Textbox = {}
Textbox.__index = Textbox

local DEFAULT_MAXIMUM_CHARACTER_COUNT = 20
local CARET_BLINK_PERIOD_SECONDS = 1
local CARET_WIDTH = 2
local OUTLINE_WIDTH = 2
local COUNTER_RESERVED_WIDTH = 56

-- Only one textbox owns the keyboard at a time.
local focused_textbox

local function strip_control_characters(text)
  return (string.gsub(text, "%c", ""))
end

local function truncate_to_character_count(text, maximum_character_count)
  local character_count = utf8.len(text)
  if not character_count then
    return ""
  end
  if character_count <= maximum_character_count then
    return text
  end
  return string.sub(text, 1, utf8.offset(text, maximum_character_count + 1) - 1)
end

-- bounds: { x, y, width, height } in virtual coordinates.
-- options (all optional): placeholder_text, maximum_character_count, initial_text,
--   on_changed(text) after the user edits, on_submitted(text) when Return is pressed.
function Textbox.new(bounds, options)
  options = options or {}

  local textbox = setmetatable({
    bounds = bounds,
    placeholder_text = options.placeholder_text or "",
    maximum_character_count = options.maximum_character_count or DEFAULT_MAXIMUM_CHARACTER_COUNT,
    on_changed = options.on_changed,
    on_submitted = options.on_submitted,
    text = "",
    visible_text = "",
    counter_text = "",
    has_focus = false,
    caret_blink_seconds = 0,
    available_text_width = bounds.width - theme.spacing.medium * 2 - COUNTER_RESERVED_WIDTH,
  }, Textbox)

  assert(textbox.maximum_character_count >= 1, "maximum_character_count must be at least 1")
  textbox.text = truncate_to_character_count(strip_control_characters(options.initial_text or ""), textbox.maximum_character_count)
  textbox:refresh_display_text()
  return textbox
end

function Textbox:get_text()
  return self.text
end

-- Replaces the text programmatically (does not call on_changed).
function Textbox:set_text(new_text)
  self.text = truncate_to_character_count(strip_control_characters(new_text), self.maximum_character_count)
  self:refresh_display_text()
end

function Textbox:set_character_limit(new_maximum_character_count)
  assert(new_maximum_character_count >= 1, "maximum_character_count must be at least 1")
  self.maximum_character_count = new_maximum_character_count
  local truncated_text = truncate_to_character_count(self.text, new_maximum_character_count)
  if truncated_text ~= self.text then
    self.text = truncated_text
    self:handle_text_changed()
  else
    self:refresh_display_text()
  end
end

function Textbox:is_focused()
  return self.has_focus
end

function Textbox:contains_point(virtual_x, virtual_y)
  local bounds = self.bounds
  if bounds.alignment == "CENTRE" then
    return util.is_point_in_rectangle(virtual_x, virtual_y, bounds.x - bounds.width/2, bounds.y - bounds.height/2, bounds.width, bounds.height)
  else
    return util.is_point_in_rectangle(virtual_x, virtual_y, bounds.x, bounds.y, bounds.width, bounds.height)
  end
end

-- Shows the on-screen keyboard and tells the OS where the box is so it can keep it visible.
function Textbox:focus()
  if focused_textbox == self then
    return
  end
  if focused_textbox then
    focused_textbox.has_focus = false
  end
  focused_textbox = self
  self.has_focus = true
  self.caret_blink_seconds = 0

  local bounds = self.bounds
  local window_x, window_y = screen.to_window(bounds.x, bounds.y)
  local scale_factor = screen.get_scale()
  love.keyboard.setTextInput(true, window_x, window_y, bounds.width * scale_factor, bounds.height * scale_factor)
  love.keyboard.setKeyRepeat(true)
end

function Textbox:blur()
  if focused_textbox ~= self then
    return
  end
  focused_textbox = nil
  self.has_focus = false
  love.keyboard.setTextInput(false)
  love.keyboard.setKeyRepeat(false)
end

function Textbox:refresh_display_text()
  local body_font = fonts.get("body")
  local visible_text = self.text
  while visible_text ~= "" and body_font:getWidth(visible_text) > self.available_text_width do
    local second_character_start = utf8.offset(visible_text, 2)
    visible_text = second_character_start and string.sub(visible_text, second_character_start) or ""
  end
  self.visible_text = visible_text
  self.counter_text = string.format("%d/%d", utf8.len(self.text), self.maximum_character_count)
end

function Textbox:handle_text_changed()
  self:refresh_display_text()
  self.caret_blink_seconds = 0
  if self.on_changed then
    self.on_changed(self.text)
  end
end

function Textbox:insert_text(incoming_text)
  local single_line_text = strip_control_characters(incoming_text)
  if single_line_text == "" or not utf8.len(single_line_text) then
    return false
  end

  local remaining_character_count = self.maximum_character_count - utf8.len(self.text)
  if remaining_character_count <= 0 then
    return false
  end

  self.text = self.text .. truncate_to_character_count(single_line_text, remaining_character_count)
  self:handle_text_changed()
  return true
end

function Textbox:delete_last_character()
  local last_character_start = utf8.offset(self.text, -1)
  if not last_character_start then
    return false
  end
  self.text = string.sub(self.text, 1, last_character_start - 1)
  self:handle_text_changed()
  return true
end

function Textbox:update(delta_time_seconds)
  if self.has_focus then
    self.caret_blink_seconds = (self.caret_blink_seconds + delta_time_seconds) % CARET_BLINK_PERIOD_SECONDS
  end
end

-- Taps inside focus the box; taps anywhere else release it. Returns true when the tap was inside.
function Textbox:pointerpressed(virtual_x, virtual_y)
  if self:contains_point(virtual_x, virtual_y) then
    self:focus()
    return true
  end
  self:blur()
  return false
end

-- Returns true when the text was consumed.
function Textbox:textinput(incoming_text)
  if not self.has_focus then
    return false
  end
  self:insert_text(incoming_text)
  return true
end

-- Returns true when the key was consumed.
function Textbox:keypressed(key)
  if not self.has_focus then
    return false
  end
  if key == "backspace" then
    self:delete_last_character()
    return true
  end
  if key == "return" or key == "kpenter" then
    if self.on_submitted then
      self.on_submitted(self.text)
    end
    self:blur()
    return true
  end
  return false
end

function Textbox:draw()
  local bounds = self.bounds
  local padding = theme.spacing.medium
  local body_font = fonts.get("body")
  local small_font = fonts.get("small")
  local text_x = bounds.x + padding
  local text_y = bounds.y + (bounds.height - body_font:getHeight()) / 2
  local box_x = bounds.x
  local box_y = bounds.y

  if bounds.alignment == "CENTRE" then
    text_x = text_x - bounds.width / 2
    text_y = text_y - bounds.height / 2
    box_x = box_x - bounds.width / 2
    box_y = box_y - bounds.height / 2
  end

  love.graphics.setColor(theme.colors.surface)
  love.graphics.rectangle("fill", box_x, box_y, bounds.width, bounds.height, theme.corner_radius, theme.corner_radius)
  love.graphics.setColor(self.has_focus and theme.colors.primary or theme.colors.outline)
  love.graphics.setLineWidth(OUTLINE_WIDTH)
  love.graphics.rectangle("line", box_x, box_y, bounds.width, bounds.height, theme.corner_radius, theme.corner_radius)

  love.graphics.setFont(body_font)
  if self.text == "" then
    love.graphics.setColor(theme.colors.text_dim)
    love.graphics.print(self.placeholder_text, text_x, text_y)
  else
    love.graphics.setColor(theme.colors.text)
    love.graphics.print(self.visible_text, text_x, text_y)
  end

  if not self.has_focus then
    return
  end

  if self.caret_blink_seconds < CARET_BLINK_PERIOD_SECONDS / 2 then
    local caret_x = text_x + body_font:getWidth(self.visible_text) + 1
    love.graphics.setColor(theme.colors.text)
    love.graphics.rectangle("fill", caret_x, text_y, CARET_WIDTH, body_font:getHeight())
  end

  local is_at_character_limit = utf8.len(self.text) >= self.maximum_character_count
  love.graphics.setColor(is_at_character_limit and theme.colors.danger or theme.colors.text_dim)
  love.graphics.setFont(small_font)
  love.graphics.printf(
    self.counter_text,
    bounds.x + bounds.width - padding - COUNTER_RESERVED_WIDTH,
    bounds.y + (bounds.height - small_font:getHeight()) / 2,
    COUNTER_RESERVED_WIDTH,
    "right"
  )
end

return Textbox