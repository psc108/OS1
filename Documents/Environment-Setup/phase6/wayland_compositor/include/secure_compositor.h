#ifndef SECURE_COMPOSITOR_H
#define SECURE_COMPOSITOR_H

#include <sys/types.h>
#include <linux/input.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <time.h>
#include <stdbool.h>

/* Security context for GUI clients */
struct secure_client_context {
    pid_t pid;
    uid_t uid;
    gid_t gid;
    char *security_label;
    uint32_t permissions;
    uint64_t resource_limits;
    struct timespec creation_time;
};

/* Secure surface with MAC controls */
struct secure_surface {
    int surface_fd;
    struct secure_client_context *client_ctx;
    void *pending_buffer;
    void *current_buffer;
    uint32_t security_level;
    bool input_allowed;
    bool output_allowed;
};

/* Compositor security operations */
int secure_compositor_init(void);
void secure_compositor_cleanup(void);
struct secure_client_context *get_client_security_context(pid_t client_pid);
int validate_surface_permissions(struct secure_client_context *ctx, 
                                struct secure_surface *surface, uint32_t operation);
int validate_buffer_security(void *buffer, struct secure_client_context *ctx);
int apply_surface_mac_policy(struct secure_surface *surface, struct secure_client_context *ctx);
void audit_log_compositor_violation(const char *message);
void audit_log_surface_commit(pid_t client_pid, struct secure_surface *surface);

/* Surface operations */
#define SURFACE_OP_COMMIT    0x01
#define SURFACE_OP_DAMAGE    0x02
#define SURFACE_OP_ATTACH    0x04
#define SURFACE_OP_INPUT     0x08

/* Security levels */
#define SECURITY_LEVEL_PUBLIC     0
#define SECURITY_LEVEL_INTERNAL   1
#define SECURITY_LEVEL_RESTRICTED 2
#define SECURITY_LEVEL_SECRET     3

#endif /* SECURE_COMPOSITOR_H */
