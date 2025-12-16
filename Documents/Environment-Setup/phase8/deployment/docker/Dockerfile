# SecureOS Docker Image
# Multi-stage build for minimal attack surface

# Build stage
FROM rockylinux:9-minimal AS builder

ARG BUILD_DATE
ARG VERSION

LABEL maintainer="SecureOS Team"
LABEL version="${VERSION}"
LABEL build-date="${BUILD_DATE}"
LABEL description="SecureOS - Security-First Operating System Container"

# Install build dependencies
RUN microdnf update -y && \
    microdnf install -y gcc make cmake openssl-devel && \
    microdnf clean all

# Copy SecureOS components
COPY --from=build-context ../../phase3/core_systems/ /build/core_systems/
COPY --from=build-context ../../phase4/system_services/ /build/system_services/
COPY --from=build-context ../../phase5/user_space/ /build/user_space/

# Build SecureOS components
WORKDIR /build
RUN make -C core_systems/secure_boot/verification && \
    make -C core_systems/filesystem/encryption && \
    make -C core_systems/process_management/sandbox && \
    make -C system_services/process_sandbox/src && \
    make -C system_services/security_monitor/src

# Production stage
FROM scratch AS production

# Copy only essential binaries
COPY --from=builder /build/core_systems/secure_boot/verification/verify_signature /usr/local/bin/
COPY --from=builder /build/core_systems/filesystem/encryption/aes_gcm_encrypt /usr/local/bin/
COPY --from=builder /build/core_systems/process_management/sandbox/secure_sandbox /usr/local/bin/
COPY --from=builder /build/system_services/process_sandbox/src/secure_sandbox /usr/local/bin/
COPY --from=builder /build/system_services/security_monitor/src/security_monitor /usr/local/bin/

# Copy minimal runtime libraries
COPY --from=builder /lib64/ld-linux-x86-64.so.2 /lib64/
COPY --from=builder /lib64/libc.so.6 /lib64/
COPY --from=builder /lib64/libssl.so.3 /lib64/
COPY --from=builder /lib64/libcrypto.so.3 /lib64/

# Create non-root user
RUN echo "secureos:x:1000:1000:SecureOS User:/home/secureos:/bin/sh" > /etc/passwd && \
    echo "secureos:x:1000:" > /etc/group && \
    mkdir -p /home/secureos && \
    chown 1000:1000 /home/secureos

# Security hardening
RUN chmod 755 /usr/local/bin/* && \
    chmod 644 /lib64/* && \
    rm -rf /tmp/* /var/tmp/*

# Switch to non-root user
USER 1000:1000
WORKDIR /home/secureos

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/security_monitor --health-check || exit 1

# Default command
CMD ["/usr/local/bin/security_monitor"]

# Security labels
LABEL security.scan="required"
LABEL security.baseline="CIS-Level2"
LABEL security.non-root="true"