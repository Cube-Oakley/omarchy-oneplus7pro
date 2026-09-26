/* PID 1 that does nothing. Lets a panic hang or a hold-through keep ramoops.
 * Do not reboot — reboot() tore console pstore on this device. */
#include <unistd.h>

int main(void) {
  for (;;)
    pause();
}
