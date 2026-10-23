-- Virtual resolution: fits a fixed-size canvas into any window, converts window coordinates
-- to virtual coordinates and reports the device safe area (notches, rounded corners).

local util = require("core.util")

local M = {}

local virtual_width = 0
local virtual_height = 0
local scale_factor = 1
local letterbox_offset_x = 0
local letterbox_offset_y = 0

function M.resize()
  local window_width, window_height = love.graphics.getDimensions()
  scale_factor = math.min(window_width / virtual_width, window_height / virtual_height)
  letterbox_offset_x = (window_width - virtual_width * scale_factor) / 2
  letterbox_offset_y = (window_height - virtual_height * scale_factor) / 2
end

function M.init(width, height)
  virtual_width = width
  virtual_height = height
  M.resize()
end

function M.get_size()
  return virtual_width, virtual_height
end

function M.get_scale()
  return scale_factor
end

function M.to_virtual(window_x, window_y)
  return (window_x - letterbox_offset_x) / scale_factor, (window_y - letterbox_offset_y) / scale_factor
end

-- Returns left, top, right, bottom in virtual coordinates.
function M.safe_area()
  local safe_x, safe_y, safe_width, safe_height = love.window.getSafeArea()
  local left, top = M.to_virtual(safe_x, safe_y)
  local right, bottom = M.to_virtual(safe_x + safe_width, safe_y + safe_height)
  return util.clamp(left, 0, virtual_width),
    util.clamp(top, 0, virtual_height),
    util.clamp(right, 0, virtual_width),
    util.clamp(bottom, 0, virtual_height)
end

function M.begin_drawing()
  love.graphics.setScissor(letterbox_offset_x, letterbox_offset_y, virtual_width * scale_factor, virtual_height * scale_factor)
  love.graphics.push()
  love.graphics.translate(letterbox_offset_x, letterbox_offset_y)
  love.graphics.scale(scale_factor)
end

function M.end_drawing()
  love.graphics.pop()
  love.graphics.setScissor()
end

return M
