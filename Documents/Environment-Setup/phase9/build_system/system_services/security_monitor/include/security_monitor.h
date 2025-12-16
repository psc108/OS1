#ifndef SECURITY_MONITOR_H
#define SECURITY_MONITOR_H

#include <sys/types.h>
#include <time.h>

#define MAX_EVENTS 10000
#define MAX_RULES 1000

enum security_event_type {
    EVENT_PROCESS_START = 1,
    EVENT_PROCESS_EXIT,
    EVENT_FILE_ACCESS,
    EVENT_NETWORK_CONNECTION,
    EVENT_PRIVILEGE_ESCALATION,
    EVENT_POLICY_VIOLATION,
    EVENT_ANOMALY_DETECTED
};

struct security_event {
    enum security_event_type type;
    time_t timestamp;
    pid_t pid;
    uid_t uid;
    gid_t gid;
    char process_name[256];
    char details[512];
    int severity;
};

struct security_rule {
    int rule_id;
    enum security_event_type event_type;
    char pattern[256];
    int action; // 0=log, 1=alert, 2=block
    int enabled;
};

int init_security_monitor(void);
int add_security_event(struct security_event *event);
int load_security_rules(const char *rules_file);
int process_security_events(void);
int check_security_violations(void);

#endif /* SECURITY_MONITOR_H */
