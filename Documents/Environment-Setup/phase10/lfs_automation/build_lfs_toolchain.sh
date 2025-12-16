#!/bin/bash
# LFS Cross-Compilation Toolchain Build (Chapter 5)
# Uses Phase 9 LFS environment with security validation
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

# Validate LFS environment
[[ -z "$LFS" ]] && { echo "ERROR: LFS variable not set"; exit 1; }
[[ -z "$LFS_TGT" ]] && { echo "ERROR: LFS_TGT variable not set"; exit 1; }

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Parse command line arguments
PARALLEL_JOBS=$(nproc)

while [[ $# -gt 0 ]]; do
    case $1 in
        --parallel=*)
            PARALLEL_JOBS="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log "Building LFS cross-compilation toolchain..."
log "LFS: $LFS"
log "LFS_TGT: $LFS_TGT"
log "Parallel jobs: $PARALLEL_JOBS"

# Ensure we're in the sources directory
cd "$LFS/sources" || { echo "ERROR: Cannot access $LFS/sources"; exit 1; }

# Build binutils cross-compiler (LFS 5.2)
build_binutils_cross() {
    log "Building binutils cross-compiler..."
    
    # Extract and enter binutils
    tar -xf binutils-2.41.tar.xz
    cd binutils-2.41
    
    # Create build directory
    mkdir -v build
    cd build
    
    # Configure binutils
    ../configure --prefix=$LFS/tools \
                 --with-sysroot=$LFS \
                 --target=$LFS_TGT \
                 --disable-nls \
                 --enable-gprofng=no \
                 --disable-werror || {
        log "ERROR: Binutils configure failed"
        exit 1
    }
    
    # Build binutils
    make -j"$PARALLEL_JOBS" || {
        log "ERROR: Binutils build failed"
        exit 1
    }
    
    # Install binutils
    make install || {
        log "ERROR: Binutils install failed"
        exit 1
    }
    
    # Cleanup
    cd "$LFS/sources"
    rm -rf binutils-2.41
    
    log "✅ Binutils cross-compiler built successfully"
}

# Build GCC cross-compiler (LFS 5.3)
build_gcc_cross() {
    log "Building GCC cross-compiler..."
    
    # Extract GCC
    tar -xf gcc-13.2.0.tar.xz
    cd gcc-13.2.0
    
    # Download GCC prerequisites
    ./contrib/download_prerequisites || {
        log "ERROR: Failed to download GCC prerequisites"
        exit 1
    }
    
    # Create build directory
    mkdir -v build
    cd build
    
    # Configure GCC
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
                 --enable-languages=c,c++ || {
        log "ERROR: GCC configure failed"
        exit 1
    }
    
    # Build GCC
    make -j"$PARALLEL_JOBS" || {
        log "ERROR: GCC build failed"
        exit 1
    }
    
    # Install GCC
    make install || {
        log "ERROR: GCC install failed"
        exit 1
    }
    
    # Create compatibility symlink
    cd ..
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/install-tools/include/limits.h
    
    # Cleanup
    cd "$LFS/sources"
    rm -rf gcc-13.2.0
    
    log "✅ GCC cross-compiler built successfully"
}

# Build Linux API Headers (LFS 5.4)
build_linux_headers() {
    log "Building Linux API headers..."
    
    # Extract Linux kernel
    tar -xf linux-6.6.8.tar.xz
    cd linux-6.6.8
    
    # Clean the kernel tree
    make mrproper
    
    # Install headers
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -rv usr/include $LFS/usr/ || {
        log "ERROR: Linux headers install failed"
        exit 1
    }
    
    # Cleanup
    cd "$LFS/sources"
    rm -rf linux-6.6.8
    
    log "✅ Linux API headers installed successfully"
}

# Build Glibc (LFS 5.5)
build_glibc() {
    log "Building Glibc..."
    
    # Extract Glibc
    tar -xf glibc-2.38.tar.xz
    cd glibc-2.38
    
    # Create case-insensitive symlink
    case $(uname -m) in
        i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
        ;;
        x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
                ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
        ;;
    esac
    
    # Apply patch if needed
    patch -Np1 -i ../glibc-2.38-fhs-1.patch 2>/dev/null || true
    
    # Create build directory
    mkdir -v build
    cd build
    
    # Ensure correct operation of the ELF loader
    echo "rootsbindir=/usr/sbin" > configparms
    
    # Configure Glibc
    ../configure --prefix=/usr \
                 --host=$LFS_TGT \
                 --build=$(../scripts/config.guess) \
                 --enable-kernel=4.14 \
                 --with-headers=$LFS/usr/include \
                 --disable-nscd \
                 libc_cv_slibdir=/usr/lib || {
        log "ERROR: Glibc configure failed"
        exit 1
    }
    
    # Build Glibc
    make -j"$PARALLEL_JOBS" || {
        log "ERROR: Glibc build failed"
        exit 1
    }
    
    # Install Glibc
    make DESTDIR=$LFS install || {
        log "ERROR: Glibc install failed"
        exit 1
    }
    
    # Fix hardcoded path to the executable loader
    sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
    
    # Cleanup
    cd "$LFS/sources"
    rm -rf glibc-2.38
    
    log "✅ Glibc built successfully"
}

# Test the toolchain
test_toolchain() {
    log "Testing cross-compilation toolchain..."
    
    # Test basic compilation
    echo 'int main(){}' | $LFS_TGT-gcc -xc -
    readelf -l a.out | grep ': /lib' || {
        log "ERROR: Toolchain test failed"
        exit 1
    }
    
    rm -f a.out
    log "✅ Toolchain test passed"
}

# Main execution
main() {
    log "Starting LFS cross-compilation toolchain build"
    
    # Validate sources are available
    for package in binutils-2.41.tar.xz gcc-13.2.0.tar.xz linux-6.6.8.tar.xz glibc-2.38.tar.xz; do
        if [[ ! -f "$package" ]]; then
            log "ERROR: Required source package not found: $package"
            log "Run download_lfs_sources.sh first"
            exit 1
        fi
    done
    
    # Build toolchain components in order
    build_binutils_cross
    build_gcc_cross
    build_linux_headers
    build_glibc
    
    # Test the completed toolchain
    test_toolchain
    
    log "✅ LFS cross-compilation toolchain completed successfully"
}

# Execute main function
main "$@"