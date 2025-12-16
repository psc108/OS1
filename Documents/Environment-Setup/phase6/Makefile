# SecureOS Phase 6: GUI Security Components Makefile
CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2
LDFLAGS = -Wl,-z,relro,-z,now -Wl,-z,noexecstack
INCLUDES = -I./wayland_compositor/include -I./input_security/include -I./client_isolation/include

# Security libraries (using kernel syscalls directly)
SECURITY_LIBS =

ALL_CFLAGS = $(CFLAGS) $(INCLUDES)
ALL_LIBS = $(SECURITY_LIBS)

# Source files
COMPOSITOR_SRCS = wayland_compositor/src/secure_compositor.c
INPUT_SRCS = input_security/src/input_security.c
ISOLATION_SRCS = client_isolation/src/client_isolation.c

# Object files
COMPOSITOR_OBJS = $(COMPOSITOR_SRCS:.c=.o)
INPUT_OBJS = $(INPUT_SRCS:.c=.o)
ISOLATION_OBJS = $(ISOLATION_SRCS:.c=.o)

# Targets
all: secure-compositor input-security client-isolation

secure-compositor: $(COMPOSITOR_OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ $(ALL_LIBS)

input-security: $(INPUT_OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ $(ALL_LIBS)

client-isolation: $(ISOLATION_OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ $(ALL_LIBS)

%.o: %.c
	$(CC) $(ALL_CFLAGS) -c $< -o $@

clean:
	rm -f $(COMPOSITOR_OBJS) $(INPUT_OBJS) $(ISOLATION_OBJS)
	rm -f secure-compositor input-security client-isolation

install: all
	install -D -m 755 secure-compositor $(DESTDIR)/usr/bin/secure-compositor
	install -D -m 755 input-security $(DESTDIR)/usr/bin/input-security
	install -D -m 755 client-isolation $(DESTDIR)/usr/bin/client-isolation

test: all
	@echo "Running Phase 6 GUI security tests..."
	@./run_tests.sh

.PHONY: all clean install test
