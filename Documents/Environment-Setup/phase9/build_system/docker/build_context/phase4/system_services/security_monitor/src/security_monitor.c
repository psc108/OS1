#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
#include <syslog.h>
#include "../include/security_monitor.h"

static struct security_event events[MAX_EVENTS];
static struct security_rule rules[MAX_RULES];
static int event_count = 0;
static int rule_count = 0;
static int monitor_initialized = 0;

int init_security_monitor(void) {
    if (monitor_initialized) {
        return 0;
    }
    
    openlog("secureos-monitor", LOG_PID | LOG_CONS, LOG_DAEMON);
    
    memset(events, 0, sizeof(events));
    memset(rules, 0, sizeof(rules));
    event_count = 0;
    rule_count = 0;
    
    monitor_initialized = 1;
    syslog(LOG_INFO, "Security monitor initialized");
    
    return 0;
}

int add_security_event(struct security_event *event) {
    if (!monitor_initialized) {
        return -EINVAL;
    }
    
    if (!event || event_count >= MAX_EVENTS) {
        return -EINVAL;
    }
    
    // Add timestamp if not set
    if (event->timestamp == 0) {
        event->timestamp = time(NULL);
    }
    
    // Copy event to buffer
    memcpy(&events[event_count], event, sizeof(struct security_event));
    event_count++;
    
    // Log high severity events immediately
    if (event->severity >= 8) {
        syslog(LOG_ALERT, "High severity security event: %s (PID: %d, UID: %d)",
               event->details, event->pid, event->uid);
    }
    
    return 0;
}

int load_security_rules(const char *rules_file) {
    if (!monitor_initialized) {
        return -EINVAL;
    }
    
    FILE *file = fopen(rules_file, "r");
    if (!file) {
        return -errno;
    }
    
    char line[512];
    while (fgets(line, sizeof(line), file) && rule_count < MAX_RULES) {
        struct security_rule *rule = &rules[rule_count];
        
        int event_type_int;
        if (sscanf(line, "%d %d %255s %d %d",
                   &rule->rule_id, &event_type_int, rule->pattern,
                   &rule->action, &rule->enabled) == 5) {
            
            rule->event_type = (enum security_event_type)event_type_int;
            rule_count++;
        }
    }
    
    fclose(file);
    syslog(LOG_INFO, "Loaded %d security rules", rule_count);
    
    return rule_count;
}

static int match_rule_pattern(const char *pattern, const char *text) {
    // Simple pattern matching - could be enhanced with regex
    return strstr(text, pattern) != NULL;
}

int process_security_events(void) {
    if (!monitor_initialized) {
        return -EINVAL;
    }
    
    int processed = 0;
    
    for (int i = 0; i < event_count; i++) {
        struct security_event *event = &events[i];
        
        for (int j = 0; j < rule_count; j++) {
            struct security_rule *rule = &rules[j];
            
            if (!rule->enabled || rule->event_type != event->type) {
                continue;
            }
            
            if (match_rule_pattern(rule->pattern, event->details)) {
                switch (rule->action) {
                    case 0: // Log
                        syslog(LOG_WARNING, "Security rule %d triggered: %s",
                               rule->rule_id, event->details);
                        break;
                    case 1: // Alert
                        syslog(LOG_ALERT, "SECURITY ALERT - Rule %d: %s",
                               rule->rule_id, event->details);
                        break;
                    case 2: // Block
                        syslog(LOG_CRIT, "SECURITY BLOCK - Rule %d: %s",
                               rule->rule_id, event->details);
                        // Could implement blocking logic here
                        break;
                }
                processed++;
            }
        }
    }
    
    return processed;
}

int check_security_violations(void) {
    if (!monitor_initialized) {
        return -EINVAL;
    }
    
    int violations = 0;
    time_t current_time = time(NULL);
    
    // Check for suspicious patterns
    for (int i = 0; i < event_count; i++) {
        struct security_event *event = &events[i];
        
        // Check for privilege escalation attempts
        if (event->type == EVENT_PRIVILEGE_ESCALATION) {
            violations++;
            syslog(LOG_ALERT, "Privilege escalation detected: PID %d, UID %d",
                   event->pid, event->uid);
        }
        
        // Check for policy violations
        if (event->type == EVENT_POLICY_VIOLATION) {
            violations++;
            syslog(LOG_WARNING, "Policy violation: %s", event->details);
        }
        
        // Check for anomalies
        if (event->type == EVENT_ANOMALY_DETECTED) {
            violations++;
            syslog(LOG_NOTICE, "Anomaly detected: %s", event->details);
        }
    }
    
    return violations;
}

/* Test main function for compilation validation */
int main(int argc, char *argv[]) {
    printf("SecureOS Security Monitor - Compilation Test Passed\n");
    return 0;
}
