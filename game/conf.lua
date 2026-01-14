function love.conf(t)
    t.identity = "bounce-arena"
    t.version = "11.4"
    t.console = false

    t.window.title = "Bounce Arena"
    t.window.width = 800
    t.window.height = 600
    t.window.resizable = false
    t.window.vsync = 1

    t.modules.joystick = false
    t.modules.physics = false
end
