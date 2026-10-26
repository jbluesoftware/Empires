-- Single source of truth for styling: colours by role, spacing, corner radius and font sizes.
-- Sizes are in virtual units (see core/screen.lua).

local util = require("core.util")

return util.freeze({
  colors = {
    letterbox = { 0.02, 0.02, 0.03, 1 },
    background = { 0.09, 0.10, 0.13, 1 },
    surface = { 0.14, 0.16, 0.20, 1 },
    outline = { 0.30, 0.32, 0.38, 1 },
    primary = { 0.20, 0.45, 0.90, 1 },
    primary_pressed = { 0.15, 0.35, 0.75, 1 },
    text = { 1, 1, 1, 1 },
    text_dim = { 0.65, 0.68, 0.75, 1 },
    danger = { 0.90, 0.30, 0.30, 1 },
    success = { 0.30, 0.80, 0.45, 1 },

    light_off = { 0.16, 0.17, 0.21, 1 },
    light_outline = { 0.30, 0.32, 0.38, 1 },
    red_muted = { 0.34, 0.10, 0.10, 1 },
    red_bright = { 1.00, 0.20, 0.20, 1 },
    green_muted = { 0.10, 0.30, 0.13, 1 },
    green_bright = { 0.20, 1.00, 0.35, 1 },
    blue_muted = { 0.10, 0.14, 0.38, 1 },
    blue_bright = { 0.28, 0.45, 1.00, 1 },
  },

  spacing = {
    small = 8,
    medium = 16,
    large = 32,
  },

  corner_radius = 12,
  button_height = 64,

  font_sizes = {
    title = 34,
    body = 20,
    small = 14,
  },
})