/* Read-only evdev diagnostics; does not grab the device from the compositor. */
#include <linux/input.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <sys/ioctl.h>
int main(int argc, char **argv) {
    const char *node = argc > 1 ? argv[1] : "/dev/input/event0";
    int seconds = argc > 2 ? atoi(argv[2]) : 180;
    int fd = open(node, O_RDONLY | O_NONBLOCK);
    if (fd < 0) { perror(node); return 1; }
    setvbuf(stdout, NULL, _IONBF, 0);
    char name[256] = {0};
    ioctl(fd, EVIOCGNAME(sizeof(name)), name);
    printf("INPUT %s name=%s watching=%ds\n", node, name, seconds);
    for (unsigned code = ABS_MT_SLOT; code <= ABS_MT_TRACKING_ID; code++) {
        struct input_absinfo a;
        if (!ioctl(fd, EVIOCGABS(code), &a))
            printf("ABS code=%u range=%d..%d\n", code, a.minimum, a.maximum);
    }
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    time_t end = now.tv_sec + seconds;
    unsigned events = 0, syncs = 0, contacts = 0;
    for (;;) {
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (now.tv_sec >= end) break;
        struct pollfd p = { .fd = fd, .events = POLLIN };
        int ret = poll(&p, 1, 1000);
        if (ret < 0) { perror("poll"); return 1; }
        if (!(p.revents & POLLIN)) continue;
        struct input_event ev[64];
        ssize_t n = read(fd, ev, sizeof(ev));
        if (n <= 0) continue;
        for (size_t i = 0; i < (size_t)n / sizeof(*ev); i++) {
            events++;
            if (ev[i].type == EV_SYN && ev[i].code == SYN_REPORT) syncs++;
            if (ev[i].type == EV_ABS && ev[i].code == ABS_MT_TRACKING_ID && ev[i].value >= 0) contacts++;
            printf("%ld.%06ld type=%u code=%u value=%d\n", (long)ev[i].input_event_sec,
                   (long)ev[i].input_event_usec, ev[i].type, ev[i].code, ev[i].value);
        }
    }
    printf("SUMMARY events=%u syncs=%u contacts=%u\n", events, syncs, contacts);
    close(fd);
    return contacts ? 0 : 2;
}
