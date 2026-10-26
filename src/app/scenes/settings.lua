-- Settings scene (placeholder): will hold user preferences backed by app/settings.lua.

local Scene = require("core.scene")
local Button = require("ui.widgets.button")
local fonts = require("ui.fonts")
local theme = require("ui.theme")

local TITLE_VERTICAL_POSITION = 160

local SettingsScene = Scene.extend()

function SettingsScene:enter(context)
  self.context = context
  self.virtual_width = context.screen.get_size()

  local safe_left, _, safe_right, safe_bottom = context.screen.safe_area()
  self.back_button = Button.new("Back", {
    x = safe_left + theme.spacing.large,
    y = safe_bottom - theme.button_height - theme.spacing.large,
    width = safe_right - safe_left - theme.spacing.large * 2,
    height = theme.button_height,
  }, function()
    context.scenes.switch("menu")
  end)
end

function SettingsScene:draw()
  love.graphics.setColor(theme.colors.text)
  love.graphics.setFont(fonts.get("title"))
  love.graphics.printf("Settings", 0, TITLE_VERTICAL_POSITION, self.virtual_width, "center")
  self.back_button:draw()
end

function SettingsScene:pointerpressed(virtual_x, virtual_y)
  self.back_button:pointerpressed(virtual_x, virtual_y)
end

function SettingsScene:pointerreleased(virtual_x, virtual_y)
  self.back_button:pointerreleased(virtual_x, virtual_y)
end

function SettingsScene:back()
  self.context.scenes.switch("menu")
  return true
end

return SettingsScene
