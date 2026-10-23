-- Base class for scenes. Subclasses (created with Scene.extend) override only the callbacks they need.
-- Scenes are singletons: reset all state in enter(). Set is_overlay = true to draw on top of the scene below.

local Scene = {}
Scene.__index = Scene

Scene.is_overlay = false

function Scene.extend()
  local subclass = {}
  subclass.__index = subclass
  return setmetatable(subclass, { __index = Scene })
end

function Scene:enter(context, ...) end

function Scene:leave(context) end

function Scene:pause(context) end

function Scene:resume(context) end

function Scene:update(delta_time_seconds) end

function Scene:draw() end

function Scene:pointerpressed(virtual_x, virtual_y, button_index, is_touch) end

function Scene:pointermoved(virtual_x, virtual_y, virtual_delta_x, virtual_delta_y, is_touch) end

function Scene:pointerreleased(virtual_x, virtual_y, button_index, is_touch) end

function Scene:keypressed(key, scancode, is_repeat) end

function Scene:textinput(text) end

-- Return true when the back action was handled; false lets the app quit.
function Scene:back()
  return false
end

return Scene
