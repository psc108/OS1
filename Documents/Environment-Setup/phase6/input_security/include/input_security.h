#ifndef INPUT_SECURITY_H
#define INPUT_SECURITY_H

#include <linux/input.h>
#include <sys/types.h>
#include <stdint.h>
#include <stdbool.h>
#include <time.h>

/* Input security context */
struct input_security_context {
    pid_t client_pid;
    uid_t client_uid;
    uint32_t security_level;
    bool keyboard_allowed;
    bool mouse_allowed;
    bool touch_allowed;
    uint64_t input_rate_limit;
    struct timespec last_input_time;
};

/* Input validation functions */
int validate_input_event(struct input_event *event, struct input_security_context *ctx);
int apply_input_filtering(struct input_event *event, struct input_security_context *ctx);
int check_input_rate_limit(struct input_security_context *ctx);
void audit_log_input_violation(const char *message, struct input_security_context *ctx);

/* Input event types */
#define INPUT_TYPE_KEYBOARD  EV_KEY
#define INPUT_TYPE_POINTER   EV_REL
#define INPUT_TYPE_TOUCH     EV_ABS
#define INPUT_TYPE_TABLET    EV_MSC

#endif /* INPUT_SECURITY_H */
