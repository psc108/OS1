#ifndef CONTAINER_SECURITY_H
#define CONTAINER_SECURITY_H

#include <sys/types.h>

struct container_policy {
    char name[64];
    uid_t allowed_uid_min;
    uid_t allowed_uid_max;
    gid_t allowed_gid_min;
    gid_t allowed_gid_max;
    unsigned long memory_limit;
    unsigned long cpu_limit;
    int network_isolation;
    int filesystem_readonly;
    char allowed_syscalls[512];
};

struct container_runtime {
    char container_id[64];
    pid_t container_pid;
    struct container_policy policy;
    int status;
};

int create_container(struct container_policy *policy, const char *image_path);
int validate_container_policy(struct container_policy *policy);
int apply_container_security(struct container_runtime *runtime);
int monitor_container_security(struct container_runtime *runtime);

#endif /* CONTAINER_SECURITY_H */
