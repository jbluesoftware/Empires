-- Tappable rectangular button: highlights while pressed and fires its callback
-- when the pointer is released inside its bounds.

local util = require("core.util")
local fonts = require("ui.fonts")
local theme = require("ui.theme")

local Button = {}
Button.__index = Button

-- bounds is a table with x, y, width and height in virtual coordinates.
function Button.new(label_text, bounds, on_activated)
  return setmetatable({
    label_text = label_text,
    bounds = bounds,
    on_activated = on_activated,
    is_pressed = false,
  }, Button)
end

function Button:contains_point(virtual_x, virtual_y)
  local bounds = self.bounds
  return util.is_point_in_rectangle(virtual_x, virtual_y, bounds.x, bounds.y, bounds.width, bounds.height)
end

function Button:pointerpressed(virtual_x, virtual_y)
  self.is_pressed = self:contains_point(virtual_x, virtual_y)
  return self.is_pressed
end

function Button:pointerreleased(virtual_x, virtual_y)
  local was_pressed = self.is_pressed
  self.is_pressed = false
  if was_pressed and self:contains_point(virtual_x, virtual_y) then
    self.on_activated()
    return true
  end
  return false
end

function Button:draw()
  local bounds = self.bounds
  local body_font = fonts.get("body")

  love.graphics.setColor(self.is_pressed and theme.colors.primary_pressed or theme.colors.primary)
  love.graphics.rectangle("fill", bounds.x, bounds.y, bounds.width, bounds.height, theme.corner_radius, theme.corner_radius)

  love.graphics.setColor(theme.colors.text)
  love.graphics.setFont(body_font)
  local label_y = bounds.y + (bounds.height - body_font:getHeight()) / 2
  love.graphics.printf(self.label_text, bounds.x, label_y, bounds.width, "center")
end

return Button
