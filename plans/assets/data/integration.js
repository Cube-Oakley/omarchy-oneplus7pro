/* ==========================================================================
   INTEGRATION page data
   ========================================================================== */
PAGE_INTEGRATION = {
  id: "integration",
  nav: "Integration",
  cardBlurb: "Phone and desktop: an Omarchy phone behaving like another member of the same family as an "
           + "Omarchy desktop — explicit pairing, per-feature control.",
  eyebrow: "Project plan · Integration",
  title: "Integration",
  blurb: "Phone and desktop. Today the link is a development link — SSH over USB and a build-and-flash pipeline. "
       + "The target is an Omarchy phone that behaves like another member of the same family as an Omarchy "
       + "desktop: shared theme, shared clipboard if you want it, notifications and texts on either screen.",

  sections: [
    {
      id: "link",
      title: "Working today (development link)",
      blurb: "Not user-facing integration, but it is real desktop-to-phone plumbing and it is what makes the rest "
           + "of this buildable.",
      items: [
        { n: "USB SSH from the desktop", s: "ok",
          note: "scripts/phone-ssh.sh with a separately provisioned pinned host key; recovers on replug.",
          ref: "docs/usb-networking-20260917.md" },
        { n: "USB network / routing bring-up", s: "ok",
          note: "phone-usb-up.sh restores routing, DNS, SSH and the clock after boot.",
          ref: "scripts/phone-usb-up.sh" },
        { n: "Host-side build → transfer → flash pipeline", s: "ok",
          note: "Kernel, initramfs, dtbo and desktop images built on the workstation and flashed with guards.",
          ref: "scripts/" },
        { n: "Live device observation from the desktop", s: "ok",
          note: "USB watchers, battery recorder, scanout readers, Sahara crashdump reads.",
          ref: "scripts/watch_phone_usb.sh" }
      ]
    },

    {
      id: "features",
      title: "Shared experience & cross-device features",
      blurb: "One service, many features: pairing and per-feature control, with presentation kept in the shell "
           + "and the transport kept separate from device adapters.",
      groups: [
        {
          title: "Features",
          items: [
            { n: "Same Omarchy theme format on both ends", s: "partial",
              note: "The phone consumes standard Omarchy palettes and wallpapers locally; there is no sync "
                  + "between devices, and the full theme repository install is unfinished.",
              ref: "docs/mobile-architecture.md" },
            { n: "Theme / wallpaper sync between phone and desktop", s: "no",
              note: "Pick a theme on one end, it applies on the other. Depends on the theme repository install "
                  + "and on the paired service.", ref: "docs/mobile-roadmap.md" },
            { n: "Phone notifications on the desktop", s: "no",
              note: "Needs the paired service. Should not require the phone to stay awake to deliver anything.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Desktop notifications on the phone", s: "no", note: "Not started.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Texting (SMS) from the computer", s: "no",
              note: "Depends on the modem milestone as well as the paired service.", ref: "docs/mobile-roadmap.md" },
            { n: "Calls surfaced on the desktop", s: "no",
              note: "Depends on modem registration plus call audio, and on audio routing between devices.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Clipboard sync (opt-in)", s: "no",
              note: "Explicitly opt-in when built; nothing exists today.", ref: "docs/mobile-roadmap.md" },
            { n: "Agent works across both machines", s: "no",
              note: "Ask the desktop agent to change something on the phone, or the phone agent to read something "
                  + "on the desktop. Built on the phone-control API plus the paired service.",
              ref: "docs/mobile-roadmap.md" }
          ]
        },
        {
          title: "Foundations to decide",
          note: "Unresolved on purpose. Existing protocols get evaluated before we invent one.",
          items: [
            { n: "Paired phone–desktop service", s: "no",
              note: "One daemon on each end, explicit pairing, per-feature toggles, transport separate from "
                  + "device adapters and from Quickshell presentation.", ref: "docs/mobile-roadmap.md" },
            { n: "Transport choice (USB, LAN, relay)", s: "no",
              note: "USB is available and private today; LAN is what people actually want; a relay adds servers "
                  + "we would rather not run.", ref: "docs/mobile-roadmap.md" },
            { n: "Pairing, trust & key pinning", s: "no",
              note: "How a phone and a desktop become peers, and how that is revoked. USB already pins a host key, "
                  + "which is the precedent to follow.", ref: "README.md" },
            { n: "Per-feature permission controls", s: "no",
              note: "Notifications yes, clipboard no, texts maybe — the same shape as agent permissions.",
              ref: "docs/mobile-roadmap.md" },
            { n: "Privacy story for what crosses the wire", s: "no",
              note: "Notification bodies, clipboard contents and messages are the most sensitive data on either "
                  + "machine. End to end, and off by default where it matters.", ref: "docs/mobile-roadmap.md" }
          ]
        }
      ],
      notes: [
        "Delivery while the phone sleeps is tracked under Software → Advanced features (background wake) "
        + "and Hardware → s2idle/deep-idle, not here — it is a sleep/wake problem before it is an integration "
        + "problem."
      ]
    }
  ]
};
