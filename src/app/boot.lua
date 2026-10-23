-- Application bootstrap: initialises modules in dependency order, builds the shared context,
-- registers scenes and opens the first one (menu, or host/client when passed as a launch argument).

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
  host = "app.scenes.host",
  client = "app.scenes.client",
}

local LAUNCH_SCENE_NAMES_BY_MODE = {
  host = "host",
  client = "client",
}

local DESKTOP_TEST_WINDOW_OFFSET_PIXELS = 230

-- Lets a host window and a client window sit side by side when both are launched on one desktop.
local function arrange_desktop_test_window(launch_mode)
  love.window.setTitle(string.format("%s (%s)", config.APP_NAME, launch_mode))
  local window_x, window_y, display_index = love.window.getPosition()
  local horizontal_offset = launch_mode == "client" and DESKTOP_TEST_WINDOW_OFFSET_PIXELS or -DESKTOP_TEST_WINDOW_OFFSET_PIXELS
  love.window.setPosition(window_x + horizontal_offset, window_y, display_index)
end

function M.initialise(command_line_arguments)
  log.set_minimum_level(config.LOG_LEVEL)
  love.graphics.setDefaultFilter("linear", "linear")

  screen.init(config.VIRTUAL_WIDTH, config.VIRTUAL_HEIGHT)
  settings.load()

  local launch_mode = command_line_arguments and command_line_arguments[1]

  local context = {
    config = config,
    events = events,
    screen = screen,
    input = input,
    scenes = scene_manager,
    theme = theme,
    fonts = fonts,
    settings = settings,
    launch_mode = launch_mode,
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

  local launch_scene_name = LAUNCH_SCENE_NAMES_BY_MODE[launch_mode]
  if launch_scene_name and not config.IS_MOBILE then
    arrange_desktop_test_window(launch_mode)
  end
  scene_manager.switch(launch_scene_name or "menu")

  return context
end

return M
