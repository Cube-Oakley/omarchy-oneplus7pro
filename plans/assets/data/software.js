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
          note: "Battery percentage with charging bolt, Wi-Fi signal. Event-driven, no polling latency.",
          ref: "docs/status-indicators-20260917.md" },
        { n: "Notification shade (pull-down)", s: "ok",
          note: "Drag-down panel with themed detail popups, real notifications, battery metrics, Wi-Fi scan and "
              + "connect, calendar, opt-in weather. Swipe up to close.",
          ref: "docs/notification-shade-20260918.md" },
        { n: "App launcher / drawer", s: "ok",
          note: "Touch launcher on desktop entries; launching through the drawer verified for both installed apps.",
          ref: "docs/keyboard-browser-20260918.md" },
        { n: "Workspace & window overview", s: "ok",
          note: "Live previews, tap to enter a workspace, drag a preview onto a workspace to move the window.",
          ref: "docs/touch-drawers-20260917.md" },
        { n: "Bottom-edge gesture navigation", s: "ok",
          note: "Left = launcher, centre = overview, right = keyboard; finger-tracked sheets with swipe-down "
              + "dismissal. User-confirmed.", ref: "docs/mobile-gestures-20260917.md" },
        { n: "On-screen keyboard", s: "ok",
          note: "Gesture activation, explicit-tap popup input, swipe-down handle to hide, no duplicate surfaces.",
          ref: "docs/keyboard-browser-20260918.md" },
        { n: "Mobile scaling & tiled windows", s: "ok",
          note: "Scale appropriate to 1440 × 3120; multiple tiled app windows coexist with the shell surfaces." },
        { n: "Notification actions, grouping and dismissal", s: "partial",
          note: "Real notification history and presentation exist; actions, grouping and per-item dismissal are "
              + "still being extended.", ref: "docs/mobile-roadmap.md" },
        { n: "Quick-setting toggles (brightness, Bluetooth, DND…)", s: "no",
          note: "The shade currently carries information rather than toggles.", ref: "docs/mobile-roadmap.md" },
        { n: "Weather tile", s: "partial",
          note: "Opt-in weather panel is installed; location unset and the end-to-end path is untested.",
          ref: "docs/notification-shade-20260918.md" },
        { n: "New Wi-Fi network entry (password)", s: "partial",
          note: "Saved-network activation and HTTPS verified; entering a password for a new network is untested.",
          ref: "docs/notification-shade-20260918.md" },
        { n: "Copy / paste and touch text selection", s: "no",
          note: "Selection handles, highlight and context menus. This blocks almost every real text task, "
              + "including coding on the phone.", ref: "docs/mobile-roadmap.md" },
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
              note: "Standard Omarchy theme colours apply across the shell, Kitty and keyboard.",
              ref: "docs/mobile-architecture.md" },
            { n: "Wallpaper preview, cycling and per-theme choice", s: "ok",
              note: "92 stock images; the chosen wallpaper survives shell restart.",
              ref: "docs/wallpaper-switching-20260917.md" },
            { n: "Font handling", s: "ok", note: "JetBrainsMono Nerd Font installed for shell, Kitty and keyboard.",
              ref: "docs/notification-shade-20260918.md" },
            { n: "Battery detail view", s: "ok",
              note: "Percentage, charge/current direction, voltage and temperature distinguished from input "
                  + "current.", ref: "docs/notification-shade-20260918.md" },
            { n: "Volume UI and output routing", s: "partial",
              note: "Themed volume OSD and media-key bindings are installed; per-device routing does not exist "
                  + "and the audible result is unconfirmed.", ref: "docs/audio-bringup-20260918.md" },
            { n: "Choices survive reboot", s: "partial",
              note: "Keyboard, audio and desktop auto-start after reboot is verified; the shade's session-bus "
                  + "startup after reboot is not yet tested.", ref: "docs/status.md" }
          ]
        },
        {
          title: "Settings app (to build)",
          note: "There is no settings application at all today — the rows below are the panels it needs, "
              + "marked against whatever partial surface already exists elsewhere.",
          items: [
            { n: "Settings application", s: "no",
              note: "A first-class Omarchy Mobile app: searchable panels, touch-first, themed by the running "
                  + "theme, and readable by the agent.", ref: "docs/mobile-roadmap.md" },
            { n: "Panel — Network & Wi-Fi", s: "partial",
              note: "Scan, connect and details exist inside the notification shade; no real settings surface.",
              ref: "docs/notification-shade-20260918.md" },
            { n: "Panel — Display & brightness", s: "no", note: "Nothing to configure until brightness control "
                  + "exists on the hardware side." },
            { n: "Panel — Sound & output routing", s: "partial",
              note: "Volume OSD only. No device picker, no per-app routing, no call-audio settings.",
              ref: "docs/audio-bringup-20260918.md" },
            { n: "Panel — Battery & charging", s: "partial",
              note: "Read-only metrics exist. Charge policy is fixed at boot and not user-settable.",
              ref: "docs/charging-20260917.md" },
            { n: "Panel — Appearance & theme", s: "partial",
              note: "Theme and wallpaper selection work from the shell; no settings surface, no font picker.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Panel — Bluetooth & devices", s: "no", note: "Nothing to manage until Bluetooth comes up." },
            { n: "Panel — SIM & cellular", s: "no", note: "Blocked behind modem bring-up.",
              ref: "docs/modem-foundations-20260917.md" },
            { n: "Panel — Security, lock screen & fingerprint", s: "no",
              note: "Covers credential enrollment and the fingerprint reader, neither of which is enabled.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Panel — Apps & permissions", s: "no",
              note: "Needs the app framework's manifest and permission model to have anything to show.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Panel — Storage", s: "no", note: "Not started." },
            { n: "Panel — Location & sensors", s: "no",
              note: "Sensor permissions for apps, GPS toggles, calibration state.", ref: "docs/pathway.md" },
            { n: "Panel — Accessibility", s: "no",
              note: "Text size, contrast, screen reader hooks. Cheap to design in early, expensive to bolt on "
                  + "later.", ref: "docs/mobile-roadmap.md" },
            { n: "Panel — About, updates & recovery", s: "no",
              note: "Device identity, build/kernel info, checkpoint and rollback entry points.",
              ref: "docs/backup.md" }
          ]
        },
        {
          title: "Preferences plumbing",
          items: [
            { n: "Unified persistent preferences surface", s: "no",
              note: "Today preferences are scattered opt-in markers (weather, audio autostart, per-theme "
                  + "wallpaper). Needs one store both shell and apps read.", ref: "docs/mobile-roadmap.md" },
            { n: "Themed font picker", s: "no",
              note: "On the roadmap; the font is fixed by hand today.", ref: "docs/mobile-roadmap.md" },
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
              note: "Native Wayland, opt-in touch-scroll patch, Nerd Font, Omarchy-branded Fastfetch.",
              ref: "docs/mobile-work-20260917.md" },
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
            { n: "File manager", s: "no",
              note: "Touch-first browsing, storage locations, share sheet. Also the escape hatch when an agent "
                  + "moves something on disk.", ref: "docs/mobile-roadmap.md" },
            { n: "Calendar", s: "no",
              note: "The shade already renders calendar data; no app, no account sync.",
              ref: "docs/notification-shade-20260918.md" },
            { n: "Weather", s: "partial",
              note: "A tile exists in the shade; a real app with locations and a forecast view does not.",
              ref: "docs/notification-shade-20260918.md" },
            { n: "Camera", s: "no", note: "Blocked behind sensors + ISP bring-up.", ref: "docs/pathway.md" },
            { n: "Settings application", s: "no", note: "See the Settings & configuration section.",
              ref: "docs/mobile-roadmap.md" },
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
            { n: "Framework core (shared runtime for mobile apps)", s: "no",
              note: "Undecided stack. Quickshell/QML is already the shell's language, which makes it the obvious "
                  + "starting point, but it is not chosen yet.", ref: "docs/mobile-architecture.md" },
            { n: "Theme inheritance from the OS", s: "partial",
              note: "The shell reads Omarchy palettes and wallpapers, and the mobile theme layer exists — but it "
                  + "is shell-internal, not something an app can inherit.",
              ref: "overlay/mobile/MobileTheme.qml" },
            { n: "Common touch widgets & layout kit", s: "no",
              note: "Lists, sheets, pickers, handles, toolbars, keyboard-aware layout, hit targets. Building it "
                  + "once is the only way eleven apps feel like one phone.", ref: "docs/mobile-roadmap.md" },
            { n: "App manifest, launcher & lifecycle integration", s: "no",
              note: "Icons, categories, single-instance rules, how an app appears in the drawer and overview, "
                  + "suspend/resume expectations.", ref: "docs/mobile-architecture.md" },
            { n: "Permissions & sandbox model", s: "no",
              note: "What an app may touch: contacts, location, camera, files, notifications, and which of those "
                  + "an agent may act on for the user.", ref: "docs/mobile-roadmap.md" },
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
            { n: "Browser audio", s: "no",
              note: "YouTube playback reported inaudible — needs a live stream capture to separate routing, "
                  + "attenuation and connection causes.", ref: "docs/next-session.md" },
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
