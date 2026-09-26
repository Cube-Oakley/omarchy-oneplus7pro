/* PID 1: prove userspace. Print a banner to kmsg, then reboot after 25s.
 * First reset ~kernel-start+25s (~35-45s) is success. 70s bounce and
 * 210s WDT hang are distinct. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <linux/reboot.h>
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <unistd.h>

static void kmsg(const char *s) {
  int fd = open("/dev/kmsg", O_WRONLY);
  if (fd >= 0) {
    write(fd, s, __builtin_strlen(s));
    close(fd);
  }
}

int main(void) {
  unsigned int left;
  kmsg("<5>MAINLINE cheetah stub: PID 1 running\n");
  left = 25;
  while (left)
    left = sleep(left);
  kmsg("<5>MAINLINE cheetah stub: rebooting\n");
  sync();
  syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
          LINUX_REBOOT_CMD_RESTART, NULL);
  for (;;)
    pause();
}
