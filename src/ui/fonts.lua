-- Lazily creates and caches fonts by role (title, body, small), rasterised at the current
-- screen scale and display density so text stays sharp. The cache is cleared on window resize.

local screen = require("core.screen")
local theme = require("ui.theme")

local M = {}

local cached_fonts_by_role = {}

function M.get(role_name)
  local cached_font = cached_fonts_by_role[role_name]
  if cached_font then
    return cached_font
  end

  local font_size = theme.font_sizes[role_name] or error("unknown font role: " .. tostring(role_name), 2)
  local raster_density = love.graphics.getDPIScale() * screen.get_scale()
  local new_font = love.graphics.newFont(font_size, "normal", raster_density)
  cached_fonts_by_role[role_name] = new_font
  return new_font
end

function M.clear_cache()
  cached_fonts_by_role = {}
end

return M
