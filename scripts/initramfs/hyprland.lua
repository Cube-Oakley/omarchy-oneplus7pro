hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 20,
        border_size = 2,
        layout      = "dwindle",
        col = {
            active_border   = { colors = {"rgba(7aa2f7ee)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
    },
    decoration = {
        rounding = 0,
        shadow   = { enabled = false },
        blur     = { enabled = false },
    },
    animations = {
        enabled = false,
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        disable_watchdog_warning = true,
        background_color         = "0x111111",
    },
    cursor = {
        invisible          = true,
        no_hardware_cursors = 1,
    },
})

local mainMod = "SUPER"
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("foot"))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
