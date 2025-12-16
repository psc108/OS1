#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mount.h>
#include <errno.h>
#include <sched.h>
#include "../include/container_security.h"

int validate_container_policy(struct container_policy *policy) {
    if (!policy || !policy->name[0]) {
        return -EINVAL;
    }
    
    if (policy->allowed_uid_min > policy->allowed_uid_max) {
        return -EINVAL;
    }
    
    if (policy->allowed_gid_min > policy->allowed_gid_max) {
        return -EINVAL;
    }
    
    if (policy->memory_limit == 0 || policy->cpu_limit == 0) {
        return -EINVAL;
    }
    
    return 0;
}

int apply_container_security(struct container_runtime *runtime) {
    if (!runtime) {
        return -EINVAL;
    }
    
    // Apply cgroup limits
    char cgroup_path[256];
    snprintf(cgroup_path, sizeof(cgroup_path), 
             "/sys/fs/cgroup/memory/containers/%s", runtime->container_id);
    
    FILE *memory_limit = fopen(cgroup_path, "w");
    if (memory_limit) {
        fprintf(memory_limit, "%lu", runtime->policy.memory_limit);
        fclose(memory_limit);
    }
    
    // Apply network isolation
    if (runtime->policy.network_isolation) {
        // Create isolated network namespace
        if (unshare(0x40000000) < 0) { // CLONE_NEWNET
            return -errno;
        }
    }
    
    return 0;
}

int create_container(struct container_policy *policy, const char *image_path) {
    if (!policy || !image_path) {
        return -EINVAL;
    }
    
    int ret = validate_container_policy(policy);
    if (ret < 0) {
        return ret;
    }
    
    pid_t pid = fork();
    if (pid < 0) {
        return -errno;
    }
    
    if (pid == 0) {
        // Container initialization
        struct container_runtime runtime;
        strncpy(runtime.container_id, policy->name, sizeof(runtime.container_id) - 1);
        runtime.container_pid = getpid();
        runtime.policy = *policy;
        runtime.status = 1;
        
        ret = apply_container_security(&runtime);
        if (ret < 0) {
            _exit(EXIT_FAILURE);
        }
        
        // Execute container image
        execl("/bin/sh", "sh", "-c", image_path, NULL);
        _exit(EXIT_FAILURE);
    }
    
    return pid;
}

int monitor_container_security(struct container_runtime *runtime) {
    if (!runtime) {
        return -EINVAL;
    }
    
    // Monitor resource usage
    char proc_path[256];
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/status", runtime->container_pid);
    
    FILE *status_file = fopen(proc_path, "r");
    if (!status_file) {
        return -errno;
    }
    
    char line[256];
    while (fgets(line, sizeof(line), status_file)) {
        if (strncmp(line, "VmRSS:", 6) == 0) {
            unsigned long memory_usage;
            if (sscanf(line, "VmRSS: %lu kB", &memory_usage) == 1) {
                if (memory_usage * 1024 > runtime->policy.memory_limit) {
                    fclose(status_file);
                    return -ENOMEM;
                }
            }
        }
    }
    
    fclose(status_file);
    return 0;
}

/* Test main function for compilation validation */
int main(int argc, char *argv[]) {
    printf("SecureOS Container Runtime - Compilation Test Passed\n");
    return 0;
}
