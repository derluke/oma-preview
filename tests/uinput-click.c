#include <errno.h>
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <stdlib.h>

static int emit(int fd, int type, int code, int value) {
    struct input_event event = {0};
    event.type = type;
    event.code = code;
    event.value = value;
    return write(fd, &event, sizeof(event)) == sizeof(event) ? 0 : -1;
}

int main(int argc, char **argv) {
    if (argc != 5 && argc != 7) {
        fprintf(stderr, "usage: %s X Y MAX_X MAX_Y [END_X END_Y]\n", argv[0]);
        return 2;
    }
    int x = atoi(argv[1]);
    int y = atoi(argv[2]);
    int max_x = atoi(argv[3]);
    int max_y = atoi(argv[4]);
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        fprintf(stderr, "open /dev/uinput: %s\n", strerror(errno));
        return 1;
    }
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_KEYBIT, BTN_LEFT);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_ABSBIT, ABS_X);
    ioctl(fd, UI_SET_ABSBIT, ABS_Y);
    struct uinput_abs_setup x_setup = {.code = ABS_X, .absinfo = {.minimum = 0, .maximum = max_x}};
    struct uinput_abs_setup y_setup = {.code = ABS_Y, .absinfo = {.minimum = 0, .maximum = max_y}};
    ioctl(fd, UI_ABS_SETUP, &x_setup);
    ioctl(fd, UI_ABS_SETUP, &y_setup);

    struct uinput_setup setup = {0};
    setup.id.bustype = BUS_USB;
    setup.id.vendor = 0x1234;
    setup.id.product = 0x5678;
    snprintf(setup.name, UINPUT_MAX_NAME_SIZE, "folio-ui-test-pointer");
    if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
        fprintf(stderr, "create uinput device: %s\n", strerror(errno));
        close(fd);
        return 1;
    }
    usleep(150000);
    emit(fd, EV_ABS, ABS_X, x);
    emit(fd, EV_ABS, ABS_Y, y);
    emit(fd, EV_SYN, SYN_REPORT, 0);
    emit(fd, EV_KEY, BTN_LEFT, 1);
    emit(fd, EV_SYN, SYN_REPORT, 0);
    usleep(30000);
    if (argc == 7) {
        int end_x = atoi(argv[5]);
        int end_y = atoi(argv[6]);
        for (int step = 1; step <= 10; step++) {
            emit(fd, EV_ABS, ABS_X, x + (end_x - x) * step / 10);
            emit(fd, EV_ABS, ABS_Y, y + (end_y - y) * step / 10);
            emit(fd, EV_SYN, SYN_REPORT, 0);
            usleep(12000);
        }
    }
    emit(fd, EV_KEY, BTN_LEFT, 0);
    emit(fd, EV_SYN, SYN_REPORT, 0);
    usleep(50000);
    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}
