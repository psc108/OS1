#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>
#include <time.h>
#include "../include/service_manager.h"

static struct service services[MAX_SERVICES];
static int service_count = 0;

static struct service* find_service(const char *name) {
    for (int i = 0; i < service_count; i++) {
        if (strcmp(services[i].config.name, name) == 0) {
            return &services[i];
        }
    }
    return NULL;
}

int validate_service_security(struct service *svc) {
    if (!svc) {
        return -EINVAL;
    }
    
    // Validate user exists
    struct passwd *pwd = getpwnam(svc->config.user);
    if (!pwd) {
        return -ENOENT;
    }
    svc->config.uid = pwd->pw_uid;
    
    // Validate group exists
    struct group *grp = getgrnam(svc->config.group);
    if (!grp) {
        return -ENOENT;
    }
    svc->config.gid = grp->gr_gid;
    
    // Security level validation
    if (svc->config.security_level < 1 || svc->config.security_level > 5) {
        return -EINVAL;
    }
    
    return 0;
}

int start_service(const char *service_name) {
    struct service *svc = find_service(service_name);
    if (!svc) {
        return -ENOENT;
    }
    
    if (svc->state == SERVICE_RUNNING) {
        return 0; // Already running
    }
    
    int ret = validate_service_security(svc);
    if (ret < 0) {
        return ret;
    }
    
    svc->state = SERVICE_STARTING;
    
    pid_t pid = fork();
    if (pid < 0) {
        svc->state = SERVICE_FAILED;
        return -errno;
    }
    
    if (pid == 0) {
        // Drop privileges
        if (setgid(svc->config.gid) < 0 || setuid(svc->config.uid) < 0) {
            _exit(EXIT_FAILURE);
        }
        
        // Execute service
        execl("/bin/sh", "sh", "-c", svc->config.command, NULL);
        _exit(EXIT_FAILURE);
    }
    
    svc->pid = pid;
    svc->state = SERVICE_RUNNING;
    svc->start_time = time(NULL);
    
    printf("Service %s started with PID %d\n", service_name, pid);
    return 0;
}

int stop_service(const char *service_name) {
    struct service *svc = find_service(service_name);
    if (!svc) {
        return -ENOENT;
    }
    
    if (svc->state != SERVICE_RUNNING) {
        return 0; // Not running
    }
    
    svc->state = SERVICE_STOPPING;
    
    if (kill(svc->pid, SIGTERM) < 0) {
        return -errno;
    }
    
    // Wait for graceful shutdown
    sleep(5);
    
    int status;
    if (waitpid(svc->pid, &status, WNOHANG) == 0) {
        // Force kill if still running
        kill(svc->pid, SIGKILL);
        waitpid(svc->pid, &status, 0);
    }
    
    svc->state = SERVICE_STOPPED;
    svc->pid = 0;
    
    printf("Service %s stopped\n", service_name);
    return 0;
}

int restart_service(const char *service_name) {
    int ret = stop_service(service_name);
    if (ret < 0) {
        return ret;
    }
    
    struct service *svc = find_service(service_name);
    if (svc) {
        svc->restart_count++;
    }
    
    return start_service(service_name);
}

int load_service_config(const char *config_file) {
    FILE *file = fopen(config_file, "r");
    if (!file) {
        return -errno;
    }
    
    char line[512];
    while (fgets(line, sizeof(line), file) && service_count < MAX_SERVICES) {
        struct service *svc = &services[service_count];
        
        if (sscanf(line, "%63s %511s %31s %31s %d %lu %lu",
                   svc->config.name, svc->config.command,
                   svc->config.user, svc->config.group,
                   &svc->config.security_level,
                   &svc->config.memory_limit,
                   &svc->config.cpu_limit) == 7) {
            
            svc->config.auto_restart = 1;
            svc->state = SERVICE_STOPPED;
            svc->pid = 0;
            svc->restart_count = 0;
            service_count++;
        }
    }
    
    fclose(file);
    return service_count;
}

/* Test main function for compilation validation */
int main(int argc, char *argv[]) {
    printf("SecureOS Service Manager - Compilation Test Passed\n");
    return 0;
}
