-- Normalises mouse, touch and keyboard events into virtual-coordinate pointer events and semantic actions.
-- Touches arrive as emulated mouse events, so one set of handlers covers both.
-- The Escape key (also the Android back button) becomes a "back" action; unhandled back quits the app.

local screen = require("core.screen")

local M = {}

local scene_receiver

-- The receiver must expose dispatch(event_name, ...) and return true when the event was handled.
function M.set_receiver(receiver)
  scene_receiver = receiver
end

local function dispatch(event_name, ...)
  if scene_receiver then
    return scene_receiver.dispatch(event_name, ...)
  end
end

function M.on_mouse_pressed(window_x, window_y, button_index, is_touch)
  local virtual_x, virtual_y = screen.to_virtual(window_x, window_y)
  dispatch("pointerpressed", virtual_x, virtual_y, button_index, is_touch)
end

function M.on_mouse_moved(window_x, window_y, window_delta_x, window_delta_y, is_touch)
  local virtual_x, virtual_y = screen.to_virtual(window_x, window_y)
  local scale_factor = screen.get_scale()
  dispatch("pointermoved", virtual_x, virtual_y, window_delta_x / scale_factor, window_delta_y / scale_factor, is_touch)
end

function M.on_mouse_released(window_x, window_y, button_index, is_touch)
  local virtual_x, virtual_y = screen.to_virtual(window_x, window_y)
  dispatch("pointerreleased", virtual_x, virtual_y, button_index, is_touch)
end

function M.on_key_pressed(key, scancode, is_repeat)
  if key == "escape" then
    if not dispatch("back") then
      love.event.quit()
    end
    return
  end
  dispatch("keypressed", key, scancode, is_repeat)
end

function M.on_text_input(text)
  dispatch("textinput", text)
end

function M.is_key_down(...)
  return love.keyboard.isDown(...)
end

return M
