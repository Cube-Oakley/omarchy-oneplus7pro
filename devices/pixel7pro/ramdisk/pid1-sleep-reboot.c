/* PID 1 proof: sleep, then PSCI reset (not RESTART2 "bootloader").
 * If this runs, the logo sits ~SLEEP_SECS then the phone resets.
 * Three slot retries then the bootloader stays in fastboot. */
#define _GNU_SOURCE
#include <sys/syscall.h>
#include <linux/reboot.h>
#include <unistd.h>

#ifndef SLEEP_SECS
#define SLEEP_SECS 12
#endif

int main(void) {
  unsigned int left = SLEEP_SECS;
  while (left)
    left = sleep(left);
  sync();
  syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
          LINUX_REBOOT_CMD_RESTART, NULL);
  for (;;)
    pause();
}
