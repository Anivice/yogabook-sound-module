// vibrate.c
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stop_requested = 0;

static void handle_signal(int sig)
{
    (void)sig;
    stop_requested = 1;
}

static int send_ff(int fd, int effect_id, int value)
{
    struct input_event ev = {
        .type = EV_FF,
        .code = (uint16_t)effect_id,
        .value = value,
    };

    ssize_t n = write(fd, &ev, sizeof(ev));
    if (n != sizeof(ev)) {
        if (n < 0)
            perror("write(EV_FF)");
        else
            fprintf(stderr, "short write to input device\n");
        return -1;
    }

    return 0;
}

static void sleep_ms(unsigned int ms)
{
    struct timespec req = {
        .tv_sec = ms / 1000,
        .tv_nsec = (long)(ms % 1000) * 1000000L,
    };

    while (!stop_requested && nanosleep(&req, &req) < 0) {
        if (errno != EINTR) {
            perror("nanosleep");
            break;
        }
    }
}

static unsigned long parse_ulong(const char *s, const char *name)
{
    char *end = NULL;
    errno = 0;

    unsigned long v = strtoul(s, &end, 10);

    if (errno || !s[0] || !end || *end != '\0') {
        fprintf(stderr, "Invalid %s: %s\n", name, s);
        exit(EXIT_FAILURE);
    }

    return v;
}

int main(int argc, char **argv)
{
    /*
     * Usage:
     *
     *   vibrate /dev/input/event27
     *   vibrate /dev/input/event27 50
     *   vibrate /dev/input/event27 100 1000
     *   vibrate /dev/input/event27 100 0
     *
     * strength:    1..100 percent
     * duration_ms: 1..60000 milliseconds
     *              0 = continuous until Ctrl-C
     */

    if (argc < 2 || argc > 4) {
        fprintf(stderr,
                "Usage: %s DEVICE [STRENGTH_PERCENT] [DURATION_MS]\n"
                "\n"
                "  DEVICE            e.g. /dev/input/event27\n"
                "  STRENGTH_PERCENT  1..100, default 100\n"
                "  DURATION_MS       1..60000, default 1000\n"
                "                    0 = run until Ctrl-C\n",
                argv[0]);
        return EXIT_FAILURE;
    }

    const char *device = argv[1];
    unsigned long strength = argc >= 3
                           ? parse_ulong(argv[2], "strength")
                           : 100;
    unsigned long duration = argc >= 4
                           ? parse_ulong(argv[3], "duration")
                           : 1000;

    if (strength < 1 || strength > 100) {
        fprintf(stderr, "Strength must be between 1 and 100\n");
        return EXIT_FAILURE;
    }

    if (duration > 60000) {
        fprintf(stderr,
                "Duration must be 0 (continuous) or at most 60000 ms\n");
        return EXIT_FAILURE;
    }

    int fd = open(device, O_RDWR);
    if (fd < 0) {
        perror(device);
        return EXIT_FAILURE;
    }

    char name[256] = {0};
    if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0)
        printf("Device: %s (%s)\n", name, device);

    struct sigaction sa = {
        .sa_handler = handle_signal,
    };

    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    /*
     * Linux FF magnitudes use 0..65535.
     *
     * drv260x_haptics_play() takes strong_magnitude first and scales it
     * to the DRV260x 8-bit RTP register.
     */
    uint16_t magnitude =
        (uint16_t)((strength * 65535UL) / 100UL);

    struct ff_effect effect;
    memset(&effect, 0, sizeof(effect));

    effect.type = FF_RUMBLE;

    /*
     * -1 tells EVIOCSFF to allocate a new effect ID.
     */
    effect.id = -1;

    effect.u.rumble.strong_magnitude = magnitude;
    effect.u.rumble.weak_magnitude = 0;

    /*
     * ff_effect.replay.length is a 16-bit millisecond field.
     *
     * For "continuous" mode we upload a 60-second effect and retrigger
     * it every 50 seconds until Ctrl-C.
     */
    effect.replay.length =
        duration == 0 ? 60000 : (uint16_t)duration;

    effect.replay.delay = 0;

    /*
     * Upload the effect. This does NOT start playback.
     */
    if (ioctl(fd, EVIOCSFF, &effect) < 0) {
        perror("ioctl(EVIOCSFF)");
        close(fd);
        return EXIT_FAILURE;
    }

    printf("Effect ID: %d\n", effect.id);
    printf("Strength:  %lu%%\n", strength);

    if (duration == 0)
        printf("Vibrating continuously. Press Ctrl-C to stop.\n");
    else
        printf("Vibrating for %lu ms...\n", duration);

    /*
     * EV_FF, code=effect.id, value=1 starts one playback.
     */
    if (send_ff(fd, effect.id, 1) < 0)
        goto cleanup;

    if (duration != 0) {
        sleep_ms((unsigned int)duration);
    } else {
        /*
         * Keep a nominal 60-second effect alive indefinitely.
         * Restart at 50 seconds so it never reaches expiry.
         */
        while (!stop_requested) {
            sleep_ms(50000);

            if (stop_requested)
                break;

            if (send_ff(fd, effect.id, 1) < 0)
                break;
        }
    }

cleanup:
    /*
     * value=0 explicitly stops playback.
     */
    printf("\nStopping vibration...\n");
    send_ff(fd, effect.id, 0);

    /*
     * Remove the uploaded effect. EVIOCRMFF also stops it if necessary.
     */
    if (ioctl(fd, EVIOCRMFF, effect.id) < 0)
        perror("ioctl(EVIOCRMFF)");

    close(fd);

    return EXIT_SUCCESS;
}
