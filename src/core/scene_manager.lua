-- Scene stack: switch (replace everything), push/pop (overlays), lifecycle calls and event forwarding.
-- Only the top scene updates and receives input; overlay scenes also draw the scenes beneath them.

local M = {}

local registered_scenes_by_name = {}
local scene_stack = {}
local application_context

local function find_registered_scene(scene_name)
  return registered_scenes_by_name[scene_name] or error("unknown scene: " .. tostring(scene_name), 3)
end

function M.init(context)
  application_context = context
end

function M.register(scene_name, scene)
  registered_scenes_by_name[scene_name] = scene
end

function M.clear()
  for stack_index = #scene_stack, 1, -1 do
    scene_stack[stack_index]:leave(application_context)
    scene_stack[stack_index] = nil
  end
end

function M.switch(scene_name, ...)
  local next_scene = find_registered_scene(scene_name)
  M.clear()
  scene_stack[1] = next_scene
  next_scene:enter(application_context, ...)
end

function M.push(scene_name, ...)
  local overlay_scene = find_registered_scene(scene_name)
  local covered_scene = scene_stack[#scene_stack]
  if covered_scene then
    covered_scene:pause(application_context)
  end
  scene_stack[#scene_stack + 1] = overlay_scene
  overlay_scene:enter(application_context, ...)
end

function M.pop()
  local top_scene = scene_stack[#scene_stack]
  if not top_scene then
    return
  end
  top_scene:leave(application_context)
  scene_stack[#scene_stack] = nil
  local revealed_scene = scene_stack[#scene_stack]
  if revealed_scene then
    revealed_scene:resume(application_context)
  end
end

function M.current()
  return scene_stack[#scene_stack]
end

function M.depth()
  return #scene_stack
end

function M.update(delta_time_seconds)
  local top_scene = scene_stack[#scene_stack]
  if top_scene then
    top_scene:update(delta_time_seconds)
  end
end

function M.draw()
  local first_visible_index = #scene_stack
  while first_visible_index > 1 and scene_stack[first_visible_index].is_overlay do
    first_visible_index = first_visible_index - 1
  end
  for stack_index = math.max(1, first_visible_index), #scene_stack do
    scene_stack[stack_index]:draw()
  end
end

-- Calls the named method on the top scene and returns its result.
function M.dispatch(event_name, ...)
  local top_scene = scene_stack[#scene_stack]
  if top_scene and top_scene[event_name] then
    return top_scene[event_name](top_scene, ...)
  end
end

return M
