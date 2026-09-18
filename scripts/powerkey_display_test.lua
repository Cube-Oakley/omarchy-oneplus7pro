-- Temporary live test: hyprctl eval 'dofile("/tmp/powerkey_display_test.lua")'.
-- Reloading Hyprland's normal config removes this binding.
-- Wake is retried automatically after 20 seconds during this test only.
hl.bind("XF86PowerOff", hl.dsp.exec_cmd([[python3 /tmp/test_display_power.py --recover >> /tmp/powerkey-display.log 2>&1 &
sleep 0.15
hyprctl eval 'hl.dispatch(hl.dsp.dpms({ action = "toggle" }))' >> /tmp/powerkey-display.log 2>&1
]]), { release = true, locked = true, description = "Temporary phone display toggle test" })
