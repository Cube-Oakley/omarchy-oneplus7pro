/* Restart into the bootloader via reboot(..., "bootloader").
 * BusyBox reboot(1) cannot pass RESTART2. */
#define _GNU_SOURCE
#include <sys/syscall.h>
#include <linux/reboot.h>
#include <unistd.h>

int main(void) {
  sync();
  syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
          LINUX_REBOOT_CMD_RESTART2, "bootloader");
  for (;;)
    pause();
}
