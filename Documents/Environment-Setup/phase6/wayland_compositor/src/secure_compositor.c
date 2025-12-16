#include "secure_compositor.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <syslog.h>
#include <sys/socket.h>
#include <linux/audit.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/eventfd.h>
#define _GNU_SOURCE
#include <time.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

static int compositor_fd = -1;
static int event_fd = -1;

/* Security context management */
struct secure_client_context *get_client_security_context(pid_t client_pid) {
    struct secure_client_context *ctx;
    pid_t pid = client_pid;
    uid_t uid;
    gid_t gid;
    char proc_path[256];
    FILE *status_file;
    
    if (pid <= 0) {
        return NULL;
    }
    
    /* Get UID/GID from /proc/PID/status */
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/status", pid);
    status_file = fopen(proc_path, "r");
    if (!status_file) {
        return NULL;
    }
    
    char line[256];
    uid = gid = -1;
    while (fgets(line, sizeof(line), status_file)) {
        if (sscanf(line, "Uid:\t%u", &uid) == 1) continue;
        if (sscanf(line, "Gid:\t%u", &gid) == 1) break;
    }
    fclose(status_file);
    
    if (uid == (uid_t)-1 || gid == (gid_t)-1) {
        return NULL;
    }
    
    ctx = calloc(1, sizeof(*ctx));
    if (!ctx) {
        return NULL;
    }
    
    ctx->pid = pid;
    ctx->uid = uid;
    ctx->gid = gid;
    /* Set creation time to 0 for now */
    ctx->creation_time.tv_sec = 0;
    ctx->creation_time.tv_nsec = 0;
    
    /* Set security label from proc filesystem */
    char label_path[256];
    snprintf(label_path, sizeof(label_path), "/proc/%d/attr/current", pid);
    FILE *label_file = fopen(label_path, "r");
    if (label_file) {
        char label[256];
        if (fgets(label, sizeof(label), label_file)) {
            size_t len = strlen(label);
            ctx->security_label = malloc(len + 1);
            if (ctx->security_label) {
                strcpy(ctx->security_label, label);
            }
        }
        fclose(label_file);
    }
    
    /* Set default permissions based on UID */
    if (uid == 0) {
        ctx->permissions = 0xFFFFFFFF; /* Root has all permissions */
    } else if (uid < 1000) {
        ctx->permissions = 0x0000000F; /* System users limited */
    } else {
        ctx->permissions = 0x000000FF; /* Regular users standard */
    }
    
    return ctx;
}

int validate_surface_permissions(struct secure_client_context *ctx, 
                                struct secure_surface *surface, uint32_t operation) {
    if (!ctx || !surface) {
        return -EINVAL;
    }
    
    /* Check if operation is allowed for this client */
    if (!(ctx->permissions & operation)) {
        audit_log_compositor_violation("Operation not permitted");
        return -EPERM;
    }
    
    /* Check security level compatibility */
    if (surface->security_level > SECURITY_LEVEL_PUBLIC && ctx->uid >= 1000) {
        audit_log_compositor_violation("Security level violation");
        return -EACCES;
    }
    
    return 0;
}

int validate_buffer_security(void *buffer, struct secure_client_context *ctx) {
    if (!buffer || !ctx) {
        return -EINVAL;
    }
    
    /* Validate buffer memory mapping permissions */
    if (mlock(buffer, 4096) != 0) {
        audit_log_compositor_violation("Buffer memory validation failed");
        return -EACCES;
    }
    munlock(buffer, 4096);
    
    return 0;
}

int apply_surface_mac_policy(struct secure_surface *surface, struct secure_client_context *ctx) {
    if (!surface || !ctx) {
        return -EINVAL;
    }
    
    /* Apply Mandatory Access Control policy */
    if (ctx->security_label) {
        /* Check SELinux policy for surface operations */
        if (strstr(ctx->security_label, "unconfined") == NULL) {
            /* Confined processes have restricted surface access */
            surface->input_allowed = false;
            surface->output_allowed = (ctx->uid >= 1000);
        } else {
            surface->input_allowed = true;
            surface->output_allowed = true;
        }
    }
    
    return 0;
}

void audit_log_compositor_violation(const char *message) {
    syslog(LOG_WARNING | LOG_AUTH, "SecureOS Compositor Security Violation: %s", message);
}

void audit_log_surface_commit(pid_t client_pid, struct secure_surface *surface) {
    syslog(LOG_INFO, "Surface commit: PID=%d Security=%d", 
           client_pid, surface->security_level);
}

/* Secure surface commit handler */
int secure_handle_surface_commit(pid_t client_pid, struct secure_surface *surface) {
    struct secure_client_context *ctx;
    int ret;

    if (!surface || client_pid <= 0) {
        return -EINVAL;
    }

    ctx = get_client_security_context(client_pid);
    if (!ctx) {
        audit_log_compositor_violation("Missing security context");
        return -EACCES;
    }

    ret = validate_surface_permissions(ctx, surface, SURFACE_OP_COMMIT);
    if (ret < 0) {
        audit_log_compositor_violation("Surface permission denied");
        free(ctx);
        return ret;
    }

    if (surface->pending_buffer) {
        ret = validate_buffer_security(surface->pending_buffer, ctx);
        if (ret < 0) {
            audit_log_compositor_violation("Buffer validation failed");
            free(ctx);
            return ret;
        }
    }

    ret = apply_surface_mac_policy(surface, ctx);
    if (ret < 0) {
        audit_log_compositor_violation("MAC policy violation");
        free(ctx);
        return ret;
    }

    /* Commit the surface securely */
    if (surface->pending_buffer) {
        surface->current_buffer = surface->pending_buffer;
        surface->pending_buffer = NULL;
    }

    audit_log_surface_commit(client_pid, surface);
    free(ctx);
    return 0;
}

/* Surface operations using direct syscalls */
int secure_surface_create(pid_t client_pid, struct secure_surface **surface) {
    struct secure_surface *surf;
    
    surf = calloc(1, sizeof(*surf));
    if (!surf) {
        return -ENOMEM;
    }
    
    surf->surface_fd = eventfd(0, EFD_CLOEXEC);
    if (surf->surface_fd < 0) {
        free(surf);
        return -errno;
    }
    
    surf->client_ctx = get_client_security_context(client_pid);
    if (!surf->client_ctx) {
        close(surf->surface_fd);
        free(surf);
        return -EACCES;
    }
    
    *surface = surf;
    return 0;
}

int secure_compositor_init(void) {
    compositor_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (compositor_fd < 0) {
        return -errno;
    }
    
    event_fd = eventfd(0, EFD_CLOEXEC);
    if (event_fd < 0) {
        close(compositor_fd);
        return -errno;
    }
    
    openlog("secureos-compositor", LOG_PID | LOG_CONS, LOG_AUTH);
    syslog(LOG_INFO, "Secure GUI compositor initialized");
    
    return 0;
}

void secure_compositor_cleanup(void) {
    if (compositor_fd >= 0) {
        close(compositor_fd);
        compositor_fd = -1;
    }
    
    if (event_fd >= 0) {
        close(event_fd);
        event_fd = -1;
    }
    
    closelog();
}

/* Main function for testing */
int main(int argc, char *argv[]) {
    int ret;
    
    printf("SecureOS Secure Compositor v1.0\n");
    
    ret = secure_compositor_init();
    if (ret < 0) {
        fprintf(stderr, "Failed to initialize compositor: %s\n", strerror(-ret));
        return 1;
    }
    
    printf("Compositor initialized successfully\n");
    
    /* Test surface creation */
    struct secure_surface *test_surface;
    ret = secure_surface_create(getpid(), &test_surface);
    if (ret == 0) {
        printf("Surface creation test: PASSED\n");
        close(test_surface->surface_fd);
        free(test_surface->client_ctx);
        free(test_surface);
    } else {
        printf("Surface creation test: FAILED (%s)\n", strerror(-ret));
    }
    
    secure_compositor_cleanup();
    printf("Compositor cleanup completed\n");
    
    return 0;
}
