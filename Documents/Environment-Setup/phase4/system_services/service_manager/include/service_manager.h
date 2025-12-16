#ifndef SERVICE_MANAGER_H
#define SERVICE_MANAGER_H

#include <sys/types.h>

#define MAX_SERVICES 256
#define MAX_SERVICE_NAME 64
#define MAX_COMMAND_LEN 512

enum service_state {
    SERVICE_STOPPED = 0,
    SERVICE_STARTING,
    SERVICE_RUNNING,
    SERVICE_STOPPING,
    SERVICE_FAILED
};

struct service_config {
    char name[MAX_SERVICE_NAME];
    char command[MAX_COMMAND_LEN];
    char user[32];
    char group[32];
    uid_t uid;
    gid_t gid;
    int auto_restart;
    int security_level;
    unsigned long memory_limit;
    unsigned long cpu_limit;
};

struct service {
    struct service_config config;
    pid_t pid;
    enum service_state state;
    time_t start_time;
    int restart_count;
};

int start_service(const char *service_name);
int stop_service(const char *service_name);
int restart_service(const char *service_name);
int load_service_config(const char *config_file);
int validate_service_security(struct service *svc);

#endif /* SERVICE_MANAGER_H */
