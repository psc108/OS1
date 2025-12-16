#define _GNU_SOURCE
#include "client_isolation.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <syslog.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sched.h>
#include <stdbool.h>

int create_client_isolation(pid_t client_pid, struct client_isolation_context **ctx) {
    struct client_isolation_context *isolation_ctx;
    pid_t pid = client_pid;
    uid_t uid;
    gid_t gid;
    char proc_path[256];
    FILE *status_file;
    
    if (client_pid <= 0 || !ctx) {
        return -EINVAL;
    }
    
    /* Get UID/GID from /proc/PID/status */
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/status", pid);
    status_file = fopen(proc_path, "r");
    if (!status_file) {
        return -ENOENT;
    }
    
    char line[256];
    uid = gid = -1;
    while (fgets(line, sizeof(line), status_file)) {
        if (sscanf(line, "Uid:\t%u", &uid) == 1) continue;
        if (sscanf(line, "Gid:\t%u", &gid) == 1) break;
    }
    fclose(status_file);
    
    if (uid == (uid_t)-1 || gid == (gid_t)-1) {
        return -EINVAL;
    }
    
    isolation_ctx = calloc(1, sizeof(*isolation_ctx));
    if (!isolation_ctx) {
        return -ENOMEM;
    }
    
    isolation_ctx->client_fd = -1;
    isolation_ctx->pid = pid;
    isolation_ctx->uid = uid;
    isolation_ctx->gid = gid;
    
    /* Set default resource limits */
    isolation_ctx->memory_limit = 128 * 1024 * 1024; /* 128MB */
    isolation_ctx->cpu_limit = 10; /* 10% CPU */
    
    /* Set default protocol permissions based on UID */
    if (uid == 0) {
        isolation_ctx->allowed_protocols = 0xFFFFFFFF;
        isolation_ctx->network_allowed = true;
        isolation_ctx->filesystem_access = true;
    } else if (uid < 1000) {
        isolation_ctx->allowed_protocols = PROTOCOL_GUI_COMPOSITOR | PROTOCOL_GUI_BUFFER;
        isolation_ctx->network_allowed = false;
        isolation_ctx->filesystem_access = false;
    } else {
        isolation_ctx->allowed_protocols = PROTOCOL_GUI_COMPOSITOR | PROTOCOL_GUI_BUFFER | 
                                          PROTOCOL_GUI_SHELL | PROTOCOL_GUI_INPUT | 
                                          PROTOCOL_GUI_OUTPUT;
        isolation_ctx->network_allowed = true;
        isolation_ctx->filesystem_access = true;
    }
    
    *ctx = isolation_ctx;
    return 0;
}

int apply_resource_limits(struct client_isolation_context *ctx) {
    char cgroup_path[256];
    char limit_str[64];
    FILE *fp;
    
    if (!ctx) {
        return -EINVAL;
    }
    
    /* Create cgroup for client */
    snprintf(cgroup_path, sizeof(cgroup_path), 
             "/sys/fs/cgroup/secureos/client_%d", ctx->pid);
    
    if (mkdir(cgroup_path, 0755) < 0 && errno != EEXIST) {
        syslog(LOG_ERR, "Failed to create cgroup: %s", strerror(errno));
        return -errno;
    }
    
    ctx->cgroup_path = strdup(cgroup_path);
    
    /* Set memory limit */
    snprintf(limit_str, sizeof(limit_str), "%s/memory.max", cgroup_path);
    fp = fopen(limit_str, "w");
    if (fp) {
        fprintf(fp, "%lu", ctx->memory_limit);
        fclose(fp);
    }
    
    /* Set CPU limit */
    snprintf(limit_str, sizeof(limit_str), "%s/cpu.max", cgroup_path);
    fp = fopen(limit_str, "w");
    if (fp) {
        fprintf(fp, "%lu 100000", ctx->cpu_limit * 1000);
        fclose(fp);
    }
    
    /* Add process to cgroup */
    snprintf(limit_str, sizeof(limit_str), "%s/cgroup.procs", cgroup_path);
    fp = fopen(limit_str, "w");
    if (fp) {
        fprintf(fp, "%d", ctx->pid);
        fclose(fp);
    }
    
    syslog(LOG_INFO, "Applied resource limits for client PID %d", ctx->pid);
    return 0;
}

int setup_client_namespace(struct client_isolation_context *ctx) {
    char namespace_path[256];
    
    if (!ctx) {
        return -EINVAL;
    }
    
    /* Create namespace directory */
    snprintf(namespace_path, sizeof(namespace_path), 
             "/tmp/secureos_ns_%d", ctx->pid);
    
    if (mkdir(namespace_path, 0700) < 0 && errno != EEXIST) {
        return -errno;
    }
    
    ctx->namespace_path = strdup(namespace_path);
    
    /* The actual namespace setup would be done in the client process */
    syslog(LOG_INFO, "Namespace setup prepared for client PID %d", ctx->pid);
    return 0;
}

int validate_protocol_access(struct client_isolation_context *ctx, const char *protocol) {
    uint32_t protocol_flag = 0;
    
    if (!ctx || !protocol) {
        return -EINVAL;
    }
    
    /* Map protocol name to flag */
    if (strcmp(protocol, "gui_compositor") == 0) {
        protocol_flag = PROTOCOL_GUI_COMPOSITOR;
    } else if (strcmp(protocol, "gui_buffer") == 0) {
        protocol_flag = PROTOCOL_GUI_BUFFER;
    } else if (strcmp(protocol, "gui_shell") == 0) {
        protocol_flag = PROTOCOL_GUI_SHELL;
    } else if (strcmp(protocol, "gui_input") == 0) {
        protocol_flag = PROTOCOL_GUI_INPUT;
    } else if (strcmp(protocol, "gui_output") == 0) {
        protocol_flag = PROTOCOL_GUI_OUTPUT;
    } else if (strcmp(protocol, "gui_window") == 0) {
        protocol_flag = PROTOCOL_GUI_WINDOW;
    } else {
        syslog(LOG_WARNING, "Unknown protocol access attempt: %s", protocol);
        return -EPERM;
    }
    
    if (!(ctx->allowed_protocols & protocol_flag)) {
        syslog(LOG_WARNING, "Protocol access denied for PID %d: %s", 
               ctx->pid, protocol);
        return -EPERM;
    }
    
    return 0;
}

void cleanup_client_isolation(struct client_isolation_context *ctx) {
    if (!ctx) {
        return;
    }
    
    /* Remove from cgroup */
    if (ctx->cgroup_path) {
        rmdir(ctx->cgroup_path);
        free(ctx->cgroup_path);
    }
    
    /* Clean up namespace */
    if (ctx->namespace_path) {
        rmdir(ctx->namespace_path);
        free(ctx->namespace_path);
    }
    
    syslog(LOG_INFO, "Cleaned up isolation for client PID %d", ctx->pid);
    free(ctx);
}

/* Main function for testing */
int main(int argc, char *argv[]) {
    struct client_isolation_context *ctx;
    int ret;
    
    printf("SecureOS Client Isolation Framework v1.0\n");
    
    /* Test client isolation creation */
    ret = create_client_isolation(getpid(), &ctx);
    if (ret == 0) {
        printf("Client isolation creation test: PASSED\n");
        
        /* Test protocol validation */
        ret = validate_protocol_access(ctx, "gui_compositor");
        if (ret == 0) {
            printf("Protocol access validation test: PASSED\n");
        } else {
            printf("Protocol access validation test: FAILED (%s)\n", strerror(-ret));
        }
        
        /* Test resource limits */
        ret = apply_resource_limits(ctx);
        if (ret == 0) {
            printf("Resource limits application test: PASSED\n");
        } else {
            printf("Resource limits application test: FAILED (%s)\n", strerror(-ret));
        }
        
        cleanup_client_isolation(ctx);
        printf("Client isolation cleanup: COMPLETED\n");
    } else {
        printf("Client isolation creation test: FAILED (%s)\n", strerror(-ret));
        return 1;
    }
    
    printf("Client isolation framework tests completed\n");
    return 0;
}
