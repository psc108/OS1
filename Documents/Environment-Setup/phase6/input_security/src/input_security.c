#define _POSIX_C_SOURCE 199309L
#include "input_security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <syslog.h>
#include <errno.h>
#include <unistd.h>
#include <stdbool.h>

#define MAX_INPUT_RATE_PER_SEC 1000
#define NSEC_PER_SEC 1000000000L

int validate_input_event(struct input_event *event, struct input_security_context *ctx) {
    if (!event || !ctx) {
        return -EINVAL;
    }
    
    switch (event->type) {
    case EV_KEY:
        if (!ctx->keyboard_allowed) {
            audit_log_input_violation("Keyboard input not allowed", ctx);
            return -EPERM;
        }
        break;
        
    case EV_REL:
    case EV_ABS:
        if (event->code >= BTN_MOUSE && event->code < BTN_JOYSTICK) {
            if (!ctx->mouse_allowed) {
                audit_log_input_violation("Mouse input not allowed", ctx);
                return -EPERM;
            }
        } else if (event->code >= ABS_X && event->code <= ABS_PRESSURE) {
            if (!ctx->touch_allowed) {
                audit_log_input_violation("Touch input not allowed", ctx);
                return -EPERM;
            }
        }
        break;
        
    default:
        /* Allow other event types by default */
        break;
    }
    
    return check_input_rate_limit(ctx);
}

int apply_input_filtering(struct input_event *event, struct input_security_context *ctx) {
    if (!event || !ctx) {
        return -EINVAL;
    }
    
    /* Filter dangerous key combinations for high security contexts */
    if (ctx->security_level >= 2 && event->type == EV_KEY) {
        /* Block dangerous keys like Alt+F4, Ctrl+Alt+Del, etc. */
        switch (event->code) {
        case KEY_SYSRQ:
        case KEY_PAUSE:
        case KEY_SCROLLLOCK:
            audit_log_input_violation("Dangerous key blocked", ctx);
            return -EPERM;
        default:
            break;
        }
    }
    
    return 0;
}

int check_input_rate_limit(struct input_security_context *ctx) {
    struct timespec current_time;
    long time_diff_ns;
    
    if (!ctx) {
        return -EINVAL;
    }
    
    clock_gettime(CLOCK_MONOTONIC, &current_time);
    
    time_diff_ns = (current_time.tv_sec - ctx->last_input_time.tv_sec) * NSEC_PER_SEC +
                   (current_time.tv_nsec - ctx->last_input_time.tv_nsec);
    
    /* Check if we're exceeding the rate limit */
    if (time_diff_ns < (NSEC_PER_SEC / MAX_INPUT_RATE_PER_SEC)) {
        audit_log_input_violation("Input rate limit exceeded", ctx);
        return -EBUSY;
    }
    
    ctx->last_input_time = current_time;
    return 0;
}

void audit_log_input_violation(const char *message, struct input_security_context *ctx) {
    syslog(LOG_WARNING | LOG_AUTH, 
           "SecureOS Input Security Violation: %s (PID=%d, UID=%d, Level=%d)",
           message, ctx->client_pid, ctx->client_uid, ctx->security_level);
}

/* Main function for testing */
int main(int argc, char *argv[]) {
    struct input_security_context ctx;
    struct input_event test_event;
    int ret;
    
    printf("SecureOS Input Security Framework v1.0\n");
    
    /* Initialize test context */
    ctx.client_pid = getpid();
    ctx.client_uid = getuid();
    ctx.security_level = 1;
    ctx.keyboard_allowed = true;
    ctx.mouse_allowed = true;
    ctx.touch_allowed = true;
    ctx.input_rate_limit = MAX_INPUT_RATE_PER_SEC;
    clock_gettime(CLOCK_MONOTONIC, &ctx.last_input_time);
    
    /* Test keyboard event */
    test_event.type = EV_KEY;
    test_event.code = KEY_A;
    test_event.value = 1;
    
    ret = validate_input_event(&test_event, &ctx);
    if (ret == 0) {
        printf("Keyboard event validation test: PASSED\n");
    } else {
        printf("Keyboard event validation test: FAILED (%s)\n", strerror(-ret));
    }
    
    /* Test input filtering */
    test_event.code = KEY_SYSRQ;
    ctx.security_level = 2;
    
    ret = apply_input_filtering(&test_event, &ctx);
    if (ret == -EPERM) {
        printf("Dangerous key filtering test: PASSED\n");
    } else {
        printf("Dangerous key filtering test: FAILED\n");
    }
    
    printf("Input security framework tests completed\n");
    return 0;
}
