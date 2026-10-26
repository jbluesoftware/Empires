-- Large on/off button drawn in a muted colour when off and a bright, outlined colour when on.
-- Toggles when the pointer is released inside its bounds and reports the new state through a callback.

local util = require("core.util")
local theme = require("ui.theme")

local ToggleButton = {}
ToggleButton.__index = ToggleButton

local ON_OUTLINE_WIDTH = 4
local PRESSED_SHADE_ALPHA = 0.18

-- bounds is a table with x, y, width and height in virtual coordinates.
function ToggleButton.new(bounds, muted_color, bright_color, on_toggled)
  return setmetatable({
    bounds = bounds,
    muted_color = muted_color,
    bright_color = bright_color,
    on_toggled = on_toggled,
    is_on = false,
    is_pressed = false,
  }, ToggleButton)
end

function ToggleButton:contains_point(virtual_x, virtual_y)
  local bounds = self.bounds
  return util.is_point_in_rectangle(virtual_x, virtual_y, bounds.x, bounds.y, bounds.width, bounds.height)
end

function ToggleButton:toggle()
  self.is_on = not self.is_on
  self.on_toggled(self.is_on)
end

function ToggleButton:pointerpressed(virtual_x, virtual_y)
  self.is_pressed = self:contains_point(virtual_x, virtual_y)
  return self.is_pressed
end

function ToggleButton:pointerreleased(virtual_x, virtual_y)
  local was_pressed = self.is_pressed
  self.is_pressed = false
  if was_pressed and self:contains_point(virtual_x, virtual_y) then
    self:toggle()
    return true
  end
  return false
end

function ToggleButton:draw()
  local bounds = self.bounds

  love.graphics.setColor(self.is_on and self.bright_color or self.muted_color)
  love.graphics.rectangle("fill", bounds.x, bounds.y, bounds.width, bounds.height, theme.corner_radius, theme.corner_radius)

  if self.is_on then
    love.graphics.setColor(theme.colors.text)
    love.graphics.setLineWidth(ON_OUTLINE_WIDTH)
    love.graphics.rectangle("line", bounds.x, bounds.y, bounds.width, bounds.height, theme.corner_radius, theme.corner_radius)
  end

  if self.is_pressed then
    love.graphics.setColor(0, 0, 0, PRESSED_SHADE_ALPHA)
    love.graphics.rectangle("fill", bounds.x, bounds.y, bounds.width, bounds.height, theme.corner_radius, theme.corner_radius)
  end
end

return ToggleButton
