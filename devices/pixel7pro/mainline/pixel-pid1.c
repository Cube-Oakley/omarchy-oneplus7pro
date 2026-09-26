// SPDX-License-Identifier: GPL-2.0-only
/* Volatile first-userspace proof. No block devices or persistent files used. */
#include <fcntl.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <termios.h>
#include <unistd.h>

int main(void)
{
    struct utsname u;
    char line[256];
    mkdir("/dev", 0755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    mkdir("/proc", 0755);
    mount("proc", "/proc", "proc", 0, NULL);
    mkdir("/sys", 0755);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    int fd = open("/dev/kmsg", O_WRONLY);
    int serial = open("/dev/ttyGS0", O_RDWR | O_NONBLOCK | O_NOCTTY);
    if (serial >= 0) {
        struct termios t;
        if (!tcgetattr(serial, &t)) {
            cfmakeraw(&t);
            tcsetattr(serial, TCSANOW, &t);
        }
    }
    uname(&u);
    int n = snprintf(line, sizeof(line), "<5>PIXEL NATIVE LINUX PID1: %s %s, pid=%d\n", u.sysname, u.release, getpid());
    if (fd >= 0) write(fd, line, n);
    for (int remaining = 120; remaining > 0; remaining--) {
        if (!(remaining % 5)) {
            n = snprintf(line, sizeof(line), "<5>PIXEL PID1 alive: RAM-only test, serial_fd=%d, reset in %d seconds\n", serial, remaining);
            if (fd >= 0) write(fd, line, n);
            if (serial >= 0) write(serial, line + 3, n - 3);
        }
        if (serial >= 0) {
            char input[128];
            int got = read(serial, input, sizeof(input));
            if (got > 0) {
                n = snprintf(line, sizeof(line), "<5>PIXEL USB RX: %.*s\n", got, input);
                if (fd >= 0) write(fd, line, n);
                write(serial, "PIXEL USB ECHO: ", 16);
                write(serial, input, got);
            }
        }
        sleep(1);
    }
    if (fd >= 0) {
        static const char msg[] = "<5>PIXEL PID1: requesting normal reboot\n";
        write(fd, msg, sizeof(msg) - 1);
    }
    reboot(RB_AUTOBOOT);
    for (;;) pause();
}
