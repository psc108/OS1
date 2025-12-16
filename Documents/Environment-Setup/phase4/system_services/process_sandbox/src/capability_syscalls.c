#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/capability.h>
#include <errno.h>
#include <string.h>

/* Complete capability management using direct syscalls */

#define _LINUX_CAPABILITY_VERSION_3 0x20080522
#define _LINUX_CAPABILITY_U32S_3 2

/* Direct syscall wrappers for complete capability control */
static int capget(cap_user_header_t header, cap_user_data_t data) {
    return syscall(SYS_capget, header, data);
}

static int capset(cap_user_header_t header, const cap_user_data_t data) {
    return syscall(SYS_capset, header, data);
}

/* Production-grade capability management functions */
int secureos_cap_get_proc(cap_user_data_t caps) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0
    };
    
    return capget(&header, caps);
}

int secureos_cap_set_proc(const cap_user_data_t caps) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0
    };
    
    return capset(&header, caps);
}

int secureos_cap_clear_all(void) {
    struct __user_cap_data_struct caps[_LINUX_CAPABILITY_U32S_3];
    
    /* Clear all capability sets */
    memset(caps, 0, sizeof(caps));
    
    return secureos_cap_set_proc(caps);
}

int secureos_cap_drop_all_except(unsigned long required_caps) {
    struct __user_cap_data_struct caps[_LINUX_CAPABILITY_U32S_3];
    
    /* Get current capabilities */
    if (secureos_cap_get_proc(caps) < 0) {
        return -errno;
    }
    
    /* Clear all capabilities first */
    memset(caps, 0, sizeof(caps));
    
    /* Set only required capabilities */
    if (required_caps != 0) {
        caps[0].effective = required_caps & 0xFFFFFFFF;
        caps[0].permitted = required_caps & 0xFFFFFFFF;
        caps[0].inheritable = 0; /* No inheritable capabilities */
        
        if (required_caps > 0xFFFFFFFF) {
            caps[1].effective = (required_caps >> 32) & 0xFFFFFFFF;
            caps[1].permitted = (required_caps >> 32) & 0xFFFFFFFF;
            caps[1].inheritable = 0;
        }
    }
    
    return secureos_cap_set_proc(caps);
}

int secureos_cap_has_capability(int cap) {
    struct __user_cap_data_struct caps[_LINUX_CAPABILITY_U32S_3];
    
    if (secureos_cap_get_proc(caps) < 0) {
        return -errno;
    }
    
    if (cap < 32) {
        return (caps[0].effective & (1U << cap)) != 0;
    } else if (cap < 64) {
        return (caps[1].effective & (1U << (cap - 32))) != 0;
    }
    
    return 0;
}

/* Audit logging for capability operations */
void audit_capability_operation(const char *operation, int result) {
    if (result == 0) {
        printf("AUDIT: Capability %s succeeded\n", operation);
    } else {
        printf("AUDIT: Capability %s failed: %s\n", operation, strerror(-result));
    }
}

/* Capability management functions ready for use */
