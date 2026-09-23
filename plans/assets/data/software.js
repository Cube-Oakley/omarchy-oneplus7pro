/* ==========================================================================
   SOFTWARE page data
   ========================================================================== */
PAGE_SOFTWARE = {
  id: "software",
  nav: "Software",
  cardBlurb: "What you actually touch: the shell, the surfaces, the apps we have to build, and the agent "
           + "layer that makes the whole thing reprogrammable.",
  eyebrow: "Project plan · Software",
  title: "Software",
  blurb: "The Omarchy mobile shell and everything that has to exist for this to be a phone rather than a "
       + "small Linux desktop. Shared shell work lives in overlay/mobile/, OnePlus-specific adaptation in "
       + "devices/oneplus7pro/.",

  sections: [
    {
      id: "ui",
      title: "Main UI",
      blurb: "The always-present surfaces: bar, shade, launcher, overview, keyboard, gestures.",
      items: [
        { n: "Status bar", s: "ok",
          note: "Battery percentage with charging bolt, Wi-Fi signal, and a compact CPU/RAM chip. Event-driven "
              + "battery/Wi-Fi; the CPU/RAM chip reads /proc in the shell every 3 s. The full performance "
              + "snapshot runs only while its shade page is open.",
          ref: "docs/smoothness-20260923.md" },
        { n: "Notification shade (pull-down)", s: "ok",
          note: "Drag-down panel with themed detail popups, grouped notifications, heads-up toasts, Wi-Fi/mute/DND "
              + "toggles, battery metrics, Wi-Fi scan and connect, calendar, opt-in weather. Swipe up to close.",
          ref: "docs/shell-controls-20260918.md" },
        { n: "App launcher / drawer", s: "ok",
          note: "Touch launcher on desktop entries; launching through the drawer verified for both installed apps.",
          ref: "docs/keyboard-browser-20260918.md" },
        { n: "Workspace & window overview", s: "ok",
          note: "Card switcher with previews, tap to open, drag onto a card to tile. The swipe up follows the "
              + "finger from the first frame (a recent screen copy, taken only while the phone is in use); "
              + "thumbnails stop copying once taken, and opening another app no longer rebuilds the cards "
              + "mid-animation. Periodic status and theme polling no longer stalls it.",
          ref: "docs/smoothness-20260923.md" },
        { n: "Bottom-edge gesture navigation", s: "ok",
          note: "Left = launcher, centre = overview, right = keyboard; finger-tracked sheets with swipe-down "
              + "dismissal. User-confirmed.", ref: "docs/mobile-gestures-20260917.md" },
        { n: "On-screen keyboard", s: "ok",
          note: "Gesture activation, explicit-tap popup input, swipe-down handle to hide, no duplicate surfaces.",
          ref: "docs/keyboard-browser-20260918.md" },
        { n: "Mobile scaling & tiled windows", s: "ok",
          note: "Scale appropriate to 1440 × 3120; multiple tiled app windows coexist with the shell surfaces." },
        { n: "Notification actions, grouping and dismissal", s: "partial",
          note: "Cards group by app, with expand, per-item and group dismiss, actions, and heads-up toasts. No "
              + "persistent history, lock-screen notifications or banners after reboot.",
          ref: "docs/shell-controls-20260918.md" },
        { n: "Quick-setting toggles (brightness, Bluetooth, DND…)", s: "partial",
          note: "Wi-Fi radio, Bluetooth, mute and Do Not Disturb are in the shade; Bluetooth starts its stack "
              + "when needed. Brightness and flashlight wait on hardware.", ref: "docs/bluetooth-20260922.md" },
        { n: "Performance panel", s: "ok",
          note: "CPU/RAM chip opens CPU, memory, load, thermal zones, battery draw and top CPU processes. Process "
              + "ranking is CPU time, not milliwatts.",
          ref: "docs/shell-controls-20260918.md" },
        { n: "Weather tile", s: "partial",
          note: "Icons, weekday names and a five-day forecast are installed; location still unset on the handset.",
          ref: "docs/shell-controls-20260918.md" },
        { n: "New Wi-Fi network entry (password)", s: "partial",
          note: "Saved-network activation and HTTPS verified; entering a password for a new network is untested.",
          ref: "docs/notification-shade-20260918.md" },
        { n: "Copy / paste and touch text selection", s: "partial",
          note: "Shell text fields long-press to select, with handles and Copy/Paste/All. Password fields do not "
              + "copy. Kitty long-press selection is in the touch patch but needs a glfw rebuild. Chromium "
              + "selection is unchanged. Desktop sync is not enabled.",
          ref: "docs/settings-clipboard-20260919.md" },
        { n: "Touch window resize / move", s: "no", note: "Not implemented." },
        { n: "Auto-rotate", s: "no", note: "Depends on the accelerometer and a sensor service; nothing yet." },
        { n: "Lock screen, PIN / biometric unlock", s: "no", note: "Not implemented.",
          ref: "docs/mobile-architecture.md" }
      ]
    },

    {
      id: "settings",
      title: "Settings & configuration",
      blurb: "Theme and preference plumbing works; there is no settings application yet. The panel list below "
           + "is the scope that app has to cover.",
      groups: [
        {
          title: "Working today",
          items: [
            { n: "Theme selection (Omarchy palettes)", s: "ok",
              note: "Standard Omarchy theme colours apply across the shell, Kitty and keyboard. A theme picked in "
                  + "Settings reaches the shell at once (it watches the palette file); changes made outside the "
                  + "shell are picked up within 30 s.",
              ref: "docs/mobile-architecture.md" },
            { n: "Wallpaper preview, cycling and per-theme choice", s: "ok",
              note: "92 stock images; the chosen wallpaper survives shell restart.",
              ref: "docs/wallpaper-switching-20260917.md" },
            { n: "Font handling", s: "ok",
              note: "JetBrainsMono Nerd Font is the default; Appearance in Settings can pick another installed family.",
              ref: "docs/settings-clipboard-20260919.md" },
            { n: "Battery detail view", s: "ok",
              note: "Percentage, charge/current direction, voltage and temperature distinguished from input "
                  + "current.", ref: "docs/notification-shade-20260918.md" },
            { n: "Volume UI and output routing", s: "partial",
              note: "Android-style panel: the keys change media volume, and an expand button reveals "
                  + "notification, alarm and call volumes as draggable sliders; a tap outside closes it. "
                  + "Connected Bluetooth headphones take over the output with their own volume, which their "
                  + "buttons also drive; the speaker level returns when they leave. No manual output picker.",
              ref: "docs/bluetooth-20260922.md" },
            { n: "Choices survive reboot", s: "partial",
              note: "Keyboard, audio and desktop auto-start after reboot is verified; the shade's session-bus "
                  + "startup after reboot is not yet tested.", ref: "docs/status.md" }
          ]
        },
        {
          title: "Settings app (to build)",
          note: "Settings exists as a themed app. Rows below are remaining panels.",
          items: [
            { n: "Settings application", s: "partial",
              note: "Appearance, Network/Wi-Fi, Sound, Battery, About, clipboard and DND. Shade still has the "
                  + "quick toggles. Searchable panels are still ahead.",
              ref: "docs/settings-panels-20260919.md" },
            { n: "Panel — Network & Wi-Fi", s: "partial",
              note: "Settings Wi-Fi page plus shade picker. Static DNS and forget are installed. Cellular/VPN/"
                  + "hotspot are not. Speed test is HTTP throughput to Cloudflare.",
              ref: "docs/network-speedtest-20260919.md" },
            { n: "Panel — Display & brightness", s: "partial",
              note: "Settings Display shows the monitor mode. Brightness is read when a backlight exists and is "
                  + "not changed. Corners are toggled from Appearance.",
              ref: "docs/mobile-architecture.md" },
            { n: "Panel — Sound & output routing", s: "partial",
              note: "Settings Sound and the OSD share the PipeWire volume helper. The OSD's four volume groups "
                  + "are not in Settings yet; no device picker or per-app routing.",
              ref: "docs/settings-panels-20260919.md" },
            { n: "Panel — Battery & charging", s: "partial",
              note: "Settings Battery shows the same sysfs metrics as the shade. Charge policy is not user-settable.",
              ref: "docs/settings-panels-20260919.md" },
            { n: "Panel — Appearance & theme", s: "ok",
              note: "Theme, wallpaper and font live in the Settings app.",
              ref: "docs/settings-clipboard-20260919.md" },
            { n: "Panel — Bluetooth & devices", s: "partial",
              note: "Settings Bluetooth powers the radio, scans, pairs, connects, disconnects and forgets; "
                  + "headphones pair and play. Devices that ask for a PIN (most keyboards) cannot pair yet.",
              ref: "docs/bluetooth-20260922.md" },
            { n: "Panel — SIM & cellular", s: "no", note: "Blocked behind modem bring-up.",
              ref: "docs/modem-foundations-20260917.md" },
            { n: "Panel — Security, lock screen & fingerprint", s: "no",
              note: "Covers credential enrollment and the fingerprint reader, neither of which is enabled.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Panel — Apps & permissions", s: "partial",
              note: "Settings Apps lists installed mobile apps and can revoke a granted permission. There is "
                  + "still no process sandbox.",
              ref: "docs/mobile-architecture.md" },
            { n: "Panel — Storage", s: "partial",
              note: "Settings Storage shows free and used space. Deleting files is done in the Files app.",
              ref: "docs/settings-panels-20260919.md" },
            { n: "Panel — Location & sensors", s: "no",
              note: "Sensor permissions for apps, GPS toggles, calibration state.", ref: "docs/pathway.md" },
            { n: "Panel — Accessibility", s: "no",
              note: "Text size, contrast, screen reader hooks. Cheap to design in early, expensive to bolt on "
                  + "later.", ref: "docs/mobile-roadmap.md" },
            { n: "Panel — About, updates & recovery", s: "partial",
              note: "Settings About shows hostname, OS, kernel, slot and latest installer backup, with a copyable "
                  + "report. Updates and rollback UI are not started.",
              ref: "docs/settings-panels-20260919.md" }
          ]
        },
        {
          title: "Preferences plumbing",
          items: [
            { n: "Unified persistent preferences surface", s: "partial",
              note: "dnd and fontFamily share prefs.json; weather, wallpaper and audio autostart are still "
                  + "separate files.", ref: "docs/settings-clipboard-20260919.md" },
            { n: "Themed font picker", s: "ok",
              note: "Settings → Appearance lists installed families and applies them through the theme helper.",
              ref: "docs/settings-clipboard-20260919.md" },
            { n: "Full Omarchy theme-repository install", s: "no",
              note: "The bundled theme set works; installing upstream themes as a set is still future work.",
              ref: "docs/mobile-architecture.md" },
            { n: "Status-bar indicator preferences", s: "no",
              note: "Show/hide battery percentage and indicator choice are hardcoded today.",
              ref: "docs/mobile-roadmap.md" }
          ]
        }
      ]
    },

    {
      id: "apps",
      title: "Apps",
      blurb: "Open by design. Desktop Omarchy apps are keyboard-and-mouse shaped, so the phone needs "
           + "touch-first equivalents — several of which do not exist as free software at all and will have to "
           + "be ours. Desktop apps still have a place when docked.",
      groups: [
        {
          title: "Running today",
          items: [
            { n: "Kitty terminal", s: "ok",
              note: "Native Wayland, opt-in touch scroll and long-press word/drag selection, copy-on-select, "
                  + "Nerd Font, Omarchy-branded Fastfetch. Rebuild is v0.48.2-matched; a package upgrade replaces it.",
              ref: "overlay/mobile/kitty-touch/README.md" },
            { n: "Chromium (stock, native Wayland)", s: "ok",
              note: "Sandbox enabled, running in its own restricted mobile-browser account.",
              ref: "docs/keyboard-browser-20260918.md" },
            { n: "Grok webapp", s: "ok", note: "App-mode window through the webapp launcher.",
              ref: "docs/keyboard-browser-20260918.md" },
            { n: "Webapp launcher", s: "ok", note: "Desktop-entry driven app-mode windows." },
            { n: "pacman package management", s: "ok",
              note: "Ordinary sync/install works; the earlier Landlock incompatibility is fixed.",
              ref: "docs/status.md" }
          ]
        },
        {
          title: "Phone apps we build for touch",
          note: "The stock set a phone is expected to have. Free-software options that fit a touch phone are "
              + "thin, so the working assumption is that we build these on the shared framework.",
          items: [
            { n: "Phone / dialer", s: "no", note: "Blocked behind modem registration and call audio.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Messaging (SMS/MMS)", s: "no", note: "Blocked behind modem registration.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Contacts", s: "no",
              note: "Needs a local contacts store plus vCard import/export, and to be readable by the dialer, "
                  + "messaging and the agent.", ref: "docs/mobile-roadmap.md" },
            { n: "Clock (alarm, timer, stopwatch)", s: "no",
              note: "Alarms have to wake the phone from suspend, so this depends on the wake design as much as "
                  + "on UI.", ref: "docs/background-wake-plan.md" },
            { n: "Gallery / photo viewer", s: "no",
              note: "Blocked behind the camera pipeline for capture, but a viewer over existing files is "
                  + "independent work.", ref: "docs/pathway.md" },
            { n: "File manager", s: "partial",
              note: "Files browses, opens, creates and deletes inside the home folder after the user grants "
                  + "files.home. It does not see the rest of the system, and there is no share sheet.",
              ref: "docs/mobile-architecture.md" },
            { n: "Calendar", s: "no",
              note: "The shade already renders calendar data; no app, no account sync.",
              ref: "docs/notification-shade-20260918.md" },
            { n: "Weather", s: "partial",
              note: "A tile exists in the shade; a real app with locations and a forecast view does not.",
              ref: "docs/notification-shade-20260918.md" },
            { n: "Camera", s: "partial", note: "GNOME Snapshot shows the main camera through PipeWire and a "
                + "patched libcamera: autofocus lands and photos save to ~/Pictures. Image quality is modest, "
                + "switching between the viewer and the preview lags, and only the main camera works.",
              ref: "docs/camera-20260922.md" },
            { n: "Settings application", s: "partial", note: "See the Settings & configuration section.",
              ref: "docs/settings-clipboard-20260919.md" },
            { n: "Further stock apps (TBD)", s: "no",
              note: "Calculator, notes, tasks, email, music… deliberately unlisted until we decide. Each one "
                  + "should be a framework exercise, not a one-off.", ref: "docs/mobile-roadmap.md" }
          ]
        },
        {
          title: "Shared app framework",
          note: "The thing that turns “we wrote eleven apps” into “anyone can write the twelfth”. Omarchy "
              + "Mobile apps inherit theme, colour, font, density and touch behaviour from the base OS instead "
              + "of re-implementing them.",
          items: [
            { n: "Framework core (shared runtime for mobile apps)", s: "partial",
              note: "OmarchyMobile supplies theme and widgets. A new app is a manifest plus an AppWindow. "
                  + "There is no sandbox or SDK package yet.",
              ref: "docs/mobile-architecture.md" },
            { n: "Theme inheritance from the OS", s: "partial",
              note: "The kit exposes MobileTheme from Omarchy palettes. Settings and Files inherit it through AppWindow.",
              ref: "overlay/mobile/kit/qmldir" },
            { n: "Common touch widgets & layout kit", s: "partial",
              note: "TouchButton, text field, page header, settings row and appearance page are shared. Lists, "
                  + "sheets and selection handles are still ahead.",
              ref: "docs/settings-clipboard-20260919.md" },
            { n: "App manifest, launcher & lifecycle integration", s: "partial",
              note: "omarchy-mobile-app reads a manifest, launches one window, and replaces that window if it is "
                  + "opened again. Suspend and resume rules are not defined.",
              ref: "docs/mobile-architecture.md" },
            { n: "Permissions & sandbox model", s: "partial",
              note: "An app declares permissions from a fixed list and the user grants them on first launch. "
                  + "The file helper enforces files.home. There is no process sandbox, and contacts, location, "
                  + "camera and notifications are not in the list yet.",
              ref: "docs/mobile-architecture.md" },
            { n: "Public SDK, docs and examples", s: "no",
              note: "The point of the framework: other people building Omarchy Mobile apps without asking us.",
              ref: "docs/mobile-roadmap.md" },
            { n: "App distribution & update path", s: "no",
              note: "pacman exists, but there is no app-facing story for signing, channels or updates.",
              ref: "docs/status.md" }
          ]
        },
        {
          title: "Browser (touch-centred)",
          items: [
            { n: "Touch-centred Chromium fork", s: "no",
              note: "Stock Chromium assumes a mouse and a tab strip. A fork (or a deeply themed wrapper) is "
                  + "likely: touch input handling, chrome/UI, gestures, theming from the OS, media policies.",
              ref: "docs/keyboard-browser-20260918.md" },
            { n: "In-browser touch text selection & paste", s: "no",
              note: "Depends on the same selection work as the shell.", ref: "docs/mobile-roadmap.md" },
            { n: "Browser audio", s: "ok",
              note: "YouTube in Chromium plays clean and audible through the media volume group. Loudness stays "
                  + "below the speaker safety cap.", ref: "docs/speakers-20260922.md" },
            { n: "Smooth web video playback", s: "no",
              note: "Streaming reported choppy; decode path (Venus vs CPU vs GPU) diagnosed separately.",
              ref: "docs/next-session.md" }
          ]
        },
        {
          title: "Desktop apps (docked)",
          note: "Only valuable with a keyboard, a mouse and a screen. Kept available for the docked case, "
              + "never a substitute for the touch apps.",
          items: [
            { n: "Standard Omarchy desktop app set", s: "no",
              note: "Files, editor, media, office… keyboard-and-mouse driven. Decide per app whether it ships "
                  + "on the phone at all.", ref: "docs/mobile-roadmap.md" },
            { n: "Docked session (external display + keyboard + mouse)", s: "no",
              note: "Gated on USB-C DisplayPort and USB host support.", ref: "docs/mobile-roadmap.md" },
            { n: "Desktop-mode shell layout when docked", s: "no",
              note: "Different density, bar, window rules and input handling than the phone layout.",
              ref: "docs/mobile-architecture.md" }
          ]
        }
      ]
    },

    {
      id: "advanced",
      title: "Advanced features",
      blurb: "Platform capability rather than surfaces: rendering, sessions, tooling, power behaviour.",
      items: [
        { n: "GPU Wayland desktop (Hyprland + Quickshell)", s: "ok",
          note: "Starts automatically on boot with FD640 rendering and native scanout.",
          ref: "docs/native-display-work-20260917.md" },
        { n: "Automated UI / backend / hardware-policy tests", s: "ok",
          note: "Gesture, backend and policy checks under tests/, run against the live session.", ref: "tests/" },
        { n: "Guarded build, flash and rollback tooling", s: "ok",
          note: "Explicit target identity, image/hash and slot checks, frozen checkpoints and rollback images.",
          ref: "README.md" },
        { n: "Reusable shell across devices", s: "partial",
          note: "Shared UI separated from the OnePlus adapter, but no second device has been validated.",
          ref: "docs/mobile-architecture.md" },
        { n: "Standard user session + sudo", s: "no",
          note: "The bring-up desktop runs as root; the mobile-browser account is a temporary Chromium bridge, "
              + "not the intended session design.", ref: "docs/mobile-roadmap.md" },
        { n: "Automatic idle / sleep policy", s: "no", note: "Not implemented; sleep is currently user-triggered.",
          ref: "docs/status.md" },
        { n: "Background wake for delayed delivery", s: "no",
          note: "Design written up, implementation not started. This is what alarms, message delivery and "
              + "agent tasks waiting on a schedule all depend on.", ref: "docs/background-wake-plan.md" },
        { n: "Measured, repeatable battery life", s: "no",
          note: "Only short informal samples exist (131 mA screen-off awake vs 83 mA suspended; 85%→78% over "
              + "~3h45m). No claim is defensible yet.", ref: "docs/idle-measurement-20260917.md" },
        { n: "Secure / verified boot path", s: "no",
          note: "Verification is disabled for bring-up; a production boot story is still open." }
      ]
    },

    {
      id: "ai",
      title: "AI & agents",
      blurb: "The phone is meant to be agentic and malleable, like desktop Omarchy — a default agent, room to "
           + "install the coding harnesses we already use, and a small model that keeps working with no network "
           + "at all.",
      groups: [
        {
          title: "Agent platform",
          items: [
            { n: "Default system agent", s: "no",
              note: "The phone's own agent: knows the shell, the settings, the apps and the user's files. Nothing "
                  + "exists yet.", ref: "docs/mobile-roadmap.md" },
            { n: "Phone-control API for agents", s: "no",
              note: "A stable, discoverable interface for reading state and making changes — brightness, theme, "
                  + "network, Do Not Disturb, launching apps, dismissing notifications. Today these are "
                  + "shell-internal Quickshell calls with no boundary.", ref: "docs/mobile-architecture.md" },
            { n: "Permission & confirmation model for agent actions", s: "no",
              note: "Which changes are silent, which ask, which are never allowed — and how that reads on a "
                  + "touch screen.", ref: "docs/mobile-roadmap.md" },
            { n: "Agent surface in the shell", s: "no",
              note: "Where the agent lives: a gesture, a launcher entry, a panel, on-screen context about the "
                  + "focused window.", ref: "docs/mobile-roadmap.md" }
          ]
        },
        {
          title: "Coding harnesses",
          items: [
            { n: "Install & drive harnesses (pi, Codex, Claude Code, Grok, Hermes)", s: "partial",
              note: "Grok runs as a webapp and ordinary Arch packages install fine, but no harness has been "
                  + "installed and driven end-to-end from the touch session.",
              ref: "docs/keyboard-browser-20260918.md" },
            { n: "Terminal ergonomics for real CLI work", s: "partial",
              note: "Kitty with touch scrolling and the on-screen keyboard work; no text selection, copy/paste or "
                  + "swipe typing, which is what working at arm's length actually needs.",
              ref: "docs/mobile-work-20260917.md" },
            { n: "Long-running sessions that survive suspend", s: "no",
              note: "A build or an agent run should not die because the screen went to sleep; needs job keeping "
                  + "plus a wake policy.", ref: "docs/background-wake-plan.md" }
          ]
        },
        {
          title: "On-device model",
          items: [
            { n: "Local inference runtime", s: "no",
              note: "Nothing installed. CPU-only is the certain baseline; whether GLES/Turnip Vulkan is usable "
                  + "for inference on this GPU is unmeasured, and the NPU has no mainline path.",
              ref: "docs/pathway.md" },
            { n: "Small offline chat / general-knowledge model", s: "no",
              note: "What fits in 8 GB alongside a compositor, and at what quality, is unknown until measured.",
              ref: "docs/pathway.md" },
            { n: "Thermal & battery budget for inference", s: "no",
              note: "How long we may run a model before the handset is too hot to hold or the battery is gone. "
                  + "No thermal policy exists to enforce a limit.", ref: "docs/idle-measurement-20260917.md" },
            { n: "Model management (download, swap, memory limits)", s: "no",
              note: "Choosing a model, fetching it, keeping it off the critical path, and falling back to the "
                  + "cloud when a task is too big." },
            { n: "On-device settings & device control", s: "no",
              note: "“Turn on Do Not Disturb at nine”, “switch to the dark theme”, “find the log from the failed "
                  + "flash” — local agent actions with no network round trip. Depends on the phone-control API.",
              ref: "docs/mobile-architecture.md" },
            { n: "Fully offline agent features", s: "no",
              note: "The reason local matters: everything still works in airplane mode, off-grid, or with no "
                  + "account. Nothing built yet." }
          ]
        }
      ]
    }
  ]
};
