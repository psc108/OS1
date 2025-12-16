#ifndef CLIENT_ISOLATION_H
#define CLIENT_ISOLATION_H

#include <sys/types.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <stdbool.h>

/* Client isolation context */
struct client_isolation_context {
    int client_fd;
    pid_t pid;
    uid_t uid;
    gid_t gid;
    char *cgroup_path;
    char *namespace_path;
    uint32_t allowed_protocols;
    uint64_t memory_limit;
    uint64_t cpu_limit;
    bool network_allowed;
    bool filesystem_access;
};

/* Isolation operations */
int create_client_isolation(pid_t client_pid, struct client_isolation_context **ctx);
int apply_resource_limits(struct client_isolation_context *ctx);
int setup_client_namespace(struct client_isolation_context *ctx);
int validate_protocol_access(struct client_isolation_context *ctx, const char *protocol);
void cleanup_client_isolation(struct client_isolation_context *ctx);

/* Protocol permissions */
#define PROTOCOL_GUI_COMPOSITOR   0x0001
#define PROTOCOL_GUI_BUFFER       0x0002
#define PROTOCOL_GUI_SHELL        0x0004
#define PROTOCOL_GUI_INPUT        0x0008
#define PROTOCOL_GUI_OUTPUT       0x0010
#define PROTOCOL_GUI_WINDOW       0x0020

#endif /* CLIENT_ISOLATION_H */
