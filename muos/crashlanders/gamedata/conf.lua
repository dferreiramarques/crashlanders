function love.conf(t)
  t.identity = "crashlanders"
  t.version = "11.5"
  t.window.title = "CRASHLANDERS"
  t.window.width = 640          -- RG35XX H native resolution
  t.window.height = 480
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
end
