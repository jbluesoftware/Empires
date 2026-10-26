-- Application bootstrap: initialises modules in dependency order, builds the shared context,
-- registers scenes and opens the first one (the menu, or a scene named by the first launch argument).
-- Desktop testing: `love src play 1` and `love src play 2` open two side-by-side windows straight into Play.

local config = require("app.config")
local settings = require("app.settings")
local events = require("core.events")
local input = require("core.input")
local log = require("core.log")
local scene_manager = require("core.scene_manager")
local screen = require("core.screen")
local fonts = require("ui.fonts")
local theme = require("ui.theme")

local M = {}

local SCENE_MODULE_NAMES_BY_SCENE_NAME = {
  menu = "app.scenes.menu",
  play = "app.scenes.play",
  settings = "app.scenes.settings",
}

local DESKTOP_WINDOW_SLOT_SPACING_PIXELS = 420

-- Places numbered launch windows side by side: slot 1 left of the default position, slot 2 right of it.
local function arrange_desktop_test_window(launch_scene_name, window_slot_number)
  love.window.setTitle(string.format("%s (%s %d)", config.APP_NAME, launch_scene_name, window_slot_number))
  local window_x, window_y, display_index = love.window.getPosition()
  local horizontal_offset = (window_slot_number - 1.5) * DESKTOP_WINDOW_SLOT_SPACING_PIXELS
  love.window.setPosition(window_x + horizontal_offset, window_y, display_index)
end

function M.initialise(command_line_arguments)
  log.set_minimum_level(config.LOG_LEVEL)
  love.graphics.setDefaultFilter("linear", "linear")

  screen.init(config.VIRTUAL_WIDTH, config.VIRTUAL_HEIGHT)
  settings.load()

  local launch_scene_name = command_line_arguments and command_line_arguments[1]
  local window_slot_number = tonumber(command_line_arguments and command_line_arguments[2])

  local context = {
    config = config,
    events = events,
    screen = screen,
    input = input,
    scenes = scene_manager,
    theme = theme,
    fonts = fonts,
    settings = settings,
    devtools = nil,
  }

  if config.DEV then
    local was_loaded, devtools = pcall(require, "core.devtools")
    if was_loaded then
      devtools.initialise()
      context.devtools = devtools
    end
  end

  scene_manager.init(context)
  input.set_receiver(scene_manager)
  for scene_name, module_name in pairs(SCENE_MODULE_NAMES_BY_SCENE_NAME) do
    scene_manager.register(scene_name, require(module_name))
  end

  local has_valid_launch_scene = SCENE_MODULE_NAMES_BY_SCENE_NAME[launch_scene_name] ~= nil
  if has_valid_launch_scene and window_slot_number and not config.IS_MOBILE then
    arrange_desktop_test_window(launch_scene_name, window_slot_number)
  end
  scene_manager.switch(has_valid_launch_scene and launch_scene_name or "menu")

  return context
end

return M
