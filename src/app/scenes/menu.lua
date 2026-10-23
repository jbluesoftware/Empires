-- Main menu scene: lets the user choose between hosting a session and joining one.

local Scene = require("core.scene")
local Button = require("ui.widgets.button")
local fonts = require("ui.fonts")
local theme = require("ui.theme")

local TITLE_VERTICAL_POSITION = 160
local FIRST_BUTTON_VERTICAL_POSITION = 340

local MenuScene = Scene.extend()

function MenuScene:enter(context)
  self.context = context
  self.virtual_width = context.screen.get_size()

  local button_width = self.virtual_width - theme.spacing.large * 2
  local button_x = theme.spacing.large

  self.buttons = {
    Button.new(
      "Host a session",
      { x = button_x, y = FIRST_BUTTON_VERTICAL_POSITION, width = button_width, height = theme.button_height },
      function()
        context.scenes.switch("host")
      end
    ),
    Button.new(
      "Join a session",
      {
        x = button_x,
        y = FIRST_BUTTON_VERTICAL_POSITION + theme.button_height + theme.spacing.medium,
        width = button_width,
        height = theme.button_height,
      },
      function()
        context.scenes.switch("client")
      end
    ),
  }
end

function MenuScene:draw()
  love.graphics.setColor(theme.colors.text)
  love.graphics.setFont(fonts.get("title"))
  love.graphics.printf(self.context.config.APP_NAME, 0, TITLE_VERTICAL_POSITION, self.virtual_width, "center")

  for _, button in ipairs(self.buttons) do
    button:draw()
  end
end

function MenuScene:pointerpressed(virtual_x, virtual_y)
  for _, button in ipairs(self.buttons) do
    button:pointerpressed(virtual_x, virtual_y)
  end
end

function MenuScene:pointerreleased(virtual_x, virtual_y)
  for _, button in ipairs(self.buttons) do
    button:pointerreleased(virtual_x, virtual_y)
  end
end

return MenuScene
