-- Minimal publish/subscribe bus for cross-layer notifications (app suspend/resume, low memory, quit).
-- Use sparingly: prefer direct calls where one module clearly owns another.

local M = {}

M.APP_SUSPENDED = "app.suspended"
M.APP_RESUMED = "app.resumed"
M.APP_FOCUS_CHANGED = "app.focus_changed"
M.APP_LOW_MEMORY = "app.low_memory"
M.APP_QUIT = "app.quit"

local listeners_by_event_name = {}

function M.on(event_name, listener)
  local listeners = listeners_by_event_name[event_name]
  if not listeners then
    listeners = {}
    listeners_by_event_name[event_name] = listeners
  end
  listeners[#listeners + 1] = listener
  return listener
end

function M.off(event_name, listener)
  local listeners = listeners_by_event_name[event_name]
  if not listeners then
    return
  end
  for listener_index = #listeners, 1, -1 do
    if listeners[listener_index] == listener then
      table.remove(listeners, listener_index)
    end
  end
end

-- Iterates over a snapshot so listeners may unsubscribe while the event is being emitted.
function M.emit(event_name, ...)
  local listeners = listeners_by_event_name[event_name]
  if not listeners then
    return
  end
  local listener_snapshot = {}
  for listener_index = 1, #listeners do
    listener_snapshot[listener_index] = listeners[listener_index]
  end
  for listener_index = 1, #listener_snapshot do
    listener_snapshot[listener_index](...)
  end
end

return M
