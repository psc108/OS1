#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stddef.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/resource.h>
#include <sched.h>
#include <signal.h>
#include <errno.h>
#include <string.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <linux/audit.h>

#ifndef SECCOMP_MODE_FILTER
#define SECCOMP_MODE_FILTER 2
#endif

#ifndef SECCOMP_RET_KILL
#define SECCOMP_RET_KILL 0x00000000U
#endif

#ifndef SECCOMP_RET_ALLOW
#define SECCOMP_RET_ALLOW 0x7fff0000U
#endif

typedef struct {
    char *program;
    char **argv;
    char **envp;
    uid_t uid;
    gid_t gid;
    char *chroot_dir;
    int *allowed_syscalls;
    int num_syscalls;
} sandbox_config_t;

// Simple seccomp filter using kernel syscalls directly
static int install_seccomp_filter(int *allowed_syscalls, int num_syscalls) {
    struct sock_filter filter[] = {
        /* Load architecture */
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, (offsetof(struct seccomp_data, arch))),
        /* Check architecture is x86_64 */
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0),
        /* Kill if wrong architecture */
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL),
        
        /* Load syscall number */
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, (offsetof(struct seccomp_data, nr))),
        
        /* Allow basic syscalls needed for operation */
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_read, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_write, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_exit, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_exit_group, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_brk, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_mmap, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_munmap, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        
        /* Kill everything else */
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL),
    };

    struct sock_fprog prog = {
        .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        perror("prctl(PR_SET_NO_NEW_PRIVS)");
        return -1;
    }

    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog) < 0) {
        perror("prctl(PR_SET_SECCOMP)");
        return -1;
    }

    return 0;
}

static int setup_namespaces(void) {
    // Create new namespaces for isolation
    if (unshare(CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWNET | 
                CLONE_NEWUTS | CLONE_NEWIPC | CLONE_NEWUSER) < 0) {
        perror("unshare");
        return -1;
    }
    
    // Remount proc filesystem in new PID namespace
    if (mount("proc", "/proc", "proc", MS_NOSUID | MS_NOEXEC | MS_NODEV, NULL) < 0) {
        // Non-fatal if we can't remount proc
        fprintf(stderr, "Warning: Could not remount /proc\n");
    }
    
    return 0;
}

static int drop_capabilities_manual(void) {
    // Drop capabilities using prctl (no libcap needed)
    
    // Clear capability bounding set
    for (int cap = 0; cap <= 37; cap++) {
        if (prctl(PR_CAPBSET_DROP, cap, 0, 0, 0) < 0) {
            // Some capabilities might not exist, continue
            continue;
        }
    }
    
    // Set no new privileges
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        perror("prctl(PR_SET_NO_NEW_PRIVS)");
        return -1;
    }
    
    return 0;
}

static int set_resource_limits(void) {
    struct rlimit limit;
    
    // Limit memory to 512MB
    limit.rlim_cur = limit.rlim_max = 512 * 1024 * 1024;
    if (setrlimit(RLIMIT_AS, &limit) < 0) {
        perror("setrlimit(RLIMIT_AS)");
        return -1;
    }
    
    // Limit number of processes
    limit.rlim_cur = limit.rlim_max = 64;
    if (setrlimit(RLIMIT_NPROC, &limit) < 0) {
        perror("setrlimit(RLIMIT_NPROC)");
        return -1;
    }
    
    // Limit number of open files
    limit.rlim_cur = limit.rlim_max = 256;
    if (setrlimit(RLIMIT_NOFILE, &limit) < 0) {
        perror("setrlimit(RLIMIT_NOFILE)");
        return -1;
    }
    
    return 0;
}

int create_secure_sandbox(sandbox_config_t *config) {
    pid_t pid;
    int status;
    
    if (!config || !config->program) {
        fprintf(stderr, "Invalid sandbox configuration\n");
        return -1;
    }
    
    pid = fork();
    if (pid < 0) {
        perror("fork");
        return -1;
    }
    
    if (pid == 0) {
        // Child process - setup sandbox
        
        // Setup namespaces
        if (setup_namespaces() < 0) {
            fprintf(stderr, "Failed to setup namespaces\n");
            _exit(EXIT_FAILURE);
        }
        
        // Change root directory if specified
        if (config->chroot_dir) {
            if (chroot(config->chroot_dir) < 0) {
                perror("chroot");
                _exit(EXIT_FAILURE);
            }
            if (chdir("/") < 0) {
                perror("chdir");
                _exit(EXIT_FAILURE);
            }
        }
        
        // Set resource limits
        if (set_resource_limits() < 0) {
            fprintf(stderr, "Failed to set resource limits\n");
            _exit(EXIT_FAILURE);
        }
        
        // Drop capabilities
        if (drop_capabilities_manual() < 0) {
            fprintf(stderr, "Failed to drop capabilities\n");
            _exit(EXIT_FAILURE);
        }
        
        // Change user/group
        if (config->gid > 0 && setgid(config->gid) < 0) {
            perror("setgid");
            _exit(EXIT_FAILURE);
        }
        if (config->uid > 0 && setuid(config->uid) < 0) {
            perror("setuid");
            _exit(EXIT_FAILURE);
        }
        
        // Setup seccomp filter (basic protection)
        if (install_seccomp_filter(config->allowed_syscalls, config->num_syscalls) < 0) {
            fprintf(stderr, "Failed to setup seccomp filter\n");
            _exit(EXIT_FAILURE);
        }
        
        // Execute program
        execve(config->program, config->argv, config->envp);
        perror("execve");
        _exit(EXIT_FAILURE);
    }
    
    // Parent process - wait for child
    if (waitpid(pid, &status, 0) < 0) {
        perror("waitpid");
        return -1;
    }
    
    return WEXITSTATUS(status);
}

// Test function
int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <program> [args...]\n", argv[0]);
        return 1;
    }
    
    sandbox_config_t config = {
        .program = argv[1],
        .argv = &argv[1],
        .envp = environ,
        .uid = 1000,  // Non-root user
        .gid = 1000,  // Non-root group
        .chroot_dir = NULL,
        .allowed_syscalls = NULL,
        .num_syscalls = 0
    };
    
    printf("Creating secure sandbox for: %s\n", config.program);
    int result = create_secure_sandbox(&config);
    printf("Sandbox exited with code: %d\n", result);
    
    return result;
}
