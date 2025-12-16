#ifndef SECURE_SANDBOX_H
#define SECURE_SANDBOX_H

#include <sys/types.h>
#include <linux/capability.h>

#define MAX_SYSCALLS 512
#define MAX_MOUNTS 64
#define MAX_ENV_VARS 128

struct sandbox_limits {
    unsigned long max_memory;
    unsigned long max_cpu_time;
    unsigned long max_file_size;
    unsigned int max_processes;
    unsigned int max_open_files;
};

struct sandbox_mount {
    char source[256];
    char target[256];
    char fstype[32];
    unsigned long flags;
    int readonly;
};

struct sandbox_config {
    char program[256];
    char **argv;
    char **envp;
    uid_t uid;
    gid_t gid;
    unsigned long allowed_syscalls[MAX_SYSCALLS/64];
    unsigned long required_caps;
    struct sandbox_limits limits;
    struct sandbox_mount mounts[MAX_MOUNTS];
    int mount_count;
    int network_access;
    int x11_access;
};

int create_secure_sandbox(struct sandbox_config *config);
int validate_sandbox_config(struct sandbox_config *config);
int setup_sandbox_mounts(struct sandbox_config *config);
int apply_seccomp_filter(unsigned long *allowed_syscalls);
int drop_all_capabilities_except(unsigned long required_caps);
int apply_resource_limits(struct sandbox_limits *limits);
int change_to_sandbox_user(uid_t uid, gid_t gid);

#endif /* SECURE_SANDBOX_H */
