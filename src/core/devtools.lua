-- Development-only tools: lurker hot reload, Cmd/Ctrl+R restart and an F3 FPS/memory overlay.
-- Excluded from release builds; boot only loads it when config.DEV is true.

local log = require("core.log").new("devtools")

local M = {}

local hot_reloader
local overlay_font
local is_overlay_visible = false

function M.initialise()
  local was_loaded, loaded_module = pcall(require, "lib.lurker")
  if was_loaded then
    hot_reloader = loaded_module
  else
    log.warn("hot reload unavailable: %s", tostring(loaded_module))
  end
end

function M.update()
  if hot_reloader then
    hot_reloader.update()
  end
end

-- Returns true when the key was consumed.
function M.handle_key_pressed(key)
  local is_modifier_down = love.keyboard.isDown("lgui", "rgui", "lctrl", "rctrl")
  if key == "r" and is_modifier_down then
    love.event.quit("restart")
    return true
  end
  if key == "f3" then
    is_overlay_visible = not is_overlay_visible
    return true
  end
  return false
end

-- Drawn in window coordinates, after the virtual canvas has been closed.
function M.draw_overlay()
  if not is_overlay_visible then
    return
  end
  overlay_font = overlay_font or love.graphics.newFont(12)
  love.graphics.push("all")
  love.graphics.setFont(overlay_font)
  love.graphics.setColor(1, 1, 0, 1)
  love.graphics.print(
    string.format("%d FPS  %d KB", love.timer.getFPS(), math.floor(collectgarbage("count"))),
    8,
    8
  )
  love.graphics.pop()
end

return M
