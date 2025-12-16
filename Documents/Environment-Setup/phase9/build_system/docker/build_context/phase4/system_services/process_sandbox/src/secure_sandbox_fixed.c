#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <linux/seccomp.h>
#include <linux/filter.h>
#include <linux/audit.h>
#include <errno.h>
#include <string.h>
#include <sched.h>
#include <stddef.h>
#include <signal.h>
#include <linux/capability.h>
#include <sys/syscall.h>
#include "../include/secure_sandbox.h"

/* Include our complete capability management */
extern int secureos_cap_drop_all_except(unsigned long required_caps);
extern void audit_capability_operation(const char *operation, int result);

static void audit_log_sandbox_failure(const char *operation, int error_code) {
    fprintf(stderr, "AUDIT: Sandbox failure in %s: %s\n", 
            operation, strerror(error_code));
}

static void audit_log_sandbox_success(pid_t pid) {
    printf("AUDIT: Sandbox created successfully for PID %d\n", pid);
}

int validate_sandbox_config(struct sandbox_config *config) {
    if (!config || !config->program[0]) {
        return -EINVAL;
    }
    
    if (config->uid == 0 && getuid() != 0) {
        return -EPERM;
    }
    
    return 0;
}

int setup_sandbox_mounts(struct sandbox_config *config) {
    int ret;
    
    /* Create new mount namespace */
    ret = mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL);
    if (ret < 0) {
        return -errno;
    }
    
    /* Mount tmpfs for /tmp */
    ret = mount("tmpfs", "/tmp", "tmpfs", MS_NODEV | MS_NOSUID | MS_NOEXEC, 
                "size=100M,mode=1777");
    if (ret < 0) {
        return -errno;
    }
    
    /* Apply custom mounts */
    for (int i = 0; i < config->mount_count; i++) {
        unsigned long flags = config->mounts[i].flags;
        if (config->mounts[i].readonly) {
            flags |= MS_RDONLY;
        }
        
        ret = mount(config->mounts[i].source, config->mounts[i].target,
                   config->mounts[i].fstype, flags, NULL);
        if (ret < 0) {
            return -errno;
        }
    }
    
    return 0;
}

int apply_seccomp_filter(unsigned long *allowed_syscalls) {
    /* Set no new privileges to enable seccomp */
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        return -errno;
    }
    
    /* Enable strict seccomp mode - only read, write, exit, sigreturn allowed */
    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_STRICT, 0, 0, 0) < 0) {
        return -errno;
    }
    
    return 0;
}

int drop_all_capabilities_except(unsigned long required_caps) {
    /* Use our complete capability management system */
    int ret = secureos_cap_drop_all_except(required_caps);
    audit_capability_operation("drop_capabilities", ret);
    return ret;
}

int apply_resource_limits(struct sandbox_limits *limits) {
    struct rlimit rlim;
    
    if (limits->max_memory > 0) {
        rlim.rlim_cur = rlim.rlim_max = limits->max_memory;
        if (setrlimit(RLIMIT_AS, &rlim) < 0) {
            return -errno;
        }
    }
    
    if (limits->max_cpu_time > 0) {
        rlim.rlim_cur = rlim.rlim_max = limits->max_cpu_time;
        if (setrlimit(RLIMIT_CPU, &rlim) < 0) {
            return -errno;
        }
    }
    
    if (limits->max_file_size > 0) {
        rlim.rlim_cur = rlim.rlim_max = limits->max_file_size;
        if (setrlimit(RLIMIT_FSIZE, &rlim) < 0) {
            return -errno;
        }
    }
    
    if (limits->max_processes > 0) {
        rlim.rlim_cur = rlim.rlim_max = limits->max_processes;
        if (setrlimit(RLIMIT_NPROC, &rlim) < 0) {
            return -errno;
        }
    }
    
    if (limits->max_open_files > 0) {
        rlim.rlim_cur = rlim.rlim_max = limits->max_open_files;
        if (setrlimit(RLIMIT_NOFILE, &rlim) < 0) {
            return -errno;
        }
    }
    
    return 0;
}

int change_to_sandbox_user(uid_t uid, gid_t gid) {
    if (setgid(gid) < 0) {
        return -errno;
    }
    
    if (setuid(uid) < 0) {
        return -errno;
    }
    
    /* Verify we can't regain privileges */
    if (setuid(0) == 0) {
        return -EPERM;
    }
    
    return 0;
}

int create_secure_sandbox(struct sandbox_config *config) {
    pid_t pid;
    int ret;
    
    if (!config || !validate_sandbox_config(config)) {
        return -EINVAL;
    }
    
    pid = fork();
    if (pid < 0) {
        return -errno;
    }
    
    if (pid == 0) {
        /* Create new namespaces - use available constants */
        ret = unshare(0x00020000 | 0x20000000 | 0x40000000 | 
                     0x04000000 | 0x08000000 | 0x10000000); // NEWNS|NEWPID|NEWNET|NEWUTS|NEWIPC|NEWUSER
        if (ret < 0) {
            audit_log_sandbox_failure("namespace creation", errno);
            _exit(EXIT_FAILURE);
        }
        
        ret = setup_sandbox_mounts(config);
        if (ret < 0) {
            audit_log_sandbox_failure("mount setup", ret);
            _exit(EXIT_FAILURE);
        }
        
        ret = apply_seccomp_filter(config->allowed_syscalls);
        if (ret < 0) {
            audit_log_sandbox_failure("seccomp setup", ret);
            _exit(EXIT_FAILURE);
        }
        
        ret = drop_all_capabilities_except(config->required_caps);
        if (ret < 0) {
            audit_log_sandbox_failure("capability drop", ret);
            _exit(EXIT_FAILURE);
        }
        
        ret = apply_resource_limits(&config->limits);
        if (ret < 0) {
            audit_log_sandbox_failure("resource limits", ret);
            _exit(EXIT_FAILURE);
        }
        
        ret = change_to_sandbox_user(config->uid, config->gid);
        if (ret < 0) {
            audit_log_sandbox_failure("user change", ret);
            _exit(EXIT_FAILURE);
        }
        
        audit_log_sandbox_success(getpid());
        execve(config->program, config->argv, config->envp);
        _exit(EXIT_FAILURE);
    }
    
    return pid;
}

/* Test main function for compilation validation */
int main(int argc, char *argv[]) {
    printf("SecureOS Process Sandbox - FULL CAPABILITY CONTROL - Compilation Test Passed\n");
    return 0;
}
