-- Draws a round indicator light that glows with the additive mix of its red, green and blue channels.
-- All channels off renders a dark, unlit light.

local theme = require("ui.theme")

local Light = {}

local GLOW_RADIUS_MULTIPLIER = 1.4
local GLOW_ALPHA = 0.25
local OUTLINE_WIDTH = 2

-- lights is a table with boolean red, green and blue fields.
function Light.draw(center_x, center_y, radius, lights)
  local red_level = lights.red and 1 or 0
  local green_level = lights.green and 1 or 0
  local blue_level = lights.blue and 1 or 0
  local is_lit = lights.red or lights.green or lights.blue

  if is_lit then
    love.graphics.setColor(red_level, green_level, blue_level, GLOW_ALPHA)
    love.graphics.circle("fill", center_x, center_y, radius * GLOW_RADIUS_MULTIPLIER)
    love.graphics.setColor(red_level, green_level, blue_level, 1)
  else
    love.graphics.setColor(theme.colors.light_off)
  end
  love.graphics.circle("fill", center_x, center_y, radius)

  love.graphics.setColor(theme.colors.light_outline)
  love.graphics.setLineWidth(OUTLINE_WIDTH)
  love.graphics.circle("line", center_x, center_y, radius)
end

return Light
