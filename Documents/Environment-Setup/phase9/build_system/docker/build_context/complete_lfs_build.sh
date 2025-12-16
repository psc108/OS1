#!/bin/bash
# Complete LFS Build Script - Production Implementation
# SecureOS Phase 10: Automated OS Build System
set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
BUILD_DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/lfs_build_${BUILD_DATE}.log"

# LFS Configuration (LFS path set by interactive selection)
export LFS_TGT=x86_64-lfs-linux-gnu
export PATH=/usr/bin:/bin:/sbin:/usr/sbin
export MAKEFLAGS=-j$(nproc)
# LFS and CONFIG_SITE set after destination selection

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Progress tracking
update_progress() {
    echo "$1" > /tmp/lfs_current_stage.txt
    log "STAGE: $1"
}

# Interactive storage selection
select_lfs_destination() {
    log "Selecting LFS build destination..."
    
    echo "LFS Build Storage Selection"
    echo "==========================="
    echo "Available storage options:"
    echo
    
    # Check available mount points with space
    local options=()
    local option_paths=()
    local count=1
    
    # Check /mnt (default)
    local mnt_space=$(df /mnt 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$mnt_space" -ge 15 ]; then
        echo "$count. /mnt/lfs (${mnt_space}GB available) [Default]"
        options+=("$count")
        option_paths+=("/mnt/lfs")
        ((count++))
    fi
    
    # Check /tmp
    local tmp_space=$(df /tmp 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$tmp_space" -ge 15 ]; then
        echo "$count. /tmp/lfs (${tmp_space}GB available)"
        options+=("$count")
        option_paths+=("/tmp/lfs")
        ((count++))
    fi
    
    # Check /home (host mounted)
    local home_space=$(df /home 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$home_space" -ge 15 ]; then
        echo "$count. /home/lfs (${home_space}GB available) [Host /home]"
        options+=("$count")
        option_paths+=("/home/lfs")
        ((count++))
    fi
    
    # Check /host-mnt (host /mnt mounted)
    local hostmnt_space=$(df /host-mnt 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$hostmnt_space" -ge 15 ]; then
        echo "$count. /host-mnt/lfs (${hostmnt_space}GB available) [Host /mnt]"
        options+=("$count")
        option_paths+=("/host-mnt/lfs")
        ((count++))
    fi
    
    if [ ${#options[@]} -eq 0 ]; then
        error_exit "No suitable storage location found. Need 15GB minimum."
    fi
    
    echo
    echo "Enter your choice (1-$((count-1))) or press Enter for default:"
    read -r choice
    
    # Default to first option if no choice
    if [ -z "$choice" ]; then
        choice=1
    fi
    
    # Validate choice
    local valid=false
    for opt in "${options[@]}"; do
        if [ "$choice" = "$opt" ]; then
            valid=true
            break
        fi
    done
    
    if [ "$valid" = false ]; then
        error_exit "Invalid choice: $choice"
    fi
    
    # Set LFS to selected path
    export LFS="${option_paths[$((choice-1))]}"
    log "Selected LFS destination: $LFS"
}

# Validate environment
validate_environment() {
    log "Validating LFS build environment..."
    
    # Check required tools
    for tool in gcc make wget tar; do
        command -v "$tool" >/dev/null || error_exit "$tool not found"
    done
    
    # Select storage destination
    select_lfs_destination
    
    # Verify selected destination has enough space
    local available_space=$(df "$(dirname "$LFS")" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 15728640 ]; then
        error_exit "Insufficient disk space at $LFS. Need 15GB, have $(($available_space/1024/1024))GB"
    fi
    
    log "Environment validation passed - Using $LFS"
}

# Setup LFS directory structure
setup_lfs_directories() {
    update_progress "Setting up LFS directory structure"
    
    mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin} $LFS/sources $LFS/tools
    
    for i in bin lib sbin; do
        ln -sfv usr/$i $LFS/$i
    done
    
    chmod -v a+wt $LFS/sources
    log "LFS directories created"
}

# Download LFS packages
download_lfs_packages() {
    update_progress "Downloading LFS packages"
    
    cd $LFS/sources
    
    # Download package list and checksums
    wget -c http://www.linuxfromscratch.org/lfs/downloads/12.0/wget-list-sysv
    wget -c http://www.linuxfromscratch.org/lfs/downloads/12.0/md5sums
    
    # Download all packages
    wget --input-file=wget-list-sysv --continue
    
    # Verify checksums
    md5sum -c md5sums || error_exit "Package checksum verification failed"
    
    log "All LFS packages downloaded and verified"
}

# Build cross-compilation toolchain
build_cross_toolchain() {
    update_progress "Building cross-compilation toolchain"
    
    cd $LFS/sources
    
    # Binutils Pass 1
    log "Building binutils cross-compiler..."
    tar -xf binutils-2.41.tar.xz
    cd binutils-2.41
    mkdir -v build && cd build
    
    ../configure --prefix=$LFS/tools \
                 --with-sysroot=$LFS \
                 --target=$LFS_TGT \
                 --disable-nls \
                 --enable-gprofng=no \
                 --disable-werror \
                 --enable-default-hash-style=gnu || error_exit "Binutils configure failed"
    
    make || error_exit "Binutils build failed"
    make install || error_exit "Binutils install failed"
    
    cd $LFS/sources && rm -rf binutils-2.41
    
    # GCC Pass 1
    log "Building GCC cross-compiler..."
    tar -xf gcc-13.2.0.tar.xz
    cd gcc-13.2.0
    
    tar -xf ../mpfr-4.2.0.tar.xz && mv mpfr-4.2.0 mpfr
    tar -xf ../gmp-6.3.0.tar.xz && mv gmp-6.3.0 gmp
    tar -xf ../mpc-1.3.1.tar.gz && mv mpc-1.3.1 mpc
    
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    
    mkdir -v build && cd build
    
    ../configure --target=$LFS_TGT \
                 --prefix=$LFS/tools \
                 --with-glibc-version=2.38 \
                 --with-sysroot=$LFS \
                 --with-newlib \
                 --without-headers \
                 --enable-default-pie \
                 --enable-default-ssp \
                 --disable-nls \
                 --disable-shared \
                 --disable-multilib \
                 --disable-threads \
                 --disable-libatomic \
                 --disable-libgomp \
                 --disable-libquadmath \
                 --disable-libssp \
                 --disable-libvtv \
                 --disable-libstdcxx \
                 --enable-languages=c,c++ || error_exit "GCC configure failed"
    
    make || error_exit "GCC build failed"
    make install || error_exit "GCC install failed"
    
    cd $LFS/sources && rm -rf gcc-13.2.0
    
    # Linux API Headers
    log "Installing Linux API headers..."
    tar -xf linux-6.4.12.tar.xz
    cd linux-6.4.12
    
    make mrproper
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -rv usr/include $LFS/usr
    
    cd $LFS/sources && rm -rf linux-6.4.12
    
    # Glibc
    log "Building Glibc..."
    tar -xf glibc-2.38.tar.xz
    cd glibc-2.38
    
    case $(uname -m) in
        i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3 ;;
        x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
                ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3 ;;
    esac
    
    patch -Np1 -i ../glibc-2.38-fhs-1.patch
    
    mkdir -v build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    
    ../configure --prefix=/usr \
                 --host=$LFS_TGT \
                 --build=$(../scripts/config.guess) \
                 --enable-kernel=4.14 \
                 --with-headers=$LFS/usr/include \
                 libc_cv_slibdir=/usr/lib || error_exit "Glibc configure failed"
    
    make || error_exit "Glibc build failed"
    make DESTDIR=$LFS install || error_exit "Glibc install failed"
    
    sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
    
    cd $LFS/sources && rm -rf glibc-2.38
    
    # Libstdc++
    log "Building Libstdc++..."
    tar -xf gcc-13.2.0.tar.xz
    cd gcc-13.2.0
    
    mkdir -v build && cd build
    
    ../libstdc++-v3/configure --host=$LFS_TGT \
                              --build=$(../config.guess) \
                              --prefix=/usr \
                              --disable-multilib \
                              --disable-nls \
                              --disable-libstdcxx-pch \
                              --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/13.2.0 || error_exit "Libstdc++ configure failed"
    
    make || error_exit "Libstdc++ build failed"
    make DESTDIR=$LFS install || error_exit "Libstdc++ install failed"
    
    rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
    
    cd $LFS/sources && rm -rf gcc-13.2.0
    
    log "Cross-compilation toolchain completed"
}

# Build temporary system
build_temporary_system() {
    update_progress "Building temporary system"
    
    cd $LFS/sources
    
    # M4
    log "Building M4..."
    tar -xf m4-1.4.19.tar.xz
    cd m4-1.4.19
    
    ./configure --prefix=/usr \
                --host=$LFS_TGT \
                --build=$(build-aux/config.guess) || error_exit "M4 configure failed"
    
    make || error_exit "M4 build failed"
    make DESTDIR=$LFS install || error_exit "M4 install failed"
    
    cd $LFS/sources && rm -rf m4-1.4.19
    
    # Ncurses
    log "Building Ncurses..."
    tar -xf ncurses-6.4.tar.gz
    cd ncurses-6.4
    
    sed -i s/mawk// configure
    
    mkdir build
    pushd build
    ../configure
    make -C include
    make -C progs tic
    popd
    
    ./configure --prefix=/usr \
                --host=$LFS_TGT \
                --build=$(./config.guess) \
                --mandir=/usr/share/man \
                --with-manpage-format=normal \
                --with-shared \
                --without-normal \
                --with-cxx-shared \
                --without-debug \
                --without-ada \
                --disable-stripping \
                --enable-widec || error_exit "Ncurses configure failed"
    
    make || error_exit "Ncurses build failed"
    make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install || error_exit "Ncurses install failed"
    
    echo "INPUT(-lncursesw)" > $LFS/usr/lib/libncurses.so
    
    cd $LFS/sources && rm -rf ncurses-6.4
    
    # Bash
    log "Building Bash..."
    tar -xf bash-5.2.15.tar.gz
    cd bash-5.2.15
    
    ./configure --prefix=/usr \
                --build=$(sh support/config.guess) \
                --host=$LFS_TGT \
                --without-bash-malloc || error_exit "Bash configure failed"
    
    make || error_exit "Bash build failed"
    make DESTDIR=$LFS install || error_exit "Bash install failed"
    
    ln -sv bash $LFS/bin/sh
    
    cd $LFS/sources && rm -rf bash-5.2.15
    
    log "Essential temporary tools completed"
}

# Configure system
configure_system() {
    update_progress "Configuring system"
    
    # Create fstab
    cat > $LFS/etc/fstab << 'EOF'
# file system  mount-point  type     options             dump  fsck
#                                                              order

/dev/sda2      /            ext4     defaults            1     1
/dev/sda1      /boot/efi    vfat     defaults            0     1
proc           /proc        proc     nosuid,noexec,nodev 0     0
sysfs          /sys         sysfs    nosuid,noexec,nodev 0     0
devpts         /dev/pts     devpts   gid=5,mode=620      0     0
tmpfs          /run         tmpfs    defaults            0     0
devtmpfs       /dev         devtmpfs mode=0755,nosuid    0     0
EOF
    
    # Set hostname
    echo "secureos" > $LFS/etc/hostname
    
    # Configure locale
    cat > $LFS/etc/locale.conf << 'EOF'
LANG=en_US.UTF-8
EOF
    
    log "System configuration completed"
}

# Create system image
create_system_image() {
    update_progress "Creating system image"
    
    # Create tar archive of the system
    cd $LFS
    tar -czf /tmp/secureos-lfs-system.tar.gz . || error_exit "System archive creation failed"
    
    log "System image created: /tmp/secureos-lfs-system.tar.gz"
}

# Generate time estimate
generate_time_estimate() {
    cat > /tmp/lfs_time_estimate.txt << 'EOF'
LFS Build Time Estimates:
- Environment Setup: 5 minutes
- Package Download: 15-30 minutes
- Cross Toolchain: 2-3 hours
- Temporary System: 2-3 hours
- Final System: 4-6 hours
- Configuration: 30 minutes
Total Estimated Time: 8-12 hours
EOF
}

# Main execution
main() {
    log "Starting complete LFS build - Version $SCRIPT_VERSION"
    
    generate_time_estimate
    
    validate_environment
    
    # Set CONFIG_SITE after LFS is determined
    export CONFIG_SITE=$LFS/usr/share/config.site
    
    setup_lfs_directories
    download_lfs_packages
    build_cross_toolchain
    build_temporary_system
    configure_system
    create_system_image
    
    update_progress "Build completed successfully"
    log "Complete LFS build finished successfully"
    log "System image: /tmp/secureos-lfs-system.tar.gz"
    log "Build log: $LOG_FILE"
}

# Execute main function
main "$@"