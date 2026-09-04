#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int emit(int fd, int type, int code, int value) {
    struct input_event event = {0};
    event.type = type;
    event.code = code;
    event.value = value;
    return write(fd, &event, sizeof(event)) == sizeof(event) ? 0 : -1;
}

static void contact(int fd, int slot, int tracking_id, int x, int y) {
    emit(fd, EV_ABS, ABS_MT_SLOT, slot);
    emit(fd, EV_ABS, ABS_MT_TRACKING_ID, tracking_id);
    if (tracking_id >= 0) {
        emit(fd, EV_ABS, ABS_MT_POSITION_X, x);
        emit(fd, EV_ABS, ABS_MT_POSITION_Y, y);
    }
}

static void setup_axis(int fd, int code, int maximum) {
    ioctl(fd, UI_SET_ABSBIT, code);
    struct uinput_abs_setup setup = {
        .code = code,
        .absinfo = {.minimum = 0, .maximum = maximum},
    };
    ioctl(fd, UI_ABS_SETUP, &setup);
}

int main(int argc, char **argv) {
    if (argc != 7) {
        fprintf(stderr, "usage: %s CENTER_X CENTER_Y START_GAP END_GAP MAX_X MAX_Y\n", argv[0]);
        return 2;
    }
    int cx = atoi(argv[1]), cy = atoi(argv[2]);
    int start_gap = atoi(argv[3]), end_gap = atoi(argv[4]);
    int max_x = atoi(argv[5]), max_y = atoi(argv[6]);
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        fprintf(stderr, "open /dev/uinput: %s\n", strerror(errno));
        return 1;
    }

    ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT);
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    setup_axis(fd, ABS_X, max_x);
    setup_axis(fd, ABS_Y, max_y);
    setup_axis(fd, ABS_MT_POSITION_X, max_x);
    setup_axis(fd, ABS_MT_POSITION_Y, max_y);
    setup_axis(fd, ABS_MT_SLOT, 1);
    setup_axis(fd, ABS_MT_TRACKING_ID, 65535);

    struct uinput_setup setup = {0};
    setup.id.bustype = BUS_USB;
    setup.id.vendor = 0x1234;
    setup.id.product = 0x5679;
    snprintf(setup.name, UINPUT_MAX_NAME_SIZE, "oma-preview-ui-test-pinch");
    if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
        fprintf(stderr, "create uinput device: %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    usleep(400000);
    contact(fd, 0, 1, cx - start_gap / 2, cy);
    contact(fd, 1, 2, cx + start_gap / 2, cy);
    emit(fd, EV_KEY, BTN_TOUCH, 1);
    emit(fd, EV_SYN, SYN_REPORT, 0);
    for (int step = 1; step <= 20; step++) {
        int gap = start_gap + (end_gap - start_gap) * step / 20;
        contact(fd, 0, 1, cx - gap / 2, cy);
        contact(fd, 1, 2, cx + gap / 2, cy);
        emit(fd, EV_SYN, SYN_REPORT, 0);
        usleep(16000);
    }
    contact(fd, 0, -1, 0, 0);
    contact(fd, 1, -1, 0, 0);
    emit(fd, EV_KEY, BTN_TOUCH, 0);
    emit(fd, EV_SYN, SYN_REPORT, 0);
    usleep(100000);
    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}
