-- Client scene (placeholder): will discover hosts on the local network and connect to one.

local Scene = require("core.scene")
local Button = require("ui.widgets.button")
local fonts = require("ui.fonts")
local theme = require("ui.theme")

local TITLE_VERTICAL_POSITION = 160

local ClientScene = Scene.extend()

function ClientScene:enter(context)
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

function ClientScene:draw()
  love.graphics.setColor(theme.colors.text)
  love.graphics.setFont(fonts.get("title"))
  love.graphics.printf("Join", 0, TITLE_VERTICAL_POSITION, self.virtual_width, "center")
  self.back_button:draw()
end

function ClientScene:pointerpressed(virtual_x, virtual_y)
  self.back_button:pointerpressed(virtual_x, virtual_y)
end

function ClientScene:pointerreleased(virtual_x, virtual_y)
  self.back_button:pointerreleased(virtual_x, virtual_y)
end

function ClientScene:back()
  self.context.scenes.switch("menu")
  return true
end

return ClientScene
