-- The only place love.* callbacks are assigned. Each handler forwards to the module that owns the behaviour.
-- Handlers look modules up at call time (no captured function references) so hot reload keeps working.

local events = require("core.events")

local M = {}

function M.install(context)
  local screen = context.screen
  local input = context.input
  local scene_manager = context.scenes
  local theme = context.theme
  local fonts = context.fonts
  local devtools = context.devtools

  function love.update(delta_time_seconds)
    if devtools then
      devtools.update()
    end
    scene_manager.update(delta_time_seconds)
  end

  function love.draw()
    love.graphics.clear(theme.colors.letterbox)
    screen.begin_drawing()
    love.graphics.setColor(theme.colors.background)
    love.graphics.rectangle("fill", 0, 0, screen.get_size())
    love.graphics.setColor(1, 1, 1, 1)
    scene_manager.draw()
    screen.end_drawing()
    if devtools then
      devtools.draw_overlay()
    end
  end

  function love.resize()
    screen.resize()
    fonts.clear_cache()
  end

  function love.mousepressed(...)
    input.on_mouse_pressed(...)
  end

  function love.mousemoved(...)
    input.on_mouse_moved(...)
  end

  function love.mousereleased(...)
    input.on_mouse_released(...)
  end

  function love.keypressed(key, scancode, is_repeat)
    if devtools and devtools.handle_key_pressed(key) then
      return
    end
    input.on_key_pressed(key, scancode, is_repeat)
  end

  function love.textinput(text)
    input.on_text_input(text)
  end

  function love.visible(is_visible)
    events.emit(is_visible and events.APP_RESUMED or events.APP_SUSPENDED)
  end

  function love.focus(is_focused)
    events.emit(events.APP_FOCUS_CHANGED, is_focused)
  end

  function love.lowmemory()
    events.emit(events.APP_LOW_MEMORY)
    collectgarbage()
  end

  function love.quit()
    scene_manager.clear()
    events.emit(events.APP_QUIT)
    return false
  end
end

return M
