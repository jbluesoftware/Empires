-- LÖVE configuration, run before any module loads: window setup and disabled engine modules.
-- Keep this file free of require() calls; the module system is not ready yet.

function love.conf(settings)
  settings.identity = "lanapp"
  settings.version = "11.5"
  settings.console = false

  settings.window.title = "LAN App"
  settings.window.width = 390
  settings.window.height = 844
  settings.window.resizable = true
  settings.window.highdpi = true

  settings.modules.physics = false
  settings.modules.video = false
end
