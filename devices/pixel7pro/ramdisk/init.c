/* Non-PIE static /init.
 * cheetah GKI has CONFIG_DEVTMPFS=n. Android fills /dev with tmpfs+ueventd.
 * We must mknod kmsg/persist/tty ourselves. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

static void wfile(const char *path, const char *s) {
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
  if (fd >= 0) {
    write(fd, s, strlen(s));
    close(fd);
  }
}

static void kmsg(const char *s) {
  int fd = open("/dev/kmsg", O_WRONLY);
  if (fd >= 0) {
    write(fd, s, strlen(s));
    close(fd);
  }
}

static void md(const char *p) { mkdir(p, 0755); }

int main(void) {
  md("/proc");
  md("/sys");
  md("/dev");
  md("/persist");
  md("/bin");
  md("/sbin");
  md("/tmp");
  md("/sys/fs");
  md("/sys/fs/selinux");
  md("/sys/fs/pstore");
  md("/sys/kernel");
  md("/sys/kernel/config");

  mount("proc", "/proc", "proc", 0, 0);
  mount("sysfs", "/sys", "sysfs", 0, 0);
  /* Not devtmpfs — this kernel does not have it. */
  mount("tmpfs", "/dev", "tmpfs", 0, "mode=0755");
  md("/dev/block");
  mknod("/dev/null", S_IFCHR | 0666, makedev(1, 3));
  mknod("/dev/zero", S_IFCHR | 0666, makedev(1, 5));
  mknod("/dev/kmsg", S_IFCHR | 0644, makedev(1, 11));
  mknod("/dev/tty", S_IFCHR | 0666, makedev(5, 0));
  mknod("/dev/console", S_IFCHR | 0600, makedev(5, 1));
  /* Live GKI: /proc/devices says "252 pmsg". 10,1 was wrong so pmsg never landed. */
  mknod("/dev/pmsg0", S_IFCHR | 0222, makedev(252, 0));
  /* persist is sda1 on this unit (8,1). */
  mknod("/dev/sda1", S_IFBLK | 0600, makedev(8, 1));
  mknod("/dev/block/sda1", S_IFBLK | 0600, makedev(8, 1));
  /* ACM gadget port from live Android: 238,0 */
  mknod("/dev/ttyGS0", S_IFCHR | 0666, makedev(238, 0));

  mount("selinuxfs", "/sys/fs/selinux", "selinuxfs", 0, 0);
  wfile("/sys/fs/selinux/enforce", "0");
  kmsg("OMARCHY: c-init mounts ok\n");

  /* Do not mount persist. A blocking ext4 mount on the mknod'd sda1
   * node hangs PID 1 (flash 5/18/24/25) and then reboot() never returns. */
  kmsg("OMARCHY: c-init skip persist\n");

  mount("configfs", "/sys/kernel/config", "configfs", 0, 0);
  mount("pstore", "/sys/fs/pstore", "pstore", 0, 0);

  char *argv[] = {"/busybox", "sh", "/init.sh", 0};
  char *envp[] = {"PATH=/bin:/sbin:/usr/bin", "HOME=/", 0};
  execve("/busybox", argv, envp);

  kmsg("OMARCHY: exec busybox FAILED\n");
  wfile("/persist/omarchy-ramdisk.log", "OMARCHY: exec busybox FAILED\n");
  for (;;)
    pause();
}
