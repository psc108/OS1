#ifndef APP_SANDBOX_H
#define APP_SANDBOX_H

#include <sys/types.h>
#include <linux/capability.h>

#define MAX_APP_NAME 64
#define MAX_POLICY_RULES 256
#define MAX_ALLOWED_FILES 128
#define MAX_ALLOWED_SYSCALLS 64

struct app_sandbox_policy {
    char app_name[MAX_APP_NAME];
    uid_t sandbox_uid;
    gid_t sandbox_gid;
    unsigned long allowed_capabilities;
    char allowed_files[MAX_ALLOWED_FILES][256];
    int file_count;
    int allowed_syscalls[MAX_ALLOWED_SYSCALLS];
    int syscall_count;
    unsigned long memory_limit;
    unsigned long cpu_limit;
    int network_access;
    int filesystem_access;
    int x11_access;
};

struct app_sandbox_context {
    pid_t sandbox_pid;
    struct app_sandbox_policy policy;
    int status;
    time_t start_time;
};

int create_app_sandbox(struct app_sandbox_policy *policy, const char *app_path, char **argv);
int validate_app_policy(struct app_sandbox_policy *policy);
int load_app_policies(const char *policy_dir);
int monitor_app_sandbox(struct app_sandbox_context *ctx);
int terminate_app_sandbox(struct app_sandbox_context *ctx);

#endif /* APP_SANDBOX_H */
