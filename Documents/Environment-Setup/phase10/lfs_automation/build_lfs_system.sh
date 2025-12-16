#!/bin/bash
# LFS System Build with SecureOS Security Integration
# Integrates Phase 3-6 security components into LFS build
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source LFS environment from Phase 9
if [[ -f ~/.lfs_env ]]; then
    source ~/.lfs_env
else
    echo "ERROR: LFS environment not configured. Run Phase 9 setup first."
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Parse command line arguments
SECURITY_ENHANCED=false
INTEGRATE_PHASES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --security-enhanced)
            SECURITY_ENHANCED=true
            shift
            ;;
        --integrate-phases=*)
            INTEGRATE_PHASES="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log "Building LFS system with SecureOS integration..."
log "Security enhanced: $SECURITY_ENHANCED"
log "Integrating phases: $INTEGRATE_PHASES"

# Setup chroot environment
setup_chroot() {
    log "Setting up chroot environment..."
    
    # Create essential directories
    mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}
    
    for i in bin lib sbin; do
        ln -sv usr/$i $LFS/$i
    done
    
    case $(uname -m) in
        x86_64) mkdir -pv $LFS/lib64 ;;
    esac
    
    # Create tools directory
    mkdir -pv $LFS/tools
    
    log "✅ Chroot environment prepared"
}

# Enter chroot and build system
build_in_chroot() {
    log "Entering chroot to build LFS system..."
    
    # Mount virtual filesystems
    mount -v --bind /dev $LFS/dev
    mount -v --bind /dev/pts $LFS/dev/pts
    mount -vt proc proc $LFS/proc
    mount -vt sysfs sysfs $LFS/sys
    mount -vt tmpfs tmpfs $LFS/run
    
    if [ -h $LFS/dev/shm ]; then
        mkdir -pv $LFS/$(readlink $LFS/dev/shm)
    else
        mount -t tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
    fi
    
    # Create chroot script
    cat > $LFS/build_system.sh << 'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Build essential system packages
build_essential_packages() {
    log "Building essential LFS packages..."
    
    cd /sources
    
    # Build gettext (needed for other packages)
    tar -xf gettext-0.22.tar.xz
    cd gettext-0.22
    ./configure --disable-shared
    make -j$(nproc)
    cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
    cd /sources
    rm -rf gettext-0.22
    
    # Build bison
    tar -xf bison-3.8.2.tar.xz
    cd bison-3.8.2
    ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
    make -j$(nproc)
    make install
    cd /sources
    rm -rf bison-3.8.2
    
    # Build perl
    tar -xf perl-5.38.0.tar.xz
    cd perl-5.38.0
    sh Configure -des -Dprefix=/usr -Dvendorprefix=/usr -Dprivlib=/usr/lib/perl5/5.38/core_perl -Darchlib=/usr/lib/perl5/5.38/core_perl -Dsitelib=/usr/lib/perl5/5.38/site_perl -Dsitearch=/usr/lib/perl5/5.38/site_perl -Dvendorlib=/usr/lib/perl5/5.38/vendor_perl -Dvendorarch=/usr/lib/perl5/5.38/vendor_perl
    make -j$(nproc)
    make install
    cd /sources
    rm -rf perl-5.38.0
    
    log "✅ Essential packages built"
}

# Build core system
build_core_system() {
    log "Building core LFS system..."
    
    # Build coreutils
    tar -xf coreutils-9.4.tar.xz
    cd coreutils-9.4
    patch -Np1 -i ../coreutils-9.4-i18n-1.patch || true
    ./configure --prefix=/usr --enable-no-install-program=kill,uptime
    make -j$(nproc)
    make install
    mv -v /usr/bin/chroot /usr/sbin
    mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
    cd /sources
    rm -rf coreutils-9.4
    
    # Build bash
    tar -xf bash-5.2.15.tar.gz
    cd bash-5.2.15
    ./configure --prefix=/usr --without-bash-malloc --with-installed-readline --docdir=/usr/share/doc/bash-5.2.15
    make -j$(nproc)
    make install
    cd /sources
    rm -rf bash-5.2.15
    
    log "✅ Core system built"
}

# Integrate SecureOS security components
integrate_security_components() {
    log "Integrating SecureOS security components..."
    
    # Copy Phase 3 security components
    if [[ -d /workspace/phase3/core_systems ]]; then
        cp -r /workspace/phase3/core_systems /opt/secureos/
        
        # Compile secure boot validator
        cd /opt/secureos/core_systems
        gcc -o secure_boot_validator secure_boot.c -lssl -lcrypto || {
            log "WARNING: Could not compile secure boot validator"
        }
    fi
    
    # Copy Phase 4 system services
    if [[ -d /workspace/phase4/system_services ]]; then
        cp -r /workspace/phase4/system_services /opt/secureos/
        
        # Compile secure sandbox
        cd /opt/secureos/system_services
        gcc -o secure_sandbox secure_sandbox_fixed.c capability_syscalls.c || {
            log "WARNING: Could not compile secure sandbox"
        }
    fi
    
    log "✅ Security components integrated"
}

# Main chroot execution
main() {
    log "Starting LFS system build in chroot"
    
    # Setup environment
    export PATH=/usr/bin:/usr/sbin:/bin:/sbin
    
    # Create secureos directory
    mkdir -p /opt/secureos
    
    # Build system packages
    build_essential_packages
    build_core_system
    
    # Integrate security if requested
    if [[ "$1" == "true" ]]; then
        integrate_security_components
    fi
    
    log "✅ LFS system build completed in chroot"
}

main "$SECURITY_ENHANCED"
CHROOT_EOF
    
    chmod +x $LFS/build_system.sh
    
    # Copy workspace to chroot if security integration requested
    if [[ "$SECURITY_ENHANCED" == "true" ]]; then
        mkdir -p $LFS/workspace
        for phase in ${INTEGRATE_PHASES//,/ }; do
            if [[ -d "$BASE_DIR/phase$phase" ]]; then
                cp -r "$BASE_DIR/phase$phase" $LFS/workspace/
            fi
        done
    fi
    
    # Execute build in chroot
    chroot "$LFS" /usr/bin/env -i \
        HOME=/root \
        TERM="$TERM" \
        PS1='(lfs chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /build_system.sh "$SECURITY_ENHANCED"
    
    # Cleanup
    rm -f $LFS/build_system.sh
    
    # Unmount virtual filesystems
    umount $LFS/dev/pts
    umount $LFS/dev
    umount $LFS/run
    umount $LFS/proc
    umount $LFS/sys
    
    log "✅ LFS system build completed"
}

# Configure system
configure_system() {
    log "Configuring LFS system..."
    
    # Create fstab
    cat > $LFS/etc/fstab << "EOF"
# Begin /etc/fstab
# file system  mount-point  type     options             dump  fsck order
/dev/sda2      /            ext4     defaults            1     1
/dev/sda1      /boot/efi    vfat     defaults            0     1
proc           /proc        proc     nosuid,noexec,nodev 0     0
sysfs          /sys         sysfs    nosuid,noexec,nodev 0     0
devpts         /dev/pts     devpts   gid=5,mode=620      0     0
tmpfs          /run         tmpfs    defaults            0     0
devtmpfs       /dev         devtmpfs mode=0755,nosuid    0     0
tmpfs          /dev/shm     tmpfs    nosuid,nodev        0     0
# End /etc/fstab
EOF
    
    # Configure network
    cat > $LFS/etc/systemd/network/10-eth-dhcp.network << "EOF"
[Match]
Name=eth*

[Network]
DHCP=yes
EOF
    
    # Set hostname
    echo "secureos-lfs" > $LFS/etc/hostname
    
    # Configure locale
    cat > $LFS/etc/locale.conf << "EOF"
LANG=en_US.UTF-8
EOF
    
    log "✅ System configuration completed"
}

# Main execution
main() {
    log "Starting LFS system build with SecureOS integration"
    
    # Validate LFS environment
    [[ -z "$LFS" ]] && { echo "ERROR: LFS variable not set"; exit 1; }
    [[ ! -d "$LFS/sources" ]] && { echo "ERROR: LFS sources not found"; exit 1; }
    
    # Setup and build
    setup_chroot
    build_in_chroot
    configure_system
    
    log "✅ LFS system with SecureOS integration completed successfully"
    log "System root: $LFS"
}

# Execute main function
main "$@"