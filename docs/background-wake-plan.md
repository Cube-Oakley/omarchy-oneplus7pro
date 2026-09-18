# Background work and Android comparison

This is a design plan, not implemented notification/telephony support.

## Power comparison

The first local test measured 131 mA screen-off awake and 83 mA over the suspend
interval. Actual suspended time was 301 seconds; estimated gauge resolution
is about 12 mA for this interval. See the measurement document for limitations.

Notebookcheck's first-hand OnePlus 7 Pro Android 9 review reports 0.1 W standby:
https://www.notebookcheck.net/OnePlus-7-Pro-Smartphone-Review.420598.0.html
At 4 V this is electrically equivalent to 25 mA; it is not a direct battery
current measurement under our conditions. Their screen-on idle and Wi-Fi
web-browsing results must not be compared to our suspended trial. A controlled
same-device Android baseline with matched radios, battery and test duration
would be needed to establish the actual gap.

At a constant 83 mA, a hypothetical usable 4000 mAh battery implies 48 hours
of standby-only runtime. This is arithmetic, not a measured runtime promise:
screen use, radio coverage, background wakeups, battery age, gauge accuracy and
the present conservative 4.20 V charge ceiling change it. First optimize and
measure power domains/clocks/rails, then include connected standby costs.

## Current behavior

Suspend freezes userspace and disconnects Wi-Fi. Email/chat cannot arrive
through that Wi-Fi connection while asleep. Modem remoteproc running for WLAN
bring-up does not establish working cellular registration, calling or SMS.
Current display restoration on every resume is diagnostic/convenience behavior;
background wakeups must eventually run with the screen kept off.

## Intended architecture

- A shared service coordinates deadlines and bounded background jobs. Batch
  nonurgent mail/sync into configurable RTC wake windows, initially accepting
  notification delay. Return to sleep after the bounded work completes.
- Urgent network notifications need a maintained low-power radio connection
  and hardware-triggered host wake. Investigate WCN3990 WoWLAN, connection/key
  maintenance and usable packet triggers. Wake on all traffic risks excessive
  drain. TCP keepalives and encrypted push integration need real validation;
  enabling a wake flag alone does not deliver application notifications.
- Prefer a shared push connection where clients/backends support it. Arbitrary
  Linux desktop apps do not automatically join such a service. Keep scheduled
  polling as an explicit fallback. Quickshell presents notifications, while
  the delivery/wake service operates independently of the shell.
- Cellular calls/SMS need a low-power registered modem plus wake signalling and
  Linux telephony services. Validate incoming events during suspend, audio,
  carrier/VoLTE integration and wake retention through the ringing/call path.
  Do not promise this based only on a running modem or DT wakeup flag.
- Distinguish user wake from background wake: Power shows the UI; mail sync may
  leave the screen off; alarms/calls hold appropriate sleep inhibitors. Enforce
  timeouts so a malfunctioning client cannot keep the phone awake indefinitely.
- Keep portable scheduling/UI in the mobile layer, device wake/charging/radio
  details in board adapters. A proper supervised service lifecycle is needed
  beyond the current chroot startup scripts.

References:
https://developer.android.com/training/monitoring-device-state/doze-standby
https://source.android.com/docs/core/power/platform_mgmt
https://wireless.docs.kernel.org/en/latest/en/users/documentation/wowlan.html

Android batches background work and uses shared FCM connections for compatible
apps; high-priority notifications can receive temporary execution. Telephony
services are separately supported through Doze. Those architectural ideas are
useful here, but Android application/Google-service integration does not come
automatically with Arch or Quickshell.
