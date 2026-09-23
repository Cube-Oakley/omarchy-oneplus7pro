/* Site-wide copy shared by all pages. */
SITE = {
  meta: ["updated 2026-09-23", "kernel #191 · slot B", "audio + Bluetooth working · SIM pending"],

  landing: {
    eyebrow: "Project plan · overview",
    title: "Omarchy Mobile on the OnePlus 7 Pro",
    blurb: "Arch Linux ARM + Hyprland + Quickshell on guacamole (Snapdragon 855 / Adreno 640), "
         + "shaped into a touch phone we can actually reprogram. Three pages: the hardware inside the "
         + "handset, the software you touch, and how the phone talks to a desktop.",
    meta: ["updated 2026-09-23", "kernel #191 · slot B", "audio + Bluetooth working · SIM pending", "3 pages"]
  },

  howTo: [
    "<b>Working</b> means verified on the handset — not “the driver probed”. Where a check was only "
    + "automated, or only seen once, the note says so.",
    "<b>Partial</b> means the plumbing is up but the user-visible result is unproven, capped, or only "
    + "one of several paths works. Cellular is the current example: the modem answers QMI and its data "
    + "interface comes up, but with no SIM there is no registration, call or data yet.",
    "<b>Not working</b> means nothing usable yet, including “not attempted so far”.",
    "<b>Not present</b> means this handset simply has no such hardware — tracked so nobody spends a "
    + "week looking for a headphone jack.",
    "Plain HTML, no build step, no network dependencies. Open any page directly from disk."
  ],

  open: [
    "<b>App set.</b> Desktop Omarchy apps are keyboard-and-mouse shaped; on the phone we need touch-first "
    + "equivalents, and several do not exist anywhere yet. Which apps we build, in what order, and which "
    + "desktop apps stay available when docked is still open — see <b>Software → Apps</b>.",
    "<b>App framework.</b> Nothing decided about the stack the Omarchy Mobile apps will be built on "
    + "(Quickshell/QML modules, a thin runtime, an app manifest, how theming is inherited, how third "
    + "parties ship apps). See <b>Software → Apps → Shared app framework</b>.",
    "<b>Browser.</b> Stock Chromium is usable but not touch-centred; a fork is likely. Scope of the fork "
    + "(input, chrome/UI, windowing, media) is undecided.",
    "<b>AI surface.</b> What the default agent is, what the on-device model is for, and exactly what the "
    + "phone-control API exposes to an agent — including how an agent action gets confirmed — is open.",
    "<b>Sensor path.</b> Raw IIO upstream versus the SLPI unified-sensor interface (the 7T Pro work drives "
    + "sensors through libssc → SEE). Worth deciding before anything is built on top of either. See "
    + "<b>Hardware → Sensors</b>.",
    "<b>Integration transport.</b> USB, LAN or relay; which existing protocols we evaluate before writing "
    + "anything; and how pairing, per-feature permissions and end-to-end privacy are framed. See "
    + "<b>Integration → Foundations to decide</b>.",
    "<b>Ship order.</b> Modem, audio and deep suspend are all phone-critical and all unfinished; the "
    + "sequence still moves with each result."
  ]
};
